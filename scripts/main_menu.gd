extends Control
## Главное меню + лобби (сеть v1). Строит UI кодом (плоский стиль, без ассетов).
## Ветки: Хост / Подключиться / Тренировка / Выход. Выбор роли (поле/вратарь)
## до входа. Хост → NetGame(host); Join → NetGame(client, ip); Тренировка →
## одиночная Main.tscn.

const NetGameScene := "res://scenes/NetGame.tscn"
const TrainingScene := "res://scenes/Main.tscn"

var _nick_edit: LineEdit
var _ip_edit: LineEdit
var _role_field: CheckBox
var _role_goalie: CheckBox
var _status: Label
var _lan_btn: Button
var _lan: LanDiscovery
var _updater: Updater


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "BULLIT"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "хоккей 1v1 — сеть v1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.75, 0.8)
	box.add_child(sub)

	box.add_child(_spacer(8))

	box.add_child(_row_label("Ник"))
	_nick_edit = LineEdit.new()
	_nick_edit.text = "player"
	box.add_child(_nick_edit)

	box.add_child(_row_label("Роль"))
	var roles := HBoxContainer.new()
	roles.add_theme_constant_override("separation", 16)
	_role_field = CheckBox.new()
	_role_field.text = "Полевой"
	_role_field.button_pressed = true
	_role_goalie = CheckBox.new()
	_role_goalie.text = "Вратарь"
	var rg := ButtonGroup.new()
	_role_field.button_group = rg
	_role_goalie.button_group = rg
	roles.add_child(_role_field)
	roles.add_child(_role_goalie)
	box.add_child(roles)

	box.add_child(_spacer(8))

	var host_btn := Button.new()
	host_btn.text = "Хостить игру"
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)

	box.add_child(_row_label("IP хоста"))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	box.add_child(_ip_edit)

	var join_btn := Button.new()
	join_btn.text = "Подключиться"
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	# Кнопка найденной в локалке игры (появляется, когда пришёл маячок).
	_lan_btn = Button.new()
	_lan_btn.visible = false
	_lan_btn.modulate = Color(0.6, 1.0, 0.7)
	_lan_btn.pressed.connect(_on_lan_join)
	box.add_child(_lan_btn)

	box.add_child(_spacer(8))

	var train_btn := Button.new()
	train_btn.text = "Тренировка (одному)"
	train_btn.pressed.connect(_on_training)
	box.add_child(train_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Выход"
	exit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(exit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.9, 0.8, 0.4)
	box.add_child(_status)

	# Мышь видима в меню.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Самообновление при запуске (в экспортированном билде; в редакторе пропуск).
	_updater = Updater.new()
	add_child(_updater)
	_updater.status.connect(func(t): _status.text = t)
	_updater.check_and_update()

	# Автопоиск игр в локальной сети.
	_lan = LanDiscovery.new()
	add_child(_lan)
	_lan.host_found.connect(_on_lan_found)
	_lan.listen()


func _on_lan_found(ip: String, port: int, host_nick: String) -> void:
	# Нашли хоста в локалке — подставляем IP и показываем кнопку прямого входа.
	_ip_edit.text = ip
	NetConfig.port = port
	var who := host_nick if host_nick != "" else ip
	_lan_btn.text = "▶ Играть в локалке: %s" % who
	_lan_btn.visible = true


func _on_lan_join() -> void:
	_on_join()


func _row_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.75, 0.8, 0.85)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _apply_config() -> void:
	NetConfig.nick = _nick_edit.text.strip_edges()
	if NetConfig.nick == "":
		NetConfig.nick = "player"
	NetConfig.role = "goalie" if _role_goalie.button_pressed else "field"


func _on_host() -> void:
	_apply_config()
	NetConfig.mode = "host"
	get_tree().change_scene_to_file(NetGameScene)


func _on_join() -> void:
	_apply_config()
	NetConfig.mode = "client"
	NetConfig.join_ip = _ip_edit.text.strip_edges()
	if NetConfig.join_ip == "":
		NetConfig.join_ip = "127.0.0.1"
	get_tree().change_scene_to_file(NetGameScene)


func _on_training() -> void:
	_apply_config()
	NetConfig.mode = "training"
	get_tree().change_scene_to_file(TrainingScene)
