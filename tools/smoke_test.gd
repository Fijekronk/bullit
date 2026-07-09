extends Node
## Headless smoke-тест. Этап 1 (физика шайбы/ворот) — без изменений.
## Движение 2.0 / Управление 3.0 + патчи (профили, рывок, carry, перекладка):
## квадратичный юз, резкий стоп 180°, разгон в дуге, рывок, скольжение (Alt),
## carry шайбы (не теряется), авто-перекладка (5 vs 10 м/с), жёсткость/хват клюшки.

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
	player.params.reset_to_defaults()
	main._rebuild_rink()
	main.get_node("Cones").set_active(false)
	_half_l = player.params.rink_length / 2.0
	_half_w = player.params.rink_width / 2.0
	_goal_x = main.get_node("Rink").goal_line_x()
	await _wait(30)

	await _test_goal_trigger(main, puck)
	await _test_containment(puck)
	await _test_shot_series(main, puck)
	await _test_quadratic_braking(main, puck)
	await _test_quick_stop_180(main, puck)
	await _test_carve_accelerates(main, puck)
	await _test_dash(main, puck)
	await _test_sprint_stamina(main, puck)
	await _test_dash_gate(main, puck)
	await _test_qe_context(main, puck)
	await _test_poke_honest(main, puck)
	await _test_backward_skating(main, puck)
	await _test_backpedal_s(main, puck)
	await _test_glide(main, puck)
	await _test_camera_stance_stable(main)
	await _test_stick_rigid(main, puck)
	await _test_stick_bend_handedness(main)
	await _test_carry_never_lost(main, puck)
	await _test_pivot_transfer(main, puck)
	await _test_carry_jitter(main, puck)
	await _test_flip_up(main, puck)
	await _test_poses(main, puck)
	await _test_stick_orientation(main)
	await _test_feint_mapping(main, puck)
	await _test_dribble_hold(main, puck)
	await _test_stance_steering(main, puck)
	await _test_q_fake(main, puck)
	await _test_triangle(main, puck)
	await _test_wide_spam(main, puck)
	await _test_flip_side_rule(main, puck)
	await _test_skate_feint(main, puck)
	await _test_juggle_timing(main, puck)
	await _test_air_slam(main, puck)
	await _test_hit_running(main, puck)
	await _test_hit_standing(main, puck)
	await _test_shielding(main, puck)
	await _test_defender_poke(main, puck)
	await _test_board_dribble(main, puck)
	await _test_pose_fuzz(main, puck)
	await _test_wrist_shot(main, puck)
	await _test_shot_aim_from_puck(main, puck)
	await _test_params_persist(main)
	await _test_body_lean(main, puck)
	await _test_slap_shot(main, puck)
	await _test_whiff(main, puck)
	await _test_bank_reflection(puck)
	await _test_reverse_stop(main, puck)
	await _test_reverse_diagonal(main, puck)
	await _test_glide_steer(main, puck)
	await _test_arena_ceiling(main, puck)
	await _test_goalie(main, puck)

	print("SMOKE RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, name: String, details: String) -> void:
	print("TEST ", name, ": ", "PASS " if ok else "FAIL ", details)
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
	_check(true, "shot_series", "30 shots ok")


# --- Движение ---

func _brake_distance(player: CharacterBody3D, v: float) -> float:
	_teleport(player, Vector3(-_half_l + 5.0, 0.1, 0), -PI / 2.0)
	player.velocity = Vector3(v, 0, 0)
	await _wait(1)
	Input.action_press("move_back")
	var dist := 0.0
	var prev := player.global_position
	for i in 240:
		await get_tree().physics_frame
		dist += (player.global_position - prev).length()
		prev = player.global_position
		if player.velocity.length() < 0.3:
			break
	Input.action_release("move_back")
	await _wait(20)
	return dist


func _test_quadratic_braking(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	var d_fast: float = await _brake_distance(player, 9.0)
	var d_slow: float = await _brake_distance(player, 4.5)
	var ratio := d_fast / maxf(d_slow, 0.01)
	_check(ratio >= 3.0 and ratio <= 4.5, "quadratic_braking",
			"%.2f / %.2f = %.2fx" % [d_fast, d_slow, ratio])


func _test_quick_stop_180(main: Node3D, puck: RigidBody3D) -> void:
	# Разворот 180° на максимальной скорости (профиль бег): 0.4–0.6 с.
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	_teleport(player, Vector3(-6, 0.1, 0), -PI / 2.0)  # facing +X
	player.velocity = Vector3(9, 0, 0)
	await _wait(1)
	Input.action_press("turn_left")  # wish -X (разворот 180°)
	var t := -1
	for i in 90:
		await get_tree().physics_frame
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		# «Разворот»: корпус развернулся к -X и игрок снова поехал.
		if fwd.normalized().dot(Vector3(-1, 0, 0)) > 0.7 and player.velocity.length() > 1.5:
			t = i
			break
	Input.action_release("turn_left")
	var secs := (t + 1) / 60.0 if t >= 0 else 99.0
	_check(t >= 0 and secs >= 0.35 and secs <= 0.65, "quick_stop_180", "%.2f с" % secs)
	await _wait(20)


func _test_carve_accelerates(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	_teleport(player, Vector3(-6, 0.1, 0), -PI / 2.0)
	await _wait(2)
	Input.action_press("turn_right")
	while player.velocity.length() < 5.0:
		await get_tree().physics_frame
	var entry := player.velocity.length()
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
	var exit_speed := player.velocity.length()
	Input.action_release("move_forward")
	Input.action_release("turn_right")
	_check(exit_speed > entry + 0.3, "carve_accelerates", "%.1f -> %.1f м/с" % [entry, exit_speed])
	await _wait(20)


## Двойной Shift (рывок): два нажатия sprint в окне DOUBLE_TAP_WINDOW.
func _double_tap_sprint() -> void:
	Input.action_press("sprint")
	await _wait(1)
	Input.action_release("sprint")
	await _wait(1)
	Input.action_press("sprint")
	await _wait(1)
	Input.action_release("sprint")


func _test_dash(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), -PI / 2.0)  # facing +X
	player.velocity = Vector3(4, 0, 0)
	player.stamina = p.sprint_max
	await _wait(2)
	var before := player.velocity.length()
	await _double_tap_sprint()  # рывок = двойной Shift
	await _wait(2)
	var after := player.velocity.length()
	var gain := after - before
	_check(absf(gain - p.dash_impulse) <= p.dash_impulse * 0.2, "dash_impulse",
			"+%.2f (ожидание %.2f)" % [gain, p.dash_impulse])
	# Бак опустошён рывком → повторный рывок не срабатывает.
	var s1 := player.velocity.length()
	await _double_tap_sprint()
	await _wait(2)
	_check(player.velocity.length() <= s1 + 0.3, "dash_cooldown", "повтор не сработал (бак пуст)")
	_check(player.stamina < 0.2, "dash_drains_stamina", "стамина после рывка %.2f" % player.stamina)
	await _wait(20)


## Спринт: расход бака ~1 с/с при удержании, восстановление ~sprint_max/regen
## в покое; во время спринта потолок скорости выше обычного.
func _test_sprint_stamina(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	var p: SkatingParams = player.params
	camera.yaw = 0.0
	player.stamina = p.sprint_max  # полный бак
	_teleport(player, Vector3(-_half_l + 6.0, 0.1, 0), 0.0)  # facing -Z
	player.velocity = Vector3(0, 0, -p.max_speed)  # уже на обычном пределе
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var s0: float = player.stamina
	var top := 0.0
	for i in 60:  # 1 с спринта
		await get_tree().physics_frame
		top = maxf(top, player.velocity.length())
	Input.action_release("sprint")
	var drained: float = s0 - player.stamina
	var s1: float = player.stamina
	for i in 60:  # 1 с восстановления (обычный бег)
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var regen: float = player.stamina - s1
	var regen_expect: float = p.sprint_max / p.stamina_regen_time
	_check(absf(drained - 1.0) < 0.15, "sprint_drain", "расход за 1 с = %.2f" % drained)
	_check(absf(regen - regen_expect) < 0.15, "sprint_regen",
			"восстановление за 1 с = %.2f (ожид. %.2f)" % [regen, regen_expect])
	_check(top > p.max_speed + 0.5, "sprint_speed",
			"пик %.1f м/с (обычный предел %.1f)" % [top, p.max_speed])
	await _wait(20)


## Рывок гейтится ПОЛНЫМ баком: на частичном не срабатывает.
func _test_dash_gate(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), -PI / 2.0)
	player.velocity = Vector3(4, 0, 0)
	player.stamina = p.sprint_max * 0.6  # частичный бак
	await _wait(1)
	var before := player.velocity.length()
	await _double_tap_sprint()
	await _wait(2)
	_check(player.velocity.length() <= before + 0.3, "dash_gate_partial",
			"рывок на неполном баке не сработал (%.1f -> %.1f)" % [before, player.velocity.length()])
	player.stamina = p.sprint_max
	await _wait(20)


## Q/E контекстны: без шайбы вне стойки Q = силовой (сносит манекен после
## телеграфа), E = отбор (выбивает свободную шайбу вперёд); в стойке — фейки.
func _test_qe_context(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	var defender_script := load("res://scripts/defender.gd")
	camera.yaw = 0.0
	# --- Q-силовой по манекену ---
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))  # шайба в сторонке
	_teleport(player, Vector3(0, 0.1, -5), 0.0)  # facing -Z, без шайбы
	var d: AnimatableBody3D = defender_script.new()
	main.add_child(d)
	d.setup(defender_script.STATIC, Vector3(0.0, 0.0, -5.9), player, blade, puck, player.params)
	await _wait(3)
	player.velocity = Vector3(0, 0, -3)  # набегаю
	Input.action_press("feint_left")  # Q
	await _wait(2)
	Input.action_release("feint_left")
	var mode: String = blade.qe_mode
	var d_start: Vector3 = d.global_position
	await _wait(20)  # телеграф 0.15 с + удар
	var d_moved: float = (d.global_position - d_start).length()
	d.queue_free()
	_check(mode.contains("силовой") and d_moved > 0.3, "q_body_check",
			"режим=%s, манекен сдвинут %.2f м" % [mode, d_moved])
	await _wait(10)
	# --- E-отбор свободной шайбы (телеграф poke_windup + окно контакта) ---
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	puck.reset_to(Vector3(0, 0.05, 4.0))  # свободная шайба в 1 м перед игроком
	await _wait(5)
	Input.action_press("feint_right")  # E
	await _wait(2)
	Input.action_release("feint_right")
	await _wait(28)  # телеграф + окно контакта
	var pv := Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).length()
	_check(pv > 2.0, "e_poke_free_puck", "шайба выбита, %.1f м/с (%s)" % [pv, blade.last_gesture])
	# --- в стойке Q = фейк ---
	await _wait(30)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(2)
	Input.action_press("feint_left")
	await _wait(2)
	Input.action_release("feint_left")
	var got: String = blade.last_gesture
	Input.action_release("stance")
	_check(grabbed and got.contains("фейк"), "qe_stance_fake", "жест=%s" % got)
	await _wait(20)


