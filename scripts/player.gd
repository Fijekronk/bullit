class_name Player
extends CharacterBody3D
## Конёк: анизотропное лезвие + профили «бег» (дефолт) и «скольжение» (Alt).
## Стойка (Ctrl) — движение работает (тяга × stance_thrust_cap), мышь уходит в
## жесты (blade), камера замирает. Рывок (Shift) — импульс с кулдауном.
## velocity меняют только тяга/лезвие/рывок; пивот и хоккейный стоп эмерджентны.
## Резкий стоп (бег, разворот >120°): форсированный SKID + доворот + толчок.

const CROSSOVER_MIN_ANGLE := 15.0
const HOCKEY_STOP_MIN_SPEED := 4.0
const PLOW_DECEL := 6.0
const STRIDE_FREQ := 1.7
const STRIDE_AMP := 0.30
const SPRAY_MIN_SPEED := 2.5
const QUICK_STOP_ANGLE := 120.0
const QUICK_STOP_EXIT_DEG := 25.0  # доворот к wish, при котором выходим из стопа

var params: SkatingParams = SkatingParams.new()

var is_stance := false
var is_glide := false
var is_skidding := false
var is_sprinting := false  # Shift: повышенная максималка/тяга, тратит стамину
var is_backward := false   # C: езда спиной (facing против движения)
var stamina := 5.0         # бак спринта (секунды); рывок требует ПОЛНЫЙ бак
var is_shielding := false  # стойка + шайба под контролем (ставит blade.gd)
var input_enabled := true  # false = управление отдано вратарю (свап)
# Пакет ввода — ЕДИНСТВЕННЫЙ источник ввода (сеть v1). Локальный игрок снимает
# Input сам; на сервере сюда пишется присланный клиентом пакет (net-слой).
var input := InputState.new()
var input_local := true    # true = снимать Input сам; false = ввод из сети
# Сеть: у удалённого игрока на сервере нет своей камеры — направление WASD берём
# из присланного yaw камеры пира, иначе управление считается от чужой камеры.
var use_net_yaw := false
var net_yaw := 0.0
var wish_cached := Vector3.ZERO
var speed_cap := 1.0  # множитель потолка скорости (замах щелчка ограничивает ход)
var aim_turn_dir := Vector3.ZERO  # зарядка броска: корпус доворачивается сюда (ZERO = нет)

var _yaw_rate := 0.0
var _stride_time := 0.0
var _lean := 0.0        # событийный крен корпуса (рад), визуал
var _lean_cont := 0.0   # континуальный крен (повороты), сглаженный
var _lean_target := 0.0
var _lean_timer := 0.0
var _fake_return := Vector3.ZERO  # ложный шаг: отложенный возврат на курс
var _fake_timer := 0.0
var _kick_flash := 0.0  # кик коньком: наклон корпуса + спрей
# Силовые (фикс-пасс 4): стан от хита, антиспам контакта, флаг фола
var _stun_timer := 0.0
var _hit_cd := 0.0
var last_hit_foul := false  # каркас правил бортования (наказание — этап правил)
var _quick_stopping := false
var _hard_reverse := false
var _dash_buffered := false
var _dash_flash := 0.0
var _sprint_tap_t := -1.0    # время с прошлого нажатия Shift (двойной = рывок)
var _backpedaling := false   # защёлка заднего хода (S лицом вперёд)
var _pivot_latch := false    # защёлка пивота на спину (Alt+назад, держится после Alt)

const BACKWARD_MIN_SPEED := 1.5
const DOUBLE_TAP_WINDOW := 0.3

@onready var _spray: GPUParticles3D = $IceSpray
@onready var _visual: Node3D = $PlayerVisual
@onready var _blade: Node3D = $Blade


## Готовность рывка = наполненность бака стамины (рывок требует полный бак).
func dash_ready_fraction() -> float:
	return clampf(stamina / maxf(params.sprint_max, 0.01), 0.0, 1.0)


func dash_ready() -> bool:
	# Почти полный бак: первый тап двойного Shift кратко тратит стамину — не
	# должен блокировать сам рывок (порог 90%).
	return stamina >= params.sprint_max * 0.9


