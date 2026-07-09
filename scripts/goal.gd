extends Node3D
## Ворота: рамка из штанг (каждая — отдельный CollisionShape), гасящая "сетка"
## и Area3D-триггер гола. Локальные координаты: линия ворот — x = 0,
## открытая сторона смотрит в +X, сетка уходит в -X.

signal goal_scored(side: String)

@export var side: String = "left"

const GOAL_WIDTH := 1.83
const GOAL_HEIGHT := 1.22
const GOAL_DEPTH := 1.0
const POST_RADIUS := 0.025

const FRAME_PHYSICS := preload("res://assets/materials/goal_frame_physics.tres")
const NET_PHYSICS := preload("res://assets/materials/net_physics.tres")

var _frame_material := StandardMaterial3D.new()
var _net_material := StandardMaterial3D.new()


func _ready() -> void:
	# Флэт-стиль: плоские цвета без бликов.
	_frame_material.albedo_color = Color(0.80, 0.16, 0.18)
	_frame_material.roughness = 1.0
	_net_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_net_material.albedo_color = Color(0.95, 0.96, 0.98, 0.25)
	_net_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_net_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_frame()
	_build_net()
	_build_trigger()


func _build_frame() -> void:
	var body := StaticBody3D.new()
	body.name = "Frame"
	body.physics_material_override = FRAME_PHYSICS
	body.collision_layer = 8  # слой "ворота": крюк их не задевает
	add_child(body)

	var half_width := GOAL_WIDTH / 2.0
	_add_frame_cylinder(body, "PostLeft",
			Transform3D(Basis.IDENTITY, Vector3(0.0, GOAL_HEIGHT / 2.0, half_width)), GOAL_HEIGHT, 0.3)
	_add_frame_cylinder(body, "PostRight",
			Transform3D(Basis.IDENTITY, Vector3(0.0, GOAL_HEIGHT / 2.0, -half_width)), GOAL_HEIGHT, 0.3)
	# Перекладина: ось цилиндра (Y) поворачивается вдоль Z.
	_add_frame_cylinder(body, "Crossbar",
			Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, GOAL_HEIGHT - POST_RADIUS, 0.0)),
			GOAL_WIDTH + POST_RADIUS * 2.0)


func _add_frame_cylinder(body: StaticBody3D, node_name: String, xform: Transform3D,
		height: float, below_ice: float = 0.0) -> void:
	# below_ice: продление коллизии под лёд. Нижний торец цилиндра ровно на
	# льду даёт контакт "ребро о ребро" с диагональной нормалью — скользящая
	# шайба взлетала от касания штанги. С запасом вниз контакт всегда боковой.
	var cylinder := CylinderShape3D.new()
	cylinder.radius = POST_RADIUS
	cylinder.height = height + below_ice
	var shape := CollisionShape3D.new()
	shape.name = node_name
	shape.shape = cylinder
	shape.transform = xform.translated_local(Vector3(0.0, -below_ice / 2.0, 0.0))
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = POST_RADIUS
	cylinder_mesh.bottom_radius = POST_RADIUS
	cylinder_mesh.height = height
	cylinder_mesh.radial_segments = 24
	mesh.mesh = cylinder_mesh
	mesh.material_override = _frame_material
	mesh.transform = xform
	body.add_child(mesh)


func _build_net() -> void:
	var body := StaticBody3D.new()
	body.name = "Net"
	body.physics_material_override = NET_PHYSICS
	body.collision_layer = 8  # слой "ворота": крюк их не задевает
	add_child(body)

	var half_width := GOAL_WIDTH / 2.0 + POST_RADIUS

	# Задняя наклонная панель: от перекладины вниз-назад к льду.
	var top := Vector2(-0.25, GOAL_HEIGHT - POST_RADIUS)
	var bottom := Vector2(-GOAL_DEPTH, 0.0)
	var slope := top - bottom
	var back_basis := Basis(Vector3.BACK, -atan2(slope.x, slope.y))  # локальная Y — вдоль ската
	var back_center := (top + bottom) / 2.0
	_add_net_panel(body,
			Transform3D(back_basis, Vector3(back_center.x, back_center.y, 0.0)),
			Vector3(0.03, slope.length(), half_width * 2.0), Vector3(-1.0, 0.0, 0.0))

	# Боковые панели.
	for s in [-1.0, 1.0]:
		_add_net_panel(body,
				Transform3D(Basis.IDENTITY, Vector3(-GOAL_DEPTH / 2.0, GOAL_HEIGHT / 2.0, s * half_width)),
				Vector3(GOAL_DEPTH, GOAL_HEIGHT, 0.03), Vector3(0.0, 0.0, s))

	# Вертикальная задняя стенка (только коллизия): без неё скат сетки снаружи
	# работает трамплином — шайба, прилетевшая сзади ворот, взлетает по нему.
	var wall := BoxShape3D.new()
	wall.size = Vector3(0.25, GOAL_HEIGHT, half_width * 2.0)
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = wall
	wall_shape.position = Vector3(-GOAL_DEPTH + 0.125, GOAL_HEIGHT / 2.0, 0.0)
	body.add_child(wall_shape)


func _add_net_panel(body: StaticBody3D, xform: Transform3D, size: Vector3,
		out_normal: Vector3) -> void:
	# Коллизия толще визуальной панели и смещена наружу от интерьера ворот
	# (out_normal, в локальных осях панели) — быстрая шайба не продавит стенку.
	const COLLISION_THICKNESS := 0.25
	var axis := out_normal.abs()
	var thickness := size.dot(axis)
	var box := BoxShape3D.new()
	box.size = size + axis * (COLLISION_THICKNESS - thickness)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = xform.translated_local(out_normal * (COLLISION_THICKNESS - thickness) / 2.0)
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _net_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = xform
	body.add_child(mesh)


func _build_trigger() -> void:
	# Зона за линией ворот внутри рамки: от -0.1 до -1.0 по X (глубокая,
	# чтобы быстрая шайба гарантированно перекрылась с зоной, пока гаснет в сетке).
	var area := Area3D.new()
	area.name = "GoalTrigger"
	area.collision_mask = 2  # реагирует только на слой шайбы
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, GOAL_HEIGHT - 0.1, GOAL_WIDTH - POST_RADIUS * 2.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(-0.55, (GOAL_HEIGHT - 0.1) / 2.0, 0.0)
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("puck"):
		print("GOAL")
		goal_scored.emit(side)
