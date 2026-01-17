extends Node3D
## AmmoRefiller - Refills player ammo when they press E nearby

@export var ammoToRefill : Dictionary = {
	"LightAmmo": 30,
	"MediumAmmo": 30,
	"HeavyAmmo": 5,
	"ShellAmmo": 16,
	"RocketAmmo": 2,
	"GrenadeAmmo": 4
}
@export var respawn_time: float = 30.0
@export var destroy_on_pickup: bool = false

var is_available: bool = true
var player_in_range: Node3D = null

@onready var mesh: Node3D = get_node_or_null("Model")
@onready var detect_area: Area3D = get_node_or_null("DetectArea")


func _ready() -> void:
	# Hide interact label initially
	if interact_label:
		interact_label.visible = false


func _process(_delta: float) -> void:
	if not is_available:
		return
	
	# Check for interaction input when player is in range
	if player_in_range and Input.is_action_just_pressed("interact"):
		_give_ammo_to_player(player_in_range)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		# Check if it's the local player
		if body.get("is_local_player") == true:
			player_in_range = body


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null


func _give_ammo_to_player(player: Node3D) -> void:
	if not is_available:
		return
	
	# Find the weapon manager on the player
	var weapon_manager = player.get_node_or_null("CameraMount/Camera3D/WeaponManager")
	if not weapon_manager:
		print("[AmmoRefiller] Could not find WeaponManager on player")
		return
	
	# Try to get ammo manager
	var ammo_manager = weapon_manager.get_node_or_null("%AmmunitionManager")
	if not ammo_manager:
		ammo_manager = weapon_manager.get("ammoManager")
	
	if not ammo_manager:
		print("[AmmoRefiller] Could not find AmmunitionManager")
		return
	
	# Add ammo to player's reserves
	var ammo_given := false
	for ammo_type in ammoToRefill.keys():
		if ammo_type in ammo_manager.ammoDict:
			var current: int = ammo_manager.ammoDict[ammo_type]
			var max_ammo: int = ammo_manager.maxNbPerAmmoDict.get(ammo_type, 999)
			var to_add: int = ammoToRefill[ammo_type]
			
			if current < max_ammo:
				ammo_manager.ammoDict[ammo_type] = mini(current + to_add, max_ammo)
				ammo_given = true
				print("[AmmoRefiller] Added %d %s (now %d)" % [to_add, ammo_type, ammo_manager.ammoDict[ammo_type]])
	
	if ammo_given:
		_pickup_effect()


func _pickup_effect() -> void:
	is_available = false
	
	# Hide visuals
	if mesh:
		mesh.visible = false
	
	# Disable detection area
	if detect_area:
		for child in detect_area.get_children():
			if child is CollisionShape3D:
				child.disabled = true
	
	player_in_range = null
	
	if destroy_on_pickup:
		queue_free()
	else:
		_start_respawn_timer()


func _start_respawn_timer() -> void:
	await get_tree().create_timer(respawn_time).timeout
	_respawn()


func _respawn() -> void:
	is_available = true
	
	# Show visuals
	if mesh:
		mesh.visible = true
	
	# Re-enable detection area
	if detect_area:
		for child in detect_area.get_children():
			if child is CollisionShape3D:
				child.disabled = false