func _physics_process(delta: float) -> void:
	if input_local:
		input.poll_local()  # снять свой Input (идемпотентно за кадр)
	is_stance = input.pressed("stance") and input_enabled
	is_glide = input.pressed("profile_glide") and input_enabled
	var wish := _wish_dir() if input_enabled else Vector3.ZERO
	wish_cached = wish
	var brake := input.pressed("move_back") and input_enabled
	# Жест-скольжение (жесты 5–10): тяга и доворот корпуса подавлены.
	var suppress: bool = _blade.suppress_movement
	if not input_enabled:
		suppress = true  # управление отдано вратарю — полевой стоит/тормозит

	_hit_cd = maxf(0.0, _hit_cd - delta)
	# Стан от хита: временная потеря управления — ввод игнорируется, тело едет.
	if _stun_timer > 0.0:
		_stun_timer -= delta
		wish = Vector3.ZERO
		wish_cached = wish
		brake = false
		is_stance = false
		suppress = true

	if _dash_flash > 0.0:
		_dash_flash -= delta

	# --- Спринт (Shift): повышенная максималка/тяга, тратит стамину ---
	is_sprinting = input.pressed("sprint") and stamina > 0.0 \
			and wish != Vector3.ZERO and not suppress and _stun_timer <= 0.0 \
			and not is_stance
	if is_sprinting:
		stamina = maxf(stamina - delta, 0.0)
	else:
		# Восстановление в покое/обычном беге (полный бак за stamina_regen_time).
		stamina = minf(stamina + params.sprint_max / maxf(params.stamina_regen_time, 0.1) * delta,
				params.sprint_max)

	if _sprint_tap_t >= 0.0:
		_sprint_tap_t += delta
		if _sprint_tap_t > DOUBLE_TAP_WINDOW:
			_sprint_tap_t = -1.0
	if _stun_timer <= 0.0:
		_handle_dash(wish, suppress)

	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hvel.length()
	var sprint_mult := params.sprint_speed_mult if is_sprinting else 1.0
	var forward := _forward()
	var side_dir := forward.rotated(Vector3.UP, -PI / 2.0)

	# --- Езда спиной, два способа ---
	# (1) ПИВОТ (Alt+назад на ходу): корпус БЫСТРО разворачивается спиной к
	#     движению; ЗАЩЁЛКА — продолжает ехать спиной и ПОСЛЕ отпускания Alt,
	#     рулится A/D (velocity поворачивается). Выход: W (лицом вперёд),
	#     тормоз S без Alt, или почти остановился.
	# (2) БЭКПЕДАЛ (просто S на малой скорости): реверс-тяга назад лицом вперёд.
	var back_held: bool = input.pressed("move_back") and not suppress and _stun_timer <= 0.0
	# Вход в пивот-защёлку.
	if is_glide and back_held and speed > BACKWARD_MIN_SPEED:
		_pivot_latch = true
	# Выход из защёлки.
	if _pivot_latch and (input.pressed("move_forward") or speed < 0.6 \
			or (back_held and not is_glide)):
		_pivot_latch = false
	var pivot_back: bool = _pivot_latch and speed > 0.4
	# Бэкпедал — только когда НЕ в пивоте.
	if back_held and not pivot_back and not _pivot_latch:
		if _backpedaling:
			if hvel.dot(forward) > 0.5:
				_backpedaling = false
		elif speed < 0.4:
			_backpedaling = true
	else:
		_backpedaling = false
	is_backward = pivot_back or _backpedaling
	if pivot_back:
		brake = false  # в скольжении назад = разворот/руль, не торможение

	# --- Профиль лезвия ---
	var carve_grip: float = params.glide_carve_grip if is_glide else params.run_carve_grip
	var carve_threshold: float = params.glide_carve_threshold if is_glide else params.run_carve_threshold
	var skid_friction: float = params.glide_skid_friction if is_glide else params.run_skid_friction
	var turn_max: float = params.glide_turn_rate_max if is_glide else params.run_turn_rate_max
	var facing_accel: float = deg_to_rad(params.glide_facing_accel if is_glide else params.run_facing_accel)

	# --- Резкий стоп (только бег): разворот >120° = форсированный юз ---
	if is_glide or suppress or wish == Vector3.ZERO or brake:
		_quick_stopping = false
	else:
		var wa := rad_to_deg(hvel.angle_to(wish)) if speed > 0.5 else 0.0
		if not _quick_stopping and wa > QUICK_STOP_ANGLE and speed > 3.0:
			_quick_stopping = true
			# Чистый реверс (>reverse_angle) требует полной остановки перед толчком.
			_hard_reverse = wa > params.reverse_angle
		elif _quick_stopping:
			var done := (speed < 0.6) if _hard_reverse else (rad_to_deg(forward.angle_to(wish)) < QUICK_STOP_EXIT_DEG)
			if done:
				_quick_stopping = false
				_hard_reverse = false

	# --- Намерение корпуса и тяги ---
	var desired_rate := 0.0
	var thrust := 0.0
	if pivot_back:
		# Корпус БЫСТРО доворачивается СПИНОЙ к движению (facing = -velocity):
		# полный угловой рейт — разворот резкий, скорость сохраняется.
		var back_dir := -hvel / speed
		desired_rate = _rate_to(forward.signed_angle_to(back_dir, Vector3.UP),
				facing_accel, deg_to_rad(params.turn_rate_at_zero))
		# Руление: A/D поворачивают вектор скорости, корпус следует спиной. Так
		# спиной можно поворачивать (обход вратаря и т.п.). hvel правится до лезвия.
		var steer := input.strength("turn_right") - input.strength("turn_left")
		if absf(steer) > 0.05:
			hvel = hvel.rotated(Vector3.UP,
					-steer * deg_to_rad(params.turn_rate_at_zero) * params.backward_control * delta)
	elif _backpedaling:
		# Задний ход лицом вперёд: реверс-тяга (пониженная), рулёжка A/D.
		thrust = -params.accel * params.backward_control
		if wish != Vector3.ZERO:
			desired_rate = _rate_to(forward.signed_angle_to(wish, Vector3.UP),
					facing_accel, deg_to_rad(params.turn_rate_at_zero) * params.backward_control)
	elif aim_turn_dir != Vector3.ZERO and not suppress:
		# Зарядка броска: корпус занят прицелом (доворот к камере), wish корпус
		# не крутит; тяга WASD вдоль корпуса сохраняется (с капом скорости).
		desired_rate = _rate_to(forward.signed_angle_to(aim_turn_dir, Vector3.UP),
				facing_accel, deg_to_rad(params.windup_turn_rate))
		if wish != Vector3.ZERO:
			_stride_time += delta
			var aim_ratio := clampf(hvel.dot(forward) / (params.max_speed * sprint_mult), 0.0, 1.0)
			thrust = params.accel * sprint_mult * pow(1.0 - aim_ratio, params.accel_curve_power)
	elif suppress:
		pass  # корпус держим, тяги нет
	elif brake and speed > HOCKEY_STOP_MIN_SPEED:
		var vel_dir := hvel / speed
		var perp := vel_dir.rotated(Vector3.UP, PI / 2.0)
		if forward.dot(perp) < forward.dot(-perp):
			perp = -perp
		desired_rate = _rate_to(forward.signed_angle_to(perp, Vector3.UP), facing_accel, deg_to_rad(params.turn_rate_at_zero))
	elif wish != Vector3.ZERO:
		var speed_t := clampf(speed / params.max_speed, 0.0, 1.0)
		var max_rate := deg_to_rad(lerpf(params.turn_rate_at_zero, turn_max, speed_t))
		if _quick_stopping:
			max_rate = deg_to_rad(params.turn_rate_at_zero)  # доворот в стопе быстрый
		desired_rate = _rate_to(forward.signed_angle_to(wish, Vector3.UP), facing_accel, max_rate)
		if not is_glide and not _quick_stopping:
			_stride_time += delta
			var ratio := clampf(hvel.dot(forward) / (params.max_speed * sprint_mult), 0.0, 1.0)
			thrust = params.accel * sprint_mult * pow(1.0 - ratio, params.accel_curve_power)
			thrust *= 1.0 + STRIDE_AMP * sin(TAU * STRIDE_FREQ * _stride_time)
			var wa := rad_to_deg(hvel.angle_to(wish)) if speed > 0.5 else 0.0
			if wa > CROSSOVER_MIN_ANGLE:
				thrust *= 1.0 + params.crossover_gain
			if is_stance:
				thrust *= params.stance_thrust_cap
	if wish == Vector3.ZERO and not (brake and speed > HOCKEY_STOP_MIN_SPEED):
		_stride_time = 0.0

	_yaw_rate = move_toward(_yaw_rate, desired_rate, facing_accel * delta)
	rotation.y += _yaw_rate * delta
	# Примечание: дриблинг (позы) НЕ вращает корпус — только уводит клюшку/шайбу
	# вбок. Руление в стойке — обычным WASD (доворот facing выше). Развязка
	# «широкий дриблинг = удержание» (blade.gd) убрала связь ширины с WASD.

	forward = _forward()
	side_dir = forward.rotated(Vector3.UP, -PI / 2.0)

	is_skidding = false
	if pivot_back:
		# Пивот на спину: лезвие НЕ раскладывается по facing (разворот на 180°
		# дал бы поперечную -> юз -> потеря скорости). Скорость и направление
		# движения сохраняются, гасит только трение вдоль.
		var bsp := move_toward(hvel.length(), 0.0, params.friction_along * delta)
		hvel = hvel.normalized() * bsp if bsp > 0.01 else Vector3.ZERO
	else:
		# --- Анизотропное лезвие ---
		var v_along := hvel.dot(forward)
		var v_side := hvel.dot(side_dir)
		v_along += thrust * delta
		v_along = move_toward(v_along, 0.0, params.friction_along * delta)
		# Плуг у стоп-скорости — но НЕ при заднем ходе (не глушим реверс-тягу).
		if brake and speed <= HOCKEY_STOP_MIN_SPEED and not _backpedaling:
			v_along = move_toward(v_along, 0.0, PLOW_DECEL * delta)
		if _backpedaling:  # кап заднего хода (медленнее обычного)
			v_along = maxf(v_along, -params.max_speed * params.backward_control)
		if _quick_stopping:
			v_along = move_toward(v_along, 0.0, params.quick_stop_friction * delta)
			v_side = move_toward(v_side, 0.0, params.quick_stop_friction * delta)
			is_skidding = true
		elif brake:
			# Тормоз (юз) работает в любом профиле: гасим поперечную (при хоккейном
			# стопе корпус поперёк — это и есть основное торможение).
			v_side = move_toward(v_side, 0.0, skid_friction * delta)
			is_skidding = speed > SPRAY_MIN_SPEED
		elif is_glide:
			# Скольжение: velocity ПОВОРАЧИВАЕТСЯ к facing с сохранением модуля
			# (руль, конечный радиус), без потери энергии на срыв.
			var mag := sqrt(v_along * v_along + v_side * v_side)
			var ang := atan2(v_side, v_along)
			var rate := log(2.0) / carve_grip  # 1/с, слабый в СКОЛЬЖЕНИИ
			ang = move_toward(ang, 0.0, rate * delta)
			v_along = mag * cos(ang)
			v_side = mag * sin(ang)
		elif absf(v_side) < carve_threshold:
			v_side *= pow(0.5, delta / carve_grip)
		else:
			v_side = move_toward(v_side, 0.0, skid_friction * delta)
			is_skidding = true
		hvel = forward * v_along + side_dir * v_side

	var ceiling: float = params.max_speed * sprint_mult * speed_cap + params.dash_overspeed
	if hvel.length() > ceiling:
		hvel = hvel.normalized() * ceiling

	velocity.x = hvel.x
	velocity.y = 0.0
	velocity.z = hvel.z
	move_and_slide()
	global_position.y = 0.0

	# Силовой контакт с манекеном: мой ход упёрся в его капсулу.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other: Object = col.get_collider()
		if other is Node3D and (other as Node3D).is_in_group("defender"):
			_resolve_body_hit(other as Node3D, (other as Node3D).get("constant_linear_velocity"))

	_spray.emitting = (is_skidding and hvel.length() > SPRAY_MIN_SPEED) \
			or _dash_flash > 0.0 or _kick_flash > 0.0
	var target_scale_y := 0.9 if is_stance else 1.0
	_visual.scale.y = lerpf(_visual.scale.y, target_scale_y, 1.0 - exp(-12.0 * delta))

	# --- Наклон корпуса (финты должны читаться телом) ---
	# Континуальный крен в повороте: пропорционален крутизне (yaw rate) и
	# скорости; в юзе/резком стопе сильнее (противодвижение весом).
	var speed_t := clampf(hvel.length() / params.max_speed, 0.0, 1.0)
	var cont := clampf(_yaw_rate / deg_to_rad(160.0), -1.0, 1.0) \
			* deg_to_rad(params.lean_turn) * speed_t
	if is_skidding:
		cont *= 1.5
	_lean_cont = lerpf(_lean_cont, cont, 1.0 - exp(-10.0 * delta))
	# Событийный крен (переводы/фейки) — поверх континуального.
	if _lean_timer > 0.0:
		_lean_timer -= delta
	else:
		_lean_target = 0.0
	_lean = lerpf(_lean, _lean_target, 1.0 - exp(-14.0 * delta))
	_visual.rotation.z = _lean_cont + _lean
	# Ложный шаг: фаза 2 — возврат на курс (корпус «обманул» и вернулся).
	if _fake_timer > 0.0:
		_fake_timer -= delta
		if _fake_timer <= 0.0:
			velocity += _fake_return
			_fake_return = Vector3.ZERO
	# Тангаж: клевок вперёд на кике, откинуться назад в резком стопе,
	# лёгкий наклон вперёд на разгоне.
	if _kick_flash > 0.0:
		_kick_flash -= delta
	var pitch_target := 0.0
	if _kick_flash > 0.0:
		pitch_target = -0.3
	elif _quick_stopping:
		pitch_target = 0.14
	elif thrust > 0.1:
		pitch_target = -0.10 * clampf(thrust / maxf(params.accel, 0.01), 0.0, 1.0)
	_visual.rotation.x = lerpf(_visual.rotation.x, pitch_target, 1.0 - exp(-14.0 * delta))


