extends AnimatableBody3D
class_name Goalie
## Вратарь: играбельный (params.goalie_player_controlled) И простой AI.
## Модель собирается процедурно (примитивы + меши экипировки с fallback).
## Всегда лицом к шайбе. Ловушка на ЛЕВОЙ руке, блин на ПРАВОЙ (зеркало —
## goalie_handedness_right). Механики таймингово-зонные (не автоблок).
## Зоны ворот — данные (см. ZONE_*), перекрытие зависит от позы.

# Машина состояний: движение WASD ТОЛЬКО в STANCE (медленно). BUTTERFLY/DIVE/
# RECOVER — позы НА МЕСТЕ (без velocity/импульса), только доводка позы 0.15 с.
enum { STANCE, BUTTERFLY, FALL_LEFT, FALL_RIGHT, RECOVER }
# Зоны створа (относительно вратаря, смотрящего на шайбу).
enum { Z_FIVE_HOLE, Z_LOW_LEFT, Z_LOW_RIGHT, Z_HIGH_LEFT, Z_HIGH_RIGHT, Z_MID }

const GOAL_WIDTH := 1.83
const GOAL_HEIGHT := 1.22
const HALF_W := 0.915

const JERSEY := Color(0.15, 0.28, 0.55)
const PAD_COL := Color(0.9, 0.9, 0.93)
const CATCH_COL := Color(0.85, 0.7, 0.2)
const BLOCK_COL := Color(0.2, 0.2, 0.24)

var goal_center := Vector3.ZERO   # центр линии ворот (y=0)
var out_dir := Vector3(-1, 0, 0)  # нормаль в поле (куда смотрит вратарь)
var state := STANCE
var puck_in_catch := false        # шайба поймана в ловушку (можно выбросить)

var _params: SkatingParams
var _puck: RigidBody3D
var _player: Node3D
var input := InputState.new()    # ввод вратаря (локально snap / из сети — сеть v1)
var input_local := true
# Сеть: на сервере вратаря пира разворачиваем по присланному yaw камеры (нет
# локальной камеры пира). На клиенте кукла — только поза из снапшота (puppet).
var use_net_yaw := false
var net_yaw := 0.0
var puppet := false
var _pose := 0.0                  # 0 стойка .. 1 баттерфляй (сглажено)
var _fall_side := 0.0            # -1 влево, +1 вправо (падение)
var _recovery := 0.0            # таймер восстановления после падения
var _save_cd := 0.0
var _catch_flash := 0.0         # ловушка тянется (визуал/окно)
var _block_flash := 0.0
var _react_timer := -1.0        # AI: отложенная реакция на бросок
var _react_action := ""
var _shot_seen := false
var _ai_save_action := ""       # AI: активная попытка сейва (окно)
var _ai_save_window := 0.0
# Узлы модели (процедурная поза)
var _visual: Node3D    # корень всех частей (падение вбок вращает его целиком)
var _torso: Node3D
var _head: Node3D
var _catcher: Node3D
var _blocker: Node3D
var _pad_l: Node3D
var _pad_r: Node3D
# Физические коллайдеры (следуют за позой)
var _col_torso: CollisionShape3D
var _col_pad_l: CollisionShape3D
var _col_pad_r: CollisionShape3D
var _col_helmet: CollisionShape3D
var _col_blocker: CollisionShape3D
var _col_catcher: CollisionShape3D
# Тайминг-окна ловушки/блина (активная фаза), предикт, GLOVED, пуш
var _catch_win_t := 0.0           # активное окно ловушки (ЛКМ)
var _block_win_t := 0.0           # активное окно блина (ПКМ)
var _glove_hold_t := 0.0          # удержание пойманной (>2 с = свисток)
var _predict := Vector3.ZERO      # предикт-точка перехвата (F2)
var _dtap_side := 0.0             # дабл-тап для баттерфляй-пуша
var _dtap_t := -1.0
var _push_t := 0.0                # активный слайд пуша
var _push_from := Vector3.ZERO
var _push_to := Vector3.ZERO
var _push_cd := 0.0
# F2/тесты
var last_action := "-"
var last_verdict := "-"           # CAUGHT/DEFLECTED/TOO_EARLY/TOO_LATE/WRONG_SIDE/OUT_OF_REACH
var debug_draw := false           # отрисовка зон/досягаемости (ставит main по F2)
var _gizmo: MeshInstance3D


func setup(p_goal_center: Vector3, p_out_dir: Vector3, player: Node3D,
		puck: RigidBody3D, params: SkatingParams) -> void:
	goal_center = p_goal_center
	out_dir = p_out_dir.normalized()
	_player = player
	_puck = puck
	_params = params
	sync_to_physics = false
	collision_layer = 32   # слой стен: корпус физически перекрывает часть створа
	collision_mask = 0
	add_to_group("goalie")
	global_position = goal_center + out_dir * 0.3
	# CCD шайбы: не туннелирует сквозь тонкие щитки на скорости.
	puck.continuous_cd = true
	_build_model()


