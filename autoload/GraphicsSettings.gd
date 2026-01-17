extends Node

# Advanced Graphics Settings System with comprehensive AAA-quality options

enum QualityPreset {
	POTATO,         # Absolute minimum for potato PCs more as a joke
	ULTRA_LOW,      # Maximum FPS 
	LOW,            # High FPS 
	MEDIUM,         # Balanced 
	HIGH,           # Quality 
	ULTRA,          # Maximum Quality 
	PAID_FOR_WHOLE_PC,  # I paid for the whole PC - MAX EVERYTHING
	CUSTOM          # User-defined
}

enum AAMode {
	DISABLED,
	FXAA,
	SMAA,
	TAA_FXAA,
	TAA_SMAA
}

enum ScalingMode {
	BILINEAR,
	FSR1,
	FSR2
}

enum TonemapMode {
	LINEAR,
	REINHARD,
	FILMIC,
	ACES
}

# Current settings
var current_preset := QualityPreset.HIGH
var target_fps := 0  # 0 = unlimited
var vsync_enabled := true

# Anti-Aliasing settings
var msaa_quality := 2  # 0=Off, 1=2x, 2=4x, 3=8x
var aa_mode := AAMode.TAA_SMAA
var taa_enabled := true
var screen_space_aa := 1  # 0=Off, 1=FXAA

# Resolution scaling
var scaling_mode := ScalingMode.BILINEAR
var render_scale := 1.0  # 0.5 - 2.0

# Shadow settings
var shadow_quality := 2  # 0=Off, 1=Low, 2=Medium, 3=High
var shadow_distance := 200.0

# Global Illumination
var gi_quality := 2  # 0=Off, 1=Low, 2=High
var sdfgi_enabled := true
var ssil_enabled := true

# Screen-Space effects
var ssao_enabled := true
var ssao_quality := 1  # 0=Low, 1=Medium, 2=High
var ssr_enabled := true
var ssr_quality := 1  # 0=Low, 1=Medium, 2=High

# Post-processing
var tonemap_mode := TonemapMode.ACES
var bloom_enabled := true
var bloom_intensity := 0.8
var volumetric_fog_enabled := true
var clouds_enabled := true  # Enable/disable clouds in sky shader
var dof_enabled := false
var motion_blur_enabled := false

# Texture quality
var texture_quality := 2  # 0=Low, 1=Medium, 2=High
var max_lights := 12

# UI settings
var show_fps_counter := true

signal settings_changed

# Flag to prevent switching to Custom when loading settings or applying preset
var _applying_preset := false

# Debounce system to prevent rapid setting changes from crashing
var _apply_pending := false
var _apply_timer: Timer = null
const DEBOUNCE_TIME := 0.1  # 100ms debounce
var _is_applying := false  # Prevent re-entry during apply

# Default values for reset
const DEFAULTS = {
	"preset": QualityPreset.HIGH,
	"target_fps": 0,
	"vsync_enabled": true,
	"msaa_quality": 2,
	"aa_mode": AAMode.TAA_SMAA,
	"taa_enabled": true,
	"screen_space_aa": 1,
	"scaling_mode": ScalingMode.BILINEAR,
	"render_scale": 1.0,
	"shadow_quality": 2,
	"shadow_distance": 200.0,
	"gi_quality": 2,
	"sdfgi_enabled": true,
	"ssil_enabled": true,
	"ssao_enabled": true,
	"ssao_quality": 1,
	"ssr_enabled": true,
	"ssr_quality": 1,
	"tonemap_mode": TonemapMode.ACES,
	"bloom_enabled": true,
	"bloom_intensity": 0.8,
	"volumetric_fog_enabled": true,
	"clouds_enabled": true,
	"dof_enabled": false,
	"motion_blur_enabled": false,
	"texture_quality": 2,
	"max_lights": 12,
	"show_fps_counter": true
}

