extends Node3D
## World - Game world container with player spawning and match management

@onready var players_container: Node3D = $Players
@onready var escape_menu: Control = $UI/EscapeMenu

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var spawn_positions: Array[Vector3] = []
var local_player: Node3D = null
var _menu_open: bool = false
var _spawned_players: Dictionary = {}  # peer_id -> player_node


func _ready() -> void:
	# Apply graphics settings to this scene's environment (must be done after scene loads)
	GraphicsSettings._apply_all_settings()
	
	_generate_spawn_positions()
	
	# Connect to game state signals
	GameState.player_added.connect(_on_player_added)
	GameState.player_removed.connect(_on_player_removed)
	GameState.player_updated.connect(_on_player_updated)
	GameState.match_phase_changed.connect(_on_match_phase_changed)
	
	# Connect escape menu signals
	escape_menu.menu_closed.connect(_on_escape_menu_closed)
	escape_menu.leave_game_requested.connect(_on_leave_game)
	
	# Capture mouse for FPS gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Enable FPS display (if setting is on)
	FPSDisplay.set_in_game(true)
	
	# Spawn all players
	_spawn_all_players()
	
	# Enable proximity voice chat
	VoiceManager.enable_voice()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_escape_menu()


func _toggle_escape_menu() -> void:
	_menu_open = not _menu_open
	
	if _menu_open:
		escape_menu.show_menu()
	else:
		escape_menu.hide_menu()


func _on_escape_menu_closed() -> void:
	_menu_open = false


func _on_leave_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FPSDisplay.set_in_game(false)
	VoiceManager.cleanup_all()
	NetworkManager.stop_networking()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _generate_spawn_positions() -> void:
	var radius := 5.0  # Small radius for testing - players spawn close together
	var count := 30
	
	for i in range(count):
		var angle := (float(i) / count) * TAU
		var pos := Vector3(
			cos(angle) * radius,
			2.0,
			sin(angle) * radius
		)
		spawn_positions.append(pos)


func _get_spawn_position(player_id: int) -> Vector3:
	var index: int = abs(player_id) % spawn_positions.size()
	return spawn_positions[index]


func _spawn_all_players() -> void:
	if NetworkManager.is_lan_mode:
		_spawn_lan_players()
	else:
		_spawn_steam_players()


func _spawn_steam_players() -> void:
	# Spawn a player for each lobby member
	var my_steam_id := SteamManager.steam_id
	print("[World] _spawn_steam_players() - my_steam_id: %d" % my_steam_id)
	
	# Get all players from GameState (populated when players joined the lobby)
	var all_steam_ids: Array = GameState.players.keys()
	print("[World] GameState players: %s" % [all_steam_ids])
	
	# Also check SteamManager lobby_members as backup
	if all_steam_ids.is_empty():
		all_steam_ids = SteamManager.lobby_members.duplicate()
		print("[World] Using lobby_members instead: %s" % [all_steam_ids])
	
	# Make sure we're in the list
	if my_steam_id not in all_steam_ids:
		all_steam_ids.append(my_steam_id)
	
	print("[World] All Steam IDs to spawn: %s" % [all_steam_ids])
	
	for steam_id in all_steam_ids:
		_spawn_player_for_steam_id(steam_id)
	
	print("[World] Total spawned players: %d" % _spawned_players.size())


func _spawn_player_for_steam_id(steam_id: int) -> void:
	if _spawned_players.has(steam_id):
		print("[World] Player %d already spawned, skipping" % steam_id)
		return
	
	var player := PLAYER_SCENE.instantiate()
	player.name = str(steam_id)
	var spawn_pos := _get_spawn_position(steam_id)
	player.position = spawn_pos
	
	players_container.add_child(player)
	_spawned_players[steam_id] = player
	
	var is_local := steam_id == SteamManager.steam_id
	print("[World] Spawned player %d at position %s (is_local: %s)" % [steam_id, spawn_pos, is_local])
	
	# Track local player reference
	if is_local:
		local_player = player
	
	# Register with NetworkManager for ViewCulling access
	NetworkManager.register_player_node(steam_id, player, is_local)
	
	# Setup voice playback for remote players
	if not is_local:
		VoiceManager.setup_voice_playback_for(steam_id, player)


func _spawn_lan_players() -> void:
	# Get our own peer ID
	var my_peer_id := multiplayer.get_unique_id()
	print("[World] _spawn_lan_players() - my_peer_id: %d, is_server: %s" % [my_peer_id, multiplayer.is_server()])
	
	# Spawn a player for each connected peer (including ourselves)
	var all_peers: Array[int] = [1]  # Always include host (peer ID 1)
	var connected_peers = multiplayer.get_peers()
	print("[World] multiplayer.get_peers() returned: %s" % [connected_peers])
	
	for peer_id in connected_peers:
		if peer_id not in all_peers:
			all_peers.append(peer_id)
	
	# Make sure we're in the list too
	if my_peer_id not in all_peers:
		all_peers.append(my_peer_id)
	
	print("[World] All peers to spawn: %s" % [all_peers])
	
	for peer_id in all_peers:
		_spawn_player_for_peer(peer_id)
	
	print("[World] Total spawned players: %d" % _spawned_players.size())


func _spawn_player_for_peer(peer_id: int) -> void:
	if _spawned_players.has(peer_id):
		print("[World] Player %d already spawned, skipping" % peer_id)
		return
	
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	var spawn_pos := _get_spawn_position(peer_id)
	player.position = spawn_pos
	
	# Set the multiplayer authority to the owning peer
	player.set_multiplayer_authority(peer_id)
	
	players_container.add_child(player)
	_spawned_players[peer_id] = player
	
	var is_local := peer_id == multiplayer.get_unique_id()
	print("[World] Spawned player %d at position %s (is_local: %s)" % [peer_id, spawn_pos, is_local])
	
	# Track local player reference
	if is_local:
		local_player = player
	
	# Register with NetworkManager for ViewCulling access
	NetworkManager.register_player_node(peer_id, player, is_local)
	
	# Setup voice playback for remote players
	if not is_local:
		VoiceManager.setup_voice_playback_for(peer_id, player)


# --- Signal Handlers ---

func _on_player_added(_steam_id: int, _player_data: Dictionary) -> void:
	pass  # UI updates handled elsewhere


func _on_player_removed(peer_id: int) -> void:
	# Cleanup voice playback for disconnected player
	VoiceManager.cleanup_voice_playback_for(peer_id)
	
	# Remove spawned player node if exists
	if _spawned_players.has(peer_id):
		var player_node = _spawned_players[peer_id]
		if is_instance_valid(player_node):
			player_node.queue_free()
		_spawned_players.erase(peer_id)
		NetworkManager.unregister_player_node(peer_id)


func _on_player_updated(_steam_id: int, _player_data: Dictionary) -> void:
	pass  # UI updates handled elsewhere


func _on_match_phase_changed(_phase: GameState.MatchPhase) -> void:
	pass  # UI updates handled elsewhere


func _on_leave_pressed() -> void:
	_on_leave_game()


func _exit_tree() -> void:
	# Ensure FPS display is hidden when leaving world
	FPSDisplay.set_in_game(false)
	
	# Cleanup voice system
	VoiceManager.cleanup_all()
