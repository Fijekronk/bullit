class_name SkatingParams
extends Resource
## Все параметры катания, камеры и клюшки. Единственный источник дефолтов —
## PARAM_DEFS: по нему же строится тюнинг-панель (F1) и сериализация в JSON.

const SAVE_PATH := "user://skating_params.json"

const PARAM_DEFS := [
	{"section": "Катание", "key": "max_speed", "label": "Макс. скорость (м/с)", "min": 4.0, "max": 15.0, "step": 0.1, "default": 9.0},
	{"section": "Катание", "key": "accel", "label": "Тяга (м/с²)", "min": 2.0, "max": 20.0, "step": 0.1, "default": 8.0},
	{"section": "Катание", "key": "accel_curve_power", "label": "Кривая разгона", "min": 0.3, "max": 3.0, "step": 0.05, "default": 1.0},
	{"section": "Катание", "key": "turn_rate_at_zero", "label": "Поворот на месте (°/с)", "min": 90.0, "max": 900.0, "step": 5.0, "default": 540.0},
	{"section": "Катание", "key": "turn_rate_at_max", "label": "Поворот на макс. (°/с)", "min": 30.0, "max": 360.0, "step": 5.0, "default": 130.0},
	{"section": "Катание", "key": "grip", "label": "Сцепление коньков (1/с)", "min": 0.5, "max": 12.0, "step": 0.1, "default": 5.0},
	{"section": "Катание", "key": "brake_force", "label": "Торможение (м/с²)", "min": 2.0, "max": 20.0, "step": 0.1, "default": 7.0},
	{"section": "Катание", "key": "brake_grip_drop", "label": "Grip при юзе (x)", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.35},
	{"section": "Катание", "key": "crossover_boost", "label": "Кроссовер-буст (м/с²)", "min": 0.0, "max": 8.0, "step": 0.1, "default": 2.5},
	{"section": "Катание", "key": "coast_friction", "label": "Трение наката (м/с²)", "min": 0.1, "max": 5.0, "step": 0.05, "default": 1.5},
	{"section": "Катание", "key": "backward_speed_ratio", "label": "Скорость назад (x)", "min": 0.2, "max": 1.0, "step": 0.01, "default": 0.55},
	{"section": "Камера", "key": "camera_height", "label": "Высота (м)", "min": 6.0, "max": 30.0, "step": 0.5, "default": 14.0},
	{"section": "Камера", "key": "camera_distance", "label": "Отступ (м)", "min": 4.0, "max": 25.0, "step": 0.5, "default": 12.0},
	{"section": "Камера", "key": "camera_lookahead", "label": "Упреждение (м)", "min": 0.0, "max": 6.0, "step": 0.1, "default": 2.0},
	{"section": "Камера", "key": "camera_smoothing", "label": "Плавность (1/с)", "min": 1.0, "max": 15.0, "step": 0.1, "default": 5.0},
	{"section": "Клюшка", "key": "stick_min_reach", "label": "Мин. досягаемость (м)", "min": 0.2, "max": 1.0, "step": 0.01, "default": 0.45},
	{"section": "Клюшка", "key": "stick_max_reach", "label": "Макс. досягаемость (м)", "min": 0.8, "max": 2.5, "step": 0.01, "default": 1.55},
	{"section": "Клюшка", "key": "stick_smoothing", "label": "Сглаживание цели (1/с)", "min": 2.0, "max": 60.0, "step": 0.5, "default": 25.0},
	{"section": "Клюшка", "key": "blade_max_speed", "label": "Скорость крюка (м/с)", "min": 4.0, "max": 30.0, "step": 0.5, "default": 14.0},
	{"section": "Клюшка", "key": "blade_max_accel", "label": "Ускорение крюка (м/с²)", "min": 20.0, "max": 300.0, "step": 5.0, "default": 90.0},
	{"section": "Клюшка", "key": "assist_radius", "label": "Радиус помощи (м)", "min": 0.05, "max": 0.6, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "assist_strength", "label": "Сила помощи (k)", "min": 0.0, "max": 40.0, "step": 0.5, "default": 14.0},
	{"section": "Клюшка", "key": "assist_max_rel_speed", "label": "Порог отн. скорости (м/с)", "min": 1.0, "max": 15.0, "step": 0.1, "default": 6.0},
	{"section": "Клюшка", "key": "assist_max_force", "label": "Макс. сила помощи (Н)", "min": 0.0, "max": 30.0, "step": 0.5, "default": 8.0},
]

@export var max_speed := 9.0
@export var accel := 8.0
@export var accel_curve_power := 1.0
@export var turn_rate_at_zero := 540.0
@export var turn_rate_at_max := 130.0
@export var grip := 5.0
@export var brake_force := 7.0
@export var brake_grip_drop := 0.35
@export var crossover_boost := 2.5
@export var coast_friction := 1.5
@export var backward_speed_ratio := 0.55
@export var camera_height := 14.0
@export var camera_distance := 12.0
@export var camera_lookahead := 2.0
@export var camera_smoothing := 5.0
@export var stick_min_reach := 0.45
@export var stick_max_reach := 1.55
@export var stick_smoothing := 25.0
@export var blade_max_speed := 14.0
@export var blade_max_accel := 90.0
@export var assist_radius := 0.22
@export var assist_strength := 14.0
@export var assist_max_rel_speed := 6.0
@export var assist_max_force := 8.0


func reset_to_defaults() -> void:
	for def in PARAM_DEFS:
		set(def.key, def.default)


func save_to_json() -> void:
	var data := {}
	for def in PARAM_DEFS:
		data[def.key] = get(def.key)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось сохранить параметры: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_from_json() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for def in PARAM_DEFS:
		if data.has(def.key):
			set(def.key, float(data[def.key]))
	return true
