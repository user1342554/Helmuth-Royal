extends Node

# Adaptive Performance System - Automatically adjusts quality for target FPS

var enabled := false
var target_fps := 60.0
var adjustment_interval := 2.0  # Check every N seconds
var fps_tolerance := 5.0  # FPS can vary by this amount

var _check_timer := 0.0
var _adjustment_cooldown := 0.0
var _cooldown_duration := 5.0  # Wait before next adjustment

enum AdjustmentLevel {
	NONE,
	MINOR,      # Small tweaks (shadows, effects)
	MODERATE,   # Medium changes (resolution scale)
	MAJOR       # Big changes (disable features)
}

func _ready():
	# Connect to PerformanceMonitor signals for immediate response to critical FPS drops
	PerformanceMonitor.performance_warning.connect(_on_performance_warning)
	PerformanceMonitor.performance_critical.connect(_on_performance_critical)
	print("AdaptivePerformance initialized")

func _process(delta):
	if not enabled:
		return
	
	_check_timer += delta
	_adjustment_cooldown -= delta
	
	if _check_timer >= adjustment_interval and _adjustment_cooldown <= 0:
		_check_timer = 0.0
		_check_and_adjust_performance()

func enable_adaptive_performance(target: int = 60):
	enabled = true
	target_fps = float(target)
	print("Adaptive Performance enabled - Target: %d FPS" % target)

func disable_adaptive_performance():
	enabled = false
	print("Adaptive Performance disabled")


func _on_performance_warning(message: String):
	# Warning signal - FPS dropped below 45
	if not enabled:
		return
	
	# Skip if we're in cooldown
	if _adjustment_cooldown > 0:
		return
	
	print("AdaptivePerformance: %s - applying minor reduction" % message)
	_apply_minor_reduction()
	_adjustment_cooldown = _cooldown_duration


func _on_performance_critical(message: String):
	# Critical signal - FPS dropped below 30, respond immediately
	if not enabled:
		return
	
	# Override cooldown for critical situations
	print("AdaptivePerformance: CRITICAL - %s - applying major reduction" % message)
	_apply_major_reduction()
	_adjustment_cooldown = _cooldown_duration * 2  # Longer cooldown after major change


func _check_and_adjust_performance():
	var avg_fps = PerformanceMonitor.get_average_fps()
	
	if avg_fps < target_fps - fps_tolerance:
		# FPS too low, reduce quality
		_reduce_quality(avg_fps)
		_adjustment_cooldown = _cooldown_duration
	elif avg_fps > target_fps + fps_tolerance + 15:
		# FPS significantly higher, can increase quality
		_increase_quality(avg_fps)
		_adjustment_cooldown = _cooldown_duration

func _reduce_quality(current_fps: float):
	var fps_deficit = target_fps - current_fps
	
	print("Adaptive: FPS too low (%.1f / %.1f), reducing quality..." % [current_fps, target_fps])
	
	if fps_deficit > 20:
		# Major adjustment needed
		_apply_major_reduction()
	elif fps_deficit > 10:
		# Moderate adjustment
		_apply_moderate_reduction()
	else:
		# Minor adjustment
		_apply_minor_reduction()

func _increase_quality(current_fps: float):
	print("Adaptive: FPS stable (%.1f / %.1f), trying to increase quality..." % [current_fps, target_fps])
	_apply_minor_increase()

func _apply_major_reduction():
	print("Adaptive: Applying MAJOR quality reduction")
	
	# Reduce resolution scale significantly
	var current_scale = GraphicsSettings.render_scale
	GraphicsSettings.set_render_scale(max(current_scale - 0.15, 0.5))
	
	# Disable expensive features
	GraphicsSettings.ssao_enabled = false
	GraphicsSettings.ssr_enabled = false
	GraphicsSettings.bloom_enabled = false
	GraphicsSettings.shadow_quality = max(GraphicsSettings.shadow_quality - 1, 0)
	
	GraphicsSettings._apply_all_settings()

func _apply_moderate_reduction():
	print("Adaptive: Applying MODERATE quality reduction")
	
	# Reduce resolution scale
	var current_scale = GraphicsSettings.render_scale
	GraphicsSettings.set_render_scale(max(current_scale - 0.1, 0.6))
	
	# Reduce shadow quality
	if GraphicsSettings.shadow_quality > 0:
		GraphicsSettings.set_shadow_quality(GraphicsSettings.shadow_quality - 1)

func _apply_minor_reduction():
	print("Adaptive: Applying MINOR quality reduction")
	
	# Disable less important effects
	if GraphicsSettings.ssr_enabled:
		GraphicsSettings.ssr_enabled = false
		GraphicsSettings._apply_all_settings()
	elif GraphicsSettings.ssao_enabled:
		GraphicsSettings.ssao_enabled = false
		GraphicsSettings._apply_all_settings()
	elif GraphicsSettings.bloom_enabled:
		GraphicsSettings.bloom_enabled = false
		GraphicsSettings._apply_all_settings()

func _apply_minor_increase():
	print("Adaptive: Applying MINOR quality increase")
	
	# Try to re-enable effects
	if not GraphicsSettings.bloom_enabled:
		GraphicsSettings.bloom_enabled = true
		GraphicsSettings._apply_all_settings()
	elif not GraphicsSettings.ssao_enabled and GraphicsSettings.shadow_quality >= 1:
		GraphicsSettings.ssao_enabled = true
		GraphicsSettings._apply_all_settings()
	elif GraphicsSettings.render_scale < 1.0:
		# Increase resolution scale slightly
		GraphicsSettings.set_render_scale(min(GraphicsSettings.render_scale + 0.05, 1.0))

