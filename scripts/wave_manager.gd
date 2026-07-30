class_name WaveManager extends Node

# 波次生成器：通过 start_next_wave() 外部触发（未来连存档点/机关），杀光自动推进到下一波
# 数量为主：第 N 波 = base + (N-1) * per_wave，capped；每 5 波 max_health 追加 health_scale 倍率

signal wave_started(wave_number: int, enemy_count: int)     # 本波生成开始时发出
signal wave_progress(remaining: int)                         # 本波存活敌人变化时发出
signal wave_completed(wave_number: int)                      # 本波清空时发出
signal intermission_started(wave_number: int, seconds: float) # 进入波间休整时发出
signal kill_count_changed(total_kills: int)                  # 累计击杀数变化（内部/清波判定）
signal score_changed(total_score: int)                       # 累计得分变化（HUD / 存档）
signal currency_changed(amount: int)                         # 可花费资金变化（升级消耗，不影响结算得分）
signal combo_changed(count: int, broken: bool)               # 连击数变化或重置
signal game_completed(wave: int)                             # 通关：到达 victory_wave 且本波清空时发出
signal wave_timer_started(wave_number: int, duration: float) # 无尽模式：本波倒计时开始（classic 永不发）

@export_group("Wave Scaling")
@export var base_enemy_count: int = 4              # 第 1 波敌人数
@export var enemy_count_per_wave: int = 1          # 每后续一波增加的敌人数
@export var max_enemies_per_wave: int = 20         # 敌人数量上限
@export var health_boost_every_n_waves: int = 5    # 每 N 波强化一次血量
@export var health_boost_per_tier: float = 0.35    # 每次强化的血量倍率增量（35%）
# 移速 bonus：每 N 波给 grunt/brute 加 X 移速（不给 runner/elite/boss，他们已经定位为"快"或"强"）
@export var speed_bonus_every_n_waves: int = 3
@export var speed_bonus_per_tier: float = 0.15

@export_group("Timing")
@export var intermission_duration: float = 3.0     # 波间休整秒数
@export var spawn_effect_duration: float = 0.8     # 红烟警示到敌人出现的延迟
@export var spawn_stagger: float = 0.1             # 同波多只敌人之间的错位生成时间

@export_group("Flow")
@export var autostart_first_wave: bool = true      # true=场景启动即开始；false=等外部调 start_next_wave()
@export var auto_continue: bool = true             # true=杀光自动进下一波；false=每波都要外部触发

@export_group("Victory")
# 完成此波次后触发通关结算（emit game_completed），不再推下一波。0=禁用通关，永远无限模式
@export var victory_wave: int = 30

@export_group("Weapon Unlock")
# 波次到达 key 时解锁对应 weapon_id（weapon_manager.unlock_weapon 调用）
# Wave 2 → rifle / Wave 4 → shotgun / Wave 6 → revolver
@export var weapon_unlock_schedule: Dictionary = {
	2: "rifle",
	4: "shotgun",
	6: "revolver",
}

@export_group("Enemy Variants")
@export var enemy_scene: PackedScene               # Grunt（标准型，兼容老字段名）
@export var runner_scene: PackedScene              # Runner（快/脆，黄橙色）
@export var brute_scene: PackedScene               # Brute（慢/肉，深紫色）
@export var elite_scene: PackedScene               # Elite（青蓝发光，每 5 波固定 1 只）
@export var boss_scene: PackedScene                # Boss（金紫发光，每 15 波固定 1 只）
# 波次阈值：从第几波开始解锁该类型
@export var runner_unlock_wave: int = 3
@export var brute_unlock_wave: int = 5
# 混合概率（解锁后才启用，越后期越高）
@export var runner_chance_base: float = 0.20
@export var runner_chance_per_wave: float = 0.03
@export var runner_chance_max: float = 0.55
@export var brute_chance_base: float = 0.10
@export var brute_chance_per_wave: float = 0.02
# 上限必须满足 brute_max + runner_max < 1.0：_pick_enemy_scene 用一次 randf 分区间，
# 两者之和超过 1 时 grunt 拿不到任何区间（后期彻底不再出现，包抄 AI 随之消失），
# 且 runner 会被静默截断到 1.0-brute_max、拿不满自己的 runner_chance_max。
# 0.30 + 0.55 = 0.85 → 后期稳定在 brute 30% / runner 55% / grunt 15%
@export var brute_chance_max: float = 0.30
# 精英 / Boss 波次周期
@export var elite_wave_period: int = 5
@export var boss_wave_period: int = 15

