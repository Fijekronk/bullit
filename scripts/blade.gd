extends AnimatableBody3D
## Крюк на мыши, модель "дуга фиксированного радиуса" (этап 3.6): курсор задаёт
## ТОЛЬКО азимут крюка вокруг точки хвата (pivot), радиус ≈ stick_length с малым
## люфтом reach_variation. Азимут ограничен жёстким сектором [backhand_limit..
## forehand_limit] относительно facing (зеркалится по хвату); текущий азимут
## ведётся к целевому ТОЛЬКО внутри сектора (через фронт), без прыжка за спину.
## Принципы этапа 3 сохранены: шайба не прилипает (только силы), крюк не
## телепортируется (лимиты скорости/ускорения). Помощь/приём — без изменений.

const BLADE_COLLISION_SIZE := Vector3(0.30, 0.10, 0.035)  # коллизия (не трогаем)
const BLADE_Y := 0.05
const HAND_HEIGHT := 1.0  # высота "рук" на капсуле для шафта

const WALL_MARGIN := 0.18

const COLOR_IDLE := Color(0.12, 0.12, 0.14)
const COLOR_ASSIST := Color(0.2, 0.85, 0.35)
const COLOR_CATCH := Color(0.2, 0.65, 1.0)
const CATCH_LOOKAHEAD := 0.08

## Для автотестов: конечная точка вместо курсора мыши (Vector3.INF = мышь).
var cursor_override := Vector3.INF

var blade_velocity := Vector3.ZERO
var target_point := Vector3.ZERO
var cursor_point := Vector3.ZERO
var pivot_point := Vector3.ZERO
var azimuth := 0.0        # текущий азимут крюка, "хватовые" градусы в секторе
var assist_active := false
var catch_active := false
var rel_speed := 0.0

var _player: CharacterBody3D
var _debug_viz: Node3D
var _blade_material := StandardMaterial3D.new()
var _shaft: MeshInstance3D
var _marker: MeshInstance3D
var _box := BoxShape3D.new()
var _azimuth_rate := 0.0
var _radius := 1.35


func _ready() -> void:
	_player = get_parent()
	_debug_viz = _player.get_node("DebugViz")

	_box.size = BLADE_COLLISION_SIZE
	var shape := CollisionShape3D.new()
	shape.shape = _box
	add_child(shape)

	_build_blade_visual()
	_build_shaft()
	_build_marker()

	var params: SkatingParams = _player.params
	_radius = params.stick_length
	azimuth = 0.0
	var start := _player.global_position
	global_position = Vector3(start.x, BLADE_Y, start.z - _radius)
	target_point = global_position
	cursor_point = target_point
	pivot_point = start


func _physics_process(delta: float) -> void:
	var params: SkatingParams = _player.params
	var forward := _forward()
	pivot_point = _compute_pivot(params, forward)

	_update_cursor()

	# --- Азимут: курсор задаёт направление; цель клэмпится в жёсткий сектор,
	#     текущий азимут ведётся к ней внутри сектора с лимитами (через фронт).
	var to_cursor := cursor_point - pivot_point
	to_cursor.y = 0.0
	if to_cursor.length() > 0.001:
		var e_raw := _signed_e(forward, to_cursor.normalized(), params)
		var e_target := _clamp_azimuth(e_raw, params)
		_advance_azimuth(e_target, params, delta)

	# --- Радиус: только люфт вокруг stick_length, мягкая зависимость.
	var raw_radius := _radius_from_distance(to_cursor.length(), params)
	_radius = lerpf(_radius, raw_radius, 1.0 - exp(-params.stick_smoothing * delta))

	var dir := _dir_from_e(azimuth, forward, params)
	target_point = pivot_point + dir * _radius
	target_point.y = 0.0

	# --- Движение к точке на дуге: лимиты скорости/ускорения (крюк не телепорт).
	var pos := global_position
	pos.y = 0.0
	var desired_velocity := (target_point - pos) / delta
	if desired_velocity.length() > params.blade_max_speed:
		desired_velocity = desired_velocity.normalized() * params.blade_max_speed
	blade_velocity = blade_velocity.move_toward(desired_velocity, params.blade_max_accel * delta)
	var new_pos := _clamp_to_rink(pos + blade_velocity * delta, params)
	blade_velocity = (new_pos - pos) / delta

	var outward := new_pos - pivot_point
	if outward.length() > 0.05:
		rotation = Vector3(0.0, atan2(outward.x, outward.z), 0.0)

	_resolve_fast_sweep(pos, new_pos)

	global_position = Vector3(new_pos.x, BLADE_Y, new_pos.z)
	constant_linear_velocity = blade_velocity

	_apply_assist(params)
	_update_visuals()


# --- Геометрия дуги ---------------------------------------------------------

func _compute_pivot(params: SkatingParams, forward: Vector3) -> Vector3:
	var right := forward.rotated(Vector3.UP, -PI / 2.0)  # право игрока
	var hand := right if params.handedness_right else -right
	var p := _player.global_position + hand * params.hand_offset_side + forward * params.hand_offset_forward
	p.y = 0.0
	return p


