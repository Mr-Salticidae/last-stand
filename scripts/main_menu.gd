extends Control

# 主菜单：6 按钮路由到游戏 / 子页面 / 退出
# Settings / Credits / High Scores 都是独立 page，用 change_scene 跳转（不再 instance overlay）

const HIGH_SCORES_PATH: String = "res://scenes/high_scores_menu.tscn"
const SETTINGS_PATH: String = "res://scenes/settings_menu.tscn"
const CREDITS_PATH: String = "res://scenes/credits_menu.tscn"
const LEVEL_SELECT_PATH: String = "res://scenes/level_select.tscn"

@onready var start_btn: Control = $MainPage/RightColumn/Buttons/StartButton
@onready var level_select_btn: Control = $MainPage/RightColumn/Buttons/LevelSelectButton
@onready var record_btn: Control = $MainPage/RightColumn/Buttons/RecordButton
@onready var settings_btn: Control = $MainPage/RightColumn/Buttons/SettingsButton
@onready var credits_btn: Control = $MainPage/RightColumn/Buttons/CreditsButton
@onready var quit_btn: Control = $MainPage/RightColumn/Buttons/QuitButton
@onready var exit_confirm: ExitConfirm = $ExitConfirm
@onready var deploying_overlay: DeployingOverlay = $DeployingOverlay

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 单轨贯穿菜单+战斗：每次进入主菜单触发，跨场景延续不间断（autoload 上的 player）
	AudioManager.play_main_bgm()
	start_btn.pressed.connect(_on_start_pressed)
	level_select_btn.pressed.connect(_on_level_select_pressed)
	record_btn.pressed.connect(_on_record_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	credits_btn.pressed.connect(_on_credits_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	exit_confirm.confirmed.connect(_on_exit_confirmed)
	exit_confirm.cancelled.connect(_on_exit_cancelled)
	start_btn.grab_focus()

func _on_start_pressed() -> void:
	AudioManager.play_ui_click()
	var path: String = Settings.get_current_arena_scene()
	if path != "":
		deploying_overlay.show_for_scene(path)

func _on_level_select_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(LEVEL_SELECT_PATH)

func _on_record_pressed() -> void:
	AudioManager.play_ui_click()
	if ResourceLoader.exists(HIGH_SCORES_PATH):
		get_tree().change_scene_to_file(HIGH_SCORES_PATH)

func _on_settings_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(SETTINGS_PATH)

func _on_credits_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(CREDITS_PATH)

func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	exit_confirm.show_modal()

func _on_exit_confirmed() -> void:
	get_tree().quit()

func _on_exit_cancelled() -> void:
	# ChamferButton 按下时 grab_focus，cancel 后要主动释放，避免 QuitButton 持续点亮
	quit_btn.release_focus()
