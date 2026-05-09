class_name RadialBlurOverlay
extends ColorRect

# 径向运动模糊覆盖层：post-process shader 实现"加速冲刺"视觉
# 替代 SpeedLinesOverlay（线条方案视觉不够"动感"）
# 外部每帧 set_target(0~1)，内部 lerp 平滑过渡

@export var lerp_rate: float = 8.0

var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _shader_mat: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ColorRect 的 color 不重要——shader 输出会覆盖每个像素
	if material is ShaderMaterial:
		_shader_mat = material as ShaderMaterial
		_shader_mat.set_shader_parameter("intensity", 0.0)
	set_process(true)

func set_target(t: float) -> void:
	_target_intensity = clampf(t, 0.0, 1.0)

func _process(delta: float) -> void:
	if absf(_intensity - _target_intensity) < 0.001:
		return
	_intensity = lerpf(_intensity, _target_intensity, clampf(delta * lerp_rate, 0.0, 1.0))
	if _shader_mat:
		_shader_mat.set_shader_parameter("intensity", _intensity)
