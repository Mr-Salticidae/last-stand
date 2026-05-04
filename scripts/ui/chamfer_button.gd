@tool
class_name ChamferButton
extends Control

# 主菜单切角按钮：560×82 默认尺寸，4 状态（normal/hover/pressed/focus）+ disabled
# 内部布局：[code] | divider | [CN label] | [EN label] | [chevron ▶]
# 自绘背景 + 边框（chamfer 16px），文字用 draw_string 直接画
#
# 对应 design menu-button.jsx 规格：
#   - 边框 2px，颜色随状态切换 red_dim → red → red_deep（pressed）→ orange（focus）
#   - hover 时 chevron 显现并右移 4px
#   - pressed 时整体偏移 (2,2) + inset shadow
#   - danger=true 时红色全部换橙色（退出按钮专用）

signal pressed

# ---------- Public exports ----------
@export var code: String = "01":
	set(value):
		code = value
		queue_redraw()
@export var cn_label: String = "开始游戏":
	set(value):
		cn_label = value
		queue_redraw()
@export var en_label: String = "DEPLOY":
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
		queue_redraw()

@export_group("Fonts")
@export var font_mono: Font = preload("res://assets/fonts/font_jbmono_500.tres")
@export var font_cn: Font = preload("res://assets/fonts/font_notosc_900.tres")
@export var font_en: Font = preload("res://assets/fonts/font_oswald_500.tres")

@export_group("Layout")
@export var chamfer_size: float = 16.0
@export var pad_left: float = 24.0
@export var pad_right: float = 28.0
@export var divider_padding_right: float = 16.0
@export var code_min_width: float = 40.0

# ---------- State (managed internally) ----------
var _hover: bool = false
var _pressed: bool = false
var _focused: bool = false
var _sweep_t: float = 0.0  # hover scan-sweep 进度，0..1 循环

const _SWEEP_PERIOD: float = 1.4  # design: 1.4s linear infinite
const _SWEEP_PEAK_ALPHA: float = 0.22

func _ready() -> void:
	# 尊重 .tscn 显式设的 custom_minimum_size（pause/upgrade 等场景用更紧凑尺寸）
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 82)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	if not Engine.is_editor_hint():
		set_process(true)

func _process(delta: float) -> void:
	if not (_hover and not disabled):
		return
	if _sweep_t >= 1.0:
		return  # sweep 已扫完一次，等下次 mouse_enter 才再启动
	_sweep_t = minf(_sweep_t + delta / _SWEEP_PERIOD, 1.0)
	queue_redraw()

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
				_sweep_t = 0.0
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

# ---------- State derivation ----------
func _current_state() -> StringName:
	if disabled:
		return &"disabled"
	if _pressed:
		return &"pressed"
	if _hover:
		return &"hover"
	if _focused:
		return &"focus"
	return &"normal"

func _accent() -> Color:
	return UiPalette.ORANGE if danger else UiPalette.RED

func _accent_dim() -> Color:
	return Color("#a83a20") if danger else UiPalette.RED_DIM