# ============================================================================
# 无尽模式（Settings.is_endless()）：每波不再是"固定 N 只、杀光过波"，而是
# "固定时长倒计时 + 一笔威胁预算按强度曲线持续释放成敌人"，时间到清场进商店。
#
# 为什么用「威胁预算」而不是「每秒刷 N 只」：
#   各敌种战力差着数量级（grunt 100HP / boss 1200HP + 召唤），按只数刷会让
#   出 boss 的那波难度爆炸。改成扣同一笔预算后，boss 吃掉一大半额度 →
#   boss 波场地自动变安静、玩家能专心打 boss。这不是特判，是模型白送的配平。
#
# 所有参数都给了默认值，三张 world_*.tscn 无需任何改动即生效。
# ============================================================================
@export_group("Endless")
# ---- 时长轴：第 1 波 20s，每波 +2s，封顶 60s（第 21 波撞顶）----
@export var endless_wave_duration_base: float = 20.0
@export var endless_wave_duration_per_wave: float = 2.0
@export var endless_wave_duration_max: float = 60.0
# ---- 预算轴（威胁点）：8 + 4(W-1) + 0.30(W-1)²，封顶 600 ----
# 第 37 波撞顶是故意的：此后敌人"数量"停止增长，难度交给 HP/移速 tier 与构成升级承担。
@export var endless_budget_base: float = 8.0
@export var endless_budget_per_wave: float = 4.0
@export var endless_budget_quad: float = 0.30
@export var endless_budget_max: float = 600.0
@export var endless_budget_carry_max: float = 12.0   # 未花费额度的攒存上限，防波末瞬间倾泻
# ---- 并发轴（性能硬闸门）----
@export var endless_concurrent_base: int = 10
@export var endless_concurrent_per_wave: float = 0.8
# 绝对上限：任何难度倍率之后都 clamp 到它。40 是当前 enemy.gd 不重构的安全区下沿，
# 再往上要先给 _apply_enemy_separation 做空间网格。
@export var endless_concurrent_hard_cap: int = 40
@export var endless_concurrent_min: int = 8
# ---- 节奏轴：组间隔从 1.6s 递减到 0.35s，每组只数从 1 涨到 5 ----
# 手感上从"一只只慢慢渗"到"五只一波往里灌"的质变全靠这两条曲线，不靠堆数值。
@export var endless_spawn_interval_base: float = 1.6
@export var endless_spawn_interval_per_wave: float = 0.05
@export var endless_spawn_interval_min: float = 0.35
@export var endless_batch_every_n_waves: int = 6
@export var endless_batch_max: int = 5
# ---- 威胁权重（配平主旋钮）----
@export var threat_cost_grunt: float = 1.0
@export var threat_cost_runner: float = 1.2
@export var threat_cost_brute: float = 3.2
@export var threat_cost_elite: float = 7.0
@export var threat_cost_boss: float = 22.0
# ---- elite / boss 排期：不随机，按波内固定时刻投放 ----
@export var endless_elite_start_wave: int = 3
@export var endless_elite_every_n_waves: int = 4
@export var endless_elite_count_max: int = 5
@export var endless_boss_start_wave: int = 6
@export var endless_boss_period: int = 6
@export var endless_boss_spawn_u: float = 0.12       # boss 在波内 12% 处出场，留 88% 时间给玩家打
# ---- 收场 ----
@export var endless_partial_credit: bool = true      # 清场按已造成伤害比例结算得分/货币
@export var endless_despawn_fade: float = 0.35
# ---- 高波次 clamp（仅无尽，classic 不受影响）----
# 不 clamp 的话 W100 的 grunt 移速 9.3m/s 已超玩家冲刺 8.0，变成"必被贴脸"而不是"难"
@export var endless_health_tier_max: int = 14
@export var endless_speed_tier_max: int = 8
@export var endless_ammo_refill_interval: float = 25.0   # 波内定时半量补备弹（60s 的波打不完一个基数）

enum State { IDLE, INTERMISSION, SPAWNING, COMBAT }

var current_wave: int = 0
var total_kills: int = 0
var total_score: int = 0
# 货币获取率：currency 每杀 = score × 此值。<1 制造稀缺、逼出 build 取舍
# （玩家反馈：经济溢出、不用 build 随意购买；极限档 count_mult 1.8 放大了溢出）
@export var currency_earn_rate: float = 0.7
# 可花费资金：按 currency_earn_rate 折算获得，但升级消耗只扣这里，不影响结算得分
var currency: int = 0
var current_combo: int = 0
# 精英猎手：elite/boss 击杀得分额外加成（UpgradeManager 改写）
var elite_score_bonus: float = 0.0
var max_combo: int = 0
var _combo_timer: float = 0.0
const COMBO_WINDOW: float = 2.5  # N 秒内击杀延续连击，超时重置
# 本波清空后延迟显示升级面板，让最后一只怪倒地动画播完再切 UI（_play_death_sequence
# 总长 1.4s，0.6s 倒地后留 0.4s 缓冲，否则升级面板弹得太突兀）
const WAVE_END_DELAY: float = 1.0
var _run_start_time_msec: int = 0
var _state: State = State.IDLE
var _intermission_timer: float = 0.0
var _spawn_points: Array = []
var _alive_enemies: Array = []
# 生成阶段 _alive_enemies.size() 的语义是"已落地数"而不是"剩余数"——每只敌人要等完
# 自己的生成烟才 append，所以直接拿它发 wave_progress 会让 HUD 的"剩 N 只"从 1 往上爬。
# 剩余数改由 总数 - 已击杀 推导，全程语义一致。
var _wave_total: int = 0        # 本波计划敌人总数（boss 召唤会追加）
var _wave_killed: int = 0       # 本波已击杀数（含异常消失的补偿）
# 仍在播生成烟、尚未落地的敌人数。_spawn_at 是协程但不被 await，循环只等 spawn_stagger
# 就置 COMBAT，此时最后几只还没出现——不挡住清波判定的话，玩家清光已落地的敌人就会
# 提前通关，剩下的敌人生成到下一波里。
var _spawns_pending: int = 0

# ---------- 无尽模式运行时状态 ----------
var _endless: bool = false        # _ready 里从 Settings 读一次，全程不变
var wave_duration: float = 0.0    # 对外只读：本波总时长（HUD 用）
var wave_time_left: float = 0.0   # 对外只读：本波剩余秒数（HUD 每帧读这个权威值，不自己 -= delta）
# 波代数。每次开波/收波自增；在途的生成协程 await 恢复后校验它。
# 头号防坑机制：_spawn_at 系列是协程且调用方不 await，原本只检查 is_inside_tree()
# （只覆盖"WaveManager 被销毁"），不挡"本波已结束"——不加 epoch 的症状是
# 升级面板已经弹出后，还从红烟里凭空冒出敌人。
var _wave_epoch: int = 0
var _wave_budget: float = 0.0     # 本波总威胁预算
var _budget_pool: float = 0.0     # 已释放、尚未花掉的额度
var _intensity_norm: float = 1.0  # 强度曲线的积分归一化常数（开波时数值积分算一次）
var _spawn_cooldown: float = 0.0
var _pending_specials: Array = [] # [{u: float, scene: PackedScene, cost: float}]，按 u 升序
var _ammo_refill_timer: float = 0.0
var _wave_health_mult: float = 1.0
var _sp_deck: Array = []          # spawn 点洗牌牌堆（无尽模式跨波持续取用）
var _sp_idx: int = 0
# 玩家已阵亡 → 整个波次泵停摆。
# 标准模式对此天然免疫：过波条件是"杀光"，死人杀不了怪，波永远清不掉、面板永远不弹。
# 无尽模式把过波条件换成了纯计时器，这道白送的保护就没了——不显式停摆的话，倒计时会在
# 尸体上走完，升级面板（layer 20）盖住死亡结算页（layer 10），关闭时还会把鼠标重新
# capture 掉，结算页的"重生 / 返回主菜单"从此点不到，而且每过一个波长再弹一次。
var _run_over: bool = false

