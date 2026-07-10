extends Node3D
## Сетевая игровая сборка (сеть v1). Серверный авторитет: сервер гоняет
## симуляцию (физика игроков/шайбы), применяет присланный ввод к player.input
## удалённых пиров, рассылает снапшоты 30 Гц. Клиент: шлёт свой ввод, гасит
## локальную симуляцию (ставит куклы) и рендерит интерполированное состояние.
##
## Запуск: из MainMenu (host/join) ИЛИ headless с аргументами
##   --server           (порт 9050)
##   --client <ip>      (коннект)
## для 2-процессного автотеста.

const PlayerScene := preload("res://scenes/Player.tscn")
const RinkScene := preload("res://scenes/Rink.tscn")
const PuckScene := preload("res://scenes/Puck.tscn")
const GoalScene := preload("res://scenes/Goal.tscn")

var params := SkatingParams.new()
var net: Net
var mode := "host"          # host / client
var join_ip := "127.0.0.1"
var port := 9050
var nick := "player"

var role := "field"         # роль ЛОКАЛЬНОГО игрока (field/goalie)

var _players := {}          # peer id -> Player node
var _puck: RigidBody3D
var _rink: Node3D
var _lan: LanDiscovery       # хост: маячок в локальную сеть
var _goals := []            # [Goal, Goal]
var _goal_x := 24.0
var _tick := 0
var _interp := InterpBuffer.new()
var _spawn_side := {}       # id -> +1/-1 (стартовая половина)

# Буллит-петля (серверный авторитет).
var _score := {"left": 0, "right": 0}
var _round := "play"        # play / reset (пауза перед вбросом)
var _reset_timer := 0.0
const RESET_PAUSE := 3.0

# Броски (серверный авторитет): состояние заряда по игроку + прицел из пакета.
var _shot := {}   # id -> {lmb_t, charging, charge, rmb_held, rmb_t, pass_charge, windup_cd}
var _aim := {}    # id -> Vector3 (направление броска из камеры пира)
const AIM_DISTANCE := 40.0
const AIM_CONE_DEG := 14.0

# HUD
var _hud: CanvasLayer
var _score_label: Label
var _round_label: Label
var _net_panel: Panel
var _net_label: Label
var _net_debug := false
var _hud_ctrl: Control
# Читается hud.gd (как у main.gd): заряд/пас локального игрока + ссылки.
var charge := 0.0
var pass_charge := 0.0
var skating_params            # алиас params для hud.gd
var _hud_lmb_t := 0.0         # клиентский мираж заряда для HUD
var _hud_rmb_t := 0.0
var _hud_rmb_held := false
var player                    # локальный полевой игрок (для hud.gd)
var blade                     # его клюшка (для hud.gd)

# Headless-хуки для 2-процессного автотеста:
var _autofwd := false       # клиент шлёт move_forward каждый тик
var _autobutterfly := false # клиент-вратарь шлёт gesture_lift (баттерфляй)
var _runframes := 0         # >0: выйти после N physics-кадров
var _dump_path := ""        # при выходе выгрузить состояние в JSON
var _frames := 0
var _headless := false
var _scoretest := false     # автотест буллит-петли (гол засчитывается один раз)
var _scoretest_log := []


func _ready() -> void:
	params.load_from_json()
	skating_params = params
	# Выбор из меню (autoload). Headless-аргументы имеют приоритет.
	if Engine.has_singleton("NetConfig") or get_node_or_null("/root/NetConfig"):
		var cfg := get_node_or_null("/root/NetConfig")
		if cfg:
			mode = cfg.mode
			join_ip = cfg.join_ip
			port = cfg.port
			nick = cfg.nick
			role = cfg.role
	_apply_cli_args()
	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.input_received.connect(_on_input_received)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.snapshot_received.connect(_on_snapshot)
	net.game_event.connect(_on_game_event)
	net.connection_failed.connect(_on_connection_failed)
	net.disconnected.connect(_on_disconnected)

	_build_arena()
	_build_hud()

	# Захват мыши: камера вращается относительным движением мыши (как в одиночной).
	# Без захвата курсор торчит на экране и камера не крутится.
	if not _headless:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if mode == "host":
		if net.host(port, nick):
			net.set_role(1, role)
			_spawn_player(1)  # хост-игрок (peer 1)
			if role != "goalie" and _hud_ctrl and player:
				_hud_ctrl.main = self   # включаем полевой HUD у хоста
			# Маячок в локальную сеть — чтобы клиент нашёл игру без ввода IP.
			_lan = LanDiscovery.new()
			add_child(_lan)
			_lan.advertise(port, nick)
	else:
		net.join(join_ip, port, nick)


