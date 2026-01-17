extends CharacterBody3D
## Player - TABG-style chaotic movement system
## Features: Momentum, sliding, wonky jumps, high air control, bunny hopping

# Movement States
enum MovementState {
	WALKING,
	SPRINTING,
	CROUCHING,
	SLIDING,
	AIRBORNE,
	WALLRUNNING
}

# Movement speeds
const WALK_SPEED := 7.0
const SPRINT_SPEED := 12.0
const SLIDE_SPEED := 15.0
const CROUCH_SPEED := 3.0

# Physics - 
const GRAVITY := 18.0
const JUMP_VELOCITY := 9.0
const AIR_CONTROL := 0.6  # High air control for wonky TABG feel
const GROUND_ACCELERATION := 45.0
const AIR_ACCELERATION := 35.0
const SLIDE_FRICTION := 0.985  # Slides carry momentum
const GROUND_FRICTION := 0.88
const BUNNY_HOP_BOOST := 1.15  # Speed multiplier when bunny hopping

# Slide settings
const SLIDE_DURATION := 0.8
const SLIDE_COOLDOWN := 0.3
const MIN_SLIDE_SPEED := 6.0

# Jump helpers
const COYOTE_TIME := 0.15
const JUMP_BUFFER_TIME := 0.1

# Wall jump settings
const WALL_JUMP_VELOCITY := 8.0           # Upward velocity
const WALL_PUSH_FORCE := 6.0              # Push away from wall
const WALL_DETECT_THRESHOLD := 0.25       # Max abs(normal.y) for wall (0=vertical, 1=floor)
const WALL_COYOTE_TIME := 0.08            # Grace period after leaving wall

# Wallrun settings (Titanfall-style)
const WALLRUN_SPEED := 10.0               # Speed maintained along wall
const WALLRUN_GRAVITY := 3.0              # Reduced gravity during wallrun
const WALLRUN_MAX_DURATION := 1.75        # Max time on wall (Titanfall baseline)
const WALLRUN_MIN_SPEED := 6.0            # Min horizontal speed to start/maintain
const WALLRUN_ATTACH_ANGLE := 0.3         # Max abs(dot) for parallel check (0=parallel, 1=perpendicular)
const WALLRUN_STICK_FORCE := 2.0          # Inward force to keep attached
const WALLRUN_CAMERA_TILT := 7.0         # Degrees of camera tilt (away from wall)
const WALLRUN_CAMERA_TILT_SPEED := 6.0    # Tilt interpolation speed
const WALLRUN_JUMP_UP := 9.5              # Upward velocity when jumping off
const WALLRUN_JUMP_PUSH := 8.0            # Push force away from wall
const WALLRUN_EXIT_BOOST := 1.25          # Speed multiplier when exiting wallrun
const WALLRUN_DETECT_DISTANCE := 0.6      # Raycast distance for wall detection
const WALLRUN_COOLDOWN := 0.2             # Per-wall cooldown after exit

# Mouse
const MOUSE_SENSITIVITY := 0.002

# Head bob settings
const BOB_FREQUENCY := 2.5
const BOB_AMPLITUDE := 0.06
const SPRINT_BOB_MULT := 0.8

# Collision
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0

@export var max_health: float = 100.0
@export var health: float = 100.0
var alive: bool = true

# Respawn settings
const RESPAWN_TIME: float = 3.0

@onready var camera_mount: Node3D = $CameraMount
@onready var camera: Camera3D = $CameraMount/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $MeshInstance3D

var steam_id: int = 0
var peer_id: int = 0
var is_local_player: bool = false

# Network sync
var _sync_timer: float = 0.0
const SYNC_RATE: float = 0.033  # ~30 times per second
const SYNC_RATE_IDLE: float = 0.1  # Slower sync when idle (~10 times per second)
const POSITION_SYNC_THRESHOLD: float = 0.05  # Min distance to trigger sync
const ROTATION_SYNC_THRESHOLD: float = 0.02  # Min rotation change to trigger sync
var _last_synced_position: Vector3 = Vector3.ZERO
var _last_synced_rotation: float = 0.0
var _idle_frames: int = 0
const IDLE_FRAME_THRESHOLD: int = 30  # Frames before considered idle

var _target_position: Vector3 = Vector3.ZERO
var _prev_target_position: Vector3 = Vector3.ZERO
var _target_rotation: float = 0.0
var _target_camera_x: float = 0.0
var _target_velocity: Vector3 = Vector3.ZERO
var _interpolation_time: float = 0.0
const INTERPOLATION_SPEED: float = 12.0

# Movement state
var state: MovementState = MovementState.WALKING
var _current_speed: float = WALK_SPEED
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO

# Jump state
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = true
var _jump_count: int = 0

# Camera effects
var _bob_time: float = 0.0
var _camera_default_y: float = 0.0
var _target_camera_tilt: float = 0.0
var _current_camera_tilt: float = 0.0

# Momentum tracking
var _last_ground_speed: float = 0.0

# Cached calculations (avoid repeated allocations)
var _cached_horizontal_speed: float = 0.0
var _cached_horizontal_velocity: Vector2 = Vector2.ZERO

