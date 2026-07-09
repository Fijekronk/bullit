extends Node3D
## Тренировочный манекен-бросающий: встаёт в разные точки поля, делает ЯВНЫЙ
## замах (клюшка отводится, пауза) и бьёт по разным зонам створа — для
## тренировки вратаря. Цикл: подъезд -> замах -> бросок -> пауза -> след. точка.

const BODY_COLOR := Color(0.55, 0.2, 0.5)
const STICK_COLOR := Color(0.1, 0.1, 0.12)

var goal_center := Vector3.ZERO
var out_dir := Vector3(-1, 0, 0)   # из ворот в поле
var shot_speed := 26.0

var _puck: RigidBody3D
var _params: SkatingParams
var _spots: Array[Vector3] = []
var _spot_i := 0
var _phase := "move"
var _t := 0.0
var _target := Vector3.ZERO
var _from := Vector3.ZERO
var _body: Node3D
var _stick: Node3D
var last_zone := ""


func setup(p_goal_center: Vector3, p_out_dir: Vector3, puck: RigidBody3D, params: SkatingParams) -> void:
	goal_center = p_goal_center
	out_dir = p_out_dir.normalized()
	_puck = puck
	_params = params
	add_to_group("training_shooter")
	var lateral := out_dir.rotated(Vector3.UP, -PI / 2.0)
	# Точки броска: слот, круги, точка, острые углы.
	_spots = [
		goal_center + out_dir * 9.0,                       # слот по центру
		goal_center + out_dir * 7.0 + lateral * 5.0,       # левый круг
		goal_center + out_dir * 7.0 - lateral * 5.0,       # правый круг
		goal_center + out_dir * 13.0,                      # от точки (дальше)
		goal_center + out_dir * 4.5 + lateral * 6.5,       # острый угол слева
		goal_center + out_dir * 4.5 - lateral * 6.5,       # острый угол справа
	]
	global_position = _spots[0]
	_from = _spots[0]
	_target = _spots[0]
	_build_body()


func _build_body() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.roughness = 1.0
	_body = Node3D.new()
	add_child(_body)
	var torso := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.3
	cyl.height = 1.3
	torso.mesh = cyl
	torso.material_override = mat
	torso.position = Vector3(0, 0.65, 0)
	_body.add_child(torso)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	head.mesh = sph
	head.material_override = mat
	head.position = Vector3(0, 1.5, 0)
	_body.add_child(head)
	# Клюшка — отдельный узел, отводится на замахе (видно телеграф).
	var smat := StandardMaterial3D.new()
	smat.albedo_color = STICK_COLOR
	smat.roughness = 1.0
	_stick = Node3D.new()
	_stick.position = Vector3(0, 0.5, 0)
	_body.add_child(_stick)
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 1.1)
	shaft.mesh = box
	shaft.material_override = smat
	shaft.position = Vector3(0.2, 0, -0.55)
	_stick.add_child(shaft)


func _physics_process(delta: float) -> void:
	if _puck == null or _params == null:
		return
	_t += delta
	# Смотрим на ворота.
	var f := (goal_center - global_position)
	f.y = 0.0
	if f.length() > 0.2:
		_body.rotation.y = atan2(f.x, f.z) + PI
	match _phase:
		"move":
			var k: float = clampf(_t / 0.8, 0.0, 1.0)
			global_position = _from.lerp(_target, k)
			# Шайба «на клюшке» перед манекеном.
			_hold_puck()
			if k >= 1.0:
				_phase = "windup"
				_t = 0.0
		"windup":
			_hold_puck()
			# Клюшка отводится назад (явный замах ~0.6 с).
			var w: float = clampf(_t / 0.6, 0.0, 1.0)
			_stick.rotation.y = lerpf(0.0, -1.2, w)
			if _t >= 0.6:
				_shoot()
				_phase = "recover"
				_t = 0.0
		"recover":
			# Клюшка возвращается, короткая пауза.
			_stick.rotation.y = lerpf(_stick.rotation.y, 0.4, 1.0 - exp(-16.0 * delta))
			if _t >= 0.5:
				_phase = "wait"
				_t = 0.0
		"wait":
			_stick.rotation.y = lerpf(_stick.rotation.y, 0.0, 1.0 - exp(-10.0 * delta))
			if _t >= 1.0:
				_spot_i = (_spot_i + 1) % _spots.size()
				_from = global_position
				_target = _spots[_spot_i]
				_phase = "move"
				_t = 0.0


func _hold_puck() -> void:
	if _puck.freeze:
		return
	var f := (goal_center - global_position)
	f.y = 0.0
	f = f.normalized() if f.length() > 0.2 else out_dir
	_puck.linear_velocity = Vector3.ZERO
	_puck.global_position = global_position + f * 0.6 + Vector3(0, 0.05, 0)


## Бросок по случайной зоне створа (высокие — с подъёмом).
func _shoot() -> void:
	var lateral := out_dir.rotated(Vector3.UP, -PI / 2.0)
	# Случайная зона: смещение по ширине и высоте створа.
	var zi := randi() % 6
	var s := 0.0
	var y := 0.15
	match zi:
		0: s = 0.0; y = 0.1; last_zone = "5-hole"
		1: s = -0.7; y = 0.15; last_zone = "низ-лево"
		2: s = 0.7; y = 0.15; last_zone = "низ-право"
		3: s = -0.75; y = 1.05; last_zone = "девятка-лево"
		4: s = 0.75; y = 1.05; last_zone = "девятка-право"
		5: s = 0.0; y = 0.6; last_zone = "середина"
	var aim := goal_center + lateral * s + Vector3(0, y, 0)
	var dir := (aim - _puck.global_position)
	var horiz := Vector3(dir.x, 0, dir.z).normalized()
	var lift := clampf(dir.y, 0.0, 1.2)
	_puck.freeze = false
	_puck.linear_velocity = Vector3.ZERO
	_puck.apply_central_impulse((horiz * shot_speed + Vector3(0, lift * 3.0, 0)) * _puck.mass)


## Точка прицела последнего броска (для тестов).
func aim_point_for(zi: int) -> Vector3:
	var lateral := out_dir.rotated(Vector3.UP, -PI / 2.0)
	match zi:
		0: return goal_center + Vector3(0, 0.1, 0)
		1: return goal_center + lateral * -0.7 + Vector3(0, 0.15, 0)
		2: return goal_center + lateral * 0.7 + Vector3(0, 0.15, 0)
		3: return goal_center + lateral * -0.75 + Vector3(0, 1.05, 0)
		4: return goal_center + lateral * 0.75 + Vector3(0, 1.05, 0)
	return goal_center + Vector3(0, 0.6, 0)
