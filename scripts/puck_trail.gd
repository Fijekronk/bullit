extends MeshInstance3D
## Лента-трейл за шайбой на скорости > trail_min_speed: СИНИЙ после щелчка
## (заряд > 0.5), ЖЁЛТЫЙ после паса/кистевого. Гаснет за ~0.4 с. Флэт-стиль:
## unshaded, альфа-затухание, без glow. Вкл/выкл — параметр puck_trail_enabled.

const FADE_TIME := 0.4
const WIDTH := 0.09
const COLOR_SLAP := Color(0.25, 0.55, 1.0)
const COLOR_SOFT := Color(1.0, 0.85, 0.25)

var params: SkatingParams
var shot_color := COLOR_SOFT  # main ставит при выстреле

var _puck: RigidBody3D
var _points: Array = []  # [{pos, t}]
var _mesh: ImmediateMesh
var _time := 0.0


func setup(puck: RigidBody3D, p: SkatingParams) -> void:
	_puck = puck
	params = p


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	_time += delta
	if _puck == null or params == null:
		return
	var hv := Vector3(_puck.linear_velocity.x, 0, _puck.linear_velocity.z)
	if params.puck_trail_enabled and hv.length() > params.trail_min_speed:
		_points.append({"pos": _puck.global_position, "t": _time})
	# Чистка устаревших точек.
	while _points.size() > 0 and _time - _points[0].t > FADE_TIME:
		_points.pop_front()
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _points.size() - 1:
		var a: Vector3 = _points[i].pos
		var b: Vector3 = _points[i + 1].pos
		var d := b - a
		d.y = 0.0
		if d.length() < 0.001:
			continue
		var perp := Vector3(-d.z, 0.0, d.x).normalized()
		var age_a: float = clampf(1.0 - (_time - _points[i].t) / FADE_TIME, 0.0, 1.0)
		var age_b: float = clampf(1.0 - (_time - _points[i + 1].t) / FADE_TIME, 0.0, 1.0)
		var wa := perp * WIDTH * 0.5 * age_a
		var wb := perp * WIDTH * 0.5 * age_b
		var ca := Color(shot_color.r, shot_color.g, shot_color.b, 0.7 * age_a)
		var cb := Color(shot_color.r, shot_color.g, shot_color.b, 0.7 * age_b)
		for v in [[a - wa, ca], [a + wa, ca], [b + wb, cb], [a - wa, ca], [b + wb, cb], [b - wb, cb]]:
			_mesh.surface_set_color(v[1])
			_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()