# Wall jump state
var _has_wall_jumped: bool = false        # Tracks if wall jump was used this airborne period
var _wall_normal: Vector3 = Vector3.ZERO  # Cached wall normal
var _wall_coyote_timer: float = 0.0       # Wall contact grace timer

# Wallrun state
var _wallrun_timer: float = 0.0
var _wallrun_side: int = 0                # -1=left, 1=right, 0=none
var _wallrun_normal: Vector3 = Vector3.ZERO  # Current wall normal
var _last_wallrun_collider_id: int = 0   # Prevent same-wall re-attach (by instance ID)
var _wallrun_cooldown_dict: Dictionary = {}  # {collider_id: cooldown_time}
var _wallrun_tilt_target: float = 0.0    # Target camera tilt
var _wallrun_tilt_current: float = 0.0   # Current camera tilt (smoothed)

# Raycasts for wallrun detection
var _wall_raycast_left: RayCast3D
var _wall_raycast_right: RayCast3D


func _ready() -> void:
	# Add to players group for easy lookup
	add_to_group("players")
	
	# Initialize collision shape to correct values
	_init_collision_shape()
	
	# Setup wallrun raycasts
	_setup_wallrun_raycasts()
	
	# Determine if this is the local player based on multiplayer authority
	if NetworkManager.is_lan_mode:
		peer_id = get_multiplayer_authority()
		is_local_player = peer_id == multiplayer.get_unique_id()
		print("[Player] LAN mode - peer_id: %d, my_id: %d, is_local: %s" % [peer_id, multiplayer.get_unique_id(), is_local_player])
	else:
		# Steam mode - use Steam ID from node name
		steam_id = name.to_int()  # Node is named after steam_id
		is_local_player = steam_id == SteamManager.steam_id
		print("[Player] Steam mode - steam_id: %d, my_steam_id: %d, is_local: %s" % [steam_id, SteamManager.steam_id, is_local_player])
	
	# Only setup camera and input for local player
	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
		# Hide our own mesh (first-person view - don't see own body)
		if has_node("MeshInstance3D"):
			$MeshInstance3D.visible = false
		if has_node("HeadMesh"):
			$HeadMesh.visible = false
		print("[Player] Local player - camera enabled, mesh hidden")
	else:
		# Disable camera for remote players, keep mesh visible
		camera.current = false
		# Initialize target position to current position
		_target_position = position
		_prev_target_position = position
		_target_rotation = rotation.y
		_target_velocity = Vector3.ZERO
		print("[Player] Remote player - camera disabled, mesh visible")
	
	_camera_default_y = STAND_HEIGHT - 0.2  # Eye level for standing


func _init_collision_shape() -> void:
	# Ensure collision shape is properly sized and positioned at start
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision_shape.shape
		capsule.height = STAND_HEIGHT
		capsule.radius = 0.4
		collision_shape.position.y = STAND_HEIGHT / 2.0
	
	# Sync body mesh
	if body_mesh and body_mesh.mesh is CapsuleMesh:
		var mesh: CapsuleMesh = body_mesh.mesh
		mesh.height = STAND_HEIGHT
		mesh.radius = 0.4
		body_mesh.position.y = STAND_HEIGHT / 2.0
	
	# Set camera mount to eye level
	if camera_mount:
		camera_mount.position.y = STAND_HEIGHT - 0.2


func _setup_wallrun_raycasts() -> void:
	# Create left raycast
	_wall_raycast_left = RayCast3D.new()
	_wall_raycast_left.target_position = Vector3(-WALLRUN_DETECT_DISTANCE, 0, 0)
	_wall_raycast_left.position.y = STAND_HEIGHT * 0.6  # Chest height
	_wall_raycast_left.enabled = true
	_wall_raycast_left.collision_mask = 1  # Collide with world geometry
	add_child(_wall_raycast_left)
	
	# Create right raycast
	_wall_raycast_right = RayCast3D.new()
	_wall_raycast_right.target_position = Vector3(WALLRUN_DETECT_DISTANCE, 0, 0)
	_wall_raycast_right.position.y = STAND_HEIGHT * 0.6  # Chest height
	_wall_raycast_right.enabled = true
	_wall_raycast_right.collision_mask = 1  # Collide with world geometry
	add_child(_wall_raycast_right)


