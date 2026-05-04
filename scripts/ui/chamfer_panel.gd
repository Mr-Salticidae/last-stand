@tool
class_name ChamferPanel
extends Control

# 切角面板：top-right 和 bottom-left 各切一个 N 像素直角
# 对应 design 的 clip-path: polygon(0 0, calc(100% - N) 0, 100% N, 100% 100%, N 100%, 0 calc(100% - N))
# 给 button / card / panel / modal 共用，外观统一军用 stencil 风
#
# 用 _draw 自绘多边形 + polyline 边框；不依赖 StyleBox（StyleBoxFlat 不支持 chamfer）

@export var bg_color: Color = UiPalette.BG_2:
	set(value):
		bg_color = value
		queue_redraw()

@export var border_color: Color = UiPalette.LINE:
	set(value):
		border_color = value
		queue_redraw()

@export var border_width: float = 2.0:
	set(value):
		border_width = value
		queue_redraw()

@export var chamfer_size: float = 16.0:
	set(value):
		chamfer_size = value
		queue_redraw()

@export var fill: bool = true:
	set(value):
		fill = value
		queue_redraw()

# 可选：第二层 inner glow / shadow（hover 状态用），由 ChamferButton 复用
@export var glow_color: Color = Color(0, 0, 0, 0):
	set(value):
		glow_color = value
		queue_redraw()

@export var glow_width: float = 0.0:
	set(value):
		glow_width = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var pts := build_polygon(size, chamfer_size)
	if fill:
		draw_colored_polygon(pts, bg_color)
	if border_width > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, border_color, border_width, true)
	if glow_width > 0.0 and glow_color.a > 0.0:
		# 外发光：在边框外侧再画一圈半透明粗线模拟 box-shadow 0 0 Npx 效果
		# 不完美但廉价，性能远好于实时 shader blur
		var loop2 := pts.duplicate()
		loop2.append(pts[0])
		draw_polyline(loop2, glow_color, border_width + glow_width, true)

# 静态方法供其他控件复用切角多边形（如 ChamferButton 自己也要用）
static func build_polygon(s: Vector2, c: float) -> PackedVector2Array:
	c = clampf(c, 0.0, minf(s.x, s.y) * 0.5)
	return PackedVector2Array([
		Vector2(0, 0),
		Vector2(s.x - c, 0),
		Vector2(s.x, c),
		Vector2(s.x, s.y),
		Vector2(c, s.y),
		Vector2(0, s.y - c),
	])
