extends Control

@onready var lobby_name_label = $Panel/VBox/LobbyNameLabel
@onready var player_list = $Panel/VBox/ScrollContainer/PlayerList
@onready var start_button = $Panel/VBox/ButtonBox/StartButton
@onready var leave_button = $Panel/VBox/ButtonBox/LeaveButton
@onready var ip_label = $Panel/VBox/IPLabel

var is_host := false

func _ready():
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	
	# ENet only
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	is_host = multiplayer.is_server()
	
	start_button.visible = is_host
	
	_update_lobby_info()
	_refresh_player_list()

func _update_lobby_info():
	if LobbyManager.my_lobby:
		lobby_name_label.text = LobbyManager.my_lobby.lobby_name
	else:
		lobby_name_label.text = "Lobby"
	
	# Zeige IP für Host
	if is_host:
		var local_ip = LobbyManager.get_local_ip()
		ip_label.text = "LAN IP: " + local_ip
		
		if NetworkManager.upnp:
			var external_ip = NetworkManager.upnp.query_external_address()
			if not external_ip.is_empty():
				ip_label.text += "\nInternet IP: " + external_ip + " (in Zwischenablage)"
				DisplayServer.clipboard_set(external_ip)
	else:
		ip_label.visible = false

func _refresh_player_list():
	for child in player_list.get_children():
		child.queue_free()
	
	var members = []
	var my_id = 0
	var host_id = 0
	
	var peer_ids = [multiplayer.get_unique_id()]
	peer_ids.append_array(multiplayer.get_peers())
	for peer_id in peer_ids:
		members.append({"id": peer_id, "name": "Spieler " + str(peer_id)})
	my_id = multiplayer.get_unique_id()
	host_id = 1
	
	for member in members:
		var label = Label.new()
		var text = member.name
		if member.id == my_id:
			text += " (Du)"
		if member.id == host_id:
			text += " [Host]"
		label.text = text
		label.add_theme_font_size_override("font_size", 16)
		player_list.add_child(label)

func _on_player_connected(peer_id: int):
	_refresh_player_list()

func _on_player_disconnected(peer_id: int):
	_refresh_player_list()

func _on_steam_player_joined(_steam_id: int):
	_refresh_player_list()

func _on_steam_player_left(_steam_id: int):
	_refresh_player_list()

func _on_start_pressed():
	if not is_host:
		return
	
	start_button.disabled = true
	NetworkManager.start_game()

func _on_leave_pressed():
	NetworkManager.disconnect_from_game()

