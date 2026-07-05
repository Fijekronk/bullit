extends Camera3D
## Следящая камера, два режима (переключатель camera_yaw_follow в F1-панели):
## - follow (дефолт): yaw следует за СГЛАЖЕННЫМ направлением скорости игрока
##   (не за facing), с лимитом угловой скорости и мёртвой зоной — экран не
##   "хлещет" при перекладках. При скорости < 2 м/с медленно доворачивается
##   к facing. Roll всегда 0 — горизонт стабилен.
## - fixed: yaw = 0, мировые оси стабильны (запасной режим).
## Позиция в обоих режимах плавно догоняет точку слежения с look-ahead
## и клэмпом в пределах катка.

const RINK_CLAMP := Vector2(18.0, 8.0)  # мягкий клэмп точки слежения (x, z)
const YAW_FOLLOW_MIN_SPEED := 2.0
const IDLE_YAW_SPEED_SCALE := 0.4  # доля cam_max_yaw_speed при довороте к facing

var params: SkatingParams
var target: CharacterBody3D

var _follow_point := Vector3.ZERO
var _yaw := 0.0
var _smoothed_dir := Vector3.FORWARD
var _initialized := false


func _physics_process(delta: float) -> void:
	if target == null or params == null:
		return

	var hvel := Vector3(target.velocity.x, 0.0, target.velocity.z)
	var speed := hvel.length()

	# --- Точка слежения: игрок + упреждение по скорости, в пределах катка.
	var look_target := target.global_position
	if speed > 0.1:
		look_target += hvel / speed * params.camera_lookahead \
				* clampf(speed / params.max_speed, 0.0, 1.0)
	look_target.x = clampf(look_target.x, -RINK_CLAMP.x, RINK_CLAMP.x)
	look_target.z = clampf(look_target.z, -RINK_CLAMP.y, RINK_CLAMP.y)
	look_target.y = 0.0

	if not _initialized:
		_initialized = true
		_follow_point = look_target
		_smoothed_dir = _target_forward()
	else:
		_follow_point = _follow_point.lerp(look_target, 1.0 - exp(-params.camera_smoothing * delta))

	_update_yaw(hvel, speed, delta)

	global_position = _follow_point + Vector3(0.0, params.camera_height, params.camera_distance) \
			.rotated(Vector3.UP, _yaw)
	rotation = Vector3(-deg_to_rad(params.camera_pitch), _yaw, 0.0)
	fov = params.camera_fov


func _update_yaw(hvel: Vector3, speed: float, delta: float) -> void:
	if not params.camera_yaw_follow:
		# Запасной режим: фиксированный yaw (плавный возврат к нулю).
		var step_to_zero := deg_to_rad(params.cam_max_yaw_speed) * delta
		_yaw = move_toward(_yaw, 0.0, step_to_zero)
		return

	var desired_dir: Vector3
	var speed_scale := 1.0
	if speed >= YAW_FOLLOW_MIN_SPEED:
		# За сглаженным направлением скорости — не за facing.
		_smoothed_dir = _smoothed_dir.slerp(hvel / speed,
				1.0 - exp(-params.cam_dir_smoothing * delta)).normalized()
		desired_dir = _smoothed_dir
	else:
		# Стоя на месте — медленно к facing игрока.
		desired_dir = _target_forward()
		_smoothed_dir = desired_dir
		speed_scale = IDLE_YAW_SPEED_SCALE

	var desired_yaw := atan2(-desired_dir.x, -desired_dir.z)
	var diff := wrapf(desired_yaw - _yaw, -PI, PI)
	var deadzone := deg_to_rad(params.cam_yaw_deadzone)
	if absf(diff) <= deadzone:
		return
	# Догоняем до края мёртвой зоны: с пропорциональным смягчением и капом.
	var remaining := diff - signf(diff) * deadzone
	var max_step := deg_to_rad(params.cam_max_yaw_speed) * speed_scale * delta
	var step := clampf(remaining * (1.0 - exp(-6.0 * delta)), -max_step, max_step)
	_yaw = wrapf(_yaw + step, -PI, PI)


func _target_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	return f.normalized()
