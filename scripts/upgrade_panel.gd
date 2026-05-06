extends CanvasLayer

# 局内升级面板：wave_completed 后弹出，3 张卡 + 锁定 + 继续
# 显示时：player.input_locked = true（锁定移动/视角/开火），鼠标解锁，ESC 让位 pause_menu
# 点"继续"后关闭，emit panel_closed 让 wave_manager 继续流程

signal panel_closed

@onready var title_label: Label = $Center/Panel/TitleLabel
@onready var score_label: Label = $Center/Panel/ScoreLabel
@onready var cards_hbox: HBoxContainer = $Center/Panel/CardsHBox
@onready var continue_btn: ChamferButton = $Center/Panel/ContinueButton
@onready var card_slots: Array[Control] = [
	$Center/Panel/CardsHBox/Card0,
	$Center/Panel/CardsHBox/Card1,
	$Center/Panel/CardsHBox/Card2,
]

# 稀有度染色（设计 palette 里 RED/CREAM/ORANGE 系，蓝色保留作功能区分，跨色系最直观）
const RARITY_COLORS: Dictionary = {
	0: Color(0.55, 0.55, 0.6),   # COMMON：灰
	1: Color(0.35, 0.65, 1.0),   # RARE：蓝
	2: Color(1.0, 0.45, 0.18),   # LEGENDARY：橙（design palette ORANGE）
}
const RARITY_NAMES_CN: Dictionary = {
	0: "普通",
	1: "稀有",
	2: "传说",
}
const RARITY_NAMES_EN: Dictionary = {
	0: "COMMON",
	1: "RARE",
	2: "LEGENDARY",
}

var _current_wave: int = 0
var _wave_manager: Node = null
var _player: Node = null

func _ready() -> void:
	add_to_group("upgrade_panel")
	visible = false
	# 暂停时仍响应输入 / 渲染
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_btn.pressed.connect(_on_continue_pressed)
	for i in card_slots.size():
		var slot: Control = card_slots[i]
		var buy_btn: SecondaryButton = slot.get_node("BuyButton")
		var lock_btn: SecondaryButton = slot.get_node("LockButton")
		buy_btn.pressed.connect(_on_buy_pressed.bind(i))
		lock_btn.pressed.connect(_on_lock_pressed.bind(i))
	# 订阅 score 变化实时刷新按钮状态（买完后余额不够的灰掉）
	UpgradeManager.card_purchased.connect(_on_card_purchased)

func show_panel(wave_num: int) -> void:
	_current_wave = wave_num
	_wave_manager = get_tree().get_first_node_in_group("wave_manager")
	_player = get_tree().get_first_node_in_group("player")
	# 锁输入 + 鼠标可见
	if _player and "input_locked" in _player:
		_player.input_locked = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 抽卡 → 刷新 UI
	UpgradeManager.draw_cards(wave_num)
	_refresh_all()
	visible = true

func _refresh_all() -> void:
	title_label.text = "第 %d 波已清 · 升级备战" % _current_wave
	var currency: int = int(_wave_manager.currency) if _wave_manager else 0
	score_label.text = "// RESERVE FUNDS · %d CR" % currency
	var draw: Array[String] = UpgradeManager.current_draw
	for i in card_slots.size():
		var slot: Control = card_slots[i]
		if i < draw.size():
			_render_card_slot(slot, draw[i])
			slot.visible = true
		else:
			# 可选卡不足 3 张时隐藏多余槽位
			slot.visible = false