# --- Финты 2.0: корпус ---------------------------------------------------

## Боковой шаг корпуса (широкий перевод, банк, треугольник) — импульс, не телепорт.
func juke(lateral: Vector3, impulse: float) -> void:
	if lateral == Vector3.ZERO:
		return
	velocity += lateral.normalized() * impulse
	body_lean(_side_of(lateral), deg_to_rad(params.lean_juke))


## Ложный шаг (Q/E): выраженный двухфазный дёрг — резкий шаг вбок, через ~0.12 с
## возврат на курс. Сильный клевок корпусом, курс в итоге почти не меняется.
func body_fake(lateral: Vector3, impulse: float) -> void:
	if lateral == Vector3.ZERO:
		return
	var dir := lateral.normalized()
	velocity += dir * impulse
	_fake_return = -dir * impulse * 0.85
	_fake_timer = 0.12
	body_lean(_side_of(lateral), deg_to_rad(params.lean_fake), 0.15)


## Кик коньком: клевок корпуса + крен + всплеск ледяной крошки.
func kick_anim(side: float) -> void:
	_kick_flash = 0.18
	if side != 0.0:
		body_lean(side, deg_to_rad(params.lean_fake) * 0.7, 0.15)


func is_stunned() -> bool:
	return _stun_timer > 0.0


