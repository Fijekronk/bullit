extends AnimatableBody3D
## Крюк + машина состояний шайбы. Состояние крюка = один угол θ + постоянный
## радиус (жёсткая клюшка). Шайба: FREE (чистая физика) / CARRIED (PD-пружина к
## carry-точке на крюке — ведение/повороты/рывок надёжны, шайба остаётся
## RigidBody) / AIR (после подброса). Разрывы CARRIED — только явные (бросок,
## жест-выброс, срыв о препятствие), НЕ от скорости. Авто-перекладка на резком
## развороте ведёт шайбу на новую сторону через дугу крюка.
## Соглашение: ПРАВША → клюшка СЛЕВА (HAND_TO_LEFT). Жесты — только в стойке.

const HAND_TO_LEFT := true
const BLADE_COLLISION_SIZE := Vector3(0.30, 0.10, 0.035)
const BLADE_Y := 0.05
const HAND_HEIGHT := 1.0
const STANCE_SECTOR_EXPAND := 15.0
const CATCH_LOOKAHEAD := 0.08
const MODEL_PATH := "res://assets/models/HockeyStickBake.fbx"
const MODEL_NATURAL_LENGTH := 1.5818
const BEND_SIGN := 1.0
const PUCK_RADIUS := 0.0127
const COLLIDE_RESTORE_MAX_TICKS := 36  # страховка возврата коллизий (0.6 с)
const BLADE_WALL_MARGIN := 0.18   # отступ крюка от внутренней грани борта
const PINCH_BREAK_TIME := 0.1     # защемление: сила на капе дольше этого -> срыв
const CARRY_MAX_SPEED := 20.0     # предохранитель feedforward ведения
const CARRY_APPROACH := 0.5       # доля смыкания к целевой скорости за тик

enum { FREE, CARRIED, AIR }

## Тесты: если задан — цель θ берётся отсюда (мышь = камера, крюком не рулят).
var forced_azimuth := INF

var blade_velocity := Vector3.ZERO
var azimuth := 0.0
var target_azimuth := 0.0
var pivot_point := Vector3.ZERO
var carry_point := Vector3.ZERO
var _carry_vel := Vector3.ZERO
var puck_state := FREE
var puck_state_name := "FREE"
var last_transition := "-"
var suppress_movement := false  # жест-скольжение (жесты 5–10)
var transfer_active := false
var transfer_side := 0.0
var transfer_last_dur := 0.0
var rel_speed := 0.0
var last_gesture := "-"
var puck_controlled := false
var bend_dir := Vector3.ZERO
var windup := 0.0  # заряд замаха щелчка (0 = нет); на замахе ведение отключено
var aim_from := Vector3.ZERO  # дебаг-луч направления броска (F2), висит aim_timer
var aim_to := Vector3.ZERO
var aim_timer := 0.0
# Позы дриблинга
var pose := 0             # -1 = L, 0 = нейтраль, +1 = R
var pose_name := "нейтр"
var pose_progress := 1.0
var current_roll := 0.0   # наклон пера (°), для визуала

var _player: CharacterBody3D
var _debug_viz: Node3D
var _box := BoxShape3D.new()
var _azimuth_rate := 0.0
var _reach := 1.35
var _stick_root: Node3D
var _stick_model: Node3D
var _model_scale := 1.0
var _measured_length := 1.58  # фактическая длина меша вдоль шафта (по вершинам)
var _stick_q := Quaternion.IDENTITY  # сглаженная ориентация визуала клюшки
var _marker: MeshInstance3D
var _grace := 0.0
var _transfer_time := 0.0
var _transfer_charge := 0.0
var _reverse_angle := 0.0
var _pinch_time := 0.0
# Жесты
var _g_buffer := ""
var _triangle_timer := 0.0
var _triangle_blend := 0.0
var _skate_feint_t := 0.0    # финт через конёк: >0 — фаза протяжки за спину
var _fake_cd := 0.0
var _last_fake_side := 0.0   # дабл-тап той же стороны = усиленный фейк
var _last_fake_t := -1.0
var qe_mode := ""            # F2: активная трактовка Q/E
var _check_t := 0.0          # Q-силовой: телеграф-замах
var _check_cd := 0.0
var _poke_phase := 0         # E-отбор: 0 idle, 1 телеграф-замах, 2 окно контакта
var _poke_t := 0.0
var _poke_cd := 0.0
var _juggle_cd := 0.0        # кулдаун набивания — спам невозможен
var _idle_t := 0.0
# Широкий дриблинг = УДЕРЖАНИЕ (ширина растёт по времени), не WASD.
var _dribble_side := 0       # 0 нет, -1 ЛКМ(внешн), +1 ПКМ(внутр)
var _dribble_t := 0.0        # время удержания
var dribble_width := 0.0     # 0..1 (F2)
# F2-индикаторы (читает debug_viz)
var juggle_open := false     # окно набивания открыто
var juggle_frac := 0.0       # 0..1 — доля окна (полоска)
var poke_active := false     # E-отбор в процессе (телеграф/контакт) — F2
var poke_ready := 1.0        # 0..1 готовность отбора (кулдаун) — HUD
var time_since_release := 999.0  # для правила чистого хита (hit_window)
var _gesture_azimuth := 0.0
var _gesture_hold := 0.0
var _glide_timer := 0.0
# Позы: таймлайн перехода
var _pose_from_az := 0.0
var _pose_to_az := 0.0
var _pose_from_roll := 0.0
var _pose_to_roll := 0.0
var _pose_t := 1.0
var _pose_dur := 0.16
var _pose_azimuth := 0.0
var _wobble := 0.0
var _carry_collisions_off := false
var _collide_restore := -1


func _ready() -> void:
	_player = get_parent()
	_debug_viz = _player.get_node("DebugViz")
	_stick_root = _player.get_node("PlayerVisual/slot_stick")
	_box.size = BLADE_COLLISION_SIZE
	var shape := CollisionShape3D.new()
	shape.shape = _box
	add_child(shape)
	_build_stick_visual()
	_build_marker()
	var params: SkatingParams = _player.params
	_reach = params.stick_length
	azimuth = _neutral(params)
	target_azimuth = azimuth
	_pose_from_az = azimuth
	_pose_to_az = azimuth
	_pose_azimuth = azimuth
	var s := _player.global_position
	global_position = Vector3(s.x, BLADE_Y, s.z - _reach)
	pivot_point = s


