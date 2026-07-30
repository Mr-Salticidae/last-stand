extends Control

# 高分页：4 卡片网格显示 user://laststand_record.cfg 的 wave/score/time/combo
# 标准 30 波与无尽两个模式各占一个 section，顶部 cycle 切换榜单
# 没记录时回落到 "----" / "--:--:--" placeholder + 显示 warning strip
# Esc 或返回按钮跳回主菜单

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const PLACEHOLDER_VALUE: String = "----"
const PLACEHOLDER_TIME: String = "--:--:--"
const PLACEHOLDER_CAPTION: String = "NO RECORD ON FILE  ·  AWAITING FIRST DEPLOYMENT"
const RECORD_CAPTION: String = "PERSONAL BEST  ·  战绩已记录"

@onready var stat_wave: Control = $PageBody/Grid/StatWave
@onready var stat_score: Control = $PageBody/Grid/StatScore
@onready var stat_time: Control = $PageBody/Grid/StatTime
@onready var stat_combo: Control = $PageBody/Grid/StatCombo
@onready var back_btn: Control = $Footer/BackButton
@onready var warning_strip: Label = $PageBody/WarningStrip
@onready var mode_cycle: CustomCycleButton = $ModeRow/Cycle

# 当前正在查看的榜单（默认跟随玩家上次选的游戏模式）
var _view_mode_idx: int = 0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_main_bgm()
	_view_mode_idx = Settings.game_mode_idx
	mode_cycle.options = PackedStringArray(Settings.GAME_MODE_NAMES_CN)
	mode_cycle.current_index = _view_mode_idx
	mode_cycle.value_changed.connect(_on_mode_changed)
	_refresh()
	back_btn.pressed.connect(_on_back)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

# 只切"看哪个榜"，不改玩家实际要开哪个模式（那是关卡选择页/设置页的职责）
func _on_mode_changed(idx: int, _option: String) -> void:
	AudioManager.play_ui_click()
	_view_mode_idx = idx
	_refresh()

func _refresh() -> void:
	var rec: Dictionary = _load_record(Settings.record_section_for(_view_mode_idx))
	var has_record: bool = rec.wave > 0 or rec.score > 0 or rec.time > 0.0 or rec.combo > 0
	var endless: bool = Settings.record_section_for(_view_mode_idx) != "record"

	# 无尽榜的第一指标是"守了多久"，波数改称"抵达波次"
	stat_wave.cn_label = "抵达波次" if endless else "最高波次"
	stat_wave.en_label = "WAVE REACHED" if endless else "TOP WAVE"
	stat_time.cn_label = "最长坚守" if endless else "最长存活"

	var caption: String = RECORD_CAPTION if has_record else PLACEHOLDER_CAPTION
	# 每次刷新都要把四张卡写全：切榜单时另一边可能没记录，
	# 不重置的话会留着上一个榜单的数字（静默串榜）
	stat_wave.value = "%d" % rec.wave if has_record else PLACEHOLDER_VALUE
	stat_score.value = "%d" % rec.score if has_record else PLACEHOLDER_VALUE
	stat_combo.value = "%d" % rec.combo if has_record else PLACEHOLDER_VALUE
	if has_record:
		var total: int = int(rec.time)
		stat_time.value = "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
	else:
		stat_time.value = PLACEHOLDER_TIME
	for card in [stat_wave, stat_score, stat_time, stat_combo]:
		card.caption = caption

	# 文案随榜单而变：老玩家切到还没打过的无尽榜时，不该看到"首次启动"
	warning_strip.visible = not has_record
	if not has_record:
		warning_strip.text = "⚠  NO ENDLESS RECORD  ·  完成一局无尽模式后将记录数据" if endless \
			else "⚠  NO CAMPAIGN RECORD  ·  完成一局标准模式后将记录数据"

func _load_record(section: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(Settings.RECORD_PATH)
	if err == ERR_FILE_NOT_FOUND:
		return {"wave": 0, "score": 0, "time": 0.0, "combo": 0}
	if err != OK:
		# 文件损坏：备份原文件让玩家有机会找回，避免下次 save 覆盖
		Settings.backup_corrupt_config(Settings.RECORD_PATH, err)
		return {"wave": 0, "score": 0, "time": 0.0, "combo": 0}
	return {
		"wave": int(cfg.get_value(section, "wave", 0)),
		"score": int(cfg.get_value(section, "score", 0)),
		"time": float(cfg.get_value(section, "time", 0.0)),
		"combo": int(cfg.get_value(section, "combo", 0)),
	}

func _on_back() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
