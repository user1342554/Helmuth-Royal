extends Control
## Escape Menu - Pause menu with settings

signal menu_closed()
signal leave_game_requested()

@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var settings_panel: PanelContainer = $CenterContainer/SettingsPanel

# Settings tabs
@onready var settings_tabs: TabContainer = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs

# Video settings controls
@onready var resolution_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/ResolutionContainer/ResolutionOption
@onready var window_mode_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/WindowModeContainer/WindowModeOption
@onready var vsync_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/VSyncContainer/VSyncCheck
@onready var sensitivity_slider: HSlider = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/SensitivityContainer/SensitivitySlider
@onready var sensitivity_value: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/SensitivityContainer/SensitivityValue
@onready var fps_counter_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Video/Content/FPSCounterContainer/FPSCounterCheck

# Audio settings controls
@onready var output_device_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/OutputDeviceContainer/OutputDeviceOption
@onready var input_device_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/InputDeviceContainer/InputDeviceOption
@onready var master_volume_slider: HSlider = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/MasterVolumeContainer/MasterVolumeSlider
@onready var master_volume_value: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/MasterVolumeContainer/MasterVolumeValue
@onready var audio_info_label: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/AudioInfoContainer/AudioInfoLabel
@onready var test_voice_button: Button = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/TestVoiceButton

# Voice settings controls
@onready var bitrate_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/BitrateContainer/BitrateOption
@onready var buffer_slider: HSlider = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/BufferContainer/BufferSlider
@onready var buffer_value: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/BufferContainer/BufferValue
@onready var loopback_stats_label: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Audio/Content/LoopbackStatsLabel

# Graphics settings controls
@onready var preset_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/PresetContainer/PresetOption
@onready var render_scale_slider: HSlider = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/RenderScaleContainer/RenderScaleSlider
@onready var render_scale_value: Label = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/RenderScaleContainer/RenderScaleValue
@onready var shadow_quality_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/ShadowQualityContainer/ShadowQualityOption
@onready var msaa_option: OptionButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/MSAAContainer/MSAAOption
@onready var taa_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/TAAContainer/TAACheck
@onready var ssao_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/SSAOContainer/SSAOCheck
@onready var ssr_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/SSRContainer/SSRCheck
@onready var bloom_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/BloomContainer/BloomCheck
@onready var sdfgi_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/SDFGIContainer/SDFGICheck
@onready var volumetric_fog_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/VolumetricFogContainer/VolumetricFogCheck
@onready var clouds_check: CheckButton = $CenterContainer/SettingsPanel/Margin/VBox/SettingsTabs/Graphics/ScrollContainer/Content/CloudsContainer/CloudsCheck

var _testing_voice: bool = false
var _stats_update_timer: float = 0.0
var _updating_graphics_ui: bool = false  # Prevent feedback loops


func _ready() -> void:
	_setup_settings_options()
	_load_current_settings()
	hide()
	
	# Listen for graphics settings changes (e.g., when preset changes VSync)
	GraphicsSettings.settings_changed.connect(_on_graphics_settings_changed)


func _process(delta: float) -> void:
	# Update loopback stats while testing voice
	if _testing_voice and visible:
		_stats_update_timer += delta
		if _stats_update_timer >= 0.2:  # Update 5 times per second
			_stats_update_timer = 0.0
			_update_loopback_stats()


func _setup_settings_options() -> void:
	# Resolution options
	resolution_option.clear()
	for res_string in SettingsManager.get_resolution_strings():
		resolution_option.add_item(res_string)
	
	# Window mode options
	window_mode_option.clear()
	window_mode_option.add_item("Windowed")
	window_mode_option.add_item("Borderless")
	window_mode_option.add_item("Fullscreen")
	
	# Audio device options
	_refresh_audio_devices()
	
	# Voice quality (bitrate) options
	bitrate_option.clear()
	for preset in VoiceManager.get_bitrate_presets():
		bitrate_option.add_item(preset.name)
	bitrate_option.selected = 1  # Default to Medium (24 kbps)
	
	# Graphics preset options
	_setup_graphics_options()


