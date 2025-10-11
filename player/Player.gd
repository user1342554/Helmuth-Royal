extends CharacterBody3D

# Movement
const SPEED = 5.0
const SPRINT_SPEED = 8.0
const SNEAK_SPEED = 2.5  # Slow and stealthy
const JUMP_VELOCITY = 4.5
const ACCELERATION = 20.0
const FRICTION = 15.0

# Sneak
var is_sneaking = false

# Dodge
const DODGE_SPEED = 10.0
const DODGE_DURATION = 0.35
const DODGE_COOLDOWN = 1.0

# Stamina System (Elden Ring Style)
const MAX_STAMINA = 100.0
const STAMINA_REGEN_RATE = 25.0  # Per second
const STAMINA_REGEN_DELAY = 1.0  # Delay after use
const DODGE_STAMINA_COST = 25.0
const SPRINT_STAMINA_COST = 15.0  # Per second

var current_stamina = MAX_STAMINA
var stamina_regen_timer = 0.0
var can_sprint = true
var can_dodge = true

# Max speeds
const MAX_HORIZONTAL_SPEED = 15.0

var dodge_timer = 0.0
var dodge_cooldown_timer = 0.0
var dodge_direction = Vector3.ZERO
var is_dodging = false
var has_iframes = false
var was_on_floor_before_dodge = false

# Get the gravity from the project settings (cached)
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Multiplayer
var is_local_player = false

# Mouse look
var mouse_sensitivity = 0.003
var camera_rotation = Vector2.ZERO

# Camera influence from cube movement
var camera_influence_strength := 0.02  # Very subtle influence
var camera_offset := Vector3.ZERO

# Performance optimization: Cache frequently accessed nodes
@onready var head_node := $Head
@onready var camera_node := $Head/Camera3D
@onready var mesh_node := $MeshInstance3D
@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _character_skin = $CharacterRotationRoot/CharacterSkin  # CharacterSkin node

# Combat cube
var combat_cube: RigidBody3D
var combat_cube_scene = preload("res://player/CombatCube.tscn")
var cube_manual_control := false  # True when holding left click
var cube_min_distance := 1.0  # Minimum distance from camera
var cube_max_distance := 3.0  # Maximum distance from camera (reduced for better control)
var screen_edge_threshold := 0.1  # 10% from edge triggers camera rotation
var edge_rotation_speed := 1.0  # Speed of camera rotation at edges
var virtual_mouse_pos := Vector2.ZERO  # Track mouse position for cube control

# Performance: Input buffering for smoother physics
var _input_buffer := Vector2.ZERO
var _sprint_pressed := false
var _jump_pressed := false
var _dodge_pressed := false
var _sneak_pressed := false

func _ready():
	# Add to player group for collision detection
	add_to_group("player")
	
	# Set player collision layer
	collision_layer = 4  # Layer 4 for players
	collision_mask = 1 + 2  # Collide with world (1) and combat objects (2)
	
	# Check if this is the local player
	is_local_player = is_multiplayer_authority()
	
	print("Player ", name, " ready. Is local: ", is_local_player, " Authority: ", get_multiplayer_authority())
	
	# Initialize character skin - no manual initialization needed
	# The AnimationTree will be automatically active
	
	# Spawn combat cube
	_spawn_combat_cube()
	
	# Setup for local player
	if is_local_player:
		# Activate first-person camera
		camera_node.make_current()
		
		# Hide own character model (first-person view)
		if _rotation_root:
			_rotation_root.visible = false
		mesh_node.visible = false
		
		# Capture mouse
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		VoiceChat.start_recording()
		print("Local player camera activated (First Person)")
	else:
		# Disable camera for remote players
		camera_node.current = false
		# Show character model for remote players
		if _rotation_root:
			_rotation_root.visible = true
		mesh_node.visible = false
		# Performance: Reduce physics priority for remote players
		process_priority = 10  # Process after local player
		print("Remote player, camera disabled")
	
	# Add player name label
	_setup_name_label()

func _spawn_combat_cube():
	# Instance combat cube
	combat_cube = combat_cube_scene.instantiate()
	combat_cube.name = "CombatCube"
	
	# Set initial position (adjusted for character model height)
	# Character is about 2 units tall, so position cube higher
	combat_cube.global_position = global_position + Vector3(0.4, 1.5, -1.5)
	
	# Set multiplayer authority to match player
	combat_cube.set_multiplayer_authority(get_multiplayer_authority())
	
	# Add to scene
	get_parent().add_child(combat_cube, true)
	
	print("Combat cube spawned for player ", name)

