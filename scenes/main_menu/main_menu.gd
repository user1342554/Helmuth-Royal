extends Control
## Main Menu - Steam lobby hosting and browsing + LAN support

# Main menu elements
@onready var main_vbox: VBoxContainer = $VBox
@onready var steam_status_label: Label = $VBox/SteamStatus

# Host panel elements
@onready var host_panel: PanelContainer = $HostPanel
@onready var lobby_name_edit: LineEdit = $HostPanel/Margin/VBox/LobbyNameContainer/LobbyNameEdit
@onready var max_players_spin: SpinBox = $HostPanel/Margin/VBox/MaxPlayersContainer/MaxPlayersSpin
@onready var start_host_button: Button = $HostPanel/Margin/VBox/ButtonContainer/StartHostButton
@onready var host_back_button: Button = $HostPanel/Margin/VBox/ButtonContainer/BackButton

# Host status panel elements
@onready var status_panel: PanelContainer = $HostPanel/Margin/VBox/StatusPanel
@onready var status_label: Label = $HostPanel/Margin/VBox/StatusPanel/StatusVBox/StatusLabel
@onready var lobby_info_label: Label = $HostPanel/Margin/VBox/StatusPanel/StatusVBox/LobbyInfoLabel
@onready var player_count_label: Label = $HostPanel/Margin/VBox/StatusPanel/StatusVBox/PlayerCountLabel
@onready var start_game_button: Button = $HostPanel/Margin/VBox/StatusPanel/StatusVBox/StartGameButton

# Browse panel elements
@onready var browse_panel: PanelContainer = $BrowsePanel
@onready var refresh_button: Button = $BrowsePanel/Margin/VBox/HeaderBox/RefreshButton
@onready var lobby_list: VBoxContainer = $BrowsePanel/Margin/VBox/LobbyScrollContainer/LobbyList
@onready var no_lobbies_label: Label = $BrowsePanel/Margin/VBox/LobbyScrollContainer/LobbyList/NoLobbiesLabel
@onready var browse_status_label: Label = $BrowsePanel/Margin/VBox/StatusLabel
@onready var join_button: Button = $BrowsePanel/Margin/VBox/ButtonContainer/JoinButton

# LAN panel elements
@onready var lan_panel: PanelContainer = $LANPanel
@onready var local_ip_value: Label = $LANPanel/Margin/VBox/LocalIPContainer/LocalIPValue
@onready var host_port_spin: SpinBox = $LANPanel/Margin/VBox/HostSection/PortContainer/HostPortSpin
@onready var join_ip_edit: LineEdit = $LANPanel/Margin/VBox/JoinSection/IPContainer/JoinIPEdit
@onready var join_port_spin: SpinBox = $LANPanel/Margin/VBox/JoinSection/JoinPortContainer/JoinPortSpin
@onready var lan_status_label: Label = $LANPanel/Margin/VBox/LANStatusLabel
@onready var host_lan_button: Button = $LANPanel/Margin/VBox/HostSection/HostLANButton
@onready var join_lan_button: Button = $LANPanel/Margin/VBox/JoinSection/JoinLANButton

# LAN Host Status panel elements
@onready var lan_host_status_panel: PanelContainer = $LANHostStatusPanel
@onready var lan_ip_info_label: Label = $LANHostStatusPanel/Margin/VBox/IPInfoLabel
@onready var lan_player_count_label: Label = $LANHostStatusPanel/Margin/VBox/LANPlayerCountLabel

# LAN Waiting panel elements (for clients waiting for host to start)
@onready var lan_waiting_panel: PanelContainer = $LANWaitingPanel
@onready var waiting_player_count: Label = $LANWaitingPanel/Margin/VBox/WaitingPlayerCount

var _selected_lobby_id: int = 0
var _lobby_buttons: Array[Button] = []


