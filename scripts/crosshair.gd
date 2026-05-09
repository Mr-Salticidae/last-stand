extends Control

# 自绘十字准星 + 命中标记闪烁反馈
# 未来做"动态扩散"（走动/开火时 gap 变大）只需改 gap 值并 queue_redraw()

@export var gap: float = 4.0
@export var length: float = 8.0
@export var thickness: float = 2.0
@export var color: Color = Color(1, 1, 1, 0.9)

# 命中反馈：打中敌人时在准星四周显示 "X" 斜线闪一下
@export var hit_marker_color: Color = Color(1, 1, 1, 1)           # 普通命中：白
@export var headshot_marker_color: Color = Color(1.0, 0.85, 0.2, 1)  # 爆头：金黄
@export var kill_marker_color: Color = Color(1.0, 0.25, 0.15, 1)    # 击杀：红
@export var hit_flash_duration: float = 0.18
@export var headshot_flash_duration: float = 0.28
@export var kill_flash_duration: float = 0.4
@export var hit_marker_length: float = 8.0
@export var hit_marker_thickness: float = 2.5

var _flash_timer: float = 0.0
var _flash_total: float = 0.0
var _flash_color: Color = Color.WHITE
var _flash_scale: float = 1.0  # 击杀反馈的放大系数

# v0.3 视觉提示：战术换弹 ready 时主十字线变红 + 4 角 corner ticks（hud 每帧驱动）
var reload_burst_ready: bool = false:
	set(v):
		if reload_burst_ready != v:
			reload_burst_ready = v
			queue_redraw()
@export var reload_burst_main_color: Color = Color(0.95, 0.45, 0.42, 0.95)  # ready 时主十字线偏红
@export var corner_tick_color: Color = Color(1, 0.918, 0.851, 0.85)  # CREAM
@export var corner_tick_offset: float = 12.0   # 离中心距离
@export var corner_tick_length: float = 6.0
@export var corner_tick_thickness: float = 2.0
# 战术换弹 / 底牌瞬时 X 形闪烁色（仿 flash_hit 但独立色，不重用 hit_marker_color）
@export var reload_burst_marker_color: Color = Color(1, 1, 1, 1)            # 白
@export var last_round_marker_color: Color = Color(1, 0.55, 0.18, 1)        # 橙

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer = max(0.0, _flash_timer - delta)
		queue_redraw()

func flash_hit() -> void:
	_flash_timer = hit_flash_duration
	_flash_total = hit_flash_duration
	_flash_color = hit_marker_color
	_flash_scale = 1.0
	queue_redraw()

func flash_headshot() -> void:
	_flash_timer = headshot_flash_duration
	_flash_total = headshot_flash_duration
	_flash_color = headshot_marker_color
	_flash_scale = 1.3
	queue_redraw()

func flash_kill() -> void:
	_flash_timer = kill_flash_duration
	_flash_total = kill_flash_duration
	_flash_color = kill_marker_color
	_flash_scale = 1.6
	queue_redraw()

# v0.3 暴伤反馈：复用 X 形 marker 通道（同时触发会被后调用的覆盖，可接受）
func flash_reload_burst() -> void:
	_flash_timer = hit_flash_duration
	_flash_total = hit_flash_duration
	_flash_color = reload_burst_marker_color
	_flash_scale = 1.1
	queue_redraw()

func flash_last_round() -> void:
	_flash_timer = hit_flash_duration
	_flash_total = hit_flash_duration
	_flash_color = last_round_marker_color
	_flash_scale = 1.1
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	# 主十字准星：ready 时偏红色（提示"下一发暴伤"）
	var main_col: Color = reload_burst_main_color if reload_burst_ready else color
	draw_line(center + Vector2(0, -gap), center + Vector2(0, -gap - length), main_col, thickness)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + length), main_col, thickness)
	draw_line(center + Vector2(-gap, 0), center + Vector2(-gap - length, 0), main_col, thickness)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), main_col, thickness)
	# 战术换弹 ready：4 角 corner ticks（项目设计语言一致，复用 ChamferButton 的视觉词汇）
	if reload_burst_ready:
		_draw_corner_ticks(center)

	# 命中标记：4 条 45° 斜线（X 形），淡出
	if _flash_timer > 0.0 and _flash_total > 0.0:
		var progress: float = _flash_timer / _flash_total  # 1.0 → 0.0
		var alpha: float = progress
		var marker_col: Color = _flash_color
		marker_col.a *= alpha
		var scale_factor: float = _flash_scale * (1.0 + (1.0 - progress) * 0.3)   # 随 fade 略放大
		var off: float = (gap + 2.0) * scale_factor
		var len_scaled: float = hit_marker_length * scale_factor
		# 四个斜角方向：↗ ↘ ↙ ↖
		var diag: Vector2 = Vector2(1, 1).normalized()
		var anti: Vector2 = Vector2(1, -1).normalized()
		draw_line(center + diag * off, center + diag * (off + len_scaled), marker_col, hit_marker_thickness)
		draw_line(center - diag * off, center - diag * (off + len_scaled), marker_col, hit_marker_thickness)
		draw_line(center + anti * off, center + anti * (off + len_scaled), marker_col, hit_marker_thickness)
		draw_line(center - anti * off, center - anti * (off + len_scaled), marker_col, hit_marker_thickness)

# 战术换弹 ready 时画 4 角小 L 形（左上 / 右上 / 左下 / 右下）
# 跟 ChamferButton hover/focus 的 corner ticks 同视觉语言
func _draw_corner_ticks(center: Vector2) -> void:
	var o: float = corner_tick_offset
	var l: float = corner_tick_length
	var c: Color = corner_tick_color
	var t: float = corner_tick_thickness
	# 左上 L
	draw_line(Vector2(center.x - o, center.y - o), Vector2(center.x - o + l, center.y - o), c, t)
	draw_line(Vector2(center.x - o, center.y - o), Vector2(center.x - o, center.y - o + l), c, t)
	# 右上 L
	draw_line(Vector2(center.x + o, center.y - o), Vector2(center.x + o - l, center.y - o), c, t)
	draw_line(Vector2(center.x + o, center.y - o), Vector2(center.x + o, center.y - o + l), c, t)
	# 左下 L
	draw_line(Vector2(center.x - o, center.y + o), Vector2(center.x - o + l, center.y + o), c, t)
	draw_line(Vector2(center.x - o, center.y + o), Vector2(center.x - o, center.y + o - l), c, t)
	# 右下 L
	draw_line(Vector2(center.x + o, center.y + o), Vector2(center.x + o - l, center.y + o), c, t)
	draw_line(Vector2(center.x + o, center.y + o), Vector2(center.x + o, center.y + o - l), c, t)
