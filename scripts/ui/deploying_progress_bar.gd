@tool
class_name DeployingProgressBar
extends Control

# DeployingOverlay 用细长 progress 条：1px 红边 + 黑底 + 红色 fill
# 12 px 高，宽度由父布局给

@export var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

# fill 颜色可覆盖：HUD 的波内倒计时条要用危险黄，避免和血条的红被玩家误读成血量。
# 默认值就是原来写死的 UiPalette.RED，DeployingOverlay 的观感一字不变。
# （用 modulate 换色行不通——它是乘法，红 × 黄只会得到暗棕。）
@export var fill_color: Color = UiPalette.RED:
	set(value):
		fill_color = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)
	if custom_minimum_size.y == 0:
		custom_minimum_size = Vector2(0, 12)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiPalette.BG_0, true)
	var fill_w: float = (size.x - 2.0) * progress
	if fill_w > 0.0:
		draw_rect(Rect2(Vector2(1, 1), Vector2(fill_w, size.y - 2.0)), fill_color, true)
	draw_rect(Rect2(Vector2.ZERO, size), UiPalette.RED_DIM, false, 1.0)
