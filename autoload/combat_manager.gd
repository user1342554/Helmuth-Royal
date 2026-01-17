extends Node
## CombatManager - Server-authoritative combat system
## All combat RPCs go through here for consistent node paths across all peers
## Autoloads always exist at /root/CombatManager on every peer

# Weapon data cache - matches weapon resource IDs
# Type 1 = HITSCAN, Type 2 = PROJECTILE
const WEAPON_DATA := {
	1: {"name": "Pistol", "damage": 22.0, "range": 200.0, "headshot_mult": 2.0, "pellets": 1, "type": 1},
	2: {"name": "AssaultRifle", "damage": 25.0, "range": 290.0, "headshot_mult": 2.0, "pellets": 1, "type": 1},
	3: {"name": "Shotgun", "damage": 25.0, "range": 210.0, "headshot_mult": 1.7, "pellets": 8, "type": 1},
	4: {"name": "SniperRifle", "damage": 180.0, "range": 490.0, "headshot_mult": 2.0, "pellets": 1, "type": 1},
	5: {"name": "RocketLauncher", "damage": 340.0, "range": 200.0, "headshot_mult": 1.0, "pellets": 1, "type": 2},
}

# Spread values for server-side hit detection (matches weapon resources)
const WEAPON_SPREAD := {
	1: {"min": -0.01, "max": 0.01},  # Pistol
	2: {"min": -0.03, "max": 0.03},  # AssaultRifle
	3: {"min": -0.7, "max": 0.7},    # Shotgun
	4: {"min": 0.0, "max": 0.0},     # SniperRifle
	5: {"min": 0.0, "max": 0.0},     # RocketLauncher
}


## Client calls this to request a shot - sends to server
func request_fire(weapon_id: int, aim_direction: Vector3) -> void:
	if NetworkManager.is_lan_mode:
		# LAN mode: use RPC to server (peer 1)
		# If WE are the server, process directly (call_remote won't call self)
		if multiplayer.is_server():
			var my_peer_id: int = multiplayer.get_unique_id()
			_process_fire_request(my_peer_id, weapon_id, aim_direction)
		else:
			_rpc_fire_request.rpc_id(1, weapon_id, aim_direction)
	else:
		# Steam mode: send via P2P packet to host
		# If WE are the host, process directly
		if NetworkManager.is_host:
			var my_steam_id: int = SteamManager.steam_id
			_process_fire_request(my_steam_id, weapon_id, aim_direction)
		else:
			var packet := NetworkManager._make_packet("FIRE", {
				"weapon_id": weapon_id,
				"dir": [aim_direction.x, aim_direction.y, aim_direction.z]
			})
			var host_id := SteamManager.get_lobby_owner_id()
			if host_id > 0:
				SteamManager.send_p2p_packet(host_id, packet, false)  # unreliable