func _input(event):
	# Only process mouse for local player
	if not is_local_player:
		return
	
	# Mouse look (optimized with cached nodes)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if cube_manual_control:
			# Controlling cube: track virtual mouse position instead of rotating camera
			var viewport = get_viewport()
			var screen_size = viewport.get_visible_rect().size
			
			# Update virtual mouse position
			virtual_mouse_pos += event.relative
			
			# Clamp to screen bounds
			virtual_mouse_pos.x = clamp(virtual_mouse_pos.x, 0, screen_size.x)
			virtual_mouse_pos.y = clamp(virtual_mouse_pos.y, 0, screen_size.y)
		else:
			# Normal camera control
			camera_rotation.x -= event.relative.y * mouse_sensitivity
			camera_rotation.y -= event.relative.x * mouse_sensitivity
			
			# Clamp vertical rotation
			camera_rotation.x = clamp(camera_rotation.x, -PI/2, PI/2)
			
			# Apply rotation (using cached nodes)
			head_node.rotation.x = camera_rotation.x
			rotation.y = camera_rotation.y
	
	# Toggle mouse capture with ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Performance: Process input in _process for better responsiveness
func _process(_delta):
	if not is_local_player:
		return
	
	# Buffer input for physics process
	_input_buffer = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sprint_pressed = Input.is_action_pressed("sprint")
	_jump_pressed = Input.is_action_just_pressed("jump")
	_dodge_pressed = Input.is_action_just_pressed("dodge")
	_sneak_pressed = Input.is_action_pressed("sneak")
	
	# Check for manual cube control (left mouse button)
	var was_controlling = cube_manual_control
	cube_manual_control = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# Initialize virtual mouse position when starting control
	if cube_manual_control and not was_controlling:
		var viewport = get_viewport()
		var screen_size = viewport.get_visible_rect().size
		virtual_mouse_pos = screen_size / 2.0  # Start at center
	
	# When releasing control, cube moves to auto position
	# Camera stays in place - no rotation needed
	
	# Edge-based camera rotation when controlling cube
	if cube_manual_control and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var viewport = get_viewport()
		var screen_size = viewport.get_visible_rect().size
		
		# Use virtual mouse position for edge detection
		var norm_x = virtual_mouse_pos.x / screen_size.x
		var norm_y = virtual_mouse_pos.y / screen_size.y
		
		# Rotate camera when near screen edges
		var rotation_amount_x = 0.0
		var rotation_amount_y = 0.0
		
		# Horizontal edges (left/right)
		if norm_x < screen_edge_threshold:
			# Left edge - rotate left
			var edge_factor = (screen_edge_threshold - norm_x) / screen_edge_threshold
			rotation_amount_y = edge_rotation_speed * edge_factor * _delta
		elif norm_x > (1.0 - screen_edge_threshold):
			# Right edge - rotate right
			var edge_factor = (norm_x - (1.0 - screen_edge_threshold)) / screen_edge_threshold
			rotation_amount_y = -edge_rotation_speed * edge_factor * _delta
		
		# Vertical edges (top/bottom)
		if norm_y < screen_edge_threshold:
			# Top edge - rotate up
			var edge_factor = (screen_edge_threshold - norm_y) / screen_edge_threshold
			rotation_amount_x = edge_rotation_speed * edge_factor * _delta
		elif norm_y > (1.0 - screen_edge_threshold):
			# Bottom edge - rotate down
			var edge_factor = (norm_y - (1.0 - screen_edge_threshold)) / screen_edge_threshold
			rotation_amount_x = -edge_rotation_speed * edge_factor * _delta
		
		# Apply rotation
		camera_rotation.x += rotation_amount_x
		camera_rotation.y += rotation_amount_y
		
		# Clamp vertical rotation
		camera_rotation.x = clamp(camera_rotation.x, -PI/2, PI/2)
		
		# Apply to nodes
		head_node.rotation.x = camera_rotation.x
		rotation.y = camera_rotation.y

func _update_camera_influence(delta: float):
	# Apply minimal camera movement based on cube velocity
	if not combat_cube or not cube_manual_control:
		# Smoothly return to center when not controlling
		camera_offset = camera_offset.lerp(Vector3.ZERO, delta * 5.0)
		head_node.position = Vector3(0, 1.6, 0) + camera_offset
		return
	
	# Get cube movement influence
	var cube_velocity = combat_cube.linear_velocity if combat_cube.has_method("get_velocity") else Vector3.ZERO
	
	# Calculate camera offset based on cube velocity (very subtle)
	var target_offset = cube_velocity * camera_influence_strength * delta
	
	# Limit maximum offset
	target_offset = target_offset.limit_length(0.03)  # Max 3cm offset
	
	# Smooth interpolation
	camera_offset = camera_offset.lerp(target_offset, delta * 8.0)
	
	# Apply offset to head (camera parent) - fixed height
	head_node.position = Vector3(0, 1.6, 0) + camera_offset