## Наезд движущегося манекена на игрока (манекен зовёт сам — CharacterBody
## не получает slide-контакт, когда стоит на месте).
func receive_defender_hit(d: Node3D) -> void:
	_resolve_body_hit(d, d.get("constant_linear_velocity"))


## Q-силовой: намеренный хит — к скорости добавляется «вложение корпуса»
## (замах), поэтому и с места идёт слабый толчок; на ходу — снос по массе.
func body_check(d: Node3D) -> void:
	_hit_cd = 0.0  # намеренный удар не глушится антиспамом контакта
	var invest := _forward() * 1.5
	velocity += invest
	_resolve_body_hit(d, d.get("constant_linear_velocity"))
	velocity -= invest


## Силовой контакт: импульс по массе x скорости вдоль линии контакта.
## Побеждает больший momentum: проигравший отлетает; жёсткий хит даёт стан
## и выбивает шайбу у носителя. Стоящий (momentum 0) сдвинуть бегущего не может.
func _resolve_body_hit(d: Node3D, their_vel_v: Variant) -> void:
	if _hit_cd > 0.0:
		return
	var their_vel: Vector3 = their_vel_v if their_vel_v is Vector3 else Vector3.ZERO
	var line := d.global_position - global_position
	line.y = 0.0
	if line.length() < 0.05:
		return
	line = line.normalized()  # от меня к цели
	var my_mass: float = params.player_mass
	var their_mass: float = float(d.get("mass_kg")) if d.get("mass_kg") != null else params.player_mass
	var my_p := maxf(velocity.dot(line), 0.0) * my_mass          # мой импульс В цель
	var their_p := maxf(their_vel.dot(-line), 0.0) * their_mass  # её импульс В меня
	if my_p < 60.0 and their_p < 60.0:
		return  # лёгкое касание (< ~0.75 м/с) — не хит
	_hit_cd = 0.5
	# Каркас правил бортования: хит чист, если ЦЕЛЬ с шайбой (шайба при ней)
	# или шайба отдана недавно (hit_window). Наказание за фол — этап правил.
	var puck := get_tree().get_first_node_in_group("puck") as Node3D
	var target_has_puck: bool = (puck != null \
			and (puck.global_position - d.global_position).length() < 1.5) \
			or _blade.time_since_release < params.hit_window
	if my_p >= their_p:
		# Я прохожу: цель отлетает по разнице импульсов, я теряю часть хода.
		var knock := (my_p - their_p) / their_mass * params.hit_impulse_scale
		if d.has_method("take_hit"):
			d.take_hit(line * knock, params.hit_stun)
		velocity -= line * velocity.dot(line) * 0.35
		last_hit_foul = not target_has_puck
	else:
		# Цель сильнее: я отлетаю, стан, шайба (если несу) выбита.
		var knock := (their_p - my_p) / my_mass * params.hit_impulse_scale
		velocity += -line * knock
		_stun_timer = params.hit_stun
		body_lean(signf(line.dot(_forward().rotated(Vector3.UP, -PI / 2.0))),
				deg_to_rad(params.lean_fake), params.hit_stun)
		if _blade.puck_state == 1:
			_blade.poke_loose(d.global_position)


