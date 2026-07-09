extends Node3D
## Ледовая коробка. Размеры — параметры (rebuild из панели). Лёд, борта,
## стекло и разметка строятся процедурно. Разметка — flat-геометрия (не
## текстура): масштабируется на любой размер катка без перерисовки PNG.
## Дефолты приходят из SkatingParams (56 x 26, углы R7).

const BOARD_HEIGHT := 1.1
const BOARD_THICKNESS := 0.1
# Коллизия толще визуала (наружу): тонкие стенки шайба на 40+ м/с может
# продавить при зажатии в клин, depenetration выталкивает наружу.
const BOARD_COLLISION_THICKNESS := 0.5
const CORNER_SEGMENTS := 10  # сегментов BoxShape на дугу угла
const STRIPE_HEIGHT := 0.12
# Видимое стекло над бортами (полупрозрачное) + невидимый потолок над всей
# площадкой: шайба никогда не покидает арену.
const GLASS_HEIGHT := 1.2
const CEILING_HEIGHT := 6.0
const GOAL_LINE_FROM_END := 4.0  # линия ворот в 4 м от торцевого борта
const MARK_Y := 0.02

const MARK_RED := Color(0.82, 0.22, 0.27)   # яркая флэт-разметка
const MARK_BLUE := Color(0.22, 0.38, 0.72)

const ICE_PHYSICS := preload("res://assets/materials/ice_physics.tres")
const BOARDS_PHYSICS := preload("res://assets/materials/boards_physics.tres")

var rink_length := 56.0
var rink_width := 26.0
var corner_radius := 7.0

var _board_material := StandardMaterial3D.new()
var _stripe_material := StandardMaterial3D.new()
var _glass_material := StandardMaterial3D.new()
var _glass_body: StaticBody3D
var _built: Array[Node] = []


func _ready() -> void:
	# Флэт-стиль: плоские цвета, roughness 1 (без бликов и PBR-градиентов).
	_board_material.albedo_color = Color(0.93, 0.94, 0.96)
	_board_material.roughness = 1.0
	_stripe_material.albedo_color = Color(0.16, 0.30, 0.72)
	_stripe_material.roughness = 1.0
	_glass_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_material.albedo_color = Color(0.75, 0.88, 0.97, 0.10)
	_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rebuild(rink_length, rink_width, corner_radius)


## Полная пересборка под новые габариты. Всё старое удаляется.
func rebuild(length: float, width: float, corner: float) -> void:
	rink_length = length
	rink_width = width
	corner_radius = minf(corner, minf(length, width) / 2.0 - 0.5)
	for node in _built:
		node.queue_free()
	_built.clear()
	_build_ice()
	_build_markings()
	_build_boards()


## Мировая координата X линии ворот (ворота ставятся на неё).
func goal_line_x() -> float:
	return rink_length / 2.0 - GOAL_LINE_FROM_END


func _track(node: Node) -> Node:
	_built.append(node)
	add_child(node)
	return node


func _build_ice() -> void:
	var body := StaticBody3D.new()
	body.name = "Ice"
	body.physics_material_override = ICE_PHYSICS
	_track(body)

	var box := BoxShape3D.new()
	box.size = Vector3(rink_length + 0.4, 0.2, rink_width + 0.4)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)  # поверхность льда — y = 0
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	mesh.position = shape.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.92, 0.97)  # почти однородный светлый лёд
	material.metallic = 0.0
	material.roughness = 1.0  # флэт: блик минимальный
	mesh.material_override = material
	body.add_child(mesh)


