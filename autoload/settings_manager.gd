extends Node
## Settings Manager - Handles saving/loading game settings

signal settings_changed()

const SETTINGS_PATH := "user://settings.cfg"

# Available resolutions
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

# Window modes
enum WindowMode {
	WINDOWED,
	BORDERLESS,
	FULLSCREEN
}

# Current settings
var resolution: Vector2i = Vector2i(1920, 1080)
var window_mode: WindowMode = WindowMode.BORDERLESS
var vsync_enabled: bool = true
var master_volume: float = 1.0
var mouse_sensitivity: float = 1.0

# Audio device settings
var input_device: String = "Default"
var output_device: String = "Default"
var voice_volume: float = 1.0

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()
	apply_settings()


func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		# First run - use defaults
		save_settings()
		return
	
	# Load video settings
	resolution.x = _config.get_value("video", "resolution_x", 1920)
	resolution.y = _config.get_value("video", "resolution_y", 1080)
	window_mode = _config.get_value("video", "window_mode", WindowMode.WINDOWED)
	vsync_enabled = _config.get_value("video", "vsync", true)
	
	# Load audio settings
	master_volume = _config.get_value("audio", "master_volume", 1.0)
	voice_volume = _config.get_value("audio", "voice_volume", 1.0)
	input_device = _config.get_value("audio", "input_device", "Default")
	output_device = _config.get_value("audio", "output_device", "Default")
	
	# Load input settings
	mouse_sensitivity = _config.get_value("input", "mouse_sensitivity", 1.0)


func save_settings() -> void:
	# Video settings
	_config.set_value("video", "resolution_x", resolution.x)
	_config.set_value("video", "resolution_y", resolution.y)
	_config.set_value("video", "window_mode", window_mode)
	_config.set_value("video", "vsync", vsync_enabled)
	
	# Audio settings
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "voice_volume", voice_volume)
	_config.set_value("audio", "input_device", input_device)
	_config.set_value("audio", "output_device", output_device)
	
	# Input settings
	_config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	
	_config.save(SETTINGS_PATH)


func apply_settings() -> void:
	# Apply resolution and window mode
	match window_mode:
		WindowMode.WINDOWED:
			# First exit fullscreen if we're in it
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			# Set the window size to the selected resolution
			get_window().size = resolution
			_center_window()
		WindowMode.BORDERLESS:
			# Borderless fullscreen (uses desktop resolution)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		WindowMode.FULLSCREEN:
			# Exclusive fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	
	# Apply VSync
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	# Apply audio (if AudioServer buses exist)
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	
	# Apply audio devices
	_apply_audio_devices()
	
	settings_changed.emit()


func _apply_audio_devices() -> void:
	# Set output device
	if output_device != "Default" and output_device in get_output_devices():
		AudioServer.output_device = output_device
	else:
		AudioServer.output_device = "Default"
	
	# Set input device
	if input_device != "Default" and input_device in get_input_devices():
		AudioServer.input_device = input_device
	else:
		AudioServer.input_device = "Default"
	
	print("[SettingsManager] Audio devices - Output: %s, Input: %s" % [AudioServer.output_device, AudioServer.input_device])


func _center_window() -> void:
	var screen_index := DisplayServer.get_primary_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_index)
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var window_size := get_window().size
	var centered_pos := screen_pos + (screen_size - window_size) / 2
	get_window().position = centered_pos


func set_resolution(res: Vector2i) -> void:
	resolution = res
	apply_settings()
	save_settings()


func set_window_mode(mode: WindowMode) -> void:
	window_mode = mode
	apply_settings()
	save_settings()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	apply_settings()
	save_settings()


func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 1.0)
	apply_settings()
	save_settings()


func set_mouse_sensitivity(sens: float) -> void:
	mouse_sensitivity = clamp(sens, 0.1, 3.0)
	save_settings()
	settings_changed.emit()


func get_resolution_index() -> int:
	for i in range(RESOLUTIONS.size()):
		if RESOLUTIONS[i] == resolution:
			return i
	return 3  # Default to 1080p


func get_resolution_strings() -> Array[String]:
	var strings: Array[String] = []
	for res in RESOLUTIONS:
		strings.append("%dx%d" % [res.x, res.y])
	return strings


# ===== Audio Device Functions =====

func get_output_devices() -> PackedStringArray:
	return AudioServer.get_output_device_list()


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_output_device(device: String) -> void:
	output_device = device
	AudioServer.output_device = device
	save_settings()
	print("[SettingsManager] Output device set to: %s" % device)


func set_input_device(device: String) -> void:
	input_device = device
	AudioServer.input_device = device
	save_settings()
	print("[SettingsManager] Input device set to: %s" % device)


func set_voice_volume(volume: float) -> void:
	voice_volume = clamp(volume, 0.0, 1.0)
	save_settings()
	settings_changed.emit()


func get_current_output_device() -> String:
	return AudioServer.output_device


func get_current_input_device() -> String:
	return AudioServer.input_device


func get_audio_info() -> Dictionary:
	return {
		"output_device": AudioServer.output_device,
		"input_device": AudioServer.input_device,
		"output_devices": AudioServer.get_output_device_list(),
		"input_devices": AudioServer.get_input_device_list(),
		"mix_rate": AudioServer.get_mix_rate(),
		"input_mix_rate": AudioServer.get_input_mix_rate()
	}

