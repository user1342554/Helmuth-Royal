extends RigidBody3D

# References
var owner_player: Node3D = null  # The player who owns this staff
var combat_cube: Node3D = null   # The cube to connect to

# Visual
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Staff appearance
var staff_thickness := 0.05  # 5cm diameter
var staff_color := Color(0.6, 0.4, 0.2)  # Brown wood

# Auto-mode floating position (relative to player)
var auto_mode_offset := Vector3(0.5, 0.8, 0.3)  # Float beside player
var auto_mode_rotation := Vector3(-45, 0, 15)  # Diagonal angle

func _ready():
	# Physics setup
	gravity_scale = 0.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = 10.0
	angular_damp = 10.0
	
	# Collision: Layer 2 (Combat), Mask 7 (World+Combat+Projectiles, NOT Players)
	collision_layer = 2
	collision_mask = 7
	
	print("Combat staff ready")

func _physics_process(delta):
	if not is_instance_valid(owner_player) or not is_instance_valid(combat_cube):
		return
	
	# Check if cube is in manual control mode
	var is_manual_mode = false
	if owner_player.has_method("is_cube_manual_control"):
		is_manual_mode = owner_player.is_cube_manual_control()
	elif "cube_manual_control" in owner_player:
		is_manual_mode = owner_player.cube_manual_control
	
	if is_manual_mode:
		# Manual mode: Connect player hand to cube
		_update_connected_mode()
	else:
		# Auto mode: Float beside player
		_update_floating_mode()

func _update_connected_mode():
	"""Staff stretches from player hand to cube"""
	# Get positions
	var hand_pos = owner_player.global_position + Vector3(0.3, 1.2, 0.2)  # Right hand area
	var cube_pos = combat_cube.global_position
	
	# Calculate midpoint
	var midpoint = (hand_pos + cube_pos) / 2.0
	
	# Calculate direction and length
	var direction = cube_pos - hand_pos
	var length = direction.length()
	
	# Update position
	global_position = midpoint
	
	# Update rotation to point from hand to cube
	if length > 0.01:
		look_at(cube_pos, Vector3.UP)
	
	# Update mesh and collision shape
	_update_staff_geometry(length)

func _update_floating_mode():
	"""Staff floats beside player, not connected"""
	# Target position beside player
	var target_pos = owner_player.global_position + auto_mode_offset
	
	# Smooth movement
	global_position = global_position.lerp(target_pos, 0.2)
	
	# Set diagonal rotation
	rotation_degrees = auto_mode_rotation
	
	# Set default length
	_update_staff_geometry(1.0)

func _update_staff_geometry(length: float):
	"""Update the staff's mesh and collision to match length"""
	if not is_instance_valid(mesh_instance) or not is_instance_valid(collision_shape):
		return
	
	# Update capsule mesh
	var capsule_mesh = mesh_instance.mesh as CapsuleMesh
	if capsule_mesh:
		capsule_mesh.radius = staff_thickness
		capsule_mesh.height = length
	
	# Update capsule collision
	var capsule_shape = collision_shape.shape as CapsuleShape3D
	if capsule_shape:
		capsule_shape.radius = staff_thickness
		capsule_shape.height = length

func set_owner_player(player: Node3D):
	"""Set the player who owns this staff"""
	owner_player = player

func set_combat_cube(cube: Node3D):
	"""Set the cube to connect to"""
	combat_cube = cube

func is_cube_manual_control() -> bool:
	"""Check if cube is in manual control mode"""
	if not is_instance_valid(owner_player):
		return false
	
	if owner_player.has_method("is_cube_manual_control"):
		return owner_player.is_cube_manual_control()
	elif "cube_manual_control" in owner_player:
		return owner_player.cube_manual_control
	
	return false
