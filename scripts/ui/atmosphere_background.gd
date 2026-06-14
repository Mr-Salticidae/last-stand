@tool
class_name AtmosphereBackground
extends Control

# 共享背景层：覆盖 1920×1080 整个 canvas，含 base 色 + vignette + hazard frame +
# corner brackets + HUD top/bottom strips
#
# 每个 menu 场景的 root 节点 instance 一份。子节点可在 .tscn 单独 hide。
#
# 全屏 shader 特效（搜索灯/灰尘/噪点/扫描线）放 Phase 5 加。

@export_group("HUD Top")
@export var hud_top_left: String = "SECTOR 07 · UNDER SIEGE":
	set(value):
		hud_top_left = value
		_refresh_hud()
@export var hud_top_center: String = "CLASSIFIED // FOR OPERATOR EYES ONLY":
	set(value):
		hud_top_center = value
		_refresh_hud()
@export var hud_top_right: String = "RED ALERT":
	set(value):
		hud_top_right = value
		_refresh_hud()

@export_group("HUD Bottom")
# 支持 BBCode：UNKNOWN / OFFLINE 用 RED_DIM #8c1a1a 突出，前后缀走 default_color CREAM_DIM
@export var hud_bot_left: String = "OPERATOR ID — [color=#8c1a1a]UNKNOWN[/color]  ·  COMMS LINK [color=#8c1a1a]OFFLINE[/color]":
	set(value):
		hud_bot_left = value
		_refresh_hud()
@export var hud_bot_right: String = "v0.7.0 DEMO BUILD":
	set(value):
		hud_bot_right = value
		_refresh_hud()

@export_group("Visibility")
@export var show_hazard_frame: bool = true:
	set(value):
		show_hazard_frame = value
		_apply_visibility()
@export var show_corner_brackets: bool = true:
	set(value):
		show_corner_brackets = value
		_apply_visibility()
@export var show_hud: bool = true:
	set(value):
		show_hud = value
		_apply_visibility()
@export var show_searchlight: bool = true:
	set(value):
		show_searchlight = value
		_apply_visibility()
@export var show_dust: bool = true:
	set(value):
		show_dust = value
		_apply_visibility()
@export var show_scanline_sweep: bool = true:
	set(value):
		show_scanline_sweep = value
		_apply_visibility()
@export var show_grain: bool = true:
	set(value):
		show_grain = value
		_apply_visibility()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_refresh_hud()
	_apply_visibility()

func _refresh_hud() -> void:
	if not is_inside_tree():
		return
	var lbl := get_node_or_null("HudTop/Left") as Label
	if lbl: lbl.text = hud_top_left
	lbl = get_node_or_null("HudTop/Center") as Label
	if lbl: lbl.text = hud_top_center
	lbl = get_node_or_null("HudTop/Right") as Label
	if lbl: lbl.text = hud_top_right
	var rtl := get_node_or_null("HudBot/Left") as RichTextLabel
	if rtl: rtl.text = hud_bot_left
	lbl = get_node_or_null("HudBot/Right") as Label
	if lbl: lbl.text = hud_bot_right

func _apply_visibility() -> void:
	if not is_inside_tree():
		return
	var hf := get_node_or_null("HazardFrame")
	if hf: hf.visible = show_hazard_frame
	var cb := get_node_or_null("CornerBrackets")
	if cb: cb.visible = show_corner_brackets
	var hudt := get_node_or_null("HudTop")
	if hudt: hudt.visible = show_hud
	var hudb := get_node_or_null("HudBot")
	if hudb: hudb.visible = show_hud
	var sl := get_node_or_null("Searchlight")
	if sl: sl.visible = show_searchlight
	var du := get_node_or_null("Dust")
	if du: du.visible = show_dust
	var sw := get_node_or_null("ScanlineSweep")
	if sw: sw.visible = show_scanline_sweep
	var gr := get_node_or_null("Grain")
	if gr: gr.visible = show_grain
