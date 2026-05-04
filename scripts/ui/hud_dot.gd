@tool
class_name HudDot
extends Control

# HUD 圆点：8px 红圆 + 外圈 glow halo，design hud-pill 里的 .hud-dot
# 闪烁动画：opacity 1 ↔ 0.35，1.4s ease-in-out，infinite
#
# CSS keyframes:
#   0%, 100% { opacity: 1; }
#   50%      { opacity: 0.35; }

@export var dot_color: Color = Color(0.855, 0.18, 0.2, 1.0):
	set(value):
		dot_color = value
		queue_redraw()
@export var dot_size: float = 8.0:
	set(value):
		dot_size = value
		queue_redraw()
@export var glow_radius: float = 8.0:  # design box-shadow 0 0 8px
	set(value):
		glow_radius = value
		queue_redraw()
@export var blink_period: float = 1.4
@export var blink_min_alpha: float = 0.35
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			modulate.a = 1.0

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 留出 glow 空间 — control size = dot + glow padding 两侧
	var s := dot_size + glow_radius * 2.0
	custom_minimum_size = Vector2(s, s)
	if not Engine.is_editor_hint():
		set_process(true)

func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	# ease-in-out: smoothstep over half period, mirror
	var phase: float = fmod(_t, blink_period) / blink_period  # 0..1
	# 0 → 0.5 → 1 对应 1.0 → 0.35 → 1.0
	var k: float = abs(phase - 0.5) * 2.0  # 0..1..0
	# ease-in-out smoothing
	var eased: float = k * k * (3.0 - 2.0 * k)  # smoothstep
	modulate.a = blink_min_alpha + (1.0 - blink_min_alpha) * eased
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var r := dot_size * 0.5
	# 外圈 glow halo：5 层 alpha 递减大圆模拟 box-shadow blur
	var halo_layers: int = 6
	for i in range(halo_layers, 0, -1):
		var t: float = float(i) / float(halo_layers)  # 1..0
		var radius: float = r + glow_radius * t
		var col := dot_color
		col.a = 0.55 * (1.0 - t) * (1.0 - t)
		if col.a < 0.01:
			continue
		draw_circle(center, radius, col)
	# 主圆点
	draw_circle(center, r, dot_color)