func _apply_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--server":
			mode = "host"
		elif args[i] == "--client":
			mode = "client"
			if i + 1 < args.size():
				join_ip = args[i + 1]
		elif args[i] == "--autofwd":
			_autofwd = true
		elif args[i] == "--runframes" and i + 1 < args.size():
			_runframes = int(args[i + 1])
			_headless = true
		elif args[i] == "--dump" and i + 1 < args.size():
			_dump_path = args[i + 1]
		elif args[i] == "--scoretest":
			_scoretest = true
			_headless = true
		elif args[i] == "--autobutterfly":
			_autobutterfly = true
		elif args[i] == "--hostgoalie":
			role = "goalie"   # хост — вратарь (клиент станет полевым)


func _build_arena() -> void:
	_rink = RinkScene.instantiate()
	add_child(_rink)
	_rink.rebuild(params.rink_length, params.rink_width, params.corner_radius)
	_goal_x = _rink.goal_line_x()
	for sx in [-1, 1]:
		var g := GoalScene.instantiate()
		g.position = Vector3(sx * _goal_x, 0, 0)
		g.side = "left" if sx < 0 else "right"
		if sx > 0:
			g.rotation.y = PI
		add_child(g)
		g.goal_scored.connect(_on_goal_scored)
		_goals.append(g)
	_puck = PuckScene.instantiate()
	add_child(_puck)
	_puck.reset_to(Vector3(0, 0.1, 0))
	# Камера (только для локального рендера; в headless не мешает).
	var cam := preload("res://scripts/chase_camera.gd").new()
	cam.name = "Camera3D"
	cam.params = params
	cam.fov = 55.0
	cam.current = true
	add_child(cam)


## Сервер: создать актёра (полевой ИЛИ вратарь) для пира по его роли.
## side задаёт стартовую половину/свои ворота.
func _spawn_player(id: int) -> Node3D:
	if _players.has(id):
		return _players[id]
	var side: int = 1 if _players.is_empty() else -1
	_spawn_side[id] = side
	var r: String = net.peers.get(id, {}).get("role", "field")
	var node: Node3D
	if r == "goalie":
		node = _make_goalie(id, side)
	else:
		node = _make_field(id, side)
	_players[id] = node
	# Камера следит за локальным актёром; вратарю — свой пресет.
	if id == multiplayer.get_unique_id():
		var cam := get_node_or_null("Camera3D")
		if cam:
			cam.target = node
			cam.goalie_mode = (r == "goalie")
	return node


func _make_field(id: int, side: int) -> Player:
	var p: Player = PlayerScene.instantiate()
	p.name = "Player_%d" % id
	p.params = params
	# Ввод: хост-игрок снимает Input; удалённые — из сети (сервер пишет пакет).
	p.input_local = (id == multiplayer.get_unique_id())
	# Удалённый игрок на сервере: WASD относительно yaw камеры пира (из пакета),
	# иначе движение считается от чужой камеры → инверсия управления.
	p.use_net_yaw = (id != multiplayer.get_unique_id())
	add_child(p)
	p.global_position = Vector3(-side * 4.0, 0.0, 0.0)
	p.rotation.y = 0.0 if side > 0 else PI
	if id == multiplayer.get_unique_id():
		player = p
		blade = p.get_node_or_null("Blade")
	return p


