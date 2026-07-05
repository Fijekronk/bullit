class_name Player
extends CharacterBody3D
## Контроллер конька. Ключевая идея: направление корпуса (facing = rotation.y)
## и вектор скорости раздельны; сцепление (grip) каждый тик доворачивает
## velocity к корпусу — отсюда проскальзывание в дугах.
## W — толчки вперёд, A/D — поворот корпуса, S — торможение / езда назад.

const HOCKEY_STOP_MIN_SPEED := 5.0  # м/с: S выше этой скорости — хоккейный стоп
const HOCKEY_STOP_BRAKE_MULT := 1.5
const HOCKEY_STOP_TURN_MULT := 0.6  # доля turn_rate_at_zero для доворота корпуса в юзе
const BACKWARD_ACCEL_RATIO := 0.5
const CROSSOVER_MIN_SPEED := 4.0
const STRIDE_FREQ := 1.7  # Гц: пульсация тяги — "толчки", а не машина
const STRIDE_AMP := 0.35
const GRIP_MIN_SPEED := 0.3
const SPRAY_MIN_SPEED := 3.0

var params: SkatingParams = SkatingParams.new()

var _stride_time := 0.0

@onready var _spray: GPUParticles3D = $IceSpray


func _physics_process(delta: float) -> void:
	var turn_input := Input.get_axis("turn_right", "turn_left")  # A = +1 (влево)
	var throttle := Input.is_action_pressed("move_forward")
	var brake_key := Input.is_action_pressed("move_back")

	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hvel.length()
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var braking := brake_key and hvel.dot(forward) > 0.5  # ещё едем вперёд — юз
	var reversing := brake_key and not braking             # почти стоим — едем назад
	var hockey_stop := braking and speed > HOCKEY_STOP_MIN_SPEED

	# --- Поворот корпуса: на месте почти мгновенно, на скорости — большая дуга.
	var speed_t := clampf(speed / params.max_speed, 0.0, 1.0)
	var turn_rate := deg_to_rad(lerpf(params.turn_rate_at_zero, params.turn_rate_at_max, speed_t))
	if hockey_stop:
		# В хоккейном стопе корпус разрешаем доворачивать боком быстро.
		turn_rate = deg_to_rad(params.turn_rate_at_zero) * HOCKEY_STOP_TURN_MULT
	rotation.y += turn_input * turn_rate * delta
	forward = -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	# --- Тяга вперёд (W): нелинейная кривая, у максимума стремится к нулю.
	if throttle:
		_stride_time += delta
		var ratio := clampf(hvel.dot(forward) / params.max_speed, 0.0, 1.0)
		var thrust := params.accel * pow(1.0 - ratio, params.accel_curve_power)
		thrust *= 1.0 + STRIDE_AMP * sin(TAU * STRIDE_FREQ * _stride_time)
		if absf(turn_input) > 0.0 and speed > CROSSOVER_MIN_SPEED:
			thrust += params.crossover_boost  # перебежка в дуге
		hvel += forward * thrust * delta
	else:
		_stride_time = 0.0

	# --- Торможение / езда назад / накат.
	if braking:
		var decel := params.brake_force * (HOCKEY_STOP_BRAKE_MULT if hockey_stop else 1.0)
		hvel = hvel.normalized() * maxf(speed - decel * delta, 0.0)
	elif reversing:
		var back_speed := -hvel.dot(forward)
		var max_back := params.max_speed * params.backward_speed_ratio
		var ratio_b := clampf(back_speed / max_back, 0.0, 1.0)
		var thrust_b := params.accel * BACKWARD_ACCEL_RATIO * pow(1.0 - ratio_b, params.accel_curve_power)
		hvel -= forward * thrust_b * delta
	elif not throttle:
		hvel = hvel.normalized() * maxf(speed - params.coast_friction * delta, 0.0)

	# --- Сцепление коньков: velocity частично доворачивается к facing.
	speed = hvel.length()
	if speed > GRIP_MIN_SPEED:
		var dir := hvel / speed
		var target_dir := forward if dir.dot(forward) >= 0.0 else -forward
		var g := params.grip * (params.brake_grip_drop if braking else 1.0)
		var weight := 1.0 - exp(-g * delta)
		hvel = dir.slerp(target_dir, weight).normalized() * speed

	# Кроссовер-буст не должен разгонять выше максимума.
	if hvel.length() > params.max_speed:
		hvel = hvel.normalized() * params.max_speed

	# Каток плоский, со льдом игрок физически не сталкивается (юбка коллизии
	# уходит под лёд против заклинивания шайбы) — высота фиксируется кодом.
	velocity.x = hvel.x
	velocity.y = 0.0
	velocity.z = hvel.z
	move_and_slide()
	global_position.y = 0.0

	_spray.emitting = brake_key and speed > SPRAY_MIN_SPEED