func _load_current_settings() -> void:
	resolution_option.selected = SettingsManager.get_resolution_index()
	window_mode_option.selected = SettingsManager.window_mode
	vsync_check.button_pressed = GraphicsSettings.vsync_enabled  # Use GraphicsSettings for VSync
	sensitivity_slider.value = SettingsManager.mouse_sensitivity
	fps_counter_check.button_pressed = GraphicsSettings.show_fps_counter
	_update_sensitivity_label()
	
	# Audio settings
	_refresh_audio_devices()
	master_volume_slider.value = SettingsManager.master_volume
	_update_master_volume_label()
	_update_audio_info()
	
	# Voice settings
	buffer_slider.value = VoiceManager.decoder_buffer_chunks
	_update_buffer_label()
	
	# Find matching bitrate preset
	var presets = VoiceManager.get_bitrate_presets()
	for i in presets.size():
		if presets[i].value == VoiceManager.opus_bitrate:
			bitrate_option.selected = i
			break
	
	# Graphics settings
	_load_graphics_settings()


func show_menu() -> void:
	_load_current_settings()
	main_panel.visible = true
	settings_panel.visible = false
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_menu() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu_closed.emit()


func _update_sensitivity_label() -> void:
	sensitivity_value.text = "%.2f" % sensitivity_slider.value


# --- Main Menu Buttons ---

func _on_resume_pressed() -> void:
	hide_menu()


func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_panel.visible = true
	settings_tabs.current_tab = 0  # Reset to Video tab


func _on_leave_pressed() -> void:
	leave_game_requested.emit()


# --- Settings Panel ---

func _on_settings_back_pressed() -> void:
	main_panel.visible = true
	settings_panel.visible = false


func _on_resolution_selected(index: int) -> void:
	var res: Vector2i = SettingsManager.RESOLUTIONS[index]
	SettingsManager.set_resolution(res)


func _on_window_mode_selected(index: int) -> void:
	SettingsManager.set_window_mode(index as SettingsManager.WindowMode)


func _on_vsync_toggled(toggled_on: bool) -> void:
	GraphicsSettings.set_vsync(toggled_on)


func _on_sensitivity_changed(value: float) -> void:
	SettingsManager.set_mouse_sensitivity(value)
	_update_sensitivity_label()


func _on_fps_counter_toggled(toggled_on: bool) -> void:
	GraphicsSettings.set_show_fps_counter(toggled_on)


# --- Audio Settings ---

func _refresh_audio_devices() -> void:
	# Output devices
	output_device_option.clear()
	var output_devices = SettingsManager.get_output_devices()
	var current_output = SettingsManager.get_current_output_device()
	var output_index := 0
	
	for i in output_devices.size():
		output_device_option.add_item(output_devices[i])
		if output_devices[i] == current_output:
			output_index = i
	
	output_device_option.selected = output_index
	
	# Input devices (microphones)
	input_device_option.clear()
	var input_devices = SettingsManager.get_input_devices()
	var current_input = SettingsManager.get_current_input_device()
	var input_index := 0
	
	for i in input_devices.size():
		input_device_option.add_item(input_devices[i])
		if input_devices[i] == current_input:
			input_index = i
	
	input_device_option.selected = input_index


func _update_master_volume_label() -> void:
	master_volume_value.text = "%d%%" % int(master_volume_slider.value * 100)


func _update_audio_info() -> void:
	var info = SettingsManager.get_audio_info()
	audio_info_label.text = "Sample Rate: %d Hz (Input: %d Hz)" % [int(info.mix_rate), int(info.input_mix_rate)]


func _on_output_device_selected(index: int) -> void:
	var device = output_device_option.get_item_text(index)
	SettingsManager.set_output_device(device)
	_update_audio_info()


func _on_input_device_selected(index: int) -> void:
	var device = input_device_option.get_item_text(index)
	SettingsManager.set_input_device(device)
	_update_audio_info()


func _on_master_volume_changed(value: float) -> void:
	SettingsManager.set_master_volume(value)
	_update_master_volume_label()


func _on_bitrate_selected(index: int) -> void:
	var presets = VoiceManager.get_bitrate_presets()
	if index >= 0 and index < presets.size():
		VoiceManager.set_bitrate(presets[index].value)


func _on_buffer_changed(value: float) -> void:
	VoiceManager.set_buffer_chunks(int(value))
	_update_buffer_label()


func _update_buffer_label() -> void:
	var chunks := int(buffer_slider.value)
	var latency_ms := chunks * 20  # 20ms per chunk
	buffer_value.text = "%dms" % latency_ms


