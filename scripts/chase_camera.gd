extends Camera3D
## Следящая камера. НЕ вращается: yaw всегда 0, мировые оси стабильны
## (задел под управление клюшкой мышью). Позиция плавно догоняет точку
## слежения = игрок + упреждение по вектору скорости, с клэмпом в пределах катка.

const RINK_CLAMP := Vector2(18.0, 8.0)  # мягкий клэмп точки слежения (x, z)

var params: SkatingParams
var target: CharacterBody3D

var _follow_point := Vector3.ZERO
var _initialized := false


func _physics_process(delta: float) -> void:
	if target == null or params == null:
		return

	var look_target := target.global_position
	var hvel := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var speed := hvel.length()
	if speed > 0.1:
		# Упреждение растёт со скоростью — на разгоне видно, куда едешь.
		look_target += hvel / speed * params.camera_lookahead \
				* clampf(speed / params.max_speed, 0.0, 1.0)
	look_target.x = clampf(look_target.x, -RINK_CLAMP.x, RINK_CLAMP.x)
	look_target.z = clampf(look_target.z, -RINK_CLAMP.y, RINK_CLAMP.y)
	look_target.y = 0.0

	if not _initialized:
		_initialized = true
		_follow_point = look_target
	else:
		_follow_point = _follow_point.lerp(look_target, 1.0 - exp(-params.camera_smoothing * delta))

	global_position = _follow_point + Vector3(0.0, params.camera_height, params.camera_distance)
	# Фиксированный угол: pitch из высоты/отступа, yaw и roll — всегда 0.
	rotation = Vector3(-atan2(params.camera_height, params.camera_distance), 0.0, 0.0)
