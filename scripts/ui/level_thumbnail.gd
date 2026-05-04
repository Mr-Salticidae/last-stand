@tool
class_name LevelThumbnail
extends Control

# 关卡缩略图：复刻 design pages.jsx LevelThumbnail SVG 的 chunky low-poly silhouettes 风格
# kind 决定画 training (射靶+网格) / warehouse (货架+警示灯) / outpost (沙丘+瞭望塔)
# design viewBox 600×330，自绘按 size 等比映射。

@export_enum("training", "warehouse", "outpost") var kind: String = "training":
	set(v):
		kind = v
		queue_redraw()
# active = LevelCard hover/focus 状态；由 LevelCard 设置，控制 thumb 边框颜色
@export var active: bool = false:
	set(v):
		active = v
		queue_redraw()

# 注：design 是 top-right chamfer 切角，但 _draw 自绘 Control 无法可靠 clip 到任意 polygon
# （shader UV 不准、mask 颜色跟动态 atmosphere fx 总有差异），demo 阶段简化成矩形 border。
# 失去 design chamfer 美感，换 robust 视觉一致性。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 矩形 clip：防御 _draw 任何 sub-pixel 溢出（hazard tape 末端 float 累加误差曾溢出右边）
	clip_contents = true
	resized.connect(queue_redraw)

# design 坐标系映射：原 SVG 600×330 → 当前 size
func _x(v: float) -> float: return v / 600.0 * size.x
func _y(v: float) -> float: return v / 330.0 * size.y
func _v(x: float, y: float) -> Vector2: return Vector2(_x(x), _y(y))

func _draw() -> void:
	match kind:
		"training":
			_draw_training()
		"warehouse":
			_draw_warehouse()
		"outpost":
			_draw_outpost()
	# active (hover) 时下半部加红色 overlay（design "scan-sweep + 50% red overlay" 的简化版）
	if active:
		draw_rect(Rect2(0, size.y * 0.5, size.x, size.y * 0.5),
			Color(0.855, 0.18, 0.2, 0.18))
	# 矩形 border（state-aware: hover red / 默认 line gray）— fallback to 方正矩形避免 chamfer 溢出问题
	var col: Color = UiPalette.RED if active else UiPalette.LINE
	draw_rect(Rect2(Vector2.ZERO, size), col, false, 2.0)

# ---------- TRAINING ----------
func _draw_training() -> void:
	# 背景：上深下浅渐变近似（用两层 rect）
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, _y(165))), Color(0.10, 0.08, 0.06, 1.0))
	draw_rect(Rect2(Vector2(0, _y(165)), Vector2(size.x, _y(165))), Color(0.055, 0.030, 0.020, 1.0))

	# 顶部 hazard 黄黑斜纹条（design id="hz-tr"）
	var tape_y: float = _y(60)
	var tape_h: float = _y(14)
	draw_rect(Rect2(0, tape_y, size.x, tape_h), Color(0.055, 0.030, 0.020, 1.0))
	# 整数计数避免 float 累加误差（while x += tile_w 经 25 次累加精度漂移会多画 1 个 tile 溢出右边）
	var tile_w: float = _x(24)
	var n_tiles: int = int(round(size.x / tile_w))
	for i in n_tiles:
		var x: float = i * tile_w
		var p: PackedVector2Array = [
			Vector2(x, tape_y), Vector2(x + tile_w * 0.5, tape_y),
			Vector2(x, tape_y + tape_h),
		]
		draw_colored_polygon(p, Color(0.78, 0.64, 0.23, 1.0))
		var p2: PackedVector2Array = [
			Vector2(x + tile_w * 0.5, tape_y), Vector2(x + tile_w, tape_y),
			Vector2(x + tile_w, tape_y + tape_h),
		]
		draw_colored_polygon(p2, Color(0.78, 0.64, 0.23, 1.0))

	# 地面网格（vertical + horizontal lines, alpha 0.6）
	var grid_col := Color(0.227, 0.125, 0.102, 0.6)
	for i in 16:
		var gx: float = _x(i * 40)
		draw_line(Vector2(gx, _y(200)), Vector2(gx, _y(330)), grid_col, 1.0)
	for i in 8:
		var gy: float = _y(200 + i * 18)
		draw_line(Vector2(0, gy), Vector2(size.x, gy), grid_col, 1.0)

	# 3 个射靶（杆 + 同心圆）
	var targets: Array = [
		[83, 160, 80, 22],   # x_center, y_center, pole_h, ring_r
		[283, 150, 90, 22],
		[483, 170, 70, 22],
	]
	for t in targets:
		var cx: float = t[0]
		var cy: float = t[1]
		var pole_h: float = t[2]
		var ring_r: float = t[3]
		# 杆
		draw_rect(Rect2(_v(cx - 3, cy), Vector2(_x(6), _y(pole_h))), Color(0.055, 0.030, 0.020, 1.0))
		# 外环（cream）
		draw_arc(_v(cx, cy), _x(ring_r), 0, TAU, 32, Color(1, 0.918, 0.851, 1.0), 3.0, true)
		# 中环（red）
		draw_arc(_v(cx, cy), _x(14), 0, TAU, 24, Color(0.855, 0.18, 0.2, 1.0), 3.0, true)
		# 心点
		draw_circle(_v(cx, cy), _x(6), Color(0.855, 0.18, 0.2, 1.0))

