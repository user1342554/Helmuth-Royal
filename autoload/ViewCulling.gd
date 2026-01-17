extends Node

# Advanced View Distance Culling System with LOD tiers for improved performance

enum CullLevel {
	FULL,       # Full detail - animations, physics, audio
	REDUCED,    # Reduced - simplified animations, full physics
	MINIMAL,    # Minimal - no animations, basic physics
	HIDDEN      # Hidden - invisible, no physics
}

var enabled := true
var max_view_distance := 100.0  # Maximum render distance
var player_cull_distance := 150.0  # Distance to cull other players
var aggressive_culling := false  # More aggressive culling for low-end

# LOD distance thresholds (squared for performance)
var lod_near_distance := 30.0      # Full detail within this range
var lod_medium_distance := 60.0    # Reduced detail
var lod_far_distance := 100.0      # Minimal detail
var audio_cull_distance := 80.0    # Distance to cull 3D audio

var _update_counter := 0
var _update_interval := 30  # Check every N frames
var _player_cull_levels: Dictionary = {}  # peer_id -> CullLevel

func _ready():
	print("ViewCulling initialized")

func _process(_delta):
	if not enabled:
		return
	
	_update_counter += 1
	if _update_counter < _update_interval:
		return
	_update_counter = 0
	
	_update_visibility()

func _update_visibility():
	var local_player = NetworkManager.get_local_player()
	if not local_player:
		return
	
	var local_pos = local_player.global_position
	
	# Pre-calculate squared distances for performance
	var near_sq := lod_near_distance * lod_near_distance
	var medium_sq := lod_medium_distance * lod_medium_distance
	var far_sq := lod_far_distance * lod_far_distance
	var cull_sq := player_cull_distance * player_cull_distance
	var audio_sq := audio_cull_distance * audio_cull_distance
	
	# Cull remote players based on distance with LOD tiers
	for peer_id in NetworkManager.players.keys():
		if peer_id == multiplayer.get_unique_id():
			continue
		
		var player = NetworkManager.get_player(peer_id)
		if not player:
			continue
		
		var distance_sq = local_pos.distance_squared_to(player.global_position)
		var new_level := _get_cull_level(distance_sq, near_sq, medium_sq, far_sq, cull_sq)
		var old_level: CullLevel = _player_cull_levels.get(peer_id, CullLevel.FULL)
		
		# Only update if level changed
		if new_level != old_level:
			_apply_cull_level(player, new_level, old_level)
			_player_cull_levels[peer_id] = new_level
		
		# Audio culling (separate from visual LOD)
		_update_audio_culling(player, distance_sq, audio_sq)


func _get_cull_level(distance_sq: float, near_sq: float, medium_sq: float, far_sq: float, cull_sq: float) -> CullLevel:
	if distance_sq > cull_sq:
		return CullLevel.HIDDEN
	elif distance_sq > far_sq:
		return CullLevel.MINIMAL
	elif distance_sq > medium_sq:
		return CullLevel.REDUCED
	else:
		return CullLevel.FULL


func _apply_cull_level(player: Node3D, new_level: CullLevel, old_level: CullLevel) -> void:
	match new_level:
		CullLevel.HIDDEN:
			player.visible = false
			player.set_physics_process(false)
			_set_collision_enabled(player, false)
		
		CullLevel.MINIMAL:
			player.visible = true
			player.set_physics_process(false)  # No physics for distant players
			_set_collision_enabled(player, false)  # No collision checks
			_set_animation_enabled(player, false)
		
		CullLevel.REDUCED:
			player.visible = true
			player.set_physics_process(true)
			_set_collision_enabled(player, true)
			_set_animation_enabled(player, false)  # Skip animations at medium distance
		
		CullLevel.FULL:
			player.visible = true
			player.set_physics_process(true)
			_set_collision_enabled(player, true)
			_set_animation_enabled(player, true)


func _set_collision_enabled(player: Node3D, enabled_flag: bool) -> void:
	# Find and toggle collision shape
	var collision_shape = player.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = not enabled_flag


func _set_animation_enabled(player: Node3D, enabled_flag: bool) -> void:
	# Find and toggle animation player if exists
	var anim_player = player.get_node_or_null("AnimationPlayer")
	if anim_player:
		if enabled_flag:
			anim_player.play()
		else:
			anim_player.pause()


func _update_audio_culling(player: Node3D, distance_sq: float, audio_sq: float) -> void:
	# Find all AudioStreamPlayer3D children and cull them
	for child in player.get_children():
		if child is AudioStreamPlayer3D:
			if distance_sq > audio_sq:
				if child.playing:
					child.stream_paused = true
			else:
				if child.stream_paused:
					child.stream_paused = false

func set_view_distance(distance: float):
	max_view_distance = distance
	player_cull_distance = distance * 1.5
	# Scale LOD distances proportionally
	lod_near_distance = distance * 0.3
	lod_medium_distance = distance * 0.6
	lod_far_distance = distance
	audio_cull_distance = distance * 0.8
	print("View distance set to: %.1f" % distance)


func enable_aggressive_culling():
	aggressive_culling = true
	max_view_distance = 50.0
	player_cull_distance = 75.0
	lod_near_distance = 15.0
	lod_medium_distance = 30.0
	lod_far_distance = 50.0
	audio_cull_distance = 40.0
	_update_interval = 15  # Update more frequently
	print("Aggressive culling enabled")


func disable_aggressive_culling():
	aggressive_culling = false
	max_view_distance = 100.0
	player_cull_distance = 150.0
	lod_near_distance = 30.0
	lod_medium_distance = 60.0
	lod_far_distance = 100.0
	audio_cull_distance = 80.0
	_update_interval = 30
	print("Aggressive culling disabled")


## Get current cull level for a player (for debugging/UI)
func get_player_cull_level(peer_id: int) -> CullLevel:
	return _player_cull_levels.get(peer_id, CullLevel.FULL)


## Get cull level name for debugging
func get_cull_level_name(level: CullLevel) -> String:
	match level:
		CullLevel.FULL: return "Full"
		CullLevel.REDUCED: return "Reduced"
		CullLevel.MINIMAL: return "Minimal"
		CullLevel.HIDDEN: return "Hidden"
	return "Unknown"