# ---------- Drawing ----------
func _draw() -> void:
	var s := _current_state()
	var draw_offset := Vector2.ZERO
	if s == &"pressed":
		draw_offset = Vector2(2, 2)

	# 1. 背景填充
	var bg_top: Color
	var bg_bot: Color
	match s:
		&"pressed":
			bg_top = Color("#1a0d0a")
			bg_bot = UiPalette.BG_0
		&"hover":
			# design 用 linear-gradient 红色叠加层，简化为单一融合色
			bg_top = Color(0.102, 0.055, 0.047, 1).lerp(UiPalette.RED, 0.12)
			bg_bot = Color(0.102, 0.055, 0.047, 1).lerp(UiPalette.RED_DIM, 0.18)
		_:  # normal / focus / disabled
			bg_top = Color("#1a100c")
			bg_bot = Color("#120a08")

	var pts := ChamferPanel.build_polygon(size, chamfer_size)
	if draw_offset != Vector2.ZERO:
		var shifted: PackedVector2Array = []
		shifted.resize(pts.size())
		for i in pts.size():
			shifted[i] = pts[i] + draw_offset
		pts = shifted

	# 简化：纯色用 bg_bot 填充，渐变需要 shader，先省略（视觉差不大）
	draw_colored_polygon(pts, bg_bot)

	# 1.5 hover scan-sweep：1.4s linear 横向红 gradient 扫一次（不循环）
	# design @keyframes btn-sweep translate -100% → 100%，但用户想要"hover 一次 sweep 一次"
	if s == &"hover" and _sweep_t < 1.0:
		_draw_scan_sweep(draw_offset)

	# 2. 边框
	var border_col: Color
	var border_w: float = 2.0
	match s:
		&"focus":
			border_col = UiPalette.ORANGE
		&"hover":
			border_col = _accent()
		&"pressed":
			border_col = UiPalette.RED_DEEP
		&"disabled":
			border_col = UiPalette.LINE_SOFT
		_:
			border_col = _accent_dim()
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, border_col, border_w, true)

	# 3. focus 时外加 1px dashed cream 描边（offset 4px），简化为单层非虚线
	if s == &"focus":
		var off_pts: PackedVector2Array = ChamferPanel.build_polygon(size + Vector2(8, 8), chamfer_size + 4.0)
		var off_loop := off_pts.duplicate()
		off_loop.append(off_pts[0])
		for i in off_loop.size():
			off_loop[i] = off_loop[i] - Vector2(4, 4) + draw_offset
		draw_polyline(off_loop, UiPalette.with_alpha(UiPalette.CREAM, 0.5), 1.0, true)

	# 4. hover/focus 状态的外发光：用同色半透明粗 polyline 模拟
	if s == &"hover":
		draw_polyline(loop, UiPalette.with_alpha(_accent(), 0.4), border_w + 6.0, true)
		# 4 corner ticks（左上 + 右下 10×10 L）
		_draw_corner_ticks(_accent(), draw_offset)
	elif s == &"focus":
		draw_polyline(loop, UiPalette.with_alpha(UiPalette.ORANGE, 0.5), border_w + 4.0, true)
		_draw_corner_ticks(UiPalette.ORANGE, draw_offset)

	# 5. 文字内容布局
	var text_alpha: float = 0.5 if s == &"disabled" else 1.0
	var label_col: Color = UiPalette.CREAM_MUTE if s == &"disabled" \
		else UiPalette.CREAM if (s == &"hover" or s == &"focus") \
		else UiPalette.CREAM_DIM
	var accent_col: Color = _accent()
	var muted_col: Color = UiPalette.CREAM_MUTE
	var code_col: Color = accent_col if (s == &"hover" or s == &"focus") else muted_col
	var en_col: Color = code_col

	label_col.a *= text_alpha
	code_col.a *= text_alpha
	en_col.a *= text_alpha

	# 5a. code（mono 14, 左侧对齐）
	var code_size: int = 14
	var code_x := pad_left + draw_offset.x
	var center_y := size.y * 0.5 + draw_offset.y
	var code_str_size := font_mono.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, code_size)
	draw_string(font_mono, Vector2(code_x, center_y + code_str_size.y * 0.3),
		code, HORIZONTAL_ALIGNMENT_LEFT, -1, code_size, code_col)

	# 5b. divider 竖线（code 右侧）
	var divider_x := pad_left + maxf(code_min_width, code_str_size.x) + draw_offset.x
	draw_line(
		Vector2(divider_x, center_y - 22),
		Vector2(divider_x, center_y + 22),
		UiPalette.LINE, 1.0
	)

	# 5c. CN label（30, weight 900, letter-spacing ~0.32em, flex 1）
	# Godot draw_string 不支持 letter-spacing，用 FontVariation.spacing_glyph 模拟
	# 这里直接画字符串，间距损失接受
	var cn_size: int = 30
	var cn_x := divider_x + divider_padding_right + draw_offset.x
	draw_string(font_cn, Vector2(cn_x, center_y + 11),
		cn_label, HORIZONTAL_ALIGNMENT_LEFT, -1, cn_size, label_col)

	# 5d. EN sublabel（16, mono/oswald, 靠右对齐 chevron 左侧）
	var en_size: int = 16
	var chev := "▶" if (s == &"hover" or s == &"focus") else ""
	var chev_size: int = 22
	var chev_str_size := font_en.get_string_size(chev, HORIZONTAL_ALIGNMENT_LEFT, -1, chev_size)
	var en_str_size := font_en.get_string_size(en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size)
	var chev_extra_x: float = 4.0 if s == &"hover" else 0.0
	var en_x := size.x - pad_right - chev_str_size.x - 12.0 - en_str_size.x + draw_offset.x
	draw_string(font_en, Vector2(en_x, center_y + 6),
		en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, en_size, en_col)

	# 5e. chevron（hover/focus 才显示）
	if chev != "":
		draw_string(font_en, Vector2(size.x - pad_right - chev_str_size.x + chev_extra_x + draw_offset.x, center_y + 8),
			chev, HORIZONTAL_ALIGNMENT_LEFT, -1, chev_size, accent_col)

