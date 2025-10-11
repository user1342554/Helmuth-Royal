extends Node

const PORT = 1909
const MAX_PLAYERS = 8

var players = {}  # peer_id -> player_node
var player_scene = preload("res://player/Player.tscn")
var upnp: UPNP

# Performance optimization: Cache for player lookups
var _player_lookup_cache := {}
var _cache_dirty := false

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal upnp_completed(success: bool, external_ip: String)

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(use_upnp: bool = true) -> bool:
	print("NetworkManager: Creating server...")
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return false
	
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Server started on port ", PORT)
	
	# UPNP im Hintergrund
	if use_upnp:
		print("NetworkManager: Starting UPNP...")
		_setup_upnp()
	
	print("NetworkManager: Server ready - waiting in lobby")
	return true

func start_game():
	# Called by host to start the game
	if not multiplayer.is_server():
		print("Only host can start game!")
		return
	
	print("NetworkManager: Host starting game for all players...")
	
	# Clear any existing players from lobby
	for peer_id in players.keys():
		var player = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
	players.clear()
	_invalidate_cache()
	
	# Tell all clients to load game
	_load_game_scene.rpc()
	
	# Load for host
	get_tree().change_scene_to_file("res://world/DreamTest.tscn")
	await get_tree().create_timer(1.5).timeout  # Wait longer for all clients to load
	
	# Get all connected peers (including host)
	var all_peers = [multiplayer.get_unique_id()]
	all_peers.append_array(multiplayer.get_peers())
	
	print("NetworkManager: Spawning players: ", all_peers)
	
	# Spawn all players on server
	for peer_id in all_peers:
		spawn_player(peer_id)
	
	# Tell all clients to spawn all players
	_spawn_all_players.rpc(all_peers)
	
	print("NetworkManager: Game started!")

@rpc("authority", "call_remote", "reliable")
func _load_game_scene():
	print("NetworkManager: Loading game scene (called by host)...")
	
	# Clear any existing players
	for peer_id in players.keys():
		var player = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
	players.clear()
	_invalidate_cache()
	
	get_tree().change_scene_to_file("res://world/DreamTest.tscn")
	await get_tree().create_timer(0.5).timeout  # Wait for scene ready
	print("NetworkManager: Client scene loaded, ready for players")

@rpc("authority", "call_remote", "reliable")
func _spawn_all_players(peer_ids: Array):
	print("NetworkManager: Spawning all players on client: ", peer_ids)
	for peer_id in peer_ids:
		spawn_player(peer_id)

func _setup_upnp():
	# Run UPNP setup in separate thread to avoid blocking
	upnp = UPNP.new()
	
	print("Discovering UPNP devices...")
	var discover_result = upnp.discover(2000, 2, "InternetGatewayDevice")  # Timeout 2s, 2 tries
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		push_warning("UPNP discovery failed: " + str(discover_result))
		upnp_completed.emit(false, "")
		return
	
	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result_udp = upnp.add_port_mapping(PORT, PORT, "DrFantasySigmakoop", "UDP")
		var map_result_tcp = upnp.add_port_mapping(PORT, PORT, "DrFantasySigmakoop", "TCP")
		
		if map_result_udp == UPNP.UPNP_RESULT_SUCCESS or map_result_tcp == UPNP.UPNP_RESULT_SUCCESS:
			var external_ip = upnp.query_external_address()
			print("UPNP Success! Your external IP is: ", external_ip)
			print("Share this IP with your friends: ", external_ip)
			upnp_completed.emit(true, external_ip)
		else:
			push_warning("UPNP port mapping failed")
			upnp_completed.emit(false, "")
	else:
		push_warning("No valid UPNP gateway found")
		upnp_completed.emit(false, "")

func join_game(address: String) -> bool:
	print("NetworkManager: Attempting to join ", address, ":", PORT)
	
	# Cleanup existing connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	
	if error != OK:
		push_error("Failed to create client: " + str(error))
		print("NetworkManager: Client creation failed with error: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Client created, connecting to ", address, ":", PORT)
	return true

