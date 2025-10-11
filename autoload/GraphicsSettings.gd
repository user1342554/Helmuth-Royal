extends Node

# Advanced Graphics Settings System for maximum FPS

enum QualityPreset {
	ULTRA_LOW,      # Maximum FPS (~120+ FPS target)
	LOW,            # High FPS (~90+ FPS target)
	MEDIUM,         # Balanced (~60 FPS target)
	HIGH,           # Quality (~60 FPS target)
	ULTRA,          # Maximum Quality (~45+ FPS target)
	CUSTOM          # User-defined
}

# Current settings
var current_preset := QualityPreset.MEDIUM
var target_fps := 0  # 0 = unlimited
var vsync_enabled := true

# Individual settings
var shadow_quality := 1
var texture_quality := 1
var msaa_quality := 1
var fxaa_enabled := true
var ssaa_scale := 1.0
var gi_quality := 1
var volumetric_fog := true
var glow_enabled := true
var ssao_enabled := true
var ssr_enabled := false
var max_lights := 8

signal settings_changed

func _ready():
	print("GraphicsSettings initialized")
	# Load saved settings
	load_settings()

# Apply preset
func apply_preset(preset: QualityPreset):
	current_preset = preset
	
	match preset:
		QualityPreset.ULTRA_LOW:
			_apply_ultra_low_settings()
		QualityPreset.LOW:
			_apply_low_settings()
		QualityPreset.MEDIUM:
			_apply_medium_settings()
		QualityPreset.HIGH:
			_apply_high_settings()
		QualityPreset.ULTRA:
			_apply_ultra_settings()
	
	_apply_all_settings()
	save_settings()
	settings_changed.emit()

# ULTRA LOW - Maximum FPS (120+ target)
func _apply_ultra_low_settings():
	shadow_quality = 0
	texture_quality = 0
	msaa_quality = 0
	fxaa_enabled = false
	ssaa_scale = 0.75  # Render at 75% resolution
	gi_quality = 0
	volumetric_fog = false
	glow_enabled = false
	ssao_enabled = false
	ssr_enabled = false
	max_lights = 4
	target_fps = 0  # Unlimited
	vsync_enabled = false
	print("Applied ULTRA LOW preset - Target: 120+ FPS")

# LOW - High FPS (90+ target)
func _apply_low_settings():
	shadow_quality = 0
	texture_quality = 1
	msaa_quality = 0
	fxaa_enabled = true
	ssaa_scale = 1.0
	gi_quality = 0
	volumetric_fog = false
	glow_enabled = false
	ssao_enabled = false
	ssr_enabled = false
	max_lights = 6
	target_fps = 0
	vsync_enabled = false
	print("Applied LOW preset - Target: 90+ FPS")

# MEDIUM - Balanced (60 target)
func _apply_medium_settings():
	shadow_quality = 1
	texture_quality = 1
	msaa_quality = 1
	fxaa_enabled = true
	ssaa_scale = 1.0
	gi_quality = 1
	volumetric_fog = true
	glow_enabled = true
	ssao_enabled = false
	ssr_enabled = false
	max_lights = 8
	target_fps = 60
	vsync_enabled = true
	print("Applied MEDIUM preset - Target: 60 FPS")

# HIGH - Quality (60 target)
func _apply_high_settings():
	shadow_quality = 2
	texture_quality = 2
	msaa_quality = 2
	fxaa_enabled = true
	ssaa_scale = 1.0
	gi_quality = 2
	volumetric_fog = true
	glow_enabled = true
	ssao_enabled = true
	ssr_enabled = false
	max_lights = 12
	target_fps = 60
	vsync_enabled = true
	print("Applied HIGH preset - Target: 60 FPS")

# ULTRA - Maximum Quality
func _apply_ultra_settings():
	shadow_quality = 3
	texture_quality = 2
	msaa_quality = 3
	fxaa_enabled = true
	ssaa_scale = 1.0
	gi_quality = 2
	volumetric_fog = true
	glow_enabled = true
	ssao_enabled = true
	ssr_enabled = true
	max_lights = 16
	target_fps = 60
	vsync_enabled = true
	print("Applied ULTRA preset - Target: 45+ FPS")

# Apply all settings to engine
func _apply_all_settings():
	_apply_shadow_settings()
	_apply_aa_settings()
	_apply_gi_settings()
	_apply_post_processing()
	_apply_resolution_scale()
	_apply_vsync()
	_apply_fps_limit()
	
	print("Graphics settings applied successfully")

func _apply_shadow_settings():
	var viewport = get_viewport()
	if not viewport:
		return
	
	match shadow_quality:
		0:  # Off
			RenderingServer.directional_shadow_atlas_set_size(512, false)
			RenderingServer.set_default_clear_color(Color(0.1, 0.1, 0.15))
		1:  # Low
			RenderingServer.directional_shadow_atlas_set_size(2048, false)
		2:  # Medium
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
		3:  # High
			RenderingServer.directional_shadow_atlas_set_size(8192, true)

