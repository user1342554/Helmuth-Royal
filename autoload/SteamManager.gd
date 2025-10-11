extends Node

# GodotSteam Wrapper (optional - graceful fallback)
var steam_initialized := false
var steam_id := 0
var steam_username := ""

# Lobby
var current_lobby_id := 0
var is_lobby_owner := false

signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_list_received(lobbies: Array)
signal lobby_data_updated
signal friend_invite_received(lobby_id: int)

func _ready():
	pass  # Steam disabled

func _init_steam():
	# Check if Steam singleton exists (GodotSteam plugin installed)
	if not Engine.has_singleton("Steam"):
		print("Steam not available - using LAN mode")
		return
	
	var Steam = Engine.get_singleton("Steam")
	var init_result = Steam.steamInitEx(true, 480)
	
	if init_result.status != 1:
		print("Steam init failed - using LAN mode")
		return
	
	steam_initialized = true
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
	
	# Callbacks
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(_on_join_requested)
	Steam.game_lobby_join_requested.connect(_on_game_lobby_join_requested)
	
	# SDR/Relay
	Steam.initRelayNetworkAccess()
	
	print("Steam initialized: ", steam_username, " (", steam_id, ")")

func _process(_delta):
	if steam_initialized and Engine.has_singleton("Steam"):
		Engine.get_singleton("Steam").run_callbacks()

# Create Lobby
func create_lobby(lobby_name: String, max_players: int, is_private := false):
	if not steam_initialized:
		return
	
	var Steam = Engine.get_singleton("Steam")
	var lobby_type = Steam.LOBBY_TYPE_PUBLIC
	if is_private:
		lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
	
	Steam.createLobby(lobby_type, max_players)
	print("Steam: Creating lobby...")

func _on_lobby_created(result: int, lobby_id: int):
	if result != 1:
		push_error("Failed to create lobby: " + str(result))
		return
	
	var Steam = Engine.get_singleton("Steam")
	current_lobby_id = lobby_id
	is_lobby_owner = true
	
	# Set metadata
	Steam.setLobbyData(lobby_id, "version", "1.0.0")
	Steam.setLobbyData(lobby_id, "mode", "coop")
	Steam.setLobbyData(lobby_id, "cur", "1")
	
	print("Steam: Lobby created: ", lobby_id)
	lobby_created.emit(lobby_id)

# Search Lobbies
func search_lobbies():
	if not steam_initialized:
		return
	
	var Steam = Engine.get_singleton("Steam")
	Steam.addRequestLobbyListStringFilter("version", "1.0.0", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_DEFAULT)
	
	Steam.requestLobbyList()
	print("Steam: Searching lobbies...")

func _on_lobby_match_list(lobbies: Array):
	var Steam = Engine.get_singleton("Steam")
	var lobby_list = []
	
	for lobby_id in lobbies:
		var lobby_data = {
			"id": lobby_id,
			"name": Steam.getLobbyData(lobby_id, "name"),
			"mode": Steam.getLobbyData(lobby_id, "mode"),
			"cur": Steam.getLobbyData(lobby_id, "cur"),
			"max": Steam.getLobbyData(lobby_id, "max"),
			"owner": Steam.getLobbyOwner(lobby_id)
		}
		lobby_list.append(lobby_data)
	
	print("Steam: Found ", lobby_list.size(), " lobbies")
	lobby_list_received.emit(lobby_list)

# Join Lobby
func join_lobby(lobby_id: int):
	if not steam_initialized:
		return
	Engine.get_singleton("Steam").joinLobby(lobby_id)
	print("Steam: Joining lobby: ", lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response != 1:
		push_error("Failed to join lobby: " + str(response))
		return
	
	var Steam = Engine.get_singleton("Steam")
	current_lobby_id = lobby_id
	is_lobby_owner = (Steam.getLobbyOwner(lobby_id) == steam_id)
	
	print("Steam: Joined lobby: ", lobby_id)
	lobby_joined.emit(lobby_id)

# Leave Lobby
func leave_lobby():
	if current_lobby_id != 0 and steam_initialized:
		Engine.get_singleton("Steam").leaveLobby(current_lobby_id)
		current_lobby_id = 0
		is_lobby_owner = false
		print("Steam: Left lobby")

# Update Lobby Data
func update_lobby_player_count(current: int):
	if current_lobby_id != 0 and is_lobby_owner and steam_initialized:
		Engine.get_singleton("Steam").setLobbyData(current_lobby_id, "cur", str(current))

func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int):
	if success == 1 and lobby_id == current_lobby_id:
		lobby_data_updated.emit()

func _on_lobby_chat_update(_lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int):
	lobby_data_updated.emit()

# Friends & Invites
func invite_friend_to_lobby(friend_id: int):
	if current_lobby_id != 0 and steam_initialized:
		Engine.get_singleton("Steam").inviteUserToLobby(current_lobby_id, friend_id)

func _on_join_requested(lobby_id: int):
	join_lobby(lobby_id)

func _on_game_lobby_join_requested(lobby_id: int, _friend_id: int):
	friend_invite_received.emit(lobby_id)
	join_lobby(lobby_id)

# Get Members
func get_lobby_members() -> Array:
	if current_lobby_id == 0 or not steam_initialized:
		return []
	
	var Steam = Engine.get_singleton("Steam")
	var member_count = Steam.getNumLobbyMembers(current_lobby_id)
	var members = []
	
	for i in range(member_count):
		var member_id = Steam.getLobbyMemberByIndex(current_lobby_id, i)
		var member_name = Steam.getFriendPersonaName(member_id)
		members.append({"id": member_id, "name": member_name})
	
	return members

# P2P Networking via Steam Sockets
func send_p2p_packet(target_id: int, data: PackedByteArray, reliable := true):
	if not steam_initialized:
		return
	var Steam = Engine.get_singleton("Steam")
	var send_type = Steam.P2P_SEND_RELIABLE if reliable else Steam.P2P_SEND_UNRELIABLE
	Steam.sendP2PPacket(target_id, data, send_type, 0)

func read_p2p_packets() -> Array:
	if not steam_initialized:
		return []
	
	var Steam = Engine.get_singleton("Steam")
	var packets = []
	
	while Steam.getAvailableP2PPacketSize(0) > 0:
		var packet_data = Steam.readP2PPacket(Steam.getAvailableP2PPacketSize(0), 0)
		if packet_data.empty():
			break
		
		packets.append({
			"data": packet_data.data,
			"sender": packet_data.steam_id_remote
		})
	
	return packets
