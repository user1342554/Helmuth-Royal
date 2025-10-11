extends Control

@onready var lobby_list = $Panel/VBox/ScrollContainer/LobbyList
@onready var refresh_button = $Panel/VBox/ButtonBox/RefreshButton
@onready var back_button = $Panel/VBox/ButtonBox/BackButton
@onready var password_dialog = $PasswordDialog
@onready var password_input = $PasswordDialog/VBox/PasswordInput
@onready var password_ok = $PasswordDialog/VBox/ButtonBox/OKButton
@onready var password_cancel = $PasswordDialog/VBox/ButtonBox/CancelButton

var selected_lobby: LobbyManager.LobbyInfo = null
var lobby_buttons = []

func _ready():
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	password_ok.pressed.connect(_on_password_ok)
	password_cancel.pressed.connect(_on_password_cancel)
	
	LobbyManager.lobby_list_updated.connect(_on_lobby_list_updated)
	LobbyManager.lobby_join_failed.connect(_on_join_failed)
	
	password_dialog.hide()
	_refresh_lobby_list()

func _on_refresh_pressed():
	# LAN + Internet suche
	LobbyManager.fetch_internet_lobbies()
	_refresh_lobby_list()

func _refresh_lobby_list():
	# Clear existing buttons
	for button in lobby_buttons:
		button.queue_free()
	lobby_buttons.clear()
	
	# Get lobbies
	var lobbies = LobbyManager.get_lobbies()
	
	print("Lobby Browser: Refreshing... Found ", lobbies.size(), " lobbies")
	
	if lobbies.is_empty():
		var label = Label.new()
		label.text = "Keine Lobbies gefunden. Warte auf Broadcasts...\n(Stelle sicher, dass Host eine Lobby erstellt hat)"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lobby_list.add_child(label)
		lobby_buttons.append(label)
		
		# Debug: Show local IP
		var debug_label = Label.new()
		debug_label.text = "Deine IP: " + LobbyManager.get_local_ip()
		debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		debug_label.modulate = Color(0.7, 0.7, 0.7)
		lobby_list.add_child(debug_label)
		lobby_buttons.append(debug_label)
		return
	
	# Create button for each lobby
	for lobby in lobbies:
		var lobby_entry = _create_lobby_entry(lobby)
		lobby_list.add_child(lobby_entry)
		lobby_buttons.append(lobby_entry)

func _create_lobby_entry(lobby: LobbyManager.LobbyInfo) -> Control:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 80)
	
	var hbox = HBoxContainer.new()
	container.add_child(hbox)
	
	# Lobby info
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = lobby.lobby_name
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)
	
	var info_label = Label.new()
	var pwd_icon = "🔒 " if lobby.has_password else ""
	info_label.text = "%sHost: %s | Spieler: %d/%d | Ping: %d ms" % [
		pwd_icon,
		lobby.host_name,
		lobby.current_players,
		lobby.max_players,
		lobby.ping
	]
	info_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info_label)
	
	var ip_label = Label.new()
	ip_label.text = "IP: %s:%d" % [lobby.host_ip, lobby.port]
	ip_label.add_theme_font_size_override("font_size", 10)
	ip_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(ip_label)
	
	# Join button
	var join_btn = Button.new()
	join_btn.text = "Beitreten"
	join_btn.custom_minimum_size = Vector2(120, 0)
	join_btn.disabled = lobby.current_players >= lobby.max_players
	
	if lobby.current_players >= lobby.max_players:
		join_btn.text = "Voll"
	
	join_btn.pressed.connect(func(): _on_lobby_selected(lobby))
	hbox.add_child(join_btn)
	
	return container

func _on_lobby_selected(lobby: LobbyManager.LobbyInfo):
	selected_lobby = lobby
	
	if lobby.has_password:
		# Show password dialog
		password_input.text = ""
		password_dialog.show()
	else:
		# Join directly
		_join_lobby("")

func _on_password_ok():
	var password = password_input.text
	password_dialog.hide()
	_join_lobby(password)

func _on_password_cancel():
	password_dialog.hide()
	selected_lobby = null

func _join_lobby(password: String):
	if not selected_lobby:
		return
	
	LobbyManager.join_lobby(selected_lobby, password)

func _on_lobby_list_updated():
	_refresh_lobby_list()

func _on_join_failed(reason: String):
	# Show error
	var error_label = Label.new()
	error_label.text = "Fehler: " + reason
	error_label.modulate = Color.RED
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_list.add_child(error_label)
	lobby_buttons.append(error_label)
	
	# Remove after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(error_label):
		error_label.queue_free()

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
