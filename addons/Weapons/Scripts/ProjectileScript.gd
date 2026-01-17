extends RigidBody3D

#properties variables
var isExplosive : bool = false
var direction : Vector3 
var damage : float
var timeBeforeVanish : float 
var bodiesList : Array = []
var explosion_radius : float = 8.0  # Radius for explosive damage
var shooter_id : int = 0  # ID of the player who fired this projectile

#references variables
@onready var mesh = $Mesh
@onready var hitbox = $Hitbox

@export_group("Sound variables")
@onready var audioManager : PackedScene = preload("../../Misc/Scenes/AudioManagerScene.tscn")
@export var explosionSound : AudioStream

@export_group("Particles variables")
@onready var particlesManager : PackedScene = preload("../../Misc/Scenes/ParticlesManagerScene.tscn")

func _process(delta):
	if timeBeforeVanish > 0.0: timeBeforeVanish -= delta
	else: hit(null)
		
func _on_body_entered(body):
	hit(body)

func hit(direct_hit_body):
	mesh.visible = false
	hitbox.set_deferred("disabled", true)
	
	if isExplosive:
		explode(direct_hit_body)
	else:
		# Non-explosive projectile - just damage what we hit
		if direct_hit_body:
			applyDamage(direct_hit_body, damage)
		queue_free()

func applyDamage(body, dmg: float):
	# Apply damage to various target types
	
	# Players (multiplayer)
	if body is CharacterBody3D and body.has_method("server_apply_damage"):
		body.server_apply_damage(dmg, shooter_id)
		return
	
	# Damage dummies and targets with projectileHit
	if body.has_method("projectileHit"):
		body.projectileHit(dmg, direction)
		return
	
	# Hitscan targets
	if body.has_method("hitscanHit"):
		body.hitscanHit(dmg, direction, global_position)
		return
	
	# Legacy support for group-based detection
	if body.is_in_group("Enemies") and body.has_method("projectileHit"):
		body.projectileHit(dmg, direction)
			
	if body.is_in_group("HitableObjects") and body.has_method("projectileHit"):
		body.projectileHit(dmg, direction)
	
func explode(direct_hit_body):
	# Play explosion effects
	weaponSoundManagement(explosionSound)
	
	var particlesIns : ParticlesManager
	if particlesIns == null:
		particlesIns = particlesManager.instantiate()
		particlesIns.particleToEmit = "Explosion"
		particlesIns.global_transform = global_transform
		get_tree().get_root().add_child.call_deferred(particlesIns)
	
	# Apply explosion damage to all nearby bodies
	var explosion_pos = global_position
	var space_state = get_world_3d().direct_space_state
	
	# Get all bodies in explosion radius using a sphere query
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), explosion_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var results = space_state.intersect_shape(query, 32)
	
	for result in results:
		var body = result.collider
		if body == self:
			continue
		
		# Calculate damage falloff based on distance
		var distance = explosion_pos.distance_to(body.global_position)
		var damage_multiplier = 1.0 - (distance / explosion_radius)
		damage_multiplier = clampf(damage_multiplier, 0.2, 1.0)  # Minimum 20% damage at edge
		
		var explosion_damage = damage * damage_multiplier
		applyDamage(body, explosion_damage)
	
	queue_free()
	
func weaponSoundManagement(soundName):
	if soundName != null:
		var audioIns = audioManager.instantiate()
		audioIns.global_transform = global_transform
		get_tree().get_root().add_child(audioIns)
		audioIns.bus = "Sfx"
		audioIns.volume_db = 5.0
		audioIns.stream = soundName
		audioIns.play()
