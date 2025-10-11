extends Node

# Performance optimization: Resource caching and preloading system

# Cache for frequently accessed resources
var _resource_cache := {}
var _loading_queue := []
var _is_loading := false

# Note: Using await for async loading instead of threads for simplicity
# Threading variables removed to avoid unused variable warnings

signal resource_loaded(resource_path: String, resource: Resource)
signal loading_progress(current: int, total: int)
signal all_resources_loaded

func _ready():
	print("ResourceLoader initialized")

# Preload resources at startup
func preload_resources(resource_paths: Array):
	for path in resource_paths:
		if not _resource_cache.has(path):
			_loading_queue.append(path)
	
	if _loading_queue.size() > 0:
		_start_loading()

# Load resource synchronously with caching
func load_resource(resource_path: String) -> Resource:
	# Check cache first
	if _resource_cache.has(resource_path):
		return _resource_cache[resource_path]
	
	# Load and cache
	var resource = load(resource_path)
	if resource:
		_resource_cache[resource_path] = resource
	
	return resource

# Load resource asynchronously
func load_resource_async(resource_path: String):
	# Check cache first
	if _resource_cache.has(resource_path):
		resource_loaded.emit(resource_path, _resource_cache[resource_path])
		return
	
	# Add to queue
	_loading_queue.append(resource_path)
	
	if not _is_loading:
		_start_loading()

func _start_loading():
	if _is_loading or _loading_queue.is_empty():
		return
	
	_is_loading = true
	_process_loading_queue()

func _process_loading_queue():
	var total = _loading_queue.size()
	var current = 0
	
	while not _loading_queue.is_empty():
		var path = _loading_queue.pop_front()
		current += 1
		
		# Load resource
		var resource = load(path)
		if resource:
			_resource_cache[path] = resource
			resource_loaded.emit(path, resource)
		
		loading_progress.emit(current, total)
		
		# Yield to prevent frame drops
		await get_tree().process_frame
	
	_is_loading = false
	all_resources_loaded.emit()

# Clear cache to free memory
func clear_cache():
	_resource_cache.clear()

# Remove specific resource from cache
func unload_resource(resource_path: String):
	if _resource_cache.has(resource_path):
		_resource_cache.erase(resource_path)

# Get cache size for debugging
func get_cache_size() -> int:
	return _resource_cache.size()

# Preload common game resources
func preload_game_resources():
	var resources_to_preload := [
		"res://player/Player.tscn",
		"res://ui/Toast.tscn",
		"res://world/Checkpoint.tscn"
	]
	preload_resources(resources_to_preload)

