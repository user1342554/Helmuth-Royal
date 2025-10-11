extends CanvasLayer

# Performance optimized loading screen

@onready var progress_bar = $Panel/VBoxContainer/ProgressBar
@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var spinner = $Panel/VBoxContainer/Spinner

var _rotation_speed := 3.0

func _ready():
	visible = false

func _process(delta):
	if visible and spinner:
		spinner.rotation += _rotation_speed * delta

func show_loading(status_text: String = "Loading..."):
	status_label.text = status_text
	progress_bar.value = 0
	visible = true

func update_progress(current: int, total: int, status_text: String = ""):
	if total > 0:
		progress_bar.value = (float(current) / float(total)) * 100.0
	
	if not status_text.is_empty():
		status_label.text = status_text

func hide_loading():
	visible = false

func set_status(status_text: String):
	status_label.text = status_text

