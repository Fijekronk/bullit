extends Node3D
## Сборка арены + отладка + маршрутизация ввода верхнего уровня.
## Мышь захвачена (камера-орбита). ЛКМ/ПКМ вне стойки — бросок/пас с
## прицеливанием от камеры (в стойке ЛКМ/ПКМ/пробел уходят в жесты — blade.gd).

const PUSH_SPEED_MIN := 5.0
const PUSH_SPEED_MAX := 25.0
const DEBUG_SHOT_SPEED := 40.0
const SHOT_SPEED := 30.0
const PASS_SPEED := 18.0
const AIM_CONE_DEG := 14.0
const GOAL_RESPAWN_DELAY := 1.0
const PUCK_SPAWN := Vector3(0.0, 0.1, 0.0)

@onready var puck: RigidBody3D = $Puck
@onready var goals: Array[Node3D] = [$GoalLeft, $GoalRight]
@onready var debug: CanvasLayer = $Debug
@onready var player: Player = $Player
@onready var chase_camera: Camera3D = $Camera3D
@onready var tuning_panel: CanvasLayer = $TuningPanel
@onready var rink: Node3D = $Rink
@onready var cones: Node3D = $Cones
@onready var trail: MeshInstance3D = $Player/SkidTrail
@onready var blade: Node3D = $Player/Blade

var score := {"left": 0, "right": 0}
var skating_params := SkatingParams.new()
var defenders: Node3D
var goalie: Node3D
var shooter: Node3D
var _controlling_goalie := false
var _training_mode := 0  # F3-цикл: 0 конусы, 1 манекены, 2 оба, 3 пусто
var _respawn_ticks := -1
# Броски/пасы (вне стойки; в стойке ЛКМ/ПКМ — позы)
var _lmb_t := 0.0
var _charging := false
var charge := 0.0          # заряд щелчка 0..1 (для HUD)
var _rmb_t := 0.0
var _rmb_held := false
var _windup_cd := 0.0
var pass_charge := 0.0     # заряд паса 0..1 (для HUD)


func _ready() -> void:
	for goal in goals:
		goal.goal_scored.connect(_on_goal_scored)
	skating_params.load_from_json()
	player.params = skating_params
	chase_camera.params = skating_params
	chase_camera.target = player
	tuning_panel.setup(skating_params)
	$Hud/HudControl.setup(self)
	$PuckTrail.setup(puck, skating_params)
	tuning_panel.rebuild_requested.connect(_rebuild_rink)
	tuning_panel.clear_trail_requested.connect(func(): trail.clear_trail())
	tuning_panel.toggle_trail_requested.connect(func(on): trail.set_enabled(on))
	defenders = preload("res://scripts/defenders.gd").new()
	defenders.name = "Defenders"
	add_child(defenders)
	_rebuild_rink()
	_refresh_goalie()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Спавн/удаление вратаря у ПРАВЫХ ворот по параметру goalie_enabled.
func _refresh_goalie() -> void:
	if goalie != null and not skating_params.goalie_enabled:
		if _controlling_goalie:
			_set_goalie_control(false)
		goalie.queue_free()
		goalie = null
	elif goalie == null and skating_params.goalie_enabled:
		var gx: float = rink.goal_line_x()
		goalie = preload("res://scripts/goalie.gd").new()
		goalie.name = "Goalie"
		add_child(goalie)
		# Правые ворота: линия x=+gx, открытая сторона (в поле) смотрит в -X.
		goalie.setup(Vector3(gx, 0.0, 0.0), Vector3(-1, 0, 0), player, puck, skating_params)


## Спавн/удаление тренировочного манекена-бросающего.
func _refresh_shooter() -> void:
	if shooter != null and not skating_params.training_shooter:
		shooter.queue_free()
		shooter = null
	elif shooter == null and skating_params.training_shooter:
		var gx: float = rink.goal_line_x()
		shooter = preload("res://scripts/training_shooter.gd").new()
		shooter.name = "TrainingShooter"
		add_child(shooter)
		shooter.setup(Vector3(gx, 0.0, 0.0), Vector3(-1, 0, 0), puck, skating_params)


## Свап управления: полевой <-> вратарь (клавиша G). Спавнит вратаря при нужде.
func _toggle_goalie_control() -> void:
	if not _controlling_goalie:
		if not skating_params.goalie_enabled:
			skating_params.goalie_enabled = true
			_refresh_goalie()
	_set_goalie_control(not _controlling_goalie)