func _physics_process(delta):
	# Update combat cube position for all players
	_update_combat_cube()
	
	# Apply subtle camera influence from cube movement
	if is_local_player:
		_update_camera_influence(delta)
	
	# Update character animations for all players
	_update_character_animations()
	
	# Only process input for local player (authority)
	if is_multiplayer_authority():
		# Update stamina system
		_update_stamina(delta)
		
		# Update sneak state (no camera height change)
		is_sneaking = _sneak_pressed and not is_dodging
		
		# Update dodge timers (optimized with early return)
		if dodge_timer > 0:
			dodge_timer -= delta
			if dodge_timer <= 0:
				is_dodging = false
				has_iframes = false
		
		if dodge_cooldown_timer > 0:
			dodge_cooldown_timer -= delta
		
		# Handle dodge (before jump to prevent exploits) - using buffered input
		if _dodge_pressed and not is_dodging and dodge_cooldown_timer <= 0 and is_on_floor() and can_dodge:
			if try_use_stamina(DODGE_STAMINA_COST):
				start_dodge()
		
		# Handle jump (not during dodge or sneak) - using buffered input
		if _jump_pressed and is_on_floor() and not is_dodging and not is_sneaking:
			velocity.y = JUMP_VELOCITY
		
		# Apply gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
		
		# Handle dodge movement
		if is_dodging:
			# Keep player grounded during dodge
			if was_on_floor_before_dodge and is_on_floor():
				velocity.y = -2.0  # Small downward force to stay grounded
			
			velocity.x = dodge_direction.x * DODGE_SPEED
			velocity.z = dodge_direction.z * DODGE_SPEED
		else:
			# Use buffered input direction for smoother movement
			var direction := Vector3.ZERO
			if _input_buffer.length_squared() > 0.01:  # Optimized deadzone check
				direction = (transform.basis * Vector3(_input_buffer.x, 0, _input_buffer.y)).normalized()
			
			# Determine movement speed based on state
			var target_speed = SPEED
			
			if is_sneaking:
				# Sneak: slow and quiet
				target_speed = SNEAK_SPEED
			elif _sprint_pressed and can_sprint and current_stamina > 0:
				# Sprint: fast but costs stamina
				if direction != Vector3.ZERO:
					var stamina_cost = SPRINT_STAMINA_COST * delta
					if current_stamina >= stamina_cost:
						current_stamina -= stamina_cost
						stamina_regen_timer = STAMINA_REGEN_DELAY
						target_speed = SPRINT_SPEED
					else:
						can_sprint = false
			
			# Apply movement with optimized calculations
			if direction != Vector3.ZERO:
				var accel_rate = ACCELERATION * delta
				velocity.x = move_toward(velocity.x, direction.x * target_speed, accel_rate)
				velocity.z = move_toward(velocity.z, direction.z * target_speed, accel_rate)
			else:
				var friction_rate = FRICTION * delta
				velocity.x = move_toward(velocity.x, 0, friction_rate)
				velocity.z = move_toward(velocity.z, 0, friction_rate)
		
		# Cap horizontal speed to prevent exploits (optimized)
		var horizontal_speed_sq = velocity.x * velocity.x + velocity.z * velocity.z
		if horizontal_speed_sq > MAX_HORIZONTAL_SPEED * MAX_HORIZONTAL_SPEED:
			var horizontal_speed = sqrt(horizontal_speed_sq)
			var scale = MAX_HORIZONTAL_SPEED / horizontal_speed
			velocity.x *= scale
			velocity.z *= scale
	
	# Always apply physics for all players (local and remote)
	move_and_slide()

func start_dodge():
	is_dodging = true
	has_iframes = true
	dodge_timer = DODGE_DURATION
	dodge_cooldown_timer = DODGE_COOLDOWN
	was_on_floor_before_dodge = is_on_floor()
	
	# Reset vertical velocity to prevent flying
	if is_on_floor():
		velocity.y = 0
	
	# Get dodge direction from buffered input for consistency
	if _input_buffer.length_squared() > 0.01:
		dodge_direction = (transform.basis * Vector3(_input_buffer.x, 0, _input_buffer.y)).normalized()
	else:
		# Default to forward if no input
		dodge_direction = -transform.basis.z

func _update_stamina(delta):
	# Regenerate stamina with delay
	if stamina_regen_timer > 0:
		stamina_regen_timer -= delta
	else:
		# Regenerate stamina
		if current_stamina < MAX_STAMINA:
			current_stamina = min(current_stamina + STAMINA_REGEN_RATE * delta, MAX_STAMINA)
	
	# Update flags
	can_sprint = current_stamina > SPRINT_STAMINA_COST * 0.5
	can_dodge = current_stamina >= DODGE_STAMINA_COST

