class_name InputState
extends RefCounted
## Пакет ввода — ЕДИНСТВЕННЫЙ источник ввода для игровой логики (сеть v1,
## правило «сервер решает»). Вся физика/механики читают ввод ТОЛЬКО отсюда,
## НЕ из Input напрямую. Заполняется двумя способами:
##   - poll_local(): локальный игрок снимает свой Input (хост-игрок / тренировка);
##   - apply_packet(): сервер применяет присланный клиентом пакет.
## Дискретные события (just_pressed) — рёбра, считаются при заполнении и
## консистентны в пределах тика (многократное чтение даёт то же значение).

# Аналоговые/удержания (game-logic ввод; мышь-камера и debug-клавиши — вне).
const AXES := [
	"move_forward", "move_back", "turn_left", "turn_right",
	"stance", "profile_glide", "sprint",
	"gesture_primary", "gesture_secondary", "gesture_lift",
	"feint_left", "feint_right",
]

var _cur := {}    # action -> strength (0..1)
var _prev := {}   # action -> было нажато (для рёбер)
var _just := {}   # action -> just_pressed в этом тике
var _rel := {}    # action -> just_released в этом тике
var _frame := -1  # последний обработанный physics-кадр (защита от повторного poll)


func _init() -> void:
	for a in AXES:
		_cur[a] = 0.0
		_prev[a] = false
		_just[a] = false
		_rel[a] = false


## Снять локальный Input один раз за physics-кадр (идемпотентно: повторные
## вызовы в том же кадре — no-op, рёбра сохраняются).
func poll_local() -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	for a in AXES:
		var s: float = Input.get_action_strength(a)
		var p: bool = s > 0.5
		var was: bool = _prev.get(a, false)
		_just[a] = p and not was
		_rel[a] = was and not p
		_prev[a] = p
		_cur[a] = s


## Сервер: применить пакет клиента (strengths + маска рёбер). frame — тик клиента.
func apply_packet(strengths: Dictionary, edges: Dictionary, releases: Dictionary = {}) -> void:
	for a in AXES:
		_cur[a] = float(strengths.get(a, 0.0))
		_just[a] = bool(edges.get(a, false))
		_rel[a] = bool(releases.get(a, false))
		_prev[a] = _cur[a] > 0.5


## Клиент: собрать пакет для отправки (аналоговые + рёбра just_pressed).
func make_packet() -> Dictionary:
	var strengths := {}
	var edges := {}
	var releases := {}
	for a in AXES:
		if _cur[a] != 0.0:
			strengths[a] = _cur[a]
		if _just[a]:
			edges[a] = true
		if _rel[a]:
			releases[a] = true
	return {"s": strengths, "e": edges, "r": releases}


func just_released(action: String) -> bool:
	return _rel.get(action, false)


func pressed(action: String) -> bool:
	return _cur.get(action, 0.0) > 0.5


func just_pressed(action: String) -> bool:
	return _just.get(action, false)


func strength(action: String) -> float:
	return _cur.get(action, 0.0)