func _ready():
	# Create debounce timer
	_apply_timer = Timer.new()
	_apply_timer.one_shot = true
	_apply_timer.wait_time = DEBOUNCE_TIME
	_apply_timer.timeout.connect(_on_debounce_timeout)
	add_child(_apply_timer)
	
	print("GraphicsSettings initialized")
	load_settings()


# Debounced apply - batches rapid changes
func _apply_settings_debounced():
	if _is_applying:
		return
	_apply_pending = true
	_apply_timer.start()


func _on_debounce_timeout():
	if _apply_pending:
		_apply_pending = false
		_apply_all_settings()

# Reset all settings to default
func reset_to_defaults():
	current_preset = DEFAULTS["preset"]
	target_fps = DEFAULTS["target_fps"]
	vsync_enabled = DEFAULTS["vsync_enabled"]
	msaa_quality = DEFAULTS["msaa_quality"]
	aa_mode = DEFAULTS["aa_mode"]
	taa_enabled = DEFAULTS["taa_enabled"]
	screen_space_aa = DEFAULTS["screen_space_aa"]
	scaling_mode = DEFAULTS["scaling_mode"]
	render_scale = DEFAULTS["render_scale"]
	shadow_quality = DEFAULTS["shadow_quality"]
	shadow_distance = DEFAULTS["shadow_distance"]
	gi_quality = DEFAULTS["gi_quality"]
	sdfgi_enabled = DEFAULTS["sdfgi_enabled"]
	ssil_enabled = DEFAULTS["ssil_enabled"]
	ssao_enabled = DEFAULTS["ssao_enabled"]
	ssao_quality = DEFAULTS["ssao_quality"]
	ssr_enabled = DEFAULTS["ssr_enabled"]
	ssr_quality = DEFAULTS["ssr_quality"]
	tonemap_mode = DEFAULTS["tonemap_mode"]
	bloom_enabled = DEFAULTS["bloom_enabled"]
	bloom_intensity = DEFAULTS["bloom_intensity"]
	volumetric_fog_enabled = DEFAULTS["volumetric_fog_enabled"]
	dof_enabled = DEFAULTS["dof_enabled"]
	motion_blur_enabled = DEFAULTS["motion_blur_enabled"]
	texture_quality = DEFAULTS["texture_quality"]
	max_lights = DEFAULTS["max_lights"]
	show_fps_counter = DEFAULTS["show_fps_counter"]
	
	_apply_all_settings()
	save_settings()
	settings_changed.emit()
	print("Graphics settings reset to defaults")

# Apply preset
func apply_preset(preset: QualityPreset):
	_applying_preset = true
	current_preset = preset
	
	match preset:
		QualityPreset.POTATO:
			_apply_potato_settings()
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
		QualityPreset.PAID_FOR_WHOLE_PC:
			_apply_paid_for_whole_pc_settings()
	
	_apply_all_settings()
	save_settings()
	_applying_preset = false
	settings_changed.emit()

# POTATO - Absolute bare minimum for the weakest PCs
func _apply_potato_settings():
	shadow_quality = 0
	shadow_distance = 0.0
	texture_quality = 0
	msaa_quality = 0
	aa_mode = AAMode.DISABLED
	taa_enabled = false
	screen_space_aa = 0
	scaling_mode = ScalingMode.BILINEAR  # Bilinear is cheaper than FSR
	render_scale = 0.25  # Render at 25% resolution (very low)
	gi_quality = 0
	sdfgi_enabled = false
	ssil_enabled = false
	ssao_enabled = false
	ssr_enabled = false
	volumetric_fog_enabled = false
	bloom_enabled = false
	tonemap_mode = TonemapMode.LINEAR
	dof_enabled = false
	motion_blur_enabled = false
	max_lights = 1  # Only 1 light
	target_fps = 0  # No FPS cap
	vsync_enabled = false
	print("Applied POTATO preset")

