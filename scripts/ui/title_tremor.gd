class_name TitleTremor
extends Control

# 不加 @tool：编辑器里持续抖会干扰对齐子节点 position。

# 让子节点整体按 design tremor 关键帧抖动（0.18s steps(2) infinite, ±1-1.4px）。
# 自身 position 不改变 — 给所有非 ignore 子节点设 offset 抖动，避免 anchor 失效。
#
# CSS keyframe 是 steps(2) 的离散切换，所以这里也用步进而不是平滑插值。

@export var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			_apply_offset(Vector2.ZERO)
@export var step_interval: float = 0.09  # design 0.18s/steps(2) ≈ 每 0.09s 换一格
@export var amplitude: float = 1.0       # ±amplitude px (用 1.0 = "tremor"，用 1.4 = "tremor-strong")

const _OFFSETS: Array[Vector2] = [
	Vector2(0.6, -0.4),
	Vector2(-0.5, 0.3),
	Vector2(0.3, 0.5),
	Vector2(-0.4, -0.3),
]

var _accum: float = 0.0
var _index: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 记录每个子节点 design-time 的 position 作为 base，后续抖动都基于此 offset
	for child in get_children():
		var ctrl := child as Control
		if ctrl != null:
			ctrl.set_meta(&"_tremor_base", ctrl.position)
	set_process(true)

func _process(delta: float) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum < step_interval:
		return
	_accum = 0.0
	_index = (_index + 1) % _OFFSETS.size()
	_apply_offset(_OFFSETS[_index] * amplitude)

func _apply_offset(off: Vector2) -> void:
	for child in get_children():
		var ctrl := child as Control
		if ctrl == null:
			continue
		var base: Vector2 = ctrl.get_meta(&"_tremor_base", ctrl.position)
		ctrl.position = base + off
