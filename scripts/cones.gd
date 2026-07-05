extends Node3D
## Полигон для теста дриблинга: конусы линией по центральной оси с шагом 3 м
## и пара у бортов. F3 — показать/скрыть (коллизии выключаются вместе с видимостью).
## Центр катка оставлен свободным — там респаунится шайба.

const CONE_POSITIONS: Array[Vector3] = [
	Vector3(2, 0, 0), Vector3(5, 0, 0), Vector3(8, 0, 0), Vector3(11, 0, 0), Vector3(14, 0, 0),
	Vector3(-5, 0, 8.5), Vector3(-9, 0, -8.5),
]
const CONE_RADIUS := 0.15
const CONE_HEIGHT := 0.4

var _active := true
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.05)
	material.roughness = 0.7
	for pos in CONE_POSITIONS:
		var body := StaticBody3D.new()
		body.position = pos
		body.collision_layer = 32  # слой "стены", как борта
		add_child(body)

		# Коллизия продлена под лёд: торец цилиндра на уровне льда даёт
		# контакт "ребро о ребро" и подбрасывает скользящую шайбу.
		var cylinder := CylinderShape3D.new()
		cylinder.radius = CONE_RADIUS
		cylinder.height = CONE_HEIGHT + 0.3
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position = Vector3(0.0, (CONE_HEIGHT - 0.3) / 2.0, 0.0)
		body.add_child(shape)
		_shapes.append(shape)

		var mesh := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = CONE_RADIUS
		cone.height = CONE_HEIGHT
		cone.material = material
		mesh.mesh = cone
		mesh.position = shape.position
		body.add_child(mesh)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_cones"):
		set_active(not _active)


func set_active(value: bool) -> void:
	_active = value
	visible = value
	for shape in _shapes:
		shape.disabled = not value