func _detect_wallrun_surface() -> Dictionary:
	# Returns {valid: bool, side: int, normal: Vector3, collider_id: int}
	var result := {"valid": false, "side": 0, "normal": Vector3.ZERO, "collider_id": 0}
	
	# Check both raycasts
	var left_hit := _wall_raycast_left.is_colliding()
	var right_hit := _wall_raycast_right.is_colliding()
	
	if not left_hit and not right_hit:
		return result
	
	# Get horizontal velocity for angle check
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var horizontal_speed := horizontal_vel.length()
	
	# Need minimum speed
	if horizontal_speed < WALLRUN_MIN_SPEED:
		return result
	
	var vel_dir := horizontal_vel.normalized()
	
	# Check left wall
	if left_hit:
		var wall_normal: Vector3 = _wall_raycast_left.get_collision_normal()
		var collider: Object = _wall_raycast_left.get_collider()
		
		# Validate it's a wall (not floor/slope)
		if abs(wall_normal.y) < WALL_DETECT_THRESHOLD:
			var collider_id: int = collider.get_instance_id() if collider else 0
			
			# Check cooldown
			if not _wallrun_cooldown_dict.has(collider_id):
				# Check angle - velocity should be roughly parallel to wall
				var angle_dot: float = absf(vel_dir.dot(wall_normal))
				if angle_dot < WALLRUN_ATTACH_ANGLE:
					result.valid = true
					result.side = -1  # Left
					result.normal = wall_normal
					result.collider_id = collider_id
					return result
	
	# Check right wall
	if right_hit:
		var wall_normal: Vector3 = _wall_raycast_right.get_collision_normal()
		var collider: Object = _wall_raycast_right.get_collider()
		
		# Validate it's a wall (not floor/slope)
		if abs(wall_normal.y) < WALL_DETECT_THRESHOLD:
			var collider_id: int = collider.get_instance_id() if collider else 0
			
			# Check cooldown
			if not _wallrun_cooldown_dict.has(collider_id):
				# Check angle - velocity should be roughly parallel to wall
				var angle_dot: float = absf(vel_dir.dot(wall_normal))
				if angle_dot < WALLRUN_ATTACH_ANGLE:
					result.valid = true
					result.side = 1  # Right
					result.normal = wall_normal
					result.collider_id = collider_id
					return result
	
	return result


func _start_wallrun(wall_info: Dictionary) -> void:
	state = MovementState.WALLRUNNING
	_wallrun_timer = 0.0
	_wallrun_side = wall_info.side
	_wallrun_normal = wall_info.normal
	_last_wallrun_collider_id = wall_info.collider_id
	
	# Project velocity onto wall plane to start clean
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var vel_into_wall := horizontal_vel.dot(_wallrun_normal)
	if vel_into_wall < 0:
		horizontal_vel -= _wallrun_normal * vel_into_wall
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z


func _exit_wallrun() -> void:
	# Apply exit speed boost
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var current_speed := horizontal_vel.length()
	if current_speed > 0:
		var boosted_speed := current_speed * WALLRUN_EXIT_BOOST
		horizontal_vel = horizontal_vel.normalized() * boosted_speed
		velocity.x = horizontal_vel.x
		velocity.z = horizontal_vel.z
	
	# Add to cooldown dict
	if _last_wallrun_collider_id != 0:
		_wallrun_cooldown_dict[_last_wallrun_collider_id] = WALLRUN_COOLDOWN
	
	# Reset wallrun state
	_wallrun_side = 0
	_wallrun_timer = 0.0
	_wallrun_normal = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if is_local_player:
		# Cache horizontal velocity once per frame (avoid repeated calculations)
		_cached_horizontal_velocity = Vector2(velocity.x, velocity.z)
		_cached_horizontal_speed = _cached_horizontal_velocity.length()
		
		# Enable/disable wallrun raycasts based on grounded state (optimization)
		var on_floor := is_on_floor()
		_wall_raycast_left.enabled = not on_floor
		_wall_raycast_right.enabled = not on_floor
		
		_update_timers(delta)
		_handle_state_transitions()
		_handle_gravity(delta)
		_handle_jump()
		_handle_movement(delta)
		_handle_collision_shape(delta)
		_handle_camera_effects(delta)
		
		move_and_slide()
		
		# Cache wall state for wall jump (with coyote time for responsiveness)
		if is_on_wall_only() and not is_on_floor():
			var wall_normal := get_wall_normal()
			# Only cache if it's a real wall (not a slope/floor)
			if abs(wall_normal.y) < WALL_DETECT_THRESHOLD:
				_wall_normal = wall_normal
				_wall_coyote_timer = WALL_COYOTE_TIME
		
		# Track floor state for coyote time
		if is_on_floor():
			_coyote_timer = COYOTE_TIME
			_was_on_floor = true
			_has_wall_jumped = false  # Reset wall jump on landing
			# Reset wallrun state on landing
			if state == MovementState.WALLRUNNING:
				_exit_wallrun()
			_wallrun_side = 0
			_wallrun_normal = Vector3.ZERO
		elif _was_on_floor:
			_was_on_floor = false
		
		# Send position updates to other players (Steam mode only) - Adaptive rate
		if not NetworkManager.is_lan_mode:
			_sync_timer += delta
			
			# Check if we've moved significantly
			var pos_changed := position.distance_squared_to(_last_synced_position) > POSITION_SYNC_THRESHOLD * POSITION_SYNC_THRESHOLD
			var rot_changed := absf(rotation.y - _last_synced_rotation) > ROTATION_SYNC_THRESHOLD
			var has_changed := pos_changed or rot_changed
			
			# Track idle state
			if has_changed:
				_idle_frames = 0
			else:
				_idle_frames += 1
			
			# Use slower sync rate when idle
			var current_sync_rate := SYNC_RATE_IDLE if _idle_frames > IDLE_FRAME_THRESHOLD else SYNC_RATE
			
			if _sync_timer >= current_sync_rate:
				_sync_timer = 0.0
				# Only send if something changed OR periodic heartbeat (every 1 second when idle)
				if has_changed or _idle_frames % 60 == 0:
					_send_position_update()
					_last_synced_position = position
					_last_synced_rotation = rotation.y
	else:
		# Remote player - interpolate towards target position
		_interpolate_remote_player(delta)


