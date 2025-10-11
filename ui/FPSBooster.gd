extends Node

# FPS Booster - Einfache Aktivierung verschiedener Performance-Modi

enum PerformanceMode {
	MAXIMUM_FPS,      # 144+ FPS target
	HIGH_FPS,         # 120+ FPS target
	BALANCED,         # 90 FPS target
	QUALITY,          # 60 FPS target
	MAXIMUM_QUALITY   # Best visuals
}

func _ready():
	print("FPSBooster ready - Call activate_mode() to boost FPS")

# Hauptfunktion - Aktiviere einen Performance-Mode
func activate_mode(mode: PerformanceMode):
	match mode:
		PerformanceMode.MAXIMUM_FPS:
			_activate_maximum_fps()
		PerformanceMode.HIGH_FPS:
			_activate_high_fps()
		PerformanceMode.BALANCED:
			_activate_balanced()
		PerformanceMode.QUALITY:
			_activate_quality()
		PerformanceMode.MAXIMUM_QUALITY:
			_activate_maximum_quality()

# 🚀 MAXIMUM FPS MODE - 144+ FPS
func _activate_maximum_fps():
	print("=== ACTIVATING MAXIMUM FPS MODE ===")
	
	# Ultra Low Graphics
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.ULTRA_LOW)
	
	# Render at 75% resolution with FSR
	GraphicsSettings.set_resolution_scale(0.75)
	
	# Remove FPS limits
	GraphicsSettings.set_vsync(false)
	GraphicsSettings.set_target_fps(0)  # Unlimited
	
	# Aggressive culling
	ViewCulling.enable_aggressive_culling()
	
	# Adaptive performance with high target
	AdaptivePerformance.enable_adaptive_performance(144)
	
	# Reduce voice quality slightly
	VoiceChat._audio_send_rate = 3  # Every 3 frames instead of 2
	
	print("✅ MAXIMUM FPS MODE ACTIVE")
	print("🎯 Target: 144+ FPS")
	print("📊 Expected FPS: 150-250 (depending on hardware)")

# ⚡ HIGH FPS MODE - 120+ FPS  
func _activate_high_fps():
	print("=== ACTIVATING HIGH FPS MODE ===")
	
	# Low Graphics
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	
	# No VSync
	GraphicsSettings.set_vsync(false)
	GraphicsSettings.set_target_fps(0)
	
	# Normal culling
	ViewCulling.set_view_distance(100.0)
	
	# Adaptive performance
	AdaptivePerformance.enable_adaptive_performance(120)
	
	print("✅ HIGH FPS MODE ACTIVE")
	print("🎯 Target: 120+ FPS")

# ⚖️ BALANCED MODE - 90 FPS
func _activate_balanced():
	print("=== ACTIVATING BALANCED MODE ===")
	
	# Low-Medium Graphics
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	
	# Cap at 90 FPS
	GraphicsSettings.set_vsync(false)
	GraphicsSettings.set_target_fps(90)
	
	# Normal culling
	ViewCulling.set_view_distance(100.0)
	
	# Adaptive performance
	AdaptivePerformance.enable_adaptive_performance(90)
	
	print("✅ BALANCED MODE ACTIVE")
	print("🎯 Target: 90 FPS")

# 🎮 QUALITY MODE - 60 FPS
func _activate_quality():
	print("=== ACTIVATING QUALITY MODE ===")
	
	# Medium Graphics
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.MEDIUM)
	
	# Standard culling
	ViewCulling.set_view_distance(150.0)
	
	# Adaptive performance
	AdaptivePerformance.enable_adaptive_performance(60)
	
	print("✅ QUALITY MODE ACTIVE")
	print("🎯 Target: 60 FPS")

# 💎 MAXIMUM QUALITY MODE - Best visuals
func _activate_maximum_quality():
	print("=== ACTIVATING MAXIMUM QUALITY MODE ===")
	
	# High/Ultra Graphics
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	
	# Extended view distance
	ViewCulling.set_view_distance(200.0)
	
	# No adaptive (maintain quality)
	AdaptivePerformance.disable_adaptive_performance()
	
	print("✅ MAXIMUM QUALITY MODE ACTIVE")
	print("🎯 Target: 45+ FPS with best visuals")

# Quick activation functions
func enable_maximum_fps():
	activate_mode(PerformanceMode.MAXIMUM_FPS)

func enable_high_fps():
	activate_mode(PerformanceMode.HIGH_FPS)

func enable_balanced():
	activate_mode(PerformanceMode.BALANCED)

# Additional performance tweaks
func apply_extreme_optimizations():
	print("=== APPLYING EXTREME OPTIMIZATIONS ===")
	
	# Already have MAXIMUM_FPS active, go even further
	GraphicsSettings.set_resolution_scale(0.5)  # 50% resolution!
	
	# Ultra aggressive culling
	ViewCulling.player_cull_distance = 50.0
	ViewCulling._update_interval = 10  # Update more often
	
	# Reduce network overhead
	VoiceChat._audio_send_rate = 4
	VoiceChat._distance_check_interval = 20
	
	# Reduce UI updates
	var game_ui = get_tree().current_scene.get_node_or_null("GameUI")
	if game_ui and game_ui.has_method("set"):
		game_ui._debug_update_interval = 30
	
	print("✅ EXTREME OPTIMIZATIONS APPLIED")
	print("⚠️ Visual quality significantly reduced")
	print("🚀 MAXIMUM POSSIBLE FPS")

# Test function - cycles through modes
func test_all_modes():
	print("\n=== TESTING ALL PERFORMANCE MODES ===\n")
	
	for i in range(5):
		var mode = PerformanceMode.values()[i]
		activate_mode(mode)
		await get_tree().create_timer(5.0).timeout
		
		var fps = PerformanceMonitor.get_average_fps()
		print("Mode %d FPS: %.1f" % [i, fps])
	
	print("\n=== TEST COMPLETE ===\n")

# Auto-select best mode based on hardware
func auto_select_mode():
	print("=== AUTO-SELECTING BEST MODE ===")
	
	# Test FPS for a moment
	await get_tree().create_timer(2.0).timeout
	var test_fps = PerformanceMonitor.get_average_fps()
	
	print("Detected FPS: %.1f" % test_fps)
	
	if test_fps < 30:
		print("Low-end hardware detected")
		activate_mode(PerformanceMode.MAXIMUM_FPS)
		apply_extreme_optimizations()
	elif test_fps < 60:
		print("Mid-range hardware detected")
		activate_mode(PerformanceMode.HIGH_FPS)
	elif test_fps < 90:
		print("Good hardware detected")
		activate_mode(PerformanceMode.BALANCED)
	elif test_fps < 120:
		print("High-end hardware detected")
		activate_mode(PerformanceMode.QUALITY)
	else:
		print("Ultra high-end hardware detected")
		activate_mode(PerformanceMode.MAXIMUM_QUALITY)

