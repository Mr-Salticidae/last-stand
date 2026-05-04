@tool
class_name CustomSlider
extends Control

# 自绘 slider：2px 灰轨 + 6px 红色 fill + 11 tick + 16×16 cream knob
# 接近 design HTML slider 视觉。无 letter-spacing 等需特殊字体支持的细节。
# 通过 value_changed 信号外发，settings_menu 接信号 set Settings.xxx

signal value_changed(value: float)

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		queue_redraw()
@export var max_value: float = 1.0:
	set(v):
		max_value = v
		queue_redraw()
@export var value: float = 0.5:
	set(v):
		value = clampf(v, min_value, max_value)
		queue_redraw()
@export var step: float = 0.01
@export var ticks_count: int = 11

var _dragging: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 36)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			grab_focus()
			_set_value_from_x(event.position.x)
			accept_event()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_set_value_from_x(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var d: float = 0.0
		if event.keycode == KEY_LEFT:
			d = -step if step > 0 else -0.01
		elif event.keycode == KEY_RIGHT:
			d = step if step > 0 else 0.01
		if d != 0.0:
			value = clampf(value + d, min_value, max_value)
			value_changed.emit(value)
			accept_event()

func _set_value_from_x(x: float) -> void:
	if size.x <= 0:
		return
	var t: float = clampf(x / size.x, 0.0, 1.0)
	var raw: float = lerpf(min_value, max_value, t)
	if step > 0.0:
		raw = roundf(raw / step) * step
	value = clampf(raw, min_value, max_value)
	value_changed.emit(value)

func _draw() -> void:
	var track_y: float = size.y * 0.5

	# 1. 2px 灰色轨道（贯穿全宽）
	draw_line(Vector2(0, track_y), Vector2(size.x, track_y), UiPalette.LINE, 2.0)

	# 2. 11 tick marks
	for i in ticks_count:
		var tx: float = size.x * float(i) / float(ticks_count - 1)
		var is_major: bool = (i == 0 or i == (ticks_count - 1) / 2 or i == ticks_count - 1)
		var tick_h: float = 8.0 if is_major else 4.0
		var tcol: Color = UiPalette.CREAM_MUTE if is_major else UiPalette.LINE
		draw_line(Vector2(tx, track_y - tick_h), Vector2(tx, track_y + tick_h), tcol, 1.0)

	# 3. 6px fill bar (左到 value 处) — design 红色渐变，简化用 RED_DIM 实色
	var t: float = (value - min_value) / max(0.0001, max_value - min_value)
	var fill_x: float = size.x * t
	if fill_x > 0.0:
		draw_rect(Rect2(0, track_y - 3, fill_x, 6), UiPalette.RED, true)

	# 4. 16×16 cream square knob with 2px red border
	var knob_size: float = 16.0
	var knob_rect := Rect2(fill_x - knob_size * 0.5, track_y - knob_size * 0.5, knob_size, knob_size)
	draw_rect(knob_rect, UiPalette.CREAM, true)
	draw_rect(knob_rect, UiPalette.RED, false, 2.0)
