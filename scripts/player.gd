class_name Player
extends CharacterBody3D
## Контроллер конька, модель "направление" (этап 3.5): WASD задаёт желаемое
## направление движения относительно yaw камеры, а не газ/руль.
## По углу между velocity и wish_dir: резаная дуга (carve) / крутая дуга /
## авто-пивот (юз → разворот → толчок). S — тормоз до полной остановки.
## Корпус (facing) имеет и лимит угловой скорости, и лимит углового
## ускорения — волчок и мгновенные развороты невозможны.

const LOW_SPEED := 3.0             # ниже — режим "пятачка": быстрый доворот
const HOCKEY_STOP_MIN_SPEED := 5.0
const HOCKEY_STOP_BRAKE_MULT := 1.5
const HOCKEY_STOP_TURN_MULT := 0.6  # доля turn_rate_at_zero в юзе/пивоте
const HARD_TURN_RATE_MULT := 1.6    # крутая дуга: корпус доворачивается быстрее
const CROSSOVER_MIN_SPEED := 4.0
const CROSSOVER_MIN_ANGLE := 15.0   # градусов между velocity и wish
const STRIDE_FREQ := 1.7            # Гц: пульсация тяги — "толчки"
const STRIDE_AMP := 0.35
const GRIP_MIN_SPEED := 0.3
const SPRAY_MIN_SPEED := 3.0

var params: SkatingParams = SkatingParams.new()

var _stride_time := 0.0
var _yaw_rate := 0.0     # текущая угловая скорость корпуса, рад/с
var _pivoting := false

@onready var _spray: GPUParticles3D = $IceSpray


func _physics_process(delta: float) -> void:
	var brake := Input.is_action_pressed("move_back")
	var wish := _wish_dir()

	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hvel.length()
	var forward := _forward()
	var vel_dir := hvel / speed if speed > 0.01 else forward

	var hockey_stop := brake and speed > HOCKEY_STOP_MIN_SPEED
	var wish_angle := rad_to_deg(vel_dir.angle_to(wish)) if wish != Vector3.ZERO else 0.0

	# --- Авто-пивот: липкое состояние "юз до pivot_exit_speed, корпус к wish".
	if _pivoting:
		if wish == Vector3.ZERO or brake or speed <= params.pivot_exit_speed \
				or wish_angle < params.carve_angle:
			_pivoting = false
	elif wish != Vector3.ZERO and not brake and speed > LOW_SPEED \
			and wish_angle > params.pivot_angle:
		_pivoting = true

	# --- Поворот корпуса: лимит скорости (зависит от хода) + лимит ускорения.
	var speed_t := clampf(speed / params.max_speed, 0.0, 1.0)
	var max_rate := deg_to_rad(lerpf(params.turn_rate_at_zero, params.turn_rate_at_max, speed_t))
	if _pivoting or hockey_stop:
		max_rate = deg_to_rad(params.turn_rate_at_zero) * HOCKEY_STOP_TURN_MULT
	elif wish_angle > params.carve_angle:
		max_rate *= HARD_TURN_RATE_MULT
	var angular_accel := deg_to_rad(params.facing_angular_accel)
	var desired_rate := 0.0
	if wish != Vector3.ZERO:
		var yaw_error := forward.signed_angle_to(wish, Vector3.UP)
		# Упреждение торможения: не быстрее, чем можно погасить к цели —
		# иначе корпус с инерцией проскакивает wish и осциллирует.
		var stop_rate := sqrt(2.0 * angular_accel * absf(yaw_error))
		desired_rate = signf(yaw_error) * minf(max_rate, stop_rate)
	_yaw_rate = move_toward(_yaw_rate, desired_rate, angular_accel * delta)
	rotation.y += _yaw_rate * delta
	forward = _forward()

	# --- Продольная динамика.
	if brake:
		_stride_time = 0.0
		var decel := params.brake_force * (HOCKEY_STOP_BRAKE_MULT if hockey_stop else 1.0)
		hvel = vel_dir * maxf(speed - decel * delta, 0.0)
	elif _pivoting:
		# Юз-торможение перед разворотом (как хоккейный стоп).
		_stride_time = 0.0
		hvel = vel_dir * maxf(speed - params.brake_force * HOCKEY_STOP_BRAKE_MULT * delta, 0.0)
	elif wish != Vector3.ZERO:
		# Тяга вдоль корпуса: нелинейная кривая + пульс "толчков".
		_stride_time += delta
		var ratio := clampf(hvel.dot(forward) / params.max_speed, 0.0, 1.0)
		var thrust := params.accel * pow(1.0 - ratio, params.accel_curve_power)
		thrust *= 1.0 + STRIDE_AMP * sin(TAU * STRIDE_FREQ * _stride_time)
		if wish_angle > CROSSOVER_MIN_ANGLE and speed > CROSSOVER_MIN_SPEED:
			thrust += params.crossover_boost  # перебежка в дуге
		hvel += forward * thrust * delta
		# Скраб: потеря скорости пропорциональна фактическому довороту корпуса.
		var scrub_k := params.turn_scrub if wish_angle < params.carve_angle else params.turn_scrub_hard
		var scrub := scrub_k * absf(rad_to_deg(_yaw_rate)) / 90.0
		hvel *= maxf(1.0 - scrub * delta, 0.0)
	else:
		# Накат по инерции.
		_stride_time = 0.0
		hvel = vel_dir * maxf(speed - params.coast_friction * delta, 0.0)

	# --- Сцепление коньков: velocity доворачивается к facing.
	speed = hvel.length()
	if speed > GRIP_MIN_SPEED:
		var dir := hvel / speed
		var target_dir := forward if dir.dot(forward) >= 0.0 else -forward
		var g := params.grip * (params.brake_grip_drop if brake or _pivoting else 1.0)
		hvel = dir.slerp(target_dir, 1.0 - exp(-g * delta)).normalized() * speed

	if hvel.length() > params.max_speed:
		hvel = hvel.normalized() * params.max_speed

	# Каток плоский, со льдом игрок физически не сталкивается (юбка коллизии
	# уходит под лёд против заклинивания шайбы) — высота фиксируется кодом.
	velocity.x = hvel.x
	velocity.y = 0.0
	velocity.z = hvel.z
	move_and_slide()
	global_position.y = 0.0

	_spray.emitting = (brake or _pivoting) and speed > SPRAY_MIN_SPEED


## WASD -> желаемое направление движения в плоскости, относительно yaw камеры.
## S в направление не входит — это тормоз.
func _wish_dir() -> Vector3:
	var x := Input.get_action_strength("turn_right") - Input.get_action_strength("turn_left")
	var forward_input := Input.get_action_strength("move_forward")
	if x == 0.0 and forward_input == 0.0:
		return Vector3.ZERO
	var yaw := 0.0
	var camera := get_viewport().get_camera_3d()
	if camera:
		yaw = camera.global_rotation.y
	return Vector3(x, 0.0, -forward_input).rotated(Vector3.UP, yaw).normalized()


func _forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()
