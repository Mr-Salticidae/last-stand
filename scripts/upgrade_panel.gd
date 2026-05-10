extends CanvasLayer

# 局内升级面板：wave_completed 后弹出，3 张卡 + 锁定 + 继续
# 显示时：player.input_locked = true（锁定移动/视角/开火），鼠标解锁，ESC 让位 pause_menu
# 点"继续"后关闭，emit panel_closed 让 wave_manager 继续流程

signal panel_closed

@onready var title_label: Label = $Center/Panel/TitleLabel
@onready var score_label: Label = $Center/Panel/ScoreLabel
@onready var cards_hbox: HBoxContainer = $Center/Panel/CardsHBox
@onready var synergy_bar: Control = $Center/Panel/SynergyBar
@onready var synergy_hbox: HBoxContainer = $Center/Panel/SynergyBar/HBox
@onready var continue_btn: ChamferButton = $Center/Panel/ContinueButton
@onready var refresh_btn: ChamferButton = $Center/Panel/RefreshButton
@onready var card_slots: Array[Control] = [
	$Center/Panel/CardsHBox/Card0,
	$Center/Panel/CardsHBox/Card1,
	$Center/Panel/CardsHBox/Card2,
]
var card_sweeps: Array[SweepOverlay] = []

# 羁绊 chip 视觉常量（金 = 已激活 / 暗 = 差 1 卡 / 史诗用紫色 border 区分）
const SYNERGY_CHIP_FONT_SIZE: int = 13
const SYNERGY_GOLD: Color = Color(1.0, 0.78, 0.32, 1.0)
const SYNERGY_GOLD_BG: Color = Color(0.42, 0.30, 0.10, 0.85)
const SYNERGY_DIM: Color = Color(0.6, 0.55, 0.5, 0.7)
const SYNERGY_DIM_BG: Color = Color(0.10, 0.08, 0.07, 0.6)
const SYNERGY_EPIC: Color = Color(0.85, 0.55, 1.0, 1.0)  # 史诗紫

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
	refresh_btn.pressed.connect(_on_refresh_pressed)
	for i in card_slots.size():
		var slot: Control = card_slots[i]
		var buy_btn: SecondaryButton = slot.get_node("BuyButton")
		var lock_btn: SecondaryButton = slot.get_node("LockButton")
		buy_btn.pressed.connect(_on_buy_pressed.bind(i))
		lock_btn.pressed.connect(_on_lock_pressed.bind(i))
		# reroll 扫光蒙版（运行时挂到 slot 上，z_index=10 盖在内容之上）
		var sweep := SweepOverlay.new()
		slot.add_child(sweep)
		card_sweeps.append(sweep)
	# 订阅 score 变化实时刷新按钮状态（买完后余额不够的灰掉）
	UpgradeManager.card_purchased.connect(_on_card_purchased)
	# 羁绊：购买后 SynergyManager 已 check，UI 也要刷一遍 SynergyBar
	if has_node("/root/SynergyManager"):
		SynergyManager.synergy_activated.connect(_on_synergy_activated)

func show_panel(wave_num: int) -> void:
	_current_wave = wave_num
	_wave_manager = get_tree().get_first_node_in_group("wave_manager")
	_player = get_tree().get_first_node_in_group("player")
	# 锁输入 + 鼠标可见
	if _player and "input_locked" in _player:
		_player.input_locked = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 进入新一波商店：先重置波次状态（清"本波已购"+ 刷新计数归零），再抽卡
	UpgradeManager.prepare_new_round()
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
	_refresh_reroll_button(currency)
	_render_synergy_bar()

func _refresh_reroll_button(currency: int) -> void:
	var cost: int = UpgradeManager.get_reroll_cost()
	# pool 空（19 张卡都已叠满 / 已买 / 已在面板）时禁用，文案区分原因便于玩家理解
	if not UpgradeManager.can_reroll():
		refresh_btn.en_label = "POOL EMPTY"
		refresh_btn.disabled = true
	else:
		refresh_btn.en_label = "REROLL [%d CR]" % cost
		refresh_btn.disabled = currency < cost

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

