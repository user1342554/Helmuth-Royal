extends Node
## Network Manager - Steam lobby and P2P networking + LAN support
## Uses Steam lobbies for matchmaking and P2P for game data
## Also supports direct LAN connections via ENet for local testing

signal hosting_started(info: Dictionary)
signal hosting_failed(reason: String)
signal connection_succeeded()
signal connection_failed(reason: String)
signal player_joined(steam_id: int, player_name: String)
signal player_left(steam_id: int)
signal lobby_list_updated(lobbies: Array)
signal game_starting()

enum ConnectionState {
	DISCONNECTED,
	HOSTING,
	CONNECTING,
	CONNECTED
}

const DEFAULT_MAX_PLAYERS := 20
const DEFAULT_LAN_PORT := 7777
const CONNECTION_TIMEOUT := 5.0  # Seconds to wait before timing out

var state: ConnectionState = ConnectionState.DISCONNECTED
var is_host: bool = false
var is_lan_mode: bool = false
var host_info: Dictionary = {}
var players: Dictionary = {}  # steam_id/peer_id -> player_name
var _lan_peer: ENetMultiplayerPeer = null
var _next_lan_player_id: int = 1  # For generating fake IDs in LAN mode
var _connection_timer: float = 0.0
var _is_connecting: bool = false
var _player_nodes: Dictionary = {}  # peer_id -> player Node3D
var _local_player_node: Node3D = null


func _ready() -> void:
	# Connect to SteamManager signals
	SteamManager.lobby_created.connect(_on_lobby_created)
	SteamManager.lobby_create_failed.connect(_on_lobby_create_failed)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)
	SteamManager.lobby_list_received.connect(_on_lobby_list_received)
	SteamManager.lobby_player_joined.connect(_on_steam_player_joined)
	SteamManager.lobby_player_left.connect(_on_steam_player_left)
	SteamManager.p2p_packet_received.connect(_on_p2p_packet_received)
	print("[NetworkManager] Ready - p2p_packet_received signal connected: %s" % SteamManager.p2p_packet_received.is_connected(_on_p2p_packet_received))


func _process(delta: float) -> void:
	# Monitor connection timeout for LAN clients
	if _is_connecting and is_lan_mode and not is_host:
		_connection_timer += delta
		
		# Log connection state periodically
		if int(_connection_timer * 2) != int((_connection_timer - delta) * 2):
			_log_connection_state()
		
		# Check for timeout
		if _connection_timer >= CONNECTION_TIMEOUT:
			print("[NetworkManager] Connection timed out after %.1f seconds" % CONNECTION_TIMEOUT)
			_is_connecting = false
			_connection_timer = 0.0
			stop_networking()
			connection_failed.emit("Connection timed out")


func _log_connection_state() -> void:
	if _lan_peer == null:
		print("[NetworkManager] LAN peer is null!")
		return
	
	var status := _lan_peer.get_connection_status()
	var status_str := "Unknown"
	match status:
		MultiplayerPeer.CONNECTION_DISCONNECTED:
			status_str = "DISCONNECTED"
		MultiplayerPeer.CONNECTION_CONNECTING:
			status_str = "CONNECTING"
		MultiplayerPeer.CONNECTION_CONNECTED:
			status_str = "CONNECTED"
	
	print("[NetworkManager] Connection status: %s (timer: %.1fs)" % [status_str, _connection_timer])


## Host a game via Steam lobby
func host_game(lobby_name: String = "", max_players: int = DEFAULT_MAX_PLAYERS) -> void:
	if state != ConnectionState.DISCONNECTED:
		stop_networking()
	
	if not SteamManager.is_steam_initialized:
		hosting_failed.emit("Steam is not initialized")
		return
	
	is_host = true
	state = ConnectionState.HOSTING
	
	if lobby_name.is_empty():
		lobby_name = SteamManager.steam_name + "'s Game"
	
	SteamManager.create_lobby(lobby_name, max_players, SteamManager.LobbyType.PUBLIC)


## Join a game via Steam lobby
func join_lobby(lobby_id: int) -> void:
	if state != ConnectionState.DISCONNECTED:
		stop_networking()
	
	if not SteamManager.is_steam_initialized:
		connection_failed.emit("Steam is not initialized")
		return
	
	is_host = false
	state = ConnectionState.CONNECTING
	
	SteamManager.join_lobby(lobby_id)