func _set_goalie_control(on: bool) -> void:
	_controlling_goalie = on and goalie != null
	skating_params.goalie_player_controlled = _controlling_goalie
	player.input_enabled = not _controlling_goalie
	chase_camera.goalie_mode = _controlling_goalie  # пресет камеры вратаря
	if _controlling_goalie:
		chase_camera.target = goalie
	else:
		chase_camera.target = player


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Освободить/захватить мышь (удобство теста).
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	# Снять ввод локального игрока ДО игровой логики (main = корень, идёт раньше
	# player). Идемпотентно за кадр. В сети сервер вместо этого пишет пакеты.
	if player.input_local:
		player.input.poll_local()
	if Input.is_action_just_pressed("debug_respawn"):
		_respawn_puck()
	if Input.is_action_just_pressed("debug_push"):
		_push_puck_random()
	if Input.is_action_just_pressed("debug_shoot"):
		_shoot_at_nearest_goal()
	if Input.is_action_just_pressed("toggle_handedness"):
		skating_params.handedness_right = not skating_params.handedness_right
		tuning_panel.refresh_values()
	if Input.is_action_just_pressed("toggle_debug_viz") and goalie:
		goalie.debug_draw = not goalie.debug_draw  # F2 — зоны/досягаемость вратаря
	if Input.is_action_just_pressed("swap_goalie"):
		_toggle_goalie_control()
	_refresh_goalie()  # реакция на тоггл в панели
	_refresh_shooter()
	if Input.is_action_just_pressed("toggle_cones"):
		# F3: цикл полигона — конусы -> манекены -> оба -> пусто.
		_training_mode = (_training_mode + 1) % 4
		cones.set_active(_training_mode == 0 or _training_mode == 2)
		defenders.set_active(_training_mode == 1 or _training_mode == 2)

	# Броски/пасы полевого — только когда игрок им управляет и вне стойки.
	if not player.input_enabled:
		_reset_shot()
	elif player.is_stance:
		_reset_shot()
	else:
		_update_shots(get_physics_process_delta_time())

	if _respawn_ticks > 0:
		_respawn_ticks -= 1
		if _respawn_ticks == 0:
			_respawn_ticks = -1
			_respawn_puck()


## Ввод бросков/пасов (этап 4): ЛКМ тап — кистевой, ЛКМ удержание — щелчок с
## зарядкой и замахом, ПКМ — пас (тап/зарядка), ПКМ во время замаха — отмена.
func _update_shots(delta: float) -> void:
	var p := skating_params
	_windup_cd = maxf(0.0, _windup_cd - delta)

	# --- ЛКМ: кистевой / щелчок ---
	if player.input.just_pressed("gesture_primary"):
		_lmb_t = 0.0
		_charging = false
	if player.input.pressed("gesture_primary"):
		_lmb_t += delta
		if _lmb_t > p.wrist_tap_time and _windup_cd <= 0.0:
			_charging = true
			charge = clampf((_lmb_t - p.wrist_tap_time) / p.slap_charge_time, 0.0, 1.0)
			blade.windup = charge
			player.speed_cap = p.slap_move_cap
			player.aim_turn_dir = _aim_dir()  # корпус доворачивается к прицелу
	if player.input.just_released("gesture_primary"):
		if _charging:
			_do_slap(charge)
		else:
			_do_wrist()
		_reset_shot()

	# --- ПКМ: пас / отмена замаха ---
	if player.input.just_pressed("gesture_secondary"):
		if _charging:
			_reset_shot()  # ложный замах — отмена
			_windup_cd = 0.2
		else:
			_rmb_held = true
			_rmb_t = 0.0
	if _rmb_held:
		_rmb_t += delta
		pass_charge = clampf(_rmb_t / 0.5, 0.0, 1.0)
	if player.input.just_released("gesture_secondary") and _rmb_held:
		_do_pass(pass_charge)
		_rmb_held = false
		pass_charge = 0.0


func _reset_shot() -> void:
	_charging = false
	charge = 0.0
	_lmb_t = 0.0
	blade.windup = 0.0
	player.speed_cap = 1.0
	player.aim_turn_dir = Vector3.ZERO


const AIM_DISTANCE := 40.0  # точка прицела на луче камеры (центр экрана)