## Честный отбор: шайба ВНЕ конуса (сбоку/сзади) — выпад не достаёт, промах
## наказывается полным кулдауном. Есть видимый телеграф (poke_active).
func _test_poke_honest(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	var p: SkatingParams = player.params
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	# Сбросить возможный CARRIED из прошлого теста: увести шайбу далеко, дать
	# carry разорваться, затем поставить СБОКУ (+X) — вне конуса выпада (-Z).
	puck.reset_to(Vector3(8.0, 0.05, 5.0))
	for i in 20:
		await get_tree().physics_frame
		if blade.puck_state == 0:
			break
	puck.reset_to(Vector3(1.0, 0.05, 5.0))
	puck.linear_velocity = Vector3.ZERO
	await _wait(3)
	Input.action_press("feint_right")
	await _wait(2)
	Input.action_release("feint_right")
	var saw_telegraph := false
	for i in 10:
		await get_tree().physics_frame
		if blade.poke_active:
			saw_telegraph = true
	await _wait(20)
	var pv_side := Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).length()
	# Промах → кулдаун активен: сразу повторный выпад не запускается.
	Input.action_press("feint_right")
	await _wait(2)
	Input.action_release("feint_right")
	await _wait(2)
	var blocked_by_cd: bool = not blade.poke_active and blade.last_gesture.contains("мимо")
	_check(saw_telegraph, "poke_telegraph_visible", "телеграф виден=%s" % saw_telegraph)
	_check(pv_side < 1.0, "poke_out_of_cone", "шайба сбоку не тронута (%.1f м/с)" % pv_side)
	_check(blocked_by_cd, "poke_miss_cooldown", "промах держит кулдаун (%s)" % blade.last_gesture)
	await _wait(int(p.poke_cooldown * 60.0) + 10)


## Езда спиной = пивот в СКОЛЬЖЕНИИ (Alt + назад): корпус разворачивается
## против движения, скорость сохраняется (только трение вдоль).
func _test_backward_skating(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(-12, 0.1, 0), -PI / 2.0)  # facing +X
	player.velocity = Vector3(7, 0, 0)  # едем +X
	Input.action_press("profile_glide")  # Alt — скольжение
	Input.action_press("move_back")      # назад = пивот на спину
	var s0 := player.velocity.length()
	for i in 60:
		await get_tree().physics_frame
		player.velocity.x = maxf(player.velocity.x, 0.1)  # держим движение +X
	var backward: bool = player.is_backward
	var fwd: Vector3 = -player.global_transform.basis.z
	var facing_back: bool = fwd.x < -0.3  # корпус смотрит против +X
	var s1 := player.velocity.length()
	Input.action_release("move_back")
	Input.action_release("profile_glide")
	_check(backward and facing_back, "backward_facing",
			"спиной=%s, forward.x=%.2f (<-0.3)" % [backward, fwd.x])
	_check(s1 > s0 * 0.6, "backward_speed_kept",
			"скорость %.1f -> %.1f (сохранена)" % [s0, s1])
	await _wait(20)


## Бэкпедал: просто S (без Alt) — почти остановившись, едем назад лицом
## вперёд (реверс-тяга), facing НЕ разворачивается.
func _test_backpedal_s(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(0, 0.1, 0), 0.0)  # facing -Z, стоим
	var fwd0: Vector3 = -player.global_transform.basis.z
	Input.action_press("move_back")  # просто S
	for i in 50:
		await get_tree().physics_frame
	var v := player.velocity
	Input.action_release("move_back")
	# Едем назад = вдоль -forward (то есть +Z, т.к. forward=-Z), facing тот же.
	var along: float = v.dot(fwd0)
	var fwd1: Vector3 = -player.global_transform.basis.z
	var kept_facing: bool = fwd1.dot(fwd0) > 0.9
	_check(player.is_backward and along < -0.5, "backpedal_moves_back",
			"ход вдоль facing=%.2f (<0 = назад)" % along)
	_check(kept_facing, "backpedal_keeps_facing", "facing сохранён (dot=%.2f)" % fwd1.dot(fwd0))
	await _wait(20)


func _test_glide(main: Node3D, puck: RigidBody3D) -> void:
	# Скольжение (Alt): тяга off (не разогнаться), скорость сохраняется при довороте.
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	_teleport(player, Vector3(0, 0.1, 0), -PI / 2.0)  # facing +X
	player.velocity = Vector3(6, 0, 0)
	await _wait(1)
	Input.action_press("profile_glide")
	Input.action_press("move_forward")  # W — тяги в glide нет
	var start := player.velocity.length()
	var mx := start
	for i in 60:
		await get_tree().physics_frame
		mx = maxf(mx, player.velocity.length())
	Input.action_release("move_forward")
	Input.action_release("profile_glide")
	_check(mx <= start + 0.2, "glide_no_thrust", "%.1f -> макс %.1f м/с" % [start, mx])
	_check(player.velocity.length() > start * 0.7, "glide_preserve",
			"скорость сохранена %.1f м/с" % player.velocity.length())
	await _wait(20)


func _test_camera_stance_stable(main: Node3D) -> void:
	# Финты 2.0: мышь = камера ВСЕГДА. В стойке движение мыши вращает yaw,
	# pitch статичный (= params.camera_pitch), roll нулевой.
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	_teleport(player, Vector3(0, 0.1, 0), -PI / 2.0)
	camera.yaw = 0.0
	Input.action_press("stance")
	await _wait(3)
	var yaw0: float = camera.yaw
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(120.0, 0.0)
	camera._unhandled_input(ev)
	await _wait(3)
	Input.action_release("stance")
	_check(absf(camera.yaw - yaw0) > 0.01, "camera_stance_mouse",
			"yaw сдвиг %.3f (мышь должна вращать камеру в стойке)" % absf(camera.yaw - yaw0))
	_check(absf(camera.pitch - player.params.camera_pitch) < 0.01
			and absf(camera.rotation.z) < 0.001, "camera_pitch_static",
			"pitch=%.1f (парам %.1f), roll %.4f" % [camera.pitch, player.params.camera_pitch, camera.rotation.z])
	camera.yaw = 0.0
	await _wait(20)


# --- Клюшка ---

func _test_stick_rigid(main: Node3D, puck: RigidBody3D) -> void:
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), 0.0)
	blade.forced_azimuth = 0.0
	await _wait(120)
	var worst := 0.0
	for t in [200.0, -60.0, 180.0, 0.0, -55.0, 150.0, 40.0, -60.0, 199.0]:
		blade.forced_azimuth = t
		for i in 18:
			await get_tree().physics_frame
			worst = maxf(worst, absf((blade.global_position - blade.pivot_point).length() - p.stick_length))
	blade.forced_azimuth = INF
	_check(worst <= 0.01, "stick_rigid", "макс отклонение радиуса %.3f м" % worst)
	await _wait(10)