# --- Ориентиры: лево/право вратаря (лицом к шайбе) ---
func _facing() -> Vector3:
	var f := out_dir
	if _puck:
		var to_puck := _puck.global_position - global_position
		to_puck.y = 0.0
		if to_puck.length() > 0.2:
			f = to_puck.normalized()
	return f


func _right() -> Vector3:
	return _facing().rotated(Vector3.UP, -PI / 2.0)


## Знак стороны ловушки в осях вратаря: ловушка на ЛЕВОЙ руке (-1), блин (+1).
func _catch_sign() -> float:
	return -1.0 if _params.goalie_handedness_right else 1.0


func _build_model() -> void:
	# ФИЗИЧЕСКИЕ коллайдеры по частям (следуют за позой в _sync_colliders):
	# торс, каждый щиток, шлем, блин, ловушка. Сейв = физический контакт.
	# Щиткам паддинг +2 см (тонкие — против туннелирования шайбы).
	_col_torso = _add_col(_capsule(0.26, 0.75))
	_col_pad_l = _add_col(_boxshape(0.28, 0.62, 0.32))
	_col_pad_r = _add_col(_boxshape(0.28, 0.62, 0.32))
	_col_helmet = _add_col(_sphere(0.21))
	_col_blocker = _add_col(_boxshape(0.32, 0.34, 0.16))
	_col_catcher = _add_col(_sphere(0.16))
	# Гасящий контакт (щитки/торс: bounce низкий — ребаунд в слот, добивания).
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.4
	physics_material_override = pm

	# Визуальный корень: все части в нём (падение — поза, не крен корня).
	_visual = Node3D.new()
	add_child(_visual)

	# Пользовательская модель со слотами (см. docs/GOALIE_MODEL.md): если есть
	# scenes/GoalieModel.tscn — инстанцируем и анимируем её слоты; иначе примитивы.
	if _try_user_model():
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = JERSEY
	mat.roughness = 1.0
	# Верхний корпус — узкий, ВЫШЕ ног (перёд модели = -Z).
	_torso = _prim(CylinderMesh.new(), mat, Vector3(0, 0.85, 0))
	var cyl: CylinderMesh = _torso.get_child(0).mesh
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.3
	cyl.height = 0.75
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.85, 0.85, 0.9)
	hmat.roughness = 1.0
	_head = _prim(SphereMesh.new(), hmat, Vector3(0, 1.42, 0))
	(_head.get_child(0).mesh as SphereMesh).radius = 0.2
	(_head.get_child(0).mesh as SphereMesh).height = 0.4

	# Щитки — крупные «доски» на голенях, НИЖЕ корпуса и ВПЕРЕДИ (видны, не в теле).
	_pad_l = _pad(-1.0)
	_pad_r = _pad(1.0)
	# Ловушка (лево) и блин (право) — на руках, на высоте пояса, СПЕРЕДИ и шире плеч.
	var cs := _catch_sign()
	_catcher = _hand(CATCH_COL, cs)
	_blocker = _hand(BLOCK_COL, -cs)


