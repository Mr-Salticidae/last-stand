@tool
class_name BulletHole
extends Control

# 弹孔：基于 design title.jsx BulletHole，但适配 LastStand atmospheric 风格调整：
# 加了 atmospheric fx 后整体画面是半透明 / 动态调子，design 原版的纯黑实体核会变成
# "挖洞遮挡感"，跟氛围层不协调。所以：
#   1) 中心 alpha 整体降到 0.72（让下面字色透出 ~28%）
#   2) 纯实体核范围从 0..35% 缩到 0..25%（外圈 fade 范围放大）
# 保持 design 的暗棕红色调和 cracks 形状不变。
#
# 0%   #000        alpha 0.72
# 25%  #000        alpha 0.68
# 55%  #1a0a08     alpha 0.50
# 80%  #501e14     alpha 0.28
# 100% transparent alpha 0.0
#
# 加 4 条短裂纹（暗棕红，alpha 0.6 → 现在比中心还显眼一档，强化"裂痕"感而非"洞"）。

@export var hole_size: float = 28.0:
	set(value):
		hole_size = value
		custom_minimum_size = Vector2(hole_size, hole_size)
		queue_redraw()
@export var crack_seed: int = 0:
	set(value):
		crack_seed = value
		queue_redraw()
@export var ring_count: int = 28  # 越多越平滑，对 5 个弹孔无所谓 perf

const _STOPS: Array = [
	[0.00, Color(0, 0, 0, 0.72)],
	[0.25, Color(0, 0, 0, 0.68)],
	[0.55, Color(0.10, 0.04, 0.03, 0.50)],
	[0.80, Color(0.31, 0.12, 0.08, 0.28)],
	[1.00, Color(0, 0, 0, 0.0)],
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(hole_size, hole_size)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r: float = hole_size * 0.5
	var center := Vector2(r, r)

	# 从外向内画 N 层 thin ring，每层颜色采样自 gradient stops
	# draw_arc 描边宽度等于 ring 间距 → 相邻 ring 无 gap、轻微重叠
	var ring_w: float = (r / float(ring_count)) + 1.0
	for i in range(ring_count, 0, -1):
		var t: float = float(i) / float(ring_count)  # 1.0 → 1/N
		var col: Color = _sample(t)
		if col.a < 0.003:
			continue
		var radius: float = r * t
		# 离散 segments 数随半径变小，避免小弹孔过度圆滑浪费
		var segs: int = clamp(int(radius * 1.2), 12, 40)
		draw_arc(center, radius, 0.0, TAU, segs, col, ring_w, true)

	# 4 条短裂纹
	var rng := RandomNumberGenerator.new()
	rng.seed = int(crack_seed) if crack_seed != 0 else int(position.x * 7 + position.y * 13)
	var crack_col := Color(0.16, 0.08, 0.06, 0.6)
	for i in 4:
		var angle: float = rng.randf_range(0, TAU)
		var len_frac: float = rng.randf_range(0.55, 0.95)
		var tail := center + Vector2.RIGHT.rotated(angle) * (r * len_frac)
		draw_line(center, tail, crack_col, maxf(r * 0.04, 0.6), true)

# 在 [0..1] 上插值 _STOPS 取颜色
func _sample(t: float) -> Color:
	if t <= _STOPS[0][0]:
		return _STOPS[0][1]
	if t >= _STOPS[_STOPS.size() - 1][0]:
		return _STOPS[_STOPS.size() - 1][1]
	for i in range(_STOPS.size() - 1):
		var t0: float = _STOPS[i][0]
		var t1: float = _STOPS[i + 1][0]
		if t >= t0 and t <= t1:
			var local: float = (t - t0) / (t1 - t0)
			var c0: Color = _STOPS[i][1]
			var c1: Color = _STOPS[i + 1][1]
			return c0.lerp(c1, local)
	return _STOPS[_STOPS.size() - 1][1]
