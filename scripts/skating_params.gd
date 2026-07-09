class_name SkatingParams
extends Resource
## Параметры: анизотропное лезвие + профили «бег»/«скольжение» (Alt), рывок
## (Shift), стойка с движением (Ctrl), машина состояний шайбы (FREE/CARRIED/AIR),
## авто-перекладка на развороте, орбитальная камера-мышь, жёсткая клюшка, жесты.
## Источник дефолтов — PARAM_DEFS. def.type=="toggle" → CheckButton.
## JSON мигрирует: неизвестные ключи игнорируются, новые — из дефолтов.

const SAVE_PATH := "user://skating_params.json"

const PARAM_DEFS := [
	{"section": "Катание", "key": "max_speed", "label": "Макс. скорость (м/с)", "min": 4.0, "max": 15.0, "step": 0.1, "default": 9.0},
	{"section": "Катание", "key": "accel", "label": "Тяга (м/с²)", "min": 2.0, "max": 24.0, "step": 0.1, "default": 9.0},
	{"section": "Катание", "key": "accel_curve_power", "label": "Кривая разгона", "min": 0.3, "max": 3.0, "step": 0.05, "default": 1.0},
	{"section": "Катание", "key": "turn_rate_at_zero", "label": "Поворот на месте (°/с)", "min": 90.0, "max": 900.0, "step": 5.0, "default": 540.0},
	{"section": "Катание", "key": "crossover_gain", "label": "Разгон в дуге (x тяги)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.18},
	{"section": "Катание", "key": "friction_along", "label": "Трение вдоль (м/с²)", "min": 0.0, "max": 3.0, "step": 0.05, "default": 0.35},
	{"section": "Профиль Бег", "key": "run_carve_grip", "label": "Кант: полугашение (с)", "min": 0.01, "max": 0.3, "step": 0.005, "default": 0.03},
	{"section": "Профиль Бег", "key": "run_carve_threshold", "label": "Порог срыва (м/с)", "min": 0.5, "max": 5.0, "step": 0.1, "default": 2.5},
	{"section": "Профиль Бег", "key": "run_skid_friction", "label": "Юз поперёк (м/с²)", "min": 1.0, "max": 12.0, "step": 0.1, "default": 6.0},
	{"section": "Профиль Бег", "key": "run_turn_rate_max", "label": "Поворот на макс. (°/с)", "min": 60.0, "max": 500.0, "step": 5.0, "default": 320.0},
	{"section": "Профиль Бег", "key": "run_facing_accel", "label": "Угл. ускорение (°/с²)", "min": 300.0, "max": 4000.0, "step": 20.0, "default": 2200.0},
	{"section": "Профиль Бег", "key": "quick_stop_friction", "label": "Резкий стоп (м/с²)", "min": 4.0, "max": 30.0, "step": 0.5, "default": 14.0},
	{"section": "Профиль Бег", "key": "reverse_angle", "label": "Угол полного реверса (°)", "min": 120.0, "max": 179.0, "step": 1.0, "default": 150.0},
	{"section": "Профиль Скольжение", "key": "glide_carve_grip", "label": "Кант: полугашение (с)", "min": 0.02, "max": 0.5, "step": 0.01, "default": 0.2},
	{"section": "Профиль Скольжение", "key": "glide_carve_threshold", "label": "Порог срыва (м/с)", "min": 0.3, "max": 3.0, "step": 0.1, "default": 0.8},
	{"section": "Профиль Скольжение", "key": "glide_skid_friction", "label": "Юз поперёк (м/с²)", "min": 1.0, "max": 12.0, "step": 0.1, "default": 4.5},
	{"section": "Профиль Скольжение", "key": "glide_turn_rate_max", "label": "Поворот на макс. (°/с)", "min": 60.0, "max": 500.0, "step": 5.0, "default": 200.0},
	{"section": "Профиль Скольжение", "key": "glide_facing_accel", "label": "Угл. ускорение (°/с²)", "min": 300.0, "max": 4000.0, "step": 20.0, "default": 1400.0},
	{"section": "Стамина", "key": "sprint_speed_mult", "label": "Спринт: множитель скорости", "min": 1.05, "max": 1.8, "step": 0.05, "default": 1.3},
	{"section": "Стамина", "key": "sprint_max", "label": "Бак спринта (с)", "min": 2.0, "max": 12.0, "step": 0.5, "default": 5.0},
	{"section": "Стамина", "key": "stamina_regen_time", "label": "Восстановление бака (с)", "min": 3.0, "max": 15.0, "step": 0.5, "default": 7.0},
	{"section": "Стамина", "key": "dash_impulse", "label": "Импульс рывка (м/с)", "min": 1.0, "max": 8.0, "step": 0.1, "default": 4.0},
	{"section": "Стамина", "key": "dash_overspeed", "label": "Превышение max (м/с)", "min": 0.0, "max": 6.0, "step": 0.1, "default": 2.5},
	{"section": "Стамина", "key": "hud_stamina", "label": "HUD: бар стамины", "type": "toggle", "default": true},
	{"section": "Рывок", "key": "stance_thrust_cap", "label": "Тяга в стойке (x)", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.9},
	{"section": "Рывок", "key": "gesture_glide_extra", "label": "Скольжение после жеста (с)", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.15},
	{"section": "Шайба", "key": "carry_stiffness", "label": "Жёсткость carry (Н/м)", "min": 100.0, "max": 1200.0, "step": 10.0, "default": 600.0},
	{"section": "Шайба", "key": "carry_max_force", "label": "Макс. сила carry (Н)", "min": 20.0, "max": 200.0, "step": 2.0, "default": 120.0},
	{"section": "Шайба", "key": "carry_heel_offset", "label": "Carry-точка к пятке (м)", "min": 0.0, "max": 0.2, "step": 0.01, "default": 0.06},
	{"section": "Шайба", "key": "carry_break_dist", "label": "Срыв carry на дистанции (м)", "min": 0.3, "max": 1.2, "step": 0.05, "default": 0.85},
	{"section": "Шайба", "key": "release_grace", "label": "Grace после броска (с)", "min": 0.1, "max": 0.6, "step": 0.05, "default": 0.35},
	{"section": "Шайба", "key": "flip_up_speed", "label": "Подброс: верт. скорость (м/с)", "min": 1.5, "max": 7.0, "step": 0.1, "default": 3.9},
	{"section": "Шайба", "key": "puck_wall_margin", "label": "Отступ шайбы от борта (м)", "min": 0.05, "max": 0.4, "step": 0.01, "default": 0.12},
	{"section": "Шайба", "key": "trail_min_speed", "label": "Трейл шайбы от (м/с)", "min": 6.0, "max": 25.0, "step": 0.5, "default": 14.0},
	{"section": "Шайба", "key": "puck_trail_enabled", "label": "Трейл шайбы", "type": "toggle", "default": true},
	{"section": "Позы", "key": "short_pose_angle", "label": "Короткий дриблинг (°)", "min": 6.0, "max": 30.0, "step": 1.0, "default": 16.0},
	{"section": "Позы", "key": "pose_blade_speed", "label": "Скорость крюка в позах (м/с)", "min": 10.0, "max": 35.0, "step": 0.5, "default": 22.0},
	{"section": "Позы", "key": "pose_angle", "label": "Угол позы (°)", "min": 15.0, "max": 60.0, "step": 1.0, "default": 35.0},
	{"section": "Позы", "key": "wide_pose_angle", "label": "Широкая поза (°)", "min": 30.0, "max": 90.0, "step": 1.0, "default": 55.0},
	{"section": "Позы", "key": "hold_max", "label": "Удержание широкого (с)", "min": 0.15, "max": 0.8, "step": 0.05, "default": 0.4},
	{"section": "Позы", "key": "pose_roll", "label": "Наклон пера (°)", "min": 0.0, "max": 45.0, "step": 1.0, "default": 20.0},
	{"section": "Позы", "key": "transfer_time", "label": "Время перекладки (с)", "min": 0.08, "max": 0.4, "step": 0.01, "default": 0.12},
	{"section": "Перекладка", "key": "pivot_transfer_angle", "label": "Угол перекладки (°)", "min": 70.0, "max": 160.0, "step": 5.0, "default": 100.0},
	{"section": "Перекладка", "key": "transfer_assist_mult", "label": "Усиление ассиста (x)", "min": 1.0, "max": 3.0, "step": 0.1, "default": 1.8},
	{"section": "Перекладка", "key": "transfer_reliable_speed", "label": "Потолок надёжности (м/с)", "min": 4.0, "max": 12.0, "step": 0.5, "default": 7.5},
	{"section": "Камера", "key": "camera_distance", "label": "Отступ (м)", "min": 3.0, "max": 20.0, "step": 0.25, "default": 6.5},
	{"section": "Камера", "key": "camera_height", "label": "Высота цели (м)", "min": 0.0, "max": 4.0, "step": 0.1, "default": 1.2},
	{"section": "Камера", "key": "camera_pitch", "label": "Наклон старт (°)", "min": 25.0, "max": 55.0, "step": 1.0, "default": 42.0},
	{"section": "Камера", "key": "camera_fov", "label": "FOV (°)", "min": 50.0, "max": 100.0, "step": 1.0, "default": 75.0},
	{"section": "Камера", "key": "camera_smoothing", "label": "Плавность позиции (1/с)", "min": 1.0, "max": 20.0, "step": 0.1, "default": 8.0},
	{"section": "Камера", "key": "mouse_sensitivity", "label": "Чувствит. мыши (°/px)", "min": 0.02, "max": 0.8, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "handedness_right", "label": "Хват: правый", "type": "toggle", "default": true},
	{"section": "Клюшка", "key": "hand_offset_side", "label": "Хват: вбок (м)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "hand_offset_forward", "label": "Хват: вперёд (м)", "min": 0.0, "max": 0.6, "step": 0.01, "default": 0.15},
	{"section": "Клюшка", "key": "stick_length", "label": "Длина клюшки (м)", "min": 0.8, "max": 2.2, "step": 0.01, "default": 1.35},
	{"section": "Клюшка", "key": "backhand_limit", "label": "Граница бэкхенда (°)", "min": -120.0, "max": 0.0, "step": 5.0, "default": -60.0},
	{"section": "Клюшка", "key": "forehand_limit", "label": "Граница форхенда (°)", "min": 120.0, "max": 270.0, "step": 5.0, "default": 200.0},
	{"section": "Клюшка", "key": "neutral_angle", "label": "Нейтраль вбок (°)", "min": 0.0, "max": 60.0, "step": 1.0, "default": 20.0},
	{"section": "Клюшка", "key": "blade_angular_speed", "label": "Скорость крюка (°/с)", "min": 200.0, "max": 1200.0, "step": 10.0, "default": 600.0},
	{"section": "Клюшка", "key": "blade_angular_accel", "label": "Ускорение крюка (°/с²)", "min": 1000.0, "max": 20000.0, "step": 100.0, "default": 6000.0},
	{"section": "Клюшка", "key": "reach_transition", "label": "Плавность вылета (с)", "min": 0.05, "max": 0.5, "step": 0.01, "default": 0.2},
	{"section": "Клюшка", "key": "stance_reach_bonus", "label": "Стойка: +вылет (x)", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "assist_radius", "label": "Радиус помощи (м)", "min": 0.05, "max": 0.6, "step": 0.01, "default": 0.22},
	{"section": "Клюшка", "key": "assist_strength", "label": "Сила помощи (k)", "min": 0.0, "max": 40.0, "step": 0.5, "default": 14.0},
	{"section": "Клюшка", "key": "assist_max_rel_speed", "label": "Порог отн. скорости (м/с)", "min": 1.0, "max": 15.0, "step": 0.1, "default": 6.0},
	{"section": "Клюшка", "key": "assist_max_force", "label": "Макс. сила помощи (Н)", "min": 0.0, "max": 30.0, "step": 0.5, "default": 8.0},
	{"section": "Клюшка", "key": "catch_radius", "label": "Радиус приёма (м)", "min": 0.1, "max": 0.8, "step": 0.01, "default": 0.35},
	{"section": "Клюшка", "key": "catch_max_rel_speed", "label": "Порог приёма (м/с)", "min": 4.0, "max": 25.0, "step": 0.5, "default": 12.0},
	{"section": "Клюшка", "key": "catch_strength", "label": "Сила приёма (k)", "min": 5.0, "max": 80.0, "step": 0.5, "default": 35.0},
	{"section": "Клюшка", "key": "catch_max_force", "label": "Макс. сила приёма (Н)", "min": 5.0, "max": 60.0, "step": 0.5, "default": 20.0},
	{"section": "Клюшка", "key": "pickup_radius", "label": "Радиус подбора (м)", "min": 0.2, "max": 1.0, "step": 0.01, "default": 0.5},
	{"section": "Клюшка", "key": "aim_assist_strength", "label": "Довод броска к воротам", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.5},
	{"section": "Наклон", "key": "lean_turn", "label": "Крен в повороте (°)", "min": 0.0, "max": 40.0, "step": 1.0, "default": 18.0},
	{"section": "Наклон", "key": "lean_juke", "label": "Крен в переводе (°)", "min": 0.0, "max": 45.0, "step": 1.0, "default": 25.0},
	{"section": "Наклон", "key": "lean_fake", "label": "Клевок фейка (°)", "min": 0.0, "max": 50.0, "step": 1.0, "default": 30.0},
	{"section": "Финты", "key": "juke_impulse", "label": "Боковой шаг финта (м/с)", "min": 0.3, "max": 3.0, "step": 0.1, "default": 1.1},
	{"section": "Финты", "key": "wide_time", "label": "Широкий перевод (с)", "min": 0.1, "max": 0.5, "step": 0.01, "default": 0.2},
	{"section": "Финты", "key": "triangle_window", "label": "Окно треугольника (с)", "min": 0.3, "max": 1.2, "step": 0.05, "default": 0.6},
	{"section": "Финты", "key": "fake_impulse", "label": "Импульс фейка (м/с)", "min": 0.2, "max": 2.0, "step": 0.05, "default": 1.0},
	{"section": "Финты", "key": "fake_cooldown", "label": "Кулдаун фейка (с)", "min": 0.2, "max": 1.5, "step": 0.05, "default": 0.5},
	{"section": "Финты", "key": "idle_dribble_amp", "label": "Идл-качание шайбы (м)", "min": 0.0, "max": 0.1, "step": 0.005, "default": 0.05},
	{"section": "Финты", "key": "juggle_window", "label": "Окно набивания (с)", "min": 0.06, "max": 0.3, "step": 0.01, "default": 0.11},
	{"section": "Финты", "key": "air_juggle_cooldown", "label": "Кулдаун набивания (с)", "min": 0.2, "max": 1.5, "step": 0.05, "default": 0.5},
	{"section": "Финты", "key": "kick_forward_speed", "label": "Отскок от конька (+м/с)", "min": 0.5, "max": 4.0, "step": 0.1, "default": 1.2},
	{"section": "Финты", "key": "skate_zone", "label": "Зона конька (м)", "min": 0.2, "max": 0.7, "step": 0.01, "default": 0.4},
	{"section": "Финты", "key": "poke_range", "label": "Манекен: радиус отбора (м)", "min": 0.6, "max": 2.5, "step": 0.05, "default": 1.3},
	{"section": "Финты", "key": "poke_cooldown", "label": "Кулдаун отбора E/манекен (с)", "min": 0.4, "max": 2.0, "step": 0.05, "default": 1.0},
	{"section": "Контакт", "key": "player_mass", "label": "Масса игрока (кг)", "min": 50.0, "max": 120.0, "step": 1.0, "default": 80.0},
	{"section": "Контакт", "key": "hit_impulse_scale", "label": "Сила хита (множ.)", "min": 0.3, "max": 3.0, "step": 0.05, "default": 1.0},
	{"section": "Контакт", "key": "hit_stun", "label": "Стан от хита (с)", "min": 0.2, "max": 1.5, "step": 0.05, "default": 0.6},
	{"section": "Контакт", "key": "hit_window", "label": "Окно чистого хита (с)", "min": 0.5, "max": 4.0, "step": 0.1, "default": 2.0},
	{"section": "Контакт", "key": "hit_reach", "label": "Q: радиус силового (м)", "min": 0.3, "max": 1.5, "step": 0.05, "default": 0.5},
	{"section": "Контакт", "key": "hit_cooldown", "label": "Q: кулдаун силового (с)", "min": 0.5, "max": 3.0, "step": 0.1, "default": 1.2},
	{"section": "Контакт", "key": "poke_reach", "label": "E: радиус отбора (м)", "min": 0.6, "max": 2.0, "step": 0.05, "default": 1.2},
	{"section": "Контакт", "key": "poke_windup", "label": "E: телеграф выпада (с)", "min": 0.1, "max": 0.4, "step": 0.02, "default": 0.2},
	{"section": "Контакт", "key": "poke_contact", "label": "E: окно контакта (с)", "min": 0.06, "max": 0.25, "step": 0.01, "default": 0.12},
	{"section": "Контакт", "key": "backward_control", "label": "Управление спиной (x)", "min": 0.3, "max": 1.0, "step": 0.05, "default": 0.6},
	{"section": "Вратарь", "key": "goalie_enabled", "label": "Вратарь у правых ворот", "type": "toggle", "default": false},
	{"section": "Вратарь", "key": "goalie_move_speed", "label": "Скорость (x полевого)", "min": 0.3, "max": 1.0, "step": 0.05, "default": 0.5},
	{"section": "Вратарь", "key": "goalie_range", "label": "Радиус зоны (м)", "min": 1.0, "max": 5.0, "step": 0.25, "default": 3.0},
	{"section": "Вратарь", "key": "catch_reach", "label": "Досягаемость ловушки/блина (м)", "min": 0.5, "max": 2.0, "step": 0.05, "default": 1.0},
	{"section": "Вратарь", "key": "catch_window", "label": "Окно ловли/блина (с)", "min": 0.1, "max": 0.5, "step": 0.01, "default": 0.25},
	{"section": "Вратарь", "key": "cover_radius", "label": "Радиус накрытия (м)", "min": 0.4, "max": 1.5, "step": 0.05, "default": 0.8},
	{"section": "Вратарь", "key": "goalie_save_cooldown", "label": "Кулдаун ловушки/блина (с)", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.2},
	{"section": "Вратарь", "key": "goalie_recovery", "label": "Восстановление после падения (с)", "min": 0.2, "max": 1.2, "step": 0.05, "default": 0.5},
	{"section": "Вратарь", "key": "goalie_reaction_time", "label": "AI: реакция на бросок (с)", "min": 0.05, "max": 0.5, "step": 0.01, "default": 0.18},
	{"section": "Вратарь", "key": "push_distance", "label": "Баттерфляй-пуш дистанция (м)", "min": 0.4, "max": 1.5, "step": 0.05, "default": 0.9},
	{"section": "Вратарь", "key": "push_cooldown", "label": "Баттерфляй-пуш кулдаун (с)", "min": 0.2, "max": 1.5, "step": 0.05, "default": 0.6},
	{"section": "Вратарь", "key": "goalie_handedness_right", "label": "Ловушка на левой (правый хват)", "type": "toggle", "default": true},
	{"section": "Вратарь", "key": "goalie_player_controlled", "label": "Играбельный вратарь (дебаг)", "type": "toggle", "default": false},
	{"section": "Вратарь", "key": "training_shooter", "label": "Манекен-бросающий (тренировка)", "type": "toggle", "default": false},
	{"section": "Камера вратаря", "key": "gcam_distance", "label": "Отступ (м)", "min": 3.0, "max": 20.0, "step": 0.25, "default": 4.25},
	{"section": "Камера вратаря", "key": "gcam_height", "label": "Высота цели (м)", "min": 0.0, "max": 4.0, "step": 0.1, "default": 0.9},
	{"section": "Камера вратаря", "key": "gcam_pitch", "label": "Наклон (°)", "min": 15.0, "max": 55.0, "step": 1.0, "default": 25.0},
	{"section": "Камера вратаря", "key": "gcam_fov", "label": "FOV (°)", "min": 50.0, "max": 100.0, "step": 1.0, "default": 72.0},
	{"section": "Камера вратаря", "key": "gcam_smoothing", "label": "Плавность позиции (1/с)", "min": 1.0, "max": 20.0, "step": 0.1, "default": 8.0},
	{"section": "Камера вратаря", "key": "gcam_sensitivity", "label": "Чувствит. мыши (°/px)", "min": 0.02, "max": 0.8, "step": 0.01, "default": 0.21},
	{"section": "Броски", "key": "wrist_tap_time", "label": "Тап кистевого (с)", "min": 0.1, "max": 0.4, "step": 0.01, "default": 0.22},
	{"section": "Броски", "key": "wrist_speed", "label": "Кистевой скорость (м/с)", "min": 8.0, "max": 30.0, "step": 0.5, "default": 17.0},
	{"section": "Броски", "key": "wrist_lift", "label": "Кистевой подъём (м/с)", "min": 0.0, "max": 4.0, "step": 0.1, "default": 1.2},
	{"section": "Броски", "key": "slap_charge_time", "label": "Зарядка щелчка (с)", "min": 0.3, "max": 1.5, "step": 0.05, "default": 0.7},
	{"section": "Броски", "key": "slap_speed_min", "label": "Щелчок мин (м/с)", "min": 12.0, "max": 30.0, "step": 0.5, "default": 20.0},
	{"section": "Броски", "key": "slap_speed_max", "label": "Щелчок макс (м/с)", "min": 20.0, "max": 50.0, "step": 0.5, "default": 40.0},
	{"section": "Броски", "key": "slap_lift_max", "label": "Щелчок подъём макс (м/с)", "min": 2.0, "max": 10.0, "step": 0.1, "default": 7.0},
	{"section": "Броски", "key": "slap_spread", "label": "Разброс щелчка (°)", "min": 0.0, "max": 12.0, "step": 0.5, "default": 7.0},
	{"section": "Броски", "key": "slap_move_cap", "label": "Скорость при замахе (x)", "min": 0.2, "max": 1.0, "step": 0.05, "default": 0.55},
	{"section": "Броски", "key": "windup_turn_rate", "label": "Доворот на зарядке (°/с)", "min": 60.0, "max": 480.0, "step": 10.0, "default": 240.0},
	{"section": "Броски", "key": "shot_window", "label": "Окно контроля броска (м)", "min": 0.15, "max": 0.6, "step": 0.01, "default": 0.30},
	{"section": "Броски", "key": "pass_speed", "label": "Пас скорость (м/с)", "min": 6.0, "max": 25.0, "step": 0.5, "default": 16.0},
	{"section": "Броски", "key": "pass_speed_max", "label": "Пас скорость макс (м/с)", "min": 10.0, "max": 30.0, "step": 0.5, "default": 24.0},
	{"section": "Броски", "key": "pass_lift_max", "label": "Пас подъём макс (м/с)", "min": 0.0, "max": 4.0, "step": 0.1, "default": 1.5},
	{"section": "Арена", "key": "rink_length", "label": "Длина катка (м)", "min": 30.0, "max": 70.0, "step": 1.0, "default": 56.0},
	{"section": "Арена", "key": "rink_width", "label": "Ширина катка (м)", "min": 16.0, "max": 36.0, "step": 1.0, "default": 26.0},
	{"section": "Арена", "key": "corner_radius", "label": "Радиус углов (м)", "min": 2.0, "max": 12.0, "step": 0.5, "default": 7.0},
]

@export var max_speed := 9.0
@export var accel := 9.0
@export var accel_curve_power := 1.0
@export var turn_rate_at_zero := 540.0
@export var crossover_gain := 0.18
@export var friction_along := 0.35
@export var run_carve_grip := 0.03
@export var run_carve_threshold := 2.5
@export var run_skid_friction := 6.0
@export var run_turn_rate_max := 320.0
@export var run_facing_accel := 2200.0
@export var quick_stop_friction := 14.0
@export var reverse_angle := 150.0
@export var glide_carve_grip := 0.2
@export var glide_carve_threshold := 0.8
@export var glide_skid_friction := 4.5
@export var glide_turn_rate_max := 200.0
@export var glide_facing_accel := 1400.0
@export var sprint_speed_mult := 1.3
@export var sprint_max := 5.0
@export var stamina_regen_time := 7.0
@export var dash_impulse := 4.0
@export var dash_overspeed := 2.5
@export var hud_stamina := true
@export var stance_thrust_cap := 0.9
@export var gesture_glide_extra := 0.15
@export var carry_stiffness := 600.0
@export var carry_max_force := 180.0
@export var carry_heel_offset := 0.06
@export var carry_break_dist := 0.85
@export var release_grace := 0.35
@export var flip_up_speed := 3.9
@export var puck_wall_margin := 0.12
@export var trail_min_speed := 14.0
@export var puck_trail_enabled := true
@export var short_pose_angle := 16.0
@export var pose_blade_speed := 22.0
@export var pose_angle := 35.0
@export var wide_pose_angle := 55.0
@export var hold_max := 0.4
@export var pose_roll := 20.0
@export var transfer_time := 0.12
@export var pivot_transfer_angle := 100.0
@export var transfer_assist_mult := 1.8
@export var transfer_reliable_speed := 7.5
@export var camera_distance := 6.5
@export var camera_height := 1.2
@export var camera_pitch := 42.0
@export var camera_fov := 75.0
@export var camera_smoothing := 8.0
@export var mouse_sensitivity := 0.22
@export var handedness_right := true
@export var hand_offset_side := 0.22
@export var hand_offset_forward := 0.15
@export var stick_length := 1.35
@export var backhand_limit := -60.0
@export var forehand_limit := 200.0
@export var neutral_angle := 20.0
@export var blade_angular_speed := 600.0
@export var blade_angular_accel := 6000.0
@export var reach_transition := 0.2
@export var stance_reach_bonus := 0.22
@export var assist_radius := 0.22
@export var assist_strength := 14.0
@export var assist_max_rel_speed := 6.0
@export var assist_max_force := 8.0
@export var catch_radius := 0.35
@export var catch_max_rel_speed := 12.0
@export var catch_strength := 35.0
@export var catch_max_force := 20.0
@export var pickup_radius := 0.5
@export var aim_assist_strength := 0.5
@export var lean_turn := 18.0
@export var lean_juke := 25.0
@export var lean_fake := 30.0
@export var juke_impulse := 1.1
@export var wide_time := 0.2
@export var triangle_window := 0.6
@export var fake_impulse := 1.0
@export var fake_cooldown := 0.5
@export var idle_dribble_amp := 0.05
@export var poke_range := 1.3
@export var poke_cooldown := 0.9
@export var juggle_window := 0.11
@export var air_juggle_cooldown := 0.5
@export var kick_forward_speed := 1.2
@export var skate_zone := 0.4
@export var player_mass := 80.0
@export var hit_impulse_scale := 1.0
@export var hit_stun := 0.6
@export var hit_window := 2.0
@export var hit_reach := 0.5
@export var hit_cooldown := 1.2
@export var poke_reach := 1.2
@export var poke_windup := 0.2
@export var poke_contact := 0.12
@export var backward_control := 0.6
@export var goalie_enabled := false
@export var goalie_move_speed := 0.5
@export var goalie_range := 3.0
@export var catch_reach := 1.0
@export var catch_window := 0.25
@export var cover_radius := 0.8
@export var goalie_save_cooldown := 0.2
@export var goalie_recovery := 0.5
@export var goalie_reaction_time := 0.18
@export var push_distance := 0.9
@export var push_cooldown := 0.6
@export var goalie_handedness_right := true
@export var goalie_player_controlled := false
@export var training_shooter := false
@export var gcam_distance := 4.25
@export var gcam_height := 0.9
@export var gcam_pitch := 25.0
@export var gcam_fov := 72.0
@export var gcam_smoothing := 8.0
@export var gcam_sensitivity := 0.21
@export var wrist_tap_time := 0.22
@export var wrist_speed := 17.0
@export var wrist_lift := 1.2
@export var slap_charge_time := 0.7
@export var slap_speed_min := 20.0
@export var slap_speed_max := 40.0
@export var slap_lift_max := 7.0
@export var slap_spread := 7.0
@export var slap_move_cap := 0.55
@export var windup_turn_rate := 240.0
@export var shot_window := 0.30
@export var pass_speed := 16.0
@export var pass_speed_max := 24.0
@export var pass_lift_max := 1.5
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