func _draw_corner_ticks(col: Color, off: Vector2) -> void:
	# 左上角 L（外凸 4px）
	draw_line(Vector2(-4, -4) + off, Vector2(6, -4) + off, col, 2.0)
	draw_line(Vector2(-4, -4) + off, Vector2(-4, 6) + off, col, 2.0)
	# 右下角 L
	draw_line(Vector2(size.x - 6, size.y + 4) + off, Vector2(size.x + 4, size.y + 4) + off, col, 2.0)
	draw_line(Vector2(size.x + 4, size.y - 6) + off, Vector2(size.x + 4, size.y + 4) + off, col, 2.0)

func _draw_scan_sweep(off: Vector2) -> void:
	# 横向 red sweep band：用 N 条垂直 stripe 拼合，每条按距离 sweep 中心算 alpha。
	# stripe x 始终在 [0, size.x] 内 — 不会画到按钮外。
	# stripe 在 chamfer 角部 y 收窄 — 不会溢出切角。
	var sweep_w: float = size.x * 0.55  # band 总宽（含两侧 fade）
	var half: float = sweep_w * 0.5
	# band 中心从 -half 扫到 size.x + half；超出按钮的部分由 stripe alpha 自然 fade 隐藏
	var travel: float = size.x + sweep_w
	var x_center: float = -half + _sweep_t * travel
	var stripes: int = 36
	var stripe_w: float = size.x / float(stripes)
	var accent: Color = _accent()
	for i in stripes:
		var sx: float = (float(i) + 0.5) * stripe_w  # stripe 中心 x（0..size.x）
		var dx: float = abs(sx - x_center)
		if dx >= half:
			continue
		# 二次曲线 fade：中心最亮，边缘 0
		var t_norm: float = dx / half  # 0..1
		var a: float = (1.0 - t_norm * t_norm) * _SWEEP_PEAK_ALPHA
		if a < 0.003:
			continue
		# chamfer 角避让：stripe 在 [0, chamfer_size] 或 [size.x - chamfer_size, size.x] 区域时 y 收窄
		var dist_edge: float = minf(sx, size.x - sx)
		var inset: float = 0.0
		if dist_edge < chamfer_size:
			inset = chamfer_size - dist_edge
		var col := accent
		col.a = a
		draw_rect(Rect2(
			sx - stripe_w * 0.5 + off.x,
			inset + off.y,
			stripe_w + 0.5,  # +0.5 防 stripe 间 1px 缝隙
			size.y - inset * 2.0
		), col)
