extends Node
## Headless smoke-тест критериев приёмки этапов 1–3.6.
## Ввод игрока симулируется Input.action_press; крюк — через cursor_override.
## Каток берётся из дефолтов (56 x 26, R7); параметры сбрасываются для
## детерминизма. Камера движения — фиксированный yaw (WASD = мировые оси).

var _failures := 0
var _half_l := 28.0
var _half_w := 13.0
var _goal_x := 24.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = $Main
	var puck: RigidBody3D = main.get_node("Puck")
	var player: CharacterBody3D = main.get_node("Player")
	# Детерминизм: дефолтные параметры и перестройка катка под них.
	player.params.reset_to_defaults()
	main._rebuild_rink()
	player.params.camera_yaw_follow = false
	main.get_node("Cones").set_active(false)
	_half_l = player.params.rink_length / 2.0
	_half_w = player.params.rink_width / 2.0
	_goal_x = main.get_node("Rink").goal_line_x()
	await _wait(30)

	await _test_goal_trigger(main, puck)
	await _test_post_ricochet(puck)
	await _test_containment(puck)
	await _test_shot_series(main, puck)
	await _test_skating(main, puck)
	await _test_carve_accelerates(main, puck)
	await _test_camera_follow(main)
	await _test_stick(main, puck)
	await _test_arc_radius(main)
	await _test_sector_continuity(main)
	await _test_catch(main, puck)

	print("SMOKE RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, test_name: String, details: String) -> void:
	print("TEST ", test_name, ": ", "PASS " if ok else "FAIL ", details)
	if not ok:
		_failures += 1


func _escaped(p: Vector3) -> bool:
	return absf(p.x) > _half_l + 0.6 or absf(p.z) > _half_w + 0.6 or p.y < -0.5


# --- Этап 1 ---

func _test_goal_trigger(main: Node3D, puck: RigidBody3D) -> void:
	var before: int = main.score["right"]
	puck.reset_to(Vector3(0, 0.05, 0))
	await _wait(3)
	puck.apply_central_impulse(Vector3(1, 0, 0) * 35.0 * puck.mass)
	await _wait(220)
	_check(main.score["right"] > before, "goal_trigger", "score=%s" % [main.score])
	await _wait(60)


func _test_post_ricochet(puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 7.0, 0.05, 0))
	await _wait(3)
	var dir := (Vector3(_goal_x, 0.03, 0.915) - puck.global_position).normalized()
	puck.apply_central_impulse(dir * 40.0 * puck.mass)
	await _wait(120)
	var pos := puck.global_position
	var ok := pos.x < _goal_x - 0.5 and not _escaped(pos)
	_check(ok, "post_ricochet", "pos=%s speed=%.1f" % [pos, puck.linear_velocity.length()])


func _test_containment(puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(0, 0.05, 0))
	await _wait(3)
	puck.apply_central_impulse(Vector3(0.7, 0, 0.55).normalized() * 40.0 * puck.mass)
	for i in 500:
		await get_tree().physics_frame
		if _escaped(puck.global_position) or puck.global_position.y > 2.5:
			_check(false, "containment", "escaped to %s at tick %d" % [puck.global_position, i])
			return
	_check(true, "containment", "pos=%s" % puck.global_position)


func _test_shot_series(main: Node3D, puck: RigidBody3D) -> void:
	for shot in 30:
		main._respawn_puck()
		await _wait(3)
		main._shoot_at_nearest_goal()
		for i in 90:
			await get_tree().physics_frame
			if _escaped(puck.global_position):
				_check(false, "shot_series", "shot %d escaped to %s" % [shot, puck.global_position])
				return
	_check(true, "shot_series", "30 shots, score=%s" % [main.score])


# --- Этапы 2 и 3.5/3.6: модель "направление" ---

