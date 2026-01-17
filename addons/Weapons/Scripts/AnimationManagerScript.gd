extends Node3D

var cW
var cWModel : Node3D

# Path from AnimationManager: WeaponManager -> Camera3D -> CameraMount -> Player
@onready var cameraHolder : Node3D = get_node_or_null("../../..")  # CameraMount
@onready var playChar : CharacterBody3D = get_node_or_null("../../../..") as CharacterBody3D  # Player
@onready var animPlayer : AnimationPlayer = %AnimationPlayer
@onready var weaponManager : Node3D = get_parent()  # WeaponManager is parent

# Track mouse movement for sway
var _mouse_input: Vector2 = Vector2.ZERO
var _input_direction: Vector2 = Vector2.ZERO

func getCurrentWeapon(currWeap, currweaponManagerodel):
	#get current weapon model and resources
	cW = currWeap
	cWModel = currweaponManagerodel
	
func _process(delta: float):
	# Only run for local player
	if playChar == null or not playChar.is_local_player:
		return
	if cW != null and cWModel != null:
		# Get input direction from player movement input
		_input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		weaponTilt(_input_direction, delta)
		weaponSway(_mouse_input, delta)
		weaponBob(playChar.velocity.length(), delta)
		# Reset mouse input after using it
		_mouse_input = Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Only process input for local player
	if playChar == null or not playChar.is_local_player:
		return
	if event is InputEventMouseMotion:
		_mouse_input = event.relative
		
func weaponTilt(playCharInput, delta):
	#rotate weapon model on the z axis depending on the player character direction orientation (left or right)
	cWModel.rotation.z = lerp(cWModel.rotation.z, playCharInput.x * cW.tiltRotAmount, cW.tiltRotSpeed * delta)
	
func weaponSway(mouseInput, delta):
	#clamp mouse movement
	mouseInput.x = clamp(mouseInput.x, cW.minSwayVal.x, cW.maxSwayVal.x)
	mouseInput.y = clamp(mouseInput.y, cW.minSwayVal.y, cW.maxSwayVal.y)
	
	#lerp weapon position based on mouse movement, relative to the initial position
	cWModel.position.x = lerp(cWModel.position.x, cW.position[0].x + (mouseInput.x * cW.swayAmountPos) * delta, cW.swaySpeedPos)
	cWModel.position.y = lerp(cWModel.position.y, cW.position[0].y - (mouseInput.y * cW.swayAmountPos) * delta, cW.swaySpeedPos)
	
	#lerp weapon rotation based on mouse movement, relative to the initial rotation
	#use of rad_to_deg here, because we rotate the model based on degrees, but the saved weapon rotation is in radians
	cWModel.rotation_degrees.y = lerp(cWModel.rotation_degrees.y, rad_to_deg(cW.position[1].y) -  (mouseInput.x * cW.swayAmountRot) * delta, cW.swaySpeedRot)
	cWModel.rotation_degrees.x = lerp(cWModel.rotation_degrees.x, rad_to_deg(cW.position[1].x) + (mouseInput.y * cW.swayAmountRot) * delta, cW.swaySpeedRot)
	
func weaponBob(vel : float, delta):
	var bobFreq : float = cW.bobFreq
	
	#change bob frequency for weapon idle
	if vel < 4.0:
		bobFreq /= cW.onIdleBobFreqDivider
		
	#smoothly move the weapon model in the form of a curve (hence the use of sin)
	cWModel.position.y = lerp(cWModel.position.y, cW.bobPos[0].y + sin(Time.get_ticks_msec() * bobFreq) * cW.bobAmount * vel / 10, cW.bobSpeed * delta)
	cWModel.position.x = lerp(cWModel.position.x, cW.bobPos[0].x + sin(Time.get_ticks_msec() * bobFreq * 0.5) * cW.bobAmount * vel / 10, cW.bobSpeed * delta)

func playAnimation(animName : String, animSpeed : float, hasToRestartAnim : bool):
	if cW != null and animPlayer != null:
		#restart current anim if needed (for example restart shoot animation while still playing)
		if hasToRestartAnim and animPlayer.current_animation == animName:
			animPlayer.seek(0, true)
		#play animation
		animPlayer.play("%s" % animName, -1, animSpeed)
		
