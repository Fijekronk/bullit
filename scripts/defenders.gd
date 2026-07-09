extends Node3D
## Менеджер манекенов-защитников (полигон финтов): три штуки — статик в
## центре зоны, патруль поперёк оси и вратарь у правых ворот. Включаются
## F3-циклом из main (конусы -> манекены -> оба -> пусто).

const DefenderScript := preload("res://scripts/defender.gd")

var _active := false


## Пересобрать под габариты катка (вызывается из main._rebuild_rink).
func layout(rink_length: float, rink_width: float, goal_x: float,
		player: Player, blade: Node3D, puck: RigidBody3D, params: SkatingParams) -> void:
	for child in get_children():
		child.queue_free()

	var specs := [
		[DefenderScript.STATIC, Vector3(rink_length * 0.18, 0.0, 0.0)],
		[DefenderScript.PATROL, Vector3(rink_length * 0.33, 0.0, 0.0)],
		[DefenderScript.GOALIE, Vector3(goal_x - 1.3, 0.0, 0.0)],
	]
	for spec in specs:
		var d := DefenderScript.new()
		add_child(d)
		d.setup(spec[0], spec[1], player, blade, puck, params)
	set_active(_active)


func set_active(value: bool) -> void:
	_active = value
	visible = value
	for d in get_children():
		d.set_physics_process(value)
		for shape in d.get_children():
			if shape is CollisionShape3D:
				shape.disabled = not value
