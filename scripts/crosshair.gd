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

func _draw() -> void:
	var center: Vector2 = size * 0.5
	# 主十字准星
	draw_line(center + Vector2(0, -gap), center + Vector2(0, -gap - length), color, thickness)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + length), color, thickness)
	draw_line(center + Vector2(-gap, 0), center + Vector2(-gap - length, 0), color, thickness)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), color, thickness)

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