func _ready() -> void:
	add_to_group("wave_manager")
	_endless = Settings.is_endless()
	# 无尽模式没有"通关"：无条件覆写（而不是"仅当为默认值才改"，避免将来某张
	# tscn override 了 victory_wave 时打架）。victory_wave=0 后 _check 里的通关
	# 分流自动失效，death_screen 的胜利路径在无尽下永不触发。
	if _endless:
		victory_wave = 0
	_run_start_time_msec = Time.get_ticks_msec()
	# 自动收集场景里的所有 SpawnPoint
	_spawn_points = get_tree().get_nodes_in_group("spawn_point")
	if _spawn_points.is_empty():
		push_warning("WaveManager: 未找到任何 spawn_point，波次无法生成")
	if enemy_scene == null:
		push_warning("WaveManager: enemy_scene 未配置，请在 Inspector 拖拽 enemy.tscn")

	# 玩家阵亡 → 波次泵停摆（见 _run_over 注释）
	var pl: Node = get_tree().get_first_node_in_group("player")
	if pl and pl.has_signal("died"):
		pl.died.connect(_on_player_died)

	if autostart_first_wave:
		start_next_wave()

# ---------- 外部 API ----------
# 存档点 / 机关 / 调试按键都走这个接口
func start_next_wave() -> void:
	# 只有 IDLE（初始/上一波清光）才接受新启动，防止重复触发
	if _state != State.IDLE:
		return
	current_wave += 1
	# 解锁该波次对应的武器（解锁后 weapon_manager 发 weapon_unlocked 信号给 HUD 提示）
	if weapon_unlock_schedule.has(current_wave):
		var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
		if wpm and wpm.has_method("unlock_weapon"):
			wpm.unlock_weapon(weapon_unlock_schedule[current_wave])
	# 备弹补满（intermission 一开始就把所有解锁武器的备弹打满，给玩家踏实感）
	var wpm2: Node = get_tree().get_first_node_in_group("weapon_manager")
	if wpm2 and wpm2.has_method("refill_all_reserves"):
		wpm2.refill_all_reserves()
	_state = State.INTERMISSION
	# 难度系数：极限突破缩短停顿增压迫，新兵报到延长停顿给反应时间
	var inter_mult: float = float(Settings.get_difficulty_param("intermission_mult", 1.0))
	_intermission_timer = intermission_duration * inter_mult
	intermission_started.emit(current_wave, _intermission_timer)

func _on_player_died() -> void:
	_run_over = true
	_state = State.IDLE
	_wave_epoch += 1        # 作废所有在途生成协程
	_spawns_pending = 0
	wave_time_left = 0.0
	_pending_specials.clear()

# 玩家重生时调用（死亡后 reload_current_scene 会销毁这个节点，但保留接口以备不拼 reload 的流程用）
func reset() -> void:
	_run_over = false
	current_wave = 0
	total_kills = 0
	total_score = 0
	currency = 0
	_state = State.IDLE
	_wave_total = 0
	_wave_killed = 0
	_spawns_pending = 0
	# 作废所有在途生成协程（epoch 一变，它们 await 恢复后自行退出）
	_wave_epoch += 1
	wave_duration = 0.0
	wave_time_left = 0.0
	_budget_pool = 0.0
	_pending_specials.clear()
	for e in _alive_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_alive_enemies.clear()

# 本波剩余敌人数 = 计划总数 - 已击杀。生成阶段也成立（未落地的仍计入剩余）
func _remaining() -> int:
	return maxi(_wave_total - _wave_killed, 0)

# ---------- 内部循环 ----------
func _process(delta: float) -> void:
	# 玩家已阵亡：停止一切推进（倒计时 / 刷怪 / 清波判定 / 连击衰减）
	if _run_over:
		return
	if _state == State.INTERMISSION:
		_intermission_timer -= delta
		if _intermission_timer <= 0.0:
			_spawn_current_wave()
	# Combo 超时衰减
	if current_combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			current_combo = 0
			combo_changed.emit(0, true)
	# 兜底：清理已 free 的敌人引用（防 fall_death_y / 异常 free 等漏发 died 信号路径），
	# 防止 _alive_enemies 残留 invalid 引用导致 is_empty 永远 false → 幽灵怪 progression blocker
	# 无尽模式下这个 filter 同样必须跑：并发闸门按 _alive_enemies.size() 算，
	# 残留 invalid 引用会让并发计数越算越满，最后彻底停止刷怪。
	if _state == State.COMBAT and not _alive_enemies.is_empty():
		var prev_size: int = _alive_enemies.size()
		_alive_enemies = _alive_enemies.filter(func(e): return is_instance_valid(e))
		if _alive_enemies.size() < prev_size and not _endless:
			# 这些敌人没走 died 信号，_wave_killed 不会自增；这里补上，
			# 否则"剩 N 只"会永远停在一个不为 0 的数
			_wave_killed += prev_size - _alive_enemies.size()
			wave_progress.emit(_remaining())
			_check_wave_cleared()

	# 无尽模式：波内倒计时 + 预算释放 + 刷怪泵
	if _endless and _state == State.COMBAT:
		_endless_tick(delta)