func _physics_process(delta: float) -> void:
	var params: SkatingParams = _player.params
	var forward := _forward()
	pivot_point = _compute_pivot(params, forward)

	_update_gesture(params, delta)
	aim_timer = maxf(0.0, aim_timer - delta)
	suppress_movement = _glide_timer > 0.0
	if _glide_timer > 0.0:
		_glide_timer -= delta

	# --- Целевой θ: авто-перекладка > позы (стойка) > нейтраль ---
	_update_transfer(params, forward, delta)
	if is_finite(forced_azimuth):
		target_azimuth = forced_azimuth
		current_roll = move_toward(current_roll, 0.0, 180.0 * delta)
	elif windup > 0.0:
		# Замах щелчка: крюк уходит назад по стороне хвата (амплитуда ~ заряд).
		target_azimuth = lerpf(_neutral(params), 150.0, windup)
		current_roll = move_toward(current_roll, 0.0, 180.0 * delta)
	elif _skate_feint_t > 0.0 or _triangle_timer > 0.0:
		# Финт через конёк / треугольник: КЛЮШКА ЗАВОДИТСЯ ЗА СПИНУ вместе с
		# шайбой — протяжка читается по клюшке, а не только по шайбе.
		target_azimuth = 155.0
		current_roll = move_toward(current_roll, -25.0, 240.0 * delta)
	elif _player.is_stance:
		# Во время удержания дриблинга _pose_azimuth драйвит _grow_dribble_hold.
		if _dribble_side == 0:
			_update_pose(params, delta)
		# _gesture_azimuth — короткие «махи»-анимации (прибивание и т.п.).
		target_azimuth = _pose_azimuth + _gesture_azimuth
	else:
		pose = 0
		pose_name = "нейтр"
		pose_progress = 1.0
		target_azimuth = _neutral(params) + _gesture_azimuth
		current_roll = move_toward(current_roll, 0.0, 180.0 * delta)
	var lo := params.backhand_limit - (STANCE_SECTOR_EXPAND if _player.is_stance else 0.0)
	var hi := params.forehand_limit + (STANCE_SECTOR_EXPAND if _player.is_stance else 0.0)
	target_azimuth = clampf(target_azimuth, lo, hi)

	var target_reach := params.stick_length * (1.0 + (params.stance_reach_bonus if _player.is_stance else 0.0))
	_reach = lerpf(_reach, target_reach, 1.0 - exp(-delta / params.reach_transition))

	# θ к цели (лимиты, внутри сектора) — позиция крюка ВЫЧИСЛЯЕТСЯ из θ.
	# В позовых переходах лимит скорости крюка отдельный, повышенный: перекладки
	# работают на любой скорости бега и не растягиваются.
	var max_rate: float = params.blade_angular_speed
	if _player.is_stance and _pose_t < 1.0:
		max_rate = maxf(max_rate, rad_to_deg(params.pose_blade_speed / maxf(_reach, 0.3)))
	var diff := target_azimuth - azimuth
	var stop_rate := sqrt(2.0 * params.blade_angular_accel * absf(diff))
	var desired := signf(diff) * minf(max_rate, stop_rate)
	_azimuth_rate = move_toward(_azimuth_rate, desired, params.blade_angular_accel * delta)
	azimuth = clampf(azimuth + _azimuth_rate * delta, lo, hi)

	var pos := global_position
	pos.y = 0.0
	# Клэмп в коробку (борта + дуги углов): крюк не заезжает в стену.
	var new_pos := _clamp_to_rink(pivot_point + _dir_from_e(azimuth, forward, params) * _reach,
			params, BLADE_WALL_MARGIN)
	new_pos.y = 0.0
	blade_velocity = (new_pos - pos) / delta
	var outward := new_pos - pivot_point
	if outward.length() > 0.05:
		rotation = Vector3(0.0, atan2(outward.x, outward.z), 0.0)
	_resolve_fast_sweep(pos, new_pos)
	global_position = Vector3(new_pos.x, BLADE_Y, new_pos.z)
	constant_linear_velocity = blade_velocity

	# carry-точка: на крюке, чуть к пятке (к pivot). На замахе шайба «заводится»
	# с корпусом — carry следует за крюком в позицию замаха (сторона хвата, сзади).
	var heel := (pivot_point - new_pos)
	heel.y = 0.0
	var prev_carry := carry_point
	carry_point = new_pos + heel.normalized() * params.carry_heel_offset
	# Треугольник / финт через конёк: ПЛАВНАЯ протяжка под себя (мгновенный
	# прыжок carry-точки за спину рвал ведение по carry_break_dist).
	var pull_back := _triangle_timer > 0.0 or _skate_feint_t > 0.0
	_triangle_blend = move_toward(_triangle_blend, 1.0 if pull_back else 0.0, delta / 0.2)
	if _triangle_blend > 0.0:
		carry_point = carry_point.lerp(pivot_point - forward * params.skate_zone, _triangle_blend)
	elif puck_state == CARRIED and pose == 0 and _pose_t >= 1.0 and windup <= 0.0:
		# Идл-дриблинг: лёгкое качание шайбы на крюке, чтобы контроль «дышал».
		_idle_t += delta
		var lat := forward.rotated(Vector3.UP, -PI / 2.0)
		carry_point += lat * (sin(_idle_t * TAU * 1.4) * params.idle_dribble_amp)
	# Клэмп carry-точки к коробке: у борта позы «сжимаются» к игроку, шайба
	# никогда не ведётся в стену.
	carry_point = _clamp_to_rink(carry_point, params, params.puck_wall_margin)
	carry_point.y = PUCK_RADIUS
	# Скорость самой carry-точки (feedforward ведения — точнее скорости крюка).
	_carry_vel = (carry_point - prev_carry) / delta if prev_carry != Vector3.ZERO else Vector3.ZERO

	_update_puck(params, delta)
	# Укрывание: стойка ИЛИ скольжение с шайбой (см. defender._is_shielded).
	_player.is_shielding = (_player.is_stance or _player.is_glide) and puck_state == CARRIED
	_update_marker()


func _process(delta: float) -> void:
	# Визуал клюшки — каждый КАДР рендера со сглаживанием: на 60 Гц физики при
	# высоком FPS дискретные шаги крюка читались как тряска меша.
	if _player == null:
		return
	_update_stick_visual(_forward(), _player.params, delta)


# --- Машина состояний шайбы -------------------------------------------------

func _set_state(s: int, reason: String) -> void:
	if puck_state == s:
		return
	puck_state = s
	puck_state_name = ["FREE", "CARRIED", "AIR"][s]
	last_transition = reason


func _update_puck(params: SkatingParams, delta: float) -> void:
	_grace = maxf(0.0, _grace - delta)
	puck_controlled = false
	rel_speed = 0.0
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	var to_puck := puck.global_position - global_position
	to_puck.y = 0.0
	var dist := to_puck.length()
	var rel := puck.linear_velocity - blade_velocity
	rel.y = 0.0
	rel_speed = rel.length()

	_run_puck_state(puck, params, delta, dist, rel_speed, rel, to_puck)

	# Коллизии крюк/капсула ↔ шайба: off в CARRIED, на замахе И весь release-grace
	# (после выстрела из замаха шайба летит из-за спины через зону игрока, а крюк
	# несётся из замаха к нейтрали НАПЕРЕРЕЗ — ранний возврат коллизий гасил
	# собственный выстрел и давал depenetration-подскок). Назад — когда grace
	# вышел И шайба покинула зону, либо по таймауту-страховке.
	var want_off := puck_state == CARRIED or windup > 0.0 or _grace > 0.0
	if want_off and not _carry_collisions_off:
		_set_carry_collisions(puck, false)
		_carry_collisions_off = true
		_collide_restore = -1
	elif not want_off and _carry_collisions_off:
		_carry_collisions_off = false
		_collide_restore = COLLIDE_RESTORE_MAX_TICKS
	if _collide_restore > 0:
		_collide_restore -= 1
		var puck_clear := (puck.global_position - _player.global_position).length() > 0.85 \
				and (puck.global_position - global_position).length() > 0.35
		if puck_clear or _collide_restore == 0:
			_set_carry_collisions(puck, true)
			_collide_restore = -1


