@tool
class_name StatCard
extends Control

# 高分页 4 卡片：背景 + 边框 + 4 角 corner ticks 由 _draw 自绘
# 文字（code/cn/value/unit/caption）改用 Label 子节点，方便编辑器里可视化拖动调整位置
# 用 stat_card.tscn 作为模板实例化

@onready var _code_en_label: Label = get_node_or_null("CodeENLabel")
@onready var _cn_label_node: Label = get_node_or_null("CNLabel")
@onready var _value_label: Label = get_node_or_null("ValueLabel")
@onready var _unit_label: Label = get_node_or_null("UnitLabel")
@onready var _caption_label: Label = get_node_or_null("CaptionLabel")

@export var code: String = "01":
	set(v):
		code = v
		_refresh_top_label()
@export var cn_label: String = "最高波次":
	set(v):
		cn_label = v
		if _cn_label_node:
			_cn_label_node.text = v
@export var en_label: String = "TOP WAVE":
	set(v):
		en_label = v
		_refresh_top_label()
@export var value: String = "----":
	set(v):
		value = v
		if _value_label:
			_value_label.text = v
@export var unit: String = "WAVE":
	set(v):
		unit = v
		if _unit_label:
			_unit_label.text = v
@export var caption: String = "NO RECORD ON FILE  ·  AWAITING FIRST DEPLOYMENT":
	set(v):
		caption = v
		if _caption_label:
			_caption_label.text = v

@export_group("Layout")
@export var chamfer_size: float = 18.0:
	set(v):
		chamfer_size = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	# 应用 export 默认值到 Label（_ready 时 @onready 才生效）
	_refresh_top_label()
	if _cn_label_node:
		_cn_label_node.text = cn_label
	if _value_label:
		_value_label.text = value
	if _unit_label:
		_unit_label.text = unit
	if _caption_label:
		_caption_label.text = caption

func _refresh_top_label() -> void:
	if _code_en_label:
		_code_en_label.text = "[" + code + "] " + en_label

func _draw() -> void:
	var pts := ChamferPanel.build_polygon(size, chamfer_size)
	# 1. 背景
	draw_colored_polygon(pts, Color(0.102, 0.055, 0.047, 0.92))
	# 2. 边框
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, UiPalette.LINE, 2.0, true)
	# 3. 4 角 corner ticks
	_draw_corner_ticks()

func _draw_corner_ticks() -> void:
	# 仅 top-left 和 bottom-right 两个直角处画 L 形（跟 chamfer 切的对角呼应）
	# 紧贴边框边缘，不向内偏移；颜色用主红色比 RED_DIM 更醒目
	var t: float = 18.0
	var c := UiPalette.RED
	var lw: float = 2.0
	# top-left
	draw_line(Vector2(0, 0), Vector2(t, 0), c, lw)
	draw_line(Vector2(0, 0), Vector2(0, t), c, lw)
	# bottom-right
	draw_line(Vector2(size.x, size.y), Vector2(size.x - t, size.y), c, lw)
	draw_line(Vector2(size.x, size.y), Vector2(size.x, size.y - t), c, lw)