var _cooldown_cleanup_counter: int = 0
const COOLDOWN_CLEANUP_INTERVAL: int = 10  # Clean up every N frames

func _update_timers(delta: float) -> void:
	# Coyote time countdown
	if not is_on_floor() and _coyote_timer > 0:
		_coyote_timer -= delta
	
	# Jump buffer countdown
	if _jump_buffer_timer > 0:
		_jump_buffer_timer -= delta
	
	# Wall coyote time countdown
	if _wall_coyote_timer > 0:
		_wall_coyote_timer -= delta
	
	# Slide timers
	if _slide_timer > 0:
		_slide_timer -= delta
	if _slide_cooldown_timer > 0:
		_slide_cooldown_timer -= delta
	
	# Wallrun timer
	if state == MovementState.WALLRUNNING:
		_wallrun_timer += delta
	
	# Wallrun cooldown dict cleanup - batched (only check every N frames)
	_cooldown_cleanup_counter += 1
	if _cooldown_cleanup_counter >= COOLDOWN_CLEANUP_INTERVAL:
		_cooldown_cleanup_counter = 0
		if not _wallrun_cooldown_dict.is_empty():
			var batch_delta := delta * COOLDOWN_CLEANUP_INTERVAL
			var cooldown_keys_to_remove: Array[int] = []
			for collider_id: int in _wallrun_cooldown_dict.keys():
				_wallrun_cooldown_dict[collider_id] -= batch_delta
				if _wallrun_cooldown_dict[collider_id] <= 0:
					cooldown_keys_to_remove.append(collider_id)
			for key: int in cooldown_keys_to_remove:
				_wallrun_cooldown_dict.erase(key)


func _handle_state_transitions() -> void:
	var dominated_velocity := _cached_horizontal_speed  # Use cached value
	var on_floor := is_on_floor()
	var wants_sprint := Input.is_action_pressed("sprint")
	var wants_crouch := Input.is_action_pressed("crouch")
	var has_movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
	
	# Store ground speed before leaving ground
	if on_floor:
		_last_ground_speed = dominated_velocity
	
	# Wallrunning state management
	if state == MovementState.WALLRUNNING:
		# Exit conditions
		var should_exit := false
		
		# Timer exceeded
		if _wallrun_timer >= WALLRUN_MAX_DURATION:
			should_exit = true
		
		# Speed too low
		if dominated_velocity < WALLRUN_MIN_SPEED:
			should_exit = true
		
		# Lost wall contact (check raycast on correct side)
		var wall_raycast := _wall_raycast_left if _wallrun_side == -1 else _wall_raycast_right
		if not wall_raycast.is_colliding():
			should_exit = true
		
		# Landed on ground
		if on_floor:
			_exit_wallrun()
			state = MovementState.WALKING if not wants_sprint else MovementState.SPRINTING
			_has_wall_jumped = false
			return
		
		if should_exit:
			_exit_wallrun()
			state = MovementState.AIRBORNE
		return
	
	# Airborne check - but don't override sliding or wallrunning
	if not on_floor and state != MovementState.SLIDING and state != MovementState.WALLRUNNING:
		state = MovementState.AIRBORNE
		
		# Check for wallrun entry while airborne
		if has_movement:
			var wall_info := _detect_wallrun_surface()
			if wall_info.valid:
				_start_wallrun(wall_info)
		return
	
	# Sliding state management
	if state == MovementState.SLIDING:
		# End slide conditions
		if _slide_timer <= 0 or dominated_velocity < MIN_SLIDE_SPEED or (not wants_crouch and on_floor):
			_slide_cooldown_timer = SLIDE_COOLDOWN
			state = MovementState.CROUCHING if wants_crouch else MovementState.WALKING
		return
	
	# Start slide: crouch while sprinting/moving fast
	if wants_crouch and on_floor and _slide_cooldown_timer <= 0:
		if (state == MovementState.SPRINTING or dominated_velocity > MIN_SLIDE_SPEED) and has_movement:
			_start_slide()
			return
	
	# Ground state transitions
	if on_floor:
		if wants_crouch:
			state = MovementState.CROUCHING
			_current_speed = CROUCH_SPEED
		elif wants_sprint and has_movement:
			state = MovementState.SPRINTING
			_current_speed = SPRINT_SPEED
		else:
			state = MovementState.WALKING
			_current_speed = WALK_SPEED