## Request list of available lobbies
func refresh_lobby_list() -> void:
	SteamManager.request_lobby_list()


## Host a LAN game using ENet
func host_lan_game(port: int = DEFAULT_LAN_PORT, max_players: int = DEFAULT_MAX_PLAYERS) -> void:
	print("[NetworkManager] host_lan_game() called - port: %d, max_players: %d" % [port, max_players])
	
	if state != ConnectionState.DISCONNECTED:
		print("[NetworkManager] Already connected, stopping existing connection...")
		stop_networking()
	
	is_lan_mode = true
	is_host = true
	state = ConnectionState.HOSTING
	
	_lan_peer = ENetMultiplayerPeer.new()
	var error := _lan_peer.create_server(port, max_players)
	
	if error != OK:
		print("[NetworkManager] ERROR: Failed to create server - error code: %d" % error)
		state = ConnectionState.DISCONNECTED
		is_host = false
		is_lan_mode = false
		hosting_failed.emit("Failed to create LAN server (Error: %d)" % error)
		return
	
	print("[NetworkManager] Server created successfully on port %d" % port)
	multiplayer.multiplayer_peer = _lan_peer
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_lan_peer_connected)
	multiplayer.peer_disconnected.connect(_on_lan_peer_disconnected)
	print("[NetworkManager] Multiplayer signals connected")
	
	# Generate a local player ID (use 1 for host)
	var local_id := 1
	var local_name := "Host"
	if SteamManager.is_steam_initialized:
		local_name = SteamManager.steam_name
	
	host_info = {
		"lobby_id": 0,
		"lobby_name": local_name + "'s LAN Game",
		"max_players": max_players,
		"host_name": local_name,
		"port": port,
		"ip": get_local_ip()
	}
	
	# Add self to players
	players[local_id] = local_name
	GameState.add_player(local_id, local_name)
	
	print("[NetworkManager] LAN server ready - IP: %s:%d" % [host_info.ip, port])
	hosting_started.emit(host_info)


## Join a LAN game using ENet
func join_lan_game(ip: String, port: int = DEFAULT_LAN_PORT) -> void:
	print("[NetworkManager] join_lan_game() called - ip: %s, port: %d" % [ip, port])
	
	if state != ConnectionState.DISCONNECTED:
		print("[NetworkManager] Already connected, stopping existing connection...")
		stop_networking()
	
	is_lan_mode = true
	is_host = false
	state = ConnectionState.CONNECTING
	_is_connecting = true
	_connection_timer = 0.0
	
	_lan_peer = ENetMultiplayerPeer.new()
	var error := _lan_peer.create_client(ip, port)
	
	if error != OK:
		print("[NetworkManager] ERROR: Failed to create client - error code: %d" % error)
		state = ConnectionState.DISCONNECTED
		is_lan_mode = false
		_is_connecting = false
		connection_failed.emit("Failed to connect to %s:%d (Error: %d)" % [ip, port, error])
		return
	
	print("[NetworkManager] Client created, attempting to connect to %s:%d..." % [ip, port])
	multiplayer.multiplayer_peer = _lan_peer
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_lan_peer_connected)
	multiplayer.peer_disconnected.connect(_on_lan_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_lan_connected_to_server)
	multiplayer.connection_failed.connect(_on_lan_connection_failed)
	print("[NetworkManager] Multiplayer signals connected, waiting for connection...")


## Get local IP address for LAN hosting
func get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		# Prefer IPv4 addresses that aren't localhost
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	# Fallback to first non-localhost address
	for addr in addresses:
		if addr != "127.0.0.1" and not addr.contains(":"):
			return addr
	return "127.0.0.1"


