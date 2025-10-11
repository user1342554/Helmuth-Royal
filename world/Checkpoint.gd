extends Area3D

var activated = false

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.name == "Player" and not activated:
		activated = true
		
		# Find Toast UI in the scene tree
		var toast = get_tree().root.find_child("Toast", true, false)
		if toast and toast.has_method("show_message"):
			toast.show_message("Checkpoint reached")
		
		# Optional: Visual feedback
		var mesh = $MeshInstance3D
		if mesh:
			var mat = mesh.material
			if mat:
				mat.albedo_color = Color.GREEN
				mat.emission = Color.GREEN