func _start_slide() -> void:
	state = MovementState.SLIDING
	_slide_timer = SLIDE_DURATION
	
	# Get slide direction from current velocity or input
	var horizontal_vel := Vector2(velocity.x, velocity.z)
	if horizontal_vel.length() > 1.0:
		_slide_direction = Vector3(horizontal_vel.x, 0, horizontal_vel.y).normalized()
	else:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_slide_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Boost into slide
	var current_speed: float = Vector2(velocity.x, velocity.z).length()
	var slide_boost: float = maxf(current_speed, SLIDE_SPEED)
	velocity.x = _slide_direction.x * slide_boost
	velocity.z = _slide_direction.z * slide_boost


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		# Reduced gravity during wallrun
		if state == MovementState.WALLRUNNING:
			velocity.y -= WALLRUN_GRAVITY * delta
			velocity.y = max(velocity.y, -10.0)  # Slower max fall during wallrun
		else:
			velocity.y -= GRAVITY * delta
			# Cap fall speed for TABG floaty feel
			velocity.y = max(velocity.y, -30.0)


func _handle_jump() -> void:
	# Wallrun jump check (highest priority during wallrun)
	if Input.is_action_just_pressed("jump") and state == MovementState.WALLRUNNING:
		_execute_wallrun_jump()
		return
	
	# Wall jump check (higher priority than regular jump when airborne)
	if Input.is_action_just_pressed("jump") and not is_on_floor():
		var can_wall_jump := _wall_coyote_timer > 0 and not _has_wall_jumped
		if can_wall_jump and _wall_normal != Vector3.ZERO:
			_execute_wall_jump()
			return  # Don't process regular jump
	
	# Buffer jump input
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	
	# Can jump conditions
	var can_jump := _coyote_timer > 0 or is_on_floor()
	var wants_jump := _jump_buffer_timer > 0
	
	if wants_jump and can_jump:
		_execute_jump()
	
	# Slide jump - can jump out of slide for momentum
	if Input.is_action_just_pressed("jump") and state == MovementState.SLIDING:
		_execute_slide_jump()


func _execute_jump() -> void:
	velocity.y = JUMP_VELOCITY
	_coyote_timer = 0
	_jump_buffer_timer = 0
	_jump_count += 1
	
	# Bunny hop boost if landing with speed and jumping immediately
	if is_on_floor() and _last_ground_speed > WALK_SPEED:
		var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
		var boosted_speed: float = minf(horizontal_speed * BUNNY_HOP_BOOST, SPRINT_SPEED * 1.3)
		var direction := Vector2(velocity.x, velocity.z).normalized()
		if direction.length() > 0:
			velocity.x = direction.x * boosted_speed
			velocity.z = direction.y * boosted_speed


func _execute_slide_jump() -> void:
	# Powerful jump out of slide preserving momentum
	velocity.y = JUMP_VELOCITY * 1.1
	
	# Keep slide momentum
	var slide_speed := Vector2(velocity.x, velocity.z).length()
	var boosted_speed := slide_speed * 1.05
	velocity.x = _slide_direction.x * boosted_speed
	velocity.z = _slide_direction.z * boosted_speed
	
	_slide_timer = 0
	state = MovementState.AIRBORNE


func _execute_wall_jump() -> void:
	# Smart momentum preservation: remove "into wall" component, keep tangential
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var vel_into_wall := horizontal_vel.dot(_wall_normal)
	
	# If moving into wall, remove that component
	if vel_into_wall < 0:
		horizontal_vel -= _wall_normal * vel_into_wall
	
	# Add push away from wall (prevents re-sticking)
	horizontal_vel += _wall_normal * WALL_PUSH_FORCE
	
	# Apply preserved momentum + push
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z
	
	# Set upward velocity
	velocity.y = WALL_JUMP_VELOCITY
	
	# Mark wall jump as used
	_has_wall_jumped = true
	_wall_coyote_timer = 0.0
	
	# Clear jump buffers to prevent double-jump
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


func _execute_wallrun_jump() -> void:
	# Enhanced jump from wallrun - preserves tangent momentum + strong push
	
	# 1. Preserve tangent velocity (along wall)
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var wall_tangent := _wallrun_normal.cross(Vector3.UP).normalized()
	# Ensure tangent points in movement direction
	if wall_tangent.dot(horizontal_vel) < 0:
		wall_tangent = -wall_tangent
	var tangent_speed := horizontal_vel.project(wall_tangent).length()
	
	# 2. Strong push away from wall
	var push_vel := _wallrun_normal * WALLRUN_JUMP_PUSH
	
	# 3. Combine push + preserved tangent momentum
	horizontal_vel = wall_tangent * tangent_speed + push_vel
	
	# 4. Apply to velocity
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z
	velocity.y = WALLRUN_JUMP_UP
	
	# 5. Exit wallrun state (no exit boost since we're jumping)
	if _last_wallrun_collider_id != 0:
		_wallrun_cooldown_dict[_last_wallrun_collider_id] = WALLRUN_COOLDOWN
	_wallrun_side = 0
	_wallrun_timer = 0.0
	_wallrun_normal = Vector3.ZERO
	state = MovementState.AIRBORNE
	
	# Clear jump buffers
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	match state:
		MovementState.WALKING, MovementState.SPRINTING, MovementState.CROUCHING:
			_handle_ground_movement(direction, delta)
		MovementState.SLIDING:
			_handle_slide_movement(delta)
		MovementState.AIRBORNE:
			_handle_air_movement(direction, delta)
		MovementState.WALLRUNNING:
			_handle_wallrun_movement(delta)