func _add_col(shape: Shape3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	return cs


func _capsule(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s


func _boxshape(x: float, y: float, z: float) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(x, y, z)
	return s


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


## Синхронизация коллайдеров с визуальными частями (следуют за позой).
## Ловушка в активном окне — коллайдер OFF (ловит проверкой близости, не бьёт).
func _sync_colliders() -> void:
	if _col_torso == null:
		return
	_col_torso.transform = _torso.transform
	_col_pad_l.transform = _pad_l.transform
	_col_pad_r.transform = _pad_r.transform
	_col_helmet.transform = _head.transform
	_col_blocker.transform = _blocker.transform
	_col_catcher.transform = _catcher.transform
	# Ловушка в активном окне — не твёрдая (ловит, а не отбивает).
	_col_catcher.disabled = _catch_win_t > 0.0


func _prim(mesh: Mesh, mat: Material, pos: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	holder.add_child(mi)
	_visual.add_child(holder)
	return holder


func _pad(side: float) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAD_COL
	mat.roughness = 1.0
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.6, 0.3)
	# Голень спереди: ниже корпуса (y 0..0.6) и вынесено ВПЕРЁД (z<0), чтобы не
	# тонуть в корпусе.
	return _prim(box, mat, Vector3(side * 0.17, 0.3, -0.26))


func _hand(col: Color, side: float) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.32, 0.12)
	# Рука с ловушкой/блином: на высоте пояса, вынесена вбок и ВПЕРЁД (-Z).
	return _prim(box, mat, Vector3(side * 0.46, 0.95, -0.28))


## Пользовательская модель: инстанс scenes/GoalieModel.tscn, слоты slot_*
## назначаются на _torso/_head/_pad_l/_pad_r/_catcher/_blocker для анимации.
func _try_user_model() -> bool:
	if not ResourceLoader.exists("res://scenes/GoalieModel.tscn"):
		return false
	var scene := load("res://scenes/GoalieModel.tscn") as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate()
	_visual.add_child(model)
	_torso = model.find_child("slot_body", true, false) as Node3D
	_head = model.find_child("slot_helmet", true, false) as Node3D
	_pad_l = model.find_child("slot_pad_l", true, false) as Node3D
	_pad_r = model.find_child("slot_pad_r", true, false) as Node3D
	var cs := _catch_sign()
	# Ловушка на левой руке при правом хвате (cs<0 -> слот слева).
	var left_slot := model.find_child("slot_catcher", true, false) as Node3D
	var right_slot := model.find_child("slot_blocker", true, false) as Node3D
	_catcher = left_slot
	_blocker = right_slot
	# Заглушки для отсутствующих слотов (чтобы поза не падала на null).
	var fallback := Node3D.new()
	add_child(fallback)
	if _torso == null: _torso = fallback
	if _head == null: _head = fallback
	if _pad_l == null: _pad_l = fallback
	if _pad_r == null: _pad_r = fallback
	if _catcher == null: _catcher = fallback
	if _blocker == null: _blocker = fallback
	return true


func _physics_process(delta: float) -> void:
	# Сетевая кукла: позиция/ориентация/состояние приходят из снапшота,
	# локально проигрываем только процедурную позу (без симуляции/движения).
	if puppet:
		_update_pose(delta)
		_sync_colliders()
		return
	if _params == null or _puck == null:
		return
	_save_cd = maxf(0.0, _save_cd - delta)
	_catch_flash = maxf(0.0, _catch_flash - delta)
	_block_flash = maxf(0.0, _block_flash - delta)
	_push_cd = maxf(0.0, _push_cd - delta)
	if _dtap_t >= 0.0:
		_dtap_t += delta
		if _dtap_t > 0.25:
			_dtap_t = -1.0
	# Восстановление после баттерфляя/падения: RECOVER, неподвижен, затем встаёт.
	if _recovery > 0.0:
		_recovery -= delta
		if _recovery <= 0.0 and state == RECOVER:
			state = STANCE

	# Обновление предикт-точки перехвата (для рук и F2).
	_predict = _predict_front_point()

	var prev := global_position
	if _params.goalie_player_controlled:
		_control_player(delta)
	else:
		_control_ai(delta)

	# Баттерфляй-пуш: слайд к фиксированной точке (один импульс, не свободное движение).
	if _push_t > 0.0:
		_push_t -= delta
		var k: float = clampf(1.0 - _push_t / 0.25, 0.0, 1.0)
		var np := _push_from.lerp(_push_to, k)
		global_position.x = np.x
		global_position.z = np.z

	# Активные окна ловушки/блина: тянемся, ловим/отбиваем на контакте.
	_update_save_windows(delta)
	# GLOVED: пойманная шайба следует за ловушкой (kinematic).
	if puck_in_catch:
		_glove_hold_t += delta
		_puck.global_position = _catcher.global_position
		_puck.linear_velocity = Vector3.ZERO
		if _glove_hold_t > 2.0:
			_freeze_whistle()

	# ЖЁСТКИЙ clamp позиции в любом состоянии: вратарь не выходит за goalie_range.
	global_position = _clamp_range(global_position)
	global_position.y = 0.0
	# Ориентация: играбельный — КАМЕРОЙ (куда смотрю); AI — на шайбу.
	if _params.goalie_player_controlled:
		_face_camera(delta)
	else:
		_face_puck(delta)
	_update_pose(delta)
	_sync_colliders()
	constant_linear_velocity = (global_position - prev) / delta
	_draw_debug()


# --- Позиционирование ---
func _face_puck(delta: float) -> void:
	var f := _facing()
	# +PI: -basis.z (перёд ноды) смотрит вдоль f, а не против.
	rotation.y = lerp_angle(rotation.y, atan2(f.x, f.z) + PI, 1.0 - exp(-12.0 * delta))


## Играбельный вратарь: корпус смотрит КУДА СМОТРИТ КАМЕРА (управление камерой).
func _face_camera(delta: float) -> void:
	if use_net_yaw:
		# Разворот по присланному yaw камеры пира (сервер: у пира нет своей камеры).
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		return
	f = f.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(f.x, f.z) + PI, 1.0 - exp(-14.0 * delta))


## Держаться на линии между шайбой и центром ворот, в пределах goalie_range.
func _move_toward_arc(delta: float) -> void:
	var to_puck := _puck.global_position - goal_center
	to_puck.y = 0.0
	if to_puck.length() < 0.1:
		return
	var depth := 0.45  # немного перед линией
	var target := goal_center + to_puck.normalized() * depth
	# Боковое смещение перехватывает угол, но в пределах створа.
	target.z = goal_center.z + clampf(_puck.global_position.z - goal_center.z, -HALF_W, HALF_W) * 0.7
	_step_to(target, delta)


## Шаг к цели на ногах (медленно). Вызывается ТОЛЬКО в STANCE (движение
## запрещено в баттерфляе/падении/recover). Спринта/рывка у вратаря нет.
func _step_to(target: Vector3, delta: float) -> void:
	target = _clamp_range(target)
	var sp: float = _params.max_speed * _params.goalie_move_speed
	var flat := global_position
	flat.y = 0.0
	var nt := flat.move_toward(Vector3(target.x, 0, target.z), sp * delta)
	global_position.x = nt.x
	global_position.z = nt.z
	global_position.y = 0.0