func _build_markings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_length := rink_length / 2.0
	var half_width := rink_width / 2.0
	var goal_x := goal_line_x()

	# Центральная линия поперёк (30 см) + центральный круг и точка.
	_mark_line(st, Vector3(0, 0, -half_width), Vector3(0, 0, half_width), 0.30, MARK_RED)
	_mark_ring(st, Vector3.ZERO, 4.5, 0.10, MARK_BLUE)
	_mark_disc(st, Vector3.ZERO, 0.15, MARK_BLUE)

	# Линии ворот (10 см), обрезаны по границе льда у скруглённого угла.
	var cx := half_length - corner_radius
	var cz := half_width - corner_radius
	var dx := goal_x - cx
	var z_extent := half_width - 0.1
	if dx > 0.0:
		z_extent = cz + sqrt(maxf(corner_radius * corner_radius - dx * dx, 0.0)) - 0.1
	for sx in [-1.0, 1.0]:
		_mark_line(st, Vector3(sx * goal_x, 0, -z_extent), Vector3(sx * goal_x, 0, z_extent), 0.10, MARK_RED)

	# Площадь ворот: полукруг R2.4 от линии ворот в сторону центра.
	_mark_arc(st, Vector3(-goal_x, 0, 0), 2.4, -90.0, 90.0, 0.08, MARK_RED)
	_mark_arc(st, Vector3(goal_x, 0, 0), 2.4, 90.0, 270.0, 0.08, MARK_RED)

	# 4 точки вбрасывания (R0.3), по 2 с каждой стороны.
	var faceoff_x := goal_x - 6.0
	var faceoff_z := half_width * 0.4
	for fx in [-faceoff_x, faceoff_x]:
		for fz in [-faceoff_z, faceoff_z]:
			_mark_disc(st, Vector3(fx, 0, fz), 0.30, MARK_RED)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	st.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "Markings"
	mesh.mesh = st.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track(mesh)


func _mark_line(st: SurfaceTool, from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var dir := (to - from)
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized() * (width / 2.0)
	_quad(st, from - perp, from + perp, to + perp, to - perp, color)


func _mark_ring(st: SurfaceTool, center: Vector3, radius: float, width: float, color: Color) -> void:
	_mark_arc(st, center, radius, 0.0, 360.0, width, color)


func _mark_arc(st: SurfaceTool, center: Vector3, radius: float, a0_deg: float,
		a1_deg: float, width: float, color: Color) -> void:
	var seg := maxi(6, int(absf(a1_deg - a0_deg) / 6.0))
	var r_in := radius - width / 2.0
	var r_out := radius + width / 2.0
	for i in seg:
		var a := deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / seg))
		var b := deg_to_rad(lerpf(a0_deg, a1_deg, float(i + 1) / seg))
		var da := Vector3(cos(a), 0, sin(a))
		var db := Vector3(cos(b), 0, sin(b))
		_quad(st, center + da * r_in, center + da * r_out,
				center + db * r_out, center + db * r_in, color)


func _mark_disc(st: SurfaceTool, center: Vector3, radius: float, color: Color) -> void:
	var seg := 24
	for i in seg:
		var a := TAU * float(i) / seg
		var b := TAU * float(i + 1) / seg
		_tri(st, center,
				center + Vector3(cos(a), 0, sin(a)) * radius,
				center + Vector3(cos(b), 0, sin(b)) * radius, color)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var y := Vector3(0, MARK_Y, 0)
	st.set_color(color)
	st.add_vertex(a + y)
	st.set_color(color)
	st.add_vertex(b + y)
	st.set_color(color)
	st.add_vertex(c + y)


