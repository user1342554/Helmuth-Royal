extends Control

@onready var lobby_name_input = $Panel/VBox/LobbyNameInput
@onready var max_players = $Panel/VBox/MaxPlayersSpinBox
@onready var private_checkbox = $Panel/VBox/PrivateCheckbox
@onready var create_button = $Panel/VBox/CreateButton
@onready var back_button = $Panel/VBox/BackButton

func _ready():
	create_button.pressed.connect(_on_create)
	back_button.pressed.connect(_on_back)
	
	SteamManager.lobby_created.connect(_on_lobby_created)

func _on_create():
	var name = lobby_name_input.text.strip_edges()
	if name.is_empty():
		name = SteamManager.steam_username + "'s Lobby"
	
	var max_p = int(max_players.value)
	var is_private = private_checkbox.button_pressed
	
	create_button.disabled = true
	SteamManager.create_lobby(name, max_p, is_private)

func _on_lobby_created(_lobby_id: int):
	get_tree().change_scene_to_file("res://ui/LobbyWaitingRoom.tscn")

func _on_back():
	get_parent().show_main_menu()

