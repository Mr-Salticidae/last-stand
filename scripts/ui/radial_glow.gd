@tool
class_name RadialGlow
extends Control

# 圆形 radial gradient 发光，用于 title 红色 bullet impact 等装饰背景。
# design: radial-gradient(circle, rgba(218,46,51,0.5) 0%, rgba(218,46,51,0.15) 35%, transparent 65%)
#
# 用 layered draw_circle alpha 累加近似 gradient，避免 shader/texture 开销。

@export var glow_color: Color = Color(0.855, 0.18, 0.2, 1.0):
	set(value):
		glow_color = value
		queue_redraw()
@export var diameter: float = 260.0:
	set(value):
		diameter = value
		custom_minimum_size = Vector2(diameter, diameter)
		queue_redraw()
@export_range(0.0, 1.0) var inner_alpha: float = 0.5:
	set(value):
		inner_alpha = value
		queue_redraw()
@export_range(0.0, 1.0) var mid_alpha: float = 0.15:
	set(value):
		mid_alpha = value
		queue_redraw()
@export var layers: int = 18  # 越多越平滑

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(diameter, diameter)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r: float = diameter * 0.5
	var center := Vector2(r, r)
	# 由外向内画，越内越亮。0.65 处 alpha=0，0.35 处 alpha=mid，0% 处 alpha=inner
	for i in range(layers, 0, -1):
		var t: float = float(i) / float(layers)  # 1.0 = outer, 0.0 = inner
		# t=0.65 → alpha=0;  t=0.35 → alpha=mid;  t=0 → alpha=inner
		var a: float
		if t >= 0.65:
			a = 0.0
		elif t >= 0.35:
			# linear from 0 (at 0.65) to mid (at 0.35)
			a = mid_alpha * (1.0 - (t - 0.35) / 0.30)
		else:
			# linear from mid (at 0.35) to inner (at 0)
			a = mid_alpha + (inner_alpha - mid_alpha) * (1.0 - t / 0.35)
		if a <= 0.001:
			continue
		var radius := r * t
		var col := glow_color
		col.a = a / float(layers) * 4.0  # 累加 alpha 近似
		draw_circle(center, radius, col)
