extends CanvasLayer

# 暂停菜单：ESC toggle 游戏 pause 并显示/隐藏覆盖层。
# 整个 CanvasLayer process_mode = ALWAYS，即使 tree.paused 也能响应 input

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/settings_menu.tscn")
const HOWTO_MENU_SCENE: PackedScene = preload("res://scenes/howto_menu.tscn")

@onready var continue_btn: ChamferButton = $Dim/Center/Panel/VBox/ContinueButton
@onready var howto_btn: ChamferButton = $Dim/Center/Panel/VBox/HowtoButton
@onready var settings_btn: ChamferButton = $Dim/Center/Panel/VBox/SettingsButton
@onready var menu_btn: ChamferButton = $Dim/Center/Panel/VBox/MenuButton
@onready var quit_btn: ChamferButton = $Dim/Center/Panel/VBox/QuitButton

var _paused: bool = false
var _settings_overlay: Control = null
var _howto_overlay: Control = null

func _ready() -> void:
	visible = false
	continue_btn.pressed.connect(_on_continue_pressed)
	howto_btn.pressed.connect(_on_howto_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _on_continue_pressed() -> void:
	AudioManager.play_ui_click()
	_resume()

func _on_settings_pressed() -> void:
	AudioManager.play_ui_click()
	if _settings_overlay != null:
		return
	_settings_overlay = SETTINGS_MENU_SCENE.instantiate()
	_settings_overlay.closed.connect(_on_settings_closed)
	add_child(_settings_overlay)

func _on_settings_closed() -> void:
	_settings_overlay = null
	# 主动释放设置按钮焦点，避免它持续点亮（点击时 ChamferButton 自动 grab_focus）
	settings_btn.release_focus()

func _on_howto_pressed() -> void:
	AudioManager.play_ui_click()
	if _howto_overlay != null:
		return
	_howto_overlay = HOWTO_MENU_SCENE.instantiate()
	_howto_overlay.closed.connect(_on_howto_closed)
	add_child(_howto_overlay)

func _on_howto_closed() -> void:
	_howto_overlay = null
	howto_btn.release_focus()

func _on_menu_pressed() -> void:
	AudioManager.play_ui_click()
	_to_main_menu()

func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	_quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 玩家死亡序列期间不允许暂停（DeathScreen 正在处理）
		var player: Node = get_tree().get_first_node_in_group("player")
		if player and "_dead" in player and player._dead:
			return
		# 升级面板开启时让位（面板自己决定 ESC 是否关闭自身）
		var upgrade_panel: Node = get_tree().get_first_node_in_group("upgrade_panel")
		if upgrade_panel and upgrade_panel.visible:
			return
		# 设置覆盖层在上层时，ESC 由 settings_menu 自己处理（先关设置）
		if _settings_overlay != null:
			return
		# 操作说明覆盖层在上层时，ESC 由 howto_menu 自己处理（先关说明页）
		if _howto_overlay != null:
			return
		if _paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	_paused = true
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _resume() -> void:
	_paused = false
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _to_main_menu() -> void:
	get_tree().paused = false
	UpgradeManager.reset()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _quit() -> void:
	get_tree().paused = false
	get_tree().quit()

# 切后台返回兜底：暂停时焦点回来强制重 apply VISIBLE，避免 Windows 失焦释放 capture 后状态错位。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		Engine.time_scale = 1.0
