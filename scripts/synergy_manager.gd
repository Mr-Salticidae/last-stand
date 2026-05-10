extends Node

# 局内羁绊系统：autoload 单例。监听 UpgradeManager 卡牌购买，自动激活/解除满足条件的羁绊。
# 设计：哈迪斯式 Duo Boon，2 卡 = 稀有羁绊，3 卡 = 史诗羁绊；不占商店槽位，纯 build 奖励。
# 实现：每次 try_purchase 末尾调 check_active() → diff 出新增/失效 → 调 _apply / _remove 改 wm/player buff 字段。

# ========== 稀有度 ==========
enum Tier { RARE, EPIC }  # 稀有=2卡 / 史诗=3卡

# ========== 羁绊数据（8 条） ==========
# 字段：id / name / desc / tier / cards (触发卡 id 数组)
# 效果实现见 _apply_synergy / _remove_synergy 的 match 派发
const SYNERGIES: Array[Dictionary] = [
	# --- 5 个稀有羁绊（2 卡触发） ---
	{
		"id": "stormpierce",
		"name": "暴风穿透",
		"desc": "暴击概率 +10%，暴击命中触发 0.2s 打断",
		"tier": Tier.RARE,
		"cards": ["crit_chance", "heavy_rounds"],
	},
	{
		"id": "reaper_dance",
		"name": "死神之舞",
		"desc": "击杀回血 +1，嗜血单次上限 +1",
		"tier": Tier.RARE,
		"cards": ["kill_heal", "vampiric"],
	},
	{
		"id": "pacekeeper",
		"name": "节拍枪手",
		"desc": "连击 ≥5 时杀戮狂热持续 ×1.66、额外射速 +20%",
		"tier": Tier.RARE,
		"cards": ["dash_combo", "kill_rage"],
	},
	{
		"id": "reaper_whisper",
		"name": "死神低语",
		"desc": "猎手本能伤害额外 ×1.3",
		"tier": Tier.RARE,
		"cards": ["weak_spot", "headshot"],
	},
	{
		"id": "mag_artist",
		"name": "弹匣艺术家",
		"desc": "弹匣末发同时获得换弹首发暴伤倍率（首末双爆）",
		"tier": Tier.RARE,
		"cards": ["reload_burst", "last_round"],
	},
	# --- 3 个史诗羁绊（3 卡触发） ---
	{
		"id": "lightning_war",
		"name": "闪电战",
		"desc": "滑铲速度 +50%，滑铲结束后短暂无敌 0.8s",
		"tier": Tier.EPIC,
		"cards": ["move_speed", "dash_combo", "slide_burst"],
	},
	{
		"id": "eternal_warrior",
		"name": "永恒战神",
		"desc": "狂战士触发阈值 30% → 50%，嗜血率 +2%",
		"tier": Tier.EPIC,
		"cards": ["berserker", "immortal", "vampiric"],
	},
	{
		"id": "reaper_realm",
		"name": "死神领域",
		"desc": "连击 ≥10 时所有击杀回 10 弹药 + 刷新杀戮狂热",
		"tier": Tier.EPIC,
		"cards": ["chain_kill", "kill_rage", "combo_rage"],
	},
]

# ========== 运行时状态 ==========
var active_ids: Array[String] = []

signal synergy_activated(id: String)        # 新触发 → HUD toast
signal synergy_deactivated(id: String)      # reset 用（实战中卡不会反向 unstack）

# ========== API ==========

# UpgradeManager.reset() 末尾调
func reset() -> void:
	for id in active_ids.duplicate():
		_remove_synergy(id)
	active_ids.clear()