func _spawn_current_wave() -> void:
	if _spawn_points.is_empty() or enemy_scene == null:
		push_error("WaveManager: 缺少生成点或 grunt 敌人场景，跳过本波")
		_state = State.IDLE
		return

	# 无尽模式走完全独立的一套：定时 + 预算刷怪。以下 classic 的原始函数体一字不动。
	if _endless:
		_begin_endless_wave()
		return

	_state = State.SPAWNING

	# 数量：base + per_wave 增量后乘难度 count_mult，再 cap 到 max_enemies_per_wave
	var count_mult: float = float(Settings.get_difficulty_param("enemy_count_mult", 1.0))
	var count_raw: float = float(base_enemy_count + (current_wave - 1) * enemy_count_per_wave) * count_mult
	var count: int = min(int(round(count_raw)), max_enemies_per_wave)
	_wave_total = count
	_wave_killed = 0
	_spawns_pending = 0
	# v0.4-A：极限档可 override 节奏；其他档位用 @export 默认值（5 / 0.35）
	var hb_every: int = int(Settings.get_difficulty_param("health_boost_every_n_waves_override", health_boost_every_n_waves))
	var hb_per: float = float(Settings.get_difficulty_param("health_boost_per_tier_override", health_boost_per_tier))
	var health_tier: int = (current_wave - 1) / maxi(hb_every, 1)
	var health_mult: float = 1.0 + float(health_tier) * hb_per

	wave_started.emit(current_wave, count)
	AudioManager.play_wave_start()

	# Boss / Elite 周期：极限突破压缩周期（boss 每 10 波 / elite 每 3 波）
	var actual_boss_period: int = int(Settings.get_difficulty_param("boss_wave_period", boss_wave_period))
	var actual_elite_period: int = int(Settings.get_difficulty_param("elite_wave_period", elite_wave_period))
	var is_boss_wave: bool = boss_scene and current_wave > 0 and current_wave % actual_boss_period == 0
	var is_elite_wave: bool = (
		elite_scene and current_wave > 0
		and current_wave % actual_elite_period == 0
		and not is_boss_wave
	)

	# Spawn 点去重抽取：每轮洗牌后顺序取用，取完一轮再重新洗牌
	# 保证 6 只以内的波次每只从不同 spawn 点出，强化"四面八方"
	var sp_shuffled: Array = _spawn_points.duplicate()
	sp_shuffled.shuffle()
	var sp_idx: int = 0

	for i in count:
		var sp: SpawnPoint = sp_shuffled[sp_idx]
		sp_idx += 1
		if sp_idx >= sp_shuffled.size():
			sp_shuffled.shuffle()
			sp_idx = 0
		# 第一只生成精英 / boss，其他按常规随机
		_spawns_pending += 1
		if i == 0 and is_boss_wave:
			_spawn_at(sp, health_mult, boss_scene)
		elif i == 0 and is_elite_wave:
			_spawn_at(sp, health_mult, elite_scene)
		else:
			_spawn_at(sp, health_mult)
		if spawn_stagger > 0.0 and i < count - 1:
			await get_tree().create_timer(spawn_stagger).timeout
			# stagger 期间 _state 还是 SPAWNING；_process 的 INTERMISSION 分支不会干扰

	_state = State.COMBAT
	wave_progress.emit(_remaining())

# 每只敌人独立 await 自己的 spawn_effect，互相不阻塞
# forced_scene 指定时用该 scene（精英/boss 固定生成），否则按随机混合
func _spawn_at(sp: SpawnPoint, health_mult: float, forced_scene: PackedScene = null) -> void:
	var smoke_dur: float = spawn_effect_duration * (1.6 if forced_scene else 1.0)
	await sp.play_smoke_effect(smoke_dur)
	if not is_inside_tree():
		# WaveManager 被销毁（场景重载等）。这只不会落地，从本波总数里剔除，
		# 否则"剩 N 只"会永远多算一只、清波判定也永远等不到它
		_wave_total -= 1
		_spawns_pending -= 1
		return

	var scene_to_spawn: PackedScene = forced_scene if forced_scene else _pick_enemy_scene()
	var enemy: Enemy = scene_to_spawn.instantiate() as Enemy
	if enemy == null:
		# 实例化失败 / 场景根不是 Enemy：同样要还回名额，不然本波永远清不掉
		push_error("WaveManager: 敌人场景实例化失败，跳过这只")
		_wave_total -= 1
		_spawns_pending -= 1
		_check_wave_cleared()
		return
	# 难度系数：health 在波次 health_mult 之上再乘 difficulty health_mult
	var diff_health_mult: float = float(Settings.get_difficulty_param("enemy_health_mult", 1.0))
	enemy.max_health *= health_mult * diff_health_mult
	# 移速 bonus：仅给 grunt 和 brute（runner/elite/boss 已经定位清晰，不再加成），
	# 然后整体乘 difficulty speed_mult（极限突破 1.4 让 runner 超玩家步行）
	# grunt/brute 在此之上再额外乘 slow_enemy_speed_mult（极限突破 1.4 让慢敌也有压迫）
	var is_slow_enemy: bool = (scene_to_spawn == enemy_scene or scene_to_spawn == brute_scene)
	# v0.4-A：极限档 override speed_bonus 周期（默认 3，极限档 2）
	var sb_every: int = int(Settings.get_difficulty_param("speed_bonus_every_n_waves_override", speed_bonus_every_n_waves))
	if is_slow_enemy:
		var speed_tier: int = current_wave / maxi(sb_every, 1)
		enemy.move_speed += float(speed_tier) * speed_bonus_per_tier
	enemy.move_speed *= float(Settings.get_difficulty_param("enemy_speed_mult", 1.0))
	if is_slow_enemy:
		enemy.move_speed *= float(Settings.get_difficulty_param("slow_enemy_speed_mult", 1.0))
	# v0.4-A：新机制 - 敌人 attack_damage 随波次 tier 增长（仅极限档启用，dmg_every 默认 9999=禁用）
	# 与 enemy.gd:773 的 enemy_damage_mult 乘法叠加（base × wave_tier × difficulty_mult）
	var dmg_every: int = int(Settings.get_difficulty_param("damage_boost_every_n_waves", 9999))
	var dmg_per: float = float(Settings.get_difficulty_param("damage_boost_per_tier", 0.0))
	if dmg_every > 0 and dmg_per > 0.0:
		var dmg_tier: int = (current_wave - 1) / dmg_every
		enemy.attack_damage *= 1.0 + float(dmg_tier) * dmg_per
	# v0.4-B 方案1：极限档非 boss 敌人 attack_range +bonus（让 B1 包抄真的能打到溜怪的玩家）
	# Boss 已有自己的 range（2.5m），不动；其他敌人 1.6 → 2.0
	var range_bonus: float = float(Settings.get_difficulty_param("attack_range_bonus", 0.0))
	if range_bonus > 0.0 and not enemy.is_boss:
		enemy.attack_range += range_bonus
	# 设 transform 放在 add_child 前，保证 _ready 里读 global_transform 时就是 SpawnPoint 的姿态
	# （enemy._ready 会记录 _initial_forward = -global_transform.basis.z）
	enemy.transform = sp.global_transform
	get_tree().current_scene.add_child(enemy)
	# 生成即 aggro：波次敌人不等视野确认，直接朝玩家冲
	# 否则大场地 SpawnPoint 距玩家 > sight_range(15) 时敌人会原地傻站
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		enemy._receive_alert(player.global_position)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_alive_enemies.append(enemy)
	# 落地不改变"剩余数"（未落地的本来就计入剩余），所以这里不再 emit wave_progress
	_spawns_pending -= 1

