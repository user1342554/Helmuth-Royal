extends Control

signal resume_pressed
signal disconnect_pressed

@onready var resume_button = $Panel/VBox/ResumeButton
@onready var settings_button = $Panel/VBox/SettingsButton
@onready var disconnect_button = $Panel/VBox/DisconnectButton
@onready var quit_button = $Panel/VBox/QuitButton

@onready var settings_panel = $SettingsPanel

# Settings references
@onready var voice_quality_slider = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/VoiceQualitySlider
@onready var voice_quality_label = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/VoiceQualityLabel
@onready var voice_volume_slider = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/VoiceVolumeSlider
@onready var voice_volume_label = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/VoiceVolumeLabel
@onready var input_device_option = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/InputDeviceOption
@onready var output_device_option = $SettingsPanel/Panel/VBox/TabContainer/Audio/AudioVBox/OutputDeviceOption
@onready var settings_back_button = $SettingsPanel/Panel/VBox/BackButton

# Controls references
@onready var controls_list = $SettingsPanel/Panel/VBox/TabContainer/Controls/ControlsList

var is_paused = false
var awaiting_input = false
var current_action = ""

func _ready():
	hide()
	set_process_input(true)
	
	# Connect main buttons
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect settings buttons
	voice_quality_slider.value_changed.connect(_on_voice_quality_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	
	# Initialize settings
	_init_settings()
	_populate_controls()

func _input(event):
	if event.is_action_pressed("ui_cancel") and not awaiting_input:
		if is_paused:
			_on_resume_pressed()
		else:
			show_pause_menu()
	
	# Handle key rebinding
	if awaiting_input and event is InputEventKey and event.pressed:
		_assign_key_to_action(current_action, event)
		awaiting_input = false

func show_pause_menu():
	is_paused = true
	show()
	settings_panel.hide()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_pause_menu():
	is_paused = false
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed():
	hide_pause_menu()
	resume_pressed.emit()

func _on_settings_pressed():
	settings_panel.show()

func _on_disconnect_pressed():
	hide_pause_menu()
	disconnect_pressed.emit()
	# Also go to main menu
	var tree = get_tree()
	if tree:
		tree.paused = false
		tree.change_scene_to_file("res://ui/MultiplayerMenu.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _on_settings_back_pressed():
	settings_panel.hide()

# Settings functions
func _init_settings():
	# Initialize voice quality slider (0-5)
	voice_quality_slider.min_value = 0
	voice_quality_slider.max_value = 5
	voice_quality_slider.step = 1
	voice_quality_slider.value = 3  # Default
	
	# Initialize voice volume slider
	voice_volume_slider.min_value = 0.5
	voice_volume_slider.max_value = 5.0
	voice_volume_slider.step = 0.1
	voice_volume_slider.value = VoiceChat.voice_volume
	
	# Populate audio devices
	_populate_audio_devices()
	
	_update_settings_labels()

func _on_voice_quality_changed(value: float):
	VoiceChat.set_quality(int(value))
	_update_settings_labels()
	
	# Sync to all clients if host
	if multiplayer.is_server():
		_sync_quality.rpc(int(value))

@rpc("authority", "call_local")
func _sync_quality(quality: int):
	VoiceChat.set_quality(quality)
	voice_quality_slider.value = quality

func _on_voice_volume_changed(value: float):
	VoiceChat.voice_volume = value
	_update_settings_labels()

func _update_settings_labels():
	var quality_text = "MAX" if voice_quality_slider.value == 5 else str(int(voice_quality_slider.value) + 1)
	voice_quality_label.text = "Voice Quality: " + quality_text
	voice_volume_label.text = "Voice Volume: %.2f" % voice_volume_slider.value

func _populate_audio_devices():
	# Get audio devices from AudioServer
	input_device_option.clear()
	output_device_option.clear()
	
	# Add input devices (microphones)
	var input_devices = AudioServer.get_input_device_list()
	for device in input_devices:
		input_device_option.add_item(device)
	
	# Set current input device
	var current_input = AudioServer.input_device
	for i in range(input_device_option.get_item_count()):
		if input_device_option.get_item_text(i) == current_input:
			input_device_option.selected = i
			break
	
	# Add output devices (speakers/headphones)
	var output_devices = AudioServer.get_output_device_list()
	for device in output_devices:
		output_device_option.add_item(device)
	
	# Set current output device
	var current_output = AudioServer.output_device
	for i in range(output_device_option.get_item_count()):
		if output_device_option.get_item_text(i) == current_output:
			output_device_option.selected = i
			break
	
	# Connect signals
	input_device_option.item_selected.connect(_on_input_device_selected)
	output_device_option.item_selected.connect(_on_output_device_selected)

func _on_input_device_selected(index: int):
	var device_name = input_device_option.get_item_text(index)
	AudioServer.input_device = device_name
	print("Input device changed to: ", device_name)

func _on_output_device_selected(index: int):
	var device_name = output_device_option.get_item_text(index)
	AudioServer.output_device = device_name
	print("Output device changed to: ", device_name)

# Controls remapping
func _populate_controls():
	# Clear existing controls
	for child in controls_list.get_children():
		child.queue_free()
	
	# Add all input actions (without talk - automatic voice)
	var actions = [
		"move_forward",
		"move_back", 
		"move_left",
		"move_right",
		"jump",
		"dodge",
		"sprint",
		"sneak"
	]
	
	for action in actions:
		if InputMap.has_action(action):
			_add_control_row(action)

func _add_control_row(action: String):
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(400, 40)
	
	# Action label
	var label = Label.new()
	label.text = action.capitalize()
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)
	
	# Current key display
	var key_label = Label.new()
	key_label.name = "KeyLabel"
	key_label.text = _get_action_key_string(action)
	key_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(key_label)
	
	# Rebind button
	var button = Button.new()
	button.text = "Rebind"
	button.pressed.connect(_on_rebind_pressed.bind(action, key_label))
	hbox.add_child(button)
	
	controls_list.add_child(hbox)

func _get_action_key_string(action: String) -> String:
	var events = InputMap.action_get_events(action)
	if events.size() > 0:
		var event = events[0]
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode)
	return "None"

func _on_rebind_pressed(action: String, key_label: Label):
	awaiting_input = true
	current_action = action
	key_label.text = "Press key..."

func _assign_key_to_action(action: String, event: InputEventKey):
	# Clear existing keys for this action
	InputMap.action_erase_events(action)
	
	# Add new key
	InputMap.action_add_event(action, event)
	
	# Update display
	_populate_controls()
	print("Rebound ", action, " to ", OS.get_keycode_string(event.physical_keycode))