## Крен корпуса на время: side -1 = влево, +1 = вправо.
func body_lean(side: float, amount: float, dur := 0.25) -> void:
	_lean_target = -side * amount
	_lean_timer = dur


func _side_of(lateral: Vector3) -> float:
	return signf(lateral.dot(_forward().rotated(Vector3.UP, -PI / 2.0)))


## Сырой WASD (включая S=назад) относительно камеры — для грамматики финтов.
func input_dir_raw() -> Vector3:
	var x := input.strength("turn_right") - input.strength("turn_left")
	var z := input.strength("move_back") - input.strength("move_forward")
	if x == 0.0 and z == 0.0:
		return Vector3.ZERO
	return Vector3(x, 0.0, z).rotated(Vector3.UP, _cam_yaw()).normalized()


## Рывок = ДВОЙНОЙ Shift (быстрое повторное нажатие sprint). Одиночное
## удержание Shift = спринт. Отдельной клавиши рывка нет.
func _handle_dash(wish: Vector3, suppress: bool) -> void:
	var double_tap := false
	if input.just_pressed("sprint"):
		if _sprint_tap_t >= 0.0 and _sprint_tap_t <= DOUBLE_TAP_WINDOW:
			double_tap = true
			_sprint_tap_t = -1.0
		else:
			_sprint_tap_t = 0.0
	if double_tap:
		if suppress:
			_dash_buffered = true  # во время жест-скольжения — буфер
		else:
			_try_dash(wish)
	if _dash_buffered and not suppress:
		_dash_buffered = false
		_try_dash(wish)