# 按当前波次选敌人类型。runner 从 runner_unlock_wave 波起解锁，brute 从 brute_unlock_wave 波起解锁；
# 解锁后每波 chance 轻微递增直到 cap。
func _pick_enemy_scene() -> PackedScene:
	var runner_chance: float = 0.0
	var brute_chance: float = 0.0
	# 难度可提前 runner/brute 解锁波次（极限突破：runner 第 1 波 / brute 第 3 波）
	var actual_runner_unlock: int = int(Settings.get_difficulty_param("runner_unlock_wave", runner_unlock_wave))
	var actual_brute_unlock: int = int(Settings.get_difficulty_param("brute_unlock_wave", brute_unlock_wave))
	if runner_scene and current_wave >= actual_runner_unlock:
		runner_chance = minf(
			runner_chance_base + float(current_wave - actual_runner_unlock) * runner_chance_per_wave,
			runner_chance_max
		)
	if brute_scene and current_wave >= actual_brute_unlock:
		brute_chance = minf(
			brute_chance_base + float(current_wave - actual_brute_unlock) * brute_chance_per_wave,
			brute_chance_max
		)
	var r: float = randf()
	# 先判 brute（更稀有但更关键）再判 runner
	if brute_chance > 0.0 and r < brute_chance:
		return brute_scene
	if runner_chance > 0.0 and r < brute_chance + runner_chance:
		return runner_scene
	return enemy_scene

# ============================================================================
# 无尽模式实现
# ============================================================================

# 对外只读：当前存活敌人数（HUD 用）
func alive_enemy_count() -> int:
	return _alive_enemies.size()

# 本波时长 = (base + per*(W-1)，封顶 max) × 难度倍率
func _endless_duration_for(w: int) -> float:
	var mult: float = float(Settings.get_difficulty_param("endless_duration_mult", 1.0))
	var raw: float = endless_wave_duration_base + endless_wave_duration_per_wave * float(w - 1)
	return maxf(minf(raw, endless_wave_duration_max) * mult, 5.0)

# 本波威胁预算 = (base + per*(W-1) + quad*(W-1)²，封顶 max) × 难度倍率
func _endless_budget_for(w: int) -> float:
	var mult: float = float(Settings.get_difficulty_param("endless_budget_mult", 1.0))
	var k: float = float(w - 1)
	var raw: float = endless_budget_base + endless_budget_per_wave * k + endless_budget_quad * k * k
	return minf(raw, endless_budget_max) * mult

# 同屏并发上限：性能硬闸门，也是"打不动就会被围死"这个失败反馈的来源
func _endless_concurrent_cap(w: int) -> int:
	var mult: float = float(Settings.get_difficulty_param("endless_concurrent_mult", 1.0))
	var raw: float = (float(endless_concurrent_base) + endless_concurrent_per_wave * float(w - 1)) * mult
	return clampi(int(raw), endless_concurrent_min, endless_concurrent_hard_cap)

func _endless_spawn_interval(w: int) -> float:
	return maxf(
		endless_spawn_interval_base - endless_spawn_interval_per_wave * float(w - 1),
		endless_spawn_interval_min
	)

func _endless_batch_size(w: int) -> int:
	return clampi(1 + (w - 1) / maxi(endless_batch_every_n_waves, 1), 1, maxi(endless_batch_max, 1))

# 波内强度曲线（u = 已过时间比例）：前松 — 稳压 — 波末小高潮
# 开波 15% 给玩家站位换弹，最后 20% 压力抬到 1.9 倍制造"撑住最后十秒"
func _intensity(u: float) -> float:
	if u < 0.15:
		return lerpf(0.55, 1.0, u / 0.15)
	if u < 0.80:
		return lerpf(1.0, 1.25, (u - 0.15) / 0.65)
	return lerpf(1.25, 1.90, clampf((u - 0.80) / 0.20, 0.0, 1.0))

# 强度曲线的均值（64 点数值积分）。用积分而不是写死常数，是为了曲线被调参后
# 释放速率自动跟随——否则改了曲线会静默变成"预算发不完"或"提前发光"。
func _compute_intensity_norm() -> float:
	const SAMPLES: int = 64
	var acc: float = 0.0
	for i in SAMPLES:
		acc += _intensity((float(i) + 0.5) / float(SAMPLES))
	return maxf(acc / float(SAMPLES), 0.001)

func _threat_cost_for(scene: PackedScene) -> float:
	if boss_scene != null and scene == boss_scene:
		return threat_cost_boss
	if elite_scene != null and scene == elite_scene:
		return threat_cost_elite
	if brute_scene != null and scene == brute_scene:
		return threat_cost_brute
	if runner_scene != null and scene == runner_scene:
		return threat_cost_runner
	return threat_cost_grunt