func _make_goalie(id: int, side: int) -> Goalie:
	var g: Goalie = preload("res://scripts/goalie.gd").new()
	g.name = "Goalie_%d" % id
	params.goalie_player_controlled = true
	g.input_local = (id == multiplayer.get_unique_id())
	# Удалённый вратарь (сервер) разворачивается по присланному yaw камеры пира.
	g.use_net_yaw = (id != multiplayer.get_unique_id())
	add_child(g)
	# Свои ворота: side +1 → левые (-X), side -1 → правые (+X). out_dir — в поле.
	var own_goal := Vector3(-side * _goal_x, 0.0, 0.0)
	var out := Vector3(side, 0.0, 0.0)
	g.setup(own_goal, out, _find_field_actor(), _puck, params)
	return g


func _find_field_actor() -> Node3D:
	for id in _players:
		if _players[id] is Player:
			return _players[id]
	return null


func _on_peer_joined(id: int, _nick: String) -> void:
	if net.is_server and id != 1:
		# Буллит: клиент получает роль, противоположную хосту (1 полевой + 1 вратарь).
		var host_role: String = net.peers.get(1, {}).get("role", "field")
		net.set_role(id, "field" if host_role == "goalie" else "goalie")
		_spawn_player(id)


func _on_peer_left(id: int) -> void:
	if _players.has(id):
		_players[id].queue_free()
		_players.erase(id)


func _on_input_received(id: int, tick: int, packet: Dictionary) -> void:
	# Сервер применяет ввод пира к его игроку (кламп частоты — базовый).
	if not net.is_server:
		return
	var p = _players.get(id)
	if p == null:
		return
	p.input.apply_packet(packet.get("s", {}), packet.get("e", {}), packet.get("r", {}))
	# Разворот/движение по yaw камеры пира (у пира нет камеры на сервере).
	if packet.has("yaw"):
		p.net_yaw = packet["yaw"]
	# Полевой: прицел броска — направление из камеры пира (в пакете).
	if p is Player and packet.has("aim"):
		var a = packet["aim"]
		_aim[id] = Vector3(a[0], 0.0, a[1])


func _physics_process(delta: float) -> void:
	_tick += 1
	if net.is_server:
		_server_tick(delta)
	else:
		_client_tick(delta)
	# Headless-автотест: выйти после N кадров, выгрузив состояние.
	_frames += 1
	if _runframes > 0 and _frames >= _runframes:
		_dump_state()
		get_tree().quit(0)


func _dump_state() -> void:
	if _dump_path == "":
		return
	var out := {"is_server": net.is_server, "peers": net.peers.size(),
			"score": _score, "round": _round, "players": {}}
	for id in _players:
		var p = _players[id]
		var e := {"x": p.global_position.x, "z": p.global_position.z}
		if p is Goalie:
			e["kind"] = "goalie"
			e["state"] = p.state
		else:
			e["kind"] = "field"
		out["players"][str(id)] = e
	if _puck:
		out["puck"] = {"x": _puck.global_position.x, "z": _puck.global_position.z}
	var f := FileAccess.open(_dump_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2:
				_net_debug = not _net_debug
				if _net_panel:
					_net_panel.visible = _net_debug
			KEY_ESCAPE:
				_return_to_menu()
			KEY_F3:
				# Хост: смена ролей между игроками (перед раундом).
				if net.is_server:
					_host_swap_roles()


func _host_swap_roles() -> void:
	# Меняем роли местами у двух пиров и переспавниваем на вбросе.
	var ids := _players.keys()
	if ids.size() < 2:
		return
	for id in ids:
		var cur: String = net.peers.get(id, {}).get("role", "field")
		net.set_role(id, "goalie" if cur == "field" else "field")
	_round = "reset"
	_reset_timer = RESET_PAUSE


func _process(_dt: float) -> void:
	if _round_label:
		if _round == "reset":
			_round_label.text = "Вброс через %.1f…" % maxf(_reset_timer, 0.0)
		else:
			_round_label.text = ""
	if _net_debug and _net_label and net:
		_net_label.text = "СЕТЬ (F2)\n"
		_net_label.text += "роль: %s  %s\n" % [mode, "сервер" if net.is_server else "клиент"]
		_net_label.text += "RTT: %.0f мс\n" % net.rtt_ms
		_net_label.text += "вх/исх: %d / %d Б/с\n" % [net.in_bps, net.out_bps]
		_net_label.text += "снапшот: %d Б\n" % net.last_snapshot_size
		_net_label.text += "интерп: %.0f мс\n" % _interp.delay_ms()
		_net_label.text += "посл. тик ввода: %d" % net.last_input_tick


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	# Счёт по центру сверху.
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 40)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.anchor_left = 0.0
	_score_label.anchor_right = 1.0
	_score_label.offset_top = 16
	_hud.add_child(_score_label)
	# Статус раунда (пауза/вброс).
	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 28)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.anchor_left = 0.0
	_round_label.anchor_right = 1.0
	_round_label.offset_top = 70
	_round_label.modulate = Color(0.95, 0.85, 0.4)
	_hud.add_child(_round_label)
	# Панель «Сеть» (F2).
	_net_panel = Panel.new()
	_net_panel.anchor_left = 1.0
	_net_panel.anchor_right = 1.0
	_net_panel.offset_left = -320
	_net_panel.offset_top = 12
	_net_panel.offset_right = -12
	_net_panel.offset_bottom = 150
	_net_panel.visible = false
	_hud.add_child(_net_panel)
	_net_label = Label.new()
	_net_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_net_label.offset_left = 10
	_net_label.offset_top = 8
	_net_panel.add_child(_net_label)
	# Полевой HUD (прицел, кольцо заряда, пас, стамина/рывок) — как в одиночной.
	_hud_ctrl = preload("res://scripts/hud.gd").new()
	_hud_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_ctrl.main = null   # включится, когда появится локальный полевой игрок
	_hud.add_child(_hud_ctrl)
	_update_score_hud()