# UpgradeManager.try_purchase 成功后调（卡 stack 变化时唯一入口）
# diff 算法：扫描所有 SYNERGIES，按"是否所有触发卡都已拥有"分组，与 active_ids 对比
func check_active() -> void:
	var ids_now: Array[String] = []
	for s in SYNERGIES:
		if _has_all(s.cards):
			ids_now.append(s.id)
	# 新增（apply 后再 emit，让监听者读到的 buff 已生效）
	for id in ids_now:
		if id not in active_ids:
			_apply_synergy(id)
			active_ids.append(id)
			synergy_activated.emit(id)
	# 失效（实战中走不到，留给 reset / 未来 unstack 机制）
	for id in active_ids.duplicate():
		if id not in ids_now:
			_remove_synergy(id)
			active_ids.erase(id)
			synergy_deactivated.emit(id)

# UI 用：返回"差 1 张就能激活"的羁绊列表（商店面板半透明 chip 提示）
func get_potential_synergies() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s in SYNERGIES:
		if s.id in active_ids:
			continue
		var have: int = 0
		for cid in s.cards:
			if UpgradeManager.stack_count(cid) > 0:
				have += 1
		if have == int(s.cards.size()) - 1:  # 差 1
			result.append(s)
	return result

func get_synergy(id: String) -> Dictionary:
	for s in SYNERGIES:
		if s.id == id:
			return s
	return {}

func is_active(id: String) -> bool:
	return id in active_ids

# ========== 内部 ==========

func _has_all(card_ids: Array) -> bool:
	for cid in card_ids:
		if UpgradeManager.stack_count(cid) <= 0:
			return false
	return true

# 应用羁绊效果（写到 wm/player 的 synergy_* 字段，weapon.gd 通过 _buff 读取）
func _apply_synergy(id: String) -> void:
	var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
	var player: Node = get_tree().get_first_node_in_group("player")
	match id:
		"stormpierce":
			if wpm:
				wpm.synergy_crit_bonus += 0.10
				wpm.synergy_crit_stagger = true
		"reaper_dance":
			# v0.4-A：+3 → +1（朋友吐槽生存压力消失，回血主力削弱）
			if wpm:
				wpm.synergy_kill_heal_bonus += 1.0
				wpm.synergy_vampiric_cap_bonus += 1.0
		"pacekeeper":
			if wpm:
				wpm.synergy_pacekeeper = true
		"reaper_whisper":
			if wpm:
				wpm.synergy_reaper_whisper = true
		"mag_artist":
			if wpm:
				wpm.synergy_mag_art = true
		"lightning_war":
			if player:
				player.synergy_slide_speed_bonus += 0.5
				player.synergy_invuln_after_slide += 0.8
		"eternal_warrior":
			# v0.4-A：vampiric_rate_bonus +5% → +2%（嗜血削弱链条配套）
			if wpm:
				wpm.synergy_berserker_threshold_bonus += 0.20
				wpm.synergy_vampiric_rate_bonus += 0.02
		"reaper_realm":
			if wpm:
				wpm.synergy_reaper_realm = true

# 解除（reset 用；实战不会走到，因为卡不会反向 unstack）
func _remove_synergy(id: String) -> void:
	var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
	var player: Node = get_tree().get_first_node_in_group("player")
	match id:
		"stormpierce":
			if wpm:
				wpm.synergy_crit_bonus -= 0.10
				wpm.synergy_crit_stagger = false
		"reaper_dance":
			if wpm:
				wpm.synergy_kill_heal_bonus -= 1.0
				wpm.synergy_vampiric_cap_bonus -= 1.0
		"pacekeeper":
			if wpm:
				wpm.synergy_pacekeeper = false
		"reaper_whisper":
			if wpm:
				wpm.synergy_reaper_whisper = false
		"mag_artist":
			if wpm:
				wpm.synergy_mag_art = false
		"lightning_war":
			if player:
				player.synergy_slide_speed_bonus -= 0.5
				player.synergy_invuln_after_slide -= 0.8
		"eternal_warrior":
			if wpm:
				wpm.synergy_berserker_threshold_bonus -= 0.20
				wpm.synergy_vampiric_rate_bonus -= 0.02
		"reaper_realm":
			if wpm:
				wpm.synergy_reaper_realm = false
