extends Node3D
## Отладочная визуализация катания (F2): зелёная стрелка velocity,
## красная стрелка facing, скорость над игроком и след за последние 2 сек.
## Узел — ребёнок Player, но top_level: рисуем в мировых координатах.

const TRAIL_SECONDS := 2.0
const ARROW_Y := 0.15
const VELOCITY_SCALE := 0.4  # м стрелки на 1 м/с
const FACING_ARROW_LENGTH := 2.0

const COLOR_VELOCITY := Color(0.25, 1.0, 0.35)
const COLOR_FACING := Color(1.0, 0.25, 0.2)
const COLOR_TRAIL := Color(1.0, 0.9, 0.35)
const COLOR_BLADE_TARGET := Color(0.3, 0.8, 1.0)
const COLOR_ZONE := Color(0.55, 0.75, 1.0, 0.45)

var _player: CharacterBody3D
var _mesh: ImmediateMesh
var _label: Label3D
var _trail: Array[Vector3] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_player = get_parent()
	visible = false

	_mesh = ImmediateMesh.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.outline_size = 8
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_viz"):
		visible = not visible


func _physics_process(_delta: float) -> void:
	var pos := _player.global_position

	# След пишем всегда — чтобы при включении F2 он уже был.
	_trail.append(pos + Vector3(0.0, 0.03, 0.0))
	var max_points := int(TRAIL_SECONDS * Engine.physics_ticks_per_second)
	while _trail.size() > max_points:
		_trail.pop_front()

	if not visible:
		return

	var hvel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	_mesh.clear_surfaces()

	if _trail.size() >= 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in _trail:
			_mesh.surface_set_color(COLOR_TRAIL)
			_mesh.surface_add_vertex(point)
		_mesh.surface_end()

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var origin := pos + Vector3(0.0, ARROW_Y, 0.0)
	_add_arrow(origin, hvel * VELOCITY_SCALE, COLOR_VELOCITY)
	_add_arrow(origin, forward * FACING_ARROW_LENGTH, COLOR_FACING)

	# Линия крюк -> целевая точка: видно отставание крюка от мыши.
	var blade := _player.get_node_or_null("Blade")
	if blade:
		_mesh.surface_set_color(COLOR_BLADE_TARGET)
		_mesh.surface_add_vertex(blade.global_position)
		_mesh.surface_set_color(COLOR_BLADE_TARGET)
		_mesh.surface_add_vertex(blade.target_point + Vector3(0.0, 0.05, 0.0))

	# Контур зоны досягаемости клюшки (следует за facing и хватом).
	if blade:
		var outline: PackedVector3Array = blade.zone_outline()
		var anchor := _player.global_position
		anchor.y = 0.04
		for i in outline.size() - 1:
			_mesh.surface_set_color(COLOR_ZONE)
			_mesh.surface_add_vertex(outline[i])
			_mesh.surface_set_color(COLOR_ZONE)
			_mesh.surface_add_vertex(outline[i + 1])
		# Замыкание через центр: границы запретного сектора.
		for edge_point in [outline[0], outline[outline.size() - 1]]:
			_mesh.surface_set_color(COLOR_ZONE)
			_mesh.surface_add_vertex(anchor)
			_mesh.surface_set_color(COLOR_ZONE)
			_mesh.surface_add_vertex(edge_point)
	_mesh.surface_end()

	_label.global_position = pos + Vector3(0.0, 2.3, 0.0)
	_label.text = "%.1f м/с" % hvel.length()
	if blade:
		_label.text += "\nотн. шайба-крюк: %.1f м/с" % blade.rel_speed


func _add_arrow(origin: Vector3, vec: Vector3, color: Color) -> void:
	if vec.length() < 0.05:
		return
	var tip := origin + vec
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(origin)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(tip)
	# Наконечник — две короткие черты назад под углом.
	var back := -vec.normalized() * minf(0.35, vec.length() * 0.3)
	for side in [1.0, -1.0]:
		var wing := tip + back.rotated(Vector3.UP, side * 0.5)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(tip)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(wing)
