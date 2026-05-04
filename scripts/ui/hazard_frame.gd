@tool
class_name HazardFrame
extends Control

# 4 边黄黑斜条带（hazard chevron tape），对应 design persistent chrome #10
# 简化版：黄色带状描边（不画斜条交替黑色），视觉上接近"警戒带"风格
# 完整版（带 45° 斜条交替黑色）放 Phase 5 做

@export var thickness: float = 6.0:
	set(value):
		thickness = value
		queue_redraw()
@export var inset: float = 24.0:
	set(value):
		inset = value
		queue_redraw()
@export var opacity: float = 0.35:
	set(value):
		opacity = value
		queue_redraw()
@export var tint: Color = UiPalette.HAZARD_Y:
	set(value):
		tint = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var col := UiPalette.with_alpha(tint, opacity)
	var w := size.x
	var h := size.y
	# top
	draw_rect(Rect2(inset, inset, w - inset * 2.0, thickness), col, true)
	# bottom
	draw_rect(Rect2(inset, h - inset - thickness, w - inset * 2.0, thickness), col, true)
	# left
	draw_rect(Rect2(inset, inset, thickness, h - inset * 2.0), col, true)
	# right
	draw_rect(Rect2(w - inset - thickness, inset, thickness, h - inset * 2.0), col, true)