func _handle_ground_movement(direction: Vector3, delta: float) -> void:
	if direction:
		# Accelerate towards target velocity
		var target_velocity := direction * _current_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, GROUND_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, GROUND_ACCELERATION * delta)
	else:
		# Apply friction when no input
		velocity.x *= GROUND_FRICTION
		velocity.z *= GROUND_FRICTION
		
		# Stop completely if very slow
		if Vector2(velocity.x, velocity.z).length() < 0.5:
			velocity.x = 0
			velocity.z = 0


func _handle_slide_movement(delta: float) -> void:
	# Slides maintain direction but allow slight steering
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	if input_dir.length() > 0.1:
		# Slight steering during slide
		var steer_direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		_slide_direction = _slide_direction.lerp(steer_direction, delta * 2.0).normalized()
	
	# Apply slide friction (gradual slowdown)
	velocity.x *= SLIDE_FRICTION
	velocity.z *= SLIDE_FRICTION
	
	# Keep velocity aligned with slide direction
	var speed := Vector2(velocity.x, velocity.z).length()
	velocity.x = _slide_direction.x * speed
	velocity.z = _slide_direction.z * speed


func _handle_air_movement(direction: Vector3, delta: float) -> void:
	# TABG-style high air control - can change direction significantly mid-air
	if direction:
		var current_horizontal := Vector2(velocity.x, velocity.z)
		var current_speed: float = current_horizontal.length()
		
		# Target speed is at least current speed (preserve momentum) or sprint speed
		var target_speed: float = maxf(maxf(current_speed, _last_ground_speed), WALK_SPEED)
		target_speed = minf(target_speed, SPRINT_SPEED * 1.2)  # Cap air speed
		
		var target_velocity: Vector3 = direction * target_speed
		var air_accel: float = AIR_ACCELERATION * AIR_CONTROL
		
		velocity.x = move_toward(velocity.x, target_velocity.x, air_accel * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, air_accel * delta)
	# No air friction - maintain momentum when no input (TABG style)


func _handle_wallrun_movement(delta: float) -> void:
	# 1. Project velocity onto wall plane (remove "into wall" component)
	var horizontal_vel := Vector3(velocity.x, 0, velocity.z)
	var vel_into_wall := horizontal_vel.dot(_wallrun_normal)
	if vel_into_wall < 0:
		horizontal_vel -= _wallrun_normal * vel_into_wall
	
	# 2. Add stick force (small inward push to maintain contact)
	horizontal_vel += -_wallrun_normal * WALLRUN_STICK_FORCE * delta
	
	# 3. Calculate wall tangent (direction along wall)
	var wall_tangent := _wallrun_normal.cross(Vector3.UP).normalized()
	# Ensure tangent points forward (dot with current velocity)
	if wall_tangent.dot(horizontal_vel) < 0:
		wall_tangent = -wall_tangent
	
	# 4. Maintain/accelerate to target speed along wall
	var current_speed := horizontal_vel.length()
	var target_speed := maxf(current_speed, WALLRUN_SPEED)
	horizontal_vel = wall_tangent * target_speed
	
	# 5. Apply input steering (subtle)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length() > 0.1:
		var steer := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
		if steer.length() > 0:
			horizontal_vel = horizontal_vel.lerp(steer.normalized() * target_speed, delta * 2.0)
	
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z


func _handle_collision_shape(delta: float) -> void:
	if not collision_shape or not collision_shape.shape is CapsuleShape3D:
		return
	
	var capsule: CapsuleShape3D = collision_shape.shape
	var target_height: float
	
	match state:
		MovementState.CROUCHING, MovementState.SLIDING:
			target_height = CROUCH_HEIGHT
		_:
			target_height = STAND_HEIGHT
	
	# Smooth height transition
	var current_height: float = capsule.height
	var new_height: float = lerpf(current_height, target_height, delta * 12.0)
	capsule.height = new_height
	
	# Adjust collision shape and mesh position to stay grounded
	# Position is the CENTER of the capsule, so for bottom at y=0, center = height/2
	var center_y: float = new_height / 2.0
	collision_shape.position.y = center_y
	
	# Sync body mesh with collision (for other players to see crouch)
	if body_mesh and body_mesh.mesh is CapsuleMesh:
		var mesh: CapsuleMesh = body_mesh.mesh
		mesh.height = new_height
		body_mesh.position.y = center_y
	
	# Adjust camera for crouch - camera stays at eye level
	var target_cam_y: float
	if state == MovementState.CROUCHING or state == MovementState.SLIDING:
		target_cam_y = new_height - 0.2  # Eyes near top of crouched height
	else:
		target_cam_y = _camera_default_y
	
	camera_mount.position.y = lerpf(camera_mount.position.y, target_cam_y, delta * 10.0)