func _update_score_hud() -> void:
	if _score_label:
		_score_label.text = "%d : %d" % [_score["left"], _score["right"]]


func _on_goal_scored(side: String) -> void:
	# Считает ТОЛЬКО сервер, ровно один раз за раунд (гейт по _round).
	if not net.is_server or _round != "play":
		return
	# side = ворота, в которые влетела шайба; очко забивает противоположная сторона.
	var scorer := "right" if side == "left" else "left"
	_score[scorer] += 1
	_round = "reset"
	_reset_timer = RESET_PAUSE
	net.broadcast_event("goal", {"scorer": scorer, "score": _score.duplicate()})


func _on_game_event(kind: String, data: Dictionary) -> void:
	match kind:
		"goal":
			_score = data.get("score", _score)
			_round = "reset"
			_reset_timer = RESET_PAUSE
			_update_score_hud()
		"faceoff":
			_round = "play"
			if data.has("score"):
				_score = data["score"]
			_update_score_hud()


func _do_faceoff() -> void:
	# Сервер: вброс — шайба в центр, игроки на стартовые половины.
	_puck.reset_to(Vector3(0, 0.1, 0))
	for id in _players:
		var p = _players[id]
		var side: int = _spawn_side.get(id, 1)
		if p is Player:
			p.global_position = Vector3(-side * 4.0, 0.0, 0.0)
			p.velocity = Vector3.ZERO
			p.rotation.y = 0.0 if side > 0 else PI
		elif p is Goalie:
			# Вратарь — к своим воротам, стойка.
			p.global_position = p.goal_center + p.out_dir * 0.3
			p.state = 0  # STANCE
	_round = "play"
	net.broadcast_event("faceoff", {"score": _score.duplicate()})


func _on_connection_failed() -> void:
	_return_to_menu()


func _on_disconnected() -> void:
	if _headless:
		get_tree().quit(0)
	else:
		_return_to_menu()


func _return_to_menu() -> void:
	net.shutdown()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _server_tick(delta: float) -> void:
	if _scoretest:
		# Автотест: заводим шайбу в ЛЕВЫЕ ворота на кадре 30 и повторно на 60
		# (проверка «гол засчитан ровно один раз» — второй заброс в паузе не в счёт).
		if _frames == 30 or _frames == 60:
			_puck.reset_to(Vector3(-_goal_x - 0.5, 0.3, 0.0))
			_puck.linear_velocity = Vector3(-2, 0, 0)
	# Буллит-петля: после гола пауза, затем вброс.
	if _round == "reset":
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			_do_faceoff()
	else:
		_check_out_of_bounds()
	# Броски/пасы полевых игроков (серверный авторитет).
	for id in _players:
		if _players[id] is Player:
			_server_update_shots(id, delta)
	# HUD хоста: заряд локального игрока из его состояния броска.
	_sync_local_hud_charge()
	# Симуляция игроков/шайбы идёт сама (их _physics_process). Рассылаем снапшот.
	var data := _make_snapshot()
	net.broadcast_snapshot(_tick, data, delta)