## RPC: Client requests to fire (unreliable_ordered for auto-fire spam)
## Uses unreliable_ordered to prevent backlog on automatic weapons
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_fire_request(weapon_id: int, aim_direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	
	var shooter_peer_id: int = multiplayer.get_remote_sender_id()
	_process_fire_request(shooter_peer_id, weapon_id, aim_direction)


## Called by NetworkManager for Steam P2P FIRE packets
func handle_steam_fire_packet(sender_id: int, weapon_id: int, aim_direction: Vector3) -> void:
	if not NetworkManager.is_host:
		return
	_process_fire_request(sender_id, weapon_id, aim_direction)


## Server processes the fire request - does raycast and applies damage
func _process_fire_request(shooter_peer_id: int, weapon_id: int, aim_direction: Vector3) -> void:
	var shooter_node: Node3D = NetworkManager.get_player(shooter_peer_id)
	
	if not shooter_node or not is_instance_valid(shooter_node):
		return
	
	# Check if player is alive
	if shooter_node.has_method("is_alive") and not shooter_node.is_alive():
		return
	
	# ANTI-CHEAT: Compute origin from SERVER-SIDE player position
	# Never trust client-sent origin - a cheater could send fake positions
	var camera_mount: Node3D = shooter_node.get_node_or_null("CameraMount")
	if not camera_mount:
		return
	
	var aim_origin: Vector3 = camera_mount.global_position
	
	# Validate and normalize direction (prevent NaN/infinite exploits)
	if not aim_direction.is_finite():
		return
	if not aim_direction.is_normalized():
		aim_direction = aim_direction.normalized()
	if aim_direction.length_squared() < 0.5:
		return
	
	# Get weapon data
	var weapon: Dictionary = WEAPON_DATA.get(weapon_id, WEAPON_DATA[1])
	var spread_data: Dictionary = WEAPON_SPREAD.get(weapon_id, WEAPON_SPREAD[1])
	
	# Skip projectile weapons for now (they need different handling)
	if weapon.type == 2:
		# TODO: Server-authoritative projectile spawning
		_rpc_play_shot_effects.rpc(shooter_peer_id, aim_origin, aim_origin + aim_direction * 10.0)
		return
	
	# Process each pellet (for shotgun, multiple pellets)
	var final_hit_position: Vector3 = aim_origin + aim_direction * weapon.range
	var total_damage_dealt: float = 0.0
	var hit_player: Node3D = null
	
	for _pellet in range(weapon.pellets):
		# Apply spread
		var spread := Vector3(
			randf_range(spread_data.min, spread_data.max),
			randf_range(spread_data.min, spread_data.max),
			randf_range(spread_data.min, spread_data.max)
		)
		var pellet_direction: Vector3 = (aim_direction + spread).normalized()
		
		# Server raycast
		var space: PhysicsDirectSpaceState3D = shooter_node.get_world_3d().direct_space_state
		var ray_end: Vector3 = aim_origin + pellet_direction * weapon.range
		var query := PhysicsRayQueryParameters3D.create(aim_origin, ray_end)
		query.exclude = [shooter_node.get_rid()]  # Exclude shooter's RID
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result: Dictionary = space.intersect_ray(query)
		
		if result:
			final_hit_position = result.position
			var hit_collider: Object = result.collider
			var final_damage: float = weapon.damage
			
			# Check if we hit a player (multiplayer)
			if hit_collider is CharacterBody3D and hit_collider.has_method("server_apply_damage"):
				# Check for headshot (if collider is in "head" group or hit Area3D for head)
				# For now, just apply base damage - headshot detection can be added later
				hit_collider.server_apply_damage(final_damage, shooter_peer_id)
				total_damage_dealt += final_damage
				hit_player = hit_collider
			# Check if we hit a shooting range target or other hitscanHit object
			elif hit_collider.has_method("hitscanHit"):
				var hit_direction: Vector3 = pellet_direction
				hit_collider.hitscanHit(final_damage, hit_direction, final_hit_position)
				total_damage_dealt += final_damage
	
	# Broadcast shot effects to all clients
	_rpc_play_shot_effects.rpc(shooter_peer_id, aim_origin, final_hit_position)


## Broadcast shot effects to all clients
## Uses unreliable since visual effects can be dropped without issue
@rpc("any_peer", "call_local", "unreliable")
func _rpc_play_shot_effects(shooter_id: int, origin: Vector3, hit_pos: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# SECURITY: Only accept from server (peer 1) or local call (0)
	if sender != 1 and sender != 0:
		return
	
	var shooter: Node3D = NetworkManager.get_player(shooter_id)
	if not shooter or not is_instance_valid(shooter):
		return
	
	# Don't double-play effects for local player (they already played locally for responsiveness)
	if shooter.has_method("is_local_player") and shooter.is_local_player:
		return
	
	# Play muzzle flash on shooter's weapon
	var weapon_manager = shooter.get_node_or_null("CameraMount/Camera3D/WeaponManager")
	if weapon_manager and weapon_manager.has_method("displayMuzzleFlash"):
		weapon_manager.displayMuzzleFlash()
	
	# Play gunshot sound at shooter position
	if weapon_manager and weapon_manager.has_method("play_remote_shot_sound"):
		weapon_manager.play_remote_shot_sound()
	
	# Spawn bullet decal at hit position
	# Note: We'd need hit normal for proper orientation - for now skip decals on remote shots
	# or do a local raycast just for decal placement