# ULTRA LOW - Maximum FPS (120+ target)
func _apply_ultra_low_settings():
	shadow_quality = 0
	shadow_distance = 50.0
	texture_quality = 0
	msaa_quality = 0
	aa_mode = AAMode.DISABLED
	taa_enabled = false
	screen_space_aa = 0
	scaling_mode = ScalingMode.FSR1
	render_scale = 0.7
	gi_quality = 0
	sdfgi_enabled = false
	ssil_enabled = false
	ssao_enabled = false
	ssr_enabled = false
	volumetric_fog_enabled = false
	bloom_enabled = false
	dof_enabled = false
	motion_blur_enabled = false
	max_lights = 4
	target_fps = 0
	vsync_enabled = false
	print("Applied ULTRA LOW preset")

# LOW - High FPS (90+ target)
func _apply_low_settings():
	shadow_quality = 1
	shadow_distance = 100.0
	texture_quality = 1
	msaa_quality = 0
	aa_mode = AAMode.FXAA
	taa_enabled = false
	screen_space_aa = 1
	scaling_mode = ScalingMode.BILINEAR
	render_scale = 1.0
	gi_quality = 0
	sdfgi_enabled = false
	ssil_enabled = false
	ssao_enabled = false
	ssr_enabled = false
	volumetric_fog_enabled = false
	bloom_enabled = true
	bloom_intensity = 0.5
	dof_enabled = false
	motion_blur_enabled = false
	max_lights = 6
	target_fps = 0
	vsync_enabled = false
	print("Applied LOW preset")

# MEDIUM - Balanced (60 target)
func _apply_medium_settings():
	shadow_quality = 1
	shadow_distance = 150.0
	texture_quality = 1
	msaa_quality = 1
	aa_mode = AAMode.TAA_FXAA
	taa_enabled = true
	screen_space_aa = 1
	scaling_mode = ScalingMode.BILINEAR
	render_scale = 1.0
	gi_quality = 1
	sdfgi_enabled = true
	ssil_enabled = false
	ssao_enabled = true
	ssao_quality = 0
	ssr_enabled = false
	volumetric_fog_enabled = true
	bloom_enabled = true
	bloom_intensity = 0.6
	dof_enabled = false
	motion_blur_enabled = false
	max_lights = 8
	target_fps = 0  # No FPS cap
	vsync_enabled = true
	print("Applied MEDIUM preset")

# HIGH - Quality (60 target) - DEFAULT
func _apply_high_settings():
	shadow_quality = 2
	shadow_distance = 200.0
	texture_quality = 2
	msaa_quality = 2
	aa_mode = AAMode.TAA_SMAA
	taa_enabled = true
	screen_space_aa = 1
	scaling_mode = ScalingMode.BILINEAR
	render_scale = 1.0
	gi_quality = 2
	sdfgi_enabled = true
	ssil_enabled = true
	ssao_enabled = true
	ssao_quality = 1
	ssr_enabled = true
	ssr_quality = 1
	volumetric_fog_enabled = true
	bloom_enabled = true
	bloom_intensity = 0.8
	tonemap_mode = TonemapMode.ACES
	dof_enabled = false
	motion_blur_enabled = false
	max_lights = 12
	target_fps = 0
	vsync_enabled = true
	print("Applied HIGH preset")

# ULTRA - Maximum Quality
func _apply_ultra_settings():
	shadow_quality = 3
	shadow_distance = 300.0
	texture_quality = 2
	msaa_quality = 3
	aa_mode = AAMode.TAA_SMAA
	taa_enabled = true
	screen_space_aa = 1
	scaling_mode = ScalingMode.BILINEAR
	render_scale = 1.0
	gi_quality = 2
	sdfgi_enabled = true
	ssil_enabled = true
	ssao_enabled = true
	ssao_quality = 2
	ssr_enabled = true
	ssr_quality = 2
	volumetric_fog_enabled = true
	bloom_enabled = true
	bloom_intensity = 1.0
	tonemap_mode = TonemapMode.ACES
	dof_enabled = true
	motion_blur_enabled = true
	max_lights = 16
	target_fps = 0
	vsync_enabled = true
	print("Applied ULTRA preset")

