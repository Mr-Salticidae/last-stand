class_name ReloadIndicator extends Control

# 换弹圆环进度条：黑底全圆 + 红色前景按 progress 顺时针填充
# HUD 在 _on_reload_started 时设 progress=0 + alpha=1，_process 每帧更新 progress
# 换弹完成短暂保留 progress=1（"已装填"反馈）+ 淡出

@export var radius: float = 30.0
@export var thickness: float = 5.0
@export var bg_color: Color = Color(0, 0, 0, 0.55)            # 半透明黑底环
@export var fg_color: Color = Color(0.855, 0.18, 0.2, 1.0)    # 游戏标志红

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = size / 2.0
	# 全圆背景
	draw_arc(center, radius, 0, TAU, 64, bg_color, thickness, true)
	# 进度前景（从 12 点开始顺时针）
	if progress > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, fg_color, thickness, true)