func _clamp_range(p: Vector3) -> Vector3:
	var off := p - goal_center
	off.y = 0.0
	# В поле, не за линию ворот (along >= 0).
	var along := off.dot(out_dir)
	if along < 0.0:
		off -= out_dir * along
	# Радиальный клэмп: расстояние от центра ворот <= goalie_range.
	if off.length() > _params.goalie_range:
		off = off.normalized() * _params.goalie_range
	return goal_center + off


func in_range(p: Vector3) -> bool:
	return (_clamp_range(p) - p).length() < 0.01


# --- Играбельное управление (как у полевого: WASD ОТНОСИТЕЛЬНО КАМЕРЫ, мышь
# вращает камеру). Отличие вратаря: корпус всегда лицом к шайбе (спиной к
# своим воротам) — _face_puck; движение свободное в пределах зоны. ---
func _control_player(delta: float) -> void:
	if input_local:
		input.poll_local()  # ввод вратаря (сеть v1: единственный источник)
	var hold := input.pressed("gesture_lift")  # Пробел = баттерфляй/падение
	# Баттерфляй-пуш: ДАБЛ-ТАП A/D сидя в бабочке — слайд к штанге (не свободное
	# движение). Детект до fall-логики; активный пуш держит позу BUTTERFLY.
	_detect_push(hold)
	if _push_t > 0.0:
		state = BUTTERFLY
	elif hold:
		# Сторона падения — по WASD влево/вправо относительно ВРАТАРЯ (facing).
		var lat := input.strength("turn_right") - input.strength("turn_left")
		if lat < -0.3:
			state = FALL_LEFT
		elif lat > 0.3:
			state = FALL_RIGHT
		else:
			state = BUTTERFLY
	else:
		# Отпустил Пробел из низкой позы — встаём (RECOVER, неподвижно 0.3 с).
		if state == BUTTERFLY or state == FALL_LEFT or state == FALL_RIGHT:
			state = RECOVER
			_recovery = 0.3
	# Движение WASD — ТОЛЬКО стоя на ногах (STANCE), медленно.
	if state == STANCE:
		var wish := _wasd_camera()
		if wish != Vector3.ZERO:
			_step_to(global_position + wish, delta)
	if input.just_pressed("gesture_primary"):
		catch()
	if input.just_pressed("gesture_secondary"):
		blocker()


## Детект дабл-тапа A/D для баттерфляй-пуша (только в бабочке, вне кулдауна).
func _detect_push(hold: bool) -> void:
	for side in [-1, 1]:
		var act := "turn_left" if side < 0 else "turn_right"
		if input.just_pressed(act):
			if hold and _dtap_t >= 0.0 and int(_dtap_side) == side and _push_cd <= 0.0 and _push_t <= 0.0:
				start_push(side)
				_dtap_t = -1.0
			else:
				_dtap_side = float(side)
				_dtap_t = 0.0


## Баттерфляй-пуш: один импульс-слайд на push_distance к штанге, clamp в зоне.
func start_push(side: int) -> void:
	_push_t = 0.25
	_push_from = global_position
	var tgt := _clamp_range(global_position + _right() * float(side) * _params.push_distance)
	_push_to = Vector3(tgt.x, 0, tgt.z)
	_push_cd = _params.push_cooldown
	last_action = "баттерфляй-пуш %s" % ("влево" if side < 0 else "вправо")


## Направление WASD относительно камеры (как у полевого игрока).
func _wasd_camera() -> Vector3:
	var x := input.strength("turn_right") - input.strength("turn_left")
	var fwd := input.strength("move_forward") - input.strength("move_back")
	if absf(x) < 0.1 and absf(fwd) < 0.1:
		return Vector3.ZERO
	var yaw := 0.0
	if use_net_yaw:
		yaw = net_yaw   # сеть: yaw камеры пира из пакета ввода
	else:
		var cam := get_viewport().get_camera_3d()
		if cam:
			yaw = cam.global_rotation.y
	return Vector3(x, 0, -fwd).rotated(Vector3.UP, yaw).normalized() * 1.6


# --- Механики (методы — для игрока И AI, и для тестов) ---

## ЛКМ/ловушка: открывает АКТИВНОЕ ОКНО. Ловля — на физическом контакте шайбы
## с ловушкой внутри окна (см. _update_save_windows). Повторный ЛКМ из GLOVED =
## выброс. Промах = кулдаун. Возвращает true, если окно открылось/выброс.
func catch() -> bool:
	if puck_in_catch:
		throw_puck()
		return true
	# Накрывание лежащей шайбы в баттерфляе (медленная свободная у ног).
	if state == BUTTERFLY and _cover_loose():
		return true
	if _save_cd > 0.0:
		return false
	_save_cd = _params.goalie_save_cooldown
	_catch_win_t = _params.catch_window
	_catch_flash = _params.catch_window
	last_verdict = _pre_verdict(_catch_sign())  # WRONG_SIDE / OUT_OF_REACH / pending
	if last_verdict != "pending":
		_log("ЛОВУШКА", last_verdict)
	last_action = "ловушка: окно"
	return true


