extends Control

@onready var create_lobby_button = $Panel/VBox/CreateLobbyButton
@onready var find_lobbies_button = $Panel/VBox/FindLobbiesButton
@onready var settings_button = $Panel/VBox/SettingsButton
@onready var quit_button = $Panel/VBox/QuitButton

func _ready():
	# Release mouse when in menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Connect buttons
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	find_lobbies_button.pressed.connect(_on_find_lobbies_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_create_lobby_pressed():
	var multiplayer_menu = _get_multiplayer_menu()
	if multiplayer_menu:
		multiplayer_menu.show_create_lobby()

func _on_find_lobbies_pressed():
	var multiplayer_menu = _get_multiplayer_menu()
	if multiplayer_menu:
		multiplayer_menu.show_lobby_browser()

func _on_settings_pressed():
	var multiplayer_menu = _get_multiplayer_menu()
	if multiplayer_menu:
		multiplayer_menu.show_settings()

func _on_quit_pressed():
	get_tree().quit()

func _get_multiplayer_menu():
	# Try to find MultiplayerMenu in parent hierarchy
	var node = get_parent()
	while node:
		if node.has_method("show_lobby_browser"):
			return node
		node = node.get_parent() if node.get_parent() != node else null
	return null