## Stop all networking
func stop_networking() -> void:
	print("[NetworkManager] stop_networking() called")
	_is_connecting = false
	_connection_timer = 0.0
	
	if is_lan_mode:
		# Disconnect LAN signals
		if multiplayer.peer_connected.is_connected(_on_lan_peer_connected):
			multiplayer.peer_connected.disconnect(_on_lan_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_lan_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_lan_peer_disconnected)
		if multiplayer.connected_to_server.is_connected(_on_lan_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_lan_connected_to_server)
		if multiplayer.connection_failed.is_connected(_on_lan_connection_failed):
			multiplayer.connection_failed.disconnect(_on_lan_connection_failed)
		
		if _lan_peer != null:
			_lan_peer.close()
			_lan_peer = null
		multiplayer.multiplayer_peer = null
	else:
		SteamManager.leave_lobby()
	
	state = ConnectionState.DISCONNECTED
	is_host = false
	is_lan_mode = false
	host_info = {}
	players.clear()
	_player_nodes.clear()
	_local_player_node = null
	
	GameState.reset()


## Start the actual game (host only)
func start_game() -> void:
	print("[NetworkManager] start_game() called - is_host: %s, is_lan_mode: %s" % [is_host, is_lan_mode])
	
	if not is_host:
		print("[NetworkManager] Not host, ignoring start_game()")
		return
	
	if is_lan_mode:
		# Notify all LAN clients to start
		print("[NetworkManager] Sending start game RPC to all clients...")
		_rpc_start_game.rpc()
	else:
		SteamManager.set_game_started(true)
		# Send start message to all players
		var start_msg := _make_packet("START", {})
		print("[NetworkManager] Sending START packet to %d lobby members: %s" % [SteamManager.lobby_members.size(), SteamManager.lobby_members])
		SteamManager.send_p2p_packet_all(start_msg)
	
	# Signal triggers scene change in main_menu for host too
	game_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_start_game() -> void:
	print("[NetworkManager] _rpc_start_game() received from host!")
	# Signal triggers scene change in main_menu
	game_starting.emit()


## Get current player count
func get_player_count() -> int:
	return players.size()


## Get max player count
func get_max_players() -> int:
	return host_info.get("max_players", DEFAULT_MAX_PLAYERS)


## Check if connected
func is_connected_to_game() -> bool:
	return state == ConnectionState.HOSTING or state == ConnectionState.CONNECTED


## Create a network packet
func _make_packet(msg_type: String, data: Dictionary) -> PackedByteArray:
	var packet := {
		"type": msg_type,
		"data": data,
		"sender": SteamManager.steam_id
	}
	return var_to_bytes(packet)


## Parse a network packet
func _parse_packet(raw: PackedByteArray) -> Dictionary:
	var packet = bytes_to_var(raw)
	if packet is Dictionary:
		return packet
	return {}


func _go_to_game() -> void:
	GameState.set_match_phase(GameState.MatchPhase.STARTING)
	get_tree().change_scene_to_file("res://scenes/game/world.tscn")


# --- Steam Lobby Callbacks ---

func _on_lobby_created(lobby_id: int) -> void:
	host_info = {
		"lobby_id": lobby_id,
		"lobby_name": Steam.getLobbyData(lobby_id, "name"),
		"max_players": Steam.getLobbyData(lobby_id, "max_players").to_int(),
		"host_name": SteamManager.steam_name
	}
	
	# Add self to players
	players[SteamManager.steam_id] = SteamManager.steam_name
	GameState.add_player(SteamManager.steam_id, SteamManager.steam_name)
	
	hosting_started.emit(host_info)


func _on_lobby_create_failed(reason: String) -> void:
	state = ConnectionState.DISCONNECTED
	is_host = false
	hosting_failed.emit(reason)


func _on_lobby_joined(_lobby_id: int) -> void:
	if is_host:
		return
	
	# We joined as a client
	state = ConnectionState.CONNECTED
	
	# Add all current lobby members to players list
	for member in SteamManager.get_lobby_members():
		players[member.steam_id] = member.name
		GameState.add_player(member.steam_id, member.name)
	
	connection_succeeded.emit()


func _on_lobby_join_failed(reason: String) -> void:
	state = ConnectionState.DISCONNECTED
	connection_failed.emit(reason)


func _on_lobby_list_received(lobbies: Array) -> void:
	lobby_list_updated.emit(lobbies)


func _on_steam_player_joined(steam_id: int) -> void:
	var player_name := Steam.getFriendPersonaName(steam_id)
	players[steam_id] = player_name
	GameState.add_player(steam_id, player_name)
	player_joined.emit(steam_id, player_name)


