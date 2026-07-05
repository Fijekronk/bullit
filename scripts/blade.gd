extends AnimatableBody3D
## Крюк на мыши. Принципы этапа 3: шайба НИКОГДА не прилипает (только силы),
## крюк НИКОГДА не телепортируется (скорость и ускорение ограничены).
## Мышь задаёт цель в кольце досягаемости вокруг игрока; помощь ведению —
## демпфирование относительной скорости шайба↔крюк, никогда позиции.
## Ребёнок Player (top_level): тик игрока уже отработал — кольцо актуально.

const BLADE_SIZE := Vector3(0.30, 0.08, 0.035)  # длина x высота x толщина (визуал)
const BLADE_Y := 0.05  # центр: нижняя грань визуала в 1 см надо льдом
# Коллизия продлена вниз до самого льда: под крюком не должно быть щели,
# куда шайба (высота 2.5 см) подныривает и клинится между крюком и льдом —
# depenetration выстреливала её вверх.
const BLADE_COLLISION_SIZE := Vector3(0.30, 0.10, 0.035)
const SHAFT_RADIUS := 0.02
const HAND_HEIGHT := 1.05

# Аналитический клэмп в пределах коробки (борта — этими же константами
# строится каток в rink.gd). Кинематическое тело не остановится о статику
# само, поэтому "упирается в борт" реализовано геометрически.
const RINK_HALF_LENGTH := 20.0
const RINK_HALF_WIDTH := 10.0
const CORNER_RADIUS := 4.0
const WALL_MARGIN := 0.18

const COLOR_IDLE := Color(0.12, 0.12, 0.14)
const COLOR_ASSIST := Color(0.2, 0.85, 0.35)
const COLOR_CATCH := Color(0.2, 0.65, 1.0)
# Горизонт предсказания траектории шайбы. Короткий — приём включается,
# когда контакт неминуем (несколько тиков), а не глушит шайбу за метры.
const CATCH_LOOKAHEAD := 0.08

## Для автотестов: конечная точка вместо курсора мыши (Vector3.INF = мышь).
var cursor_override := Vector3.INF

var blade_velocity := Vector3.ZERO
var target_point := Vector3.ZERO
var cursor_point := Vector3.ZERO
var assist_active := false
var catch_active := false
var rel_speed := 0.0

var _player: CharacterBody3D
var _debug_viz: Node3D
var _blade_material := StandardMaterial3D.new()
var _shaft: MeshInstance3D
var _marker: MeshInstance3D
var _box := BoxShape3D.new()


func _ready() -> void:
	_player = get_parent()
	_debug_viz = _player.get_node("DebugViz")

	_blade_material.albedo_color = COLOR_IDLE
	_blade_material.roughness = 0.5

	_box.size = BLADE_COLLISION_SIZE
	var shape := CollisionShape3D.new()
	shape.shape = _box
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = BLADE_SIZE
	mesh.mesh = box_mesh
	mesh.material_override = _blade_material
	add_child(mesh)

	# Палка от капсулы к крюку — чистый декор, без коллизии.
	_shaft = MeshInstance3D.new()
	_shaft.top_level = true
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = SHAFT_RADIUS
	cylinder.bottom_radius = SHAFT_RADIUS
	cylinder.height = 1.0  # масштабируется по факту
	cylinder.radial_segments = 10
	var shaft_material := StandardMaterial3D.new()
	shaft_material.albedo_color = Color(0.5, 0.35, 0.18)
	shaft_material.roughness = 0.8
	cylinder.material = shaft_material
	_shaft.mesh = cylinder
	add_child(_shaft)

	# Маркер точки курсора на льду (виден всегда).
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

	var start := _player.global_position
	global_position = Vector3(start.x, BLADE_Y, start.z - 1.0)
	target_point = Vector3(start.x, 0.0, start.z - 1.0)
	cursor_point = target_point


