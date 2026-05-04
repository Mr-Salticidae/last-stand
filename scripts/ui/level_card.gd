@tool
class_name LevelCard
extends Control

# 关卡选择卡片：跟 StatCard 同款 — Label/ColorRect/Panel 子节点 + 仅自绘卡片背景与边框。
# 使用方式：preload("res://scenes/ui_common/level_card.tscn").instantiate()，
# 然后 set 各 export 值。setter 会同步到对应子节点。

signal pressed

@onready var _thumb: LevelThumbnail = get_node_or_null("ThumbBg") as LevelThumbnail
@onready var _thumb_label: Label = get_node_or_null("ThumbLabel")
@onready var _map_chip_label: Label = get_node_or_null("MapChip/Label")
@onready var _threat_chip_label: Label = get_node_or_null("ThreatChip/Label")
@onready var _cn_label: Label = get_node_or_null("CnNameLabel")
@onready var _en_label: Label = get_node_or_null("EnNameLabel")
@onready var _desc_label: Label = get_node_or_null("DescLabel")
@onready var _locked_label: Label = get_node_or_null("LockedLabel")

@export var key: String = "training":
	set(v):
		key = v
		_apply_thumb_kind()
		_refresh_map_chip()
@export var cn_name: String = "训练场":
	set(v):
		cn_name = v
		if _cn_label:
			_cn_label.text = v
@export var en_name: String = "PROVING GROUND":
	set(v):
		en_name = v
		_refresh_map_chip()
		if _en_label:
			_en_label.text = v
		if _thumb_label:
			_thumb_label.text = v
@export var desc: String = "":
	set(v):
		desc = v
		if _desc_label:
			_desc_label.text = v
@export var threat: String = "MED":  # LOW / MED / HIGH
	set(v):
		threat = v
		if _threat_chip_label:
			_threat_chip_label.text = "THREAT · " + v.to_upper()
@export var available: bool = true:
	set(v):
		available = v
		modulate.a = 1.0 if v else 0.55
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_FORBIDDEN
		if _locked_label:
			_locked_label.visible = not v

var _hover: bool = false
var _focused: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_FORBIDDEN
	# 同步 export 默认到 Label（@onready 在 _ready 时才生效）
	_apply_thumb_kind()
	_refresh_map_chip()
	if _cn_label: _cn_label.text = cn_name
	if _en_label: _en_label.text = en_name
	if _desc_label: _desc_label.text = desc
	if _threat_chip_label: _threat_chip_label.text = "THREAT · " + threat.to_upper()
	if _locked_label:
		_locked_label.visible = not available
	modulate.a = 1.0 if available else 0.55

func _apply_thumb_kind() -> void:
	if _thumb and key in ["training", "warehouse", "outpost"]:
		_thumb.kind = key

func _refresh_map_chip() -> void:
	if _map_chip_label:
		_map_chip_label.text = "MAP · " + en_name.to_upper()

func _gui_input(event: InputEvent) -> void:
	if not available:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		pressed.emit()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			pressed.emit()
			accept_event()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if available:
				_hover = true
				_sync_thumb_active()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_sync_thumb_active()
		NOTIFICATION_FOCUS_ENTER:
			_focused = true
			_sync_thumb_active()
		NOTIFICATION_FOCUS_EXIT:
			_focused = false
			_sync_thumb_active()

func _sync_thumb_active() -> void:
	if _thumb:
		_thumb.active = (_hover and available) or _focused
	queue_redraw()

# details 区（thumb 下方文字区）自绘背景 + 卡片下半 3 边外框
# thumb 区由 LevelThumbnail 画填色 + 4 边外框；这里补全下半，让上下拼成完整卡片
func _draw() -> void:
	const DETAILS_Y: float = 330.0  # ThumbBg.size.y
	var details_h: float = size.y - DETAILS_Y
	if details_h <= 0.0:
		return
	# 暗棕底色（比 thumb 区背景浅一档，区分 layer）
	draw_rect(Rect2(0, DETAILS_Y, size.x, details_h), UiPalette.BG_2)
	# 分隔线：thumb 与 details 之间一条暗线
	draw_line(Vector2(0, DETAILS_Y), Vector2(size.x, DETAILS_Y), UiPalette.LINE, 1.0)
	# details 区 3 边外框（左/右/下）— 与 thumb 区外框在 DETAILS_Y 处衔接成完整卡片
	var border_col: Color = UiPalette.RED if ((_hover and available) or _focused) else UiPalette.LINE
	var t: float = 2.0
	draw_line(Vector2(0, DETAILS_Y), Vector2(0, size.y), border_col, t)
	draw_line(Vector2(size.x, DETAILS_Y), Vector2(size.x, size.y), border_col, t)
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), border_col, t)