func _test_stick_bend_handedness(main: Node3D) -> void:
	# Изгиб крюка должен смотреть в сторону хвата при ОБОИХ хватах.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), 0.0)
	var ok := true
	var detail := ""
	for right in [true, false]:
		p.handedness_right = right
		await _wait(40)
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		var hand: Vector3 = blade._hand_side(forward.normalized(), p)
		var d: float = blade.bend_dir.dot(hand)
		detail += "%s:%.2f " % ["R" if right else "L", d]
		if d <= 0.0:
			ok = false
	p.handedness_right = true
	_check(ok, "stick_bend_handedness", detail)
	await _wait(20)


# --- Шайба: carry / перекладка ---

func _grab(player: CharacterBody3D, blade: AnimatableBody3D, puck: RigidBody3D) -> bool:
	# Отменить возможный отложенный гол-респаун из прошлого теста (иначе шайба
	# телепортируется в центр посреди этого теста).
	($Main as Node).set("_respawn_ticks", -1)
	# Поставить шайбу на carry-точку и дождаться CARRIED.
	await _wait(20)
	puck.reset_to(Vector3(blade.carry_point.x, 0.05, blade.carry_point.z))
	for i in 30:
		await get_tree().physics_frame
		if blade.puck_state == 1:  # CARRIED
			# Отменить гол-респаун, если гол забился свободной шайбой в ожидании.
			($Main as Node).set("_respawn_ticks", -1)
			return true
	($Main as Node).set("_respawn_ticks", -1)
	return false


func _test_carry_never_lost(main: Node3D, puck: RigidBody3D) -> void:
	# Слалом + развороты + рывок с шайбой — контроль не теряется.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	# Старт из центра вдоль длинной оси (+X): места хватает, в борт не упрёмся.
	_teleport(player, Vector3(-10, 0.1, 0), -PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	_check(grabbed, "carry_grab", "взята под контроль=%s" % grabbed)
	# Связка: ход вперёд + мягкие carve-дуги (без реверса) + рывок по ходу.
	var lost := false
	var why := ""
	Input.action_press("move_forward")
	var seq := [["", 35], ["turn_left", 12], ["", 15], ["turn_right", 12], ["", 15],
			["turn_left", 10], ["", 20], ["dash", 4], ["", 25]]
	for step in seq:
		if step[0] != "":
			Input.action_press(step[0])
		for i in int(step[1]):
			await get_tree().physics_frame
			if blade.puck_state == 0 and not lost:
				lost = true
				why = "@%s (%s) v=%.1f" % [blade.last_transition, step[0],
						Vector3(player.velocity.x, 0, player.velocity.z).length()]
		if step[0] != "" and step[0] != "dash":
			Input.action_release(step[0])
		if step[0] == "dash":
			Input.action_release("dash")
		if lost:
			break
	Input.action_release("move_forward")
	_check(not lost, "carry_never_lost", "состояние=%s %s" % [blade.puck_state_name, why])
	await _wait(20)


func _pivot_once(player: CharacterBody3D, blade: AnimatableBody3D, puck: RigidBody3D, v: float) -> bool:
	_teleport(player, Vector3(0, 0.1, 0), -PI / 2.0)  # facing +X
	var grabbed: bool = await _grab(player, blade, puck)
	if not grabbed:
		return false
	player.velocity = Vector3(v, 0, 0)
	Input.action_press("turn_left")  # wish -X: разворот -> перекладка
	var controlled := false
	for i in 70:
		await get_tree().physics_frame
		# «Выход из юза»: velocity развернулась к -X.
		var hv := Vector3(player.velocity.x, 0, player.velocity.z)
		if hv.length() > 1.0 and hv.normalized().dot(Vector3(-1, 0, 0)) > 0.3:
			controlled = blade.puck_state == 1
			break
	Input.action_release("turn_left")
	await _wait(15)
	return controlled


func _test_pivot_transfer(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	# 5 м/с — перекладка надёжна.
	var ok5: bool = await _pivot_once(player, blade, puck, 5.0)
	_check(ok5, "pivot_transfer_5ms", "контроль на выходе=%s" % ok5)
	# 10 м/с — честный срыв в большинстве прогонов (>50%).
	var lost := 0
	for r in 6:
		var held: bool = await _pivot_once(player, blade, puck, 10.0)
		if not held:
			lost += 1
	_check(lost >= 3, "pivot_transfer_10ms_loss", "срывов %d/6 (нужно >=3)" % lost)
	await _wait(10)


# --- Раздел 1–3: развязка carry, подброс, позы, ориентация ---

func _test_carry_jitter(main: Node3D, puck: RigidBody3D) -> void:
	# Ведение ровное: σ отклонения шайбы от carry-точки < 2 см, без дрожи.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(-10, 0.1, 0), -PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("move_forward")
	for i in 40:
		await get_tree().physics_frame
	# Дрожь = высокочастотные знакопеременные скачки: меряем изменение отклонения
	# от кадра к кадру (гладкий трейлинг на скорости — это НЕ дрожь). Отдельно
	# фиксируем средний трейлинг (≈ один кадр движения) для ручной оценки.
	var samples: Array[float] = []
	var prev: float = (blade.carry_point - puck.global_position).length()
	var mean := 0.0
	var count := 0
	var seq := [["", 20], ["turn_left", 12], ["", 15], ["turn_right", 12], ["", 20]]
	for step in seq:
		if step[0] != "":
			Input.action_press(step[0])
		for i in int(step[1]):
			await get_tree().physics_frame
			var d: float = (blade.carry_point - puck.global_position).length()
			samples.append(absf(d - prev))  # покадровое изменение (дрожь)
			prev = d
			mean += d
			count += 1
		if step[0] != "":
			Input.action_release(step[0])
	Input.action_release("move_forward")
	mean /= maxf(count, 1)
	var jitter := 0.0
	for s in samples:
		jitter = maxf(jitter, s)  # максимальный покадровый скачок
	# Порог 3 см/кадр: реальная дрожь (осцилляции старого PD) была бы 5+ см;
	# скачок на смене направления слалома — допустим.
	_check(grabbed and jitter < 0.03, "carry_jitter",
			"макс. покадровый скачок=%.3f м, трейлинг≈%.3f м" % [jitter, mean])
	await _wait(20)


func _test_flip_up(main: Node3D, puck: RigidBody3D) -> void:
	# Подброс: апекс 0.35–0.6 м, приземление в радиусе 1 м от игрока на ходу.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(-6, 0.1, 0), -PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	player.velocity = Vector3(4, 0, 0)
	Input.action_press("stance")
	await _wait(3)
	Input.action_press("gesture_lift")
	await _wait(1)
	Input.action_release("gesture_lift")
	var apex := 0.0
	var land_dist := -1.0
	for i in 120:
		await get_tree().physics_frame
		apex = maxf(apex, puck.global_position.y)
		if i > 15 and puck.global_position.y < 0.05 and land_dist < 0.0:
			var d := puck.global_position - player.global_position
			d.y = 0.0
			land_dist = d.length()
			break
	Input.action_release("stance")
	_check(grabbed and apex >= 0.6 and apex <= 0.95, "flip_up_apex", "апекс %.2f м" % apex)
	# Горизонталь = скорость игрока: шайба летит С ним и садится у крюка (~1.5 м).
	_check(land_dist >= 0.0 and land_dist < 1.9, "flip_up_land", "приземление %.2f м от игрока" % land_dist)
	await _wait(20)


func _test_poses(main: Node3D, puck: RigidBody3D) -> void:
	# ЛКМ/ПКМ в стойке — позы L/R; шайба в CARRIED всё время перехода.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(-8, 0.1, 0), -PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	Input.action_press("move_forward")
	await _wait(20)
	var lost := false
	var why := ""
	# Поза L (ЛКМ).
	Input.action_press("gesture_primary")
	await _wait(1)
	Input.action_release("gesture_primary")
	for i in 30:
		await get_tree().physics_frame
		if blade.puck_state != 1 and not lost:
			lost = true
			why = "L@%s" % blade.last_transition
	var pose_l: int = blade.pose
	# Поза R (ПКМ).
	Input.action_press("gesture_secondary")
	await _wait(1)
	Input.action_release("gesture_secondary")
	for i in 30:
		await get_tree().physics_frame
		if blade.puck_state != 1:
			lost = true
	var pose_r: int = blade.pose
	Input.action_release("move_forward")
	Input.action_release("stance")
	_check(grabbed and not lost, "poses_no_loss", "потеря=%s %s" % [lost, why])
	_check(pose_l == -1 and pose_r == 1, "poses_switch", "L=%d R=%d" % [pose_l, pose_r])
	await _wait(20)


func _test_stick_orientation(main: Node3D) -> void:
	# Перо у льда (min.y ~ 0), верх шафта У РУК ИГРОКА (якорь) — оба хвата.
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 0), 0.0)
	var detail := ""
	var ok := true
	for right in [true, false]:
		p.handedness_right = right
		await _wait(40)
		var box: AABB = blade.stick_world_aabb()
		var miny := box.position.y
		var maxy := box.position.y + box.size.y
		# Верхний торец шафта обязан быть у точки рук (не летать рядом).
		var top_expected := player.global_position + Vector3(0, 1.0, 0)
		var top_pt: Vector3 = box.get_center()
		top_pt.y = maxy
		var top_dist_h := Vector2(top_pt.x - top_expected.x, top_pt.z - top_expected.z).length()
		detail += "%s:[%.2f..%.2f] верх↔руки %.2f м; " % ["R" if right else "L", miny, maxy, top_dist_h]
		if miny < -0.08 or miny > 0.1 or absf(maxy - 1.0) > 0.25 or top_dist_h > 0.9:
			ok = false
	p.handedness_right = true
	_check(ok, "stick_orientation", detail)
	await _wait(20)


