extends Camera3D

# Main camera is the parent of WeaponManager (WeaponManager is child of Camera3D)
@onready var mainCam : Camera3D = get_node_or_null("../..") as Camera3D

func _process(_delta: float):
	if mainCam != null: 
		global_transform = mainCam.global_transform
