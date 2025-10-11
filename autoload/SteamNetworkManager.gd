extends Node

# Steam P2P Network Manager (replaces ENet)

var players := {}
var is_host := false

signal player_joined(steam_id: int)
signal player_left(steam_id: int)

func _ready():
	set_process(false)

func _process(_delta):
	# Read P2P packets
	var packets = SteamManager.read_p2p_packets()
	for packet in packets:
		_handle_packet(packet.data, packet.sender)

func host_game():
	is_host = true
	players[SteamManager.steam_id] = {"name": SteamManager.steam_username}
	set_process(true)
	print("SteamNetwork: Hosting")

func join_game():
	is_host = false
	set_process(true)
	
	# Send join request to host
	if not SteamManager.steam_initialized or not Engine.has_singleton("Steam"):
		push_error("SteamNetwork: Cannot join - Steam not initialized")
		return
	
	var Steam = Engine.get_singleton("Steam")
	var host_id = Steam.getLobbyOwner(SteamManager.current_lobby_id)
	_send_join_request(host_id)
	print("SteamNetwork: Joining host: ", host_id)

func _send_join_request(host_id: int):
	var data = PackedByteArray()
	data.append(0)  # JOIN_REQUEST
	SteamManager.send_p2p_packet(host_id, data, true)

func _handle_packet(data: PackedByteArray, sender: int):
	if data.is_empty():
		return
	
	var msg_type = data[0]
	
	match msg_type:
		0:  # JOIN_REQUEST
			if is_host:
				_accept_player(sender)
		1:  # JOIN_ACCEPTED
			print("SteamNetwork: Join accepted")
		2:  # PLAYER_LIST
			_update_player_list(data.slice(1))

func _accept_player(steam_id: int):
	if not players.has(steam_id):
		var player_name = "Player " + str(steam_id)
		if SteamManager.steam_initialized and Engine.has_singleton("Steam"):
			var Steam = Engine.get_singleton("Steam")
			player_name = Steam.getFriendPersonaName(steam_id)
		
		players[steam_id] = {"name": player_name}
		print("SteamNetwork: Player joined: ", steam_id)
		
		# Send acceptance
		var data = PackedByteArray()
		data.append(1)  # JOIN_ACCEPTED
		SteamManager.send_p2p_packet(steam_id, data, true)
		
		# Broadcast updated player list
		_broadcast_player_list()
		player_joined.emit(steam_id)

func _broadcast_player_list():
	var data = PackedByteArray()
	data.append(2)  # PLAYER_LIST
	
	# TODO: Serialize player list
	
	for player_id in players.keys():
		if player_id != SteamManager.steam_id:
			SteamManager.send_p2p_packet(player_id, data, true)

func _update_player_list(data: PackedByteArray):
	# TODO: Deserialize player list
	pass

func disconnect_network():
	players.clear()
	is_host = false
	set_process(false)
	SteamManager.leave_lobby()
