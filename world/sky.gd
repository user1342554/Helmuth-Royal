@tool
extends Node

@export_range(0.0, 1.0) var time_of_day := 10  # 0.25 = midday
@export_range(-90.0, 90.0, 1.0) var latitude := 45.0

@export var auto_cycle := false  # Automatischer Tag/Nacht-Zyklus (disabled - always day)
@export var cycle_speed := 0.01  # Geschwindigkeit des Zyklus (niedriger = langsamer)

@export var sky_material: ShaderMaterial = preload("res://world/materials/SkyMaterial.tres")

@export var environment: WorldEnvironment

@export var sun: DirectionalLight3D

var time_elapsed := 0.0

func kelvin_to_rgb(temp_kelvin: float) -> Color:
	var temperature = temp_kelvin / 100.0

	var red: float
	var green: float
	var blue: float

	if temperature <= 66.0:
		red = 255.0
	else:
		red = temperature - 60.0
		red = 329.698727446 * pow(red, -0.1332047592)
		red = clamp(red, 0.0, 255.0)

	if temperature <= 66.0:
		green = 99.4708025861 * log(temperature) - 161.1195681661
		green = clamp(green, 0.0, 255.0)
	else:
		green = temperature - 60.0
		green = 288.1221695283 * pow(green, -0.0755148492)
		green = clamp(green, 0.0, 255.0)

	if temperature >= 66.0:
		blue = 255.0
	elif temperature <= 19.0:
		blue = 0.0
	else:
		blue = temperature - 10.0
		blue = 138.5177312231 * log(blue) - 305.0447927307
		blue = clamp(blue, 0.0, 255.0)

	return Color(red / 255.0, green / 255.0, blue / 255.0)


func _process(delta: float) -> void:
	# Update time of day if auto cycle is enabled
	if auto_cycle:
		time_elapsed += delta
		time_of_day = fmod(time_elapsed * cycle_speed, 1.0)
	
	# Update sun rotation based on time of day and latitude
	if sun:
		# Calculate sun angle (0 = horizon at sunrise, PI = horizon at sunset)
		var sun_angle = time_of_day * TAU  # Full rotation
		var lat_rad = deg_to_rad(latitude)
		
		# Create rotation for sun based on time and latitude
		var sun_rotation = Basis()
		sun_rotation = sun_rotation.rotated(Vector3.RIGHT, sun_angle - PI/2)  # Day/night rotation
		sun_rotation = sun_rotation.rotated(Vector3.FORWARD, lat_rad)  # Latitude tilt
		
		sun.global_transform.basis = sun_rotation
		
		# Update shader with sun rotation for stars
		sky_material.set_shader_parameter("stars_rotation", sun.global_basis)
		
		# Calculate sun energy and color based on position
		var sun_weight: float = sun.global_basis.z.normalized().dot(Vector3.UP)
		var sun_energy = smoothstep(-0.09, -0.00, sun_weight)
		sun_weight = pow(clamp(sun_weight, 0.0, 1.0), 0.5)
		var sun_color = kelvin_to_rgb(lerpf(1500, 6500, sun_weight))
		sun.light_color = sun_color
		sun.light_energy = sun_energy
	
	# Animate clouds
	if sky_material:
		# Cloud movement
		var cloud_speed = Vector3(0.02, 0.0, 0.01)  # Movement speed
		var cloud_offset = cloud_speed * time_elapsed
		sky_material.set_shader_parameter("cloud_shape_offset", cloud_offset)
		
		# Cirrus clouds movement (higher clouds, different speed)
		var cirrus_offset = Vector2(time_elapsed * 0.005, time_elapsed * 0.003)
		sky_material.set_shader_parameter("cirrus_offset", cirrus_offset)