func _run_puck_state(puck: RigidBody3D, params: SkatingParams, delta: float, dist: float, rel_speed_: float, rel: Vector3, to_puck: Vector3) -> void:
	match puck_state:
		FREE:
			if _grace <= 0.0 and _can_grab(puck, params, dist, rel_speed_, rel, to_puck):
				_set_state(CARRIED, "подбор/приём")
		CARRIED:
			puck_controlled = true
			puck.sleeping = false  # спящее тело игнорирует силы carry-пружины
			# Чистый разворот на пределе скорости честно отрывает шайбу
			# (перекладка надёжна только до потолка надёжности).
			var speed := Vector3(_player.velocity.x, 0, _player.velocity.z).length()
			if transfer_active and _reverse_angle > 150.0 and speed > params.transfer_reliable_speed:
				_set_state(FREE, "разворот на пределе оторвал шайбу")
				_grace = 0.1
			else:
				var pinched := _apply_carry(puck, params, delta)
				# Контакт с бортом сам по себе carry не рвёт (клэмп + пружина
				# держат). Разрыв — только настоящее защемление: сила на капе
				# дольше PINCH_BREAK_TIME, либо большой отрыв (страховка).
				_pinch_time = (_pinch_time + delta) if pinched else 0.0
				if _pinch_time > PINCH_BREAK_TIME:
					_set_state(FREE, "защемление")
					_pinch_time = 0.0
					_grace = 0.1
				elif (carry_point - puck.global_position).length() > params.carry_break_dist:
					_set_state(FREE, "срыв о препятствие/манёвр")
					_grace = 0.1
		AIR:
			# Пружина в AIR ПОЛНОСТЬЮ отключена — шайба свободна. Приём с
			# воздуха уважает release-grace (иначе выстрел с подъёмом ловится
			# обратно в тот же тик — Jolt применяет импульс отложенно).
			if _grace <= 0.0 and puck.global_position.y < 0.18 \
					and puck.linear_velocity.y <= 0.1 and dist < params.catch_radius * 1.6:
				_set_state(CARRIED, "приём с воздуха")
			elif puck.global_position.y < 0.05 and puck.linear_velocity.length() < 3.0 and dist > params.pickup_radius:
				_set_state(FREE, "падение")


func _set_carry_collisions(puck: RigidBody3D, on: bool) -> void:
	puck.set_collision_mask_value(3, on)  # шайба ↔ игрок (капсула)
	puck.set_collision_mask_value(5, on)  # шайба ↔ крюк
	_player.set_collision_mask_value(2, on)
	set_collision_mask_value(2, on)


func _can_grab(puck: RigidBody3D, params: SkatingParams, dist: float, rspeed: float, rel: Vector3, to_puck: Vector3) -> bool:
	# Контроль/приём/подбор — как триггеры перехода в CARRIED.
	if dist <= params.assist_radius and rspeed <= params.assist_max_rel_speed:
		return true
	if puck.linear_velocity.length() < 3.0 and dist <= params.pickup_radius:
		return true
	if rspeed > 0.01 and rspeed <= params.catch_max_rel_speed and rel.dot(to_puck) < 0.0:
		var t := clampf(-to_puck.dot(rel) / (rspeed * rspeed), 0.0, CATCH_LOOKAHEAD)
		if (to_puck + rel * t).length() <= params.catch_radius:
			return true
	return false


## Ведение шайбы: прямое управление горизонтальной скоростью (feedforward
## скорости carry-точки + полное смыкание зазора за тик). Безусловно устойчиво
## на 60 Гц — «приклеено», без лага и дрожи (силовой PD при явном интегрировании
## осциллировал). Шайба остаётся RigidBody: коллизии со льдом/бортами/воротами
## живут (упор в препятствие копит зазор → срыв carry). Y не трогаем.
## Возвращает true, если сила упёрлась в кап (кандидат на защемление).
func _apply_carry(puck: RigidBody3D, params: SkatingParams, delta: float) -> bool:
	var gain := params.carry_stiffness / 20.0
	var boost := 1.0
	if transfer_active and Vector3(_player.velocity.x, 0, _player.velocity.z).length() <= params.transfer_reliable_speed:
		boost = params.transfer_assist_mult
	# Позовый переход (широкие переводы с juke) и протяжка за спину (треугольник,
	# финт через конёк): шайба «приклеена» сильнее — быстрые движения carry-точки
	# не срывают ведение.
	if (_player.is_stance and _pose_t < 1.0) or _triangle_blend > 0.01:
		boost = maxf(boost, 1.8)
	var ff := _carry_vel
	if ff.length() > CARRY_MAX_SPEED:
		ff = ff.normalized() * CARRY_MAX_SPEED
	var to_target := carry_point - puck.global_position
	to_target.y = 0.0
	var desired_v := ff + to_target * gain
	var dv := desired_v - puck.linear_velocity
	dv.y = 0.0
	# Мягкий подход (доля к desired за тик) вместо deadbeat: не перелетает на
	# шумном feedforward, не зашвыривает шайбу на быстрых свипах поз.
	var force := dv * (puck.mass / delta) * CARRY_APPROACH
	var capped := force.length() > params.carry_max_force * boost
	if capped:
		force = force.normalized() * params.carry_max_force * boost
	puck.apply_central_force(force)
	return capped


## Внешние выбросы шайбы (бросок/пас/жест) — с grace, чтобы не подхватилась сразу.
func release_puck(impulse: Vector3, air: bool = false) -> void:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	puck.apply_central_impulse(impulse)
	_grace = _player.params.release_grace
	time_since_release = 0.0  # окно чистого хита (hit_window)
	_set_state(AIR if air else FREE, "выброс: %s" % ("подброс" if air else "бросок/пас/финт"))


## Бросок/пас: шайба должна быть в окне контроля (иначе whiff — свинг вхолостую).
## dir горизонтальный; скорость speed, вертикальный подъём lift. Возвращает true,
## если бросок состоялся. Ставит дебаг-луч направления на 1 с.
func shoot(dir: Vector3, speed: float, lift: float) -> bool:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return false
	var d := dir
	d.y = 0.0
	d = d.normalized()
	aim_from = puck.global_position
	aim_to = puck.global_position + d * 6.0  # дебаг-луч: от шайбы к прицелу
	aim_timer = 1.0
	windup = 0.0
	# Шайба под контролем (CARRIED, «заведена» с корпусом) — бросок разрешён.
	# Свободная шайба — только из окна контроля у нейтрали (иначе whiff).
	if puck_state != CARRIED:
		var forward := _forward()
		var params: SkatingParams = _player.params
		var control := _compute_pivot(params, forward) \
				+ _dir_from_e(params.neutral_angle, forward, params) * params.stick_length
		control.y = puck.global_position.y
		if (puck.global_position - control).length() > params.shot_window:
			return false  # whiff
	puck.sleeping = false
	puck.linear_velocity = Vector3.ZERO  # чистый бросок из окна контроля
	release_puck((d * speed + Vector3(0, lift, 0)) * puck.mass, lift > 3.0)
	return true


# --- Авто-перекладка --------------------------------------------------------