## ПКМ/блин: открывает окно; отбивание — на контакте шайбы с блином в окне.
func blocker() -> bool:
	if _save_cd > 0.0:
		return false
	_save_cd = _params.goalie_save_cooldown
	_block_win_t = _params.catch_window
	_block_flash = _params.catch_window
	last_verdict = _pre_verdict(-_catch_sign())
	if last_verdict != "pending":
		_log("БЛИН", last_verdict)
	last_action = "блин: окно"
	return true


## Лог вердикта в консоль (только при F2 — иначе спам на стресс-тестах).
func _log(what: String, verdict: String) -> void:
	if debug_draw:
		print("GOALIE ", what, ": ", verdict)


## Прогноз-вердикт при нажатии: та ли рука/сторона и достанет ли предикт.
## sign: сторона руки (ловушка = _catch_sign, блин = -_catch_sign).
## Боковая ось ВОРОТ (фиксированная, не зависит от разворота вратаря к шайбе).
func _net_right() -> Vector3:
	return out_dir.rotated(Vector3.UP, -PI / 2.0)


func _pre_verdict(sign: float) -> String:
	# Половина ВОРОТ (фикс. ось), s>0 = правая. Ловушка (sign<0) — левая
	# половина (s <= +0.1); блин (sign>0) — правая (s >= -0.1).
	var s := (_predict - goal_center).dot(_net_right())
	if sign < 0.0 and s > 0.1:
		return "WRONG_SIDE"
	if sign > 0.0 and s < -0.1:
		return "WRONG_SIDE"
	var dist := (_predict - global_position)
	dist.y = 0.0
	if dist.length() > _params.catch_reach + 0.15:
		return "OUT_OF_REACH"
	return "pending"


## Активные окна: пока окно живо, ловим (ловушка) / отбиваем (блин) на контакте
## шайбы с рукой (близость к предикт-руке в своей половине).
func _update_save_windows(delta: float) -> void:
	if _catch_win_t > 0.0:
		_catch_win_t -= delta
		if not puck_in_catch and not _puck.freeze:
			var d := (_puck.global_position - _catcher.global_position).length()
			if d < 0.24 and _puck.linear_velocity.y < GOAL_HEIGHT + 1.0:
				_puck.freeze = true
				_puck.linear_velocity = Vector3.ZERO
				puck_in_catch = true
				_glove_hold_t = 0.0
				last_verdict = "CAUGHT"
				last_action = "ловушка: поймал"
				_catch_win_t = 0.0
				_log("ЛОВУШКА", "CAUGHT")
		if _catch_win_t <= 0.0 and last_verdict == "pending":
			last_verdict = "TOO_LATE"
			_log("ЛОВУШКА", "TOO_LATE")
	if _block_win_t > 0.0:
		_block_win_t -= delta
		var d := (_puck.global_position - _blocker.global_position).length()
		if not _puck.freeze and d < 0.28:
			var refl := (out_dir + _right() * signf(-_catch_sign()) * 1.2).normalized()
			_puck.linear_velocity = Vector3.ZERO
			_puck.apply_central_impulse((refl + Vector3.UP * 0.2).normalized() * 8.0 * _puck.mass)
			last_verdict = "DEFLECTED"
			last_action = "блин: отбил"
			_block_win_t = 0.0
			_log("БЛИН", "DEFLECTED")
		if _block_win_t <= 0.0 and last_verdict == "pending":
			last_verdict = "TOO_LATE"
			_log("БЛИН", "TOO_LATE")


## Заморозка-свисток (заготовка): удержание пойманной >2 с — респаун/вбрасывание.
func _freeze_whistle() -> void:
	last_action = "свисток (заготовка)"
	# Пока просто держим шайбу замороженной; регламент вбрасывания — этап правил.


## Падение (desperation) — ПОЗА НА МЕСТЕ (для AI; у игрока — из _control_player).
## НЕТ velocity/импульса: тело не двигается, таз смещается визуально позой
## (_update_pose), перекрытие даёт вытянутая нога-щиток. Смещение позы clamp'ится.
func fall(side: int) -> void:
	state = FALL_LEFT if side < 0 else FALL_RIGHT
	_fall_side = float(side)


## Выброс пойманной шайбы игроку (или вперёд в поле).
func throw_puck() -> void:
	if not puck_in_catch:
		return
	puck_in_catch = false
	_puck.freeze = false
	var dir := out_dir
	if _player:
		var to_p := _player.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 0.5:
			dir = to_p.normalized()
	_puck.global_position = global_position + dir * 0.6 + Vector3(0, 0.2, 0)
	_puck.linear_velocity = Vector3.ZERO
	_puck.apply_central_impulse((dir + Vector3.UP * 0.15).normalized() * 12.0 * _puck.mass)
	last_action = "выброс шайбы"


