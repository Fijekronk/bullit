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
	await _wait(30)

	await _test_goal_trigger(main, puck)
	await _test_post_ricochet(puck)
	await _test_containment(puck)
	await _test_shot_series(main, puck)
	await _test_skating(main, puck)
	await _test_stick(main, puck)

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


# --- Этап 2 ---

func _test_skating(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	puck.reset_to(Vector3(15, 0.05, 8))  # шайбу — с дороги
	await _wait(10)

	# 1. Разгон с места до 95% максимума за 2.5–3.5 с (допуск теста 2–4 с).
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)  # носом в +X
	await _wait(2)
	Input.action_press("move_forward")
	var ticks := 0
	while player.velocity.length() < 0.95 * player.params.max_speed and ticks < 400:
		await get_tree().physics_frame
		ticks += 1
	var accel_time := ticks / 60.0
	_check(accel_time >= 2.0 and accel_time <= 4.0, "accel_time", "%.2f s" % accel_time)

	# 2 и 3. Дуга на полной скорости: корпус поворачивает медленно (большой
	# радиус), velocity отстаёт от facing (проскальзывание).
	Input.action_press("turn_left")
	var yaw_total := 0.0
	var prev_yaw := player.rotation.y
	for i in 60:
		await get_tree().physics_frame
		yaw_total += wrapf(player.rotation.y - prev_yaw, -PI, PI)
		prev_yaw = player.rotation.y
	var hvel := Vector3(player.velocity.x, 0, player.velocity.z)
	var forward := -player.global_transform.basis.z
	var drift_deg := rad_to_deg(hvel.normalized().angle_to(forward))
	Input.action_release("turn_left")
	Input.action_release("move_forward")
	var turn_deg := rad_to_deg(yaw_total)
	_check(turn_deg > 100.0 and turn_deg < 260.0, "turn_at_speed", "%.0f deg/s" % turn_deg)
	_check(drift_deg > 5.0 and drift_deg < 60.0, "grip_drift", "%.1f deg" % drift_deg)

	# 2b. Разворот на месте — почти мгновенный.
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	await _wait(2)
	Input.action_press("turn_left")
	yaw_total = 0.0
	prev_yaw = player.rotation.y
	for i in 30:
		await get_tree().physics_frame
		yaw_total += wrapf(player.rotation.y - prev_yaw, -PI, PI)
		prev_yaw = player.rotation.y
	Input.action_release("turn_left")
	_check(rad_to_deg(yaw_total) > 150.0, "turn_in_place", "%.0f deg за 0.5 s" % rad_to_deg(yaw_total))

	# 4. Хоккейный стоп: с ~максимума остановка примерно за секунду.
	_teleport(player, Vector3(-15, 0.1, -5), -PI / 2.0)
	await _wait(2)
	Input.action_press("move_forward")
	await _wait(220)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	ticks = 0
	while player.velocity.length() > 0.5 and ticks < 150:
		await get_tree().physics_frame
		ticks += 1
	Input.action_release("move_back")
	var stop_time := ticks / 60.0
	_check(stop_time > 0.2 and stop_time <= 1.6, "hockey_stop", "%.2f s" % stop_time)
	await _wait(10)

	# 5. Езда назад: S с места разгоняет назад (velocity против facing).
	_teleport(player, Vector3(0, 0.1, 5), -PI / 2.0)
	await _wait(2)
	Input.action_press("move_back")
	await _wait(150)
	hvel = Vector3(player.velocity.x, 0, player.velocity.z)
	forward = -player.global_transform.basis.z
	var along := hvel.dot(forward)
	Input.action_release("move_back")
	_check(along < -2.0, "backward", "v_along=%.2f m/s" % along)

	# 6. Камера не вращается: yaw и roll — всегда нули.
	var cam_ok := absf(camera.rotation.y) < 0.0001 and absf(camera.rotation.z) < 0.0001
	_check(cam_ok, "camera_fixed", "rot=%s" % camera.rotation)


# --- Этап 3: крюк ---

func _test_stick(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var params: SkatingParams = player.params

	# 1. Удар крюком на максимальной скорости по лежащей шайбе:
	#    шайба получает не выше ~1.3 x blade_max_speed и не уходит под лёд.
	_teleport(player, Vector3(-1.2, 0.1, 0), -PI / 2.0)
	puck.reset_to(Vector3(0, 0.05, 0))
	blade.cursor_override = Vector3(-3.5, 0, 0)  # крюк — на дальний край кольца сзади
	await _wait(40)
	blade.cursor_override = Vector3(3.0, 0, 0)   # рывок через шайбу
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
	blade.cursor_override = Vector3(0, 0, 0)  # крюк в (0,0), длинной стороной поперёк X
	await _wait(40)
	puck.reset_to(Vector3(6, 0.05, 0))
	await _wait(3)
	puck.apply_central_impulse(Vector3(-40, 0, 0) * puck.mass)
	var min_x := 100.0
	for i in 40:
		await get_tree().physics_frame
		min_x = minf(min_x, puck.global_position.x)
	_check(min_x > -0.5, "puck_vs_blade_ccd", "min_x=%.2f" % min_x)

	# 3. Крюк не покидает каток при цели далеко за бортом: доезжает до стены
	#    (значит, действительно двигался) и останавливается у неё.
	_teleport(player, Vector3(-18.5, 0.1, 5), PI / 2.0)
	blade.cursor_override = Vector3(-30, 0, 5)
	await _wait(150)
	var bx := blade.global_position.x
	_check(bx > -20.0 and bx < -19.0, "blade_inside_boards", "x=%.2f" % bx)
	blade.cursor_override = Vector3.INF


func _teleport(player: CharacterBody3D, pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
