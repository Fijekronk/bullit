extends RigidBody3D
## Тестовая шайба. Телепорт (респаун) выполняется через _integrate_forces —
## прямое присваивание transform у RigidBody3D ломает состояние физики.

var _reset_requested := false
var _reset_transform := Transform3D.IDENTITY


func _ready() -> void:
	# Carry-пружина двигает шайбу силами — спящее тело их игнорирует.
	can_sleep = false


func reset_to(position_target: Vector3) -> void:
	_reset_requested = true
	_reset_transform = Transform3D(Basis.IDENTITY, position_target)
	# Спящее тело не вызывает _integrate_forces — будим, иначе телепорт
	# отложится до следующего импульса и обнулит его.
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_requested:
		_reset_requested = false
		state.transform = _reset_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
