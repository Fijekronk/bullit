extends Node
## Headless smoke-тест. Этап 1: гол-триггер, рикошет от штанги, удержание
## шайбы в коробке. Этап 2: разгон, радиусы поворота, проскальзывание (grip),
## хоккейный стоп, езда назад, неподвижность осей камеры.

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = $Main
	var puck: RigidBody3D = main.get_node("Puck")
	main.get_node("Cones").set_active(false)  # конусы не должны мешать тестам
	# Для детерминизма ввода движение тестируем с фиксированной камерой
	# (WASD относительно yaw камеры); режим follow проверяется отдельно.
	var player: CharacterBody3D = main.get_node("Player")
	player.params.camera_yaw_follow = false
	await _wait(30)

	await _test_goal_trigger(main, puck)
	await _test_post_ricochet(puck)
	await _test_containment(puck)
	await _test_shot_series(main, puck)
	await _test_skating(main, puck)
	await _test_camera_follow(main)
	await _test_stick(main, puck)
	await _test_catch(main, puck)
	await _test_zone(main)

	print("SMOKE RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, test_name: String, details: String) -> void:
	print("TEST ", test_name, ": ", "PASS " if ok else "FAIL ", details)
	if not ok:
		_failures += 1


# --- Этап 1 ---

func _test_goal_trigger(main: Node3D, puck: RigidBody3D) -> void:
	var before: int = main.score["right"]
	puck.reset_to(Vector3(0, 0.05, 0))
	await _wait(3)
	puck.apply_central_impulse(Vector3(1, 0, 0) * 35.0 * puck.mass)
	await _wait(180)
	_check(main.score["right"] > before, "goal_trigger", "score=%s" % [main.score])
	await _wait(90)


func _test_post_ricochet(puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(10, 0.05, 0))
	await _wait(3)
	var dir := (Vector3(17, 0.03, 0.915) - puck.global_position).normalized()
	puck.apply_central_impulse(dir * 40.0 * puck.mass)
	await _wait(120)
	# После удара в штангу шайба должна отлететь, не застряв и не пройдя в ворота.
	var pos := puck.global_position
	var ok := pos.x < 16.5 and absf(pos.x) < 20.6 and absf(pos.z) < 10.6
	_check(ok, "post_ricochet", "pos=%s speed=%.1f" % [pos, puck.linear_velocity.length()])


func _test_containment(puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(0, 0.05, 0))
	await _wait(3)
	puck.apply_central_impulse(Vector3(0.7, 0, 0.55).normalized() * 40.0 * puck.mass)
	for i in 400:
		await get_tree().physics_frame
		var p := puck.global_position
		if absf(p.x) > 20.6 or absf(p.z) > 10.6 or p.y > 2.5 or p.y < -0.5:
			_check(false, "containment", "escaped to %s at tick %d" % [p, i])
			return
	_check(true, "containment", "pos=%s" % puck.global_position)


func _test_shot_series(main: Node3D, puck: RigidBody3D) -> void:
	var history: Array[String] = []
	for shot in 30:
		main._respawn_puck()
		await _wait(3)
		main._shoot_at_nearest_goal()
		for i in 90:
			await get_tree().physics_frame
			var p := puck.global_position
			history.append("t%d p=%v v=%v" % [i, p, puck.linear_velocity])
			while history.size() > 45:
				history.pop_front()
			if absf(p.x) > 20.6 or absf(p.z) > 10.6 or p.y < -0.5:
				_check(false, "shot_series", "shot %d escaped to %s" % [shot, p])
				print("    траектория перед вылетом:\n    ", "\n    ".join(history))
				return
	_check(true, "shot_series", "30 shots, score=%s" % [main.score])


# --- Этапы 2 и 3.5: модель "направление" ---

func _test_skating(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	puck.reset_to(Vector3(15, 0.05, 8))  # шайбу — с дороги
	await _wait(10)

	# 1. Разгон с места до 95% максимума (камера фиксирована: D = wish +X).
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)  # носом в +X
	await _wait(2)
	Input.action_press("turn_right")
	var ticks := 0
	while player.velocity.length() < 0.95 * player.params.max_speed and ticks < 400:
		await get_tree().physics_frame
		ticks += 1
	var accel_time := ticks / 60.0
	_check(accel_time >= 2.0 and accel_time <= 4.0, "accel_time", "%.2f s" % accel_time)

	# 2. Резаная дуга: D+W = wish 45° от velocity — дуга с умеренной потерей.
	var speed_before := player.velocity.length()
	Input.action_press("move_forward")
	await _wait(75)
	var hvel := Vector3(player.velocity.x, 0, player.velocity.z)
	var carve_turn := rad_to_deg(Vector3(1, 0, 0).angle_to(hvel.normalized()))
	var carve_speed := hvel.length()
	Input.action_release("move_forward")
	Input.action_release("turn_right")
	_check(carve_turn > 15.0, "carve_turns", "%.0f deg за 1.25 s" % carve_turn)
	_check(carve_speed > speed_before * 0.55, "carve_speed_kept",
			"%.1f -> %.1f м/с" % [speed_before, carve_speed])
	await _wait(30)

	# 3. Разворот корпуса на месте: быстрый, но с видимой инерцией,
	#    угловая скорость никогда не превышает лимит (волчок невозможен).
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	player.velocity = Vector3.ZERO
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
			early_turn = rad_to_deg(absf(wrapf(player.rotation.y - 0.0, -PI, PI)))
	var forward := -player.global_transform.basis.z
	var final_err := rad_to_deg(forward.angle_to(Vector3(1, 0, 0)))
	Input.action_release("turn_right")
	_check(early_turn < 35.0, "facing_inertia", "%.0f deg за первые 0.1 s" % early_turn)
	_check(final_err < 30.0, "turn_in_place", "ошибка %.0f deg через 1 s" % final_err)
	_check(max_tick_rate < player.params.turn_rate_at_zero * 1.15, "no_spin_top",
			"пик %.0f deg/s" % max_tick_rate)

	# 4. Хоккейный стоп (S): с ~максимума остановка примерно за секунду.
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

	# 5. Авто-пивот: разворот на 180° = юз до < 2.5 м/с + толчок обратно.
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	await _wait(200)
	Input.action_release("turn_right")
	Input.action_press("turn_left")  # wish -X: угол 180° -> пивот
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

	# 6. Камера в fixed-режиме не вращается.
	var cam_ok := absf(camera.rotation.y) < 0.0001 and absf(camera.rotation.z) < 0.0001
	_check(cam_ok, "camera_fixed", "rot=%s" % camera.rotation)


func _test_camera_follow(main: Node3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	player.params.camera_yaw_follow = true
	_teleport(player, Vector3(-12, 0.1, 0), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")  # разгоняемся; камера доворачивается
	var max_yaw := 0.0
	var max_roll := 0.0
	for i in 150:
		await get_tree().physics_frame
		max_yaw = maxf(max_yaw, absf(camera.rotation.y))
		max_roll = maxf(max_roll, absf(camera.rotation.z))
	Input.action_release("turn_right")
	_check(max_yaw > deg_to_rad(30.0), "camera_follow_turns",
			"yaw до %.0f deg" % rad_to_deg(max_yaw))
	_check(max_roll < 0.001, "camera_horizon", "roll %.4f" % max_roll)
	player.params.camera_yaw_follow = false
	await _wait(60)


# --- Этапы 3 и 3.5: крюк, зона, автоприём ---

func _test_stick(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params
	params.handedness_right = true

	# 1. Удар крюком на максимальной скорости по лежащей шайбе:
	#    шайба получает не выше ~1.3 x blade_max_speed и не уходит под лёд.
	#    Игрок носом в -Z, замах из-за спины со стороны хвата (+X).
	_teleport(player, Vector3(0, 0.1, 1.2), 0.0)
	puck.reset_to(Vector3(0, 0.05, 0))
	blade.cursor_override = Vector3(0.5, 0, 4.2)  # за спиной справа (форхенд)
	await _wait(40)
	blade.cursor_override = Vector3(0, 0, -3.0)   # рывок вперёд через шайбу
	var max_puck_speed := 0.0
	var min_y := 1.0
	for i in 60:
		await get_tree().physics_frame
		max_puck_speed = maxf(max_puck_speed, puck.linear_velocity.length())
		min_y = minf(min_y, puck.global_position.y)
	var speed_ok := max_puck_speed > 5.0 and max_puck_speed <= 1.3 * params.blade_max_speed
	_check(speed_ok, "blade_hit_speed",
			"puck %.1f м/с (лимит %.1f)" % [max_puck_speed, 1.3 * params.blade_max_speed])
	_check(min_y > -0.05, "puck_above_ice", "min_y=%.3f" % min_y)

	# 2. Шайба на 40 м/с не пролетает сквозь неподвижный крюк.
	#    Крюк остался у цели (0, 0, -0.35), длинной стороной поперёк Z.
	await _wait(30)
	puck.reset_to(Vector3(0, 0.05, -6))
	await _wait(3)
	puck.apply_central_impulse(Vector3(0, 0, 40) * puck.mass)
	var max_z := -100.0
	for i in 40:
		await get_tree().physics_frame
		max_z = maxf(max_z, puck.global_position.z)
	_check(max_z < -0.2, "puck_vs_blade_ccd", "max_z=%.2f" % max_z)

	# 3. Крюк не покидает каток при цели далеко за бортом: доезжает до стены
	#    (значит, действительно двигался) и останавливается у неё.
	_teleport(player, Vector3(-18.5, 0.1, 5), PI / 2.0)
	blade.cursor_override = Vector3(-30, 0, 5)
	await _wait(150)
	var bx := blade.global_position.x
	_check(bx > -20.0 and bx < -19.0, "blade_inside_boards", "x=%.2f" % bx)
	blade.cursor_override = Vector3.INF


func _test_catch(main: Node3D, puck: RigidBody3D) -> void:
	# Автоприём: шайба 10 м/с в зону крюка гасится до < 1 м/с относительной
	# скорости не дольше 0.4 с после входа в ближнюю зону, без отскока.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	blade.cursor_override = Vector3(0, 0, 3.0)  # крюк перед игроком, z=3.45
	await _wait(160)  # крюк мог остаться на другом конце катка
	var blade_in_place := (blade.global_position - Vector3(0, 0.05, 3.45)).length() < 0.15
	_check(blade_in_place, "catch_setup", "blade=%s" % blade.global_position)
	puck.reset_to(Vector3(0, 0.05, 0))
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
	_check(caught, "auto_catch", "гашение за %d тиков" % (damped_tick - near_tick if damped_tick >= 0 else -1))
	# Без отскока: шайба не улетела обратно и не проскочила крюк.
	var vz := puck.linear_velocity.z
	var pz := puck.global_position.z
	_check(vz > -1.0 and pz < 3.45, "catch_soft", "vz=%.2f pz=%.2f" % [vz, pz])
	blade.cursor_override = Vector3.INF


func _test_zone(main: Node3D) -> void:
	# Запретная зона: цель крюка никогда не выходит за границу сектора
	# (форхенд 200° со стороны хвата, бэкхенд 60° с укороченным радиусом).
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params
	params.handedness_right = true
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z, хват справа (+X)
	var worst := ""
	for i in 12:
		var azimuth := TAU * float(i) / 12.0
		blade.cursor_override = player.global_position \
				+ Vector3(sin(azimuth), 0, -cos(azimuth)) * 3.0
		await _wait(30)
		var offset: Vector3 = blade.target_point - player.global_position
		offset.y = 0.0
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		# e > 0 — сторона хвата (для правого хвата зеркалим знак).
		var e := -rad_to_deg(forward.normalized().signed_angle_to(offset.normalized(), Vector3.UP))
		var covered := (e >= -params.backhand_arc - 3.0 and e <= 3.0) \
				or (e >= -3.0 and e <= params.forehand_arc + 3.0) \
				or (params.forehand_arc > 180.0 and e <= params.forehand_arc - 360.0 + 3.0)
		var reach_limit: float = blade.zone_reach(e, params)
		if not covered or offset.length() > reach_limit + 0.05:
			worst = "азимут %d: e=%.0f r=%.2f (лимит %.2f)" % [i * 30, e, offset.length(), reach_limit]
	_check(worst == "", "zone_boundary", worst if worst != "" else "12 азимутов в секторе")
	blade.cursor_override = Vector3.INF


func _teleport(player: CharacterBody3D, pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