func _physics_process(delta: float) -> void:
	var params: SkatingParams = _player.params
	var anchor := _player.global_position
	anchor.y = 0.0

	_update_cursor()

	# Цель крюка: курсор, зажатый в асимметричную зону досягаемости
	# (сектор форхенда/бэкхенда вокруг facing, зеркалится по хвату),
	# со слабым экспоненциальным сглаживанием против дрожи руки.
	var offset := cursor_point - anchor
	offset.y = 0.0
	var raw_target := target_point
	if offset.length() > 0.001:
		raw_target = anchor + _clamp_to_zone(offset, params)
	target_point = target_point.lerp(raw_target, 1.0 - exp(-params.stick_smoothing * delta))

	# Движение к цели: скорость и ускорение ограничены — резкий рывок мыши
	# даёт быстрый, но конечный проезд крюка (может и промахнуться).
	var pos := global_position
	pos.y = 0.0
	var desired_velocity := (target_point - pos) / delta
	if desired_velocity.length() > params.blade_max_speed:
		desired_velocity = desired_velocity.normalized() * params.blade_max_speed
	blade_velocity = blade_velocity.move_toward(desired_velocity, params.blade_max_accel * delta)
	var new_pos := _clamp_to_rink(pos + blade_velocity * delta)
	blade_velocity = (new_pos - pos) / delta  # фактическая скорость после клэмпа

	# Длинная сторона крюка перпендикулярна лучу игрок→крюк.
	var outward := new_pos - anchor
	if outward.length() > 0.05:
		rotation = Vector3(0.0, atan2(outward.x, outward.z), 0.0)

	# Быстрый проезд: шаг крюка за тик больше окна контакта с шайбой,
	# солвер такой удар не увидит — ловим самим свипом.
	_resolve_fast_sweep(pos, new_pos)

	global_position = Vector3(new_pos.x, BLADE_Y, new_pos.z)
	# Скорость крюка для солвера: контакты шайбы с крюком считаются так,
	# будто "статичное" тело движется с этой скоростью.
	constant_linear_velocity = blade_velocity

	_apply_assist(params)
	_update_visuals(anchor)


func _resolve_fast_sweep(from: Vector3, to: Vector3) -> void:
	var motion := to - from
	if motion.length() < 0.06:
		return  # медленный крюк корректно обрабатывает сам солвер
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
		return  # медленное сближение — оставляем физике и помощи
	puck.apply_central_impulse(dir * rel * 1.05 * puck.mass)


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
	var t := -origin.y / normal.y  # пересечение с плоскостью льда y = 0
	if t > 0.0:
		cursor_point = origin + normal * t


## Азимутальная зона досягаемости. Координата e — угол от "прямо вперёд"
## по facing игрока, положительное направление — сторона хвата.
## Форхенд: e in [0, forehand_arc], полный радиус. Бэкхенд: e in
## [-backhand_arc, 0], радиус плавно падает до backhand_reach. Остальное —
## запретная зона: азимут зажимается к ближайшему краю.
func _clamp_to_zone(offset: Vector3, params: SkatingParams) -> Vector3:
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var dist := offset.length()
	var hand_sign := -1.0 if params.handedness_right else 1.0  # e>0 — сторона хвата
	var e := rad_to_deg(forward.signed_angle_to(offset / dist, Vector3.UP)) * hand_sign

	var fa: float = params.forehand_arc
	var ba: float = params.backhand_arc
	var covered := (e >= 0.0 and e <= fa) or (e < 0.0 and e >= -ba) \
			or (fa > 180.0 and e <= fa - 360.0)
	if not covered:
		# Запретная зона: к ближайшему краю по дуге.
		var fa_edge := fa if fa <= 180.0 else fa - 360.0
		var to_fore := absf(wrapf(e - fa_edge, -180.0, 180.0))
		var to_back := absf(wrapf(e + ba, -180.0, 180.0))
		e = fa_edge if to_fore < to_back else -ba
	var reach := zone_reach(e, params)
	var azimuth := deg_to_rad(e * hand_sign)  # обратно в мировой знак
	return forward.rotated(Vector3.UP, azimuth) * clampf(dist, params.stick_min_reach, reach)


