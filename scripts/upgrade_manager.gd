extends Node

# 局内升级系统：autoload 单例，管理卡池 / 已叠层数 / 锁定 / 抽卡 / 应用效果
# 关卡重开（reload_current_scene）时 _ready 会被重新调用、stacks 归零；
# 但因为是 autoload，Node 本身不会销毁，这里显式在场景切换时 reset()

# ========== 稀有度 ==========
enum Rarity { COMMON, RARE, LEGENDARY }

# ========== 商店刷新 ==========
# 每波刷新成本递增（100→200→400→800…），下波重置；防止 currency 溢出时无限刷传说
const REROLL_BASE_COST: int = 100

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
	{"id": "kill_heal", "name": "杀戮回血", "desc": "击杀敌人恢复 3 点生命",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 800},
	{"id": "kill_rage", "name": "杀戮狂热", "desc": "击杀后 3 秒内射速 +30%",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 800},
	# 玩家反馈：原 RARE/可叠 2 层(30%)太强且太好拿，升金色单卡封顶
	{"id": "ammo_save", "name": "弹药节省", "desc": "命中时 25% 概率不消耗弹药",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
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
	# --- v0.3 新稀有 7 张 ---
	{"id": "crit_chance", "name": "穿甲弹", "desc": "命中 15% 概率造成 ×3 伤害",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 800},
	{"id": "weak_spot", "name": "猎手本能", "desc": "击杀同种敌人后对其下次伤害 +50%（最多叠 3 层）",
		"rarity": Rarity.RARE, "max_stack": 1, "base_cost": 900},
	{"id": "reload_burst", "name": "战术换弹", "desc": "换弹后下一发开火 ×3 伤害（每 stack 倍率 +1）",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 800},
	{"id": "last_round", "name": "底牌", "desc": "弹匣最后 1 发伤害 +200%（每 stack +1 发）",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 700},
	{"id": "momentum", "name": "游击战", "desc": "移动中伤害 +10%，静止时 -5%（每 stack 翻倍）",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 800},
	{"id": "dash_combo", "name": "杀戮节拍", "desc": "连击 ≥5 时移速 +15%（每 stack 累加）",
		"rarity": Rarity.RARE, "max_stack": 3, "base_cost": 700},
	{"id": "stagger", "name": "重型压制", "desc": "命中精英/BOSS 25% 概率打断 0.3s（每 stack 概率+25%、持续+0.1s）",
		"rarity": Rarity.RARE, "max_stack": 2, "base_cost": 1000},
	# --- v0.3 新传说 4 张 ---
	{"id": "berserker", "name": "狂战士", "desc": "血量低于 30% 时所有伤害 +60%",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "vampiric", "name": "嗜血", "desc": "造成伤害的 5% 转化为治疗，单次击杀回血上限 2",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "slide_burst", "name": "战术突进", "desc": "滑铲期间无敌 + 滑铲结束后 1.5s 内射速 +40%",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
	{"id": "chain_kill", "name": "连锁处决", "desc": "1 秒内连续击杀 → 该击杀回 5 弹药 + 短暂无敌 0.3s",
		"rarity": Rarity.LEGENDARY, "max_stack": 1, "base_cost": 2500},
]

# ========== 运行时状态 ==========
var stacks: Dictionary = {}       # id -> int 已叠层数
var locked_ids: Array[String] = []  # 当前面板锁定的 id（不参与 reroll）
var current_draw: Array[String] = []  # 当前面板的 3 张 id
var purchased_this_round: Array[String] = []  # 本波已购买的 id，prepare_new_round() 清空
var reroll_count: int = 0  # 本波已刷新次数，prepare_new_round() 归零
# 全局 buff：由 enemy.gd 读取
var drop_chance_bonus: float = 0.0

signal draw_refreshed                 # 抽卡后通知面板刷新 UI
signal card_purchased(id: String)     # 买到一张 → 刷新单张 UI（锁按钮状态、价格）
signal rerolled                       # 商店刷新成功 → 面板更新刷新按钮成本/可点态

# ========== API ==========
# 每次场景重载 / 回主菜单都必须 reset，否则死亡重开会继承上局升级
func reset() -> void:
	stacks.clear()
	locked_ids.clear()
	current_draw.clear()
	purchased_this_round.clear()
	reroll_count = 0
	drop_chance_bonus = 0.0
	# 羁绊：清空 active 并把已加 buff 退回（autoload 不会销毁，跨局必须手动 reset）
	if Engine.has_singleton("SynergyManager") or has_node("/root/SynergyManager"):
		SynergyManager.reset()

# 进入新一波商店前调：清"本波已购"标记 + 重置刷新计数
# 与 draw_cards 解耦，让 reroll 时不会清掉 purchased_this_round（防止刷出已买卡又重买）
func prepare_new_round() -> void:
	purchased_this_round.clear()
	reroll_count = 0

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

# 抽卡：保留锁定的 id 在 *原槽位*，其余从池内重新抽取（wave 越大稀有/传说权重越高）
# 不清 purchased_this_round / reroll_count（那由 prepare_new_round() 管），
# 这样 reroll 复用本函数时不会让"本波已购"卡再次进池被重买
# 锁定槽位保留：reroll 时玩家锁定的中间卡不能"跳到第 1 位"，否则视觉像被换了
func draw_cards(wave: int) -> Array[String]:
	# 清理已叠满的锁定 id（lock 没意义了）
	for id in locked_ids.duplicate():
		if is_maxed(id):
			locked_ids.erase(id)
	# 准备 3 个槽位（"" 表示空待抽）
	var slots: Array[String] = ["", "", ""]
	# 步骤 1：上一轮 current_draw 中"被锁"的，按 *原槽位* 保留
	for i in mini(current_draw.size(), 3):
		var pid: String = current_draw[i]
		if pid in locked_ids:
			slots[i] = pid
	# 步骤 2：剩余空槽从未叠满 && 本波未购 && 已在槽位的卡池里按权重抽
	var pool: Array = []
	for c in CARDS:
		if is_maxed(c.id):
			continue
		if is_purchased_this_round(c.id):
			continue
		if c.id in slots:
			continue
		pool.append(c)
	var weights: Dictionary = _compute_rarity_weights(wave)
	for i in 3:
		if slots[i] != "":
			continue
		if pool.is_empty():
			break
		var picked: Dictionary = _weighted_pick(pool, weights)
		slots[i] = picked.id
		pool.erase(picked)
	# 紧凑化：pool 不足导致的空槽去掉（render 端按 size() 隐藏多余槽位）
	var new_draw: Array[String] = []
	for s in slots:
		if s != "":
			new_draw.append(s)
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

# 当前刷新成本：100 * 2^reroll_count → 100 / 200 / 400 / 800 / 1600 …
func get_reroll_cost() -> int:
	return REROLL_BASE_COST * (1 << reroll_count)

# 卡池是否还有可换出的新卡（pool 空 → 刷新无意义，按钮应禁用）
# 与 draw_cards 的 pool 构造规则保持一致：未叠满 + 本波未购 + 不在当前面板
func can_reroll() -> bool:
	for c in CARDS:
		if is_maxed(c.id):
			continue
		if is_purchased_this_round(c.id):
			continue
		if c.id in current_draw:
			continue
		return true
	return false

# 商店刷新：扣 currency → 复用 draw_cards 重抽 → reroll_count++
# 返回 true=刷新成功；false=钱不够
func try_reroll(wave: int) -> bool:
	var cost: int = get_reroll_cost()
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	if wm == null or int(wm.currency) < cost:
		return false
	wm.currency -= cost
	wm.currency_changed.emit(wm.currency)
	reroll_count += 1
	draw_cards(wave)
	rerolled.emit()
	return true

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
	# 羁绊检查：每次卡牌叠层后扫描，新激活的会发 synergy_activated 给 HUD toast
	if has_node("/root/SynergyManager"):
		SynergyManager.check_active()
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
			# v0.4-A：每 stack +5 → +3，max 3 stack 9/次（原 15/次过高，朋友吐槽生存压力消失）
			if wpm: wpm.kill_heal_amount += 3.0
		"kill_rage":
			if wpm:
				wpm.kill_rage_duration = 3.0
				wpm.kill_rage_fire_rate_bonus += 0.30
		"ammo_save":
			if wpm: wpm.ammo_save_chance += 0.25
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
		# --- v0.3 新稀有 ---
		"crit_chance":
			if wpm: wpm.crit_chance += 0.15
		"weak_spot":
			if wpm: wpm.weak_spot_enabled = true
		"reload_burst":
			# 换弹后首发 ×N 伤害：stack 1 = ×3，stack 2 = ×4
			if wpm:
				wpm.reload_burst_enabled = true
				wpm.reload_burst_damage_mult = 2.0 + float(stack_count("reload_burst"))
		"last_round":
			# stack 数 = 影响"弹匣最后 N 发"
			if wpm: wpm.last_round_count = stack_count("last_round")
		"momentum":
			# stack 1: +10/-5；stack 2: +20/-10
			if wpm:
				var ms: int = stack_count("momentum")
				wpm.momentum_move_bonus = 0.10 * float(ms)
				wpm.momentum_static_penalty = 0.05 * float(ms)
		"dash_combo":
			# 阈值固定 5；每 stack +15% 移速（叠 3 = +45%）
			if player:
				player.combo_speed_threshold = 5
				player.combo_speed_bonus = 0.15 * float(stack_count("dash_combo"))
		"stagger":
			# stack 1: 25%/0.3s; stack 2: 50%/0.4s
			if wpm:
				var st: int = stack_count("stagger")
				wpm.stagger_chance = 0.25 * float(st)
				wpm.stagger_duration = 0.2 + 0.1 * float(st)
		# --- v0.3 新传说 ---
		"berserker":
			if wpm: wpm.berserker_active = true
		"vampiric":
			# v0.4-A：cap 5 → 2（朋友吐槽"根本不缺血"，回血主力削弱；rate 不动）
			if wpm:
				wpm.vampiric_rate = 0.05
				wpm.vampiric_cap_per_kill = 2.0
		"slide_burst":
			if wpm:
				wpm.slide_burst_active = true
				wpm.slide_burst_duration = 1.5
				wpm.slide_burst_fire_rate_bonus = 0.4
			if player: player.slide_burst_enabled = true
		"chain_kill":
			# v0.4-A：回弹 20 → 5（破"永不缺弹"），无敌 0.5 → 0.3（仍能保命，不能"无脑冲怪堆"）
			if wpm:
				wpm.chain_kill_active = true
				wpm.chain_kill_window = 1.0
				wpm.chain_kill_ammo_refund = 5
				wpm.chain_kill_invuln = 0.3

func _grant_max_health(player: Node, delta: float) -> void:
	if player == null:
		return
	player.max_health += delta
	player.current_health = clampf(player.current_health + delta, 0.0, player.max_health)
	player.health_changed.emit(player.current_health, player.max_health)