# I PAID FOR THE WHOLE PC - ABSOLUTE MAXIMUM EVERYTHING
func _apply_paid_for_whole_pc_settings():
	shadow_quality = 3  # Maximum shadows
	shadow_distance = 500.0  # See shadows from far away
	texture_quality = 2  # Maximum textures
	msaa_quality = 3  # 8x MSAA - the works
	aa_mode = AAMode.TAA_SMAA
	taa_enabled = true  # TAA on
	screen_space_aa = 1  # FXAA on top
	scaling_mode = ScalingMode.BILINEAR
	render_scale = 2.0  # SUPERSAMPLING - render at 200% resolution!
	gi_quality = 2  # Maximum GI
	sdfgi_enabled = true  # Full SDFGI
	ssil_enabled = true  # Full SSIL
	ssao_enabled = true  # Full SSAO
	ssao_quality = 2  # Maximum SSAO
	ssr_enabled = true  # Full SSR
	ssr_quality = 2  # Maximum SSR
	volumetric_fog_enabled = true  # Full volumetric fog
	bloom_enabled = true  # Full bloom
	bloom_intensity = 1.2  # Extra bloom
	tonemap_mode = TonemapMode.ACES  # Cinematic tonemapping
	dof_enabled = true  # Depth of field
	motion_blur_enabled = true  # Motion blur
	max_lights = 32  # Maximum lights
	target_fps = 0  # Unlimited FPS
	vsync_enabled = false  # No VSync - let it rip!
	print("Applied I PAID FOR THE WHOLE PC preset")

# Apply all settings to engine
func _apply_all_settings():
	# Prevent re-entry which can cause crashes
	if _is_applying:
		_apply_pending = true  # Queue another apply
		return
	
	_is_applying = true
	
	_apply_aa_settings()
	_apply_shadow_settings()
	_apply_gi_settings()
	_apply_resolution_scale()
	_apply_vsync()
	_apply_fps_limit()
	_apply_environment_settings()
	_apply_performance_settings()
	_apply_sky_shader_settings()
	
	# Save after applying all settings
	save_settings()
	
	_is_applying = false
	print("Graphics settings applied successfully")
	
	# If another apply was requested during this one, do it now (debounced)
	if _apply_pending:
		_apply_pending = false
		_apply_settings_debounced()

func _apply_performance_settings():
	var viewport = get_viewport()
	if not viewport:
		return
	
	# Potato mode specific optimizations
	if current_preset == QualityPreset.POTATO:
		# Disable occlusion culling (CPU overhead not worth it on weak CPUs)
		viewport.use_occlusion_culling = false
		# Disable XR (just in case)
		viewport.use_xr = false
		# Reduce texture filtering
		viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	else:
		viewport.use_occlusion_culling = true
		viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	
	# Enable/disable AdaptivePerformance based on preset
	_apply_adaptive_performance_settings()
	
	# Enable/disable aggressive ViewCulling based on preset
	_apply_view_culling_settings()


func _apply_adaptive_performance_settings():
	# Auto-enable adaptive performance for lower presets that have a target FPS
	match current_preset:
		QualityPreset.POTATO:
			AdaptivePerformance.enable_adaptive_performance(30)
		QualityPreset.ULTRA_LOW:
			AdaptivePerformance.enable_adaptive_performance(120)
		QualityPreset.LOW:
			AdaptivePerformance.enable_adaptive_performance(90)
		QualityPreset.MEDIUM:
			AdaptivePerformance.enable_adaptive_performance(60)
		_:
			# HIGH, ULTRA, PAID_FOR_WHOLE_PC, CUSTOM - user wants quality, disable adaptive
			AdaptivePerformance.disable_adaptive_performance()