func _update_transfer(params: SkatingParams, forward: Vector3, delta: float) -> void:
	var was := transfer_active
	transfer_active = false
	if puck_state != CARRIED:
		if was:
			transfer_last_dur = _transfer_time
		_transfer_time = 0.0
		_transfer_charge = 0.0
		return
	var hvel := Vector3(_player.velocity.x, 0, _player.velocity.z)
	var wish: Vector3 = _player.wish_cached
	# Дебаунс: разворот должен УДЕРЖАТЬСЯ (не мгновенный флик слалома).
	_reverse_angle = rad_to_deg(hvel.angle_to(wish)) if wish != Vector3.ZERO and hvel.length() > 0.5 else 0.0
	var reversing := wish != Vector3.ZERO and hvel.length() > 3.0 \
			and _reverse_angle > params.pivot_transfer_angle
	_transfer_charge = (_transfer_charge + delta) if reversing else 0.0
	if _transfer_charge > 0.08:
		transfer_active = true
		var toward_hand := wish.dot(_hand_side(forward, params)) > 0.0
		transfer_side = 1.0 if toward_hand else -1.0
	if transfer_active:
		_transfer_time += delta
	elif was:
		transfer_last_dur = _transfer_time
		_transfer_time = 0.0


# --- Финты 2.0: кнопка (L/R/SP/Q/E) + направление WASD в момент нажатия -----
# Мышь НИКОГДА не участвует (мышь = камера). Направление — относительно
# facing игрока: forward/back/left/right/neutral; диагонали округляются к
# доминирующей боковой. Каждый финт двигает и корпус.
# Q (фейк корпусом) и E (конёк) работают и вне стойки — на бегу.

func _update_gesture(params: SkatingParams, delta: float) -> void:
	if _gesture_hold > 0.0:
		_gesture_hold -= delta
	else:
		_gesture_azimuth = move_toward(_gesture_azimuth, 0.0, 240.0 * delta)
	if _triangle_timer > 0.0:
		_triangle_timer -= delta
	_fake_cd = maxf(0.0, _fake_cd - delta)
	_juggle_cd = maxf(0.0, _juggle_cd - delta)
	time_since_release += delta
	if _last_fake_t >= 0.0:
		_last_fake_t += delta
		if _last_fake_t > 0.35:
			_last_fake_t = -1.0
	_update_juggle_indicator(params)

	# Финт через конёк: фаза протяжки кончилась — авто-подставка возвращает вперёд.
	if _skate_feint_t > 0.0:
		_skate_feint_t -= delta
		if _skate_feint_t <= 0.0:
			_kick_return(params)

	# Управление отдано вратарю — ввод клюшки/финтов не читаем (ЛКМ/ПКМ = вратарь).
	if not _player.input_enabled:
		return

	# Q/E контекстны (приоритет: стойка -> фейк; шайба -> фейк; иначе Q=силовой,
	# E=отбор). Телеграфы тикают ниже; F2 показывает активную трактовку.
	_check_cd = maxf(0.0, _check_cd - delta)
	_poke_cd = maxf(0.0, _poke_cd - delta)
	poke_ready = 1.0 - clampf(_poke_cd / maxf(params.poke_cooldown, 0.01), 0.0, 1.0)
	var qe_fake: bool = _player.is_stance or puck_state == CARRIED
	qe_mode = "фейки (стойка)" if _player.is_stance \
			else ("фейки (шайба)" if puck_state == CARRIED else "силовой/отбор")
	if _player.input.just_pressed("feint_left"):
		if qe_fake:
			_side_fake(-1.0, params)
		elif _check_cd <= 0.0 and _check_t <= 0.0:
			_check_t = 0.15  # телеграф-замах силового
			_player.body_lean(-1.0, deg_to_rad(params.lean_fake) * 0.6, 0.15)
			last_gesture = "Q → силовой (замах)"
	if _player.input.just_pressed("feint_right"):
		if qe_fake:
			_side_fake(1.0, params)
		elif _poke_cd <= 0.0 and _poke_phase == 0:
			_start_poke(params)  # честный отбор: телеграф -> окно контакта
	if _check_t > 0.0:
		_check_t -= delta
		if _check_t <= 0.0:
			_do_body_check(params)
	_update_poke(params, delta)

	if not _player.is_stance:
		_g_buffer = ""
		_end_dribble_hold(params)  # вышли из стойки — вернуть шайбу
		return

	# Широкий дриблинг = УДЕРЖАНИЕ ЛКМ/ПКМ: пока держишь, клюшка отводится шире
	# (до wide_pose_angle за hold_max). Отпустил — возврат + juke по ширине.
	if _dribble_side != 0:
		_grow_dribble_hold(params, delta)

	# Буфер 1 клик: если предыдущий финт «исполняется» (жест-скольжение),
	# следующий клик срабатывает сразу по окончании.
	var button := ""
	if _player.input.just_pressed("gesture_primary"):
		button = "L"
	elif _player.input.just_pressed("gesture_secondary"):
		button = "R"
	elif _player.input.just_pressed("gesture_lift"):
		button = "SP"
	if button != "":
		# В воздухе — мгновенно (набивание/прибивание — тайминг), буфер только на льду.
		if _glide_timer > 0.0 and puck_state != AIR:
			_g_buffer = button
		else:
			_do_feint(button, _feint_dir(params), params)
	elif _g_buffer != "" and _glide_timer <= 0.0:
		_do_feint(_g_buffer, _feint_dir(params), params)
		_g_buffer = ""


## Направление WASD в момент клика, в осях игрока:
## "fwd" / "back" / "left" / "right" / "" (нейтраль).
func _feint_dir(_params: SkatingParams) -> String:
	var wish: Vector3 = _player.input_dir_raw()
	if wish == Vector3.ZERO:
		return ""
	var forward := _forward()
	var right := forward.rotated(Vector3.UP, -PI / 2.0)
	var f := wish.dot(forward)
	var s := wish.dot(right)
	# Диагонали округляются к доминирующей БОКОВОЙ.
	if absf(s) >= 0.38:
		return "right" if s > 0.0 else "left"
	return "fwd" if f > 0.0 else "back"


