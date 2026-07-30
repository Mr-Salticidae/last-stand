@tool
class_name DeployingOverlay
extends Control

# 部署中 overlay。设计：design README §8
# 开始游戏按钮触发，约 2.2s 假 load 进度条 → 切场景。
# 用法：show_for_scene(path)；done 信号在切场景前 emit（可挂回调做收尾）

signal done

@export var fake_duration: float = 2.2

# arena key → "SECTOR XX · EN_NAME" 显示文本
const SECTOR_TEXT: Dictionary = {
	"training":  "SECTOR 02 · PROVING GROUND",
	"warehouse": "SECTOR 05 · DEPOT 07",
	"outpost":   "SECTOR 07 · DESERT OUTPOST",
}

@onready var _bar: DeployingProgressBar = $Center/Stack/BarOuter
@onready var _pct_label: Label = $Center/Stack/BottomRow/PctLabel
@onready var _sector_label: Label = $Center/Stack/BottomRow/SectorLabel

var _scene_path: String = ""
var _elapsed: float = 0.0
var _running: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_for_scene(path: String) -> void:
	_scene_path = path
	var key: String = Settings.last_arena
	_sector_label.text = SECTOR_TEXT.get(key, "SECTOR ?? · UNKNOWN")
	_pct_label.text = "0%" + _wave_tag()
	_bar.progress = 0.0
	_elapsed = 0.0
	_running = true
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(dt: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	_elapsed += dt
	var t: float = clampf(_elapsed / fake_duration, 0.0, 1.0)
	_bar.progress = t
	_pct_label.text = "%d%%" % int(t * 100.0) + _wave_tag()
	if t >= 1.0:
		_running = false
		_finish()

# 进关提示带上模式，让玩家在读条时就知道自己开的是哪一局
func _wave_tag() -> String:
	return " · ENDLESS · WAVE 01 INBOUND" if Settings.is_endless() else " · WAVE 01 INBOUND"

func _finish() -> void:
	await get_tree().create_timer(0.4).timeout
	done.emit()
	if _scene_path != "" and is_inside_tree():
		get_tree().change_scene_to_file(_scene_path)