func _apply_aa_settings():
	var viewport = get_viewport()
	if not viewport:
		return
	
	# MSAA
	match msaa_quality:
		0:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		1:
			viewport.msaa_3d = Viewport.MSAA_2X
		2:
			viewport.msaa_3d = Viewport.MSAA_4X
		3:
			viewport.msaa_3d = Viewport.MSAA_8X
	
	# FXAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa_enabled else Viewport.SCREEN_SPACE_AA_DISABLED

func _apply_gi_settings():
	# Global Illumination settings
	match gi_quality:
		0:  # Off
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", true)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 1)
		1:  # Low
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", true)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 1)
		2:  # High
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", false)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 2)

func _apply_post_processing():
	var viewport = get_viewport()
	if not viewport:
		return
	
	# Glow
	viewport.use_debanding = glow_enabled
	
	# Note: SSAO, SSR need to be set in WorldEnvironment
	# This is a placeholder for those settings

func _apply_resolution_scale():
	var viewport = get_viewport()
	if not viewport:
		return
	
	# Render scale for performance
	viewport.scaling_3d_scale = ssaa_scale
	
	if ssaa_scale < 1.0:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

func _apply_vsync():
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply_fps_limit():
	if target_fps > 0:
		Engine.max_fps = target_fps
	else:
		Engine.max_fps = 0  # Unlimited

# Individual setting changes
func set_shadow_quality(quality: int):
	shadow_quality = quality
	_apply_shadow_settings()
	current_preset = QualityPreset.CUSTOM
	save_settings()

func set_texture_quality(quality: int):
	texture_quality = quality
	current_preset = QualityPreset.CUSTOM
	save_settings()

func set_msaa_quality(quality: int):
	msaa_quality = quality
	_apply_aa_settings()
	current_preset = QualityPreset.CUSTOM
	save_settings()

func set_resolution_scale(scale: float):
	ssaa_scale = clamp(scale, 0.5, 2.0)
	_apply_resolution_scale()
	current_preset = QualityPreset.CUSTOM
	save_settings()

func set_target_fps(fps: int):
	target_fps = fps
	_apply_fps_limit()
	save_settings()

func set_vsync(enabled: bool):
	vsync_enabled = enabled
	_apply_vsync()
	save_settings()

# Save/Load settings
func save_settings():
	var config = ConfigFile.new()
	
	config.set_value("graphics", "preset", current_preset)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("graphics", "texture_quality", texture_quality)
	config.set_value("graphics", "msaa_quality", msaa_quality)
	config.set_value("graphics", "fxaa_enabled", fxaa_enabled)
	config.set_value("graphics", "ssaa_scale", ssaa_scale)
	config.set_value("graphics", "gi_quality", gi_quality)
	config.set_value("graphics", "target_fps", target_fps)
	config.set_value("graphics", "vsync_enabled", vsync_enabled)
	
	config.save("user://graphics_settings.cfg")
	print("Graphics settings saved")

func load_settings():
	var config = ConfigFile.new()
	var err = config.load("user://graphics_settings.cfg")
	
	if err != OK:
		print("No saved settings, using defaults")
		apply_preset(QualityPreset.MEDIUM)
		return
	
	current_preset = config.get_value("graphics", "preset", QualityPreset.MEDIUM)
	shadow_quality = config.get_value("graphics", "shadow_quality", 1)
	texture_quality = config.get_value("graphics", "texture_quality", 1)
	msaa_quality = config.get_value("graphics", "msaa_quality", 1)
	fxaa_enabled = config.get_value("graphics", "fxaa_enabled", true)
	ssaa_scale = config.get_value("graphics", "ssaa_scale", 1.0)
	gi_quality = config.get_value("graphics", "gi_quality", 1)
	target_fps = config.get_value("graphics", "target_fps", 60)
	vsync_enabled = config.get_value("graphics", "vsync_enabled", true)
	
	_apply_all_settings()
	print("Graphics settings loaded")

# Auto-detect best preset based on hardware
func auto_detect_preset():
	# Simple heuristic based on rendering performance
	var test_fps = Engine.get_frames_per_second()
	
	if test_fps >= 90:
		apply_preset(QualityPreset.HIGH)
	elif test_fps >= 60:
		apply_preset(QualityPreset.MEDIUM)
	elif test_fps >= 45:
		apply_preset(QualityPreset.LOW)
	else:
		apply_preset(QualityPreset.ULTRA_LOW)
	
	print("Auto-detected preset based on performance")

# Get preset name
func get_preset_name(preset: QualityPreset) -> String:
	match preset:
		QualityPreset.ULTRA_LOW: return "Ultra Low (120+ FPS)"
		QualityPreset.LOW: return "Low (90+ FPS)"
		QualityPreset.MEDIUM: return "Medium (60 FPS)"
		QualityPreset.HIGH: return "High (60 FPS)"
		QualityPreset.ULTRA: return "Ultra (45+ FPS)"
		QualityPreset.CUSTOM: return "Custom"
	return "Unknown"

