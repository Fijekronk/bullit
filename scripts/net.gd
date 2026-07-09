extends Node
class_name Net
## Сетевое ядро (сеть v1): ENet listen-server, строгий серверный авторитет.
## ПРАВИЛО: сервер решает — клиент показывает. Клиент шлёт ТОЛЬКО пакет ввода;
## сервер исполняет всю логику и рассылает состояние; клиент интерполирует.
##
## Этот узел — транспорт/протокол. Игровую сборку (спавн игроков, применение
## ввода к player.input на сервере, рассылка снапшотов) подключает NetGame,
## используя сигналы и RPC ниже. Тренировка (одиночный режим) сеть не трогает.

signal peer_joined(id: int, nick: String)
signal peer_left(id: int)
signal roles_changed(roles: Dictionary)      # id -> "field"/"goalie"
signal connected_to_host()
signal connection_failed()
signal disconnected()
signal snapshot_received(tick: int, data: Dictionary)
signal game_event(kind: String, data: Dictionary)   # гол/сброс/счёт/смена ролей

const DEFAULT_PORT := 9050
const MAX_PEERS := 2
const SNAPSHOT_HZ := 30.0

var is_server := false
var local_nick := "player"
var peers := {}          # id -> {"nick": String, "role": String}
var last_input_tick := 0 # сервер: номер последнего применённого тика ввода (F2)
var rtt_ms := 0.0        # клиент: оценка RTT (F2)

var _peer: ENetMultiplayerPeer
var _snap_accum := 0.0
var _in_bytes := 0       # статистика (F2): вх. байт/с
var _out_bytes := 0
var _stat_accum := 0.0
var in_bps := 0
var out_bps := 0
var last_snapshot_size := 0


func host(port: int = DEFAULT_PORT, nick: String = "host") -> bool:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("Хост: не удалось создать сервер на порту %d (%d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = _peer
	is_server = true
	local_nick = nick
	peers[1] = {"nick": nick, "role": "field"}
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("NET: хост на порту ", port)
	return true


func join(ip: String, port: int = DEFAULT_PORT, nick: String = "client") -> bool:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		push_error("Коннект: не удалось подключиться к %s:%d (%d)" % [ip, port, err])
		return false
	multiplayer.multiplayer_peer = _peer
	is_server = false
	local_nick = nick
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("NET: коннект к ", ip, ":", port)
	return true


func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	is_server = false
	peers.clear()


func set_role(id: int, role: String) -> void:
	# Роли меняет ТОЛЬКО сервер (авторитет), затем рассылает.
	if not is_server:
		return
	if peers.has(id):
		peers[id]["role"] = role
	_sync_roles.rpc(_roles_dict())
	roles_changed.emit(_roles_dict())


func _roles_dict() -> Dictionary:
	var r := {}
	for id in peers:
		r[id] = peers[id]["role"]
	return r


# --- Соединения ---
func _on_peer_connected(id: int) -> void:
	peers[id] = {"nick": "peer%d" % id, "role": "goalie"}
	# Запросить ник у нового пира и разослать текущий состав.
	_hello.rpc_id(id, local_nick)
	peer_joined.emit(id, peers[id]["nick"])
	_sync_roles.rpc(_roles_dict())


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	peer_left.emit(id)
	if is_server:
		_sync_roles.rpc(_roles_dict())


func _on_connected() -> void:
	connected_to_host.emit()
	_register.rpc_id(1, local_nick)


func _on_connect_failed() -> void:
	connection_failed.emit()
	shutdown()


func _on_server_disconnected() -> void:
	disconnected.emit()
	shutdown()


# --- RPC: рукопожатие/ники ---
@rpc("any_peer", "reliable")
func _register(nick: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id):
		peers[id]["nick"] = nick
	peer_joined.emit(id, nick)
	_sync_roles.rpc(_roles_dict())


@rpc("authority", "reliable")
func _hello(_host_nick: String) -> void:
	pass  # клиент узнаёт, что принят; состав придёт в _sync_roles


@rpc("authority", "reliable")
func _sync_roles(roles: Dictionary) -> void:
	for id in roles:
		if not peers.has(id):
			peers[id] = {"nick": "peer%d" % id, "role": roles[id]}
		else:
			peers[id]["role"] = roles[id]
	roles_changed.emit(roles)


# --- RPC: ввод клиента -> сервер (каждый тик) ---
## Клиент шлёт пакет ввода (unreliable_ordered — свежесть важнее доставки).
## Дискретные рёбра идут в том же пакете (see InputState.make_packet).
@rpc("any_peer", "unreliable_ordered")
func send_input(tick: int, packet: Dictionary) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	last_input_tick = tick
	# NetGame подключает применение к player.input соответствующего пира.
	input_received.emit(id, tick, packet)


signal input_received(id: int, tick: int, packet: Dictionary)


func push_input(tick: int, packet: Dictionary) -> void:
	if is_server:
		return
	send_input.rpc_id(1, tick, packet)
	_out_bytes += 24  # грубая оценка размера пакета ввода


# --- RPC: состояние сервер -> клиенты (30 Гц) ---
@rpc("authority", "unreliable_ordered")
func recv_snapshot(tick: int, data: Dictionary) -> void:
	last_snapshot_size = var_to_bytes(data).size()
	_in_bytes += last_snapshot_size
	snapshot_received.emit(tick, data)


## Сервер: разослать снапшот (NetGame формирует data). Дросселит до SNAPSHOT_HZ.
func broadcast_snapshot(tick: int, data: Dictionary, delta: float) -> bool:
	if not is_server:
		return false
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAPSHOT_HZ:
		return false
	_snap_accum = 0.0
	last_snapshot_size = var_to_bytes(data).size()
	_out_bytes += last_snapshot_size
	recv_snapshot.rpc(tick, data)
	return true


# --- RPC: игровые события сервер -> клиенты (гол/сброс/счёт) ---
@rpc("authority", "reliable")
func recv_event(kind: String, data: Dictionary) -> void:
	game_event.emit(kind, data)


## Сервер: разослать событие раунда (и продублировать локально у себя).
func broadcast_event(kind: String, data: Dictionary) -> void:
	if not is_server:
		return
	recv_event.rpc(kind, data)
	game_event.emit(kind, data)


func _process(delta: float) -> void:
	_stat_accum += delta
	if _stat_accum >= 1.0:
		in_bps = int(_in_bytes / _stat_accum)
		out_bps = int(_out_bytes / _stat_accum)
		_in_bytes = 0
		_out_bytes = 0
		_stat_accum = 0.0
	# Оценка RTT (клиент): ENet держит его на peer.
	if _peer and not is_server and multiplayer.multiplayer_peer == _peer:
		var p := _peer.get_peer(1)
		if p:
			rtt_ms = p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
