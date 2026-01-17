extends Node
## Steam Manager - Handles Steam initialization, lobbies, and P2P networking

signal steam_initialized(success: bool)
signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_list_received(lobbies: Array)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_player_joined(steam_id: int)
signal lobby_player_left(steam_id: int)
signal lobby_data_updated(lobby_id: int)
signal p2p_session_request(remote_id: int)
signal p2p_packet_received(data: PackedByteArray, sender_id: int)

enum LobbyType {
	PRIVATE = 0,
	FRIENDS_ONLY = 1,
	PUBLIC = 2,
	INVISIBLE = 3
}

const MAX_LOBBY_MEMBERS := 20
const GAME_ID := "TABG"
const CHANNEL := 0

var is_steam_initialized: bool = false
var steam_id: int = 0
var steam_name: String = ""
var current_lobby_id: int = 0
var is_lobby_owner: bool = false
var cached_lobbies: Array = []
var lobby_members: Array = []  # Array of steam IDs in current lobby


func _ready() -> void:
	_initialize_steam()


func _process(_delta: float) -> void:
	if is_steam_initialized:
		Steam.run_callbacks()
		_read_p2p_packets()


func _initialize_steam() -> void:
	var init_result: Dictionary = Steam.steamInitEx(false, 480)
	
	if init_result.status != Steam.STEAM_API_INIT_RESULT_OK:
		push_error("Steam initialization failed: %s" % init_result.verbal)
		steam_initialized.emit(false)
		return
	
	is_steam_initialized = true
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	
	print("Steam initialized! User: %s (ID: %d)" % [steam_name, steam_id])
	
	# Connect Steam signals
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)
	
	steam_initialized.emit(true)


## Create a new lobby for hosting
func create_lobby(lobby_name: String, max_players: int = MAX_LOBBY_MEMBERS, lobby_type: LobbyType = LobbyType.PUBLIC) -> void:
	if not is_steam_initialized:
		lobby_create_failed.emit("Steam not initialized")
		return
	
	if current_lobby_id != 0:
		leave_lobby()
	
	set_meta("pending_lobby_name", lobby_name)
	set_meta("pending_max_players", max_players)
	
	Steam.createLobby(lobby_type, max_players)


