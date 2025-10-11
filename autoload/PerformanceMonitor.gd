extends Node

# Performance monitoring and optimization system

var _fps_history := []
var _fps_history_size := 60  # Track last 60 frames
var _frame_time_history := []
# var _network_stats := {}  # Reserved for future network monitoring

var _update_counter := 0
var _update_interval := 30  # Update stats every N frames

# Performance thresholds
const FPS_TARGET := 60.0
const FPS_WARNING := 45.0
const FPS_CRITICAL := 30.0

signal performance_warning(message: String)
signal performance_critical(message: String)

func _ready():
	print("PerformanceMonitor initialized")
	# Start monitoring
	set_process(true)

func _process(_delta):
	_update_counter += 1
	if _update_counter < _update_interval:
		return
	_update_counter = 0
	
	# Update performance metrics
	_update_fps_stats()
	_check_performance_thresholds()

func _update_fps_stats():
	var current_fps = Engine.get_frames_per_second()
	
	# Add to history
	_fps_history.append(current_fps)
	if _fps_history.size() > _fps_history_size:
		_fps_history.pop_front()
	
	# Track frame time
	var frame_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0  # ms
	_frame_time_history.append(frame_time)
	if _frame_time_history.size() > _fps_history_size:
		_frame_time_history.pop_front()

func _check_performance_thresholds():
	var avg_fps = get_average_fps()
	
	if avg_fps < FPS_CRITICAL:
		performance_critical.emit("Critical FPS drop: %.1f" % avg_fps)
	elif avg_fps < FPS_WARNING:
		performance_warning.emit("Low FPS warning: %.1f" % avg_fps)

func get_average_fps() -> float:
	if _fps_history.is_empty():
		return 0.0
	
	var sum := 0.0
	for fps in _fps_history:
		sum += fps
	return sum / _fps_history.size()

func get_average_frame_time() -> float:
	if _frame_time_history.is_empty():
		return 0.0
	
	var sum := 0.0
	for time in _frame_time_history:
		sum += time
	return sum / _frame_time_history.size()

func get_memory_usage() -> Dictionary:
	return {
		"static": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0 / 1024.0,  # MB
		"dynamic": Performance.get_monitor(Performance.OBJECT_COUNT),  # Object count as proxy
		"total": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0 / 1024.0  # MB
	}

func get_network_stats() -> Dictionary:
	if not multiplayer.has_multiplayer_peer():
		return {}
	
	return {
		"peers_connected": NetworkManager.players.size(),
		"is_server": multiplayer.is_server(),
		"unique_id": multiplayer.get_unique_id()
	}

func get_performance_report() -> String:
	var report := PackedStringArray()
	
	report.append("=== Performance Report ===")
	report.append("FPS: %.1f (avg: %.1f)" % [Engine.get_frames_per_second(), get_average_fps()])
	report.append("Frame Time: %.2f ms (avg: %.2f ms)" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		get_average_frame_time()
	])
	
	var memory = get_memory_usage()
	report.append("Memory: %.1f MB (Static: %.1f, Dynamic: %.1f)" % [
		memory.total, memory.static, memory.dynamic
	])
	
	report.append("Objects: %d" % Performance.get_monitor(Performance.OBJECT_COUNT))
	report.append("Nodes: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	
	var network = get_network_stats()
	if not network.is_empty():
		report.append("Network: %d peers, Server: %s" % [
			network.peers_connected,
			network.is_server
		])
	
	return "\n".join(report)

# Toggle FPS display
func toggle_fps_display():
	var tree = get_tree()
	if tree:
		tree.debug_collisions_hint = !tree.debug_collisions_hint

# Enable performance profiling
func enable_profiling():
	print("Performance profiling enabled")
	print(get_performance_report())