## Радиус зоны на азимуте e (в "хватовых" градусах, e уже в покрытом секторе).
func zone_reach(e: float, params: SkatingParams) -> float:
	if e >= 0.0 or e <= -params.backhand_arc:
		return params.stick_max_reach
	var t: float = absf(e) / params.backhand_arc
	return lerpf(params.stick_max_reach, params.backhand_reach, smoothstep(0.0, 1.0, t))


## Контур зоны для F2-отрисовки (мировые точки на льду).
func zone_outline(steps := 48) -> PackedVector3Array:
	var points := PackedVector3Array()
	var params: SkatingParams = _player.params
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var hand_sign := -1.0 if params.handedness_right else 1.0
	var anchor := _player.global_position
	anchor.y = 0.04
	for i in steps + 1:
		var e := lerpf(-params.backhand_arc, params.forehand_arc, float(i) / steps)
		var dir := forward.rotated(Vector3.UP, deg_to_rad(e * hand_sign))
		points.append(anchor + dir * zone_reach(e, params))
	return points


func _apply_assist(params: SkatingParams) -> void:
	# "Мягкие руки": при близком и медленном (относительно крюка) контакте
	# демпфируем относительную скорость силой (никогда позицию). Плюс режим
	# автоприёма: сближающаяся шайба, чья траектория проходит рядом с крюком,
	# гасится сильнее. Быстрый рывок крюком (флик) не душим — там чистый удар.
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

	# Штатная помощь ведению.
	if to_puck.length() <= params.assist_radius and rel_speed <= params.assist_max_rel_speed:
		assist_active = true
		_apply_damping_force(puck, rel, params.assist_strength, params.assist_max_force)
		return

	# Автоприём: только когда шайба СБЛИЖАЕТСЯ (флики не душим).
	if rel_speed < 0.01 or rel_speed > params.catch_max_rel_speed:
		return
	if rel.dot(to_puck) >= 0.0:
		return  # удаляется
	# Ближайшая точка предсказанной траектории шайбы относительно крюка.
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


func _clamp_to_rink(p: Vector3) -> Vector3:
	var hx := RINK_HALF_LENGTH - WALL_MARGIN
	var hz := RINK_HALF_WIDTH - WALL_MARGIN
	p.x = clampf(p.x, -hx, hx)
	p.z = clampf(p.z, -hz, hz)
	var cx := RINK_HALF_LENGTH - CORNER_RADIUS
	var cz := RINK_HALF_WIDTH - CORNER_RADIUS
	if absf(p.x) > cx and absf(p.z) > cz:
		var center := Vector3(signf(p.x) * cx, 0.0, signf(p.z) * cz)
		var d := p - center
		var r := CORNER_RADIUS - WALL_MARGIN
		if d.length() > r:
			p = center + d.normalized() * r
	return p


func _update_visuals(anchor: Vector3) -> void:
	# Индикация помощи/приёма — только при включённой F2-визуализации.
	if _debug_viz.visible and catch_active:
		_blade_material.albedo_color = COLOR_CATCH
	elif _debug_viz.visible and assist_active:
		_blade_material.albedo_color = COLOR_ASSIST
	else:
		_blade_material.albedo_color = COLOR_IDLE

	var hand := anchor + Vector3(0.0, HAND_HEIGHT, 0.0)
	var tip := global_position + Vector3(0.0, BLADE_SIZE.y / 2.0, 0.0)
	var span := tip - hand
	var length := span.length()
	if length > 0.01:
		var dir := span / length
		var axis := Vector3.UP.cross(dir)
		var basis := Basis.IDENTITY
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
		_shaft.global_transform = Transform3D(
				basis * Basis.from_scale(Vector3(1.0, length, 1.0)), (hand + tip) / 2.0)

	_marker.global_position = Vector3(cursor_point.x, 0.01, cursor_point.z)