func _on_steam_player_left(steam_id: int) -> void:
	players.erase(steam_id)
	GameState.remove_player(steam_id)
	player_left.emit(steam_id)


func _on_p2p_packet_received(data: PackedByteArray, sender_id: int) -> void:
	# Check for voice packet first (raw binary with magic number)
	if data.size() >= 8:
		var magic = data.decode_u32(0)
		if magic == 0x564F4943:  # "VOIC" magic number
			_handle_steam_voice_packet(data, sender_id)
			return
	
	# Regular game packet (var_to_bytes format)
	var packet := _parse_packet(data)
	if packet.is_empty():
		return
	
	var msg_type: String = packet.get("type", "")
	
	match msg_type:
		"START":
			# Host says to start the game - signal triggers scene change in main_menu
			print("[NetworkManager] Received START packet from host! Emitting game_starting signal...")
			game_starting.emit()
		"HELLO":
			# New player saying hello - if we're host, accept them
			if is_host:
				print("[NetworkManager] Received HELLO from player: %d" % sender_id)
				SteamManager.accept_p2p_session(sender_id)
		"POS":
			# Position update from another player
			_handle_position_update(sender_id, packet.get("data", {}))


# --- LAN Callbacks ---

func _on_lan_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] _on_lan_peer_connected() - peer_id: %d, is_host: %s" % [peer_id, is_host])
	
	if is_host:
		# A new player connected
		var player_name := "Player %d" % peer_id
		players[peer_id] = player_name
		GameState.add_player(peer_id, player_name)
		player_joined.emit(peer_id, player_name)
		print("[NetworkManager] Host: Player %d added to game" % peer_id)
		
		# Notify the new player about existing players
		for existing_id in players:
			_rpc_player_info.rpc_id(peer_id, existing_id, players[existing_id])


func _on_lan_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] _on_lan_peer_disconnected() - peer_id: %d" % peer_id)
	if players.has(peer_id):
		players.erase(peer_id)
		GameState.remove_player(peer_id)
		player_left.emit(peer_id)


func _on_lan_connected_to_server() -> void:
	print("[NetworkManager] _on_lan_connected_to_server() - SUCCESS! Connected to server!")
	
	_is_connecting = false
	_connection_timer = 0.0
	state = ConnectionState.CONNECTED
	
	# Add self to players
	var my_id := multiplayer.get_unique_id()
	var my_name := "Player %d" % my_id
	if SteamManager.is_steam_initialized:
		my_name = SteamManager.steam_name
	
	players[my_id] = my_name
	GameState.add_player(my_id, my_name)
	print("[NetworkManager] Client: Added self as %s (ID: %d)" % [my_name, my_id])
	
	# Tell the server our name
	_rpc_announce_player.rpc_id(1, my_id, my_name)
	
	connection_succeeded.emit()
	print("[NetworkManager] connection_succeeded signal emitted")


