extends Node3D
## Ледовая коробка 3v3: 40 x 20 м, углы скруглены радиусом 4 м.
## Лёд, борта и разметка строятся процедурно в _ready — размеры в константах.

const RINK_LENGTH := 40.0
const RINK_WIDTH := 20.0
const CORNER_RADIUS := 4.0
const BOARD_HEIGHT := 1.1
const BOARD_THICKNESS := 0.1
# Коллизия толще визуала (наружу): тонкие стенки шайба на 40+ м/с может
# продавить при зажатии в клин "лёд + сетка", depenetration выталкивает наружу.
const BOARD_COLLISION_THICKNESS := 0.5
const CORNER_SEGMENTS := 8  # сегментов BoxShape на каждую дугу угла
const STRIPE_HEIGHT := 0.12  # синяя полоса по верхней кромке борта

const ICE_PHYSICS := preload("res://assets/materials/ice_physics.tres")
const BOARDS_PHYSICS := preload("res://assets/materials/boards_physics.tres")

# Невидимое "стекло" над бортами: редкие рикошеты подбрасывают шайбу чуть
# выше борта (1.1–1.5 м), а правил аута нет — шайба не должна покидать игру.
const GLASS_HEIGHT := 3.0
var _glass_body: StaticBody3D

var _board_material := StandardMaterial3D.new()
var _stripe_material := StandardMaterial3D.new()


func _ready() -> void:
	_board_material.albedo_color = Color(0.92, 0.93, 0.95)
	_board_material.roughness = 0.6
	_stripe_material.albedo_color = Color(0.13, 0.26, 0.72)
	_stripe_material.roughness = 0.5
	_build_ice()
	_build_markings()
	_build_boards()


func _build_ice() -> void:
	var body := StaticBody3D.new()
	body.name = "Ice"
	body.physics_material_override = ICE_PHYSICS
	add_child(body)

	# Плита чуть шире катка, чтобы под бортами не было щели.
	var box := BoxShape3D.new()
	box.size = Vector3(RINK_LENGTH + 0.4, 0.2, RINK_WIDTH + 0.4)
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
	material.albedo_color = Color(0.82, 0.90, 0.96)
	material.metallic = 0.0
	material.roughness = 0.07
	mesh.material_override = material
	body.add_child(mesh)


func _build_markings() -> void:
	# Разметка — отдельная плоскость с alpha-текстурой чуть выше льда.
	var mesh := MeshInstance3D.new()
	mesh.name = "Markings"
	var plane := PlaneMesh.new()
	plane.size = Vector2(RINK_LENGTH, RINK_WIDTH)
	mesh.mesh = plane
	mesh.position = Vector3(0.0, 0.002, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/rink_markings.png")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.0
	material.roughness = 0.07
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _build_boards() -> void:
	var body := StaticBody3D.new()
	body.name = "Boards"
	body.physics_material_override = BOARDS_PHYSICS
	body.collision_layer = 32  # слой "стены": борта отдельно от льда
	add_child(body)

	_glass_body = StaticBody3D.new()
	_glass_body.name = "Glass"
	var glass_physics := PhysicsMaterial.new()
	glass_physics.friction = 0.05
	glass_physics.bounce = 0.3
	_glass_body.physics_material_override = glass_physics
	_glass_body.collision_layer = 32
	add_child(_glass_body)

	var half_length := RINK_LENGTH / 2.0
	var half_width := RINK_WIDTH / 2.0

	# Прямые борта вдоль длинных сторон. Базис повёрнут так, чтобы локальная
	# +Z всегда смотрела наружу катка — туда смещается утолщённая коллизия.
	for sz in [-1.0, 1.0]:
		var origin := Vector3(0.0, BOARD_HEIGHT / 2.0, sz * (half_width + BOARD_THICKNESS / 2.0))
		var basis := Basis.IDENTITY if sz > 0.0 else Basis(Vector3.UP, PI)
		_add_board_segment(body, Transform3D(basis, origin), RINK_LENGTH - 2.0 * CORNER_RADIUS)

	# Прямые торцевые борта.
	for sx in [-1.0, 1.0]:
		var origin := Vector3(sx * (half_length + BOARD_THICKNESS / 2.0), BOARD_HEIGHT / 2.0, 0.0)
		_add_board_segment(body, Transform3D(Basis(Vector3.UP, sx * PI / 2.0), origin), RINK_WIDTH - 2.0 * CORNER_RADIUS)

	# Скруглённые углы: дуга 90° из коротких сегментов, касательных к окружности.
	var mid_radius := CORNER_RADIUS + BOARD_THICKNESS / 2.0
	var step := (PI / 2.0) / float(CORNER_SEGMENTS)
	# Длина хорды с небольшим запасом, чтобы стыки сегментов перекрывались.
	var segment_length := 2.0 * mid_radius * tan(step / 2.0) * 1.03
	var collision_length := 2.0 * (CORNER_RADIUS + BOARD_COLLISION_THICKNESS / 2.0) * tan(step / 2.0) * 1.03
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var arc_center := Vector3(sx * (half_length - CORNER_RADIUS), 0.0, sz * (half_width - CORNER_RADIUS))
			for i in CORNER_SEGMENTS:
				var angle := (float(i) + 0.5) * step
				var normal := Vector3(sx * cos(angle), 0.0, sz * sin(angle))
				var origin := arc_center + normal * mid_radius + Vector3(0.0, BOARD_HEIGHT / 2.0, 0.0)
				var basis := Basis(Vector3.UP, atan2(normal.x, normal.z))  # локальная Z — наружу
				_add_board_segment(body, Transform3D(basis, origin), segment_length, collision_length)


func _add_board_segment(body: StaticBody3D, xform: Transform3D, length: float,
		collision_length: float = -1.0) -> void:
	# Коллизия: длина по локальной X, толщина по локальной Z. Бокс толще
	# визуальной панели и смещён наружу — внутренняя грань совпадает с панелью.
	var box := BoxShape3D.new()
	box.size = Vector3(collision_length if collision_length > 0.0 else length,
			BOARD_HEIGHT, BOARD_COLLISION_THICKNESS)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = xform.translated_local(
			Vector3(0.0, 0.0, (BOARD_COLLISION_THICKNESS - BOARD_THICKNESS) / 2.0))
	body.add_child(shape)

	# Невидимое стекло — продолжение борта вверх (коллизия без визуала).
	var glass_box := BoxShape3D.new()
	glass_box.size = Vector3(box.size.x, GLASS_HEIGHT, BOARD_COLLISION_THICKNESS)
	var glass_shape := CollisionShape3D.new()
	glass_shape.shape = glass_box
	glass_shape.transform = shape.transform.translated_local(
			Vector3(0.0, (BOARD_HEIGHT + GLASS_HEIGHT) / 2.0, 0.0))
	_glass_body.add_child(glass_shape)

	# Белая панель.
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = box.size
	panel.mesh = panel_mesh
	panel.material_override = _board_material
	panel.transform = xform
	body.add_child(panel)

	# Синяя полоса по верхней кромке (чуть шире панели, чтобы не мерцала).
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(length + 0.02, STRIPE_HEIGHT, BOARD_THICKNESS + 0.02)
	stripe.mesh = stripe_mesh
	stripe.material_override = _stripe_material
	stripe.transform = xform.translated_local(Vector3(0.0, (BOARD_HEIGHT - STRIPE_HEIGHT) / 2.0 + 0.001, 0.0))
	body.add_child(stripe)
