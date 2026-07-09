extends AnimatableBody3D
## Манекен-защитник для тренировки финтов. Три режима: СТАТИК (стоит),
## ПАТРУЛЬ (туда-сюда 4 м), ВРАТАРЬ (держит зону перед воротами, следит за
## шайбой). Автоотбор: игрок с шайбой в poke_range -> телеграф (клюшка
## краснеет и тянется) 0.25 с -> если всё ещё рядом, шайба выбита; кулдаун.
## Слой 32 (стены): шайба отскакивает, игрок упирается. Флэт-материалы.

enum { STATIC, PATROL, GOALIE }

const TELEGRAPH_TIME := 0.25
const PATROL_HALF := 2.0    # ±2 м = 4 м пути
const PATROL_SPEED := 1.5
const GOALIE_SPEED := 3.0
const GOALIE_HALF_Z := 2.2  # зона вратаря вдоль ворот
const BODY_COLOR := Color(0.16, 0.22, 0.42)
const ALERT_COLOR := Color(0.92, 0.18, 0.12)

var mode := STATIC
var home := Vector3.ZERO
var mass_kg := 80.0  # масса для силовых (та же формула, что у игрока)

var _player: Player
var _blade: Node3D
var _puck: RigidBody3D
var _params: SkatingParams
var _patrol_dir := 1.0
var _telegraph := 0.0
var _cd := 0.0
var _knock_vel := Vector3.ZERO  # отлёт от силового хита
var _hit_stun := 0.0            # «упал»: наклон визуала, poke не работает
var _hit_cd := 0.0
var _stick_mat := StandardMaterial3D.new()
var _stick: MeshInstance3D


func setup(p_mode: int, p_home: Vector3, player: Player, blade: Node3D,
		puck: RigidBody3D, params: SkatingParams) -> void:
	mode = p_mode
	home = p_home
	_player = player
	_blade = blade
	_puck = puck
	_params = params
	mass_kg = params.player_mass
	sync_to_physics = false
	collision_layer = 32
	collision_mask = 0
	add_to_group("defender")
	global_position = Vector3(home.x, 0.0, home.z)
	_build_body()


func _build_body() -> void:
	# Коллизия: капсула, продлена под лёд (торец на льду подбрасывает шайбу).
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 2.1
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.75, 0.0)
	add_child(shape)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	body_mat.roughness = 1.0
	var torso := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.3
	cyl.height = 1.3
	cyl.material = body_mat
	torso.mesh = cyl
	torso.position = Vector3(0.0, 0.65, 0.0)
	add_child(torso)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	sph.material = body_mat
	head.mesh = sph
	head.position = Vector3(0.0, 1.5, 0.0)
	add_child(head)

	_stick_mat.albedo_color = BODY_COLOR.lightened(0.35)
	_stick_mat.roughness = 1.0
	_stick = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.05, 1.1)
	box.material = _stick_mat
	_stick.mesh = box
	_stick.position = Vector3(0.0, 0.1, -0.75)
	add_child(_stick)


func _physics_process(delta: float) -> void:
	if _player == null or _params == null:
		return
	_cd = maxf(0.0, _cd - delta)
	_hit_cd = maxf(0.0, _hit_cd - delta)
	if _hit_stun > 0.0:
		_hit_stun -= delta
	# «Упал» от хита: наклон корпуса назад на время стана.
	rotation.x = lerpf(rotation.x, -0.55 if _hit_stun > 0.0 else 0.0, 1.0 - exp(-10.0 * delta))
	_move(delta)
	_poke(delta)


## Силовой хит по манекену: отлёт по разнице импульсов + стан.
func take_hit(knock_vel: Vector3, stun: float) -> void:
	knock_vel.y = 0.0
	if knock_vel.length() > 12.0:
		knock_vel = knock_vel.normalized() * 12.0
	_knock_vel = knock_vel
	_hit_stun = stun
	_telegraph = 0.0
	_set_alert(false)


func _move(delta: float) -> void:
	var prev := global_position
	if _hit_stun <= 0.0:
		match mode:
			PATROL:
				var z := global_position.z + _patrol_dir * PATROL_SPEED * delta
				if absf(z - home.z) > PATROL_HALF:
					_patrol_dir = -_patrol_dir
					z = clampf(z, home.z - PATROL_HALF, home.z + PATROL_HALF)
				global_position.z = z
			GOALIE:
				var target_z := clampf(_puck.global_position.z,
						home.z - GOALIE_HALF_Z, home.z + GOALIE_HALF_Z)
				global_position.z = move_toward(global_position.z, target_z, GOALIE_SPEED * delta)
	# Отлёт от хита: интеграция с затуханием, клэмп в коробку катка.
	if _knock_vel.length() > 0.05:
		global_position += _knock_vel * delta
		_knock_vel = _knock_vel.move_toward(Vector3.ZERO, 8.0 * delta)
		global_position.x = clampf(global_position.x,
				-_params.rink_length / 2.0 + 0.6, _params.rink_length / 2.0 - 0.6)
		global_position.z = clampf(global_position.z,
				-_params.rink_width / 2.0 + 0.6, _params.rink_width / 2.0 - 0.6)
	constant_linear_velocity = (global_position - prev) / delta
	# Наезд на игрока: CharacterBody сам не получает контакт, когда стоит.
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if _hit_cd <= 0.0 and constant_linear_velocity.length() > 0.5 \
			and to_player.length() < 0.75:
		_hit_cd = 0.6
		_player.receive_defender_hit(self)
	# Разворот к игроку (телеграф читается по клюшке).
	if to_player.length() > 0.3 and _hit_stun <= 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(to_player.x, to_player.z) + PI, 1.0 - exp(-6.0 * delta))


## Укрывание: игрок в стойке/скольжении корпусом МЕЖДУ манекеном и шайбой —
## выпад упирается в капсулу и шайбу не достаёт.
func _is_shielded() -> bool:
	if not _player.is_shielding or _puck == null:
		return false
	var a := global_position
	var b := _puck.global_position
	a.y = 0.0
	b.y = 0.0
	var ab := b - a
	if ab.length_squared() < 0.01:
		return false
	var pp := _player.global_position
	pp.y = 0.0
	var t := clampf((pp - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return t > 0.05 and t < 0.95 and (a + ab * t - pp).length() < 0.45


func _poke(delta: float) -> void:
	if _hit_stun > 0.0:
		return
	var carried: bool = _blade.puck_state == 1  # CARRIED
	var dist := (_player.global_position - global_position).length()
	if _telegraph > 0.0:
		_telegraph -= delta
		# Клюшка тянется к шайбе — телеграф-замах читается глазами.
		_stick.position.z = lerpf(_stick.position.z, -1.0, 1.0 - exp(-10.0 * delta))
		if _telegraph <= 0.0:
			# Выпад: достаёт, только если шайба не укрыта корпусом.
			if carried and dist < _params.poke_range * 1.15 and not _is_shielded():
				_blade.poke_loose(global_position)
			_cd = _params.poke_cooldown
			_set_alert(false)
		return
	_stick.position.z = lerpf(_stick.position.z, -0.75, 1.0 - exp(-10.0 * delta))
	if carried and _cd <= 0.0 and dist < _params.poke_range and not _is_shielded():
		_telegraph = TELEGRAPH_TIME
		_set_alert(true)


func _set_alert(on: bool) -> void:
	_stick_mat.albedo_color = ALERT_COLOR if on else BODY_COLOR.lightened(0.35)