func _apply_view_culling_settings():
	# Enable aggressive culling for low-end presets
	match current_preset:
		QualityPreset.POTATO, QualityPreset.ULTRA_LOW:
			ViewCulling.enable_aggressive_culling()
		_:
			ViewCulling.disable_aggressive_culling()


func _apply_sky_shader_settings():
	# Find the sky shader and adjust quality based on preset
	# The atmosphere shader is VERY expensive - 64 samples, 64 cloud marches, 8 light marches
	# Use call_deferred to avoid issues during rapid setting changes
	call_deferred("_apply_sky_shader_settings_deferred")


func _apply_sky_shader_settings_deferred():
	var tree = get_tree()
	if not tree or not tree.current_scene:
		return
	
	# Find WorldEnvironment node - use a safer approach
	var world_envs = tree.current_scene.find_children("*", "WorldEnvironment", true, false)
	if world_envs.is_empty():
		return
	
	var world_env: WorldEnvironment = world_envs[0]
	if not is_instance_valid(world_env):
		return
	if not world_env.environment or not world_env.environment.sky:
		return
	
	var sky: Sky = world_env.environment.sky
	if not sky.sky_material:
		return
	
	var sky_mat = sky.sky_material
	if not is_instance_valid(sky_mat):
		return
	
	# Get shader quality settings based on preset
	var atmosphere_samples: int
	var cloud_marches: int
	var light_marches: int
	
	match current_preset:
		QualityPreset.POTATO:
			atmosphere_samples = 16
			cloud_marches = 8
			light_marches = 4
		QualityPreset.ULTRA_LOW:
			atmosphere_samples = 24
			cloud_marches = 12
			light_marches = 4
		QualityPreset.LOW:
			atmosphere_samples = 32
			cloud_marches = 16
			light_marches = 6
		QualityPreset.MEDIUM:
			atmosphere_samples = 48
			cloud_marches = 32
			light_marches = 6
		QualityPreset.HIGH:
			atmosphere_samples = 64
			cloud_marches = 48
			light_marches = 8
		_:  # ULTRA, PAID_FOR_WHOLE_PC
			atmosphere_samples = 64
			cloud_marches = 64
			light_marches = 8
	
	# Apply shader parameters if it's a ShaderMaterial
	if sky_mat is ShaderMaterial:
		# Use the correct quality parameter names that the shader actually uses
		sky_mat.set_shader_parameter("quality_atmosphere_samples", atmosphere_samples)
		
		# When clouds disabled, minimize computation
		if clouds_enabled:
			sky_mat.set_shader_parameter("quality_cloud_marches", cloud_marches)
			sky_mat.set_shader_parameter("quality_light_marches", light_marches)
			sky_mat.set_shader_parameter("coverage", 0.35)  # Default coverage
			sky_mat.set_shader_parameter("use_cirrus", true)  # Enable cirrus clouds
		else:
			# Set coverage to 0 - shader will early-exit and skip cloud raymarching entirely
			sky_mat.set_shader_parameter("quality_cloud_marches", 1)  # Minimum iterations (fallback)
			sky_mat.set_shader_parameter("quality_light_marches", 1)  # Minimum iterations (fallback)
			sky_mat.set_shader_parameter("coverage", 0.0)  # Triggers early-exit in shader
			sky_mat.set_shader_parameter("use_cirrus", false)  # Disable cirrus clouds


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
	
	# TAA
	viewport.use_taa = taa_enabled
	
	# Screen Space AA (FXAA/SMAA)
	match screen_space_aa:
		0:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1:
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	
	# Debanding - disable for potato mode to save GPU
	viewport.use_debanding = current_preset != QualityPreset.POTATO
	
	print("AA Settings: MSAA=%d, TAA=%s, ScreenAA=%d" % [msaa_quality, taa_enabled, screen_space_aa])