# ---------- WAREHOUSE ----------
func _draw_warehouse() -> void:
	# 暗背景渐变
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, _y(165))), Color(0.122, 0.078, 0.063, 1.0))
	draw_rect(Rect2(Vector2(0, _y(165)), Vector2(size.x, _y(165))), Color(0.040, 0.024, 0.024, 1.0))

	# 顶部 warning light（halo + 实心红圆）
	var wc := _v(300, 60)
	draw_circle(wc, _x(40), Color(0.855, 0.18, 0.2, 0.18))
	draw_circle(wc, _x(14), Color(0.855, 0.18, 0.2, 0.6))

	# 3 个货架（黑实色 + 红描边 + 多层水平条）
	var shelves: Array = [
		[40, 120, 160, 180, [140, 180, 220, 260]],
		[220, 100, 160, 200, [120, 160, 200, 240, 280]],
		[400, 130, 160, 170, [150, 190, 230, 270]],
	]
	for s in shelves:
		var sx: float = s[0]
		var sy: float = s[1]
		var sw: float = s[2]
		var sh: float = s[3]
		var levels: Array = s[4]
		# 货架 frame
		draw_rect(Rect2(_v(sx, sy), Vector2(_x(sw), _y(sh))), Color(0.055, 0.030, 0.020, 1.0))
		draw_rect(Rect2(_v(sx, sy), Vector2(_x(sw), _y(sh))), Color(0.227, 0.125, 0.102, 1.0), false, 1.5)
		# 层板
		for ly in levels:
			draw_rect(Rect2(_v(sx + 20, ly), Vector2(_x(sw - 40), _y(20))), Color(0.055, 0.030, 0.020, 1.0))
			draw_rect(Rect2(_v(sx + 20, ly), Vector2(_x(sw - 40), _y(20))), Color(0.227, 0.125, 0.102, 1.0), false, 1.0)

	# 前景箱子
	var crates: Array = [
		[80, 270, 50, 40],
		[140, 280, 40, 30],
		[450, 275, 50, 35],
	]
	for c in crates:
		draw_rect(Rect2(_v(c[0], c[1]), Vector2(_x(c[2]), _y(c[3]))), Color(0.227, 0.141, 0.094, 1.0))
		draw_rect(Rect2(_v(c[0], c[1]), Vector2(_x(c[2]), _y(c[3]))), Color(0.040, 0.020, 0.016, 1.0), false, 1.5)

	# 聚光灯三角（cream 5% alpha）
	var spot: PackedVector2Array = [_v(300, 80), _v(230, 330), _v(370, 330)]
	draw_colored_polygon(spot, Color(1, 0.918, 0.851, 0.05))

# ---------- OUTPOST ----------
func _draw_outpost() -> void:
	# 暖棕沙漠渐变 (3 段)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, _y(110))), Color(0.227, 0.122, 0.082, 1.0))
	draw_rect(Rect2(Vector2(0, _y(110)), Vector2(size.x, _y(110))), Color(0.353, 0.227, 0.133, 1.0))
	draw_rect(Rect2(Vector2(0, _y(220)), Vector2(size.x, _y(110))), Color(0.165, 0.086, 0.063, 1.0))

	# 太阳 halo
	draw_circle(_v(430, 120), _x(60), Color(1.0, 0.451, 0.314, 0.25))
	draw_circle(_v(430, 120), _x(28), Color(1.0, 0.451, 0.314, 0.45))

	# 沙丘 (用 polygon 模拟 Q-curve)
	var dune1: PackedVector2Array = [
		_v(0, 260), _v(150, 220), _v(300, 240), _v(450, 230), _v(600, 230),
		_v(600, 330), _v(0, 330)
	]
	draw_colored_polygon(dune1, Color(0.227, 0.141, 0.094, 1.0))
	var dune2: PackedVector2Array = [
		_v(0, 290), _v(200, 260), _v(400, 280), _v(600, 270),
		_v(600, 330), _v(0, 330)
	]
	draw_colored_polygon(dune2, Color(0.141, 0.078, 0.063, 1.0))

	# outpost 建筑（剪影黑）
	var c := Color(0.055, 0.030, 0.020, 1.0)
	# 左塔（带尖顶）
	draw_rect(Rect2(_v(80, 200), Vector2(_x(60), _y(80))), c)
	var roof: PackedVector2Array = [_v(80, 200), _v(110, 170), _v(140, 200)]
	draw_colored_polygon(roof, c)
	# 中央建筑
	draw_rect(Rect2(_v(200, 180), Vector2(_x(120), _y(100))), c)
	draw_rect(Rect2(_v(220, 160), Vector2(_x(20), _y(20))), c)
	draw_rect(Rect2(_v(280, 160), Vector2(_x(20), _y(20))), c)
	# 右瞭望塔
	draw_rect(Rect2(_v(380, 190), Vector2(_x(40), _y(90))), c)
	draw_rect(Rect2(_v(370, 170), Vector2(_x(60), _y(20))), c)
	# 远右建筑
	draw_rect(Rect2(_v(460, 210), Vector2(_x(80), _y(70))), c)

	# 前景 sandbags（fill ellipse — draw_arc 是描边，用 polygon 采样模拟实心椭圆）
	var sb := Color(0.040, 0.020, 0.016, 1.0)
	_draw_ellipse(_v(100, 310), _x(40), _y(10), sb)
	_draw_ellipse(_v(180, 320), _x(50), _y(11), sb)
	_draw_ellipse(_v(500, 315), _x(50), _y(11), sb)

func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts: PackedVector2Array = []
	pts.resize(32)
	for i in 32:
		var a: float = float(i) / 32.0 * TAU
		pts[i] = center + Vector2(cos(a) * rx, sin(a) * ry)
	draw_colored_polygon(pts, col)