func _build_boards() -> void:
	var body := StaticBody3D.new()
	body.name = "Boards"
	body.physics_material_override = BOARDS_PHYSICS
	body.collision_layer = 32  # слой "стены": борта отдельно от льда
	_track(body)

	_glass_body = StaticBody3D.new()
	_glass_body.name = "Glass"
	var glass_physics := PhysicsMaterial.new()
	glass_physics.friction = 0.05
	glass_physics.bounce = 0.4
	_glass_body.physics_material_override = glass_physics
	_glass_body.collision_layer = 32
	_track(_glass_body)

	_build_ceiling()

	var half_length := rink_length / 2.0
	var half_width := rink_width / 2.0

	# Прямые борта: локальная +Z смотрит наружу (туда смещается коллизия).
	for sz in [-1.0, 1.0]:
		var origin := Vector3(0.0, BOARD_HEIGHT / 2.0, sz * (half_width + BOARD_THICKNESS / 2.0))
		var basis := Basis.IDENTITY if sz > 0.0 else Basis(Vector3.UP, PI)
		_add_board_segment(body, Transform3D(basis, origin), rink_length - 2.0 * corner_radius)

	for sx in [-1.0, 1.0]:
		var origin := Vector3(sx * (half_length + BOARD_THICKNESS / 2.0), BOARD_HEIGHT / 2.0, 0.0)
		_add_board_segment(body, Transform3D(Basis(Vector3.UP, sx * PI / 2.0), origin), rink_width - 2.0 * corner_radius)

	# Скруглённые углы: дуга 90° из коротких касательных сегментов.
	var mid_radius := corner_radius + BOARD_THICKNESS / 2.0
	var step := (PI / 2.0) / float(CORNER_SEGMENTS)
	var segment_length := 2.0 * mid_radius * tan(step / 2.0) * 1.03
	var collision_length := 2.0 * (corner_radius + BOARD_COLLISION_THICKNESS / 2.0) * tan(step / 2.0) * 1.03
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var arc_center := Vector3(sx * (half_length - corner_radius), 0.0, sz * (half_width - corner_radius))
			for i in CORNER_SEGMENTS:
				var angle := (float(i) + 0.5) * step
				var normal := Vector3(sx * cos(angle), 0.0, sz * sin(angle))
				var origin := arc_center + normal * mid_radius + Vector3(0.0, BOARD_HEIGHT / 2.0, 0.0)
				var basis := Basis(Vector3.UP, atan2(normal.x, normal.z))
				_add_board_segment(body, Transform3D(basis, origin), segment_length, collision_length)


func _build_ceiling() -> void:
	# Невидимый потолок над всей площадкой: шайба не покидает арену вверх.
	var body := StaticBody3D.new()
	body.name = "Ceiling"
	var phys := PhysicsMaterial.new()
	phys.friction = 0.5
	phys.bounce = 0.1
	body.physics_material_override = phys
	body.collision_layer = 32
	_track(body)
	var box := BoxShape3D.new()
	box.size = Vector3(rink_length + 4.0, 0.4, rink_width + 4.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, CEILING_HEIGHT, 0.0)
	body.add_child(shape)


func _add_board_segment(body: StaticBody3D, xform: Transform3D, length: float,
		collision_length: float = -1.0) -> void:
	# Коллизия толще визуальной панели и смещена наружу (внутренняя грань — на границе).
	var box := BoxShape3D.new()
	box.size = Vector3(collision_length if collision_length > 0.0 else length,
			BOARD_HEIGHT, BOARD_COLLISION_THICKNESS)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = xform.translated_local(
			Vector3(0.0, 0.0, (BOARD_COLLISION_THICKNESS - BOARD_THICKNESS) / 2.0))
	body.add_child(shape)

	# Коллизия стекла — невидимо ВВЕРХ до потолка (иначе шайба уходит боком выше
	# видимой панели). Bounce как у стекла.
	var wall_h := CEILING_HEIGHT - BOARD_HEIGHT
	var glass_box := BoxShape3D.new()
	glass_box.size = Vector3(box.size.x, wall_h, BOARD_COLLISION_THICKNESS)
	var glass_shape := CollisionShape3D.new()
	glass_shape.shape = glass_box
	glass_shape.transform = shape.transform.translated_local(Vector3(0.0, BOARD_HEIGHT / 2.0 + wall_h / 2.0, 0.0))
	_glass_body.add_child(glass_shape)

	# Видимая полупрозрачная панель — только нижние GLASS_HEIGHT метров.
	var glass_mesh := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(length, GLASS_HEIGHT, 0.03)
	glass_mesh.mesh = gm
	glass_mesh.material_override = _glass_material
	glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass_mesh.transform = xform.translated_local(Vector3(0.0, (BOARD_HEIGHT + GLASS_HEIGHT) / 2.0, 0.0))
	_glass_body.add_child(glass_mesh)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = box.size
	panel.mesh = panel_mesh
	panel.material_override = _board_material
	panel.transform = xform
	body.add_child(panel)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(length + 0.02, STRIPE_HEIGHT, BOARD_THICKNESS + 0.02)
	stripe.mesh = stripe_mesh
	stripe.material_override = _stripe_material
	stripe.transform = xform.translated_local(Vector3(0.0, (BOARD_HEIGHT - STRIPE_HEIGHT) / 2.0 + 0.001, 0.0))
	body.add_child(stripe)
