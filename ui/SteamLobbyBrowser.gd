extends Control

@onready var lobby_list = $Panel/VBox/ScrollContainer/LobbyList
@onready var refresh_button = $Panel/VBox/Buttons/RefreshButton
@onready var back_button = $Panel/VBox/Buttons/BackButton

var lobby_buttons = []

func _ready():
	if not SteamManager.steam_initialized:
		push_error("Steam not initialized!")
		return
	
	refresh_button.pressed.connect(_on_refresh)
	back_button.pressed.connect(_on_back)
	
	SteamManager.lobby_list_received.connect(_on_lobby_list_received)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	
	_refresh_lobbies()

func _refresh_lobbies():
	# Clear
	for btn in lobby_buttons:
		btn.queue_free()
	lobby_buttons.clear()
	
	# Search
	SteamManager.search_lobbies()

func _on_refresh():
	_refresh_lobbies()

func _on_lobby_list_received(lobbies: Array):
	for lobby in lobbies:
		var btn = Button.new()
		btn.text = "%s [%s/%s] - %s" % [
			lobby.name if lobby.name else "Lobby",
			lobby.cur,
			lobby.max,
			lobby.mode
		]
		btn.pressed.connect(func(): SteamManager.join_lobby(lobby.id))
		
		lobby_list.add_child(btn)
		lobby_buttons.append(btn)

func _on_lobby_joined(_lobby_id: int):
	get_tree().change_scene_to_file("res://ui/LobbyWaitingRoom.tscn")

func _on_back():
	get_parent().show_main_menu()