## Шайба в зоне ловушки/блина (сектор со стороны sign) И приближается (окно).
func _cover_loose() -> bool:
	if _puck.freeze:
		return false
	var to_puck := _puck.global_position - global_position
	to_puck.y = 0.0
	if to_puck.length() <= _params.cover_radius and _puck.linear_velocity.length() < 4.0:
		_puck.freeze = true
		_puck.linear_velocity = Vector3.ZERO
		puck_in_catch = false
		last_action = "накрыл шайбу"
		return true
	return false


# --- Зоны ворот (данные) ---
## Классифицировать точку створа в зону (в осях вратаря).
func zone_of(world_point: Vector3) -> int:
	var s := (world_point - goal_center).dot(_right())  # <0 слева вратаря
	var y := world_point.y
	var low := y < GOAL_HEIGHT * 0.42
	var high := y > GOAL_HEIGHT * 0.62
	if low and absf(s) < 0.28:
		return Z_FIVE_HOLE
	if low:
		return Z_LOW_LEFT if s < 0.0 else Z_LOW_RIGHT
	if high:
		return Z_HIGH_LEFT if s < 0.0 else Z_HIGH_RIGHT
	return Z_MID


## Перекрывает ли текущая поза зону (для AI/индикации).
func covers(zone: int) -> bool:
	match state:
		STANCE:
			return zone == Z_MID
		BUTTERFLY:
			return zone == Z_FIVE_HOLE or zone == Z_LOW_LEFT or zone == Z_LOW_RIGHT
		FALL_LEFT:
			# Вытянутая нога-щиток: низ и середина ЭТОЙ стороны + 5-hole. Верх открыт.
			return zone == Z_LOW_LEFT or zone == Z_MID or zone == Z_FIVE_HOLE
		FALL_RIGHT:
			return zone == Z_LOW_RIGHT or zone == Z_MID or zone == Z_FIVE_HOLE
	return false


## Действие AI по зоне полёта шайбы.
func action_for_zone(zone: int) -> String:
	match zone:
		Z_FIVE_HOLE, Z_LOW_LEFT, Z_LOW_RIGHT:
			return "butterfly"
		Z_HIGH_LEFT:
			return "catch" if _catch_sign() < 0 else "blocker"
		Z_HIGH_RIGHT:
			return "blocker" if _catch_sign() < 0 else "catch"
		_:
			return "stance"


# --- AI ---
func _control_ai(delta: float) -> void:
	if _recovery <= 0.0 and _react_timer < 0.0:
		state = STANCE
		_move_toward_arc(delta)
	# Детект броска: свободная шайба летит в створ.
	var v := _puck.linear_velocity
	var toward := v.dot(-out_dir)  # к воротам
	var incoming: bool = not _puck.freeze and toward > 6.0 \
			and absf(_puck.global_position.z - goal_center.z) < HALF_W + 1.0 \
			and (_puck.global_position - goal_center).dot(out_dir) > 0.0
	if incoming and not _shot_seen and _react_timer < 0.0:
		_shot_seen = true
		# Прогноз точки пересечения плоскости ворот.
		var target := _predict_goal_point()
		_react_action = action_for_zone(zone_of(target))
		_react_timer = _params.goalie_reaction_time
	if not incoming:
		_shot_seen = false
	if _react_timer >= 0.0:
		_react_timer -= delta
		if _react_timer < 0.0:
			_do_ai_action(_react_action)
	# Окно попытки сейва ловушкой/блином — тянемся, пока шайба долетает.
	if _ai_save_window > 0.0:
		_ai_save_window -= delta
		var ok := catch() if _ai_save_action == "catch" else blocker()
		if ok or _ai_save_window <= 0.0:
			_ai_save_window = 0.0


## Предикт: точка пересечения траектории шайбы с ФРОНТАЛЬНОЙ плоскостью
## вратаря (через позицию вратаря, нормаль = out_dir). Для наводки рук.
func _predict_front_point() -> Vector3:
	if _puck == null:
		return global_position
	var v := _puck.linear_velocity
	var denom := v.dot(-out_dir)  # приближается к воротам
	if denom < 0.5:
		return _puck.global_position  # не летит на нас — текущая позиция
	var dist := (global_position - _puck.global_position).dot(-out_dir)
	if dist < 0.0:
		return _puck.global_position  # уже за вратарём
	return _puck.global_position + v * (dist / denom)


func _predict_goal_point() -> Vector3:
	var v := _puck.linear_velocity
	var denom := v.dot(-out_dir)
	if denom < 0.1:
		return _puck.global_position
	var dist := (goal_center - _puck.global_position).dot(-out_dir)
	var t := dist / denom
	return _puck.global_position + v * clampf(t, 0.0, 1.0)


func _do_ai_action(action: String) -> void:
	match action:
		"butterfly":
			var s := (_predict_goal_point() - goal_center).dot(_right())
			if absf(s) > 0.4:
				fall(-1 if s < 0 else 1)  # низкий угол — падение в сторону
			else:
				state = BUTTERFLY
			_recovery = _params.goalie_recovery  # держим позу, потом встаёт (STANCE)
		"catch":
			_ai_save_action = "catch"
			_ai_save_window = _params.catch_window * 2.0
			catch()
		"blocker":
			_ai_save_action = "blocker"
			_ai_save_window = _params.catch_window * 2.0
			blocker()
		_:
			state = STANCE