# Spawn 点去重抽取：洗一轮牌顺序取用，取完再重洗。避免连续几只从同一个点冒出来。
func _next_spawn_point() -> SpawnPoint:
	if _spawn_points.is_empty():
		return null
	if _sp_deck.is_empty() or _sp_idx >= _sp_deck.size():
		_sp_deck = _spawn_points.duplicate()
		_sp_deck.shuffle()
		_sp_idx = 0
	var sp: SpawnPoint = _sp_deck[_sp_idx] as SpawnPoint
	_sp_idx += 1
	return sp

func _begin_endless_wave() -> void:
	_wave_epoch += 1
	var w: int = current_wave
	wave_duration = _endless_duration_for(w)
	wave_time_left = wave_duration
	_wave_budget = _endless_budget_for(w)
	_intensity_norm = _compute_intensity_norm()
	_budget_pool = 0.0
	_spawn_cooldown = 0.0
	_spawns_pending = 0
	_ammo_refill_timer = endless_ammo_refill_interval
	# 这两个是 classic 的计数器，无尽模式全程不用；归零只为不让残值污染调试输出
	_wave_total = 0
	_wave_killed = 0
	# 血量 tier 与 classic 同公式，但 tier 有上限（否则百波后敌人 HP 线性膨胀、
	# 而玩家伤害走 √W，必然撞死墙）
	var hb_every: int = int(Settings.get_difficulty_param("health_boost_every_n_waves_override", health_boost_every_n_waves))
	var hb_per: float = float(Settings.get_difficulty_param("health_boost_per_tier_override", health_boost_per_tier))
	var health_tier: int = mini((w - 1) / maxi(hb_every, 1), endless_health_tier_max)
	_wave_health_mult = 1.0 + float(health_tier) * hb_per
	_build_pending_specials(w)

	_state = State.COMBAT
	# enemy_count 传 0：无尽没有"计划总数"。签名保持不变是刻意的——HUD 是按
	# 参数个数直连的，改签名会在运行时静默断连。HUD 靠自己的 _endless 标志忽略它。
	wave_started.emit(w, 0)
	wave_timer_started.emit(w, wave_duration)
	AudioManager.play_wave_start()

# elite / boss 不参与随机，按波内固定时刻预定投放，并从同一笔预算里预先扣费。
# 于是 boss 波的 ambient 刷怪会自动变稀疏，玩家能专心打 boss——这不是特判，
# 是威胁预算模型白送的配平。
func _build_pending_specials(w: int) -> void:
	_pending_specials.clear()
	var boss_start: int = int(Settings.get_difficulty_param("endless_boss_start_override", endless_boss_start_wave))
	var boss_period: int = maxi(int(Settings.get_difficulty_param("endless_boss_period_override", endless_boss_period)), 1)
	var is_boss_wave: bool = boss_scene != null and w >= boss_start and (w - boss_start) % boss_period == 0
	if is_boss_wave:
		var boss_count: int = clampi(1 + (w - boss_start) / 18, 1, 3)
		for i in boss_count:
			_pending_specials.append({
				"u": clampf(endless_boss_spawn_u + 0.06 * float(i), 0.0, 0.9),
				"scene": boss_scene,
				"cost": threat_cost_boss,
			})
	if elite_scene != null and w >= endless_elite_start_wave:
		var count: int = clampi(
			1 + (w - endless_elite_start_wave) / maxi(endless_elite_every_n_waves, 1),
			1, maxi(endless_elite_count_max, 1)
		)
		count += int(Settings.get_difficulty_param("endless_elite_bonus", 0))
		if is_boss_wave:
			count = count / 2   # boss 波精英减半，别让两种压力叠在一起
		for k in count:
			_pending_specials.append({
				"u": float(k + 1) / float(count + 1),
				"scene": elite_scene,
				"cost": threat_cost_elite,
			})
	_pending_specials.sort_custom(func(a, b): return float(a["u"]) < float(b["u"]))
	# 预定的特殊敌人先把预算扣掉，剩下的才是 ambient 额度
	for s in _pending_specials:
		_wave_budget -= float(s["cost"])
	_wave_budget = maxf(_wave_budget, 0.0)

func _endless_tick(delta: float) -> void:
	if wave_time_left <= 0.0:
		return
	wave_time_left -= delta
	if wave_time_left <= 0.0:
		wave_time_left = 0.0
		_end_endless_wave()
		return

	var u: float = clampf(1.0 - wave_time_left / maxf(wave_duration, 0.001), 0.0, 1.0)
	var cap: int = _endless_concurrent_cap(current_wave)
	var in_play: int = _alive_enemies.size() + _spawns_pending

	# 1) 投放到期的 elite / boss。
	#    **不再扣 _budget_pool**：它们的费用已经在 _build_pending_specials 里从
	#    _wave_budget 预扣过了（那正是"boss 波 ambient 自动变稀疏"的实现方式）。
	#    这里再扣一次等于双重计费，实测会让出精英的波少刷近一半的怪。
	#    唯一的门槛是并发闸门。
	while not _pending_specials.is_empty():
		var head: Dictionary = _pending_specials[0]
		if u < float(head["u"]) or in_play >= cap:
			break
		_pending_specials.pop_front()
		_spawns_pending += 1
		in_play += 1
		_spawn_endless_at(_next_spawn_point(), head["scene"] as PackedScene)

	# 2) 按强度曲线释放额度。carry_max 封住攒存，防止玩家清得太快导致波末瞬间倾泻。
	_budget_pool += (_wave_budget / maxf(wave_duration, 0.001)) * (_intensity(u) / _intensity_norm) * delta
	_budget_pool = minf(_budget_pool, endless_budget_carry_max)

	# 3) 刷怪泵
	_spawn_cooldown -= delta
	if _spawn_cooldown <= 0.0:
		_spawn_cooldown = 0.0
		if in_play < cap:
			var spawned: int = 0
			for i in _endless_batch_size(current_wave):
				if in_play >= cap:
					break
				var scene: PackedScene = _pick_enemy_scene()
				var cost: float = _threat_cost_for(scene)
				if cost > _budget_pool:
					# 买不起就**等**，不要降级成 grunt。
					# 稳态下每个 interval 只释放 1~3 威胁点，而 brute 要 3.2——
					# 一降级就等于把额度立刻花在便宜单位上，池子永远攒不到 brute 的价，
					# 结果是中期 brute 被静默清零、混合比例完全跑偏。
					# 这里 break 之后 pool 继续累积（上限 carry_max），下一拍就买得起了。
					break
				_budget_pool -= cost
				_spawns_pending += 1
				in_play += 1
				spawned += 1
				_spawn_endless_at(_next_spawn_point(), scene)
			# 额度不够时小步重试，别每帧空转抽 scene
			_spawn_cooldown = _endless_spawn_interval(current_wave) if spawned > 0 else 0.25

	# 4) 波内定时半量补备弹：60 秒的波打不完一个弹药基数，
	#    而 refill_all_reserves 只在每波开头调一次
	_ammo_refill_timer -= delta
	if _ammo_refill_timer <= 0.0:
		_ammo_refill_timer = endless_ammo_refill_interval
		var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
		if wpm and wpm.has_method("refill_partial"):
			wpm.refill_partial(0.5)

