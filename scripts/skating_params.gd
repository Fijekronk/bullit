class_name SkatingParams
extends Resource
## Все параметры катания, управления, камеры, клюшки и арены. Единственный
## источник дефолтов — PARAM_DEFS: по нему же строится тюнинг-панель (F1) и JSON.
## def.type == "toggle" — булев переключатель (CheckButton вместо слайдера).

const SAVE_PATH := "user://skating_params.json"

const PARAM_DEFS := [
	{"section": "Катание", "key": "max_speed", "label": "Макс. скорость (м/с)", "min": 4.0, "max": 15.0, "step": 0.1, "default": 9.0},
	{"section": "Катание", "key": "accel", "label": "Тяга (м/с²)", "min": 2.0, "max": 20.0, "step": 0.1, "default": 8.0},
	{"section": "Катание", "key": "accel_curve_power", "label": "Кривая разгона", "min": 0.3, "max": 3.0, "step": 0.05, "default": 1.0},
	{"section": "Катание", "key": "turn_rate_at_zero", "label": "Поворот на месте (°/с)", "min": 90.0, "max": 900.0, "step": 5.0, "default": 540.0},
	{"section": "Катание", "key": "turn_rate_at_max", "label": "Поворот на макс. (°/с)", "min": 30.0, "max": 360.0, "step": 5.0, "default": 170.0},
	{"section": "Катание", "key": "grip", "label": "Сцепление коньков (1/с)", "min": 0.5, "max": 12.0, "step": 0.1, "default": 5.0},
	{"section": "Катание", "key": "brake_force", "label": "Торможение (м/с²)", "min": 2.0, "max": 20.0, "step": 0.1, "default": 7.0},
	{"section": "Катание", "key": "brake_grip_drop", "label": "Grip при юзе (x)", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.35},
	{"section": "Катание", "key": "crossover_boost", "label": "Кроссовер-буст (м/с²)", "min": 0.0, "max": 8.0, "step": 0.1, "default": 2.5},
	{"section": "Катание", "key": "coast_friction", "label": "Трение наката (м/с²)", "min": 0.1, "max": 5.0, "step": 0.05, "default": 1.5},
	{"section": "Катание", "key": "backward_speed_ratio", "label": "Скорость назад (x)", "min": 0.2, "max": 1.0, "step": 0.01, "default": 0.55},
	{"section": "Управление", "key": "carve_angle", "label": "Угол резаной дуги (°)", "min": 30.0, "max": 90.0, "step": 1.0, "default": 60.0},
	{"section": "Управление", "key": "hard_angle", "label": "Угол крутой дуги (°)", "min": 90.0, "max": 150.0, "step": 1.0, "default": 120.0},
	{"section": "Управление", "key": "pivot_angle", "label": "Угол авто-пивота (°)", "min": 90.0, "max": 170.0, "step": 1.0, "default": 120.0},
	{"section": "Управление", "key": "turn_scrub", "label": "Потеря в резаной дуге", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.0},
	{"section": "Управление", "key": "turn_scrub_hard", "label": "Потеря в крутой дуге", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.35},
	{"section": "Управление", "key": "crossover_gain", "label": "Разгон в дуге (x тяги)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.18},
	{"section": "Управление", "key": "facing_angular_accel", "label": "Угл. ускорение корпуса (°/с²)", "min": 180.0, "max": 2500.0, "step": 10.0, "default": 1100.0},
	{"section": "Управление", "key": "pivot_exit_speed", "label": "Скорость выхода из пивота (м/с)", "min": 0.5, "max": 4.0, "step": 0.1, "default": 1.5},
	{"section": "Камера", "key": "camera_yaw_follow", "label": "Камера за игроком (yaw)", "type": "toggle", "default": true},
	{"section": "Камера", "key": "camera_height", "label": "Высота (м)", "min": 3.0, "max": 30.0, "step": 0.25, "default": 5.5},
	{"section": "Камера", "key": "camera_distance", "label": "Отступ (м)", "min": 3.0, "max": 25.0, "step": 0.25, "default": 6.5},
	{"section": "Камера", "key": "camera_pitch", "label": "Наклон (°)", "min": 20.0, "max": 70.0, "step": 1.0, "default": 35.0},
	{"section": "Камера", "key": "camera_fov", "label": "FOV (°)", "min": 50.0, "max": 100.0, "step": 1.0, "default": 75.0},
	{"section": "Камера", "key": "camera_lookahead", "label": "Упреждение (м)", "min": 0.0, "max": 6.0, "step": 0.1, "default": 2.0},
	{"section": "Камера", "key": "camera_smoothing", "label": "Плавность позиции (1/с)", "min": 1.0, "max": 15.0, "step": 0.1, "default": 5.0},
	{"section": "Камера", "key": "cam_dir_smoothing", "label": "Сглаживание направления (1/с)", "min": 0.5, "max": 10.0, "step": 0.1, "default": 3.0},
	{"section": "Камера", "key": "cam_max_yaw_speed", "label": "Макс. скорость yaw (°/с)", "min": 30.0, "max": 360.0, "step": 5.0, "default": 150.0},
	{"section": "Камера", "key": "cam_yaw_deadzone", "label": "Мёртвая зона yaw (°)", "min": 0.0, "max": 30.0, "step": 1.0, "default": 10.0},
	{"section": "Клюшка", "key": "handedness_right", "label": "Хват: правый", "type": "toggle", "default": true},
	{"section": "Клюшка", "key": "hand_offset_side", "label": "Смещение хвата вбок (м)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "hand_offset_forward", "label": "Смещение хвата вперёд (м)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.15},
	{"section": "Клюшка", "key": "stick_length", "label": "Длина клюшки (м)", "min": 0.8, "max": 2.2, "step": 0.01, "default": 1.35},
	{"section": "Клюшка", "key": "reach_variation", "label": "Радиальный люфт (м)", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.12},
	{"section": "Клюшка", "key": "backhand_limit", "label": "Граница бэкхенда (°)", "min": -120.0, "max": 0.0, "step": 5.0, "default": -60.0},
	{"section": "Клюшка", "key": "forehand_limit", "label": "Граница форхенда (°)", "min": 120.0, "max": 270.0, "step": 5.0, "default": 200.0},
	{"section": "Клюшка", "key": "stick_smoothing", "label": "Сглаживание цели (1/с)", "min": 2.0, "max": 60.0, "step": 0.5, "default": 25.0},
	{"section": "Клюшка", "key": "blade_max_speed", "label": "Скорость крюка (м/с)", "min": 4.0, "max": 30.0, "step": 0.5, "default": 14.0},
	{"section": "Клюшка", "key": "blade_max_accel", "label": "Ускорение крюка (м/с²)", "min": 20.0, "max": 300.0, "step": 5.0, "default": 90.0},
	{"section": "Клюшка", "key": "assist_radius", "label": "Радиус помощи (м)", "min": 0.05, "max": 0.6, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "assist_strength", "label": "Сила помощи (k)", "min": 0.0, "max": 40.0, "step": 0.5, "default": 14.0},
	{"section": "Клюшка", "key": "assist_max_rel_speed", "label": "Порог отн. скорости (м/с)", "min": 1.0, "max": 15.0, "step": 0.1, "default": 6.0},
	{"section": "Клюшка", "key": "assist_max_force", "label": "Макс. сила помощи (Н)", "min": 0.0, "max": 30.0, "step": 0.5, "default": 8.0},
	{"section": "Клюшка", "key": "catch_radius", "label": "Радиус приёма (м)", "min": 0.1, "max": 0.8, "step": 0.01, "default": 0.35},
	{"section": "Клюшка", "key": "catch_max_rel_speed", "label": "Порог приёма (м/с)", "min": 4.0, "max": 25.0, "step": 0.5, "default": 12.0},
	{"section": "Клюшка", "key": "catch_strength", "label": "Сила приёма (k)", "min": 5.0, "max": 80.0, "step": 0.5, "default": 35.0},
	{"section": "Клюшка", "key": "catch_max_force", "label": "Макс. сила приёма (Н)", "min": 5.0, "max": 60.0, "step": 0.5, "default": 20.0},
	{"section": "Арена", "key": "rink_length", "label": "Длина катка (м)", "min": 30.0, "max": 70.0, "step": 1.0, "default": 56.0},
	{"section": "Арена", "key": "rink_width", "label": "Ширина катка (м)", "min": 16.0, "max": 36.0, "step": 1.0, "default": 26.0},
	{"section": "Арена", "key": "corner_radius", "label": "Радиус углов (м)", "min": 2.0, "max": 12.0, "step": 0.5, "default": 7.0},
]

@export var max_speed := 9.0
@export var accel := 8.0
@export var accel_curve_power := 1.0
@export var turn_rate_at_zero := 540.0
@export var turn_rate_at_max := 170.0
@export var grip := 5.0
@export var brake_force := 7.0
@export var brake_grip_drop := 0.35
@export var crossover_boost := 2.5
@export var coast_friction := 1.5
@export var backward_speed_ratio := 0.55
@export var carve_angle := 60.0
@export var hard_angle := 120.0
@export var pivot_angle := 120.0
@export var turn_scrub := 0.0
@export var turn_scrub_hard := 0.35
@export var crossover_gain := 0.18
@export var facing_angular_accel := 1100.0
@export var pivot_exit_speed := 1.5
@export var camera_yaw_follow := true
@export var camera_height := 5.5
@export var camera_distance := 6.5
@export var camera_pitch := 35.0
@export var camera_fov := 75.0
@export var camera_lookahead := 2.0
@export var camera_smoothing := 5.0
@export var cam_dir_smoothing := 3.0
@export var cam_max_yaw_speed := 150.0
@export var cam_yaw_deadzone := 10.0
@export var handedness_right := true
@export var hand_offset_side := 0.22
@export var hand_offset_forward := 0.15
@export var stick_length := 1.35
@export var reach_variation := 0.12
@export var backhand_limit := -60.0
@export var forehand_limit := 200.0
@export var stick_smoothing := 25.0
@export var blade_max_speed := 14.0
@export var blade_max_accel := 90.0
@export var assist_radius := 0.22
@export var assist_strength := 14.0
@export var assist_max_rel_speed := 6.0
@export var assist_max_force := 8.0
@export var catch_radius := 0.35
@export var catch_max_rel_speed := 12.0
@export var catch_strength := 35.0
@export var catch_max_force := 20.0
@export var rink_length := 56.0
@export var rink_width := 26.0
@export var corner_radius := 7.0


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
		if not data.has(def.key):
			continue
		if def.get("type", "") == "toggle":
			set(def.key, bool(data[def.key]))
		else:
			set(def.key, float(data[def.key]))
	return true