## Серверный аналог main._update_shots для игрока id: ЛКМ кистевой/щелчок,
## ПКМ пас; прицел — из пакета (_aim[id]). Броски только вне стойки.
func _server_update_shots(id: int, delta: float) -> void:
	var p = _players[id]
	var b = p.get_node_or_null("Blade")
	if b == null:
		return
	if not _shot.has(id):
		_shot[id] = {"lmb_t": 0.0, "charging": false, "charge": 0.0,
				"rmb_held": false, "rmb_t": 0.0, "pass_charge": 0.0, "windup_cd": 0.0}
	var s: Dictionary = _shot[id]
	# Броски запрещены в стойке / без управления (как в одиночной).
	if (not p.input_enabled) or p.is_stance or _round != "play":
		_reset_shot_state(s, p, b)
		return
	var pr := params
	s["windup_cd"] = maxf(0.0, s["windup_cd"] - delta)
	var aim: Vector3 = _aim.get(id, -Vector3(sin(p.rotation.y), 0, cos(p.rotation.y)))
	# --- ЛКМ: кистевой / щелчок ---
	if p.input.just_pressed("gesture_primary"):
		s["lmb_t"] = 0.0
		s["charging"] = false
	if p.input.pressed("gesture_primary"):
		s["lmb_t"] += delta
		if s["lmb_t"] > pr.wrist_tap_time and s["windup_cd"] <= 0.0:
			s["charging"] = true
			s["charge"] = clampf((s["lmb_t"] - pr.wrist_tap_time) / pr.slap_charge_time, 0.0, 1.0)
			b.windup = s["charge"]
			p.speed_cap = pr.slap_move_cap
			p.aim_turn_dir = aim
	if p.input.just_released("gesture_primary"):
		if s["charging"]:
			_do_slap(b, aim, s["charge"])
		else:
			_do_wrist(b, aim)
		_reset_shot_state(s, p, b)
	# --- ПКМ: пас / отмена замаха ---
	if p.input.just_pressed("gesture_secondary"):
		if s["charging"]:
			_reset_shot_state(s, p, b)
			s["windup_cd"] = 0.2
		else:
			s["rmb_held"] = true
			s["rmb_t"] = 0.0
	if s["rmb_held"]:
		s["rmb_t"] += delta
		s["pass_charge"] = clampf(s["rmb_t"] / 0.5, 0.0, 1.0)
	if p.input.just_released("gesture_secondary") and s["rmb_held"]:
		_do_pass(b, aim, s["pass_charge"])
		s["rmb_held"] = false
		s["pass_charge"] = 0.0


func _reset_shot_state(s: Dictionary, p, b) -> void:
	s["charging"] = false
	s["charge"] = 0.0
	s["lmb_t"] = 0.0
	if b:
		b.windup = 0.0
	if p:
		p.speed_cap = 1.0
		p.aim_turn_dir = Vector3.ZERO


func _do_wrist(b, aim: Vector3) -> void:
	b.shoot(_aim_assist(aim, 1.0), params.wrist_speed, params.wrist_lift)


func _do_slap(b, aim: Vector3, c: float) -> void:
	var dir := _aim_assist(aim, 1.0 - 0.5 * c)
	var spread := deg_to_rad(lerpf(1.0, params.slap_spread, c))
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	b.shoot(dir, lerpf(params.slap_speed_min, params.slap_speed_max, c),
			lerpf(1.5, params.slap_lift_max, c))


func _do_pass(b, aim: Vector3, c: float) -> void:
	b.shoot(aim, lerpf(params.pass_speed, params.pass_speed_max, c),
			lerpf(0.0, params.pass_lift_max, c))


