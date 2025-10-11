extends Control

@onready var back_button = $Panel/VBox/BackButton
@onready var range_slider = $Panel/VBox/VoiceSettings/RangeSlider
@onready var range_label = $Panel/VBox/VoiceSettings/RangeLabel
@onready var volume_slider = $Panel/VBox/VoiceSettings/VolumeSlider
@onready var volume_label = $Panel/VBox/VoiceSettings/VolumeLabel
@onready var quality_option = $Panel/VBox/QualityOption

func _ready():
	# Connect signals
	back_button.pressed.connect(_on_back_pressed)
	range_slider.value_changed.connect(_on_range_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	quality_option.item_selected.connect(_on_quality_selected)
	
	# Initialize values
	range_slider.value = VoiceChat.voice_range
	volume_slider.value = VoiceChat.voice_volume
	_update_labels()
	
	# Populate quality options
	quality_option.clear()
	quality_option.add_item("Ultra Low", 0)
	quality_option.add_item("Low", 1)
	quality_option.add_item("Medium", 2)
	quality_option.add_item("High", 3)
	quality_option.select(2)  # Default: Medium

func _on_back_pressed():
	var multiplayer_menu = _get_multiplayer_menu()
	if multiplayer_menu:
		multiplayer_menu.show_main_menu()

func _on_range_changed(value: float):
	VoiceChat.voice_range = value
	_update_labels()

func _on_volume_changed(value: float):
	VoiceChat.voice_volume = value
	_update_labels()

func _on_quality_selected(index: int):
	# Apply graphics preset
	match index:
		0:
			GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.ULTRA_LOW)
		1:
			GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
		2:
			GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.MEDIUM)
		3:
			GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	print("Graphics quality changed to: ", quality_option.get_item_text(index))

func _update_labels():
	range_label.text = "Voice Range: %.1f m" % VoiceChat.voice_range
	volume_label.text = "Voice Volume: %.2f" % VoiceChat.voice_volume

func _get_multiplayer_menu():
	var node = get_parent()
	while node:
		if node.has_method("show_main_menu"):
			return node
		node = node.get_parent() if node.get_parent() != node else null
	return null
