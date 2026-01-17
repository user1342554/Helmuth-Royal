extends CharacterBody3D
## DamageDummy - A training dummy that shows damage numbers when hit
## Used for testing weapons and seeing damage output

@export var max_health: float = 1000.0
@export var auto_heal: bool = true
@export var heal_delay: float = 3.0
@export var heal_rate: float = 50.0  # HP per second

var current_health: float
var time_since_hit: float = 0.0
var total_damage_received: float = 0.0
var damage_in_last_second: float = 0.0
var dps_timer: float = 0.0
var recent_damages: Array[float] = []

@onready var health_bar: ProgressBar = $HealthBar3D/SubViewport/HealthBar
@onready var health_label: Label = $HealthBar3D/SubViewport/HealthLabel
@onready var dps_label: Label = $HealthBar3D/SubViewport/DPSLabel
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_bar_sprite: Sprite3D = $HealthBar3D
@onready var sub_viewport: SubViewport = $HealthBar3D/SubViewport


func _ready() -> void:
	current_health = max_health
	
	# Set up viewport texture for the 3D health bar
	if health_bar_sprite and sub_viewport:
		health_bar_sprite.texture = sub_viewport.get_texture()
	
	# Create material for the mesh if it doesn't have one
	if mesh and not mesh.material_override:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.2, 0.2)
		mesh.material_override = mat
	
	_update_health_display()


func _process(delta: float) -> void:
	time_since_hit += delta
	dps_timer += delta
	
	# Calculate DPS (damage per second) over rolling 1-second window
	if dps_timer >= 0.1:
		dps_timer = 0.0
		# Remove old damage entries (older than 1 second)
		var current_time := Time.get_ticks_msec() / 1000.0
		while recent_damages.size() > 0 and recent_damages[0] < current_time - 1.0:
			recent_damages.remove_at(0)
	
	# Auto-heal after delay
	if auto_heal and time_since_hit > heal_delay and current_health < max_health:
		current_health = minf(current_health + heal_rate * delta, max_health)
		_update_health_display()
	
	# Flash red when recently hit
	if mesh and time_since_hit < 0.1:
		mesh.material_override.albedo_color = Color(1, 0.3, 0.3)
	elif mesh and mesh.material_override:
		mesh.material_override.albedo_color = Color(0.8, 0.2, 0.2)


## Called by CombatManager for player-style damage
func server_apply_damage(amount: float, _attacker_id: int) -> void:
	_take_damage(amount)


## Called by CombatManager for hitscan weapons
func hitscanHit(damage: float, _direction: Vector3, hit_position: Vector3) -> void:
	_take_damage(damage)
	_spawn_damage_number(damage, hit_position)


## Called by projectiles
func projectileHit(damage: float, _direction: Vector3) -> void:
	_take_damage(damage)
	_spawn_damage_number(damage, global_position + Vector3.UP * 1.5)


func _take_damage(amount: float) -> void:
	current_health = maxf(current_health - amount, 0.0)
	total_damage_received += amount
	time_since_hit = 0.0
	
	# Track for DPS calculation
	var current_time := Time.get_ticks_msec() / 1000.0
	for i in range(int(amount)):
		recent_damages.append(current_time)
	
	_update_health_display()
	
	# Reset health if "dead"
	if current_health <= 0:
		current_health = max_health
		_update_health_display()


func _update_health_display() -> void:
	if health_bar:
		health_bar.value = (current_health / max_health) * 100.0
	
	if health_label:
		health_label.text = "%d / %d" % [int(current_health), int(max_health)]
	
	if dps_label:
		var dps := recent_damages.size()
		dps_label.text = "DPS: %d" % dps


func _spawn_damage_number(damage: float, spawn_pos: Vector3) -> void:
	# Create floating damage number
	var damage_label := Label3D.new()
	damage_label.text = str(int(damage))
	damage_label.font_size = 64
	damage_label.outline_size = 8
	damage_label.modulate = Color(1, 1, 0)  # Yellow
	damage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	damage_label.no_depth_test = true
	
	get_tree().get_root().add_child(damage_label)
	damage_label.global_position = spawn_pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	
	# Animate floating up and fading
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(damage_label, "global_position", damage_label.global_position + Vector3.UP * 1.5, 1.0)
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(damage_label.queue_free)
