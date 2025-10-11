extends Control

@onready var label = $Panel/Label
@onready var panel = $Panel
@onready var timer = $Timer

func _ready():
	modulate.a = 0.0
	hide()

func show_message(text: String, duration: float = 2.0):
	label.text = text
	show()
	
	# Fade in
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	
	# Start timer for fade out
	timer.wait_time = duration
	timer.start()

func _on_timer_timeout():
	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(hide)

