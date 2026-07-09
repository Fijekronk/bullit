extends Node
class_name LanDiscovery
## Автопоиск игр в локальной сети (без ввода IP). Хост раз в секунду шлёт
## UDP-broadcast-«маячок» (magic, порт игры, ник); клиент в меню слушает порт
## обнаружения и сообщает найденные хосты. Только LAN — через интернет/VPN
## по-прежнему по IP (broadcast за пределы подсети не уходит).

signal host_found(ip: String, port: int, nick: String)

const DISCOVERY_PORT := 9051    # порт «маячка» (игра — 9050)
const MAGIC := "BULLIT1"

var _udp: PacketPeerUDP
var _mode := ""                 # advertise / listen
var _port := 9050
var _nick := ""
var _accum := 1.0


## Хост: начать «маячить» в локальную сеть (вызывать из игры-хоста).
func advertise(game_port: int, nick: String) -> void:
	stop()
	_mode = "advertise"
	_port = game_port
	_nick = nick
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	set_process(true)


## Клиент: слушать маячки (вызывать из меню).
func listen() -> void:
	stop()
	_mode = "listen"
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LAN: не удалось слушать порт %d (%d)" % [DISCOVERY_PORT, err])
		_mode = ""
		return
	set_process(true)


func stop() -> void:
	if _udp:
		_udp.close()
		_udp = null
	_mode = ""
	set_process(false)


func _process(delta: float) -> void:
	if _mode == "advertise":
		_accum += delta
		if _accum >= 1.0:
			_accum = 0.0
			var msg := JSON.stringify({"m": MAGIC, "port": _port, "nick": _nick})
			_udp.put_packet(msg.to_utf8_buffer())
	elif _mode == "listen":
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var ip := _udp.get_packet_ip()
			var data = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(data) == TYPE_DICTIONARY and data.get("m", "") == MAGIC:
				host_found.emit(ip, int(data.get("port", 9050)), String(data.get("nick", "")))
