extends Control

# 致谢页（page mode）：跳转自主菜单。兼容 overlay 模式。

signal closed

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

@onready var back_btn: Control = $Footer/BackButton

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	back_btn.pressed.connect(_on_back)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _on_back() -> void:
	AudioManager.play_ui_click()
	closed.emit()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		queue_free()
