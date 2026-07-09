extends SceneTree
## Генератор справочников из КОДА (источник истины — input map + PARAM_DEFS):
##   docs/CONTROLS.md — раскладка: клавиша -> действие -> режимы;
##   docs/PARAMS.md   — все параметры панели по секциям с дефолтами.
## Запуск: godot --headless --path . --script res://tools/gen_docs.gd
## Прогонять после ЛЮБОГО изменения input map или PARAM_DEFS.

# Описания действий: действие и поведение по режимам. Лежит рядом с кодом —
# обновляется в том же коммите, что и логика.
const ACTIONS := {
	"move_forward": ["Движение вперёд (относительно камеры)", "Везде. Для финтов кликов — направление «вперёд»."],
	"move_back": ["Тормоз / хоккейный стоп / пивот на спину", "Бег: плуг/юз. В СКОЛЬЖЕНИИ (Alt) + назад = пивот на спину (езда спиной, скорость сохраняется). Для финтов кликов — направление «назад» (треугольник, финт через конёк)."],
	"turn_left": ["Движение влево", "Везде. Для финтов кликов — направление «влево»."],
	"turn_right": ["Движение вправо", "Везде. Для финтов кликов — направление «вправо»."],
	"stance": ["Стойка (дриблинг)", "Удержание: тяга с капом, ЛКМ/ПКМ/Пробел = финты, укрывание шайбы корпусом."],
	"profile_glide": ["Профиль СКОЛЬЖЕНИЕ", "Удержание: velocity поворачивается за корпусом без потерь (руль), тяги нет; укрывание. + назад = пивот на спину (езда спиной)."],
	"sprint": ["Спринт (удержание) / Рывок (двойное)", "УДЕРЖАНИЕ Shift при движении: спринт — скорость и тяга x sprint_speed_mult, тратит бак (sprint_max сек); пустой — недоступен, восстановление вне спринта. ДВОЙНОЕ нажатие Shift = рывок: только при ПОЛНОМ баке, тратит весь (взрывной импульс dash_impulse). Выбор: длинный спринт ИЛИ рывок."],
	"gesture_primary": ["ЛКМ — бросок / дриблинг", "Вне стойки: тап = кистевой, удержание = щелчок (замах, заряд, клюшка поднимается). Стойка: ТАП = короткий перевод к хвату (внешняя); УДЕРЖАНИЕ = широкий дриблинг (ширина растёт по времени до hold_max, на отпускании боковой шаг); +назад = треугольник-сетап (выход: ЛКМ+вбок в окне — выстрел из-под конька). Воздух: удар в лёд ОТ хвата (широко)."],
	"gesture_secondary": ["ПКМ — пас / дриблинг", "Вне стойки: пас (тап/заряд с подъёмом); во время замаха щелчка — отмена. Стойка: ТАП = короткий перевод от хвата (внутренняя); УДЕРЖАНИЕ = широкий дриблинг; +вбок у борта (<2.5 м) = банк от борта. Воздух: мягко вернуть К хвату."],
	"gesture_lift": ["Пробел — подброс / воздух", "Стойка, шайба на ВНЕШНЕЙ = подброс (~0.8 м, летит с игроком). Внутренняя = ничего (нужен перевод ЛКМ). +назад (любая сторона) = финт через конёк (за спину -> конёк -> вперёд в клюшку). Воздух: набивание — окно СТРОГО juggle_window до льда + кулдаун."],
	"feint_left": ["Q — фейк влево / силовой", "Стойка или с шайбой: фейк корпусом ВЛЕВО (дабл-тап = усиленный). Без шайбы вне стойки: СИЛОВОЙ — телеграф 0.15 с, хит в ближайшего в hit_reach перед собой (импульс по массе x скорости), кулдаун hit_cooldown."],
	"feint_right": ["E — фейк вправо / отбор", "Стойка или с шайбой: фейк корпусом ВПРАВО (дабл-тап = усиленный). Без шайбы вне стойки: ЧЕСТНЫЙ ОТБОР — видимый телеграф-замах poke_windup, затем окно контакта poke_contact; достаёт шайбу только в конусе перед собой и если не укрыта корпусом; промах = полный кулдаун poke_cooldown."],
	"toggle_tuning": ["F1 — тюнинг-панель", "Все параметры; правки автосохраняются в user://skating_params.json (дебаунс 1 с)."],
	"toggle_debug_viz": ["F2 — дебаг-оверлей", "Крюк/сектор, состояние и сторона шайбы, окно набивания, трактовка Q/E, стан/фол, луч броска."],
	"toggle_cones": ["F3 — полигон", "Цикл: конусы -> манекены (статик/патруль/вратарь) -> оба -> пусто."],
	"toggle_handedness": ["H — смена хвата", "Правша/левша (клюшка и правила стороны зеркалятся)."],
	"swap_goalie": ["G — свап на вратаря", "Переключение управления полевой<->вратарь (вратарь спавнится при нужде). В роли вратаря: WASD в зоне ворот, Пробел=баттерфляй (+сторона=падение), ЛКМ=ловушка, ПКМ=блин; камера за вратарём."],
	"debug_respawn": ["R — шайбу в центр", "Дебаг."],
	"debug_push": ["P — толчок шайбы", "Дебаг: случайный импульс."],
	"debug_shoot": ["T — выстрел в ворота", "Дебаг: шайба летит в ближайшие ворота."],
}
const ACTION_ORDER := [
	"move_forward", "move_back", "turn_left", "turn_right",
	"stance", "profile_glide", "sprint",
	"gesture_primary", "gesture_secondary", "gesture_lift",
	"feint_left", "feint_right", "swap_goalie",
	"toggle_tuning", "toggle_debug_viz", "toggle_cones", "toggle_handedness",
	"debug_respawn", "debug_push", "debug_shoot",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs")
	_write_controls()
	_write_params()
	print("DOCS OK: docs/CONTROLS.md, docs/PARAMS.md")
	quit(0)


func _key_label(action: String) -> String:
	var labels: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			labels.append(OS.get_keycode_string((ev as InputEventKey).physical_keycode))
		elif ev is InputEventMouseButton:
			var idx := (ev as InputEventMouseButton).button_index
			labels.append({1: "ЛКМ", 2: "ПКМ", 3: "СКМ"}.get(idx, "Мышь%d" % idx))
	return " / ".join(labels) if labels.size() > 0 else "?"


func _write_controls() -> void:
	var out := "# BULLIT — управление\n\n"
	out += "> Сгенерировано из input map: `godot --headless --path . --script res://tools/gen_docs.gd`.\n"
	out += "> НЕ править руками — источник истины код (project.godot + tools/gen_docs.gd).\n\n"
	out += "Мышь — камера ВСЕГДА (yaw; pitch статичный из панели). Esc — отпустить/захватить мышь.\n\n"
	out += "| Клавиша | Действие | Поведение по режимам |\n|---|---|---|\n"
	for action in ACTION_ORDER:
		if not InputMap.has_action(action):
			continue
		var desc: Array = ACTIONS.get(action, ["(без описания)", ""])
		out += "| **%s** | %s | %s |\n" % [_key_label(action), desc[0], desc[1]]
	# Не описанные в словаре действия — чтобы файл не расходился с кодом.
	for action in InputMap.get_actions():
		var a := String(action)
		if a.begins_with("ui_") or ACTIONS.has(a):
			continue
		out += "| **%s** | %s | ВНИМАНИЕ: нет описания в gen_docs.gd |\n" % [_key_label(a), a]
	var f := FileAccess.open("res://docs/CONTROLS.md", FileAccess.WRITE)
	f.store_string(out)


func _write_params() -> void:
	var params_script := load("res://scripts/skating_params.gd")
	var defs: Array = params_script.PARAM_DEFS
	var out := "# BULLIT — параметры тюнинг-панели (F1)\n\n"
	out += "> Сгенерировано из SkatingParams.PARAM_DEFS (tools/gen_docs.gd). НЕ править руками.\n"
	out += "> Правки в панели автосохраняются в `user://skating_params.json`.\n\n"
	var section := ""
	for def in defs:
		if def.get("section", "") != section:
			section = def.section
			out += "\n## %s\n\n| Параметр | Ключ | Дефолт | Диапазон |\n|---|---|---|---|\n" % section
		if def.get("type", "") == "toggle":
			out += "| %s | `%s` | %s | вкл/выкл |\n" % [def.label, def.key, "вкл" if def.default else "выкл"]
		else:
			out += "| %s | `%s` | %s | %s..%s |\n" % [def.label, def.key, def.default, def.min, def.max]
	var f := FileAccess.open("res://docs/PARAMS.md", FileAccess.WRITE)
	f.store_string(out)
