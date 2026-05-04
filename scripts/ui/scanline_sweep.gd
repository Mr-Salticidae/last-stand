class_name ScanlineSweep
extends ColorRect

# 220px 高红 band，9s linear infinite 从屏顶下移到屏底
# 不要 @tool — 编辑器里不需要持续动

@export var period_seconds: float = 9.0
@export var band_height: float = 220.0
@export var screen_height: float = 1080.0

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, band_height)
	size = Vector2(get_viewport_rect().size.x, band_height)
	position.y = -band_height
	set_process(true)

func _process(delta: float) -> void:
	_t = fmod(_t + delta, period_seconds)
	var phase: float = _t / period_seconds  # 0..1
	position.y = -band_height + phase * (screen_height + band_height)