# --- Финты 2.0: кнопка + направление WASD ---

## Маппинг: L нейтраль = перевод L, R нейтраль = перевод R,
## L+бок = широкий перевод + juke-импульс корпуса вбок.
func _test_feint_mapping(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z (по камере)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	# L без направления -> поза L.
	Input.action_press("gesture_primary")
	await _wait(1)
	Input.action_release("gesture_primary")
	await _wait(15)
	var pose_l: int = blade.pose
	# R без направления -> поза R.
	Input.action_press("gesture_secondary")
	await _wait(1)
	Input.action_release("gesture_secondary")
	await _wait(30)  # > 0.35 с — дабл-тап-таймер L истекает
	var pose_r: int = blade.pose
	Input.action_release("stance")
	_check(grabbed and pose_l == -1 and pose_r == 1, "feint_mapping_poses",
			"L=%d R=%d" % [pose_l, pose_r])
	await _wait(20)


## Широкий дриблинг = УДЕРЖАНИЕ (ширина растёт по времени), WASD не влияет.
## Тап = узкая поза; долгое удержание = широкая (до wide_pose_angle), на
## отпускании — боковой шаг (juke). Корпус не разворачивается.
func _test_dribble_hold(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	var p: SkatingParams = player.params
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	# Тап ЛКМ: узкая поза (маленький |azimuth|).
	Input.action_press("gesture_primary")
	await _wait(2)
	Input.action_release("gesture_primary")
	await _wait(3)
	var az_tap: float = absf(blade.azimuth)
	await _wait(15)
	# Удержание ЛКМ на hold_max: ширина растёт к 1.0, azimuth к wide_pose_angle.
	Input.action_press("gesture_primary")
	var hold_frames := int(p.hold_max * 60.0) + 8
	for i in hold_frames:
		await get_tree().physics_frame
	var width_held: float = blade.dribble_width
	var az_hold: float = absf(blade.azimuth)
	player.velocity = Vector3.ZERO
	Input.action_release("gesture_primary")
	# Пик бокового шага сразу после отпускания (лезвие быстро гасит поперечную).
	var juke_speed := 0.0
	for i in 4:
		await get_tree().physics_frame
		juke_speed = maxf(juke_speed, Vector3(player.velocity.x, 0, player.velocity.z).length())
	Input.action_release("stance")
	_check(grabbed and width_held > 0.9, "dribble_hold_width",
			"ширина по удержанию = %.2f (>0.9)" % width_held)
	_check(az_hold > az_tap + 10.0 and az_hold > p.wide_pose_angle - 12.0, "dribble_hold_wider",
			"тап |θ|=%.0f°, удержание |θ|=%.0f° (широкая %.0f°)" % [az_tap, az_hold, p.wide_pose_angle])
	_check(juke_speed > p.juke_impulse * 0.5, "dribble_hold_juke",
			"боковой шаг на отпускании %.2f м/с" % juke_speed)
	await _wait(20)


## Руление в стойке РАБОТАЕТ: удержание WASD-стороны поворачивает корпус
## (дриблинг не блокирует поворот — прошлый баг).
func _test_stance_steering(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	var yaw0: float = player.rotation.y
	Input.action_press("turn_right")  # руль вбок
	for i in 40:
		await get_tree().physics_frame
	var dev: float = absf(wrapf(player.rotation.y - yaw0, -PI, PI))
	Input.action_release("turn_right")
	Input.action_release("stance")
	_check(grabbed and rad_to_deg(dev) > 20.0, "stance_steering",
			"корпус повернулся на %.0f° (руление в стойке работает)" % rad_to_deg(dev))
	await _wait(20)


## Q = фейк влево, E = фейк вправо (раздельные стороны, без мыши и WASD).
## Дабл-тап той же кнопки = усиленный фейк (обходит кулдаун).
func _test_q_fake(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z: влево = -X
	var grabbed: bool = await _grab(player, blade, puck)
	player.velocity = Vector3.ZERO
	await _wait(2)
	# Q — шаг влево (-X).
	Input.action_press("feint_left")
	await _wait(2)
	Input.action_release("feint_left")
	var dvx_q: float = player.velocity.x
	var got_q: String = blade.last_gesture
	# Дабл-тап Q в окно 0.35 с — усиленный (обходит кулдаун).
	await _wait(6)
	Input.action_press("feint_left")
	await _wait(2)
	Input.action_release("feint_left")
	var got_dbl: String = blade.last_gesture
	await _wait(40)  # кулдаун фейка прошёл
	# E — шаг вправо (+X).
	player.velocity = Vector3.ZERO
	Input.action_press("feint_right")
	await _wait(2)
	Input.action_release("feint_right")
	var dvx_e: float = player.velocity.x
	var got_e: String = blade.last_gesture
	_check(grabbed and got_q.contains("влево") and dvx_q < -0.5, "q_fake_left",
			"жест=%s Δv=%.2f" % [got_q, dvx_q])
	_check(got_dbl.contains("УСИЛ"), "fake_double_tap", "жест=%s" % got_dbl)
	_check(got_e.contains("вправо") and dvx_e > 0.5, "e_fake_right",
			"жест=%s Δv=%.2f" % [got_e, dvx_e])
	await _wait(20)


## Треугольник: L+назад (сетап, шайба под себя) -> E+вбок в окне -> шайба
## выстреливает вперёд-в сторону от конька (FREE, скорость).
func _test_triangle(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	# Шаг 1: L + S (назад). Направление жмётся заранее (отдельный тик), чтобы
	# strength гарантированно применился к моменту клика.
	Input.action_press("move_back")
	await _wait(2)
	Input.action_press("gesture_primary")
	await _wait(2)
	Input.action_release("gesture_primary")
	Input.action_release("move_back")
	var setup_ok: bool = blade._triangle_timer > 0.0
	# Шаг 2: L + A (вбок) внутри окна 0.6 с — выстрел из-под конька.
	Input.action_press("turn_left")
	await _wait(2)
	Input.action_press("gesture_primary")
	await _wait(2)
	Input.action_release("gesture_primary")
	var fired := false
	var out_speed := 0.0
	for i in 40:
		await get_tree().physics_frame
		if blade.puck_state == 0:  # FREE — шайба выстрелила из треугольника
			fired = true
			out_speed = maxf(out_speed, Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).length())
	Input.action_release("turn_left")
	Input.action_release("stance")
	_check(grabbed and setup_ok, "triangle_setup", "окно=%s" % setup_ok)
	# Порог 2.0: отскок от конька ослаблен на ~35% (фикс-пасс 4 §6).
	_check(fired and out_speed > 2.0, "triangle_fire",
			"выстрел=%s, скорость %.1f м/с" % [fired, out_speed])
	await _wait(30)


## Правило стороны: шайба на ВНУТРЕННЕЙ + Пробел = ничего (CARRIED остаётся);
## перевод на ВНЕШНЮЮ (ПКМ) + Пробел = подброс (AIR).
func _test_flip_side_rule(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	# УДЕРЖИВАЕМ ПКМ — шайба уходит на внутреннюю (дриблинг держит сторону).
	Input.action_press("gesture_secondary")
	await _wait(25)  # серво дотащило шайбу на внутреннюю
	var internal: bool = not blade.puck_is_external(player.params)
	# Пробел на внутренней (ПКМ ещё держим) — НИЧЕГО.
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	await _wait(3)
	var still_carried: bool = blade.puck_state == 1
	Input.action_release("gesture_secondary")
	await _wait(20)
	# УДЕРЖИВАЕМ ЛКМ — шайба на внешней (сторона хвата).
	Input.action_press("gesture_primary")
	await _wait(25)
	var external: bool = blade.puck_is_external(player.params)
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	await _wait(4)
	var airborne: bool = blade.puck_state == 2
	Input.action_release("gesture_primary")
	Input.action_release("stance")
	_check(grabbed and internal and still_carried, "flip_inner_nothing",
			"внутр=%s, SP не подкинул=%s (%s)" % [internal, still_carried, blade.last_gesture])
	_check(external and airborne, "flip_outer_up",
			"внешн=%s, AIR=%s" % [external, airborne])
	await _wait(40)  # шайба падает и подбирается


## Внутренняя + Пробел + назад = финт через конёк: шайба за спину, конёк
## возвращает её вперёд в клюшку — контроль сохраняется в конце.
func _test_skate_feint(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	Input.action_press("gesture_secondary")  # перевод на внутреннюю (от хвата)
	await _wait(2)
	Input.action_release("gesture_secondary")
	await _wait(25)
	# SP + назад.
	Input.action_press("move_back")
	await _wait(2)
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	Input.action_release("move_back")
	var started: bool = blade._skate_feint_t > 0.0
	# Фазы: протяжка ЗА СПИНУ (carried, шайба сзади) -> авто-возврат вперёд.
	# Шайба всё время на ведении — потерь нет.
	var went_behind := false
	var lost := false
	for i in 90:
		await get_tree().physics_frame
		if blade.puck_state != 1:
			lost = true
		var fwd: Vector3 = -player.global_transform.basis.z
		var to_puck: Vector3 = puck.global_position - player.global_position
		if to_puck.dot(fwd) < -0.1:
			went_behind = true
	var fwd_end: Vector3 = -player.global_transform.basis.z
	var ended_front: bool = (puck.global_position - player.global_position).dot(fwd_end) > 0.1 \
			and blade.puck_state == 1
	Input.action_release("stance")
	_check(grabbed and started, "skate_feint_start", "фаза=%s (%s)" % [started, blade.last_gesture])
	_check(went_behind and not lost and ended_front, "skate_feint_return",
			"за спину=%s потерь=%s спереди в конце=%s" % [went_behind, lost, ended_front])
	await _wait(20)


## Набивание скилловое: вне окна — промах; в окно (110 мс до льда) — подбив;
## сразу после — кулдаун.
func _test_juggle_timing(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	Input.action_press("gesture_lift")  # подброс (нейтраль = внешняя)
	await _wait(2)
	Input.action_release("gesture_lift")
	await _wait(8)  # шайба высоко, летит вверх — окно закрыто
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	var miss: String = blade.last_gesture
	var missed: bool = miss.contains("мимо окна")
	# Ждём открытия окна (падение, последние 110 мс).
	var opened := false
	for i in 90:
		await get_tree().physics_frame
		if blade.juggle_open:
			opened = true
			break
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	var hit_ok: bool = blade.last_gesture.contains("набивание!")
	var vy: float = puck.linear_velocity.y
	# Сразу ещё раз — кулдаун. Кадр между release и press (кадровый InputState
	# видит фронт нажатия только между тиками, как реальный ввод/сеть).
	await _wait(1)
	Input.action_press("gesture_lift")
	await _wait(2)
	Input.action_release("gesture_lift")
	var cd: bool = blade.last_gesture.contains("кулдаун")
	Input.action_release("stance")
	_check(grabbed and missed, "juggle_miss_window", "вне окна: %s" % miss)
	_check(opened and hit_ok and vy > 2.0, "juggle_hit_window",
			"окно=%s подбив=%s vy=%.1f" % [opened, hit_ok, vy])
	_check(cd, "juggle_cooldown", "спам: %s" % blade.last_gesture)
	await _wait(60)  # шайба падает, подбирается


## Силовые: бегущий сносит стоящий манекен и проходит (инерция-преимущество).
func _test_hit_running(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var defender_script := load("res://scripts/defender.gd")
	var blade: AnimatableBody3D = player.get_node("Blade")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))  # шайба в сторонке
	_teleport(player, Vector3(-10, 0.1, -5), -PI / 2.0)
	var d: AnimatableBody3D = defender_script.new()
	main.add_child(d)
	d.setup(defender_script.STATIC, Vector3(-6.0, 0.0, -5.0), player, blade, puck, player.params)
	await _wait(3)
	player.velocity = Vector3(7, 0, 0)  # бегу на манекена
	Input.action_press("turn_right")
	var d_start: Vector3 = d.global_position
	var passed := false
	var speed_after := 0.0
	for i in 90:
		await get_tree().physics_frame
		player.velocity.x = maxf(player.velocity.x, 2.0) if i < 30 else player.velocity.x
		if player.global_position.x > -5.4:
			passed = true
			speed_after = player.velocity.length()
			break
	Input.action_release("turn_right")
	var d_moved: float = (d.global_position - d_start).length()
	d.queue_free()
	_check(d_moved > 0.4, "hit_running_knock", "манекен отлетел на %.2f м" % d_moved)
	_check(passed and speed_after > 1.0, "hit_running_through",
			"прошёл=%s, скорость %.1f м/с" % [passed, speed_after])
	await _wait(20)


## Силовые: движущийся манекен сносит СТОЯЩЕГО игрока (стан) и выбивает шайбу.
func _test_hit_standing(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var defender_script := load("res://scripts/defender.gd")
	_teleport(player, Vector3(0, 0.1, -5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	# Патруль ходит по Z вокруг home — игрок стоит на его пути.
	var d: AnimatableBody3D = defender_script.new()
	main.add_child(d)
	d.setup(defender_script.PATROL, Vector3(0.0, 0.0, -6.2), player, blade, puck, player.params)
	var got_hit := false
	var stripped := false
	for i in 240:  # патруль доезжает до игрока
		await get_tree().physics_frame
		if player.is_stunned():
			got_hit = true
		if blade.puck_state != 1:
			stripped = true
		if got_hit and stripped:
			break
	var kicked_speed: float = player.velocity.length()
	d.queue_free()
	_check(grabbed and got_hit, "hit_standing_stun",
			"стан=%s, скорость отлёта %.1f" % [got_hit, kicked_speed])
	_check(stripped, "hit_strips_puck", "шайба выбита=%s" % stripped)
	await _wait(30)


## Укрывание: игрок в стойке корпусом между манекеном и шайбой — poke не
## достаёт, контроль сохраняется.
func _test_shielding(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var defender_script := load("res://scripts/defender.gd")
	_teleport(player, Vector3(0, 0.1, 5), 0.0)  # facing -Z, шайба впереди (-Z)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")  # is_shielding
	await _wait(3)
	# Манекен ЗА спиной (+Z): игрок между ним и шайбой.
	var d: AnimatableBody3D = defender_script.new()
	main.add_child(d)
	d.setup(defender_script.STATIC, Vector3(0.0, 0.0, 6.1), player, blade, puck, player.params)
	var kept := true
	for i in 80:
		await get_tree().physics_frame
		if blade.puck_state != 1:
			kept = false
			break
	d.queue_free()
	Input.action_release("stance")
	_check(grabbed and kept, "shielding_blocks_poke", "укрыта=%s" % kept)
	await _wait(20)


## Спам широких переводов со сменой стороны (жалоба плейтеста): чередование
## R+вправо / L+влево на бегу — шайба не выбрасывается, carry держится.
func _test_wide_spam(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 10), 0.0)  # facing -Z (по камере), борта далеко
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	Input.action_press("move_forward")  # тяга вперёд (в стойке — с капом, медленно)
	await _wait(3)
	var lost := false
	var why := ""
	for cycle in 8:
		var side_btn := "turn_right" if cycle % 2 == 0 else "turn_left"
		var click_btn := "gesture_secondary" if cycle % 2 == 0 else "gesture_primary"
		Input.action_press(side_btn)
		await _wait(2)
		Input.action_press(click_btn)
		await _wait(2)
		Input.action_release(click_btn)
		Input.action_release(side_btn)
		for i in 16:  # ~0.27 с между переводами — спам
			await get_tree().physics_frame
			if blade.puck_state != 1 and not lost:
				lost = true
				why = blade.last_transition
		if lost:
			break
	Input.action_release("move_forward")
	Input.action_release("stance")
	_check(grabbed and not lost, "wide_spam_carry", "потеря=%s (%s)" % [lost, why])
	await _wait(20)


## Прибивание в лёд (L в воздухе): после подброса шайба резко уходит вниз
## и вскоре снова под контролем (grace нулевой).
func _test_air_slam(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = 0.0
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	await _wait(3)
	Input.action_press("gesture_lift")  # подброс
	await _wait(2)
	Input.action_release("gesture_lift")
	await _wait(14)  # шайба у апекса (~0.4 с)
	Input.action_press("gesture_primary")  # прибить
	await _wait(2)
	Input.action_release("gesture_primary")
	var vy: float = puck.linear_velocity.y
	var got: String = blade.last_gesture
	await _wait(30)  # шайба должна лечь на лёд и не скакать (bounce ~0)
	var settled: bool = puck.global_position.y < 0.15
	Input.action_release("stance")
	_check(grabbed and got.contains("в лёд") and vy < -2.0, "air_slam",
			"жест=%s, vy=%.1f" % [got, vy])
	_check(settled, "air_slam_settled", "y=%.2f (должна лежать на льду)" % puck.global_position.y)
	await _wait(20)


## Манекен: игрок с шайбой в poke_range — телеграф 0.25 с, затем отбор;
## вне радиуса — контроль не трогается.
func _test_defender_poke(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var defender_script := load("res://scripts/defender.gd")
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	# Сначала контроль, ПОТОМ манекен: иначе телеграф стартует во время
	# подготовки и отбор съедается кулдауном до начала замера.
	var grabbed: bool = await _grab(player, blade, puck)
	# Манекен сбоку в 1.1 м (< poke_range 1.3) — шайба впереди, не касается.
	var d: AnimatableBody3D = defender_script.new()
	main.add_child(d)
	d.setup(defender_script.STATIC, Vector3(1.1, 0.0, 5.0), player, blade, puck, player.params)
	var poked := false
	for i in 40:  # телеграф 0.25 с = 15 тиков + запас
		await get_tree().physics_frame
		if blade.puck_state != 1:
			poked = true
			break
	var got: String = blade.last_gesture
	d.queue_free()
	await _wait(10)
	# Вне радиуса: манекен в 6 м — контроль держится.
	var far: AnimatableBody3D = defender_script.new()
	main.add_child(far)
	far.setup(defender_script.STATIC, Vector3(6.0, 0.0, 5.0), player, blade, puck, player.params)
	_teleport(player, Vector3(0, 0.1, 5), 0.0)
	var grabbed2: bool = await _grab(player, blade, puck)
	var kept := true
	for i in 60:
		await get_tree().physics_frame
		if blade.puck_state != 1:
			kept = false
			break
	far.queue_free()
	_check(grabbed and poked and got.contains("отбор"), "defender_poke",
			"отбор=%s жест=%s" % [poked, got])
	_check(grabbed2 and kept, "defender_out_of_range", "контроль вне радиуса=%s" % kept)
	await _wait(20)


## Дриблинг вплотную к борту 10 с со скриптовыми перекладками: carry держится,
## шайба не пересекает внутреннюю грань борта.
func _test_board_dribble(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var wall_z := _half_w  # внутренняя грань борта +Z
	_teleport(player, Vector3(-12, 0.1, wall_z - 0.55), -PI / 2.0)  # вплотную, ход +X
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	Input.action_press("turn_right")  # тяга вдоль борта (стойка: тяга с капом)
	var lost := false
	var max_pz := -100.0
	var buttons := ["gesture_primary", "gesture_secondary"]
	for cycle in 20:  # ~10 с: перекладка каждые ~0.5 с
		var b: String = buttons[cycle % 2]
		Input.action_press(b)
		await _wait(1)
		Input.action_release(b)
		for i in 29:
			await get_tree().physics_frame
			max_pz = maxf(max_pz, puck.global_position.z)
			if blade.puck_state != 1 and not lost:
				lost = true
		if lost:
			break
	Input.action_release("turn_right")
	Input.action_release("stance")
	_check(grabbed and not lost, "board_dribble_carry", "потеря=%s (%s)" % [lost, blade.last_transition])
	_check(max_pz < wall_z - 0.02, "board_dribble_inside", "max z шайбы %.2f (борт %.2f)" % [max_pz, wall_z])
	await _wait(20)


## Фаззинг поз: случайные ЛКМ/ПКМ 30 с на бегу — система отвечает, шайба CARRIED.
func _test_pose_fuzz(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(-18, 0.1, 0), -PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("stance")
	Input.action_press("turn_right")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var lost := false
	var flips := 0
	var prev_pose: int = blade.pose
	var ticks_left := 1800  # 30 с
	while ticks_left > 0:
		var b := "gesture_primary" if rng.randf() < 0.5 else "gesture_secondary"
		Input.action_press(b)
		await _wait(1)
		Input.action_release(b)
		ticks_left -= 1
		var gap := rng.randi_range(2, 18)  # 30–300 мс
		for i in gap:
			await get_tree().physics_frame
			ticks_left -= 1
			if blade.puck_state != 1 and not lost:
				lost = true
			if blade.pose != prev_pose:
				flips += 1
				prev_pose = blade.pose
		# У дальнего борта — бесшовный перенос в начало дорожки (игрок + шайба
		# вместе, скорость сохраняется): бег без реверсов на пределе.
		if player.global_position.x > _half_l - 8.0:
			var shift := player.global_position.x - (-_half_l + 8.0)
			player.global_position.x -= shift
			var pk := get_tree().get_first_node_in_group("puck") as RigidBody3D
			pk.global_position.x -= shift
	Input.action_release("turn_right")
	Input.action_release("stance")
	_check(grabbed and not lost, "pose_fuzz_carry", "потеря=%s (%s)" % [lost, blade.last_transition])
	_check(flips >= 15, "pose_fuzz_responsive", "перекладок %d (нужно >=15)" % flips)
	await _wait(20)


# --- Раздел 4: броски и пасы (камера yaw 0 -> _camera_dir = -Z) ---

func _puck_peak_speed(puck: RigidBody3D, ticks: int) -> float:
	var mx := 0.0
	for i in ticks:
		await get_tree().physics_frame
		var hv := Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z)
		mx = maxf(mx, hv.length())
	return mx


func _test_wrist_shot(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 8), 0.0)  # facing -Z
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("gesture_primary")
	await _wait(4)  # < wrist_tap_time -> тап
	Input.action_release("gesture_primary")
	var peak: float = await _puck_peak_speed(puck, 20)
	_check(grabbed and absf(peak - p.wrist_speed) <= p.wrist_speed * 0.12, "wrist_speed",
			"%.1f м/с (ожидание %.1f)" % [peak, p.wrist_speed])
	await _wait(20)


## Фикс-пасс 4: бросок летит от ШАЙБЫ к точке прицела (луч камеры), а не по
## форварду камеры из корпуса. Камера повёрнута вбок — угол к цели < 3°.
func _test_shot_aim_from_puck(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var camera: Camera3D = main.get_node("Camera3D")
	camera.yaw = PI / 2.0  # смотрим на -X
	# z=10: направление на ворота ~19° от прицела — ВНЕ конуса auto-aim (14°).
	_teleport(player, Vector3(6, 0.1, 10), PI / 2.0)
	var grabbed: bool = await _grab(player, blade, puck)
	await _wait(10)  # камера доезжает на позицию за игроком
	# Точка прицела — по формуле main._aim_dir (та же).
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var aim_point: Vector3 = camera.global_position + cam_fwd * 40.0
	var expected := aim_point - puck.global_position
	expected.y = 0.0
	expected = expected.normalized()
	Input.action_press("gesture_primary")
	await _wait(4)  # тап — кистевой
	Input.action_release("gesture_primary")
	await _wait(3)
	var v := Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z)
	var angle := rad_to_deg(v.angle_to(expected)) if v.length() > 1.0 else 180.0
	camera.yaw = 0.0
	_check(grabbed and angle < 3.0, "shot_aim_from_puck",
			"угол к точке прицела %.1f° (скорость %.1f)" % [angle, v.length()])
	await _wait(20)


## Параметры (в т.ч. камера) сохраняются в JSON и переживают перезапуск.
## Файл юзера бережно восстанавливается.
func _test_params_persist(main: Node3D) -> void:
	var path: String = SkatingParams.SAVE_PATH
	var backup := ""
	var had_file := FileAccess.file_exists(path)
	if had_file:
		backup = FileAccess.open(path, FileAccess.READ).get_as_text()
	var p := SkatingParams.new()
	p.reset_to_defaults()
	p.camera_pitch = 37.0
	p.camera_distance = 9.25
	p.save_to_json()
	var fresh := SkatingParams.new()  # «перезапуск»
	var loaded := fresh.load_from_json()
	var ok: bool = loaded and absf(fresh.camera_pitch - 37.0) < 0.01 \
			and absf(fresh.camera_distance - 9.25) < 0.01
	# Восстановить файл юзера.
	if had_file:
		FileAccess.open(path, FileAccess.WRITE).store_string(backup)
	else:
		DirAccess.remove_absolute(path)
	_check(ok, "params_persist",
			"load=%s pitch=%.1f dist=%.2f" % [loaded, fresh.camera_pitch, fresh.camera_distance])
	# Параметры сцены не трогались (свой инстанс), но на всякий случай:
	main.skating_params.reset_to_defaults()
	await _wait(5)


## Наклон корпуса: в быстром повороте визуал кренится; Q-фейк даёт резкий клевок.
func _test_body_lean(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	var visual: Node3D = player.get_node("PlayerVisual")
	camera.yaw = 0.0
	_teleport(player, Vector3(-14, 0.1, 0), -PI / 2.0)
	player.velocity = Vector3(7, 0, 0)  # быстрый ход +X
	Input.action_press("move_forward")  # W: wish -Z -> крутой поворот влево
	var max_turn_lean := 0.0
	for i in 30:
		await get_tree().physics_frame
		max_turn_lean = maxf(max_turn_lean, absf(visual.rotation.z))
	Input.action_release("move_forward")
	await _wait(30)  # успокоиться
	var rest: float = absf(visual.rotation.z)
	# Q-фейк: резкий клевок больше остаточного.
	Input.action_press("feint_left")
	await _wait(1)
	Input.action_release("feint_left")
	var max_fake_lean := 0.0
	for i in 12:
		await get_tree().physics_frame
		max_fake_lean = maxf(max_fake_lean, absf(visual.rotation.z))
	_check(max_turn_lean > deg_to_rad(6.0), "lean_turn",
			"крен в повороте %.1f° (>6°)" % rad_to_deg(max_turn_lean))
	_check(max_fake_lean > rest + deg_to_rad(10.0), "lean_fake",
			"клевок фейка %.1f° (покой %.1f°)" % [rad_to_deg(max_fake_lean), rad_to_deg(rest)])
	await _wait(20)


func _test_slap_shot(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	var p: SkatingParams = player.params
	_teleport(player, Vector3(0, 0.1, 8), 0.0)
	var grabbed: bool = await _grab(player, blade, puck)
	Input.action_press("gesture_primary")
	await _wait(60)  # полный заряд (> wrist_tap + slap_charge)
	Input.action_release("gesture_primary")
	var peak := 0.0
	var max_y := 0.0
	var late_speed := 0.0
	for i in 30:
		await get_tree().physics_frame
		var hv := Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z)
		peak = maxf(peak, hv.length())
		max_y = maxf(max_y, puck.global_position.y)
		if i == 29:
			late_speed = hv.length()
	_check(grabbed and absf(peak - p.slap_speed_max) <= p.slap_speed_max * 0.12, "slap_speed_max",
			"%.1f м/с (ожидание %.1f)" % [peak, p.slap_speed_max])
	# Сила не гасится о собственную капсулу, шайба не подскакивает свечкой.
	_check(late_speed > p.slap_speed_max * 0.5 and max_y < 2.5, "slap_clean_release",
			"через 0.5с %.1f м/с, max_y %.2f" % [late_speed, max_y])
	await _wait(20)


func _test_whiff(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var blade: AnimatableBody3D = player.get_node("Blade")
	_teleport(player, Vector3(0, 0.1, 8), 0.0)
	# Шайба далеко (свободна, вне окна) — дождаться срыва любого контроля.
	puck.reset_to(Vector3(0, 0.05, 3.0))
	($Main as Node).set("_respawn_ticks", -1)
	for i in 40:
		await get_tree().physics_frame
	var before := puck.linear_velocity.length()
	Input.action_press("gesture_primary")
	await _wait(4)
	Input.action_release("gesture_primary")
	var peak: float = await _puck_peak_speed(puck, 15)
	_check(peak - before < 0.2 and blade.puck_state != 1, "whiff",
			"Δскорости %.3f м/с, state=%s" % [peak - before, blade.puck_state_name])
	await _wait(10)


func _test_bank_reflection(puck: RigidBody3D) -> void:
	# Отражение от борта под 45° в пределах ±8° от зеркального (физика борта).
	var half_w := _half_w
	puck.reset_to(Vector3(-4, 0.05, half_w - 8.0))  # старт дальше от борта
	await _wait(3)
	var vin := Vector3(0.6, 0, 0.6).normalized()
	puck.apply_central_impulse(vin * 22.0 * puck.mass)
	await _wait(1)
	var incoming: Vector3 = Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).normalized()
	# Ждём отскок от +Z борта (vz меняет знак).
	var bounced := false
	for i in 120:
		await get_tree().physics_frame
		if puck.linear_velocity.z < -0.5:
			bounced = true
			break
	var outgoing: Vector3 = Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).normalized()
	var mirror := Vector3(incoming.x, 0, -incoming.z).normalized()  # зеркало от Z-борта
	var err := rad_to_deg(outgoing.angle_to(mirror))
	_check(bounced and err <= 8.0, "bank_reflection", "отклонение от зеркального %.1f°" % err)
	await _wait(10)


# --- Раздел 5: реверс ---

func _test_reverse_stop(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(-6, 0.1, 0), -PI / 2.0)  # facing +X
	player.velocity = Vector3(9, 0, 0)
	await _wait(1)
	Input.action_press("turn_left")  # wish -X: чистый реверс 180°
	var mins := 99.0
	for i in 150:
		await get_tree().physics_frame
		mins = minf(mins, player.velocity.length())
	Input.action_release("turn_left")
	_check(mins < 1.0, "reverse_stop", "мин. скорость %.2f м/с" % mins)
	await _wait(10)


func _test_reverse_diagonal(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(-6, 0.1, -6), -PI / 2.0)  # facing +X
	player.velocity = Vector3(6, 0, 0)
	await _wait(1)
	Input.action_press("move_forward")  # wish -Z: смена ~90°
	var mins := 99.0
	for i in 45:
		await get_tree().physics_frame
		mins = minf(mins, player.velocity.length())
	Input.action_release("move_forward")
	_check(mins > 3.0, "reverse_diagonal", "мин. скорость %.2f м/с (>50%% от 6)" % mins)
	await _wait(10)


# --- Раздел 6: Alt-глайд ---

func _test_glide_steer(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	puck.reset_to(Vector3(_goal_x - 2.0, 0.05, _half_w - 3.0))
	_teleport(player, Vector3(-10, 0.1, 8), -PI / 2.0)  # facing +X
	player.velocity = Vector3(7, 0, 0)
	await _wait(1)
	Input.action_press("profile_glide")
	Input.action_press("move_forward")  # wish -Z: руль в глайде
	var heading := 0.0
	var path := 0.0
	var prev_dir := Vector3(1, 0, 0)
	var prev_pos := player.global_position
	for i in 80:
		await get_tree().physics_frame
		var hv := Vector3(player.velocity.x, 0, player.velocity.z)
		if hv.length() > 0.5:
			heading += absf(prev_dir.signed_angle_to(hv.normalized(), Vector3.UP))
			prev_dir = hv.normalized()
		path += (player.global_position - prev_pos).length()
		prev_pos = player.global_position
	Input.action_release("move_forward")
	Input.action_release("profile_glide")
	var radius := path / maxf(heading, 0.01)
	_check(heading > 0.3 and radius < 25.0, "glide_steer",
			"радиус %.1f м, поворот %.0f°" % [radius, rad_to_deg(heading)])
	await _wait(10)


# --- Раздел 7: шайба не покидает арену ---

func _test_arena_ceiling(main: Node3D, puck: RigidBody3D) -> void:
	var escaped := false
	for shot in 60:
		puck.reset_to(Vector3(0, 0.05, 0))
		await _wait(2)
		# Случайный сильный выстрел вверх/в стороны.
		var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.2), randf_range(-1, 1)).normalized()
		puck.apply_central_impulse(dir * 45.0 * puck.mass)
		for i in 40:
			await get_tree().physics_frame
			var pp := puck.global_position
			if absf(pp.x) > _half_l + 0.6 or absf(pp.z) > _half_w + 0.6 or pp.y > 6.6 or pp.y < -0.5:
				escaped = true
				break
		if escaped:
			_check(false, "arena_ceiling", "шайба покинула арену на выстреле %d: %v" % [shot, puck.global_position])
			return
	_check(true, "arena_ceiling", "60 сильных выстрелов — шайба в арене")
	await _wait(10)


# --- Вратарь ---
func _test_goalie(main: Node3D, puck: RigidBody3D) -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var params: SkatingParams = player.params
	var goalie_script := load("res://scripts/goalie.gd")
	var gx := _goal_x
	var gc := Vector3(gx, 0.0, 0.0)
	var out_dir := Vector3(-1, 0, 0)  # правые ворота смотрят в поле по -X
	# Игрока и шайбу — подальше, чтобы не мешали.
	_teleport(player, Vector3(0, 0.1, 8), 0.0)

	# 1) Всегда лицом к шайбе.
	var g: AnimatableBody3D = goalie_script.new()
	main.add_child(g)
	g.setup(gc, out_dir, player, puck, params)
	puck.freeze = false
	puck.reset_to(Vector3(gx - 5.0, 0.05, 4.0))  # сбоку-впереди
	for i in 40:
		await get_tree().physics_frame
	var fwd: Vector3 = -g.global_transform.basis.z
	var to_puck: Vector3 = puck.global_position - g.global_position
	to_puck.y = 0.0
	var facing_ok: bool = fwd.normalized().dot(to_puck.normalized()) > 0.85
	_check(facing_ok, "goalie_faces_puck", "dot(facing, к шайбе)=%.2f" % fwd.normalized().dot(to_puck.normalized()))

	# 2) Позиция клампится в goalie_range.
	var far := gc + out_dir * 20.0 + Vector3(0, 0, 15.0)
	var clamped: Vector3 = g._clamp_range(far)
	var off := (clamped - gc)
	off.y = 0.0
	_check(off.length() <= params.goalie_range + 0.01, "goalie_range_clamp",
			"смещение %.2f <= range %.2f" % [off.length(), params.goalie_range])

	# 3) Ловля = окно + КОНТАКТ: открыл окно (ЛКМ), шайба дошла до ловушки →
	# GLOVED. Держим шайбу у ловушки на время окна (эмуляция контакта).
	params.goalie_player_controlled = false
	puck.freeze = false
	puck.reset_to(g.global_position + Vector3(-0.4, 0.4, -0.4))  # слева-впереди
	await _wait(2)
	puck.linear_velocity = (g.global_position - puck.global_position).normalized() * 4.0
	await _wait(1)
	g._save_cd = 0.0
	g.catch()  # открыть окно
	var caught := false
	for i in 16:  # окно ~0.25 с
		await get_tree().physics_frame
		puck.global_position = g._catcher.global_position  # шайба у ловушки (контакт)
		if g.puck_in_catch:
			caught = true
			break
	_check(caught and puck.freeze, "goalie_catch_window",
			"поймал в окне=%s (вердикт %s)" % [caught, g.last_verdict])
	# Выброс пойманной шайбы игроку.
	g.throw_puck()
	await _wait(2)
	var thrown: bool = not puck.freeze and not g.puck_in_catch \
			and Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).length() > 3.0
	_check(thrown, "goalie_throw", "выброшена (%.1f м/с)" % Vector3(puck.linear_velocity.x, 0, puck.linear_velocity.z).length())

	# 4) Ловушка (левая) на шайбу в ПРАВОЙ половине ворот = WRONG_SIDE (рука не
	# пересекает центр). Правая половина — фикс. ось ворот.
	puck.freeze = false
	g.puck_in_catch = false
	g._save_cd = 0.0
	var net_r: Vector3 = g._net_right()
	puck.reset_to(gc + net_r * 1.2 + Vector3(0, 0.3, 0))  # правая половина
	await _wait(3)  # предикт обновится
	g.catch()
	var verdict_ws: String = g.last_verdict
	var not_caught := true
	for i in 16:
		await get_tree().physics_frame
		if g.puck_in_catch:
			not_caught = false
	_check(verdict_ws == "WRONG_SIDE" and not_caught, "goalie_wrong_side",
			"правая половина+ловушка: вердикт=%s пойма=%s" % [verdict_ws, not not_caught])
	# Кулдаун 0.2: сразу повторный сейв не открывается.
	g.puck_in_catch = false
	puck.freeze = false
	g._save_cd = 0.0
	g.catch()
	var blocked_by_cd: bool = not g.catch()  # второй вызов — кулдаун
	_check(blocked_by_cd, "goalie_cooldown", "кулдаун блокирует спам (cd=%.2f)" % g._save_cd)

	# 5) AI выбирает действие по зоне (низ→баттерфляй, девятка→ловушка/блин, серед→стойка).
	var g_right: Vector3 = g._right()
	var z_low: Vector3 = gc + Vector3(0, 0.15, 0.0)
	var z_high_l: Vector3 = gc + g_right * -0.6 + Vector3(0, 1.0, 0)
	var z_mid: Vector3 = gc + Vector3(0, 0.7, 0.0)
	var a_low: String = g.action_for_zone(g.zone_of(z_low))
	var a_high: String = g.action_for_zone(g.zone_of(z_high_l))
	var a_mid: String = g.action_for_zone(g.zone_of(z_mid))
	_check(a_low == "butterfly", "goalie_ai_low", "низ→%s" % a_low)
	_check(a_high == "catch" or a_high == "blocker", "goalie_ai_high", "девятка→%s" % a_high)
	_check(a_mid == "stance", "goalie_ai_mid", "середина→%s" % a_mid)

	# 6) Перекрытие зон зависит от позы: баттерфляй закрывает низ, открывает верх.
	g.state = g.BUTTERFLY
	var covers_low: bool = g.covers(g.Z_LOW_LEFT)
	var opens_high: bool = not g.covers(g.Z_HIGH_LEFT)
	g.state = g.STANCE
	_check(covers_low and opens_high, "goalie_coverage",
			"баттерфляй: низ закрыт=%s верх открыт=%s" % [covers_low, opens_high])

	# 6b) ФИЗИКА: бабочка физически перекрывает низ и 5-hole — шайба НЕ проходит
	# за вратаря (коллайдеры щитков по позе + CCD).
	params.goalie_player_controlled = false
	var through := 0
	var five_hole_saved := false
	for shot in 14:
		puck.freeze = false
		var zoff: float = lerpf(-0.6, 0.6, float(shot) / 13.0)
		if shot == 7:
			zoff = 0.0  # ровно 5-hole
		puck.reset_to(gc + out_dir * 3.0 + Vector3(0, 0.12, zoff))
		var aim := gc + Vector3(0, 0.1, zoff * 0.3)
		puck.linear_velocity = (aim - puck.global_position).normalized() * 24.0
		var crossed := false
		for i in 30:
			await get_tree().physics_frame
			g.state = g.BUTTERFLY
			g._recovery = 1.0  # держим бабочку (AI не встаёт)
			# За вратаря/линию (в сетку, +X за gx) = проход.
			if puck.global_position.x > gx + 0.12:
				crossed = true
				break
		if crossed:
			through += 1
		elif shot == 7:
			five_hole_saved = true
	g._recovery = 0.0
	_check(through == 0, "goalie_physical_block", "проходов сквозь бабочку: %d/14 (нужно 0)" % through)
	_check(five_hole_saved, "goalie_five_hole", "5-hole закрыт бабочкой=%s" % five_hole_saved)

	# 6c) Баттерфляй-пуш: слайд на ~push_distance к штанге, кулдаун, clamp в зоне.
	params.goalie_player_controlled = true
	puck.freeze = false
	puck.reset_to(Vector3(gx - 6.0, 0.05, 0.0))
	_teleport(player, Vector3(0, 0.1, 8), 0.0)
	g.global_position = gc + out_dir * 0.3
	await _wait(2)
	g.state = g.BUTTERFLY
	g._push_cd = 0.0
	var px0: Vector3 = g.global_position
	g.start_push(1)  # пуш вправо (в осях вратаря)
	for i in 25:
		await get_tree().physics_frame
	var pushed: float = Vector3(g.global_position.x - px0.x, 0, g.global_position.z - px0.z).length()
	var in_zone: bool = g.in_range(g.global_position) or (g.global_position - gc).length() <= params.goalie_range + 0.05
	_check(pushed > 0.5 and pushed <= params.push_distance + 0.15, "goalie_push_distance",
			"слайд %.2f м (цель %.2f)" % [pushed, params.push_distance])
	_check(g._push_cd > 0.0 and in_zone, "goalie_push_cooldown",
			"кулдаун=%.2f, в зоне=%s" % [g._push_cd, in_zone])
	params.goalie_player_controlled = false

	g.queue_free()
	puck.freeze = false
	await _wait(10)

	# 7) Манекен-бросающий: за цикл делает бросок (шайба летит к воротам).
	var shooter_script := load("res://scripts/training_shooter.gd")
	var sh: Node3D = shooter_script.new()
	main.add_child(sh)
	puck.freeze = false
	sh.setup(gc, out_dir, puck, params)
	var shot_fired := false
	for i in 240:  # ~4 с — хватает на подъезд+замах+бросок
		await get_tree().physics_frame
		var toward: float = puck.linear_velocity.dot(-out_dir)  # к воротам
		if toward > 8.0:
			shot_fired = true
			break
	sh.queue_free()
	_check(shot_fired, "shooter_fires", "манекен бросил в ворота=%s" % shot_fired)
	await _wait(10)

	# 8) Свап на вратаря: player.input_enabled выключается, камера на вратаря.
	params.goalie_enabled = false
	await _wait(2)
	main._toggle_goalie_control()
	var swapped: bool = not player.input_enabled and main._controlling_goalie
	main._toggle_goalie_control()
	var back: bool = player.input_enabled and not main._controlling_goalie
	_check(swapped, "swap_to_goalie", "управление у вратаря=%s" % swapped)
	_check(back, "swap_back", "управление вернулось полевому=%s" % back)
	# Вернуть дефолты сцены.
	params.goalie_enabled = false
	main._refresh_goalie()
	puck.freeze = false
	await _wait(10)


func _teleport(player: CharacterBody3D, pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
