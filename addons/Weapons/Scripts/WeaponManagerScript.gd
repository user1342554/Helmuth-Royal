extends Node3D

var weaponStack : Array[int] = [] #weapons current wielded by play char
var weaponList : Dictionary = {} #all weapons available in the game (key = weapon name, value = wepakn resource)
@export var weaponResources : Array[WeaponResource] #all weapon resources files
@export var startWeapons : Array[WeaponSlot] #the weapon the player character will start with

var cW = null #current weapon
var cWModel = null #current weapon model
var weaponIndex : int = 0

#weapon changes variables
var canChangeWeapons : bool = true
var canUseWeapon : bool = true

@export_group("Keybind variables")
@export var shoot_action : String = "shoot"
@export var reload_action : String = "reload"
@export var weapon_wheel_up_action : String = "weaponWheelUp"
@export var weapon_wheel_down_action : String = "weaponWheelDown"

# Player reference - WeaponManager is at Player/CameraMount/Camera3D/WeaponManager
@onready var playChar : CharacterBody3D = get_node("../../..") as CharacterBody3D
# Camera is the direct parent (Camera3D)
@onready var camera : Camera3D = get_parent() as Camera3D
# CameraMount is Camera3D's parent
@onready var cameraHolder : Node3D = get_node("../..") as Node3D
# These are internal to the WeaponManager scene (use unique names)
@onready var cameraRecoilHolder : Node3D = get_node_or_null("%CameraRecoilHolder")
@onready var weaponContainer : Node3D = %WeaponContainer
@onready var shootManager : Node3D = %ShootManager
@onready var reloadManager : Node3D = %ReloadManager
@onready var ammoManager : Node3D = %AmmunitionManager
@onready var animPlayer : AnimationPlayer = %AnimationPlayer
@onready var animManager : Node3D = %AnimationManager
@onready var audioManager : PackedScene = preload("../../Misc/Scenes/AudioManagerScene.tscn")
@onready var bulletDecal : PackedScene = preload("../../Weapons/Scenes/BulletDecalScene.tscn")
# HUD may not exist - handle gracefully (try multiple possible paths)
@onready var hud : CanvasLayer = _find_hud()

func _find_hud() -> CanvasLayer:
	# Try different possible HUD locations
	var possible_paths := [
		"/root/World/UI/HUD",
		"/root/Main/World/UI/HUD",
	]
	for path in possible_paths:
		var node = get_node_or_null(path)
		if node:
			return node as CanvasLayer
	return null
# LinkComponent may not exist
@onready var linkComponent : Node3D = get_node_or_null("%LinkComponent")

func _ready():
	initialize()
	
func initialize():
	for weapon in weaponResources:
		#create dict to refer weapons
		weaponList[weapon.weaponId] = weapon
		
	for weapo in weaponList.keys():
		#weaponsEmplacements[weapo] = weaponIndex
		cW = weaponList[weapo] #set each weapon to current, to acess properties useful to set up animations slicing and select correct weapon slot
		
		for weaponSlot in weaponContainer.get_children():
			if weaponSlot.weaponId == cW.weaponId: #id correspondant
				
				#if weapon is in the predetermined start weapons list
				for startWeapon in startWeapons:
					if startWeapon.weaponId == cW.weaponId: 
						weaponStack.append(cW.weaponId)
						
				cW.weaponSlot = weaponSlot #get weapon slot script ref from weapon list (allows to get access to model, attack point, ...)
				cWModel = cW.weaponSlot.model
				cWModel.visible = false
				
				forceAttackPointTransformValues(cW.weaponSlot.attackPoint)
				
				cW.bobPos = cW.position
				
	if weaponStack.size() > 0:
		#enable (equip and set up) the first weapon on the weapon stack
		enterWeapon(weaponStack[0])
		
func exitWeapon(nextWeapon : int):
	#this function manage the first part of the weapon switching mechanic
	#in this part, the current weapon is disabled (unequiped and taked down)
	if nextWeapon != cW.weaponId:
		canChangeWeapons = false
		canUseWeapon = false
		if cW.isShooting: cW.isShooting = false
		if cW.isReloading: cW.isReloading = false
		
		if cW.unequipAnimName != "":
			animManager.playAnimation("UnequipAnim%s" % cW.weaponName, cW.unequipAnimSpeed, false)
		await get_tree().create_timer(cW.unequipTime).timeout
		
		cWModel.visible = false
		
		enterWeapon(nextWeapon)
	