## Словарь финтов (клики — только в стойке).
func _do_feint(button: String, dir: String, params: SkatingParams) -> void:
	var forward := _forward()
	var right := forward.rotated(Vector3.UP, -PI / 2.0)
	var lateral := right if dir == "right" else -right
	var side_sign := 1 if dir == "right" else -1  # знак в осях игрока

	# --- Воздух (AIR): ЛКМ в лёд от хвата, ПКМ к хвату (вернуть), SP подбив ---
	if puck_state == AIR:
		var hand := _hand_side(forward, params)
		match button:
			"SP":
				_air_juggle(params)
			"L":
				# ШИРОКО в лёд от стороны хвата (правша: вперёд-влево).
				_air_slam(forward * 0.7 - hand * 1.6, params)
				last_gesture = "L (воздух) → в лёд от хвата"
			"R":
				# ШИРОКО к стороне хвата (настильно — шайба уходит вбок).
				_air_strike(forward * 0.3 + hand * 1.6 + Vector3.DOWN * 1.1, 7.0)
				_grace = 0.0
				last_gesture = "R (воздух) → к хвату"
		return

	# --- Лёд ---
	# Ширина дриблинга больше НЕ зависит от WASD — только удержание (см.
	# _grow_dribble_hold). WASD-направление оставляет спец-финты (треугольник,
	# банк, выход из треугольника), всё остальное L/R = начало дриблинг-удержания.
	match button:
		"SP":
			# SP+назад = финт через конёк (с ЛЮБОЙ стороны — надёжный ввод).
			# SP без назад — ПРАВИЛО СТОРОНЫ: подброс только с ВНЕШНЕЙ (хват);
			# с внутренней — ничего (сначала перевод, ЛКМ).
			if puck_state != CARRIED:
				pass
			elif dir == "back":
				_skate_feint_start(params)
			elif puck_is_external(params):
				_flip_up(params)
			else:
				last_gesture = "SP: шайба на внутренней — нужен перевод (ЛКМ)"
		"L":
			if dir == "back":
				_triangle_setup(params)  # шайба под себя; выход — L+вбок в окне
			elif (dir == "left" or dir == "right") and _triangle_timer > 0.0:
				_skate_deflect(lateral, params)  # выстрел из-под конька
			else:
				_begin_dribble_hold(-1, params)  # перевод к хвату (ВНЕШНЯЯ), тап/удержание
		"R":
			if (dir == "left" or dir == "right") and _wall_within(lateral, 2.5, params):
				_bank_off_boards(lateral, params)  # банк от борта (приоритет)
			else:
				_begin_dribble_hold(1, params)  # перевод от хвата (внутренняя), тап/удержание


## Шайба на внешней стороне (сторона хвата)? Правило подброса и F2-индикатор.
func puck_is_external(params: SkatingParams) -> bool:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return false
	var to_puck := puck.global_position - _player.global_position
	to_puck.y = 0.0
	return to_puck.dot(_hand_side(_forward(), params)) >= 0.0


## Q без шайбы: силовой — хит по ближайшему манекену/игроку в hit_reach
## перед собой. Импульс по массе x скорости (на месте слабый толчок).
func _do_body_check(params: SkatingParams) -> void:
	_check_cd = params.hit_cooldown
	var forward := _forward()
	var best: Node3D = null
	var best_d := params.hit_reach + 0.65  # + радиусы капсул
	for d in get_tree().get_nodes_in_group("defender"):
		var to_d: Vector3 = (d as Node3D).global_position - _player.global_position
		to_d.y = 0.0
		if to_d.length() < best_d and to_d.normalized().dot(forward) > 0.2:
			best = d
			best_d = to_d.length()
	if best:
		_player.body_check(best)
		last_gesture = "Q → силовой!"
	else:
		last_gesture = "Q → силовой (мимо)"


## E без шайбы: ЧЕСТНЫЙ отбор. Фаза 1 — ВИДИМЫЙ телеграф-замах (клюшка
## отводится назад) poke_windup; фаза 2 — окно контакта poke_contact, в
## котором выпад достаёт шайбу в конусе перед собой, если она не укрыта
## корпусом носителя. Попал или промах — полный кулдаун (наказание за спам).
func _start_poke(params: SkatingParams) -> void:
	_poke_phase = 1
	_poke_t = params.poke_windup
	poke_active = true
	last_gesture = "E → отбор (замах)"


func _update_poke(params: SkatingParams, delta: float) -> void:
	if _poke_phase == 0:
		poke_active = false
		return
	poke_active = true
	_poke_t -= delta
	if _poke_phase == 1:
		# Телеграф: клюшка ОТВОДИТСЯ назад (видно сопернику) — вне стойки через
		# _gesture_azimuth поверх нейтрали.
		_gesture_azimuth = lerpf(_gesture_azimuth, -35.0, 1.0 - exp(-18.0 * delta))
		_gesture_hold = 0.05
		if _poke_t <= 0.0:
			_poke_phase = 2
			_poke_t = params.poke_contact
	elif _poke_phase == 2:
		# Выпад: клюшка резко вперёд; каждый тик пробуем достать шайбу.
		_gesture_azimuth = lerpf(_gesture_azimuth, 40.0, 1.0 - exp(-30.0 * delta))
		_gesture_hold = 0.05
		if _try_poke_contact(params):
			_poke_phase = 0
			_poke_cd = params.poke_cooldown
		elif _poke_t <= 0.0:
			_poke_phase = 0
			_poke_cd = params.poke_cooldown  # промах = полный кулдаун
			last_gesture = "E → отбор (мимо)"


## Достаёт ли выпад шайбу СЕЙЧАС: в конусе (poke_reach + угол) и не укрыта.
func _try_poke_contact(params: SkatingParams) -> bool:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null or puck_state == CARRIED:
		return false  # свою шайбу не выбиваем
	var forward := _forward()
	var to_puck := puck.global_position - _player.global_position
	to_puck.y = 0.0
	var d := to_puck.length()
	if d > params.poke_reach or puck.global_position.y > 0.4:
		return false
	if to_puck.normalized().dot(forward) < 0.5:  # конус ~60° перед собой
		return false
	if _poke_blocked_by_shield(puck):
		return false
	puck.sleeping = false
	puck.linear_velocity = Vector3.ZERO
	puck.apply_central_impulse(to_puck.normalized() * 5.0 * puck.mass)
	_player.kick_anim(0.0)
	last_gesture = "E → отбор: шайба выбита"
	return true


## Укрыта ли шайба корпусом носителя между клюшкой отбирающего и шайбой.
## Против свободной шайбы — нет носителя, укрытия нет. Полноценно — в сетевом
## ТЗ (2-й игрок); здесь каркас: манекен-носитель отсутствует.
func _poke_blocked_by_shield(_puck: RigidBody3D) -> bool:
	return false


## Q/E: фейк корпусом влево/вправо. Дабл-тап той же кнопки в 0.35 с =
## УСИЛЕННЫЙ фейк (обходит кулдаун, импульс x1.6).
func _side_fake(side: float, params: SkatingParams) -> void:
	var dbl: bool = side == _last_fake_side and _last_fake_t >= 0.0
	if _fake_cd > 0.0 and not dbl:
		return
	_fake_cd = params.fake_cooldown
	if dbl:
		_last_fake_t = -1.0  # тройной не спамится
		_last_fake_side = 0.0
	else:
		_last_fake_side = side
		_last_fake_t = 0.0
	var right := _forward().rotated(Vector3.UP, -PI / 2.0)
	_player.body_fake(right * side, params.fake_impulse * (1.6 if dbl else 1.0))
	last_gesture = "%s → фейк %s%s" % ["Q" if side < 0 else "E",
			"влево" if side < 0 else "вправо", " УСИЛ." if dbl else ""]


## SP+назад с внутренней: финт через конёк — клюшка уводит шайбу за спину,
## конёк авто-подставкой возвращает её вперёд в клюшку.
func _skate_feint_start(params: SkatingParams) -> void:
	_skate_feint_t = 0.3  # фаза протяжки (carry за спиной — см. carry-блок)
	_glide_timer = 0.45 + params.gesture_glide_extra
	_player.body_lean(0.0, 0.0)  # сброс событийного крена
	last_gesture = "SP+назад → финт через конёк (за спину)"


