@tool
class_name Searchlight
extends Control

# Searchlight：1400×1400 暖白 radial glow，在 (-300, -300) 和 (600, -100) 之间
# ease-in-out alternate 18s 漂移。design: opacity ~0.10/0.04，screen blend.
# 复用 RadialGlow 自绘，外层 Control 控制 position tween。

@export var travel_seconds: float = 18.0
@export var start_pos: Vector2 = Vector2(-300, -300)
@export var end_pos: Vector2 = Vector2(600, -100)
@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
		_restart_tween()

var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Engine.is_editor_hint():
		_restart_tween()

func _restart_tween() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	if not enabled or not is_inside_tree():
		return
	position = start_pos
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "position", end_pos, travel_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", start_pos, travel_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
