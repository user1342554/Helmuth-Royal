extends Node3D
## ShootManager - Handles shooting logic with server-authoritative damage
## Local effects are played immediately for responsiveness
## Hit detection is done by the server via CombatManager

var cW  # Current weapon
var rng: RandomNumberGenerator

@onready var weaponManager: Node3D = get_parent()  # WeaponManager is parent


func getCurrentWeapon(currWeap) -> void:
	cW = currWeap


func shoot() -> void:
	if cW == null:
		return
	
	if not _can_shoot():
		return
	
	cW.isShooting = true
	
	# Number of successive shots (burst fire)
	for i in range(cW.nbProjShots):
		if not _has_ammo():
			break
		
		# Consume ammo locally
		_consume_ammo()
		
		# Play local effects immediately for responsiveness
		_play_local_effects()
		
		# Get aim direction from camera
		var camera: Camera3D = weaponManager.camera
		if camera:
			var aim_direction: Vector3 = -camera.global_transform.basis.z
			
			# Send fire request to server (server will do hit detection)
			# Only send direction - server computes origin from server-side player position
			if cW.type == cW.types.HITSCAN:
				CombatManager.request_fire(cW.weaponId, aim_direction)
			elif cW.type == cW.types.PROJECTILE:
				# For projectiles, spawn locally but server should validate hits
				_spawn_projectile(aim_direction)
		
		# Wait between shots
		await get_tree().create_timer(cW.timeBetweenShots).timeout
	
	cW.isShooting = false


func _can_shoot() -> bool:
	if cW.isShooting:
		return false
	if cW.isReloading:
		return false
	if not _has_ammo():
		return false
	return true


func _has_ammo() -> bool:
	if cW.allAmmoInMag:
		return weaponManager.ammoManager.ammoDict[cW.ammoType] >= cW.nbProjShotsAtSameTime
	return cW.totalAmmoInMag >= cW.nbProjShotsAtSameTime


func _consume_ammo() -> void:
	for j in range(cW.nbProjShotsAtSameTime):
		if cW.allAmmoInMag:
			weaponManager.ammoManager.ammoDict[cW.ammoType] -= 1
		else:
			cW.totalAmmoInMag -= 1


func _play_local_effects() -> void:
	# Sound
	if cW.shootSound:
		weaponManager.weaponSoundManagement(cW.shootSound, cW.shootSoundSpeed)
	
	# Animation
	if cW.shootAnimName != "":
		weaponManager.animManager.playAnimation("ShootAnim%s" % cW.weaponName, cW.shootAnimSpeed, true)
	
	# Muzzle flash
	if cW.showMuzzleFlash:
		weaponManager.displayMuzzleFlash()
	
	# Camera recoil (if available)
	if weaponManager.cameraRecoilHolder and weaponManager.cameraRecoilHolder.has_method("setRecoilValues"):
		weaponManager.cameraRecoilHolder.setRecoilValues(cW.baseRotSpeed, cW.targetRotSpeed)
		weaponManager.cameraRecoilHolder.addRecoil(cW.recoilVal)
	
	# Local raycast for visual effects (bullet decals) - damage is handled by server
	if cW.type == cW.types.HITSCAN:
		_spawn_local_bullet_decal()


func _spawn_projectile(aim_direction: Vector3) -> void:
	# Projectile weapons still spawn locally for visual feedback
	if cW.projRef == null:
		return
	
	rng = RandomNumberGenerator.new()
	
	# Apply spread
	var spread := Vector3(
		rng.randf_range(cW.minSpread, cW.maxSpread),
		rng.randf_range(cW.minSpread, cW.maxSpread),
		rng.randf_range(cW.minSpread, cW.maxSpread)
	)
	var projectile_direction: Vector3 = (aim_direction + spread).normalized()
	
	# Instantiate projectile
	var proj_instance = cW.projRef.instantiate()
	
	# Set projectile properties
	proj_instance.global_transform = cW.weaponSlot.attackPoint.global_transform
	proj_instance.direction = projectile_direction
	proj_instance.damage = cW.damagePerProj
	proj_instance.timeBeforeVanish = cW.projTimeBeforeVanish
	proj_instance.gravity_scale = cW.projGravityVal
	proj_instance.isExplosive = cW.isProjExplosive
	
	# Pass shooter ID for damage attribution
	var player = weaponManager.playChar
	if player:
		if NetworkManager.is_lan_mode:
			proj_instance.shooter_id = player.get("peer_id") if player.get("peer_id") else 0
		else:
			proj_instance.shooter_id = player.get("steam_id") if player.get("steam_id") else 0
	
	get_tree().get_root().add_child(proj_instance)
	proj_instance.set_linear_velocity(projectile_direction * cW.projMoveSpeed)


## Local raycast for visual effects only (bullet decals)
## This does NOT handle damage - that's done by the server
func _spawn_local_bullet_decal() -> void:
	var camera: Camera3D = weaponManager.camera
	if camera == null:
		return
	
	# Initialize RNG if needed
	if rng == null:
		rng = RandomNumberGenerator.new()
	
	# Apply spread
	var spread := Vector3(
		rng.randf_range(cW.minSpread, cW.maxSpread),
		rng.randf_range(cW.minSpread, cW.maxSpread),
		rng.randf_range(cW.minSpread, cW.maxSpread)
	)
	
	var aim_direction: Vector3 = (-camera.global_transform.basis.z + spread).normalized()
	var ray_start: Vector3 = camera.global_position
	var ray_end: Vector3 = ray_start + aim_direction * cW.maxRange
	
	# Local raycast for visual feedback
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	# Exclude the local player
	var player: CharacterBody3D = weaponManager.playChar
	if player:
		query.exclude = [player.get_rid()]
	
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var result: Dictionary = space.intersect_ray(query)
	
	if result:
		var hit_point: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		var hit_collider: Object = result.collider
		
		# Spawn bullet decal on non-player surfaces
		if not (hit_collider is CharacterBody3D):
			weaponManager.displayBulletHole(hit_point, hit_normal)
		else:
			# Hit a player - could show blood effect here instead
			# For now, just don't spawn a decal
			pass


# Legacy function kept for compatibility - now unused for hitscan
func getCameraPOV() -> Vector3:
	var camera: Camera3D = weaponManager.camera
	if camera == null:
		return Vector3.ZERO
	
	var window: Window = get_window()
	var viewport: Vector2i
	
	match window.content_scale_mode:
		window.CONTENT_SCALE_MODE_VIEWPORT:
			viewport = window.content_scale_size
		window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
			viewport = window.content_scale_size
		window.CONTENT_SCALE_MODE_DISABLED:
			viewport = window.get_size()
	
	var raycast_start: Vector3 = camera.project_ray_origin(viewport / 2)
	var raycast_end: Vector3
	
	if cW.type == cW.types.HITSCAN:
		raycast_end = raycast_start + camera.project_ray_normal(viewport / 2) * cW.maxRange
	else:
		raycast_end = raycast_start + camera.project_ray_normal(viewport / 2) * 280
	
	var query := PhysicsRayQueryParameters3D.create(raycast_start, raycast_end)
	var intersection: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	
	if not intersection.is_empty():
		return intersection.position
	return raycast_end