# --- Процедурная поза ---
func _update_pose(delta: float) -> void:
	var fall_l: bool = state == FALL_LEFT
	var fall_r: bool = state == FALL_RIGHT
	var falling: bool = fall_l or fall_r
	# ХОККЕЙНЫЙ БАТТЕРФЛЯЙ (не футбольный dive): таз оседает вниз, голени
	# плашмя веером, корпус ВЕРТИКАЛЬНЫЙ. И баттерфляй, и падение — низкая поза.
	# RECOVER целится в стойку (поза встаёт), STANCE — стойка.
	var down: bool = state == BUTTERFLY or falling
	var p: float = move_toward(_pose, 1.0 if down else 0.0, delta / 0.15)
	_pose = p

	# НИКАКОГО завала тела вбок (это был dive) — визуальный корень ровный.
	_visual.rotation.z = 0.0
	_visual.position = Vector3.ZERO

	# Таз (корпус) ОСЕДАЕТ вниз ~0.4 м, чуть вперёд; корпус вертикальный с
	# лёгким наклоном вперёд. Плечи ровные.
	_torso.position.y = lerpf(0.85, 0.45, p)
	_torso.position.z = lerpf(0.0, -0.12, p)  # чуть вперёд (перёд = -Z)
	_head.position.y = lerpf(1.42, 1.02, p)
	_torso.rotation.x = lerpf(0.0, 0.12, p)   # лёгкий наклон корпуса вперёд
	# Небольшой крен в сторону выпада (плечи НЕ уходят в горизонт).
	var lean := 0.0
	if fall_l:
		lean = 0.18
	elif fall_r:
		lean = -0.18
	_torso.rotation.z = lerpf(_torso.rotation.z, lean * p, 1.0 - exp(-14.0 * delta))
	# Таз смещается в сторону выпада на ~0.35 м — ТОЛЬКО ПОЗОЙ (тело не двигается,
	# нет velocity). Доводка за 0.15 с к фиксированной точке.
	var hips_x := 0.0
	if fall_l:
		hips_x = -0.35
	elif fall_r:
		hips_x = 0.35
	_torso.position.x = hips_x * p
	_head.position.x = hips_x * p * 0.5

	# ЩИТКИ. Баттерфляй: голени плашмя, ВНУТРЕННИЕ края сходятся к центру
	# (щиток 0.62 длиной, лёжа вдоль X от центра наружу) — 5-hole ЗАКРЫТ (без
	# щели). Падение: нога стороны выпада ВЫТЯНУТА далеко (низ+середина), вторая
	# подогнута. Стойка: щитки чуть развёрнуты внутрь (~12°).
	var l_ext := 0.3   # центр щитка при бабочке (внутренний край ~у центра)
	var r_ext := 0.3
	if fall_l:
		l_ext = 0.95
		r_ext = 0.16
	elif fall_r:
		l_ext = 0.16
		r_ext = 0.95
	_pad_l.position = Vector3(lerpf(-0.17, -l_ext, p), lerpf(0.3, 0.09, p), -0.15)
	_pad_r.position = Vector3(lerpf(0.17, r_ext, p), lerpf(0.3, 0.09, p), -0.15)
	# Разворот голени в горизонт (плашмя): вертикальный щиток ложится вдоль X.
	_pad_l.rotation.z = lerpf(0.0, PI / 2.0, p)
	_pad_r.rotation.z = lerpf(0.0, -PI / 2.0, p)
	# Стойка: лёгкий разворот внутрь ~12° (носки внутрь).
	_pad_l.rotation.y = lerpf(-0.21, 0.0, p)
	_pad_r.rotation.y = lerpf(0.21, 0.0, p)
	# Баттерфляй-пуш: толчковое колено (сторона, ОТКУДА толкаемся) приподнимается,
	# конёк упирается — процедурный подъём щитка на время слайда.
	var push_dir := signf((_push_to - _push_from).dot(_right())) if _push_t > 0.0 else 0.0
	var lift_l := 0.16 if push_dir > 0.0 else 0.0   # толкаемся вправо -> левое колено
	var lift_r := 0.16 if push_dir < 0.0 else 0.0
	_pad_l.position.y += lift_l
	_pad_r.position.y += lift_r
	_pad_l.rotation.x = lerpf(_pad_l.rotation.x, -0.6 if lift_l > 0.0 else 0.0, 1.0 - exp(-18.0 * delta))
	_pad_r.rotation.x = lerpf(_pad_r.rotation.x, -0.6 if lift_r > 0.0 else 0.0, 1.0 - exp(-18.0 * delta))

	# Ловушка/блин тянутся к шайбе при срабатывании (IK-lite), иначе базовая.
	var cs := _catch_sign()
	_reach_hand(_catcher, cs, _catch_flash > 0.0)
	_reach_hand(_blocker, -cs, _block_flash > 0.0)