## Финт через конёк, фаза 2: авто-подставка. Шайба ОСТАЁТСЯ на ведении —
## carry-точка возвращается из-за спины вперёд (спад _triangle_blend), серво
## гарантированно доводит шайбу обратно в клюшку (release терял её на ходу).
func _kick_return(_params: SkatingParams) -> void:
	if puck_state != CARRIED:
		return
	_player.kick_anim(0.0)
	last_gesture = "конёк → возврат вперёд в клюшку"


## Выстрел из-под конька (выход из треугольника, L+вбок в окне).
func _skate_deflect(lateral: Vector3, params: SkatingParams) -> void:
	_triangle_timer = 0.0
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null or puck_state != CARRIED:
		return
	var forward := _forward()
	var out := (forward + lateral * 0.9).normalized()
	var pv := Vector3(_player.velocity.x, 0, _player.velocity.z)
	puck.sleeping = false
	puck.linear_velocity = Vector3.ZERO
	release_puck(out * (pv.length() * 0.5 + params.kick_forward_speed + 1.4) * puck.mass, false)
	_grace = 0.25
	_player.juke(lateral, params.juke_impulse * 0.7)
	_player.kick_anim(signf(lateral.dot(forward.rotated(Vector3.UP, -PI / 2.0))))
	last_gesture = "конёк → выстрел из треугольника"


## Удар по воздушной шайбе в лёд (направление горизонтальное, вниз добавляется).
func _air_slam(h_dir: Vector3, _params: SkatingParams) -> void:
	# Настильно и ШИРОКО: шайба явно уходит в сторону удара, а не «микродвижение».
	_air_strike(h_dir.normalized() * 1.5 + Vector3.DOWN * 1.5, 9.0)
	# Анимация: резкий мах пера вперёд-вниз с возвратом (виден и в стойке).
	_gesture_azimuth = -30.0
	_gesture_hold = 0.08
	current_roll = -35.0
	_grace = 0.0  # прибитую можно подобрать сразу


## Начало дриблинга (тап ИЛИ удержание). side: -1 = ЛКМ (перевод к хвату,
## внешняя), +1 = ПКМ (от хвата, внутренняя). Ширина растёт в _grow_dribble_hold
## по времени удержания — WASD на ширину НЕ влияет.
func _begin_dribble_hold(side: int, params: SkatingParams) -> void:
	if puck_state != CARRIED:
		return
	_dribble_side = side
	_dribble_t = 0.0
	dribble_width = 0.0
	pose = side
	pose_name = "L" if side == -1 else "R"
	_player.body_lean(-side, deg_to_rad(params.lean_juke) * 0.5)
	last_gesture = "%s → дриблинг %s" % ["L" if side == -1 else "R",
			"к хвату" if side == -1 else "от хвата"]


## Пока кнопка держится — клюшка отводится всё шире (short_pose_angle ->
## wide_pose_angle за hold_max). Отпустил — возврат + juke по ширине.
func _grow_dribble_hold(params: SkatingParams, delta: float) -> void:
	var held: bool = (_dribble_side < 0 and _player.input.pressed("gesture_primary")) \
			or (_dribble_side > 0 and _player.input.pressed("gesture_secondary"))
	if not held or puck_state != CARRIED:
		_end_dribble_hold(params)
		return
	_dribble_t += delta
	dribble_width = clampf(_dribble_t / maxf(params.hold_max, 0.01), 0.0, 1.0)
	var angle: float = lerpf(params.short_pose_angle, params.wide_pose_angle, dribble_width)
	var target: float = -float(_dribble_side) * angle
	var rate: float = rad_to_deg(params.pose_blade_speed / maxf(_reach, 0.3))
	_pose_azimuth = move_toward(_pose_azimuth, target, rate * delta)
	current_roll = move_toward(current_roll,
			-float(_dribble_side) * params.pose_roll, 180.0 * delta)
	pose_progress = dribble_width


## Отпустили дриблинг: широкий (>0.25) даёт боковой шаг корпусом; клюшка
## возвращает шайбу вперёд (плавный возврат к центру).
func _end_dribble_hold(params: SkatingParams) -> void:
	if _dribble_side == 0:
		return
	var side := _dribble_side
	var width := dribble_width
	_dribble_side = 0
	_dribble_t = 0.0
	dribble_width = 0.0
	if width > 0.25 and puck_state == CARRIED:
		var lateral := _forward().rotated(Vector3.UP, -PI / 2.0) * float(-side)
		_player.juke(lateral, params.juke_impulse * width)
	# Возврат клюшки/шайбы вперёд (к центру).
	_pose_from_az = _pose_azimuth
	_pose_to_az = 0.0
	_pose_from_roll = current_roll
	_pose_to_roll = 0.0
	_pose_t = 0.0
	_pose_dur = params.transfer_time


## Треугольник, шаг 1: протяжка шайбы под себя/за спину. Выход — E.
func _triangle_setup(params: SkatingParams) -> void:
	_triangle_timer = params.triangle_window
	_glide_timer = 0.25 + params.gesture_glide_extra  # жест-скольжение
	last_gesture = "L+назад → шайба под себя (E — выход)"


## Банк от борта: настильный толчок вдоль борта, игрок делает шаг ОТ борта
## (не въезжает следом), шайба возвращается на ход умеренной скоростью.
func _bank_off_boards(lateral: Vector3, params: SkatingParams) -> void:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null or puck_state != CARRIED:
		return
	var pv := Vector3(_player.velocity.x, 0, _player.velocity.z)
	var along := pv.normalized() if pv.length() > 1.0 else _forward()
	var bank_dir := (lateral * 0.7 + along * 1.0).normalized()
	puck.sleeping = false
	puck.linear_velocity = Vector3.ZERO
	release_puck(bank_dir * (5.0 + pv.length() * 0.8) * puck.mass, false)
	_player.juke(-lateral, params.juke_impulse)  # полный шаг от борта
	last_gesture = "R+к борту → банк"


## Борт ближе dist в данном направлении?
func _wall_within(dir: Vector3, dist: float, params: SkatingParams) -> bool:
	var probe := _player.global_position + dir.normalized() * dist
	var clamped := _clamp_to_rink(probe, params, 0.0)
	return (clamped - probe).length() > 0.01


## Подброс (CARRIED -> AIR), только с внешней стороны (правило стороны).
func _flip_up(params: SkatingParams) -> void:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null or puck_state != CARRIED:
		return
	_glide_timer = 0.2 + params.gesture_glide_extra
	var pv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	puck.sleeping = false
	# Горизонталь = скорость игрока (летит С ним) + чуть в сторону внешней.
	var hand := _hand_side(_forward(), params)
	puck.linear_velocity = pv + hand * 0.4 + Vector3(0, params.flip_up_speed, 0)
	_grace = params.release_grace
	_set_state(AIR, "подброс")
	last_gesture = "SP → подброс (внешняя)"


## Окно набивания: строго последние juggle_window секунд падения до льда.
## Индикатор для F2 (juggle_open / juggle_frac) обновляется каждый тик.
func _update_juggle_indicator(params: SkatingParams) -> void:
	juggle_open = false
	juggle_frac = 0.0
	if puck_state != AIR or _juggle_cd > 0.0:
		return
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	var to_puck := puck.global_position - global_position
	to_puck.y = 0.0
	if to_puck.length() > params.catch_radius * 3.0:
		return
	var vy: float = puck.linear_velocity.y
	if vy >= 0.0:
		return  # окно — только на падении
	var t_to_ice: float = maxf(puck.global_position.y - PUCK_RADIUS, 0.0) / maxf(-vy, 0.1)
	if t_to_ice <= params.juggle_window:
		juggle_open = true
		juggle_frac = 1.0 - t_to_ice / params.juggle_window


