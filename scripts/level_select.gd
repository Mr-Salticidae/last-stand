extends Control

# 关卡选择页：从 Settings.ARENAS 读数据 + LEVEL_DETAILS 内表补充 EN name / threat
# 用 LevelCard 自定义控件渲染。点击可用卡片 → set_last_arena + 切场景

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LEVEL_CARD_SCENE: PackedScene = preload("res://scenes/ui_common/level_card.tscn")

# ARENAS 没有 EN name / threat 等设计字段，这里补充映射
# 不动 settings.gd 是因为这些是 UI 层装饰，不影响存档逻辑
const LEVEL_DETAILS: Dictionary = {
	"training":  {"en": "PROVING GROUND", "threat": "MED"},
	"warehouse": {"en": "DEPOT 07",       "threat": "HIGH"},
	"outpost":   {"en": "DESERT OUTPOST", "threat": "LOW"},
}

@onready var cards_hbox: HBoxContainer = $PageBody/CardsHBox
@onready var back_btn: Control = $Footer/BackButton
@onready var mode_cycle: CustomCycleButton = $ModeRow/Cycle

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_main_bgm()
	_build_cards()
	# 模式选择：只写 Settings，不参与切场景。change_scene_to_file 不能传参，
	# 进关后由 wave_manager 自己 pull（_on_card_selected 因此一个字都不用改）
	mode_cycle.options = PackedStringArray(Settings.GAME_MODE_NAMES_CN)
	mode_cycle.current_index = Settings.game_mode_idx
	mode_cycle.value_changed.connect(_on_mode_changed)
	back_btn.pressed.connect(_on_back)

func _on_mode_changed(idx: int, _option: String) -> void:
	AudioManager.play_ui_click()
	Settings.set_game_mode_idx(idx)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()

func _build_cards() -> void:
	for arena in Settings.ARENAS:
		var key: String = arena["key"]
		var details: Dictionary = LEVEL_DETAILS.get(key, {"en": key.to_upper(), "threat": "MED"})
		var card: LevelCard = LEVEL_CARD_SCENE.instantiate()
		card.key = key
		card.cn_name = arena["name"]
		card.en_name = details["en"]
		card.desc = arena["desc"]
		card.threat = details["threat"]
		card.available = bool(arena["available"])
		if card.available:
			card.pressed.connect(_on_card_selected.bind(key))
		cards_hbox.add_child(card)

func _on_card_selected(key: String) -> void:
	AudioManager.play_ui_click()
	Settings.set_last_arena(key)
	var path: String = Settings.get_current_arena_scene()
	if path != "":
		get_tree().change_scene_to_file(path)

func _on_back() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
