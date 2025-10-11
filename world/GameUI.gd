extends CanvasLayer

@onready var crosshair = $Crosshair
@onready var stamina_bar = $StaminaBar
@onready var pause_menu = $PauseMenu

func _ready():
	add_to_group("game_ui")  # For pause menu to find us
	
	# Show crosshair
	crosshair.visible = true
	
	# Connect pause menu signals
	if pause_menu:
		pause_menu.disconnect_pressed.connect(_on_disconnect_pressed)

func _process(_delta):
	# Update stamina bar every frame
	_update_stamina_bar()

func _on_disconnect_pressed():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.disconnect_from_game()

func _update_stamina_bar():
	var local_player = NetworkManager.get_local_player()
	if local_player and is_instance_valid(local_player):
		var stamina_percent = local_player.get_stamina_percent()
		stamina_bar.value = stamina_percent * 100
		
		# Color based on stamina level (Elden Ring style)
		if stamina_percent > 0.5:
			stamina_bar.modulate = Color(0.2, 1.0, 0.3)  # Green
		elif stamina_percent > 0.25:
			stamina_bar.modulate = Color(1.0, 0.8, 0.0)  # Yellow
		else:
			stamina_bar.modulate = Color(1.0, 0.3, 0.2)  # Red
