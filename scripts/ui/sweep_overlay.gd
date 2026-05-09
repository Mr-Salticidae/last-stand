class_name SweepOverlay
extends Control

# 红色横向扫光蒙版：play() 触发一次从左到右的 sweep，结束后自动停绘
# 视觉语言对齐 ChamferButton hover 的 _draw_scan_sweep（同一种 stripe 算法）
# 用途：商店刷新时给被换内容的卡片来一次"刷过"特效

@export var sweep_color: Color = Color(0.855, 0.18, 0.2, 1)  # UiPalette.RED
@export var peak_alpha: float = 0.35
@export var duration: float = 0.4

var _t: float = 1.0  # 1.0 = 已播放完成，不绘制

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 10  # 盖在父控件内容之上
	set_process(false)

func play() -> void:
	_t = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_t = minf(_t + delta / duration, 1.0)
	queue_redraw()
	if _t >= 1.0:
		set_process(false)

func _draw() -> void:
	if _t >= 1.0:
		return
	# 横向 sweep band 从左扫到右，stripe alpha 中心高边缘 0
	var sweep_w: float = size.x * 0.55
	var half: float = sweep_w * 0.5
	var travel: float = size.x + sweep_w
	var x_center: float = -half + _t * travel
	# 全程 alpha 衰减（结束时整体淡出，避免突然消失）
	var lifetime_fade: float = 1.0 - smoothstep(0.7, 1.0, _t)
	var stripes: int = 36
	var stripe_w: float = size.x / float(stripes)
	for i in stripes:
		var sx: float = (float(i) + 0.5) * stripe_w
		var dx: float = absf(sx - x_center)
		if dx >= half:
			continue
		var t_norm: float = dx / half
		var a: float = (1.0 - t_norm * t_norm) * peak_alpha * lifetime_fade
		if a < 0.003:
			continue
		var col := sweep_color
		col.a = a
		draw_rect(Rect2(sx - stripe_w * 0.5, 0.0, stripe_w + 0.5, size.y), col)