func _apply_shadow_settings():
	var viewport = get_viewport()
	if not viewport:
		return
	
	match shadow_quality:
		0:  # Off
			viewport.positional_shadow_atlas_size = 0
			RenderingServer.directional_shadow_atlas_set_size(512, false)
			print("Shadows: OFF")
		1:  # Low
			viewport.positional_shadow_atlas_size = 2048
			viewport.positional_shadow_atlas_16_bits = true
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			print("Shadows: LOW (2048)")
		2:  # Medium
			viewport.positional_shadow_atlas_size = 4096
			viewport.positional_shadow_atlas_16_bits = false
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
			print("Shadows: MEDIUM (4096)")
		3:  # High
			viewport.positional_shadow_atlas_size = 8192
			viewport.positional_shadow_atlas_16_bits = false
			RenderingServer.directional_shadow_atlas_set_size(8192, false)
			print("Shadows: HIGH (8192)")

func _apply_gi_settings():
	match gi_quality:
		0:  # Off
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", true)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 0)
		1:  # Low
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", true)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 1)
		2:  # High
			ProjectSettings.set_setting("rendering/global_illumination/gi/use_half_resolution", false)
			ProjectSettings.set_setting("rendering/global_illumination/sdfgi/probe_ray_count", 2)

func _apply_resolution_scale():
	var viewport = get_viewport()
	if not viewport:
		return
	
	viewport.scaling_3d_scale = render_scale
	
	match scaling_mode:
		ScalingMode.BILINEAR:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		ScalingMode.FSR1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		ScalingMode.FSR2:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	
	# Mesh LOD bias - higher = use lower detail meshes sooner
	if current_preset == QualityPreset.POTATO:
		viewport.mesh_lod_threshold = 8.0  # Very aggressive LOD
	elif current_preset == QualityPreset.ULTRA_LOW:
		viewport.mesh_lod_threshold = 4.0
	elif current_preset == QualityPreset.LOW:
		viewport.mesh_lod_threshold = 2.0
	else:
		viewport.mesh_lod_threshold = 1.0  # Default
	
	print("Resolution Scale: %.0f%%, Mode: %d" % [render_scale * 100, scaling_mode])

func _apply_vsync():
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _apply_fps_limit():
	Engine.max_fps = target_fps if target_fps > 0 else 0

func _apply_environment_settings():
	# Find and update WorldEnvironment if exists
	var world_env = _find_world_environment()
	if world_env and world_env.environment:
		var env = world_env.environment
		
		# SSAO
		env.ssao_enabled = ssao_enabled
		if ssao_enabled:
			match ssao_quality:
				0:  # Low
					env.ssao_radius = 0.5
					env.ssao_intensity = 1.5
				1:  # Medium
					env.ssao_radius = 1.0
					env.ssao_intensity = 2.0
				2:  # High
					env.ssao_radius = 1.5
					env.ssao_intensity = 2.5
		
		# SSIL
		env.ssil_enabled = ssil_enabled
		
		# SSR
		env.ssr_enabled = ssr_enabled
		if ssr_enabled:
			match ssr_quality:
				0:  # Low
					env.ssr_max_steps = 32
				1:  # Medium
					env.ssr_max_steps = 64
				2:  # High
					env.ssr_max_steps = 128
		
		# SDFGI
		env.sdfgi_enabled = sdfgi_enabled
		
		# Bloom
		env.glow_enabled = bloom_enabled
		if bloom_enabled:
			env.glow_intensity = bloom_intensity
		
		# Volumetric Fog
		env.volumetric_fog_enabled = volumetric_fog_enabled
		
		# Tonemapping - use integer values directly for compatibility
		# 0 = Linear, 1 = Reinhard, 2 = Filmic, 3 = ACES
		env.tonemap_mode = tonemap_mode
		
		print("Environment settings applied")