# 无尽模式的单只生成。相对 classic 的 _spawn_at 有三处关键差异：
#   ① 进函数先记 epoch，await 红烟后校验——本波已结束就直接退出。
#      原版只检查 is_inside_tree()（只覆盖"WaveManager 被销毁"），照抄必漏，
#      症状是升级面板已经弹出后还从红烟里凭空冒出敌人。
#   ② health / speed tier 有上限，防百波后数值失控
#   ③ 完全不碰 _wave_total / _wave_killed
func _spawn_endless_at(sp: SpawnPoint, scene_to_spawn: PackedScene) -> void:
	var my_epoch: int = _wave_epoch
	if sp == null or scene_to_spawn == null:
		_spawns_pending = maxi(_spawns_pending - 1, 0)
		return
	var is_special: bool = (
		(boss_scene != null and scene_to_spawn == boss_scene)
		or (elite_scene != null and scene_to_spawn == elite_scene)
	)
	# allow_skip 只对普通敌人开：elite/boss 的加长预警是玩家唯一的"大家伙要来了"提示，
	# 任何情况下都不能被冷却吞掉
	await sp.play_smoke_effect(spawn_effect_duration * (1.6 if is_special else 1.0), not is_special)
	if my_epoch != _wave_epoch or not is_inside_tree():
		# 本波已结束或 WaveManager 已销毁。所有 epoch 自增点都同时把
		# _spawns_pending 清零了，这里不再回退，避免减成负数。
		return

	var enemy: Enemy = scene_to_spawn.instantiate() as Enemy
	if enemy == null:
		push_error("WaveManager: 敌人场景实例化失败，跳过这只")
		_spawns_pending = maxi(_spawns_pending - 1, 0)
		return

	var diff_health_mult: float = float(Settings.get_difficulty_param("enemy_health_mult", 1.0))
	enemy.max_health *= _wave_health_mult * diff_health_mult
	var is_slow_enemy: bool = (scene_to_spawn == enemy_scene or scene_to_spawn == brute_scene)
	var sb_every: int = int(Settings.get_difficulty_param("speed_bonus_every_n_waves_override", speed_bonus_every_n_waves))
	if is_slow_enemy:
		var speed_tier: int = mini(current_wave / maxi(sb_every, 1), endless_speed_tier_max)
		enemy.move_speed += float(speed_tier) * speed_bonus_per_tier
	enemy.move_speed *= float(Settings.get_difficulty_param("enemy_speed_mult", 1.0))
	if is_slow_enemy:
		enemy.move_speed *= float(Settings.get_difficulty_param("slow_enemy_speed_mult", 1.0))
	var dmg_every: int = int(Settings.get_difficulty_param("damage_boost_every_n_waves", 9999))
	var dmg_per: float = float(Settings.get_difficulty_param("damage_boost_per_tier", 0.0))
	if dmg_every > 0 and dmg_per > 0.0:
		var dmg_tier: int = mini((current_wave - 1) / dmg_every, endless_health_tier_max)
		enemy.attack_damage *= 1.0 + float(dmg_tier) * dmg_per
	var range_bonus: float = float(Settings.get_difficulty_param("attack_range_bonus", 0.0))
	if range_bonus > 0.0 and not enemy.is_boss:
		enemy.attack_range += range_bonus

	enemy.transform = sp.global_transform
	get_tree().current_scene.add_child(enemy)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player:
		enemy._receive_alert(player.global_position)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_alive_enemies.append(enemy)
	_spawns_pending = maxi(_spawns_pending - 1, 0)

# 倒计时归零：立刻停刷 → 淡出清场 → 按已造成伤害比例结算 → 接回原有的
# wave_completed → 升级面板 → start_next_wave 链路。
#
# 为什么是"清场"而不是"停刷等玩家杀完"或"让怪跟进下一波"：升级面板并不暂停
# 场景树（它只设 process_mode=ALWAYS 并锁玩家输入），留着活怪等于让玩家在
# 商店界面后面当活靶子。
func _end_endless_wave() -> void:
	_wave_epoch += 1     # 作废所有在途生成协程
	_spawns_pending = 0
	wave_time_left = 0.0
	_pending_specials.clear()

	# 先整体摘出 _alive_enemies 再逐只 despawn，避免清场过程中的任何路径回头改这个数组
	var leftovers: Array = _alive_enemies.duplicate()
	_alive_enemies.clear()
	var credit_score: int = 0
	for e in leftovers:
		if not is_instance_valid(e):
			continue
		var base_val: int = int(e.score_value) if "score_value" in e else 100
		var ratio: float = 0.0
		if e.has_method("despawn"):
			ratio = float(e.despawn(endless_despawn_fade))
		else:
			e.queue_free()
		if endless_partial_credit and ratio > 0.0:
			credit_score += int(round(float(base_val) * ratio))
	# boss 的在飞投射物也要清：升级面板期间玩家输入是被锁住的，
	# 留着弹在飞等于让玩家在商店界面后面白挨最多 5 秒伤害
	for p in get_tree().get_nodes_in_group("boss_projectile"):
		if is_instance_valid(p):
			p.queue_free()

	# partial credit：波末最后十秒开的枪不能是白打，否则会诱导出"留着怪慢慢磨"的反向激励。
	# 只给分和钱，不计击杀数、不续连击。
	if credit_score > 0:
		total_score += credit_score
		score_changed.emit(total_score)
		currency += int(round(float(credit_score) * currency_earn_rate))
		currency_changed.emit(currency)

	_end_wave_common()

