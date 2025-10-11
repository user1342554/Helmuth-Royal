extends Control

@onready var lobby_name_input = $Panel/VBox/LobbyNameInput
@onready var max_players_spinbox = $Panel/VBox/MaxPlayersSpinBox
@onready var password_input = $Panel/VBox/PasswordInput
@onready var use_upnp_checkbox = $Panel/VBox/UseUPNPCheckbox
@onready var create_button = $Panel/VBox/CreateButton
@onready var back_button = $Panel/VBox/BackButton
@onready var status_label = $Panel/VBox/StatusLabel

func _ready():
	create_button.pressed.connect(_on_create_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Default values
	lobby_name_input.text = "My Lobby"
	max_players_spinbox.value = 8
	use_upnp_checkbox.button_pressed = true

func _on_create_pressed():
	var lobby_name = lobby_name_input.text.strip_edges()
	if lobby_name.is_empty():
		status_label.text = "Lobby-Name eingeben!"
		return
	
	var max_players = int(max_players_spinbox.value)
	var password = password_input.text
	var use_upnp = use_upnp_checkbox.button_pressed
	
	create_button.disabled = true
	status_label.text = "Lobby wird erstellt..."
	print("CreateLobby: Starting creation...")
	
	var success = await LobbyManager.create_lobby(lobby_name, max_players, password, use_upnp)
	
	print("CreateLobby: Result = ", success)
	
	if success:
		# Will redirect to LobbyWaitingRoom automatically
		print("CreateLobby: Success, going to lobby waiting room...")
	else:
		status_label.text = "Fehler beim Erstellen"
		create_button.disabled = false
		print("CreateLobby: Failed!")

func _on_back_pressed():
	var multiplayer_menu = _get_multiplayer_menu()
	if multiplayer_menu:
		multiplayer_menu.show_main_menu()

func _get_multiplayer_menu():
	var node = get_parent()
	while node:
		if node.has_method("show_main_menu"):
			return node
		node = node.get_parent() if node.get_parent() != node else null
	return null