func _find_world_environment() -> WorldEnvironment:
	var tree = get_tree()
	if tree and tree.current_scene:
		var world_envs = tree.current_scene.find_children("*", "WorldEnvironment", true, false)
		if world_envs.size() > 0:
			return world_envs[0]
	return null

# Individual setting setters - all use debounced apply to prevent crashes
# Only switch to Custom if user manually changed setting (not during preset apply)
func set_msaa_quality(quality: int):
	msaa_quality = quality
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_taa_enabled(enabled: bool):
	taa_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_screen_space_aa(mode: int):
	screen_space_aa = mode
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_shadow_quality(quality: int):
	shadow_quality = quality
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_scaling_mode(mode: int):
	scaling_mode = mode
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_render_scale(scale: float):
	render_scale = clamp(scale, 0.25, 2.0)
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_ssao_enabled(enabled: bool):
	ssao_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_ssil_enabled(enabled: bool):
	ssil_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_ssr_enabled(enabled: bool):
	ssr_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_sdfgi_enabled(enabled: bool):
	sdfgi_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_bloom_enabled(enabled: bool):
	bloom_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_bloom_intensity(intensity: float):
	bloom_intensity = clamp(intensity, 0.0, 2.0)
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_volumetric_fog_enabled(enabled: bool):
	volumetric_fog_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_clouds_enabled(enabled: bool):
	clouds_enabled = enabled
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_tonemap_mode(mode: int):
	tonemap_mode = mode
	if not _applying_preset:
		current_preset = QualityPreset.CUSTOM
	_apply_settings_debounced()
	settings_changed.emit()

func set_target_fps(fps: int):
	target_fps = fps
	_apply_fps_limit()
	save_settings()
	settings_changed.emit()

func set_vsync(enabled: bool):
	vsync_enabled = enabled
	_apply_vsync()
	save_settings()
	settings_changed.emit()

func set_show_fps_counter(enabled: bool):
	show_fps_counter = enabled
	save_settings()
	settings_changed.emit()

# Save/Load settings
func save_settings():
	var config = ConfigFile.new()
	
	config.set_value("graphics", "preset", current_preset)
	config.set_value("graphics", "target_fps", target_fps)
	config.set_value("graphics", "vsync_enabled", vsync_enabled)
	config.set_value("graphics", "msaa_quality", msaa_quality)
	config.set_value("graphics", "aa_mode", aa_mode)
	config.set_value("graphics", "taa_enabled", taa_enabled)
	config.set_value("graphics", "screen_space_aa", screen_space_aa)
	config.set_value("graphics", "scaling_mode", scaling_mode)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("graphics", "shadow_distance", shadow_distance)
	config.set_value("graphics", "gi_quality", gi_quality)
	config.set_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	config.set_value("graphics", "ssil_enabled", ssil_enabled)
	config.set_value("graphics", "ssao_enabled", ssao_enabled)
	config.set_value("graphics", "ssao_quality", ssao_quality)
	config.set_value("graphics", "ssr_enabled", ssr_enabled)
	config.set_value("graphics", "ssr_quality", ssr_quality)
	config.set_value("graphics", "tonemap_mode", tonemap_mode)
	config.set_value("graphics", "bloom_enabled", bloom_enabled)
	config.set_value("graphics", "bloom_intensity", bloom_intensity)
	config.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	config.set_value("graphics", "clouds_enabled", clouds_enabled)
	config.set_value("graphics", "dof_enabled", dof_enabled)
	config.set_value("graphics", "motion_blur_enabled", motion_blur_enabled)
	config.set_value("graphics", "texture_quality", texture_quality)
	config.set_value("graphics", "max_lights", max_lights)
	config.set_value("graphics", "show_fps_counter", show_fps_counter)
	
	config.save("user://graphics_settings.cfg")
	print("Graphics settings saved")