## Рывок (X): взрывной импульс, доступен ТОЛЬКО при ПОЛНОМ баке стамины и
## тратит его весь — выбор «длинный спринт ИЛИ один рывок».
func _try_dash(wish: Vector3) -> void:
	if not dash_ready():
		return
	var dir := wish if wish != Vector3.ZERO else _forward()
	velocity += dir * params.dash_impulse
	stamina = 0.0
	_dash_flash = 0.2  # всплеск крошки/следа


func _rate_to(yaw_error: float, angular_accel: float, max_rate: float) -> float:
	var stop_rate := sqrt(2.0 * angular_accel * absf(yaw_error))
	return signf(yaw_error) * minf(max_rate, stop_rate)


## WASD -> направление относительно yaw камеры. S не входит (тормоз).
func _wish_dir() -> Vector3:
	var x := input.strength("turn_right") - input.strength("turn_left")
	var fwd := input.strength("move_forward")
	if x == 0.0 and fwd == 0.0:
		return Vector3.ZERO
	return Vector3(x, 0.0, -fwd).rotated(Vector3.UP, _cam_yaw()).normalized()


## Yaw для WASD: локально — своя камера; по сети (удалённый на сервере) — yaw
## камеры пира из пакета (иначе управление считается от чужой камеры → инверсия).
func _cam_yaw() -> float:
	if use_net_yaw:
		return net_yaw
	var camera := get_viewport().get_camera_3d()
	return camera.global_rotation.y if camera else 0.0


func _forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()