# v0.4-B B5-A：Boss 召唤增援接口——把召唤的小弟纳入本波 alive 列表
# 玩家必须杀完召唤的 grunt 才能过波，强化 Phase 2 持续压力（不只杀 boss 本体）
func register_summoned_enemy(enemy: Enemy) -> void:
	if enemy == null or _alive_enemies.has(enemy):
		return
	# 无尽模式：boss 的召唤计时器与波次状态完全解耦、每帧都跑，会在"倒计时已归零、
	# 正在清场或升级面板中"的窗口里继续塞怪。不加这道守卫，商店界面后面会冒出 grunt。
	# 召唤怪占并发名额但不扣威胁预算（扣的话会把 ambient 刷怪饿死）。
	if _endless and (_state != State.COMBAT or wave_time_left <= 0.0):
		enemy.queue_free()
		return
	# 召唤不扣威胁预算，但仍受并发硬闸门约束——否则 boss 的 Phase 2 每 10 秒 +2 只
	# 能把同屏数顶到闸门之上，性能防线就漏了
	if _endless and _alive_enemies.size() + _spawns_pending >= endless_concurrent_hard_cap:
		enemy.queue_free()
		return
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_alive_enemies.append(enemy)
	if not _endless:
		# 召唤的小弟计入本波总数，玩家必须一并杀完才过波
		_wave_total += 1
		wave_progress.emit(_remaining())

func _on_enemy_died(enemy) -> void:
	_alive_enemies.erase(enemy)
	_wave_killed += 1
	total_kills += 1
	kill_count_changed.emit(total_kills)
	var gained: int = int(enemy.score_value) if "score_value" in enemy else 100
	# 精英/BOSS 击杀得分加成（elite_hunter 升级）
	if elite_score_bonus > 0.0:
		var is_special: bool = (("is_elite" in enemy and enemy.is_elite) or ("is_boss" in enemy and enemy.is_boss))
		if is_special:
			gained = int(round(float(gained) * (1.0 + elite_score_bonus)))
	total_score += gained
	score_changed.emit(total_score)
	# 货币按获取率折算（< 全额），制造稀缺让 build 取舍有意义
	currency += int(round(float(gained) * currency_earn_rate))
	currency_changed.emit(currency)
	current_combo += 1
	if current_combo > max_combo:
		max_combo = current_combo
	_combo_timer = COMBO_WINDOW
	combo_changed.emit(current_combo, false)
	# 无尽模式没有"剩余数"这个概念，且高频击杀下这条信号会不断冲掉 HUD 的倒计时文本
	if not _endless:
		wave_progress.emit(_remaining())

	# 仅在 COMBAT 态下才检查清空（SPAWNING 途中有敌人被秒也不该推进）
	_check_wave_cleared()

# 抽出 wave 清空判定 + 推波 / 通关分流（_on_enemy_died 和 _process 兜底共用）
func _check_wave_cleared() -> void:
	# 无尽模式永不因"杀光"过波，只认倒计时
	if _endless:
		return
	if _state != State.COMBAT or not _alive_enemies.is_empty():
		return
	# 还有敌人在播生成烟没落地：此刻 _alive_enemies 为空只代表"已落地的都清了"，
	# 不代表本波打完。不挡住的话会提前通关，未落地的敌人生成到下一波里
	if _spawns_pending > 0:
		return
	_end_wave_common()

# 收波公共尾巴：classic（杀光）与 endless（时间到）共用同一个交接点。
# _state 归 IDLE 是 start_next_wave 那道守卫的唯一入口，忘了归位的症状是
# "升级面板关了但游戏静止、且没有任何报错"，极难定位——所以两条路径必须共用这里。
func _end_wave_common() -> void:
	if _run_over:
		return
	_state = State.IDLE
	wave_completed.emit(current_wave)
	# 每波清空给玩家 +1 处决次数（保底应急回弹来源）
	var _pl: Node = get_tree().get_first_node_in_group("player")
	if _pl and _pl.has_method("add_execute_charge"):
		_pl.add_execute_charge(1)
	# 通关：到达 victory_wave 触发结算页，不再推下一波（无尽模式 victory_wave=0，永不命中）
	if victory_wave > 0 and current_wave >= victory_wave:
		game_completed.emit(current_wave)
		return
	if auto_continue:
		# 延迟让最后一只怪倒地动画播完再弹升级面板，避免突然切 UI
		# 无尽模式额外等一个清场淡出的时长，让"时间到"的收场看得完整
		var delay: float = WAVE_END_DELAY + (endless_despawn_fade if _endless else 0.0)
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree() or _run_over:
			return  # 场景重载 / 等待期间玩家阵亡
		_request_upgrade_then_next()

# 波次清空 → 弹升级面板（若存在）→ 面板关闭 → 下一波
func _request_upgrade_then_next() -> void:
	# 双保险：绝不把商店弹到死亡结算页上（它是 layer 20，会盖住 layer 10 的结算页）
	if _run_over:
		return
	var panel: Node = get_tree().get_first_node_in_group("upgrade_panel")
	if panel and panel.has_method("show_panel"):
		# 面板会在玩家按"继续"后 emit panel_closed 信号
		if not panel.panel_closed.is_connected(_on_upgrade_panel_closed):
			panel.panel_closed.connect(_on_upgrade_panel_closed, CONNECT_ONE_SHOT)
		panel.show_panel(current_wave)
	else:
		start_next_wave()

func _on_upgrade_panel_closed() -> void:
	start_next_wave()

# 本局已运行秒数（供结算统计用）
func run_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _run_start_time_msec) / 1000.0