func load_settings():
	var config = ConfigFile.new()
	var err = config.load("user://graphics_settings.cfg")
	
	if err != OK:
		print("No saved settings, applying HIGH preset as default")
		apply_preset(QualityPreset.HIGH)
		return
	
	current_preset = config.get_value("graphics", "preset", QualityPreset.HIGH)
	target_fps = config.get_value("graphics", "target_fps", 0)
	vsync_enabled = config.get_value("graphics", "vsync_enabled", true)
	msaa_quality = config.get_value("graphics", "msaa_quality", 2)
	aa_mode = config.get_value("graphics", "aa_mode", AAMode.TAA_SMAA)
	taa_enabled = config.get_value("graphics", "taa_enabled", true)
	screen_space_aa = config.get_value("graphics", "screen_space_aa", 1)
	scaling_mode = config.get_value("graphics", "scaling_mode", ScalingMode.BILINEAR)
	render_scale = config.get_value("graphics", "render_scale", 1.0)
	shadow_quality = config.get_value("graphics", "shadow_quality", 2)
	shadow_distance = config.get_value("graphics", "shadow_distance", 200.0)
	gi_quality = config.get_value("graphics", "gi_quality", 2)
	sdfgi_enabled = config.get_value("graphics", "sdfgi_enabled", true)
	ssil_enabled = config.get_value("graphics", "ssil_enabled", true)
	ssao_enabled = config.get_value("graphics", "ssao_enabled", true)
	ssao_quality = config.get_value("graphics", "ssao_quality", 1)
	ssr_enabled = config.get_value("graphics", "ssr_enabled", true)
	ssr_quality = config.get_value("graphics", "ssr_quality", 1)
	tonemap_mode = config.get_value("graphics", "tonemap_mode", TonemapMode.ACES)
	bloom_enabled = config.get_value("graphics", "bloom_enabled", true)
	bloom_intensity = config.get_value("graphics", "bloom_intensity", 0.8)
	volumetric_fog_enabled = config.get_value("graphics", "volumetric_fog_enabled", true)
	clouds_enabled = config.get_value("graphics", "clouds_enabled", true)
	dof_enabled = config.get_value("graphics", "dof_enabled", false)
	motion_blur_enabled = config.get_value("graphics", "motion_blur_enabled", false)
	texture_quality = config.get_value("graphics", "texture_quality", 2)
	max_lights = config.get_value("graphics", "max_lights", 12)
	show_fps_counter = config.get_value("graphics", "show_fps_counter", true)
	
	_apply_all_settings()
	print("Graphics settings loaded")

# Auto-detect best preset based on hardware
func auto_detect_preset():
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
		QualityPreset.POTATO: return "Potato"
		QualityPreset.ULTRA_LOW: return "Ultra Low"
		QualityPreset.LOW: return "Low"
		QualityPreset.MEDIUM: return "Medium"
		QualityPreset.HIGH: return "High"
		QualityPreset.ULTRA: return "Ultra"
		QualityPreset.PAID_FOR_WHOLE_PC: return "I Paid For The Whole PC"
		QualityPreset.CUSTOM: return "Custom"
	return "Unknown"

func get_msaa_name(quality: int) -> String:
	match quality:
		0: return "Off"
		1: return "2x"
		2: return "4x"
		3: return "8x"
	return "Unknown"

func get_shadow_name(quality: int) -> String:
	match quality:
		0: return "Off"
		1: return "Low"
		2: return "Medium"
		3: return "High"
	return "Unknown"

func get_scaling_name(mode: int) -> String:
	match mode:
		ScalingMode.BILINEAR: return "Bilinear"
		ScalingMode.FSR1: return "FSR 1.0"
		ScalingMode.FSR2: return "FSR 2.0"
	return "Unknown"

func get_tonemap_name(mode: int) -> String:
	match mode:
		TonemapMode.LINEAR: return "Linear"
		TonemapMode.REINHARD: return "Reinhard"
		TonemapMode.FILMIC: return "Filmic"
		TonemapMode.ACES: return "ACES"
	return "Unknown"