func _test_skating(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))  # шайбу — с дороги
	await _wait(10)

	# 1. Разгон с места до 95% максимума (камера фиксирована: D = wish +X).
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	var ticks := 0
	while player.velocity.length() < 0.95 * player.params.max_speed and ticks < 400:
		await get_tree().physics_frame
		ticks += 1
	var accel_time := ticks / 60.0
	_check(accel_time >= 2.0 and accel_time <= 4.0, "accel_time", "%.2f s" % accel_time)
	Input.action_release("turn_right")
	await _wait(60)

	# 2. Разворот корпуса на месте: быстрый, но с видимой инерцией; угловая
	#    скорость не превышает лимит (волчок невозможен).
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	await _wait(2)
	Input.action_press("turn_right")  # wish +X: 90° от корпуса
	var early_turn := 0.0
	var max_tick_rate := 0.0
	var prev_yaw := player.rotation.y
	for i in 60:
		await get_tree().physics_frame
		var step := absf(wrapf(player.rotation.y - prev_yaw, -PI, PI))
		max_tick_rate = maxf(max_tick_rate, rad_to_deg(step) * 60.0)
		prev_yaw = player.rotation.y
		if i == 5:
			early_turn = rad_to_deg(absf(wrapf(player.rotation.y, -PI, PI)))
	var forward := -player.global_transform.basis.z
	var final_err := rad_to_deg(forward.angle_to(Vector3(1, 0, 0)))
	Input.action_release("turn_right")
	_check(early_turn < 35.0, "facing_inertia", "%.0f deg за первые 0.1 s" % early_turn)
	_check(final_err < 30.0, "turn_in_place", "ошибка %.0f deg через 1 s" % final_err)
	_check(max_tick_rate < player.params.turn_rate_at_zero * 1.15, "no_spin_top",
			"пик %.0f deg/s" % max_tick_rate)

	# 3. Хоккейный стоп (S): с ~максимума остановка примерно за секунду.
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	await _wait(220)
	Input.action_release("turn_right")
	Input.action_press("move_back")
	ticks = 0
	while player.velocity.length() > 0.5 and ticks < 150:
		await get_tree().physics_frame
		ticks += 1
	Input.action_release("move_back")
	var stop_time := ticks / 60.0
	_check(stop_time > 0.2 and stop_time <= 1.6, "hockey_stop", "%.2f s" % stop_time)
	await _wait(10)

	# 4. Авто-пивот: разворот на 180° = юз до < 2.5 м/с + толчок обратно.
	_teleport(player, Vector3(-8, 0.1, -5), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	await _wait(200)
	Input.action_release("turn_right")
	Input.action_press("turn_left")  # wish -X: 180° -> пивот
	var min_speed := 100.0
	var recovered_vx := 0.0
	for i in 240:
		await get_tree().physics_frame
		min_speed = minf(min_speed, player.velocity.length())
		recovered_vx = player.velocity.x
	Input.action_release("turn_left")
	_check(min_speed < 2.5, "pivot_slows", "min %.2f м/с" % min_speed)
	_check(recovered_vx < -2.0, "pivot_recovers", "vx=%.2f м/с через 4 s" % recovered_vx)
	await _wait(20)

	# 5. Камера в fixed-режиме не вращается.
	var cam_ok := absf(camera.rotation.y) < 0.0001 and absf(camera.rotation.z) < 0.0001
	_check(cam_ok, "camera_fixed", "rot=%s" % camera.rotation)


func _test_carve_accelerates(main: Node3D, puck: RigidBody3D) -> void:
	# Плавная дуга с удержанием W РАЗГОНЯЕТ: скорость на выходе выше входной.
	var player: CharacterBody3D = main.get_node("Player")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(-6, 0.1, 0), -PI / 2.0)  # facing +X
	await _wait(2)
	# Разгон до ~середины, затем устойчивая резаная дуга (W + доворот).
	Input.action_press("turn_right")
	while player.velocity.length() < 5.0:
		await get_tree().physics_frame
	var entry_speed := player.velocity.length()
	Input.action_press("move_forward")  # W+D = дуга ~45°, carve
	for i in 150:
		await get_tree().physics_frame
	var exit_speed := player.velocity.length()
	Input.action_release("move_forward")
	Input.action_release("turn_right")
	_check(exit_speed > entry_speed + 0.3, "carve_accelerates",
			"%.1f -> %.1f м/с" % [entry_speed, exit_speed])
	await _wait(30)