func try_use_stamina(cost: float) -> bool:
	if current_stamina >= cost:
		current_stamina -= cost
		stamina_regen_timer = STAMINA_REGEN_DELAY
		return true
	return false

func get_stamina_percent() -> float:
	return current_stamina / MAX_STAMINA

# Camera height update removed - no camera movement when sneaking

func has_invincibility_frames() -> bool:
	return has_iframes

func _setup_name_label():
	# Create a Label3D to show player name
	var label = Label3D.new()
	label.text = "Player " + name
	label.font_size = 32
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Position above character model (character is about 2 units tall)
	label.position = Vector3(0, 2.3, 0)
	label.modulate = Color.CYAN if is_local_player else Color.WHITE
	add_child(label)

func _update_combat_cube():
	# Update combat cube to follow look direction or mouse
	if not combat_cube:
		return
	
	var target_pos: Vector3
	
	if cube_manual_control and is_local_player:
		# Manual control: Follow virtual mouse cursor
		var mouse_pos = virtual_mouse_pos
		
		# Raycast from camera through mouse position
		var from = camera_node.project_ray_origin(mouse_pos)
		var ray_direction = camera_node.project_ray_normal(mouse_pos)
		var to = from + ray_direction * cube_max_distance
		
		# Use PhysicsRayQueryParameters3D for raycasting
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1 + 4  # World + Players
		query.exclude = [self]  # Don't hit ourselves
		
		var result = space_state.intersect_ray(query)
		
		if result:
			# Hit something, place cube at hit point (slightly offset)
			var hit_distance = from.distance_to(result.position)
			
			# Clamp distance to min/max range
			if hit_distance < cube_min_distance:
				# Too close, place at min distance
				target_pos = from + ray_direction * cube_min_distance
			elif hit_distance > cube_max_distance:
				# Too far, place at max distance
				target_pos = from + ray_direction * cube_max_distance
			else:
				# Good distance, place at hit point
				target_pos = result.position + result.normal * 0.2
		else:
			# No hit, place at default distance in ray direction
			# This keeps cube always in front of camera, even when looking down
			target_pos = from + ray_direction * 2.5
	else:
		# Auto mode: Follow look direction with offset
		var forward = -camera_node.global_transform.basis.z  # Camera forward
		var right = camera_node.global_transform.basis.x     # Camera right
		var up = camera_node.global_transform.basis.y        # Camera up
		
		# Offset: 1.5m forward, 0.9m right (far right), -0.3m down (below center)
		var offset = forward * 1.5 + right * 0.9 + up * -0.3
		target_pos = camera_node.global_position + offset
	
	# Set target for smooth movement
	if combat_cube.has_method("set_target_position"):
		combat_cube.set_target_position(target_pos)

func _update_character_animations():
	if not _rotation_root or not _rotation_root.visible:
		return
	
	if not _character_skin:
		return
	
	# Get horizontal velocity for speed calculation
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var speed = horizontal_velocity.length()
	var stopping_speed = 0.5  # Threshold for idle vs moving
	
	# Rotate character model to face movement direction (smooth rotation)
	# Only rotate when moving
	if speed > stopping_speed:
		var move_direction = horizontal_velocity.normalized()
		if move_direction.length_squared() > 0.01:
			_orient_character_to_direction(move_direction, get_physics_process_delta_time())
	
	# Update character skin animations
	var is_moving = speed > stopping_speed
	
	# Set moving state (triggers idle/walk/run state machine transition)
	_character_skin.moving = is_moving
	
	if is_moving:
		# Special handling for sneaking: slow down animation
		if is_sneaking:
			# Sneaking: play walk animation slowly (0.3 = slow walk)
			_character_skin.move_speed = 0.3
		else:
			# Normal movement: blend between walk and run based on speed
			var max_speed = SPRINT_SPEED if _sprint_pressed else SPEED
			var speed_ratio = clamp(speed / max_speed, 0.0, 1.0)
			_character_skin.move_speed = speed_ratio
	
	# Handle jump and fall animations - only update if significantly moving vertically
	if not is_on_floor():
		if velocity.y > 0.5:
			_character_skin.jump()
		elif velocity.y < -0.5:
			_character_skin.fall()

# Character rotation logic from GDQuest demo
func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	var rotation_speed = 12.0  # Rotation speed
	var left_axis := Vector3.UP.cross(direction)
	var rotation_basis := Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var model_scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(
		_rotation_root.transform.basis.get_rotation_quaternion().slerp(rotation_basis, delta * rotation_speed)
	).scaled(model_scale)

func _exit_tree():
	# Cleanup combat cube
	if is_instance_valid(combat_cube):
		combat_cube.queue_free()
	
	# Stop recording if this was the local player
	if is_local_player:
		VoiceChat.stop_recording()
		# Release mouse
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
