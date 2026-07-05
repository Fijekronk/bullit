extends Node3D
## Этап 1: сборка арены и отладочное управление тестовой шайбой.
## Вся игровая логика — в _physics_process (фиксированный тикрейт 60).

const PUSH_SPEED_MIN := 5.0
const PUSH_SPEED_MAX := 25.0
const SHOT_SPEED := 40.0
const GOAL_RESPAWN_DELAY := 1.0  # сек до респауна шайбы после гола
const PUCK_SPAWN := Vector3(0.0, 0.1, 0.0)

@onready var puck: RigidBody3D = $Puck
@onready var goals: Array[Node3D] = [$GoalLeft, $GoalRight]
@onready var debug: CanvasLayer = $Debug
@onready var player: Player = $Player
@onready var chase_camera: Camera3D = $Camera3D
@onready var tuning_panel: CanvasLayer = $TuningPanel

var score := {"left": 0, "right": 0}
var skating_params := SkatingParams.new()
var _respawn_ticks := -1


func _ready() -> void:
	for goal in goals:
		goal.goal_scored.connect(_on_goal_scored)
	# Один общий ресурс параметров: игрок, камера и F1-панель крутят его же.
	skating_params.load_from_json()
	player.params = skating_params
	chase_camera.params = skating_params
	chase_camera.target = player
	tuning_panel.setup(skating_params)
	# Мышь не должна выпадать за окно при финтах.
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_respawn"):
		_respawn_puck()
	if Input.is_action_just_pressed("debug_push"):
		_push_puck_random()
	if Input.is_action_just_pressed("debug_shoot"):
		_shoot_at_nearest_goal()
	if Input.is_action_just_pressed("toggle_handedness"):
		skating_params.handedness_right = not skating_params.handedness_right
		tuning_panel.refresh_values()

	if _respawn_ticks > 0:
		_respawn_ticks -= 1
		if _respawn_ticks == 0:
			_respawn_ticks = -1
			_respawn_puck()


func _respawn_puck() -> void:
	puck.reset_to(PUCK_SPAWN)


func _push_puck_random() -> void:
	var angle := randf() * TAU
	var speed := randf_range(PUSH_SPEED_MIN, PUSH_SPEED_MAX)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	puck.apply_central_impulse(direction * speed * puck.mass)


func _shoot_at_nearest_goal() -> void:
	var target_goal: Node3D = goals[0]
	for goal in goals:
		if goal.global_position.distance_to(puck.global_position) \
				< target_goal.global_position.distance_to(puck.global_position):
			target_goal = goal
	# Целимся в случайную точку створа, включая штанги и перекладину —
	# так клавиша T проверяет и гол-триггер, и рикошеты от рамки.
	var target := target_goal.global_position \
			+ Vector3(0.0, randf_range(0.05, 1.3), randf_range(-1.2, 1.2))
	var direction := (target - puck.global_position).normalized()
	puck.apply_central_impulse(direction * SHOT_SPEED * puck.mass)


func _on_goal_scored(side: String) -> void:
	score[side] += 1
	debug.set_score(score["left"], score["right"])
	_respawn_ticks = int(GOAL_RESPAWN_DELAY * Engine.physics_ticks_per_second)