func _aim_assist(dir: Vector3, scale: float) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(AIM_CONE_DEG))
	for g in _goals:
		var to_goal: Vector3 = g.global_position - _puck.global_position
		to_goal.y = 0.0
		if to_goal.length() < 0.1:
			continue
		to_goal = to_goal.normalized()
		var d := dir.dot(to_goal)
		if d > best_dot:
			best = dir.slerp(to_goal, params.aim_assist_strength * scale)
			best_dot = d
	return best.normalized()


## Заряд локального игрока для HUD: у хоста — из его серверного состояния броска,
## у клиента мираж считается в _client_tick.
func _sync_local_hud_charge() -> void:
	var lid := multiplayer.get_unique_id()
	if net.is_server and _shot.has(lid):
		charge = _shot[lid]["charge"]
		pass_charge = _shot[lid]["pass_charge"]


func _check_out_of_bounds() -> void:
	# За ворота заезжать МОЖНО (как в хоккее) — вброс только если шайба реально
	# вылетела за борт (страховка от вылета сквозь геометрию), не за сеткой.
	if _puck == null:
		return
	var px: float = _puck.global_position.x
	var pz: float = _puck.global_position.z
	if absf(px) > params.rink_length / 2.0 + 1.5 or absf(pz) > params.rink_width / 2.0 + 1.5:
		_round = "reset"
		_reset_timer = 1.0


func _make_snapshot() -> Dictionary:
	var players := {}
	for id in _players:
		var p = _players[id]
		if p is Goalie:
			# Вратарь: поза восстанавливается на клиенте локально из state/pose.
			players[id] = {"pos": p.global_position, "rot": p.rotation.y, "k": "g",
					"gs": p.state, "po": p._pose, "cf": p._catch_flash,
					"bf": p._block_flash, "pin": p.puck_in_catch}
		else:
			players[id] = {"pos": p.global_position, "rot": p.rotation.y,
					"vel": p.velocity, "k": "f"}
	var puck := {"pos": _puck.global_position, "vel": _puck.linear_velocity,
			"state": 0}
	var any_blade: Node = _find_blade_any()
	if any_blade:
		puck["state"] = any_blade.puck_state
	return {"players": players, "puck": puck}


func _find_blade_any() -> Node:
	for id in _players:
		if _players[id] is Player:
			var b = _players[id].get_node_or_null("Blade")
			if b:
				return b
	return null


func _client_tick(delta: float) -> void:
	# Клиент: шлёт свой ввод, рендерит интерполированное состояние.
	var mine = _players.get(multiplayer.get_unique_id())
	if mine:
		if _autofwd:
			# Автотест: синтетический ввод «вперёд» (без клавиатуры).
			net.push_input(_tick, {"s": {"move_forward": 1.0}, "e": {}, "r": {}})
		elif _autobutterfly:
			# Автотест вратаря: держим баттерфляй (gesture_lift) + нейтральный yaw.
			net.push_input(_tick, {"s": {"gesture_lift": 1.0}, "e": {}, "r": {}, "yaw": 0.0})
		else:
			mine.input.poll_local()
			var pkt: Dictionary = mine.input.make_packet()
			# Вратарь управляется камерой — шлём yaw для разворота на сервере.
			var cam := get_node_or_null("Camera3D")
			if cam:
				pkt["yaw"] = cam.global_rotation.y
			# Полевой: шлём направление прицела (от шайбы к точке камеры).
			if mine is Player:
				var aim := _local_aim_dir(cam)
				pkt["aim"] = [aim.x, aim.z]
			net.push_input(_tick, pkt)
			_client_hud_charge(mine, delta)
	_interp.advance(delta)
	# Применяем интерполированные позиции к куклам (поза вратаря — сама в кукле).
	for id in _players:
		var p = _players[id]
		p.global_position = _interp.sample_vec3("player_%d" % id, "pos", p.global_position)
		var ry = _interp.latest("player_%d" % id, "rot", p.rotation.y)
		p.rotation.y = ry
	if _puck:
		_puck.global_position = _interp.sample_vec3("puck", "pos", _puck.global_position)