## Набивание: попадание в строгое окно (110 мс до льда) + кулдаун — спам
## невозможен, нужен тайминг. Промах — шайба падает (FREE сама).
func _air_juggle(params: SkatingParams) -> void:
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	if _juggle_cd > 0.0:
		last_gesture = "SP (воздух) → кулдаун набивания"
		return
	if juggle_open:
		var pv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		puck.sleeping = false
		puck.linear_velocity = pv * 0.9 + Vector3(0, params.flip_up_speed, 0)
		_juggle_cd = params.air_juggle_cooldown
		_grace = params.release_grace
		last_gesture = "SP (воздух) → набивание!"
	else:
		last_gesture = "SP (воздух) → мимо окна"


## Вход в позу (сторона: -1=L/внутренняя, +1=R/внешняя). wide — широкий отвод.
func _update_pose(params: SkatingParams, delta: float) -> void:
	if _pose_t < 1.0:
		_pose_t = minf(1.0, _pose_t + delta / _pose_dur)
	var s := smoothstep(0.0, 1.0, _pose_t)
	_pose_azimuth = lerpf(_pose_from_az, _pose_to_az, s)
	current_roll = lerpf(_pose_from_roll, _pose_to_roll, s)
	pose_progress = _pose_t
	if _wobble > 0.0:
		_wobble -= delta
		_pose_azimuth += 8.0 * sin(_wobble * TAU * 6.0)


## Отбор манекеном: шайба выбивается прочь от точки отбора; короткий запрет
## подбора, чтобы игрок не подхватывал её тем же тиком.
func poke_loose(from_pos: Vector3) -> void:
	if puck_state != CARRIED:
		return
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null:
		return
	var away := puck.global_position - from_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else _forward()
	puck.sleeping = false
	release_puck(away * 6.0 * puck.mass, false)
	_grace = 0.45
	last_gesture = "отбор манекеном!"


func _air_strike(dir: Vector3, speed: float = 3.0) -> void:
	if puck_state != AIR:
		return
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck:
		# Гасим текущую скорость: удар задаёт шайбе НОВУЮ скорость, а не добавку.
		puck.sleeping = false
		puck.linear_velocity = Vector3.ZERO
		puck.apply_central_impulse(dir.normalized() * speed * puck.mass)


# --- Геометрия / контакты ---------------------------------------------------

func _hand_side(forward: Vector3, params: SkatingParams) -> Vector3:
	var left := forward.rotated(Vector3.UP, PI / 2.0)
	var stick_left := params.handedness_right == HAND_TO_LEFT
	return left if stick_left else -left


func _compute_pivot(params: SkatingParams, forward: Vector3) -> Vector3:
	var hand := _hand_side(forward, params)
	var p := _player.global_position + hand * params.hand_offset_side + forward * params.hand_offset_forward
	p.y = 0.0
	return p


func _dir_from_e(e: float, forward: Vector3, params: SkatingParams) -> Vector3:
	var hand := _hand_side(forward, params)
	var sign_to_hand := 1.0 if forward.rotated(Vector3.UP, deg_to_rad(90.0)).dot(hand) > 0.0 else -1.0
	return forward.rotated(Vector3.UP, deg_to_rad(e) * sign_to_hand)


func _neutral(params: SkatingParams) -> float:
	return params.neutral_angle


func zone_outline(steps := 40) -> PackedVector3Array:
	var points := PackedVector3Array()
	var params: SkatingParams = _player.params
	var forward := _forward()
	var lo := params.backhand_limit - (STANCE_SECTOR_EXPAND if _player.is_stance else 0.0)
	var hi := params.forehand_limit + (STANCE_SECTOR_EXPAND if _player.is_stance else 0.0)
	for i in steps + 1:
		var e := lerpf(lo, hi, float(i) / steps)
		points.append(pivot_point + _dir_from_e(e, forward, params) * _reach + Vector3(0, 0.04, 0))
	return points


func _resolve_fast_sweep(from: Vector3, to: Vector3) -> void:
	var motion := to - from
	if motion.length() < 0.06:
		return
	if motion.length() > 1.0:
		return  # телепорт/скачок кадра, не физический свип — не бить шайбу
	var puck := get_tree().get_first_node_in_group("puck") as RigidBody3D
	if puck == null or puck_state == CARRIED:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _box
	query.transform = Transform3D(global_transform.basis, Vector3(from.x, BLADE_Y, from.z))
	query.motion = motion
	query.collision_mask = 2
	var result := get_world_3d().direct_space_state.cast_motion(query)
	if result[0] >= 1.0:
		return
	var dir := motion.normalized()
	var rel := (blade_velocity - puck.linear_velocity).dot(dir)
	if rel <= 4.0:
		return
	# Кап импульса физическим пределом крюка (страховка от скачков):
	# линейная скорость из угловой (макс. из обычной и позовой) на текущем плече.
	var params: SkatingParams = _player.params
	var max_lin := maxf(deg_to_rad(params.blade_angular_speed) * _reach, params.pose_blade_speed)
	rel = minf(rel, max_lin * 1.5)
	puck.apply_central_impulse(dir * rel * 1.05 * puck.mass)


func _forward() -> Vector3:
	var f := -_player.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


## Аналитический клэмп точки в коробку катка (прямые борта + дуги углов).
func _clamp_to_rink(p: Vector3, params: SkatingParams, margin: float) -> Vector3:
	var hx := params.rink_length / 2.0 - margin
	var hz := params.rink_width / 2.0 - margin
	p.x = clampf(p.x, -hx, hx)
	p.z = clampf(p.z, -hz, hz)
	var cr: float = params.corner_radius
	var cx := params.rink_length / 2.0 - cr
	var cz := params.rink_width / 2.0 - cr
	if absf(p.x) > cx and absf(p.z) > cz:
		var center := Vector3(signf(p.x) * cx, 0.0, signf(p.z) * cz)
		var d := p - center
		var r := cr - margin
		if d.length() > r:
			p = center + d.normalized() * r
	return p


# --- Визуал -----------------------------------------------------------------

func _build_stick_visual() -> void:
	var params: SkatingParams = _player.params
	var boom := sqrt(params.stick_length * params.stick_length + HAND_HEIGHT * HAND_HEIGHT)
	var scene: PackedScene = load(MODEL_PATH)
	if scene != null:
		_stick_model = scene.instantiate()
		_stick_root.add_child(_stick_model)
		# Ориентация меша выводится из ЕГО ВЕРШИН (у FBX свои оси, слепые
		# повороты мазали): длинная ось -> слот-Y (шафт вверх), перо -> вниз.
		_fit_stick_model()
		_model_scale = boom / maxf(_measured_length, 0.1)
		# Флэт-стиль: один плоский цвет, roughness 1 (без бликов/PBR).
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.16, 0.17, 0.20)
		flat.roughness = 1.0
		for mi in _stick_model.find_children("*", "MeshInstance3D"):
			mi.material_override = flat
	else:
		_stick_model = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, MODEL_NATURAL_LENGTH, 0.05)
		_stick_model.mesh = box
		_model_scale = 1.0
		_stick_root.add_child(_stick_model)
		_stick_model.position = Vector3(0, -MODEL_NATURAL_LENGTH / 2.0, 0)