func _on_lan_connection_failed() -> void:
	print("[NetworkManager] _on_lan_connection_failed() - Connection failed!")
	
	_is_connecting = false
	_connection_timer = 0.0
	state = ConnectionState.DISCONNECTED
	is_lan_mode = false
	connection_failed.emit("Connection to LAN server failed")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_announce_player(peer_id: int, player_name: String) -> void:
	if is_host:
		players[peer_id] = player_name
		GameState.add_player(peer_id, player_name)
		player_joined.emit(peer_id, player_name)
		
		# Broadcast to all other players
		_rpc_player_info.rpc(peer_id, player_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_player_info(peer_id: int, player_name: String) -> void:
	if not players.has(peer_id):
		players[peer_id] = player_name
		GameState.add_player(peer_id, player_name)


# --- Position Sync (Steam Mode) ---

func _handle_position_update(sender_id: int, data: Dictionary) -> void:
	# Find the player node for this sender
	var player_node = _player_nodes.get(sender_id)
	if player_node and is_instance_valid(player_node) and player_node.has_method("apply_network_state"):
		player_node.apply_network_state(data)


# --- Player Node Tracking ---

## Register a spawned player node
func register_player_node(peer_id: int, node: Node3D, is_local: bool = false) -> void:
	_player_nodes[peer_id] = node
	if is_local:
		_local_player_node = node


## Unregister a player node
func unregister_player_node(peer_id: int) -> void:
	_player_nodes.erase(peer_id)
	if _local_player_node and _local_player_node.name == str(peer_id):
		_local_player_node = null


## Get the local player node
func get_local_player() -> Node3D:
	return _local_player_node


## Get a player node by peer ID
func get_player(peer_id: int) -> Node3D:
	return _player_nodes.get(peer_id, null)


# --- Voice Networking ---

const VOICE_CHANNEL := 1  # Separate channel from gameplay (channel 0)

## Send voice packet to host (clients call this)
func send_voice_packet(data: PackedByteArray) -> void:
	if state != ConnectionState.HOSTING and state != ConnectionState.CONNECTED:
		return
	
	if is_lan_mode:
		if is_host:
			# Host sending voice - relay to others via proximity
			var my_id = multiplayer.get_unique_id()
			_relay_voice_packet(my_id, data)
		else:
			# Client sending to host
			_rpc_voice_to_host.rpc_id(1, data)
	else:
		# Steam mode: use UnreliableNoDelay for voice (Steam docs recommend this)
		# Note: Steam P2P voice packets go to the host who then relays
		if is_host:
			var my_id = SteamManager.steam_id
			_relay_voice_packet(my_id, data)
		else:
			# Get host steam ID from lobby owner
			var host_steam_id = SteamManager.get_lobby_owner_id()
			if host_steam_id > 0:
				# Use unreliable no delay - Steam recommends for voice
				SteamManager.send_p2p_packet(host_steam_id, data, 0)  # 0 = unreliable


## RPC: Client sends voice to host (LAN mode)
@rpc("any_peer", "call_remote", "unreliable_ordered", VOICE_CHANNEL)
func _rpc_voice_to_host(data: PackedByteArray) -> void:
	if not is_host:
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	_relay_voice_packet(sender_id, data)


## Host relays voice packet to nearby listeners
func _relay_voice_packet(sender_id: int, data: PackedByteArray) -> void:
	if not is_host:
		return
	
	# Get cached listener list from VoiceManager (computed at 10 Hz, not per-packet)
	var listeners = VoiceManager.get_listeners_for(sender_id)
	var my_id = multiplayer.get_unique_id() if is_lan_mode else SteamManager.steam_id
	
	for listener_id in listeners:
		if listener_id == my_id:
			# Host is a listener — call directly, not via RPC (listen-server gotcha)
			VoiceManager.receive_voice_packet(sender_id, data)
		else:
			if is_lan_mode:
				_rpc_voice_from_player.rpc_id(listener_id, sender_id, data)
			else:
				# Steam P2P to listener
				SteamManager.send_p2p_packet(listener_id, _make_voice_packet(sender_id, data), 0)


## RPC: Host sends voice to client (LAN mode)
@rpc("authority", "call_remote", "unreliable_ordered", VOICE_CHANNEL)
func _rpc_voice_from_player(sender_id: int, data: PackedByteArray) -> void:
	VoiceManager.receive_voice_packet(sender_id, data)


## Create a voice packet for Steam P2P (includes sender ID)
func _make_voice_packet(sender_id: int, opus_data: PackedByteArray) -> PackedByteArray:
	var packet = PackedByteArray()
	packet.resize(8 + opus_data.size())  # 8 bytes for header (type + sender)
	packet.encode_u32(0, 0x564F4943)  # "VOIC" magic number
	packet.encode_u32(4, sender_id)
	for i in opus_data.size():
		packet[8 + i] = opus_data[i]
	return packet


## Handle incoming Steam P2P voice packets
func _handle_steam_voice_packet(data: PackedByteArray, from_steam_id: int) -> void:
	if data.size() < 8:
		return
	
	# Check magic number
	var magic = data.decode_u32(0)
	if magic != 0x564F4943:  # "VOIC"
		return
	
	var sender_id = data.decode_u32(4)
	var opus_data = data.slice(8)
	
	if is_host:
		# Host received voice from client - relay to listeners
		_relay_voice_packet(sender_id, opus_data)
	else:
		# Client received voice from host relay
		VoiceManager.receive_voice_packet(sender_id, opus_data)
