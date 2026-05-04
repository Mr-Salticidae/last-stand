extends Control

# 高分页：4 卡片网格显示 user://laststand_record.cfg 的 wave/score/time/combo
# 没记录时保持卡片默认 placeholder ("----" / "--:--:--")
# Esc 或返回按钮跳回主菜单

const RECORD_PATH: String = "user://laststand_record.cfg"
const RECORD_SECTION: String = "record"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

@onready var stat_wave: Control = $PageBody/Grid/StatWave
@onready var stat_score: Control = $PageBody/Grid/StatScore
@onready var stat_time: Control = $PageBody/Grid/StatTime
@onready var stat_combo: Control = $PageBody/Grid/StatCombo
@onready var back_btn: Control = $Footer/BackButton
@onready var warning_strip: Label = $PageBody/WarningStrip

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_main_bgm()
	_refresh()
	back_btn.pressed.connect(_on_back)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _refresh() -> void:
	var rec: Dictionary = _load_record()
	var has_record: bool = rec.wave > 0 or rec.score > 0 or rec.time > 0.0 or rec.combo > 0

	if has_record:
		stat_wave.value = "%d" % rec.wave
		stat_wave.caption = "PERSONAL BEST  ·  战绩已记录"

		stat_score.value = "%d" % rec.score
		stat_score.caption = "PERSONAL BEST  ·  战绩已记录"

		var total: int = int(rec.time)
		stat_time.value = "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
		stat_time.caption = "PERSONAL BEST  ·  战绩已记录"

		stat_combo.value = "%d" % rec.combo
		stat_combo.caption = "PERSONAL BEST  ·  战绩已记录"

		warning_strip.visible = false
	# else: 保持 .tscn 中的默认 placeholder + warning strip 显示

func _load_record() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_PATH) != OK:
		return {"wave": 0, "score": 0, "time": 0.0, "combo": 0}
	return {
		"wave": int(cfg.get_value(RECORD_SECTION, "wave", 0)),
		"score": int(cfg.get_value(RECORD_SECTION, "score", 0)),
		"time": float(cfg.get_value(RECORD_SECTION, "time", 0.0)),
		"combo": int(cfg.get_value(RECORD_SECTION, "combo", 0)),
	}

func _on_back() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