func _handle_camera_effects(delta: float) -> void:
	var dominated_velocity := _cached_horizontal_speed  # Use cached value
	
	# Head bob
	if is_on_floor() and dominated_velocity > 1.0 and state != MovementState.SLIDING:
		var freq_mult := SPRINT_BOB_MULT if state == MovementState.SPRINTING else 1.0
		var amp_mult := 1.3 if state == MovementState.SPRINTING else 1.0
		_bob_time += delta * BOB_FREQUENCY * freq_mult * (dominated_velocity / WALK_SPEED)
		
		var bob_offset := sin(_bob_time * TAU) * BOB_AMPLITUDE * amp_mult
		var sway_offset := cos(_bob_time * TAU * 0.5) * BOB_AMPLITUDE * 0.4
		
		camera.position.y = lerp(camera.position.y, bob_offset, delta * 15.0)
		camera.position.x = lerp(camera.position.x, sway_offset, delta * 15.0)
	else:
		_bob_time = 0.0
		camera.position.y = lerp(camera.position.y, 0.0, delta * 8.0)
		camera.position.x = lerp(camera.position.x, 0.0, delta * 8.0)
	
	# Camera tilt during slide
	if state == MovementState.SLIDING:
		# Tilt based on slide direction relative to look direction
		var look_dir := -transform.basis.z
		var cross := look_dir.cross(_slide_direction)
		_target_camera_tilt = cross.y * 5.0  # degrees
	else:
		_target_camera_tilt = 0.0
	
	_current_camera_tilt = lerp(_current_camera_tilt, _target_camera_tilt, delta * 8.0)
	
	# Wallrun camera tilt (tilts AWAY from wall for Titanfall feel)
	if state == MovementState.WALLRUNNING:
		# Negative because we tilt AWAY from wall
		# Right wall (side=1) → tilt left (negative rotation)
		# Left wall (side=-1) → tilt right (positive rotation)
		_wallrun_tilt_target = -_wallrun_side * WALLRUN_CAMERA_TILT
	else:
		_wallrun_tilt_target = 0.0
	
	_wallrun_tilt_current = lerp(_wallrun_tilt_current, _wallrun_tilt_target, delta * WALLRUN_CAMERA_TILT_SPEED)
	
	# Combine slide tilt and wallrun tilt
	camera.rotation_degrees.z = _current_camera_tilt + _wallrun_tilt_current


func _input(event: InputEvent) -> void:
	if not is_local_player:
		return
	
	# Mouse look (only when mouse is captured)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY * SettingsManager.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		camera_mount.rotate_x(-event.relative.y * sens)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -PI * 0.45, PI * 0.45)


## Legacy take_damage - use server_apply_damage instead for multiplayer
func take_damage(amount: float, _from_steam_id: int = 0) -> void:
	# Only server should apply damage in multiplayer
	if multiplayer.is_server():
		server_apply_damage(amount, _from_steam_id)


## Check if player is alive
func is_alive() -> bool:
	return alive


# --- Server-Authoritative Combat System ---

## Called by CombatManager on server only - applies damage and syncs to clients
func server_apply_damage(amount: float, attacker_id: int) -> void:
	if not multiplayer.is_server() or not alive:
		return
	
	health = maxf(health - amount, 0.0)
	print("[Player %s] Took %.1f damage from %d, health: %.1f" % [name, amount, attacker_id, health])
	
	# Sync health to all clients
	_rpc_sync_health.rpc(health)
	
	if health <= 0:
		_server_trigger_death(attacker_id)


## RPC to sync health - uses any_peer but verifies sender is server
@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_health(new_health: float) -> void:
	# SECURITY: Only accept from server (peer 1) or local call (0)
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	
	health = new_health
	
	# Update health UI if local player
	if is_local_player:
		_update_health_ui()


func _update_health_ui() -> void:
	# TODO: Update HUD health bar
	pass


