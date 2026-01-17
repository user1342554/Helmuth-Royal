extends CanvasLayer
## FPS Display - Shows framerate counter in corner of screen (only in-game)

var fps_label: Label
var control: Control
var in_game: bool = false  # Set by world scene

# Update optimization - don't update every frame
var _update_counter: int = 0
const UPDATE_INTERVAL: int = 10  # Update every N frames


func _ready() -> void:
	# Set layer to be on top of everything
	layer = 100
	
	# Create a control to hold the label (needed for proper anchoring)
	control = Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)
	
	# Create the FPS label
	fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.text = "FPS: 0"
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color.YELLOW)
	fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_label.add_theme_constant_override("shadow_offset_x", 2)
	fps_label.add_theme_constant_override("shadow_offset_y", 2)
	fps_label.add_theme_constant_override("outline_size", 2)
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	# Position in top-right corner with padding
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -120
	fps_label.offset_right = -10
	fps_label.offset_top = 10
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	control.add_child(fps_label)
	
	# Connect to settings changed signal
	GraphicsSettings.settings_changed.connect(_on_settings_changed)
	
	# Start hidden (not in game yet)
	_update_visibility()


func _process(_delta: float) -> void:
	if not fps_label.visible:
		return
	
	# Only update every N frames to reduce overhead
	_update_counter += 1
	if _update_counter < UPDATE_INTERVAL:
		return
	_update_counter = 0
	
	var fps := Engine.get_frames_per_second()
	fps_label.text = "FPS: %d" % fps
	
	# Color code based on performance
	if fps >= 60:
		fps_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		fps_label.add_theme_color_override("font_color", Color.RED)


func _on_settings_changed() -> void:
	_update_visibility()


func _update_visibility() -> void:
	# Only show if setting is enabled AND we're in game
	fps_label.visible = GraphicsSettings.show_fps_counter and in_game


func set_in_game(value: bool) -> void:
	in_game = value
	_update_visibility()
