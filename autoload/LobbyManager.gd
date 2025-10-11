extends Node

const BROADCAST_PORT_BASE = 1910
const BROADCAST_INTERVAL = 1.0
const HEARTBEAT_INTERVAL = 15.0
const MASTER_SERVER_URL = "https://drfantasysigmakoop-lobbies.glitch.me"
var use_internet_lobbies := true

const GAME_VERSION = "1.0.0"
const GAME_REGION = "EU"

var my_broadcast_port: int

class LobbyInfo:
	var lobby_id: String
	var lobby_name: String
	var host_name: String
	var host_ip: String
	var port: int
	var max_players: int
	var current_players: int
	var has_password: bool
	var last_seen: float
	var ping: int = 0
	var version: String = GAME_VERSION
	var region: String = GAME_REGION
	
	func _init(name: String, host: String, ip: String, p: int, max_p: int, curr_p: int, pwd: bool, id: String = ""):
		lobby_name = name
		host_name = host
		host_ip = ip
		port = p
		max_players = max_p
		current_players = curr_p
		has_password = pwd
		lobby_id = id if not id.is_empty() else _generate_id()
		last_seen = Time.get_ticks_msec() / 1000.0
	
	func _generate_id() -> String:
		return str(Time.get_ticks_msec()) + "_" + str(randi())

var my_lobby: LobbyInfo = null
var discovered_lobbies := {}  # ip -> LobbyInfo
var lobby_password := ""
var lobby_password_hash := ""

var broadcast_socket: PacketPeerUDP
var listen_socket: PacketPeerUDP
var broadcast_timer := 0.0
var heartbeat_timer := 0.0

# Performance optimization
var _cleanup_timer := 0.0
var _cleanup_interval := 1.0
var _cached_json_parser := JSON.new()
var _last_broadcast_data := ""

# Password challenge
var pending_nonce: PackedByteArray
var pending_lobby: LobbyInfo

signal lobby_list_updated
signal lobby_joined
signal lobby_join_failed(reason: String)

func _ready():
	# Find available port for listening (for multiple local instances)
	listen_socket = PacketPeerUDP.new()
	my_broadcast_port = BROADCAST_PORT_BASE
	var bind_result = ERR_CANT_CREATE
	
	# Try up to 10 ports
	for i in range(10):
		bind_result = listen_socket.bind(my_broadcast_port + i)
		if bind_result == OK:
			my_broadcast_port += i
			break
	
	if bind_result != OK:
		push_error("Failed to bind UDP socket: %d" % bind_result)
		return
	
	# Setup broadcast socket - broadcast to all potential ports
	broadcast_socket = PacketPeerUDP.new()
	broadcast_socket.set_broadcast_enabled(true)
	
	print("LobbyManager initialized - listening on port ", my_broadcast_port)

func _process(delta):
	# Broadcast own lobby if hosting
	if my_lobby:
		broadcast_timer += delta
		if broadcast_timer >= BROADCAST_INTERVAL:
			broadcast_timer = 0.0
			broadcast_lobby()
		
		# Heartbeat to master server
		heartbeat_timer += delta
		if heartbeat_timer >= HEARTBEAT_INTERVAL:
			heartbeat_timer = 0.0
			if use_internet_lobbies and NetworkManager.upnp and NetworkManager.upnp.query_external_address():
				_send_heartbeat()
	
	# Listen for LAN broadcasts
	while listen_socket.get_available_packet_count() > 0:
		var packet = listen_socket.get_packet()
		var sender_ip = listen_socket.get_packet_ip()
		
		var data = packet.get_string_from_utf8()
		parse_lobby_broadcast(data, sender_ip)
	
	# Cleanup
	_cleanup_timer += delta
	if _cleanup_timer >= _cleanup_interval:
		_cleanup_timer = 0.0
		cleanup_old_lobbies()

func create_lobby(lobby_name: String, max_players: int, password: String, use_upnp: bool = true) -> bool:
	my_lobby = LobbyInfo.new(
		lobby_name,
		OS.get_environment("USERNAME") if OS.get_environment("USERNAME") else "Host",
		get_local_ip(),
		NetworkManager.PORT,
		max_players,
		1,
		not password.is_empty()
	)
	lobby_password = password
	if not password.is_empty():
		lobby_password_hash = password.sha256_text()
	
	print("Lobby creating: ", lobby_name)
	var success = await NetworkManager.host_game(use_upnp)
	
	if success:
		print("Lobby created successfully!")
		
		# Register with master server
		if use_internet_lobbies:
			_register_with_master_server()
		
		get_tree().change_scene_to_file("res://ui/LobbyWaitingRoom.tscn")
	else:
		print("Lobby creation failed!")
		my_lobby = null
	
	return success