func _ready() -> void:
	_show_main_menu()
	
	# Update Steam status
	if SteamManager.is_steam_initialized:
		_update_steam_status(true)
	else:
		_update_steam_status(false)
		SteamManager.steam_initialized.connect(_on_steam_initialized)
	
	# Connect to NetworkManager signals
	NetworkManager.hosting_started.connect(_on_hosting_started)
	NetworkManager.hosting_failed.connect(_on_hosting_failed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.game_starting.connect(_on_game_starting)
	
	print("[MainMenu] Ready - game_starting signal connected")


func _update_steam_status(initialized: bool) -> void:
	if initialized:
		steam_status_label.text = "Steam: %s" % SteamManager.steam_name
		steam_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	else:
		steam_status_label.text = "Steam: Not Connected"
		steam_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))


func _on_steam_initialized(success: bool) -> void:
	_update_steam_status(success)


func _show_main_menu() -> void:
	main_vbox.visible = true
	host_panel.visible = false
	browse_panel.visible = false
	lan_panel.visible = false
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = false


func _show_host_panel() -> void:
	main_vbox.visible = false
	host_panel.visible = true
	browse_panel.visible = false
	lan_panel.visible = false
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = false
	
	# Reset host panel state
	status_panel.visible = false
	start_host_button.visible = true
	start_host_button.disabled = false
	host_back_button.disabled = false
	lobby_name_edit.text = ""


func _show_browse_panel() -> void:
	main_vbox.visible = false
	host_panel.visible = false
	browse_panel.visible = true
	lan_panel.visible = false
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = false
	
	# Reset browse panel state
	browse_status_label.visible = false
	join_button.visible = true
	join_button.disabled = true
	join_button.text = "Join"
	refresh_button.visible = true
	refresh_button.disabled = false
	refresh_button.text = "Refresh"
	_selected_lobby_id = 0
	
	# Show lobby list items again
	for button in _lobby_buttons:
		if is_instance_valid(button):
			button.visible = true
	
	# Auto-refresh on open
	_on_refresh_pressed()


func _show_lan_panel() -> void:
	main_vbox.visible = false
	host_panel.visible = false
	browse_panel.visible = false
	lan_panel.visible = true
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = false
	
	# Reset LAN panel state
	lan_status_label.visible = false
	host_lan_button.disabled = false
	join_lan_button.disabled = false
	
	# Update local IP display
	local_ip_value.text = NetworkManager.get_local_ip()


func _show_lan_host_status() -> void:
	main_vbox.visible = false
	host_panel.visible = false
	browse_panel.visible = false
	lan_panel.visible = false
	lan_host_status_panel.visible = true
	lan_waiting_panel.visible = false


func _show_lan_waiting() -> void:
	main_vbox.visible = false
	host_panel.visible = false
	browse_panel.visible = false
	lan_panel.visible = false
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = true
	_update_waiting_player_count()


func _show_steam_waiting() -> void:
	# Show browse panel with waiting status
	main_vbox.visible = false
	host_panel.visible = false
	browse_panel.visible = true
	lan_panel.visible = false
	lan_host_status_panel.visible = false
	lan_waiting_panel.visible = false
	
	# Update UI to show waiting state
	join_button.visible = false
	refresh_button.visible = false
	browse_status_label.visible = true
	browse_status_label.text = "Connected! Waiting for host to start..."
	browse_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	
	# Hide the lobby list
	for button in _lobby_buttons:
		if is_instance_valid(button):
			button.visible = false
	no_lobbies_label.visible = false


# --- Main Menu Buttons ---

func _on_host_button_pressed() -> void:
	if not SteamManager.is_steam_initialized:
		return
	_show_host_panel()


func _on_browse_button_pressed() -> void:
	if not SteamManager.is_steam_initialized:
		return
	_show_browse_panel()


func _on_lan_button_pressed() -> void:
	_show_lan_panel()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


# --- Host Panel ---