func _on_synergy_activated(_id: String) -> void:
	# 羁绊新激活 → SynergyBar 重新渲染（从"差 1 卡"chip 变成"已激活"金色 chip）
	_render_synergy_bar()

# 渲染 SynergyBar：清空旧 chips → 已激活的优先（金色） → 差 1 张的（暗色）
# 没任何 chip 时整个 bar 隐藏（避免空 layout 占位）
# 注意：用 remove_child + queue_free 立即从 layout 树移除（仅 queue_free 当帧仍在树里，
# HBoxContainer 会把旧 children 算进 minimum_size 撑大外壳，导致 chip 行下沿挤进 Card 顶部）
func _render_synergy_bar() -> void:
	for c in synergy_hbox.get_children():
		synergy_hbox.remove_child(c)
		c.queue_free()
	if not has_node("/root/SynergyManager"):
		synergy_bar.visible = false
		return
	var active_count: int = SynergyManager.active_ids.size()
	var potential: Array[Dictionary] = SynergyManager.get_potential_synergies()
	if active_count == 0 and potential.is_empty():
		synergy_bar.visible = false
		return
	synergy_bar.visible = true
	# 已激活：按 SYNERGIES 顺序遍历 active_ids（保持稳定显示顺序）
	for s in SynergyManager.SYNERGIES:
		if SynergyManager.is_active(s.id):
			synergy_hbox.add_child(_make_synergy_chip(s, true))
	# 差 1 卡的：暗色显示，提示"还差 X"
	for s in potential:
		synergy_hbox.add_child(_make_synergy_chip(s, false))

# 单个羁绊 chip：PanelContainer + Label
# active=true → 金色 + 名字；active=false → 暗色 + 名字 + "差 1 卡" suffix
# tooltip 显示完整描述 + 触发卡列表
func _make_synergy_chip(s: Dictionary, active: bool) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var is_epic: bool = int(s.tier) == SynergyManager.Tier.EPIC
	if active:
		sb.bg_color = SYNERGY_GOLD_BG
		sb.border_color = SYNERGY_EPIC if is_epic else SYNERGY_GOLD
	else:
		sb.bg_color = SYNERGY_DIM_BG
		sb.border_color = SYNERGY_DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS  # tooltip 需要 hover
	chip.tooltip_text = "%s\n%s\n触发卡：%s" % [
		s.name,
		s.desc,
		_format_required_cards(s.cards),
	]
	var label := Label.new()
	var tier_marker: String = "★" if is_epic else "◆"
	if active:
		label.text = "%s %s" % [tier_marker, s.name]
		label.add_theme_color_override("font_color", SYNERGY_EPIC if is_epic else SYNERGY_GOLD)
	else:
		label.text = "%s %s · 差 1" % [tier_marker, s.name]
		label.add_theme_color_override("font_color", SYNERGY_DIM)
	label.add_theme_font_size_override("font_size", SYNERGY_CHIP_FONT_SIZE)
	chip.add_child(label)
	return chip

# tooltip 用：把 ["crit_chance", "heavy_rounds"] 渲染成 "穿甲弹 + 重型弹药"
func _format_required_cards(card_ids: Array) -> String:
	var names: Array = []
	for cid in card_ids:
		var c: Dictionary = UpgradeManager.get_card(cid)
		if c.is_empty():
			names.append(cid)
		else:
			names.append(c.name)
	return " + ".join(names)

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

func _on_refresh_pressed() -> void:
	AudioManager.play_ui_click()
	# 记录旧 draw 才能判断"哪些槽位真的换了"，只对换了的播 sweep
	var prev_draw: Array[String] = UpgradeManager.current_draw.duplicate()
	if UpgradeManager.try_reroll(_current_wave):
		_refresh_all()
		var new_draw: Array[String] = UpgradeManager.current_draw
		for i in card_slots.size():
			if i >= new_draw.size() or i >= card_sweeps.size():
				continue
			var changed: bool = i >= prev_draw.size() or prev_draw[i] != new_draw[i]
			if changed:
				card_sweeps[i].play()
	# panel 不关，焦点留在按钮上会持续点亮；reroll 后释放焦点（同 [feedback_godot_button_focus_release]）
	refresh_btn.release_focus()

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
