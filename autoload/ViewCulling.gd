extends Node

# View Distance Culling System for improved performance

var enabled := true
var max_view_distance := 100.0  # Maximum render distance
var player_cull_distance := 150.0  # Distance to cull other players
var aggressive_culling := false  # More aggressive culling for low-end

var _update_counter := 0
var _update_interval := 30  # Check every N frames

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
	
	# Cull remote players based on distance
	for peer_id in NetworkManager.players.keys():
		if peer_id == multiplayer.get_unique_id():
			continue
		
		var player = NetworkManager.get_player(peer_id)
		if not player:
			continue
		
		var distance_sq = local_pos.distance_squared_to(player.global_position)
		var cull_distance_sq = player_cull_distance * player_cull_distance
		
		# Hide/show player based on distance
		if distance_sq > cull_distance_sq:
			if player.visible:
				player.visible = false
				# Disable physics for invisible players
				player.set_physics_process(false)
		else:
			if not player.visible:
				player.visible = true
				# Re-enable physics
				player.set_physics_process(true)

func set_view_distance(distance: float):
	max_view_distance = distance
	player_cull_distance = distance * 1.5
	print("View distance set to: %.1f" % distance)

func enable_aggressive_culling():
	aggressive_culling = true
	max_view_distance = 50.0
	player_cull_distance = 75.0
	_update_interval = 15  # Update more frequently
	print("Aggressive culling enabled")

func disable_aggressive_culling():
	aggressive_culling = false
	max_view_distance = 100.0
	player_cull_distance = 150.0
	_update_interval = 30
	print("Aggressive culling disabled")