## Азимут точки в "хватовых" градусах: 0 — прямо вперёд, + — сторона хвата.
func _signed_e(forward: Vector3, dir: Vector3, params: SkatingParams) -> float:
	var hand_sign := -1.0 if params.handedness_right else 1.0
	return rad_to_deg(forward.signed_angle_to(dir, Vector3.UP)) * hand_sign


func _dir_from_e(e: float, forward: Vector3, params: SkatingParams) -> Vector3:
	var hand_sign := -1.0 if params.handedness_right else 1.0
	return forward.rotated(Vector3.UP, deg_to_rad(e * hand_sign))


## Клэмп целевого азимута в сектор [backhand_limit, forehand_limit].
## Возвращает значение в [bl, fl]; в запретной дуге — ближайшая граница.
func _clamp_azimuth(e_raw: float, params: SkatingParams) -> float:
	var bl: float = params.backhand_limit
	var fl: float = params.forehand_limit
	var e := e_raw
	while e < bl:
		e += 360.0
	while e >= bl + 360.0:
		e -= 360.0
	if e <= fl:
		return e
	# Запретная дуга (fl, bl+360): к ближайшей границе.
	return fl if (e - fl) <= (bl + 360.0 - e) else bl


## Ведёт текущий азимут к цели внутри сектора с лимитами (из скорости/ускорения
## крюка, пересчитанных в угловые через радиус) — движение по дуге, не по хорде.
func _advance_azimuth(e_target: float, params: SkatingParams, delta: float) -> void:
	var r := maxf(_radius, 0.2)
	var max_rate := rad_to_deg(params.blade_max_speed / r)
	var max_accel := rad_to_deg(params.blade_max_accel / r)
	var diff := e_target - azimuth  # оба в [bl, fl] — путь линеен и в секторе
	var stop_rate := sqrt(2.0 * max_accel * absf(diff))
	var desired_rate := signf(diff) * minf(max_rate, stop_rate)
	_azimuth_rate = move_toward(_azimuth_rate, desired_rate, max_accel * delta)
	azimuth = clampf(azimuth + _azimuth_rate * delta, params.backhand_limit, params.forehand_limit)


func _radius_from_distance(dist: float, params: SkatingParams) -> float:
	if params.reach_variation <= 0.0:
		return params.stick_length
	var lo := params.stick_length - params.reach_variation
	var hi := params.stick_length + params.reach_variation
	var t := clampf((dist - lo) / (hi - lo), 0.0, 1.0)
	return lerpf(lo, hi, smoothstep(0.0, 1.0, t))


## Контур сектора для F2: дуга по границе досягаемости + две граничные линии.
func zone_outline(steps := 48) -> PackedVector3Array:
	var points := PackedVector3Array()
	var params: SkatingParams = _player.params
	var forward := _forward()
	for i in steps + 1:
		var e := lerpf(params.backhand_limit, params.forehand_limit, float(i) / steps)
		points.append(pivot_point + _dir_from_e(e, forward, params) * params.stick_length \
				+ Vector3(0.0, 0.04, 0.0))
	return points


# --- Ввод и физика ----------------------------------------------------------

func _update_cursor() -> void:
	if cursor_override.is_finite():
		cursor_point = cursor_override
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	if absf(normal.y) < 0.0001:
		return
	var t := -origin.y / normal.y
	if t > 0.0:
		cursor_point = origin + normal * t


func _resolve_fast_sweep(from: Vector3, to: Vector3) -> void:
	var motion := to - from
	if motion.length() < 0.06:
		return
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _box
	query.transform = Transform3D(global_transform.basis, Vector3(from.x, BLADE_Y, from.z))
	query.motion = motion
	query.collision_mask = 2  # только шайба
	var result := get_world_3d().direct_space_state.cast_motion(query)
	if result[0] >= 1.0:
		return
	var dir := motion.normalized()
	var rel := (blade_velocity - puck.linear_velocity).dot(dir)
	if rel <= 4.0:
		return
	puck.apply_central_impulse(dir * rel * 1.05 * puck.mass)


func _apply_assist(params: SkatingParams) -> void:
	# "Мягкие руки" + автоприём — логика без изменений с этапа 3.5.
	assist_active = false
	catch_active = false
	rel_speed = 0.0
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	var rel := puck.linear_velocity - blade_velocity
	rel.y = 0.0
	rel_speed = rel.length()
	var to_puck := puck.global_position - global_position
	to_puck.y = 0.0

	if to_puck.length() <= params.assist_radius and rel_speed <= params.assist_max_rel_speed:
		assist_active = true
		_apply_damping_force(puck, rel, params.assist_strength, params.assist_max_force)
		return

	if rel_speed < 0.01 or rel_speed > params.catch_max_rel_speed:
		return
	if rel.dot(to_puck) >= 0.0:
		return  # удаляется — флики не душим
	var t_close := clampf(-to_puck.dot(rel) / (rel_speed * rel_speed), 0.0, CATCH_LOOKAHEAD)
	var closest := (to_puck + rel * t_close).length()
	if closest > params.catch_radius:
		return
	catch_active = true
	_apply_damping_force(puck, rel, params.catch_strength, params.catch_max_force)