## Выставляет ориентацию/позицию _stick_model по вершинам меша:
## длинная ось (шафт) -> слот-Y вверх, перо (конец с широким поперечником) ->
## вниз, изгиб пера -> слот +X; верхний торец ручки -> в origin слота (руки).
func _fit_stick_model() -> void:
	var mis := _stick_model.find_children("*", "MeshInstance3D")
	if mis.is_empty():
		return
	var mi := mis[0] as MeshInstance3D
	# Вершины в координатах корня модели (до нашей коррекции).
	var chain := Transform3D.IDENTITY
	var n: Node3D = mi
	while n != null and n != _stick_model:
		chain = n.transform * chain
		n = n.get_parent() as Node3D
	var verts := PackedVector3Array()
	for v in mi.mesh.get_faces():
		verts.append(chain * v)
	# Длинная ось = наибольший размах AABB.
	var mn := verts[0]
	var mx := verts[0]
	for p in verts:
		mn = mn.min(p)
		mx = mx.max(p)
	var ext := mx - mn
	var long_i := 0
	if ext.y > ext[long_i]:
		long_i = 1
	if ext.z > ext[long_i]:
		long_i = 2
	_measured_length = ext[long_i]
	var lo: float = mn[long_i]
	var hi: float = mx[long_i]
	# Перо — конец с большим поперечным размахом (крайние 20% длины).
	var band := 0.2 * _measured_length
	var lo_spread := 0.0
	var hi_spread := 0.0
	var lo_centroid := Vector3.ZERO
	var lo_count := 0
	var hi_centroid := Vector3.ZERO
	var hi_count := 0
	for p in verts:
		var t: float = p[long_i]
		var lateral := p
		lateral[long_i] = 0.0
		if t < lo + band:
			lo_spread = maxf(lo_spread, lateral.length())
			lo_centroid += lateral
			lo_count += 1
		elif t > hi - band:
			hi_spread = maxf(hi_spread, lateral.length())
			hi_centroid += lateral
			hi_count += 1
	var blade_at_lo := lo_spread > hi_spread
	# Оси в пространстве модели: y_dir — от пера к ручке (вверх).
	var y_dir := Vector3.ZERO
	y_dir[long_i] = 1.0 if blade_at_lo else -1.0
	var blade_centroid := (lo_centroid / maxf(lo_count, 1)) if blade_at_lo else (hi_centroid / maxf(hi_count, 1))
	var x_dir := blade_centroid
	x_dir[long_i] = 0.0
	if x_dir.length() < 0.001:
		x_dir = Vector3(0, 0, 1) if long_i != 2 else Vector3(1, 0, 0)
	x_dir = x_dir.normalized()  # направление изгиба пера
	var z_dir := x_dir.cross(y_dir).normalized()
	x_dir = y_dir.cross(z_dir).normalized()
	# R переводит модельные оси в слот: столбцы = образы базиса.
	var rot := Basis(x_dir, y_dir, z_dir).transposed()  # ортонормальный -> inverse
	_stick_model.transform = Transform3D(rot, Vector3.ZERO)
	# Верхний торец ручки -> origin слота (руки).
	var top := -1e9
	for p in verts:
		top = maxf(top, (rot * p).y)
	_stick_model.position.y = -top


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.top_level = true
	var disc := CylinderMesh.new()
	disc.top_radius = 0.09
	disc.bottom_radius = 0.09
	disc.height = 0.004
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.35)
	disc.material = m
	_marker.mesh = disc
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func _update_marker() -> void:
	var mcol := Color(0.5, 0.5, 0.5, 0.5)
	if puck_state == CARRIED:
		mcol = Color(0.2, 0.85, 0.35, 0.55) if not transfer_active else Color(1.0, 0.75, 0.2, 0.6)
	elif puck_state == AIR:
		mcol = Color(0.6, 0.4, 1.0, 0.55)
	_marker.get_active_material(0).albedo_color = mcol
	_marker.global_position = _player.global_position + Vector3(0, 0.015, 0)


## Визуал клюшки (вызывается из _process — каждый кадр, со сглаживанием).
## ЖЁСТКИЙ ЯКОРЬ: верх шафта ВСЕГДА в точке рук на капсуле; ось шафта вниз к
## физическому крюку (перо у льда). Ориентация сглаживается slerp'ом —
## дискретные 60 Гц шаги физики не читаются как тряска меша.
func _update_stick_visual(forward: Vector3, params: SkatingParams, delta: float) -> void:
	if _stick_model == null:
		return
	var hand := _hand_side(forward, params)
	var hands := _player.global_position + hand * params.hand_offset_side + Vector3(0, HAND_HEIGHT, 0)
	var crook := global_position
	# Замах щелчка: перо ПОДНИМАЕТСЯ вверх по заряду (клюшка вращается вокруг
	# рук) — сильный бросок читается по поднятой клюшке.
	crook.y = 0.02 + windup * 1.15
	var dir := hands - crook
	if dir.length() < 0.05:
		return
	var y_axis := dir.normalized()  # +Y — вверх вдоль шафта, к рукам
	var ref := crook - pivot_point
	ref.y = 0.0
	var z_axis := ref - y_axis * ref.dot(y_axis)
	if z_axis.length() < 0.01:
		z_axis = forward
	z_axis = z_axis.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	var mirror := 1.0 if (params.handedness_right == HAND_TO_LEFT) else -1.0
	# Наклон пера (roll) — вокруг оси шафта.
	var ori := Basis(x_axis, y_axis, z_axis).rotated(y_axis, deg_to_rad(current_roll) * mirror)
	# Сглаживание ориентации (высокая скорость — без визуального лага, но без дрожи).
	var target_q := ori.get_rotation_quaternion()
	if _stick_q != Quaternion.IDENTITY:
		_stick_q = _stick_q.slerp(target_q, 1.0 - exp(-25.0 * delta))
	else:
		_stick_q = target_q
	var basis := Basis(_stick_q).scaled(Vector3(_model_scale * mirror, _model_scale, _model_scale))
	_stick_root.top_level = true
	_stick_root.global_transform = Transform3D(basis, hands)
	# Направление изгиба крюка в мире (для регресс-теста хвата), без учёта roll.
	bend_dir = (x_axis * mirror * BEND_SIGN).normalized()


## Мировой AABB меша клюшки (для автотеста ориентации: перо у льда, шафт вверх).
func stick_world_aabb() -> AABB:
	var result := AABB()
	var first := true
	for mi in _stick_model.find_children("*", "MeshInstance3D"):
		var m := mi as MeshInstance3D
		var local := m.mesh.get_aabb()
		var xf := m.global_transform
		for cx in [0, 1]:
			for cy in [0, 1]:
				for cz in [0, 1]:
					var corner := xf * (local.position + Vector3(cx, cy, cz) * local.size)
					if first:
						result = AABB(corner, Vector3.ZERO)
						first = false
					else:
						result = result.expand(corner)
	return result