func join_lobby(lobby: LobbyInfo, password: String = "") -> bool:
	if lobby.has_password and password.is_empty():
		lobby_join_failed.emit("Password required")
		return false
	
	pending_lobby = lobby
	lobby_password = password
	
	var success = NetworkManager.join_game(lobby.host_ip)
	if success:
		if lobby.has_password:
			await _perform_password_challenge()
		else:
			lobby_joined.emit()
	else:
		lobby_join_failed.emit("Connection failed")
	
	return success

func broadcast_lobby():
	if not my_lobby:
		return
	
	var current_players = NetworkManager.players.size()
	my_lobby.current_players = current_players
	
	var data = {
		"lobby_id": my_lobby.lobby_id,
		"lobby_name": my_lobby.lobby_name,
		"host_name": my_lobby.host_name,
		"port": my_lobby.port,
		"max_players": my_lobby.max_players,
		"current_players": current_players,
		"has_password": my_lobby.has_password,
		"version": my_lobby.version,
		"region": my_lobby.region
	}
	
	var json = JSON.stringify(data)
	_last_broadcast_data = json
	
	# Broadcast to multiple ports for local testing
	for i in range(10):
		broadcast_socket.set_dest_address("255.255.255.255", BROADCAST_PORT_BASE + i)
		broadcast_socket.put_packet(json.to_utf8_buffer())

func parse_lobby_broadcast(data: String, sender_ip: String):
	var error = _cached_json_parser.parse(data)
	
	if error != OK:
		print("Failed to parse lobby broadcast from ", sender_ip)
		return
	
	var lobby_data = _cached_json_parser.data
	if not lobby_data is Dictionary:
		return
	
	# Skip our own lobby broadcasts
	var lobby_id = lobby_data.get("lobby_id", "")
	if my_lobby and lobby_id == my_lobby.lobby_id:
		return
	
	# Filter by version
	if lobby_data.get("version", "") != GAME_VERSION:
		return
	
	var lobby = LobbyInfo.new(
		lobby_data.get("lobby_name", "Unknown"),
		lobby_data.get("host_name", "Host"),
		sender_ip,
		lobby_data.get("port", NetworkManager.PORT),
		lobby_data.get("max_players", 8),
		lobby_data.get("current_players", 0),
		lobby_data.get("has_password", false),
		lobby_id
	)
	lobby.version = lobby_data.get("version", GAME_VERSION)
	lobby.region = lobby_data.get("region", GAME_REGION)
	
	measure_ping(lobby)
	
	# Use lobby_id as key instead of IP to support multiple instances on same machine
	var key = lobby.lobby_id if not lobby.lobby_id.is_empty() else sender_ip
	discovered_lobbies[key] = lobby
	lobby_list_updated.emit()
	
	print("Lobby discovered: ", lobby.lobby_name, " from ", sender_ip)

func measure_ping(lobby: LobbyInfo):
	# Simple ping estimation (not actual ICMP ping)
	# In production, you'd want proper ping measurement
	lobby.ping = randi_range(10, 100)

func cleanup_old_lobbies():
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	
	# Optimized: Use Array instead of multiple appends
	for ip in discovered_lobbies.keys():
		var lobby = discovered_lobbies[ip]
		if current_time - lobby.last_seen > 5.0:  # 5 seconds timeout
			to_remove.append(ip)
	
	# Only emit signal if we actually removed something
	if to_remove.size() > 0:
		for ip in to_remove:
			discovered_lobbies.erase(ip)
		lobby_list_updated.emit()

func get_lobbies() -> Array:
	return discovered_lobbies.values()

func stop_hosting():
	# Unregister from master server
	if use_internet_lobbies and my_lobby:
		_unregister_from_master_server()
	
	my_lobby = null
	lobby_password = ""

# Internet Lobby System
func _register_with_master_server():
	if not my_lobby:
		return
	
	var external_ip = ""
	if NetworkManager.upnp:
		external_ip = NetworkManager.upnp.query_external_address()
	
	if external_ip.is_empty():
		return
	
	var http = HTTPRequest.new()
	add_child(http)
	
	var data = {
		"id": my_lobby.lobby_id,
		"name": my_lobby.lobby_name,
		"region": my_lobby.region,
		"version": my_lobby.version,
		"host_ip": external_ip,
		"port": NetworkManager.PORT,
		"max": my_lobby.max_players,
		"cur": my_lobby.current_players,
		"has_password": my_lobby.has_password
	}
	
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	http.request(MASTER_SERVER_URL + "/lobbies", headers, HTTPClient.METHOD_POST, json)
	
	await http.request_completed
	http.queue_free()