# --- Дебаг: зоны створа (цвет = перекрыта/открыта) + круги досягаемости ---
func _draw_debug() -> void:
	if not debug_draw:
		if _gizmo:
			_gizmo.visible = false
		return
	if _gizmo == null:
		_gizmo = MeshInstance3D.new()
		_gizmo.top_level = true
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gizmo.material_override = m
		add_child(_gizmo)
	_gizmo.visible = true
	var im := _gizmo.mesh as ImmediateMesh
	if im == null:
		im = ImmediateMesh.new()
		_gizmo.mesh = im
	_gizmo.global_transform = Transform3D.IDENTITY
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var right := _right()
	# Сетка створа: 3 столбца (лево/центр/право) x 2 ряда (низ/верх) в плоскости.
	for zs in [-HALF_W, -0.28, 0.28, HALF_W]:
		_giz_line(im, goal_center + right * zs, goal_center + right * zs + Vector3.UP * GOAL_HEIGHT, Color(1,1,1,0.3))
	for yy in [0.0, GOAL_HEIGHT * 0.42, GOAL_HEIGHT * 0.62, GOAL_HEIGHT]:
		_giz_line(im, goal_center - right * HALF_W + Vector3.UP * yy, goal_center + right * HALF_W + Vector3.UP * yy, Color(1,1,1,0.3))
	# Маркеры центров зон: зелёный = перекрыта позой, красный = открыта.
	for z in [Z_FIVE_HOLE, Z_LOW_LEFT, Z_LOW_RIGHT, Z_HIGH_LEFT, Z_HIGH_RIGHT, Z_MID]:
		var c := goal_center + _zone_center(z)
		var col := Color(0.2, 0.9, 0.3, 0.9) if covers(z) else Color(0.95, 0.25, 0.2, 0.9)
		_giz_line(im, c - right * 0.12, c + right * 0.12, col)
		_giz_line(im, c - Vector3.UP * 0.12, c + Vector3.UP * 0.12, col)
	# ПРЕДИКТ-точка перехвата (жёлтый крест) + вертикаль от льда.
	var pcol := Color(1.0, 0.9, 0.2, 0.95)
	_giz_line(im, _predict - right * 0.18, _predict + right * 0.18, pcol)
	_giz_line(im, _predict - Vector3.UP * 0.18, _predict + Vector3.UP * 0.18, pcol)
	_giz_line(im, Vector3(_predict.x, 0, _predict.z), _predict, Color(1.0, 0.9, 0.2, 0.4))
	# Полоса активного окна ловушки/блина (над головой).
	var win: float = maxf(_catch_win_t, _block_win_t)
	if win > 0.0:
		var frac: float = clampf(win / maxf(_params.catch_window, 0.01), 0.0, 1.0)
		var bar0 := global_position + Vector3(-0.4, 1.9, 0)
		var wc := Color(0.3, 0.9, 1.0, 0.95) if _catch_win_t > 0.0 else Color(1.0, 0.6, 0.2, 0.95)
		_giz_line(im, bar0, bar0 + right * (0.8 * frac), wc)
	im.surface_end()


func _zone_center(zone: int) -> Vector3:
	var right := _right()
	match zone:
		Z_FIVE_HOLE: return Vector3.UP * 0.2
		Z_LOW_LEFT: return -right * 0.55 + Vector3.UP * 0.2
		Z_LOW_RIGHT: return right * 0.55 + Vector3.UP * 0.2
		Z_HIGH_LEFT: return -right * 0.6 + Vector3.UP * 0.95
		Z_HIGH_RIGHT: return right * 0.6 + Vector3.UP * 0.95
	return Vector3.UP * 0.55  # MID


func _giz_line(im: ImmediateMesh, a: Vector3, b: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_set_color(col)
	im.surface_add_vertex(b)


## Рука тянется к ПРЕДИКТ-точке (не к текущей позиции шайбы), клэмп в СВОЮ
## половину (макс +10 см за центр — рука не пересекает центр), в пределах reach.
func _reach_hand(hand: Node3D, side: float, reaching: bool) -> void:
	var target := Vector3(side * 0.46, 0.95, -0.28)  # базовая поза руки (спереди)
	if reaching and _puck:
		# Цель — предикт, клэмп в СВОЮ половину ВОРОТ (фикс. ось), в пределах reach.
		var nr := _net_right()
		var s := (_predict - goal_center).dot(nr)
		if side < 0.0:
			s = minf(s, 0.1)   # ловушка не пересекает центр (левая половина)
		else:
			s = maxf(s, -0.1)  # блин — правая половина
		var y := clampf(_predict.y, 0.2, GOAL_HEIGHT)
		# Мировая цель кисти в своей половине, затем в локальные оси руки.
		var world_target := goal_center + nr * s + Vector3(0, y, 0) + out_dir * 0.3
		var local := to_local(world_target)
		local.y = clampf(local.y, 0.2, GOAL_HEIGHT)
		# Ограничение вылета руки от плеча.
		var shoulder := Vector3(side * 0.3, 0.95, 0.0)
		target = shoulder + (local - shoulder).limit_length(_params.catch_reach)
	hand.position = hand.position.lerp(target, 0.4)
