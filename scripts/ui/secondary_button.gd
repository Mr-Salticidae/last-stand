@tool
class_name SecondaryButton
extends Control

# 子页面用小按钮：56px 高 / chamfer 10px / 文本 [icon] [CN label] [EN label]
# 每个子页面底部"返回主菜单 ◀ BACK"用这个。比 ChamferButton 简洁，无 code/水印/chevron。
#
# 对应 design menu-button.jsx → SecondaryButton 规格

signal pressed

@export var icon: String = "◀":
	set(value):
		icon = value
		queue_redraw()
@export var cn_label: String = "返回":
	set(value):
		cn_label = value
		queue_redraw()
@export var en_label: String = "BACK":
	set(value):
		en_label = value
		queue_redraw()
@export var danger: bool = false:
	set(value):
		danger = value
		queue_redraw()
@export var disabled: bool = false:
	set(value):
		disabled = value
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if value else Control.CURSOR_POINTING_HAND
		# 变 disabled 时清掉残留 hover/focus（防止鼠标已悬停在按钮上时切到禁用状态仍点亮）
		if value:
			_hover = false
			_focused = false
		queue_redraw()

@export_group("Fonts")
@export var font_cn: Font = preload("res://assets/fonts/font_notosc_800.tres")
@export var font_en: Font = preload("res://assets/fonts/font_oswald_500.tres")
@export var font_mono: Font = preload("res://assets/fonts/font_jbmono_500.tres")

@export_group("Layout")
@export var chamfer_size: float = 10.0
@export var pad_x: float = 22.0
@export var gap: float = 14.0

var _hover: bool = false
var _pressed: bool = false
var _focused: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 56)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	# 自动按内容 fit width（如果 .tscn 没设固定宽度）
	_recalc_min_width()

func _recalc_min_width() -> void:
	if not is_inside_tree():
		return
	var w := pad_x * 2.0 + gap * 2.0
	w += font_mono.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	w += font_cn.get_string_size(cn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	w += font_en.get_string_size(en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, w), 56)

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
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
				pressed.emit()
				accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			pressed.emit()
			accept_event()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not disabled:
				_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_pressed = false
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER:
			if not disabled:
				_focused = true
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			_focused = false
			queue_redraw()

func _accent() -> Color:
	return UiPalette.ORANGE if danger else UiPalette.RED

func _accent_dim() -> Color:
	return Color("#a83a20") if danger else UiPalette.RED_DIM

func _draw() -> void:
	var active: bool = _hover or _focused
	var draw_off := Vector2(1, 1) if _pressed else Vector2.ZERO

	# 背景
	var bg_col: Color
	if disabled:
		bg_col = Color("#0a0606")
	elif _pressed:
		bg_col = UiPalette.BG_0
	elif active:
		bg_col = UiPalette.with_alpha(_accent(), 0.10)
	else:
		bg_col = Color("#150c0a")

	var pts := ChamferPanel.build_polygon(size, chamfer_size)
	if draw_off != Vector2.ZERO:
		var shifted: PackedVector2Array = []
		shifted.resize(pts.size())
		for i in pts.size():
			shifted[i] = pts[i] + draw_off
		pts = shifted
	draw_colored_polygon(pts, bg_col)

	# 边框
	var border_col: Color
	if disabled:
		border_col = UiPalette.LINE_SOFT
	elif _focused:
		border_col = UiPalette.ORANGE
	elif _hover:
		border_col = _accent()
	else:
		border_col = _accent_dim()
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, border_col, 2.0, true)

	# 文字布局：icon | CN | EN
	var text_alpha: float = 0.45 if disabled else 1.0
	var label_col: Color = UiPalette.CREAM if active else UiPalette.CREAM_DIM
	var accent_col: Color = _accent()
	var muted_col: Color = UiPalette.CREAM_MUTE
	var icon_col: Color = accent_col if active else muted_col
	var en_col: Color = accent_col if active else muted_col
	if disabled:
		label_col = UiPalette.CREAM_MUTE
		icon_col = UiPalette.CREAM_MUTE
		en_col = UiPalette.CREAM_MUTE
	label_col.a *= text_alpha
	icon_col.a *= text_alpha
	en_col.a *= text_alpha
	var center_y := size.y * 0.5 + draw_off.y

	var x: float = pad_x + draw_off.x
	var icon_size: int = 18
	var icon_str := font_mono.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size)
	draw_string(font_mono, Vector2(x, center_y + icon_str.y * 0.3),
		icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size, icon_col)
	x += icon_str.x + gap

	var cn_size: int = 20
	draw_string(font_cn, Vector2(x, center_y + 7),
		cn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cn_size, label_col)
	x += font_cn.get_string_size(cn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cn_size).x + gap

	var en_size: int = 13
	draw_string(font_en, Vector2(x, center_y + 5),
		en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size, en_col)
