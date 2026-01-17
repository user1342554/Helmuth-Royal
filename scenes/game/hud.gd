extends CanvasLayer
## HUD - Displays weapon info, ammo counter, health bar, and other game UI

@onready var ammo_label: Label = $AmmoContainer/AmmoRow/AmmoLabel
@onready var reserve_label: Label = $AmmoContainer/AmmoRow/ReserveLabel
@onready var weapon_name_label: Label = $AmmoContainer/WeaponName
@onready var health_bar: ProgressBar = $HealthContainer/HealthBar
@onready var health_label: Label = $HealthContainer/HealthLabel

var current_ammo: int = 0
var max_ammo: int = 0
var reserve_ammo: int = 0
var current_health: float = 100.0
var max_health: float = 100.0


func _ready() -> void:
	# Initialize with default values
	_update_ammo_display()
	_update_health_display()


func _process(_delta: float) -> void:
	# Try to get health from local player
	_update_health_from_player()


func _update_health_from_player() -> void:
	var local_player = _get_local_player()
	if local_player:
		var player_health = local_player.get("health")
		var player_max_health = local_player.get("max_health")
		if player_health != null:
			current_health = player_health
		if player_max_health != null:
			max_health = player_max_health
		_update_health_display()


func _get_local_player() -> Node:
	# Try to find local player
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.get("is_local_player") == true:
			return player
	
	# Fallback: try NetworkManager
	if has_node("/root/NetworkManager"):
		var nm = get_node("/root/NetworkManager")
		if nm.has_method("get_local_player"):
			return nm.get_local_player()
	
	return null


func _update_health_display() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = "%d / %d" % [int(current_health), int(max_health)]


## Called by WeaponManagerScript to update ammo in magazine
func displayTotalAmmoInMag(ammo: int, _shots_per_round: int = 1) -> void:
	current_ammo = ammo
	_update_ammo_display()


## Called by WeaponManagerScript to update reserve ammo
func displayTotalAmmo(ammo: int, _shots_per_round: int = 1) -> void:
	reserve_ammo = ammo
	_update_ammo_display()


## Called by WeaponManagerScript to show weapon name
func displayWeaponName(weapon_name: String) -> void:
	if weapon_name_label:
		weapon_name_label.text = weapon_name


## Called by WeaponManagerScript to show weapon stack count
func displayWeaponStack(count: int) -> void:
	# Could display weapon count indicator here
	pass


func _update_ammo_display() -> void:
	if ammo_label:
		ammo_label.text = str(current_ammo)
	if reserve_label:
		reserve_label.text = "/ " + str(reserve_ammo)