func _on_player_connected(id: int):
	print("Player connected: ", id)
	
	# If we're the server, handle new player
	if multiplayer.is_server():
		# Password challenge if needed
		if LobbyManager.my_lobby and LobbyManager.my_lobby.has_password:
			var nonce = Crypto.new().generate_random_bytes(16)
			LobbyManager.pending_nonce = nonce
			LobbyManager._receive_password_challenge.rpc_id(id, nonce)
	
	# Emit signal for lobby to update player list
	player_connected.emit(id)

func _on_player_disconnected(id: int):
	print("Player disconnected: ", id)
	
	# Only cleanup if we're in game (not in lobby)
	if players.has(id):
		_unregister_player.rpc(id)
		_unregister_player(id)
	else:
		# Just emit signal for lobby
		player_disconnected.emit(id)

func _on_connected_to_server():
	print("NetworkManager: Successfully connected to server!")
	print("NetworkManager: My peer ID: ", multiplayer.get_unique_id())
	# Go to waiting room
	get_tree().change_scene_to_file("res://ui/LobbyWaitingRoom.tscn")

func _on_connection_failed():
	print("NetworkManager: Connection failed!")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	print("NetworkManager: Server disconnected!")
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

@rpc("authority", "call_remote", "reliable")
func _register_players_batch(peer_ids: Array):
	# Batch registration for better performance
	for peer_id in peer_ids:
		spawn_player(peer_id)
	
	# Setup voice players after all spawns
	await get_tree().create_timer(0.5).timeout
	for peer_id in peer_ids:
		if players.has(peer_id):
			VoiceChat.setup_voice_player(peer_id)

@rpc("authority", "call_remote", "reliable")
func _register_player(peer_id: int):
	print("Registering player: ", peer_id)
	spawn_player(peer_id)
	
	# Setup voice player after spawn
	await get_tree().create_timer(0.5).timeout
	if players.has(peer_id):
		VoiceChat.setup_voice_player(peer_id)

@rpc("authority", "call_remote", "reliable")
func _unregister_player(peer_id: int):
	print("Unregistering player: ", peer_id)
	
	# Cleanup voice
	VoiceChat.cleanup_voice_player(peer_id)
	
	if players.has(peer_id):
		var player = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)
		_invalidate_cache()
	player_disconnected.emit(peer_id)

func spawn_player(peer_id: int):
	if players.has(peer_id):
		print("Player ", peer_id, " already exists")
		return
	
	var world = get_tree().current_scene
	if not world or not world.is_inside_tree():
		print("ERROR: World not ready, waiting...")
		await get_tree().process_frame
		world = get_tree().current_scene
	
	if not world:
		print("ERROR: No world scene!")
		return
	
	var player = player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	
	# Add to scene first, then set position
	world.add_child(player, true)
	
	var spawn_hash = hash(peer_id)
	var spawn_pos = Vector3(
		(spawn_hash % 100 - 50) * 0.1,
		2, 
		((spawn_hash / 100) % 100 - 50) * 0.1
	)
	player.global_position = spawn_pos
	players[peer_id] = player
	_invalidate_cache()
	player_connected.emit(peer_id)
	print("Spawned player for peer ", peer_id)

func get_player(peer_id: int) -> Node:
	# Use cache for better performance
	if not _cache_dirty and _player_lookup_cache.has(peer_id):
		var cached = _player_lookup_cache[peer_id]
		if is_instance_valid(cached):
			return cached
	
	var player = players.get(peer_id)
	if is_instance_valid(player):
		_player_lookup_cache[peer_id] = player
		return player
	
	return null

func get_local_player() -> Node:
	# Cache local player for frequent access
	var local_id = multiplayer.get_unique_id()
	return get_player(local_id)

func _invalidate_cache():
	_cache_dirty = true
	_player_lookup_cache.clear()
	_cache_dirty = false

func disconnect_from_game():
	# Clean up UPNP
	if upnp:
		upnp.delete_port_mapping(PORT, "UDP")
		upnp.delete_port_mapping(PORT, "TCP")
		upnp = null
	
	# Stop hosting lobby
	LobbyManager.stop_hosting()
	
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	players.clear()
	get_tree().change_scene_to_file("res://ui/MultiplayerMenu.tscn")