## Направление броска у клиента: от шайбы к точке на луче камеры (как _aim_dir
## в одиночной). Прижато ко льду.
func _local_aim_dir(cam) -> Vector3:
	if cam == null:
		return Vector3(0, 0, -1)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var aim_point: Vector3 = cam.global_position + fwd * AIM_DISTANCE
	var d: Vector3 = aim_point - _puck.global_position
	d.y = 0.0
	if d.length() < 0.5:
		d = fwd
		d.y = 0.0
	return d.normalized()


## Клиентский мираж заряда для HUD (реальный бросок считает сервер).
func _client_hud_charge(mine, delta: float) -> void:
	if not (mine is Player) or mine.is_stance or not mine.input_enabled:
		charge = 0.0
		pass_charge = 0.0
		_hud_lmb_t = 0.0
		_hud_rmb_held = false
		return
	var pr := params
	if mine.input.just_pressed("gesture_primary"):
		_hud_lmb_t = 0.0
	if mine.input.pressed("gesture_primary"):
		_hud_lmb_t += delta
		charge = clampf((_hud_lmb_t - pr.wrist_tap_time) / pr.slap_charge_time, 0.0, 1.0)
	if mine.input.just_released("gesture_primary"):
		_hud_lmb_t = 0.0
		charge = 0.0
	if mine.input.just_pressed("gesture_secondary"):
		_hud_rmb_held = true
		_hud_rmb_t = 0.0
	if _hud_rmb_held:
		_hud_rmb_t += delta
		pass_charge = clampf(_hud_rmb_t / 0.5, 0.0, 1.0)
	if mine.input.just_released("gesture_secondary"):
		_hud_rmb_held = false
		pass_charge = 0.0


func _on_snapshot(_tick_n: int, data: Dictionary) -> void:
	# Клиент: разложить снапшот в буфер интерполяции; спавнить недостающих кукол.
	var flat := {}
	var players: Dictionary = data.get("players", {})
	for id in players:
		var iid := int(id)
		var pd: Dictionary = players[id]
		if not _players.has(iid):
			_spawn_puppet(iid, pd.get("k", "f"))
		# Вратарь-кукла: состояние позы обновляем сразу (проигрывается локально).
		var node = _players.get(iid)
		if node is Goalie:
			node.state = pd.get("gs", node.state)
			node._catch_flash = pd.get("cf", 0.0)
			node._block_flash = pd.get("bf", 0.0)
			node.puck_in_catch = pd.get("pin", false)
		flat["player_%d" % iid] = {"pos": pd["pos"], "rot": pd["rot"]}
	if data.has("puck"):
		flat["puck"] = {"pos": data["puck"]["pos"]}
	_interp.push(flat)


## Клиент: кукла (полевой/вратарь) — симуляция выключена, позиция из снапшотов.
func _spawn_puppet(id: int, kind: String) -> void:
	var p: Node3D
	if kind == "g":
		var g: Goalie = preload("res://scripts/goalie.gd").new()
		g.name = "GoaliePuppet_%d" % id
		g.input_local = false
		g.puppet = true                 # только поза, без симуляции
		add_child(g)
		# setup строит модель; своих ворот у куклы нет — позиция придёт из снапшота.
		g.setup(Vector3.ZERO, Vector3(-1, 0, 0), null, _puck, params)
		p = g
	else:
		var f: Player = PlayerScene.instantiate()
		f.name = "Puppet_%d" % id
		f.params = params
		f.input_local = false
		add_child(f)
		f.set_physics_process(false)   # сервер авторитетен — куклой не рулим
		var blade: Node = f.get_node_or_null("Blade")
		if blade:
			blade.set_physics_process(false)
		p = f
	_players[id] = p
	if id == multiplayer.get_unique_id():
		var cam := get_node_or_null("Camera3D")
		if cam:
			cam.target = p
			cam.goalie_mode = (kind == "g")
		if kind != "g":
			player = p
			blade = p.get_node_or_null("Blade")
			if _hud_ctrl:
				_hud_ctrl.main = self   # включаем полевой HUD, когда игрок есть
	# На клиенте своя шайба — тоже кукла (позиция из снапшота).
	if _puck and not _puck.freeze:
		_puck.freeze = true
