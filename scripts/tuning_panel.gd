extends CanvasLayer
## Тюнинг-панель (F1): слайдеры для всех параметров SkatingParams,
## сохранение/загрузка user://skating_params.json, сброс к дефолтам.
## Любая правка АВТОСОХРАНЯЕТСЯ (дебаунс 1 с) — камера и прочее переживают
## перезапуск без кнопки. UI строится процедурно по SkatingParams.PARAM_DEFS.

signal rebuild_requested
signal clear_trail_requested
signal toggle_trail_requested(enabled: bool)

const AUTOSAVE_DELAY := 1.0

var params: SkatingParams

var _rows := {}  # key -> {"slider": HSlider, "value": Label}
var _autosave_t := -1.0  # >0 — отложенное сохранение тикает


func _process(delta: float) -> void:
	if _autosave_t > 0.0:
		_autosave_t -= delta
		if _autosave_t <= 0.0 and params:
			params.save_to_json()


func _queue_autosave() -> void:
	_autosave_t = AUTOSAVE_DELAY


func _ready() -> void:
	visible = false
	_build_ui()


func setup(new_params: SkatingParams) -> void:
	params = new_params
	_refresh_all()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_tuning"):
		visible = not visible


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 48)
	panel.self_modulate = Color(1, 1, 1, 0.92)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(570, 560)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Тюнинг (F1 — скрыть)"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var current_section := ""
	for def in SkatingParams.PARAM_DEFS:
		if def.get("section", "") != current_section:
			current_section = def.section
			var header := Label.new()
			header.text = "— %s —" % current_section
			header.add_theme_font_size_override("font_size", 16)
			header.modulate = Color(0.7, 0.85, 1.0)
			vbox.add_child(header)
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var name_label := Label.new()
		name_label.text = def.label
		name_label.custom_minimum_size = Vector2(230, 0)
		row.add_child(name_label)

		if def.get("type", "") == "toggle":
			var check := CheckButton.new()
			check.toggled.connect(_on_toggle_changed.bind(def.key))
			row.add_child(check)
			_rows[def.key] = {"toggle": check}
			continue

		var slider := HSlider.new()
		slider.min_value = def.min
		slider.max_value = def.max
		slider.step = def.step
		slider.custom_minimum_size = Vector2(220, 0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_slider_changed.bind(def.key))
		row.add_child(slider)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		_rows[def.key] = {"slider": slider, "value": value_label}

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)

	var save_button := Button.new()
	save_button.text = "Сохранить в JSON"
	save_button.pressed.connect(_on_save)
	buttons.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Загрузить"
	load_button.pressed.connect(_on_load)
	buttons.add_child(load_button)

	var reset_button := Button.new()
	reset_button.text = "Сброс к дефолту"
	reset_button.pressed.connect(_on_reset)
	buttons.add_child(reset_button)

	# Камера: явные кнопки (правки всё равно автосохраняются, но по ТЗ нужны).
	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 8)
	vbox.add_child(cam_row)
	var cam_save := Button.new()
	cam_save.text = "Сохранить камеру"
	cam_save.pressed.connect(_on_save)  # пишет весь JSON (камера включена)
	cam_row.add_child(cam_save)
	var cam_reset := Button.new()
	cam_reset.text = "Сбросить камеру"
	cam_reset.pressed.connect(_on_reset_camera)
	cam_row.add_child(cam_reset)

	var rebuild_button := Button.new()
	rebuild_button.text = "Пересобрать каток"
	rebuild_button.pressed.connect(func(): rebuild_requested.emit())
	vbox.add_child(rebuild_button)

	var trail_row := HBoxContainer.new()
	trail_row.add_theme_constant_override("separation", 8)
	vbox.add_child(trail_row)

	var trail_toggle := CheckButton.new()
	trail_toggle.text = "След юза"
	trail_toggle.button_pressed = true
	trail_toggle.toggled.connect(func(on): toggle_trail_requested.emit(on))
	trail_row.add_child(trail_toggle)

	var clear_trail_button := Button.new()
	clear_trail_button.text = "Очистить след"
	clear_trail_button.pressed.connect(func(): clear_trail_requested.emit())
	trail_row.add_child(clear_trail_button)


func refresh_values() -> void:
	_refresh_all()


func _refresh_all() -> void:
	if params == null:
		return
	for def in SkatingParams.PARAM_DEFS:
		if def.get("type", "") == "toggle":
			_rows[def.key].toggle.set_pressed_no_signal(bool(params.get(def.key)))
			continue
		var value: float = params.get(def.key)
		_rows[def.key].slider.set_value_no_signal(value)
		_rows[def.key].value.text = _format_value(value)


func _on_slider_changed(value: float, key: String) -> void:
	if params:
		params.set(key, value)
		_queue_autosave()
	_rows[key].value.text = _format_value(value)


func _on_toggle_changed(pressed: bool, key: String) -> void:
	if params:
		params.set(key, pressed)
		_queue_autosave()


func _format_value(value: float) -> String:
	return "%.2f" % value


func _on_save() -> void:
	if params:
		params.save_to_json()


func _on_load() -> void:
	if params and params.load_from_json():
		_refresh_all()


func _on_reset() -> void:
	if params:
		params.reset_to_defaults()
		_refresh_all()
		_queue_autosave()  # сброс тоже переживает перезапуск


## Сброс ТОЛЬКО параметров секции «Камера» к дефолтам (остальное не трогаем).
func _on_reset_camera() -> void:
	if params == null:
		return
	for def in SkatingParams.PARAM_DEFS:
		if def.get("section", "") == "Камера":
			params.set(def.key, def.default)
	_refresh_all()
	_queue_autosave()
