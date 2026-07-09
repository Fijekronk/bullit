extends Node3D
## Полигон для теста дриблинга: слаломная линия конусов + пара у бортов.
## Расстановка масштабируется под размер катка (layout из main при пересборке).
## F3 — показать/скрыть. Центр катка свободен — там респаунится шайба.

const CONE_RADIUS := 0.15
const CONE_HEIGHT := 0.4
const SPACING := 3.0

var _active := true
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(1.0, 0.47, 0.08)
	_material.roughness = 1.0  # флэт


## Пересобрать конусы под текущие габариты катка.
func layout(rink_length: float, rink_width: float) -> void:
	for child in get_children():
		child.queue_free()

	var positions: Array[Vector3] = []
	# Слаломная линия по центральной оси, от центра к правой зоне.
	var max_x := rink_length / 2.0 - 6.0
	var x := SPACING
	while x <= max_x:
		positions.append(Vector3(x, 0, 0))
		x += SPACING
	# Пара у бортов на левой половине.
	var board_z := rink_width / 2.0 - 2.0
	positions.append(Vector3(-rink_length * 0.12, 0, board_z))
	positions.append(Vector3(-rink_length * 0.24, 0, -board_z))

	for pos in positions:
		var body := StaticBody3D.new()
		body.position = pos
		body.collision_layer = 32  # слой "стены", как борта
		add_child(body)

		# Коллизия продлена под лёд: торец на уровне льда подбрасывает шайбу.
		var cylinder := CylinderShape3D.new()
		cylinder.radius = CONE_RADIUS
		cylinder.height = CONE_HEIGHT + 0.3
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position = Vector3(0.0, (CONE_HEIGHT - 0.3) / 2.0, 0.0)
		shape.disabled = not _active
		body.add_child(shape)

		var mesh := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = CONE_RADIUS
		cone.height = CONE_HEIGHT
		cone.material = _material
		mesh.mesh = cone
		mesh.position = Vector3(0.0, CONE_HEIGHT / 2.0, 0.0)
		body.add_child(mesh)

	visible = _active


func set_active(value: bool) -> void:
	_active = value
	visible = value
	for body in get_children():
		for shape in body.get_children():
			if shape is CollisionShape3D:
				shape.disabled = not value
