@tool
class_name CustomToggle
extends Control

# 自绘 ON/OFF 开关：120×32 矩形，内部 thumb 滑动，120ms 平滑过渡
# 对应 design Toggle 规格

signal toggled(pressed: bool)

@export var pressed: bool = false:
	set(v):
		var changed: bool = pressed != v
		pressed = v
		_animate_thumb()
		queue_redraw()
		if changed and not Engine.is_editor_hint():
			toggled.emit(v)

@export_group("Fonts")
@export var font_mono: Font = preload("res://assets/fonts/font_jbmono_500.tres")

const THUMB_W: float = 52.0
const PAD: float = 4.0
const ANIM_TIME: float = 0.12

var _thumb_x: float = PAD
var _tween: Tween = null

func _ready() -> void:
	custom_minimum_size = Vector2(120, 32)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_recalc_thumb)
	_recalc_thumb()

func _recalc_thumb() -> void:
	_thumb_x = (size.x - PAD - THUMB_W) if pressed else PAD
	queue_redraw()

func _animate_thumb() -> void:
	if not is_inside_tree():
		_recalc_thumb()
		return
	var target_x: float = (size.x - PAD - THUMB_W) if pressed else PAD
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_thumb_x, _thumb_x, target_x, ANIM_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_thumb_x(x: float) -> void:
	_thumb_x = x
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = not pressed
		grab_focus()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			pressed = not pressed
			accept_event()

func _draw() -> void:
	# 1. 背景
	var bg: Color = UiPalette.with_alpha(UiPalette.RED, 0.15) if pressed else UiPalette.BG_0
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)

	# 2. 边框 2px
	var border: Color = UiPalette.RED if pressed else UiPalette.LINE
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0)

	# 3. Thumb 52×24 滑动
	var thumb_h: float = size.y - PAD * 2.0
	var thumb_rect := Rect2(_thumb_x, PAD, THUMB_W, thumb_h)
	var thumb_bg: Color = UiPalette.RED if pressed else UiPalette.BG_2
	draw_rect(thumb_rect, thumb_bg, true)

	# 4. ON / OFF 文本
	var label: String = "ON" if pressed else "OFF"
	var lbl_color: Color = UiPalette.CREAM if pressed else UiPalette.CREAM_MUTE
	var fsize: int = 11
	var lbl_w: float = font_mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font_mono,
		Vector2(thumb_rect.position.x + (THUMB_W - lbl_w) * 0.5,
			thumb_rect.position.y + thumb_rect.size.y * 0.5 + 4),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, lbl_color)
