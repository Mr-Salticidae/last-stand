@tool
class_name CustomCycleButton
extends Control

# 多状态循环按钮：点击切换到下一个 option，左右键也支持
# 跟 toggle 视觉一致（120×32 矩形 + 边框），适合 FPS 限制等多档位选择
# 文本居中显示当前 option，hover/focus 时显示左右指示箭头

signal value_changed(index: int, option: String)

@export var options: PackedStringArray = PackedStringArray(["OPTION"]):
	set(v):
		options = v
		_clamp_index()
		queue_redraw()

@export var current_index: int = 0:
	set(v):
		current_index = clampi(v, 0, max(0, options.size() - 1))
		queue_redraw()

@export_group("Fonts")
@export var font: Font = preload("res://assets/fonts/font_jbmono_500.tres")

var _hover: bool = false
var _focused: bool = false
var _pressed: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(140, 32)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			grab_focus()
			queue_redraw()
		else:
			var was_pressed: bool = _pressed
			_pressed = false
			queue_redraw()
			if was_pressed and Rect2(Vector2.ZERO, size).has_point(event.position):
				_cycle_next()
				accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_RIGHT:
			_cycle_next()
			accept_event()
		elif event.keycode == KEY_LEFT:
			_cycle_prev()
			accept_event()

func _cycle_next() -> void:
	if options.is_empty():
		return
	current_index = (current_index + 1) % options.size()
	value_changed.emit(current_index, options[current_index])

func _cycle_prev() -> void:
	if options.is_empty():
		return
	current_index = (current_index - 1 + options.size()) % options.size()
	value_changed.emit(current_index, options[current_index])

func _clamp_index() -> void:
	if options.is_empty():
		current_index = 0
	else:
		current_index = clampi(current_index, 0, options.size() - 1)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_pressed = false
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER:
			_focused = true
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			_focused = false
			queue_redraw()

func _draw() -> void:
	var active: bool = _hover or _focused
	# 1. 背景
	var bg: Color = UiPalette.with_alpha(UiPalette.RED, 0.10) if active else UiPalette.BG_0
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)

	# 2. 边框
	var border: Color
	if _focused:
		border = UiPalette.ORANGE
	elif _hover:
		border = UiPalette.RED
	else:
		border = UiPalette.LINE
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 2.0)

	# 3. 当前 option 文本居中
	var text: String = options[current_index] if not options.is_empty() else ""
	var fsize: int = 12
	var col: Color = UiPalette.CREAM if active else UiPalette.CREAM_DIM
	var txt_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, Vector2((size.x - txt_w) * 0.5, size.y * 0.5 + 4),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

	# 4. hover/focus 时左右箭头指示可循环
	if active:
		var arrow_col: Color = UiPalette.RED
		var center_y: float = size.y * 0.5
		draw_string(font, Vector2(10, center_y + 4),
			"<", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, arrow_col)
		draw_string(font, Vector2(size.x - 18, center_y + 4),
			">", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, arrow_col)