func _apply_damping_force(puck: RigidBody3D, rel: Vector3, strength: float, max_force: float) -> void:
	var force := -strength * rel
	if force.length() > max_force:
		force = force.normalized() * max_force
	puck.apply_central_force(force)


func _clamp_to_rink(p: Vector3, params: SkatingParams) -> Vector3:
	var hx := params.rink_length / 2.0 - WALL_MARGIN
	var hz := params.rink_width / 2.0 - WALL_MARGIN
	p.x = clampf(p.x, -hx, hx)
	p.z = clampf(p.z, -hz, hz)
	var cr: float = params.corner_radius
	var cx := params.rink_length / 2.0 - cr
	var cz := params.rink_width / 2.0 - cr
	if absf(p.x) > cx and absf(p.z) > cz:
		var center := Vector3(signf(p.x) * cx, 0.0, signf(p.z) * cz)
		var d := p - center
		var r := cr - WALL_MARGIN
		if d.length() > r:
			p = center + d.normalized() * r
	return p


func _forward() -> Vector3:
	var f := -_player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


# --- Визуал -----------------------------------------------------------------

func _build_blade_visual() -> void:
	# Изогнутый крюк: пятка + носок под углом ~15°, "лента" на лицевой грани.
	# Изгиб в сторону хвата (знак зависит от хватовой ориентации локальных осей).
	_blade_material.albedo_color = COLOR_IDLE
	_blade_material.roughness = 0.5
	var params: SkatingParams = _player.params
	var bend := deg_to_rad(15.0) * (1.0 if params.handedness_right else -1.0)

	var heel_len := 0.20
	var toe_len := 0.17
	var height := 0.10
	var thick := 0.03

	var heel := _blade_box(Vector3(heel_len, height, thick), _blade_material)
	heel.transform = Transform3D(Basis.IDENTITY, Vector3(-heel_len / 2.0, 0.0, 0.0))
	add_child(heel)

	var toe := _blade_box(Vector3(toe_len, height, thick), _blade_material)
	var toe_basis := Basis(Vector3.UP, bend)
	toe.transform = Transform3D(toe_basis, Vector3(toe_len / 2.0 * cos(bend), 0.0, -toe_len / 2.0 * sin(bend) * 0.0))
	add_child(toe)

	# Лента — светлая полоса на лицевой (+Z) грани, слегка выступает.
	var tape_material := StandardMaterial3D.new()
	tape_material.albedo_color = Color(0.9, 0.92, 0.95)
	tape_material.roughness = 0.6
	var tape := _blade_box(Vector3(heel_len + toe_len, height * 0.45, thick + 0.006), tape_material)
	tape.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -height * 0.2, 0.0))
	add_child(tape)


func _blade_box(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	return mesh


func _build_shaft() -> void:
	_shaft = MeshInstance3D.new()
	_shaft.top_level = true
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 1.0, 0.03)  # масштабируется по длине
	var shaft_material := StandardMaterial3D.new()
	shaft_material.albedo_color = Color(0.10, 0.10, 0.12)  # графит
	shaft_material.roughness = 0.4
	box.material = shaft_material
	_shaft.mesh = box
	add_child(_shaft)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = 0.06
	disc.bottom_radius = 0.06
	disc.height = 0.004
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	disc.material = marker_material
	_marker.mesh = disc
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func _update_visuals() -> void:
	if _debug_viz.visible and catch_active:
		_blade_material.albedo_color = COLOR_CATCH
	elif _debug_viz.visible and assist_active:
		_blade_material.albedo_color = COLOR_ASSIST
	else:
		_blade_material.albedo_color = COLOR_IDLE

	# Шафт: от "рук" (на капсуле, сторона хвата, ~1.0 м) к пятке крюка.
	var params: SkatingParams = _player.params
	var forward := _forward()
	var right := forward.rotated(Vector3.UP, -PI / 2.0)
	var hand := right if params.handedness_right else -right
	var hands := _player.global_position + hand * params.hand_offset_side + Vector3(0.0, HAND_HEIGHT, 0.0)
	var heel := global_position + (global_position - pivot_point).normalized() * 0.10
	heel.y = BLADE_Y
	var span := heel - hands
	var length := span.length()
	if length > 0.01:
		var dir := span / length
		var axis := Vector3.UP.cross(dir)
		var basis := Basis.IDENTITY
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		_shaft.global_transform = Transform3D(
				basis * Basis.from_scale(Vector3(1.0, length, 1.0)), (hands + heel) / 2.0)

	_marker.global_position = Vector3(cursor_point.x, 0.01, cursor_point.z)