## Направление броска: от ШАЙБЫ к точке прицела (луч камеры из центра экрана
## на дальнюю дистанцию, прижатый ко льду) — «куда смотрю — туда летит»,
## независимо от того, где шайба относительно корпуса.
func _aim_dir() -> Vector3:
	var cam_fwd := -chase_camera.global_transform.basis.z
	var aim_point := chase_camera.global_position + cam_fwd * AIM_DISTANCE
	var dir := aim_point - puck.global_position
	dir.y = 0.0
	if dir.length() < 0.5:  # вырожденный случай — горизонтальный форвард камеры
		dir = cam_fwd
		dir.y = 0.0
	return dir.normalized()


func _do_wrist() -> void:
	var dir := _aim_assist(_aim_dir(), 1.0)
	$PuckTrail.shot_color = $PuckTrail.COLOR_SOFT
	blade.shoot(dir, skating_params.wrist_speed, skating_params.wrist_lift)


func _do_slap(c: float) -> void:
	var p := skating_params
	# Трейд-офф мощи: на полном заряде auto-aim ослаблен вдвое, разброс больше.
	var dir := _aim_assist(_aim_dir(), 1.0 - 0.5 * c)
	var spread := deg_to_rad(lerpf(1.0, p.slap_spread, c))
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	$PuckTrail.shot_color = $PuckTrail.COLOR_SLAP if c > 0.5 else $PuckTrail.COLOR_SOFT
	blade.shoot(dir, lerpf(p.slap_speed_min, p.slap_speed_max, c),
			lerpf(1.5, p.slap_lift_max, c))


func _do_pass(c: float) -> void:
	var p := skating_params
	# Пас — чистое направление на точку прицела, БЕЗ auto-aim; на заряде подъём.
	$PuckTrail.shot_color = $PuckTrail.COLOR_SOFT
	blade.shoot(_aim_dir(), lerpf(p.pass_speed, p.pass_speed_max, c),
			lerpf(0.0, p.pass_lift_max, c))


func _aim_assist(dir: Vector3, scale: float) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(AIM_CONE_DEG))
	for goal in goals:
		var to_goal := goal.global_position - puck.global_position
		to_goal.y = 0.0
		to_goal = to_goal.normalized()
		var d := dir.dot(to_goal)
		if d > best_dot:
			best = dir.slerp(to_goal, skating_params.aim_assist_strength * scale)
			best_dot = d
	return best.normalized()


func _rebuild_rink() -> void:
	rink.rebuild(skating_params.rink_length, skating_params.rink_width, skating_params.corner_radius)
	var goal_x: float = rink.goal_line_x()
	goals[0].transform = Transform3D(Basis.IDENTITY, Vector3(-goal_x, 0.0, 0.0))
	goals[1].transform = Transform3D(Basis(Vector3.UP, PI), Vector3(goal_x, 0.0, 0.0))
	cones.layout(skating_params.rink_length, skating_params.rink_width)
	defenders.layout(skating_params.rink_length, skating_params.rink_width, goal_x,
			player, blade, puck, skating_params)
	if absf(puck.global_position.x) > goal_x or absf(puck.global_position.z) > skating_params.rink_width / 2.0:
		_respawn_puck()


func _respawn_puck() -> void:
	puck.reset_to(PUCK_SPAWN)
	trail.clear_trail()  # чистый лёд при возврате шайбы в центр


func _push_puck_random() -> void:
	var angle := randf() * TAU
	var speed := randf_range(PUSH_SPEED_MIN, PUSH_SPEED_MAX)
	puck.apply_central_impulse(Vector3(cos(angle), 0.0, sin(angle)) * speed * puck.mass)


func _shoot_at_nearest_goal() -> void:
	var target_goal: Node3D = goals[0]
	for goal in goals:
		if goal.global_position.distance_to(puck.global_position) \
				< target_goal.global_position.distance_to(puck.global_position):
			target_goal = goal
	var target := target_goal.global_position \
			+ Vector3(0.0, randf_range(0.05, 1.3), randf_range(-1.2, 1.2))
	var direction := (target - puck.global_position).normalized()
	puck.apply_central_impulse(direction * DEBUG_SHOT_SPEED * puck.mass)


func _on_goal_scored(side: String) -> void:
	score[side] += 1
	debug.set_score(score["left"], score["right"])
	_respawn_ticks = int(GOAL_RESPAWN_DELAY * Engine.physics_ticks_per_second)
