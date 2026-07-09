class_name InterpBuffer
extends RefCounted
## Буфер снапшотов для клиента (сеть v1): рендер между двумя снапшотами с
## задержкой ~100 мс. Плавность приоритетнее задержки — НИКАКОЙ экстраполяции.
## Сервер шлёт снапшоты 30 Гц; клиент хранит окно и сэмплит на now-delay.

const DELAY := 0.1     # задержка интерполяции (с)
const KEEP := 0.5      # сколько истории держать

var _snaps: Array = []  # [{t, data}] по возрастанию t
var _clock := 0.0


func advance(delta: float) -> void:
	_clock += delta
	# Чистим старое.
	while _snaps.size() > 2 and _snaps[0].t < _clock - KEEP:
		_snaps.pop_front()


func push(data: Dictionary) -> void:
	_snaps.append({"t": _clock, "data": data})


## Значение поля (Vector3) сущности key на now-DELAY, линейно между снапшотами.
func sample_vec3(key: String, field: String, fallback: Vector3) -> Vector3:
	var target := _clock - DELAY
	if _snaps.is_empty():
		return fallback
	if _snaps.size() == 1:
		return _get_vec3(_snaps[0].data, key, field, fallback)
	# Найти пару снапшотов вокруг target.
	for i in range(_snaps.size() - 1):
		var a: Dictionary = _snaps[i]
		var b: Dictionary = _snaps[i + 1]
		if a.t <= target and target <= b.t:
			var span: float = maxf(b.t - a.t, 0.0001)
			var f: float = clampf((target - a.t) / span, 0.0, 1.0)
			var va := _get_vec3(a.data, key, field, fallback)
			var vb := _get_vec3(b.data, key, field, fallback)
			return va.lerp(vb, f)
	# target новее последнего — берём последний (без экстраполяции).
	return _get_vec3(_snaps.back().data, key, field, fallback)


func latest(key: String, field: String, fallback):
	if _snaps.is_empty():
		return fallback
	var d: Dictionary = _snaps.back().data
	if d.has(key) and d[key].has(field):
		return d[key][field]
	return fallback


func _get_vec3(data: Dictionary, key: String, field: String, fallback: Vector3) -> Vector3:
	if data.has(key) and data[key].has(field):
		return data[key][field]
	return fallback


func delay_ms() -> float:
	return DELAY * 1000.0
