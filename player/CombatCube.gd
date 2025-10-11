extends RigidBody3D

# Combat cube that follows player's look direction
var target_position := Vector3.ZERO
var smooth_speed := 50.0  # Very fast response
var max_distance := 2.5  # Max distance from player
var previous_position := Vector3.ZERO  # For camera influence

# Collision detection
var is_blocked := false
var raycast: RayCast3D

func _ready():
	# Setup collision
	collision_layer = 2  # Layer 2 for combat objects
	collision_mask = 1 + 2 + 4  # Collide with world (1), combat (2), players (4)
	
	# Physics settings for smooth collision
	gravity_scale = 0.0  # No gravity, controlled by player
	continuous_cd = true  # Continuous collision detection
	contact_monitor = true
	max_contacts_reported = 10
	linear_damp = 3.0  # Low damping for fast response but still heavy feel
	angular_damp = 10.0
	mass = 2.0  # Heavy mass for substantial feel
	
	# Setup raycast for smooth collision prediction
	raycast = RayCast3D.new()
	add_child(raycast)
	raycast.enabled = true
	raycast.collision_mask = 1 + 2 + 4  # Same as body
	raycast.target_position = Vector3.FORWARD * 0.5
	
	# Connect collision signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	
	# Check if path to target is clear
	var direction = (target_position - global_position).normalized()
	var distance = global_position.distance_to(target_position)
	
	# Raycast to check for obstacles
	raycast.target_position = direction * min(distance, 0.3)
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		# Something is blocking, stop before collision
		var collision_point = raycast.get_collision_point()
		var blocked_distance = global_position.distance_to(collision_point)
		
		if blocked_distance < 0.2:  # Very close to obstacle
			# Stop movement, push back slightly
			linear_velocity = -direction * 2.0
			is_blocked = true
			return
	
	is_blocked = false
	
	# Store previous position for camera influence
	previous_position = global_position
	
	# Smooth movement to target position
	var current_pos = global_position
	var desired_velocity = (target_position - current_pos) * smooth_speed
	
	# Limit velocity for smooth but fast movement
	var max_speed = 25.0  # Very fast for quick response
	if desired_velocity.length() > max_speed:
		desired_velocity = desired_velocity.normalized() * max_speed
	
	# Apply velocity with collision awareness
	linear_velocity = desired_velocity
	
	# Stop rotation
	angular_velocity = Vector3.ZERO

func set_target_position(pos: Vector3):
	target_position = pos

func _on_body_entered(body: Node):
	# Handle collision with other objects
	if body.is_in_group("player"):
		print("Combat cube hit player: ", body.name)
		# TODO: Apply damage
	elif body.has_method("get_class") and body.get_class() == "RigidBody3D":
		# Collided with another combat cube
		print("Combat cube collision!")

func _on_body_exited(body: Node):
	pass

func get_velocity() -> Vector3:
	return linear_velocity

func get_movement_delta(delta: float) -> Vector3:
	# Return the movement influence for camera
	var current_movement = global_position - previous_position
	return current_movement / delta if delta > 0 else Vector3.ZERO