## Request list of available lobbies
func request_lobby_list() -> void:
	if not is_steam_initialized:
		lobby_list_received.emit([])
		return
	
	Steam.addRequestLobbyListStringFilter("game", GAME_ID, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.requestLobbyList()


## Join an existing lobby
func join_lobby(lobby_id: int) -> void:
	if not is_steam_initialized:
		lobby_join_failed.emit("Steam not initialized")
		return
	
	if current_lobby_id != 0:
		leave_lobby()
	
	Steam.joinLobby(lobby_id)


## Leave the current lobby
func leave_lobby() -> void:
	if current_lobby_id != 0:
		# Close P2P sessions with all members
		for member_id in lobby_members:
			if member_id != steam_id:
				Steam.closeP2PSessionWithUser(member_id)
		
		Steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0
		is_lobby_owner = false
		lobby_members.clear()


## Get lobby data for display
func get_lobby_data(lobby_id: int) -> Dictionary:
	return {
		"id": lobby_id,
		"name": Steam.getLobbyData(lobby_id, "name"),
		"host_name": Steam.getLobbyData(lobby_id, "host_name"),
		"player_count": Steam.getNumLobbyMembers(lobby_id),
		"max_players": Steam.getLobbyData(lobby_id, "max_players").to_int(),
		"game_started": Steam.getLobbyData(lobby_id, "game_started") == "true"
	}


## Get all members in current lobby
func get_lobby_members() -> Array:
	var members := []
	if current_lobby_id == 0:
		return members
	
	var member_count := Steam.getNumLobbyMembers(current_lobby_id)
	for i in range(member_count):
		var member_id := Steam.getLobbyMemberByIndex(current_lobby_id, i)
		members.append({
			"steam_id": member_id,
			"name": Steam.getFriendPersonaName(member_id),
			"is_owner": member_id == Steam.getLobbyOwner(current_lobby_id)
		})
	
	return members


## Update lobby members list
func _update_lobby_members() -> void:
	lobby_members.clear()
	if current_lobby_id == 0:
		return
	
	var member_count := Steam.getNumLobbyMembers(current_lobby_id)
	for i in range(member_count):
		lobby_members.append(Steam.getLobbyMemberByIndex(current_lobby_id, i))
	
	print("[SteamManager] Updated lobby_members: %s (count: %d)" % [lobby_members, lobby_members.size()])


## Set lobby data (host only)
func set_lobby_data(key: String, value: String) -> void:
	if current_lobby_id != 0 and is_lobby_owner:
		Steam.setLobbyData(current_lobby_id, key, value)


## Mark game as started
func set_game_started(started: bool) -> void:
	set_lobby_data("game_started", "true" if started else "false")
	if started:
		Steam.setLobbyJoinable(current_lobby_id, false)


## Get the lobby owner's Steam ID
func get_lobby_owner_id() -> int:
	if current_lobby_id == 0:
		return 0
	return Steam.getLobbyOwner(current_lobby_id)


## Send P2P packet to a specific user
func send_p2p_packet(target_id: int, data: PackedByteArray, reliable: bool = true) -> bool:
	var send_type := Steam.P2P_SEND_RELIABLE if reliable else Steam.P2P_SEND_UNRELIABLE
	return Steam.sendP2PPacket(target_id, data, send_type, CHANNEL)


## Send P2P packet to all lobby members
func send_p2p_packet_all(data: PackedByteArray, reliable: bool = true, include_self: bool = false) -> void:
	for member_id in lobby_members:
		if member_id != steam_id or include_self:
			send_p2p_packet(member_id, data, reliable)


## Read incoming P2P packets
func _read_p2p_packets() -> void:
	var packet_size := Steam.getAvailableP2PPacketSize(CHANNEL)
	while packet_size > 0:
		var packet := Steam.readP2PPacket(packet_size, CHANNEL)
		if packet.is_empty():
			break
		
		# Validate packet has required keys before accessing
		# Note: GodotSteam uses "remote_steam_id", not "steam_id_remote"
		if not packet.has("remote_steam_id") or not packet.has("data"):
			packet_size = Steam.getAvailableP2PPacketSize(CHANNEL)
			continue
		
		var sender_id: int = packet["remote_steam_id"]
		var data: PackedByteArray = packet["data"]
		p2p_packet_received.emit(data, sender_id)
		
		packet_size = Steam.getAvailableP2PPacketSize(CHANNEL)


## Accept P2P session from user
func accept_p2p_session(remote_id: int) -> void:
	Steam.acceptP2PSessionWithUser(remote_id)


# --- Steam Callbacks ---

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		lobby_create_failed.emit("Failed to create lobby (Error: %d)" % result)
		return
	
	current_lobby_id = lobby_id
	is_lobby_owner = true
	
	var lobby_name: String = get_meta("pending_lobby_name", steam_name + "'s Game")
	var max_players: int = get_meta("pending_max_players", MAX_LOBBY_MEMBERS)
	
	Steam.setLobbyData(lobby_id, "game", GAME_ID)
	Steam.setLobbyData(lobby_id, "name", lobby_name)
	Steam.setLobbyData(lobby_id, "host_name", steam_name)
	Steam.setLobbyData(lobby_id, "host_id", str(steam_id))
	Steam.setLobbyData(lobby_id, "max_players", str(max_players))
	Steam.setLobbyData(lobby_id, "player_count", "1")
	Steam.setLobbyData(lobby_id, "game_started", "false")
	
	remove_meta("pending_lobby_name")
	remove_meta("pending_max_players")
	
	_update_lobby_members()
	lobby_created.emit(lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	cached_lobbies.clear()
	
	for lobby_id in lobbies:
		var game := Steam.getLobbyData(lobby_id, "game")
		if game == GAME_ID:
			var data := get_lobby_data(lobby_id)
			if not data.game_started:
				cached_lobbies.append(data)
	
	lobby_list_received.emit(cached_lobbies)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, result: int) -> void:
	if result != Steam.RESULT_OK:
		lobby_join_failed.emit("Failed to join lobby (Error: %d)" % result)
		return
	
	current_lobby_id = lobby_id
	is_lobby_owner = (Steam.getLobbyOwner(lobby_id) == steam_id)
	
	_update_lobby_members()
	
	# If we're not the host, request P2P connection with host
	if not is_lobby_owner:
		var host_id := get_lobby_owner_id()
		# Send a "hello" packet to establish P2P connection
		# Use var_to_bytes format to match network_manager's expected packet format
		var hello_packet := {
			"type": "HELLO",
			"data": {},
			"sender": steam_id
		}
		send_p2p_packet(host_id, var_to_bytes(hello_packet))
		print("[SteamManager] Sent HELLO to host: %d" % host_id)
	
	lobby_joined.emit(lobby_id)


func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if lobby_id != current_lobby_id:
		return
	
	print("[SteamManager] Lobby chat update - changed_id: %d, chat_state: %d" % [changed_id, chat_state])
	_update_lobby_members()
	
	match chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			print("[SteamManager] Player entered lobby: %d" % changed_id)
			lobby_player_joined.emit(changed_id)
			if is_lobby_owner:
				Steam.setLobbyData(lobby_id, "player_count", str(lobby_members.size()))
		
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT, Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED, Steam.CHAT_MEMBER_STATE_CHANGE_KICKED, Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
			print("[SteamManager] Player left/disconnected: %d" % changed_id)
			# Don't close P2P session immediately - the game might be starting
			# The P2P connection is needed even after leaving the lobby
			# Only emit signal, let NetworkManager decide what to do
			lobby_player_left.emit(changed_id)
			if is_lobby_owner:
				Steam.setLobbyData(lobby_id, "player_count", str(lobby_members.size()))


func _on_lobby_data_update(lobby_id: int, _member_id: int, _key: int) -> void:
	if lobby_id == current_lobby_id:
		lobby_data_updated.emit(lobby_id)


func _on_p2p_session_request(remote_id: int) -> void:
	print("[SteamManager] _on_p2p_session_request called - remote_id: %d, current_lobby_id: %d" % [remote_id, current_lobby_id])
	# Accept P2P sessions when we're in a lobby
	# Note: We accept from anyone in lobby context since Steam lobbies are authenticated
	# The lobby_members list might not be updated yet due to race conditions
	if current_lobby_id != 0:
		Steam.acceptP2PSessionWithUser(remote_id)
		p2p_session_request.emit(remote_id)
		print("[SteamManager] Accepted P2P session from: %d" % remote_id)
	else:
		print("[SteamManager] Rejected P2P from %d - not in a lobby" % remote_id)


func _on_p2p_session_connect_fail(steam_id_remote: int, session_error: int) -> void:
	push_warning("P2P connection failed with %d (Error: %d)" % [steam_id_remote, session_error])


func _exit_tree() -> void:
	leave_lobby()
	if is_steam_initialized:
		Steam.steamShutdown()
