@tool
class_name CornerBrackets
extends Control

# 4 个角的 80×80 L 形装饰线，对应 design persistent chrome #11
# 56px inset from canvas edges (注意 hazard frame 在 24px，corner brackets 在 56px，不冲突)

@export var bracket_size: float = 80.0:
	set(value):
		bracket_size = value
		queue_redraw()
@export var corner_inset: float = 56.0:
	set(value):
		corner_inset = value
		queue_redraw()
@export var line_color: Color = UiPalette.RED_DIM:
	set(value):
		line_color = value
		queue_redraw()
@export var line_thickness: float = 2.0:
	set(value):
		line_thickness = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := bracket_size
	var i := corner_inset
	var w := size.x
	var h := size.y
	var c := line_color
	var t := line_thickness
	# top-left
	draw_line(Vector2(i, i), Vector2(i + s, i), c, t)
	draw_line(Vector2(i, i), Vector2(i, i + s), c, t)
	# top-right
	draw_line(Vector2(w - i, i), Vector2(w - i - s, i), c, t)
	draw_line(Vector2(w - i, i), Vector2(w - i, i + s), c, t)
	# bottom-left
	draw_line(Vector2(i, h - i), Vector2(i + s, h - i), c, t)
	draw_line(Vector2(i, h - i), Vector2(i, h - i - s), c, t)
	# bottom-right
	draw_line(Vector2(w - i, h - i), Vector2(w - i - s, h - i), c, t)
	draw_line(Vector2(w - i, h - i), Vector2(w - i, h - i - s), c, t)
