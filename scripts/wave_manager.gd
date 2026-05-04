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
@export var brute_chance_max: float = 1.0
# 精英 / Boss 波次周期
@export var elite_wave_period: int = 5
@export var boss_wave_period: int = 15

enum State { IDLE, INTERMISSION, SPAWNING, COMBAT }

var current_wave: int = 0
var total_kills: int = 0
var total_score: int = 0
# 可花费资金：与 total_score 同步获得，但升级消耗只扣这里，不影响结算得分
var currency: int = 0
var current_combo: int = 0
# 精英猎手：elite/boss 击杀得分额外加成（UpgradeManager 改写）
var elite_score_bonus: float = 0.0
var max_combo: int = 0
var _combo_timer: float = 0.0
const COMBO_WINDOW: float = 2.5  # N 秒内击杀延续连击，超时重置
var _run_start_time_msec: int = 0
var _state: State = State.IDLE
var _intermission_timer: float = 0.0
var _spawn_points: Array = []
var _alive_enemies: Array = []

func _ready() -> void:
	add_to_group("wave_manager")
	_run_start_time_msec = Time.get_ticks_msec()
	# 自动收集场景里的所有 SpawnPoint
	_spawn_points = get_tree().get_nodes_in_group("spawn_point")
	if _spawn_points.is_empty():
		push_warning("WaveManager: 未找到任何 spawn_point，波次无法生成")
	if enemy_scene == null:
		push_warning("WaveManager: enemy_scene 未配置，请在 Inspector 拖拽 enemy.tscn")

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
	_intermission_timer = intermission_duration
	intermission_started.emit(current_wave, intermission_duration)

# 玩家重生时调用（死亡后 reload_current_scene 会销毁这个节点，但保留接口以备不拼 reload 的流程用）
func reset() -> void:
	current_wave = 0
	total_kills = 0
	total_score = 0
	currency = 0
	_state = State.IDLE
	for e in _alive_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_alive_enemies.clear()

# ---------- 内部循环 ----------
func _process(delta: float) -> void:
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

func _spawn_current_wave() -> void:
	if _spawn_points.is_empty() or enemy_scene == null:
		push_error("WaveManager: 缺少生成点或 grunt 敌人场景，跳过本波")
		_state = State.IDLE
		return

	_state = State.SPAWNING

	var count: int = min(base_enemy_count + (current_wave - 1) * enemy_count_per_wave, max_enemies_per_wave)
	var health_tier: int = (current_wave - 1) / health_boost_every_n_waves
	var health_mult: float = 1.0 + float(health_tier) * health_boost_per_tier

	wave_started.emit(current_wave, count)
	AudioManager.play_wave_start()

	# Boss 波（每 boss_wave_period 波 1 只）优先级高于 Elite 波
	var is_boss_wave: bool = boss_scene and current_wave > 0 and current_wave % boss_wave_period == 0
	var is_elite_wave: bool = (
		elite_scene and current_wave > 0
		and current_wave % elite_wave_period == 0
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
		if i == 0 and is_boss_wave:
			_spawn_at(sp, health_mult, boss_scene)
		elif i == 0 and is_elite_wave:
			_spawn_at(sp, health_mult, elite_scene)
		elif current_wave == 1 and runner_scene:
			# TEMP DEBUG (v0.2 #11): 第一波全部强制 runner 用于 hitbox 调试，验证后删除此分支
			_spawn_at(sp, health_mult, runner_scene)
		else:
			_spawn_at(sp, health_mult)
		if spawn_stagger > 0.0 and i < count - 1:
			await get_tree().create_timer(spawn_stagger).timeout
			# stagger 期间 _state 还是 SPAWNING；_process 的 INTERMISSION 分支不会干扰

	_state = State.COMBAT
	wave_progress.emit(_alive_enemies.size())

# 每只敌人独立 await 自己的 spawn_effect，互相不阻塞
# forced_scene 指定时用该 scene（精英/boss 固定生成），否则按随机混合
func _spawn_at(sp: SpawnPoint, health_mult: float, forced_scene: PackedScene = null) -> void:
	var smoke_dur: float = spawn_effect_duration * (1.6 if forced_scene else 1.0)
	await sp.play_smoke_effect(smoke_dur)
	if not is_inside_tree():
		return  # WaveManager 被销毁（场景重载等）

	var scene_to_spawn: PackedScene = forced_scene if forced_scene else _pick_enemy_scene()
	var enemy: Enemy = scene_to_spawn.instantiate()
	enemy.max_health *= health_mult
	# 移速 bonus：仅给 grunt 和 brute（runner/elite/boss 已经定位清晰，不再加成）
	if scene_to_spawn == enemy_scene or scene_to_spawn == brute_scene:
		var speed_tier: int = current_wave / speed_bonus_every_n_waves
		enemy.move_speed += float(speed_tier) * speed_bonus_per_tier
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
	wave_progress.emit(_alive_enemies.size())

# 按当前波次选敌人类型。runner 从 runner_unlock_wave 波起解锁，brute 从 brute_unlock_wave 波起解锁；
# 解锁后每波 chance 轻微递增直到 cap。
func _pick_enemy_scene() -> PackedScene:
	var runner_chance: float = 0.0
	var brute_chance: float = 0.0
	if runner_scene and current_wave >= runner_unlock_wave:
		runner_chance = minf(
			runner_chance_base + float(current_wave - runner_unlock_wave) * runner_chance_per_wave,
			runner_chance_max
		)
	if brute_scene and current_wave >= brute_unlock_wave:
		brute_chance = minf(
			brute_chance_base + float(current_wave - brute_unlock_wave) * brute_chance_per_wave,
			brute_chance_max
		)
	var r: float = randf()
	# 先判 brute（更稀有但更关键）再判 runner
	if brute_chance > 0.0 and r < brute_chance:
		return brute_scene
	if runner_chance > 0.0 and r < brute_chance + runner_chance:
		return runner_scene
	return enemy_scene

func _on_enemy_died(enemy) -> void:
	_alive_enemies.erase(enemy)
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
	currency += gained
	currency_changed.emit(currency)
	current_combo += 1
	if current_combo > max_combo:
		max_combo = current_combo
	_combo_timer = COMBO_WINDOW
	combo_changed.emit(current_combo, false)
	wave_progress.emit(_alive_enemies.size())

	# 仅在 COMBAT 态下才检查清空（SPAWNING 途中有敌人被秒也不该推进）
	if _state == State.COMBAT and _alive_enemies.is_empty():
		_state = State.IDLE
		wave_completed.emit(current_wave)
		if auto_continue:
			_request_upgrade_then_next()

# 波次清空 → 弹升级面板（若存在）→ 面板关闭 → 下一波
func _request_upgrade_then_next() -> void:
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