## Server triggers death when health reaches 0
func _server_trigger_death(killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	alive = false
	
	# Update game state
	var my_id: int = peer_id if NetworkManager.is_lan_mode else steam_id
	GameState.kill_player(my_id, killer_id)
	
	print("[Player %s] Died! Killed by %d" % [name, killer_id])
	
	# Notify all clients
	_rpc_trigger_death.rpc(killer_id)
	
	# Start respawn timer (server-side)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	_server_respawn()


## RPC for death - any_peer but verify sender is server
@rpc("any_peer", "call_local", "reliable")
func _rpc_trigger_death(killer_id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	
	alive = false
	
	# Disable collision so dead body doesn't block shots
	if collision_shape:
		collision_shape.disabled = true
	
	# Hide player mesh
	if body_mesh:
		body_mesh.visible = false
	if has_node("HeadMesh"):
		$HeadMesh.visible = false
	
	# Disable weapon
	var weapon_manager = get_node_or_null("CameraMount/Camera3D/WeaponManager")
	if weapon_manager:
		weapon_manager.visible = false
	
	if is_local_player:
		# Disable input processing
		set_physics_process(false)
		# Show death UI / spectate mode
		_show_death_screen(killer_id)


func _show_death_screen(killer_id: int) -> void:
	# TODO: Show "You were killed by X" UI
	# TODO: Spectate mode camera
	print("[Player] You were killed by player %d! Respawning in %.1f seconds..." % [killer_id, RESPAWN_TIME])


## Server handles respawn
func _server_respawn() -> void:
	if not multiplayer.is_server():
		return
	
	var spawn_pos: Vector3 = _get_random_spawn_point()
	print("[Player %s] Respawning at %s" % [name, spawn_pos])
	_rpc_respawn.rpc(spawn_pos)


## RPC for respawn - any_peer but verify sender is server
@rpc("any_peer", "call_local", "reliable")
func _rpc_respawn(spawn_position: Vector3) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return
	
	# Reset state
	health = max_health
	alive = true
	position = spawn_position
	velocity = Vector3.ZERO
	
	# Re-enable collision
	if collision_shape:
		collision_shape.disabled = false
	
	# Re-enable weapon
	var weapon_manager = get_node_or_null("CameraMount/Camera3D/WeaponManager")
	if weapon_manager:
		weapon_manager.visible = true
	
	if is_local_player:
		# Local player: HIDE mesh (first-person, don't see own body)
		if body_mesh:
			body_mesh.visible = false
		if has_node("HeadMesh"):
			$HeadMesh.visible = false
		# Re-enable input
		set_physics_process(true)
		_hide_death_screen()
	else:
		# Remote player: SHOW mesh so others can see them
		if body_mesh:
			body_mesh.visible = true
		if has_node("HeadMesh"):
			$HeadMesh.visible = true
	
	print("[Player %s] Respawned at %s with %.1f health" % [name, spawn_position, health])


func _get_random_spawn_point() -> Vector3:
	var spawns: Array[Node] = []
	for node in get_tree().get_nodes_in_group("spawn_points"):
		spawns.append(node)
	
	if spawns.is_empty():
		# Fallback to a default position
		return Vector3(randf_range(-5, 5), 2, randf_range(-5, 5))
	
	return spawns[randi() % spawns.size()].global_position


func _hide_death_screen() -> void:
	# TODO: Hide death UI
	print("[Player] Respawned!")


func get_current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_sprinting() -> bool:
	return state == MovementState.SPRINTING


func is_sliding() -> bool:
	return state == MovementState.SLIDING


func is_crouching() -> bool:
	return state == MovementState.CROUCHING or state == MovementState.SLIDING


func is_wallrunning() -> bool:
	return state == MovementState.WALLRUNNING


func get_movement_state() -> MovementState:
	return state


# --- Network Sync (Steam Mode) ---

func _send_position_update() -> void:
	if NetworkManager.is_lan_mode:
		return
	
	var update_data := {
		"pos_x": position.x,
		"pos_y": position.y,
		"pos_z": position.z,
		"rot_y": rotation.y,
		"cam_x": camera_mount.rotation.x if camera_mount else 0.0,
		"vel_x": velocity.x,
		"vel_y": velocity.y,
		"vel_z": velocity.z
	}
	
	var packet := NetworkManager._make_packet("POS", update_data)
	SteamManager.send_p2p_packet_all(packet, false)  # unreliable for position updates


func _interpolate_remote_player(delta: float) -> void:
	_interpolation_time += delta
	
	# Predict where player should be based on velocity
	var time_factor: float = minf(_interpolation_time, SYNC_RATE)
	var predicted_pos: Vector3 = _target_position + _target_velocity * time_factor
	
	# Smoothly interpolate position with adaptive speed
	var dist: float = position.distance_to(predicted_pos)
	var lerp_speed: float = INTERPOLATION_SPEED
	
	# Speed up if too far behind, slow down if close
	if dist > 2.0:
		lerp_speed = 25.0  # Catch up fast
	elif dist < 0.1:
		lerp_speed = 8.0   # Slow and smooth when close
	
	position = position.lerp(predicted_pos, delta * lerp_speed)
	
	# Smoothly rotate towards target rotation
	rotation.y = lerp_angle(rotation.y, _target_rotation, delta * INTERPOLATION_SPEED)
	
	# Update camera mount rotation for remote players (head look)
	if camera_mount:
		camera_mount.rotation.x = lerp_angle(camera_mount.rotation.x, _target_camera_x, delta * INTERPOLATION_SPEED)


func apply_network_state(data: Dictionary) -> void:
	# Called when receiving position update from network
	_prev_target_position = _target_position
	_target_position = Vector3(
		data.get("pos_x", position.x),
		data.get("pos_y", position.y),
		data.get("pos_z", position.z)
	)
	_target_rotation = data.get("rot_y", rotation.y)
	_target_camera_x = data.get("cam_x", 0.0)
	
	# Store velocity for prediction
	_target_velocity = Vector3(
		data.get("vel_x", 0.0),
		data.get("vel_y", 0.0),
		data.get("vel_z", 0.0)
	)
	
	# Reset interpolation timer
	_interpolation_time = 0.0
