extends CanvasLayer
## Тюнинг-панель (F1): слайдеры для всех параметров SkatingParams,
## сохранение/загрузка user://skating_params.json, сброс к дефолтам.
## UI строится процедурно по SkatingParams.PARAM_DEFS.

var params: SkatingParams

var _rows := {}  # key -> {"slider": HSlider, "value": Label}


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


func _refresh_all() -> void:
	if params == null:
		return
	for def in SkatingParams.PARAM_DEFS:
		var value: float = params.get(def.key)
		_rows[def.key].slider.set_value_no_signal(value)
		_rows[def.key].value.text = _format_value(value)


func _on_slider_changed(value: float, key: String) -> void:
	if params:
		params.set(key, value)
	_rows[key].value.text = _format_value(value)


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