func _render_card_slot(slot: Control, card_id: String) -> void:
	var card: Dictionary = UpgradeManager.get_card(card_id)
	var name_label: Label = slot.get_node("NameLabel")
	var rarity_label: Label = slot.get_node("RarityLabel")
	var stack_label: Label = slot.get_node("StackLabel")
	var desc_label: Label = slot.get_node("DescLabel")
	var buy_btn: SecondaryButton = slot.get_node("BuyButton")
	var lock_btn: SecondaryButton = slot.get_node("LockButton")

	var rarity: int = int(card.rarity)
	var rarity_color: Color = RARITY_COLORS[rarity]
	name_label.text = card.name
	rarity_label.text = "// %s · %s" % [RARITY_NAMES_CN[rarity], RARITY_NAMES_EN[rarity]]
	rarity_label.add_theme_color_override("font_color", rarity_color)
	stack_label.text = "STACK · %d / %d" % [UpgradeManager.stack_count(card_id), int(card.max_stack)]
	desc_label.text = card.desc
	# 卡片边框：本波已购 → 稀有度色提亮版（让玩家一眼区分"已购买"状态）；否则用稀有度色
	var bought: bool = UpgradeManager.is_purchased_this_round(card_id)
	if slot is ChamferPanel:
		slot.border_color = rarity_color.lightened(0.4) if bought else rarity_color
	# 按钮文字 / 启用态（优先级：本波已购买 > 已满级 > 可购买）
	var cost: int = UpgradeManager.get_cost(card_id)
	var can_afford: bool = _wave_manager and int(_wave_manager.currency) >= cost
	var maxed: bool = UpgradeManager.is_maxed(card_id)
	if bought:
		buy_btn.cn_label = "已购买"
		buy_btn.en_label = "BOUGHT"
		buy_btn.disabled = true
	elif maxed:
		buy_btn.cn_label = "已满级"
		buy_btn.en_label = "MAXED"
		buy_btn.disabled = true
	else:
		buy_btn.cn_label = "购买"
		buy_btn.en_label = "BUY [%d CR]" % cost
		buy_btn.disabled = not can_afford
	# 锁定按钮：满级时禁用（锁了也没意义，下一波该卡不会被 draw）
	lock_btn.disabled = maxed
	if maxed:
		lock_btn.cn_label = "锁定"
		lock_btn.en_label = "LOCK"
	else:
		var locked: bool = UpgradeManager.is_locked(card_id)
		lock_btn.cn_label = "已锁定" if locked else "锁定"
		lock_btn.en_label = "LOCKED" if locked else "LOCK"

func _on_buy_pressed(slot_idx: int) -> void:
	AudioManager.play_ui_click()
	var draw: Array[String] = UpgradeManager.current_draw
	if slot_idx >= draw.size():
		return
	var id: String = draw[slot_idx]
	UpgradeManager.try_purchase(id)
	# 不 refresh 整块（buy 成功时 card_purchased 信号会刷），但其他卡的按钮可能因为余额变化需要更新
	_refresh_all()

func _on_lock_pressed(slot_idx: int) -> void:
	AudioManager.play_ui_click()
	var draw: Array[String] = UpgradeManager.current_draw
	if slot_idx >= draw.size():
		return
	UpgradeManager.toggle_lock(draw[slot_idx])
	_refresh_all()

func _on_card_purchased(id: String) -> void:
	_refresh_all()
	# 找到该卡对应的 slot，触发整卡闪烁动画
	var idx: int = UpgradeManager.current_draw.find(id)
	if idx >= 0 and idx < card_slots.size():
		_flash_card(card_slots[idx], UpgradeManager.get_card(id))

# 购买成功反馈：边框白闪 2 次 → 稳定到稀有度色提亮版（与 _render_card_slot 的 bought 分支一致）
# 边框变化比整卡 modulate 闪烁更显眼，且最终状态保留区分"已购买"
func _flash_card(slot: Control, card: Dictionary) -> void:
	if not slot is ChamferPanel:
		return
	var rarity: int = int(card.rarity)
	var rarity_color: Color = RARITY_COLORS[rarity]
	var purchased_color: Color = rarity_color.lightened(0.4)
	var flash_color: Color = UiPalette.CREAM
	var tween: Tween = create_tween()
	tween.tween_property(slot, "border_color", flash_color, 0.08)
	tween.tween_property(slot, "border_color", rarity_color, 0.10)
	tween.tween_property(slot, "border_color", flash_color, 0.08)
	tween.tween_property(slot, "border_color", purchased_color, 0.20)

func _on_continue_pressed() -> void:
	AudioManager.play_ui_click()
	_close_panel()

func _close_panel() -> void:
	visible = false
	if _player and "input_locked" in _player:
		_player.input_locked = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	panel_closed.emit()

# 切后台返回兜底：Windows 失焦会被 OS 释放鼠标 capture，回来时 Godot 状态可能与 OS 错位；
# 同时若失焦瞬间正好有 hit_pause 在进行，time_scale=0.3 可能未恢复。
# panel 可见时焦点回来 → 强制重 apply 一遍 panel 期望状态。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if _player and "input_locked" in _player:
			_player.input_locked = true
		Engine.time_scale = 1.0