func _on_host_back_pressed() -> void:
	NetworkManager.stop_networking()
	_show_main_menu()


func _on_start_host_pressed() -> void:
	start_host_button.disabled = true
	host_back_button.disabled = true
	
	var lobby_name := lobby_name_edit.text.strip_edges()
	var max_players := int(max_players_spin.value)
	
	NetworkManager.host_game(lobby_name, max_players)


func _on_hosting_started(info: Dictionary) -> void:
	# Check if this is a LAN game or Steam game
	if NetworkManager.is_lan_mode:
		_on_lan_hosting_started(info)
		return
	
	status_panel.visible = true
	start_host_button.visible = false
	host_back_button.disabled = false
	
	status_label.text = "Lobby Created!"
	lobby_info_label.text = info.lobby_name
	_update_player_count()


func _on_hosting_failed(reason: String) -> void:
	# Handle LAN hosting failure
	if lan_panel.visible:
		lan_status_label.visible = true
		lan_status_label.text = reason
		lan_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		host_lan_button.disabled = false
		join_lan_button.disabled = false
		return
	
	start_host_button.disabled = false
	host_back_button.disabled = false
	
	status_panel.visible = true
	status_label.text = "Failed to create lobby"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	lobby_info_label.text = reason
	player_count_label.visible = false
	start_game_button.visible = false


func _on_start_game_pressed() -> void:
	NetworkManager.start_game()


func _on_stop_host_pressed() -> void:
	NetworkManager.stop_networking()
	_show_host_panel()


func _update_player_count() -> void:
	var count := NetworkManager.get_player_count()
	var max_p := NetworkManager.get_max_players()
	player_count_label.text = "Players: %d/%d" % [count, max_p]


# --- Browse Panel ---

func _on_browse_back_pressed() -> void:
	NetworkManager.stop_networking()
	_show_main_menu()


func _on_refresh_pressed() -> void:
	refresh_button.disabled = true
	refresh_button.text = "Searching..."
	browse_status_label.visible = false
	
	NetworkManager.refresh_lobby_list()
	
	# Re-enable after a short delay
	await get_tree().create_timer(1.0).timeout
	refresh_button.disabled = false
	refresh_button.text = "Refresh"


func _on_lobby_list_updated(lobbies: Array) -> void:
	_clear_lobby_list()
	
	if lobbies.is_empty():
		no_lobbies_label.visible = true
		no_lobbies_label.text = "No games found. Click Refresh to search."
		return
	
	no_lobbies_label.visible = false
	
	for lobby_data in lobbies:
		_add_lobby_entry(lobby_data)


func _clear_lobby_list() -> void:
	# Remove all lobby buttons but keep the no_lobbies_label
	for button in _lobby_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_lobby_buttons.clear()
	_selected_lobby_id = 0
	join_button.disabled = true


func _add_lobby_entry(lobby_data: Dictionary) -> void:
	var entry := Button.new()
	entry.custom_minimum_size = Vector2(0, 40)
	entry.toggle_mode = true
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Format: "LobbyName                    HostName           5/20"
	var lobby_name: String = lobby_data.get("name", "Unknown")
	var host_name: String = lobby_data.get("host_name", "Unknown")
	var player_count: int = lobby_data.get("player_count", 0)
	var max_players: int = lobby_data.get("max_players", 20)
	
	# Truncate long names
	if lobby_name.length() > 25:
		lobby_name = lobby_name.substr(0, 22) + "..."
	if host_name.length() > 15:
		host_name = host_name.substr(0, 12) + "..."
	
	entry.text = "%-25s %-15s %d/%d" % [lobby_name, host_name, player_count, max_players]
	
	var lobby_id: int = lobby_data.get("id", 0)
	entry.pressed.connect(_on_lobby_selected.bind(lobby_id, entry))
	
	lobby_list.add_child(entry)
	_lobby_buttons.append(entry)


