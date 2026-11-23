## Test fixture for test_save_safety.gd: a Resource whose script flags that it ran. A crafted .tres that names this
## script runs _init() the moment it is loaded, which is what a malicious shared settings file would use.
extends Resource

func _init() -> void:
	Engine.set_meta("save_safety_ran", true)
