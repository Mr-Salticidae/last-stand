extends Control

# 设置页（page mode）：跳转自主菜单，返回时 change_scene 回主菜单
# 兼容 overlay mode：如果被 instance 添加到其他场景（如 pause_menu），closed 信号外发让外部 free

signal closed

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

@onready var master_slider: CustomSlider = $PageBody/LeftCol/AudioGroup/MasterRow/Slider
@onready var master_value: Label = $PageBody/LeftCol/AudioGroup/MasterRow/Value
@onready var sfx_slider: CustomSlider = $PageBody/LeftCol/AudioGroup/SfxRow/Slider
@onready var sfx_value: Label = $PageBody/LeftCol/AudioGroup/SfxRow/Value
@onready var music_slider: CustomSlider = $PageBody/LeftCol/AudioGroup/MusicRow/Slider
@onready var music_value: Label = $PageBody/LeftCol/AudioGroup/MusicRow/Value

@onready var sens_slider: CustomSlider = $PageBody/LeftCol/ControlsGroup/SensRow/Slider
@onready var sens_value: Label = $PageBody/LeftCol/ControlsGroup/SensRow/Value

@onready var window_mode_cycle: CustomCycleButton = $PageBody/RightCol/DisplayGroup/WindowModeRow/Cycle
@onready var resolution_cycle: CustomCycleButton = $PageBody/RightCol/DisplayGroup/ResolutionRow/Cycle
@onready var vsync_toggle: CustomToggle = $PageBody/RightCol/DisplayGroup/VsyncRow/Toggle
@onready var fps_cycle: CustomCycleButton = $PageBody/RightCol/DisplayGroup/FpsRow/Cycle

@onready var back_btn: Control = $Footer/BackButton

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Audio sliders
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.value = Settings.master_volume
	master_slider.value_changed.connect(_on_master_changed)

	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.value = Settings.sfx_volume
	sfx_slider.value_changed.connect(_on_sfx_changed)

	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(_on_music_changed)

	# Controls
	sens_slider.min_value = 0.05
	sens_slider.max_value = 0.5
	sens_slider.step = 0.01
	sens_slider.value = Settings.mouse_sensitivity
	sens_slider.value_changed.connect(_on_sens_changed)

	# Display: window mode + resolution（cycle）
	window_mode_cycle.options = PackedStringArray(Settings.WINDOW_MODE_NAMES)
	window_mode_cycle.current_index = Settings.window_mode
	window_mode_cycle.value_changed.connect(_on_window_mode_changed)

	resolution_cycle.options = PackedStringArray(Settings.RESOLUTION_NAMES)
	resolution_cycle.current_index = Settings.resolution_idx
	resolution_cycle.value_changed.connect(_on_resolution_changed)

	# Display: vsync toggle
	vsync_toggle.pressed = Settings.vsync_enabled
	vsync_toggle.toggled.connect(_on_vsync_toggled)

	# FPS cycle: options 来自 Settings.FPS_NAMES，初始 index 来自 Settings.fps_limit_idx
	fps_cycle.options = PackedStringArray(Settings.FPS_NAMES)
	fps_cycle.current_index = Settings.fps_limit_idx
	fps_cycle.value_changed.connect(_on_fps_changed)

	back_btn.pressed.connect(_on_back)
	_refresh_all_values()

func _refresh_all_values() -> void:
	master_value.text = "%d%%" % roundi(Settings.master_volume * 100.0)
	sfx_value.text = "%d%%" % roundi(Settings.sfx_volume * 100.0)
	music_value.text = "%d%%" % roundi(Settings.music_volume * 100.0)
	# 灵敏度 0.05-0.5 映射 10%-100%
	var sens_pct: int = roundi((Settings.mouse_sensitivity - 0.05) / 0.45 * 100.0)
	sens_value.text = "%d%%" % sens_pct

func _on_master_changed(v: float) -> void:
	Settings.set_master_volume(v)
	_refresh_all_values()

func _on_sfx_changed(v: float) -> void:
	Settings.set_sfx_volume(v)
	_refresh_all_values()

func _on_music_changed(v: float) -> void:
	Settings.set_music_volume(v)
	_refresh_all_values()

func _on_sens_changed(v: float) -> void:
	Settings.set_mouse_sensitivity(v)
	_refresh_all_values()

func _on_window_mode_changed(idx: int, _option: String) -> void:
	Settings.set_window_mode(idx)

func _on_resolution_changed(idx: int, _option: String) -> void:
	Settings.set_resolution_idx(idx)

func _on_vsync_toggled(p: bool) -> void:
	Settings.set_vsync_enabled(p)

func _on_fps_changed(idx: int, _option: String) -> void:
	Settings.set_fps_limit_idx(idx)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _on_back() -> void:
	AudioManager.play_ui_click()
	closed.emit()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		queue_free()