func enterWeapon(nextWeapon : int):
	#this function manage the second part of the weapon switching mechanic
	#in this part, the next weapon is enabled (equiped and set up)
	cW = weaponList[nextWeapon]
	nextWeapon = 0
	cWModel = cW.weaponSlot.model
	cWModel.visible = true
	
	shootManager.getCurrentWeapon(cW)
	reloadManager.getCurrentWeapon(cW)
	animManager.getCurrentWeapon(cW, cWModel)
	
	weaponSoundManagement(cW.equipSound, cW.equipSoundSpeed)
	
	animPlayer.playback_default_blend_time = cW.animBlendTime
	
	if cW.equipAnimName != "":
		animManager.playAnimation("EquipAnim%s" % cW.weaponName, cW.equipAnimSpeed, false)
	await get_tree().create_timer(cW.equipTime).timeout
	
	if cW.isShooting: cW.isShooting = false
	if cW.isReloading: cW.isReloading = false
	canUseWeapon = true
	canChangeWeapons = true
	
func _process(_delta : float):
	# CRITICAL: Only local player processes weapon input
	# This prevents remote players from controlling weapons
	if playChar == null or not playChar.is_local_player:
		return
	
	if cW != null and cWModel != null and canUseWeapon:
		weaponInputs()
		
		reloadManager.autoReload()
		
	displayStats()
	
func weaponInputs():
	if Input.is_action_pressed(shoot_action): shootManager.shoot()
			
	if Input.is_action_just_pressed(reload_action): reloadManager.reload()
	
	if Input.is_action_just_pressed(weapon_wheel_up_action):
		if canChangeWeapons and !cW.isShooting and !cW.isReloading:
			weaponIndex = min(weaponIndex + 1, weaponStack.size() - 1) #from first element of weapon stack to last element 
			changeWeapon(weaponStack[weaponIndex])
			
	if Input.is_action_just_pressed(weapon_wheel_down_action):
		if canChangeWeapons and !cW.isShooting and !cW.isReloading:
			weaponIndex = max(weaponIndex - 1, 0) #from last element of weapon stack to first element 
			changeWeapon(weaponStack[weaponIndex])
		
func displayStats():
	if hud == null or cW == null:
		return
	if hud.has_method("displayWeaponStack"):
		hud.displayWeaponStack(weaponStack.size())
	if hud.has_method("displayWeaponName"):
		hud.displayWeaponName(cW.weaponName)
	if hud.has_method("displayTotalAmmoInMag"):
		hud.displayTotalAmmoInMag(cW.totalAmmoInMag, cW.nbProjShotsAtSameTime)
	if hud.has_method("displayTotalAmmo"):
		hud.displayTotalAmmo(ammoManager.ammoDict[cW.ammoType], cW.nbProjShotsAtSameTime)
	
func changeWeapon(nextWeapon : int):
	if canChangeWeapons and !cW.isShooting and !cW.isReloading:
		exitWeapon(nextWeapon)
	else:
		push_error("Can't change weapon now")
		return 
	
func displayMuzzleFlash():
	#create a muzzle flash instance, and display it at the indicated point
	if cW.muzzleFlashRef != null:
		var muzzleFlashInstance = cW.muzzleFlashRef.instantiate()
		add_child(muzzleFlashInstance)
		muzzleFlashInstance.global_position = cW.weaponSlot.muzzleFlashSpawner.global_position
		muzzleFlashInstance.emitting = true
	else:
		push_error("%s doesn't have a muzzle flash reference" % cW.weaponName)
		return
		
func displayBulletHole(colliderPoint : Vector3, colliderNormal : Vector3):
	#create a muzzle flash instance, and display it at the indicated point
	var bulletDecalInstance = bulletDecal.instantiate()
	get_tree().get_root().add_child(bulletDecalInstance)
	bulletDecalInstance.global_position = colliderPoint
	bulletDecalInstance.look_at(colliderPoint - colliderNormal, Vector3.UP)
	bulletDecalInstance.rotate_object_local(Vector3(1.0, 0.0, 0.0), 90)
	
func weaponSoundManagement(soundName : AudioStream, soundSpeed : float):
	var audioIns : AudioStreamPlayer3D = audioManager.instantiate()
	get_tree().get_root().add_child.call_deferred(audioIns)
	#makes sure the node is in the scene tree
	await get_tree().process_frame
	if audioIns.is_inside_tree():
		audioIns.global_transform = cW.weaponSlot.attackPoint.global_transform
		audioIns.bus = "Sfx"
		audioIns.pitch_scale = soundSpeed
		audioIns.stream = soundName
		audioIns.play()
	else:
		print("The sound can't be played, AudioStreamPlayer3D instance is not in the scene tree")
	
func forceAttackPointTransformValues(attackPoint : Marker3D):
	#reset the attack points rotation values, to ensure that the projectiles will be shot in the correct direction
	if attackPoint.rotation != Vector3.ZERO: attackPoint.rotation = Vector3.ZERO


## Play shot sound for remote players (called by CombatManager)
func play_remote_shot_sound() -> void:
	if cW != null and cW.shootSound:
		weaponSoundManagement(cW.shootSound, cW.shootSoundSpeed)
