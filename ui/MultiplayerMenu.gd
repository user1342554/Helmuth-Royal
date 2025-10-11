extends Control

@onready var main_menu = $MainMenu
@onready var create_lobby = $CreateLobby
@onready var lobby_browser = $LobbyBrowser
@onready var settings_menu = $SettingsMenu

func _ready():
	show_main_menu()

func show_main_menu():
	main_menu.show()
	create_lobby.hide()
	lobby_browser.hide()
	settings_menu.hide()

func show_create_lobby():
	main_menu.hide()
	create_lobby.show()
	lobby_browser.hide()
	settings_menu.hide()

func show_lobby_browser():
	main_menu.hide()
	create_lobby.hide()
	lobby_browser.show()
	settings_menu.hide()

func show_settings():
	main_menu.hide()
	create_lobby.hide()
	lobby_browser.hide()
	settings_menu.show()