func _test_camera_follow(main: Node3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	player.params.camera_yaw_follow = true
	_teleport(player, Vector3(-12, 0.1, 0), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	var max_yaw := 0.0
	var max_roll := 0.0
	for i in 150:
		await get_tree().physics_frame
		max_yaw = maxf(max_yaw, absf(camera.rotation.y))
		max_roll = maxf(max_roll, absf(camera.rotation.z))
	Input.action_release("turn_right")
	_check(max_yaw > deg_to_rad(30.0), "camera_follow_turns", "yaw до %.0f deg" % rad_to_deg(max_yaw))
	_check(max_roll < 0.001, "camera_horizon", "roll %.4f" % max_roll)
	player.params.camera_yaw_follow = false
	await _wait(60)


# --- Этапы 3 и 3.6: крюк, дуга, автоприём ---

func _test_stick(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params
	params.handedness_right = true

	# Игрок facing -Z в центре; крюк ходит по дуге радиусом stick_length.
	_teleport(player, Vector3(0, 0.1, 0), 0.0)
	var pivot := Vector3(0.22, 0, -0.15)  # для facing -Z, правый хват
	var puck_on_arc := pivot + Vector3(0, 0, -1) * params.stick_length  # азимут 0 (перед)

	# 1. Удар крюком в шайбу на дуге при быстром сметании мимо (не в цель):
	#    цель — за шайбой, крюк проходит через неё на скорости.
	puck.reset_to(Vector3(puck_on_arc.x, 0.05, puck_on_arc.z))
	blade.cursor_override = pivot + Vector3(0.866, 0, 0.5) * 1.5    # азимут ~+120
	await _wait(45)
	blade.cursor_override = pivot + Vector3(-0.866, 0, -0.5) * 3.0  # азимут ~-60 (мимо)
	var max_puck_speed := 0.0
	var min_y := 1.0
	for i in 60:
		await get_tree().physics_frame
		max_puck_speed = maxf(max_puck_speed, puck.linear_velocity.length())
		min_y = minf(min_y, puck.global_position.y)
	var speed_ok := max_puck_speed > 3.0 and max_puck_speed <= 1.35 * params.blade_max_speed
	_check(speed_ok, "blade_hit_speed",
			"puck %.1f м/с (лимит %.1f)" % [max_puck_speed, 1.35 * params.blade_max_speed])
	_check(min_y > -0.05, "puck_above_ice", "min_y=%.3f" % min_y)

	# 2. Шайба на 40 м/с не пролетает сквозь неподвижный крюк.
	blade.cursor_override = pivot + Vector3(0, 0, -1) * 2.0  # крюк спереди, азимут 0
	await _wait(40)
	puck.reset_to(Vector3(blade.global_position.x, 0.05, -6))
	await _wait(3)
	puck.apply_central_impulse(Vector3(0, 0, 40) * puck.mass)
	var max_z := -100.0
	for i in 40:
		await get_tree().physics_frame
		max_z = maxf(max_z, puck.global_position.z)
	_check(max_z < blade.global_position.z + 0.15, "puck_vs_blade_ccd", "max_z=%.2f" % max_z)

	# 3. Крюк у борта не выходит за коробку.
	_teleport(player, Vector3(-_half_l + 0.7, 0.1, 0), PI / 2.0)  # facing -X, вплотную к торцу
	blade.cursor_override = Vector3(-_half_l - 10.0, 0, 0)  # цель далеко за бортом
	await _wait(120)
	var bx := blade.global_position.x
	_check(bx > -_half_l and bx < -_half_l + 1.2, "blade_inside_boards", "x=%.2f (борт -%.1f)" % [bx, _half_l])
	blade.cursor_override = Vector3.INF


func _test_arc_radius(main: Node3D) -> void:
	# Крюк ходит строго по дуге: радиус ≈ stick_length ± reach_variation,
	# как бы далеко/близко ни ставился курсор.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), 0.0)
	blade.cursor_override = blade.pivot_point + Vector3(0, 0, -1) * 1.0
	await _wait(160)  # дать крюку доехать к дуге после прошлого теста
	var lo := params.stick_length - params.reach_variation - 0.05
	var hi := params.stick_length + params.reach_variation + 0.05
	var worst := ""
	# Курсор спереди на разной дистанции — радиус крюка обязан остаться у stick_length.
	for dist in [0.3, 1.0, 3.0, 8.0]:
		blade.cursor_override = blade.pivot_point + Vector3(0, 0, -1) * dist
		await _wait(40)
		var r: float = (blade.global_position - blade.pivot_point).length()
		if r < lo or r > hi:
			worst = "курсор %.1f м -> радиус %.2f (окно %.2f..%.2f)" % [dist, r, lo, hi]
	_check(worst == "", "arc_radius", worst if worst != "" else "радиус стабилен на 4 дистанциях")
	blade.cursor_override = Vector3.INF


func _test_sector_continuity(main: Node3D) -> void:
	# Из положения "за спиной со стороны хвата" цель на другом краю сектора:
	# крюк идёт ЧЕРЕЗ фронт, не перепрыгивая запретную зону за спиной.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params
	params.handedness_right = true
	_teleport(player, Vector3(0, 0.1, 0), 0.0)  # facing -Z
	blade.cursor_override = Vector3(0.8, 0, 2.5)  # позади-справа (форхенд ~+168°)
	await _wait(60)
	var start_az: float = blade.azimuth
	# Цель — передне-левый край (граница бэкхенда).
	blade.cursor_override = blade.pivot_point + Vector3(-0.866, 0, -0.5) * 2.0
	var passed_front := false
	var min_az := start_az
	var max_az := start_az
	var out_of_sector := false
	for i in 120:
		await get_tree().physics_frame
		var az: float = blade.azimuth
		min_az = minf(min_az, az)
		max_az = maxf(max_az, az)
		if absf(az) < 30.0:
			passed_front = true
		if az < params.backhand_limit - 1.0 or az > params.forehand_limit + 1.0:
			out_of_sector = true
	_check(start_az > 120.0, "continuity_setup", "старт азимут %.0f" % start_az)
	_check(passed_front and not out_of_sector, "sector_continuity",
			"прошёл фронт=%s, вне сектора=%s (az %.0f..%.0f)" % [passed_front, out_of_sector, min_az, max_az])
	blade.cursor_override = Vector3.INF


func _test_catch(main: Node3D, puck: RigidBody3D) -> void:
	# Автоприём: шайба 10 м/с в крюк гасится до < 1 м/с отн. скорости за < 0.4 с.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	blade.cursor_override = Vector3(0.22, 0, 2.0)  # крюк перед игроком
	await _wait(120)
	var bz := blade.global_position.z
	_check(bz > 3.0 and bz < 4.2, "catch_setup", "blade.z=%.2f" % bz)
	puck.reset_to(Vector3(blade.global_position.x, 0.05, 0.5))
	await _wait(3)
	puck.apply_central_impulse(Vector3(0, 0, 10) * puck.mass)
	var near_tick := -1
	var damped_tick := -1
	for i in 90:
		await get_tree().physics_frame
		var dist := (puck.global_position - blade.global_position).length()
		if near_tick < 0 and dist < 1.2:
			near_tick = i
		var rel: float = (puck.linear_velocity - blade.blade_velocity).length()
		if near_tick >= 0 and damped_tick < 0 and rel < 1.0:
			damped_tick = i
			break
	var caught := damped_tick >= 0 and (damped_tick - near_tick) <= 24
	_check(caught, "auto_catch", "гашение за %d тиков" % ((damped_tick - near_tick) if damped_tick >= 0 else -1))
	var vz := puck.linear_velocity.z
	_check(vz > -1.0 and puck.global_position.z < bz + 0.2, "catch_soft",
			"vz=%.2f pz=%.2f" % [vz, puck.global_position.z])
	blade.cursor_override = Vector3.INF


func _teleport(player: CharacterBody3D, pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
