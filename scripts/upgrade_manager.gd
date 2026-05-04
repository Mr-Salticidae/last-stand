extends Node

# 局内升级系统：autoload 单例，管理卡池 / 已叠层数 / 锁定 / 抽卡 / 应用效果
# 关卡重开（reload_current_scene）时 _ready 会被重新调用、stacks 归零；
# 但因为是 autoload，Node 本身不会销毁，这里显式在场景切换时 reset()

# ========== 稀有度 ==========
enum Rarity { COMMON, RARE, LEGENDARY }

# ========== 卡池（P0 共 19 张） ==========
# 字段：id / name / desc / rarity / max_stack / base_cost
# 价格 = base_cost * pow(1.4, 已叠层数)
const CARDS: Array[Dictionary] = [
	# --- 普通（9）：基础数值强化 ---
	{"id": "damage", "name": "口径升级", "desc": "武器伤害 +15%",
		"rarity": Rarity.COMMON, "max_stack": 5, "base_cost": 300},
	{"id": "fire_rate", "name": "急促射击", "desc": "射速 +12%",
		"rarity": Rarity.COMMON, "max_stack": 4, "base_cost": 300},
	{"id": "mag_size", "name": "扩容弹匣", "desc": "弹匣容量 +25%",
		"rarity": Rarity.COMMON, "max_stack": 3, "base_cost": 300},
	{"id": "headshot", "name": "头部专精", "desc": "爆头倍率 +0.5",
		"rarity": Rarity.COMMON, "max_stack": 4, "base_cost": 300},
	{"id": "reload", "name": "快速装填", "desc": "装填时间 -25%",
		"rarity": Rarity.COMMON, "max_stack": 3, "base_cost": 300},
	{"id": "spread", "name": "弹道稳定", "desc": "子弹散布 -20%",
		"rarity": Rarity.COMMON, "max_stack": 3, "base_cost": 250},
	{"id": "max_health", "name": "强健体魄", "desc": "最大血量 +20",
		"rarity": Rarity.COMMON, "max_stack": 5, "base_cost": 250},
	{"id": "move_speed", "name": "疾风步伐", "desc": "移速 +8%",
		"rarity": Rarity.COMMON, "max_stack": 4, "base_cost": 250},
	{"id": "heal_boost", "name": "战地医疗", "desc": "血包治疗量 +40%",
		"rarity": Rarity.COMMON, "max_stack": 3, "base_cost": 250},
	# --- 稀有（6） ---
	{"id": "kill_heal", "name": "杀戮回血", "desc": "击杀敌人恢复 5 点生命",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 800},
	{"id": "kill_rage", "name": "杀戮狂热", "desc": "击杀后 3 秒内射速 +30%",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 800},
	{"id": "ammo_save", "name": "弹药节省", "desc": "命中时 15% 概率不消耗弹药",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 800},
	{"id": "drop_boost", "name": "战场拾荒", "desc": "血包掉落率 +30%",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 700},
	{"id": "jump_boost", "name": "鹰跃", "desc": "跳跃力 +15%",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 700},
	{"id": "heavy_rounds", "name": "重型弹药", "desc": "伤害 +30%，射速 -15%",
		"rarity": Rarity.RARE, "max_stack": 1, "base_cost": 1000},
	# --- 传说（4） ---
	{"id": "double_jump", "name": "二段跳", "desc": "空中可再跳一次",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "immortal", "name": "不朽之躯", "desc": "最大血量 +50，血包治疗 ×2",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "elite_hunter", "name": "精英猎手", "desc": "对精英/BOSS 伤害和得分 +50%",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "combo_rage", "name": "战斗狂热", "desc": "连击 ≥10 时伤害 +40%",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
]

# ========== 运行时状态 ==========
var stacks: Dictionary = {}       # id -> int 已叠层数
var locked_ids: Array[String] = []  # 当前面板锁定的 id（不参与 reroll）
var current_draw: Array[String] = []  # 当前面板的 3 张 id
var purchased_this_round: Array[String] = []  # 本波已购买的 id，draw_cards 时清空
# 全局 buff：由 enemy.gd 读取
var drop_chance_bonus: float = 0.0

signal draw_refreshed                 # 抽卡后通知面板刷新 UI
signal card_purchased(id: String)     # 买到一张 → 刷新单张 UI（锁按钮状态、价格）

# ========== API ==========
# 每次场景重载 / 回主菜单都必须 reset，否则死亡重开会继承上局升级
func reset() -> void:
	stacks.clear()
	locked_ids.clear()
	current_draw.clear()
	purchased_this_round.clear()
	drop_chance_bonus = 0.0

func get_card(id: String) -> Dictionary:
	for c in CARDS:
		if c.id == id:
			return c
	return {}

func stack_count(id: String) -> int:
	return int(stacks.get(id, 0))

func is_maxed(id: String) -> bool:
	var c: Dictionary = get_card(id)
	return stack_count(id) >= int(c.max_stack)

func get_cost(id: String) -> int:
	var c: Dictionary = get_card(id)
	var base: int = int(c.base_cost)
	var cost: float = float(base) * pow(1.4, float(stack_count(id)))
	return int(round(cost))

func is_locked(id: String) -> bool:
	return id in locked_ids

# 本波次是否已购买（无论是这张刚抽到的还是之前叠过的）
func is_purchased_this_round(id: String) -> bool:
	return id in purchased_this_round

func toggle_lock(id: String) -> void:
	if id in locked_ids:
		locked_ids.erase(id)
	else:
		locked_ids.append(id)

# 波次结束时调：保留锁定的 id，其余从池内重新抽取
# wave 越大，稀有/传说权重越高
func draw_cards(wave: int) -> Array[String]:
	# 新一波次开始：清空"本波已购买"标记
	purchased_this_round.clear()
	var new_draw: Array[String] = []
	# 保留锁定且未叠满的
	for id in locked_ids.duplicate():
		if is_maxed(id):
			locked_ids.erase(id)
		else:
			new_draw.append(id)
	# 剩余槽位从未叠满 && 不在当前面板的卡池里按权重抽
	var pool: Array = []
	for c in CARDS:
		if is_maxed(c.id):
			continue
		if c.id in new_draw:
			continue
		pool.append(c)
	var weights: Dictionary = _compute_rarity_weights(wave)
	while new_draw.size() < 3 and not pool.is_empty():
		var picked: Dictionary = _weighted_pick(pool, weights)
		new_draw.append(picked.id)
		pool.erase(picked)
	current_draw = new_draw
	draw_refreshed.emit()
	return new_draw

func _compute_rarity_weights(wave: int) -> Dictionary:
	return {
		Rarity.COMMON: 80.0,
		Rarity.RARE: 18.0 + float(wave) * 1.0,
		Rarity.LEGENDARY: 2.0 + float(wave) * 0.5,
	}

func _weighted_pick(pool: Array, rarity_weights: Dictionary) -> Dictionary:
	var total: float = 0.0
	for c in pool:
		total += float(rarity_weights[int(c.rarity)])
	var r: float = randf() * total
	for c in pool:
		r -= float(rarity_weights[int(c.rarity)])
		if r <= 0.0:
			return c
	return pool.back()

# 返回 true=购买成功并已应用效果；false=钱不够 / 已叠满 / 本波已买
func try_purchase(id: String) -> bool:
	if is_maxed(id) or is_purchased_this_round(id):
		return false
	var cost: int = get_cost(id)
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	# 升级只消耗 currency，不动 total_score：结算分数 = 累计获得（含已花掉的）
	if wm == null or int(wm.currency) < cost:
		return false
	wm.currency -= cost
	wm.currency_changed.emit(wm.currency)
	stacks[id] = stack_count(id) + 1
	purchased_this_round.append(id)
	# 买完自动解锁这张（锁定的意义是"没买"保留，买了没必要锁）
	locked_ids.erase(id)
	_apply_effect(id)
	card_purchased.emit(id)
	return true

# ========== 效果应用 ==========
# 武器 buff 上移到 weapon_manager（共享给所有武器，切武器 buff 不丢）
# 玩家 buff 仍写到 player；wave_manager buff 仍写到 wm
func _apply_effect(id: String) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	match id:
		# --- 普通 ---
		"damage":
			if wpm: wpm.damage_mult += 0.15
		"fire_rate":
			# fire_rate 是"冷却秒数"，要让射速 +12% 相当于冷却 * (1/1.12)
			if wpm: wpm.fire_rate_mult *= (1.0 / 1.12)
		"mag_size":
			# 弹匣容量 +25%（线性叠加：1.25 / 1.50 / 1.75）
			if wpm:
				wpm.mag_size_mult += 0.25
				wpm.notify_ammo_recompute()
		"headshot":
			if wpm: wpm.headshot_bonus += 0.5
		"reload":
			if wpm: wpm.reload_time_mult *= (1.0 - 0.25)
		"spread":
			if wpm: wpm.spread_mult *= (1.0 - 0.20)
		"max_health":
			_grant_max_health(player, 20.0)
		"move_speed":
			if player: player.speed_mult += 0.08
		"heal_boost":
			if player: player.heal_mult += 0.40
		# --- 稀有 ---
		"kill_heal":
			if wpm: wpm.kill_heal_amount += 5.0
		"kill_rage":
			if wpm:
				wpm.kill_rage_duration = 3.0
				wpm.kill_rage_fire_rate_bonus += 0.30
		"ammo_save":
			if wpm: wpm.ammo_save_chance += 0.15
		"drop_boost":
			drop_chance_bonus += 0.30
		"jump_boost":
			if player: player.jump_mult += 0.15
		"heavy_rounds":
			if wpm:
				wpm.damage_mult += 0.30
				# 射速 -15% → 冷却 *1/0.85 ≈ *1.176
				wpm.fire_rate_mult *= (1.0 / 0.85)
		# --- 传说 ---
		"double_jump":
			if player: player.max_air_jumps += 1
		"immortal":
			_grant_max_health(player, 50.0)
			if player: player.heal_mult += 1.0
		"elite_hunter":
			if wpm: wpm.elite_damage_bonus += 0.5
			if wm: wm.elite_score_bonus += 0.5
		"combo_rage":
			if wpm:
				wpm.combo_damage_threshold = 10
				wpm.combo_damage_bonus += 0.4

func _grant_max_health(player: Node, delta: float) -> void:
	if player == null:
		return
	player.max_health += delta
	player.current_health = clampf(player.current_health + delta, 0.0, player.max_health)
	player.health_changed.emit(player.current_health, player.max_health)