func _update_loopback_stats() -> void:
	var stats = VoiceManager.get_loopback_stats()
	if stats.enabled:
		loopback_stats_label.visible = true
		loopback_stats_label.text = "Queue: %d packets (%dms latency)" % [
			stats.queue_size, stats.latency_ms]
		
		# Color code based on latency
		if stats.latency_ms > 500:
			loopback_stats_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif stats.latency_ms > 200:
			loopback_stats_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		else:
			loopback_stats_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		loopback_stats_label.visible = false


func _on_test_voice_pressed() -> void:
	if _testing_voice:
		# Stop test
		_testing_voice = false
		test_voice_button.text = "Test Microphone"
		loopback_stats_label.visible = false
		VoiceManager.enable_loopback(false)
		VoiceManager.disable_voice()
	else:
		# Start test - enable loopback
		_testing_voice = true
		test_voice_button.text = "Stop Test"
		loopback_stats_label.visible = true
		VoiceManager.enable_voice()
		VoiceManager.enable_loopback(true)


# --- Graphics Settings ---

func _setup_graphics_options() -> void:
	# Quality presets
	preset_option.clear()
	preset_option.add_item("Potato")
	preset_option.add_item("Ultra Low")
	preset_option.add_item("Low")
	preset_option.add_item("Medium")
	preset_option.add_item("High")
	preset_option.add_item("Ultra")
	preset_option.add_item("I Paid For The Whole PC")
	preset_option.add_item("Custom")
	
	# Shadow quality
	shadow_quality_option.clear()
	shadow_quality_option.add_item("Off")
	shadow_quality_option.add_item("Low")
	shadow_quality_option.add_item("Medium")
	shadow_quality_option.add_item("High")
	
	# MSAA
	msaa_option.clear()
	msaa_option.add_item("Off")
	msaa_option.add_item("2x")
	msaa_option.add_item("4x")
	msaa_option.add_item("8x")


func _load_graphics_settings() -> void:
	_updating_graphics_ui = true
	
	# Preset
	preset_option.selected = GraphicsSettings.current_preset
	
	# Render scale
	render_scale_slider.value = GraphicsSettings.render_scale
	_update_render_scale_label()
	
	# Shadow quality
	shadow_quality_option.selected = GraphicsSettings.shadow_quality
	
	# MSAA
	msaa_option.selected = GraphicsSettings.msaa_quality
	
	# Effects toggles
	taa_check.button_pressed = GraphicsSettings.taa_enabled
	ssao_check.button_pressed = GraphicsSettings.ssao_enabled
	ssr_check.button_pressed = GraphicsSettings.ssr_enabled
	bloom_check.button_pressed = GraphicsSettings.bloom_enabled
	sdfgi_check.button_pressed = GraphicsSettings.sdfgi_enabled
	volumetric_fog_check.button_pressed = GraphicsSettings.volumetric_fog_enabled
	clouds_check.button_pressed = GraphicsSettings.clouds_enabled
	
	_updating_graphics_ui = false


func _update_render_scale_label() -> void:
	render_scale_value.text = "%d%%" % int(render_scale_slider.value * 100)


func _on_preset_selected(index: int) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.apply_preset(index as GraphicsSettings.QualityPreset)
	_load_graphics_settings()  # Refresh UI to show preset values


func _on_render_scale_changed(value: float) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_render_scale(value)
	_update_render_scale_label()


func _on_shadow_quality_selected(index: int) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_shadow_quality(index)


func _on_msaa_selected(index: int) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_msaa_quality(index)


func _on_taa_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_taa_enabled(toggled_on)


func _on_ssao_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_ssao_enabled(toggled_on)


func _on_ssr_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_ssr_enabled(toggled_on)


func _on_bloom_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_bloom_enabled(toggled_on)


func _on_sdfgi_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_sdfgi_enabled(toggled_on)


func _on_volumetric_fog_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_volumetric_fog_enabled(toggled_on)


func _on_clouds_toggled(toggled_on: bool) -> void:
	if _updating_graphics_ui:
		return
	GraphicsSettings.set_clouds_enabled(toggled_on)


func _on_graphics_settings_changed() -> void:
	# Update VSync checkbox when graphics settings change (e.g., preset change)
	vsync_check.button_pressed = GraphicsSettings.vsync_enabled
	# Also refresh graphics settings UI
	_load_graphics_settings()