func _send_heartbeat():
	if not my_lobby or not NetworkManager.upnp:
		return
	
	var external_ip = NetworkManager.upnp.query_external_address()
	if external_ip.is_empty():
		return
	
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = MASTER_SERVER_URL + "/lobbies/" + my_lobby.lobby_id + "/heartbeat"
	var data = {"cur": NetworkManager.players.size()}
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	http.request(url, headers, HTTPClient.METHOD_POST, json)
	
	await http.request_completed
	http.queue_free()

func _unregister_from_master_server():
	if not my_lobby:
		return
	
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = MASTER_SERVER_URL + "/lobbies/" + my_lobby.lobby_id
	http.request(url, [], HTTPClient.METHOD_DELETE)
	
	await http.request_completed
	http.queue_free()

func fetch_internet_lobbies():
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = MASTER_SERVER_URL + "/lobbies?version=" + GAME_VERSION + "&region=" + GAME_REGION + "&has_space=true"
	http.request(url)
	var result = await http.request_completed
	
	if result[1] == 200:
		var json = JSON.new()
		var error = json.parse(result[3].get_string_from_utf8())
		
		if error == OK and json.data is Array:
			for lobby_data in json.data:
				# Filter by version and available space
				if lobby_data.get("version", "") != GAME_VERSION:
					continue
				if lobby_data.get("cur", 0) >= lobby_data.get("max", 0):
					continue
				
				var lobby = LobbyInfo.new(
					lobby_data.get("name", "Unknown"),
					lobby_data.get("host_name", "Host"),
					lobby_data.get("host_ip", ""),
					lobby_data.get("port", NetworkManager.PORT),
					lobby_data.get("max", 8),
					lobby_data.get("cur", 0),
					lobby_data.get("has_password", false),
					lobby_data.get("id", "")
				)
				lobby.version = lobby_data.get("version", GAME_VERSION)
				lobby.region = lobby_data.get("region", GAME_REGION)
				
				# Measure RTT
				await _measure_rtt(lobby)
				
				discovered_lobbies[lobby.host_ip] = lobby
			
			# Sort by ping
			var lobby_list = discovered_lobbies.values()
			lobby_list.sort_custom(func(a, b): return a.ping < b.ping)
			
			lobby_list_updated.emit()
	
	http.queue_free()

func get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		# Skip localhost and IPv6
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	
	return "127.0.0.1"

func validate_player_password(password: String) -> bool:
	if not my_lobby or not my_lobby.has_password:
		return true
	
	return password == lobby_password

# Password Challenge-Response
func _perform_password_challenge():
	# Wait for nonce from host
	await get_tree().create_timer(0.5).timeout
	
	if pending_nonce.is_empty():
		lobby_join_failed.emit("Challenge timeout")
		return
	
	# Compute HMAC
	var hmac = _compute_hmac(pending_nonce, lobby_password)
	
	# Send response to host
	_send_password_response.rpc_id(1, hmac)
	
	# Wait for validation
	await get_tree().create_timer(2.0).timeout

@rpc("any_peer", "call_remote", "reliable")
func _receive_password_challenge(nonce: PackedByteArray):
	pending_nonce = nonce

@rpc("any_peer", "call_remote", "reliable")
func _send_password_response(hmac: PackedByteArray):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Validate HMAC
	var expected_hmac = _compute_hmac(pending_nonce, lobby_password)
	
	if hmac == expected_hmac:
		print("Password validated for peer ", sender_id)
		_password_accepted.rpc_id(sender_id)
	else:
		print("Password rejected for peer ", sender_id)
		_password_rejected.rpc_id(sender_id)

@rpc("authority", "call_remote", "reliable")
func _password_accepted():
	lobby_joined.emit()

@rpc("authority", "call_remote", "reliable")
func _password_rejected():
	lobby_join_failed.emit("Invalid password")
	NetworkManager.disconnect_from_game()

func _compute_hmac(nonce: PackedByteArray, password: String) -> PackedByteArray:
	var ctx = HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, password.to_utf8_buffer())
	ctx.update(nonce)
	return ctx.finish()

func _generate_nonce() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(16)

func _measure_rtt(lobby: LobbyInfo):
	var start_time = Time.get_ticks_msec()
	
	var tcp = StreamPeerTCP.new()
	tcp.connect_to_host(lobby.host_ip, lobby.port)
	
	var timeout = 2.0
	var elapsed = 0.0
	
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		lobby.ping = int(Time.get_ticks_msec() - start_time)
		tcp.disconnect_from_host()
	else:
		lobby.ping = 9999
	
	tcp = null
