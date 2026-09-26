extends Button

# Stored as a path rather than a PackedScene so scenes can link to each other
# (e.g. title <-> credits) without a cyclic load that leaves one side null.
@export_file("*.tscn", "*.scn") var new_scene: String

func _ready() -> void:
	self.pressed.connect(_button_press)

func _button_press() -> void:
	get_tree().change_scene_to_file(new_scene)