func _on_lobby_selected(lobby_id: int, button: Button) -> void:
	# Deselect other buttons
	for btn in _lobby_buttons:
		if btn != button:
			btn.button_pressed = false
	
	_selected_lobby_id = lobby_id
	join_button.disabled = false


func _on_join_pressed() -> void:
	if _selected_lobby_id == 0:
		return
	
	join_button.disabled = true
	join_button.text = "Joining..."
	browse_status_label.visible = true
	browse_status_label.text = "Connecting to lobby..."
	browse_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	
	NetworkManager.join_lobby(_selected_lobby_id)


func _on_connection_succeeded() -> void:
	# Both LAN and Steam clients should wait for host to start the game
	if NetworkManager.is_lan_mode:
		_show_lan_waiting()
	else:
		# Steam mode - show waiting in browse panel
		_show_steam_waiting()


func _on_connection_failed(reason: String) -> void:
	# Handle LAN connection failure
	if lan_panel.visible:
		lan_status_label.visible = true
		lan_status_label.text = reason
		lan_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		host_lan_button.disabled = false
		join_lan_button.disabled = false
		return
	
	browse_status_label.visible = true
	browse_status_label.text = reason
	browse_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	join_button.disabled = false
	join_button.text = "Join"


# --- Player Events ---

func _on_player_joined(_steam_id: int, _player_name: String) -> void:
	_update_player_count()
	_update_lan_player_count()
	_update_waiting_player_count()


func _on_player_left(_steam_id: int) -> void:
	_update_player_count()
	_update_lan_player_count()
	_update_waiting_player_count()


func _on_game_starting() -> void:
	# Host started the game - transition to game scene
	print("[MainMenu] _on_game_starting() called! Transitioning to game...")
	GameState.set_match_phase(GameState.MatchPhase.STARTING)
	
	# Small delay to ensure network packets are flushed before scene change
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://scenes/game/world.tscn")


# --- LAN Panel ---

func _on_lan_back_pressed() -> void:
	NetworkManager.stop_networking()
	_show_main_menu()


func _on_host_lan_pressed() -> void:
	host_lan_button.disabled = true
	join_lan_button.disabled = true
	lan_status_label.visible = true
	lan_status_label.text = "Starting server..."
	lan_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	
	var port := int(host_port_spin.value)
	NetworkManager.host_lan_game(port)


func _on_join_lan_pressed() -> void:
	var ip := join_ip_edit.text.strip_edges()
	if ip.is_empty():
		lan_status_label.visible = true
		lan_status_label.text = "Please enter an IP address"
		lan_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		return
	
	host_lan_button.disabled = true
	join_lan_button.disabled = true
	lan_status_label.visible = true
	lan_status_label.text = "Connecting to %s..." % ip
	lan_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	
	var port := int(join_port_spin.value)
	NetworkManager.join_lan_game(ip, port)


func _on_lan_hosting_started(info: Dictionary) -> void:
	_show_lan_host_status()
	
	var ip: String = info.get("ip", "127.0.0.1")
	var port: int = info.get("port", 7777)
	lan_ip_info_label.text = "IP: %s:%d" % [ip, port]
	_update_lan_player_count()


func _on_start_lan_game_pressed() -> void:
	NetworkManager.start_game()


func _on_stop_lan_pressed() -> void:
	NetworkManager.stop_networking()
	_show_lan_panel()


func _update_lan_player_count() -> void:
	if lan_host_status_panel.visible:
		var count := NetworkManager.get_player_count()
		var max_p := NetworkManager.get_max_players()
		lan_player_count_label.text = "Players: %d/%d" % [count, max_p]


func _on_leave_waiting_pressed() -> void:
	NetworkManager.stop_networking()
	_show_lan_panel()


func _update_waiting_player_count() -> void:
	if lan_waiting_panel.visible:
		var count := NetworkManager.get_player_count()
		waiting_player_count.text = "Players: %d" % count
