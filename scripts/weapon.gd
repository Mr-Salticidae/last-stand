class_name Weapon extends Node3D

# 头部 hitbox 倍率基数。与 scenes/enemy.tscn 里 head Hitbox 的 damage_multiplier 数据耦合，
# 改这里要一并调 tscn；爆头阈值判定 + headshot_bonus 公式都从这里取。
const HEADSHOT_BASE_MULT: float = 2.5

# ========== 身份配置 ==========
@export_group("Identity")
@export var weapon_id: String = "pistol"      # 唯一 ID（HUD / 切换 / 解锁系统索引用）
@export var weapon_name: String = "手枪"      # 显示名

# ========== 数值配置（Inspector 可调） ==========
@export_group("Stats")
@export var damage: float = 25.0
@export var mag_size: int = 12                # 基础弹匣容量（运行时用 max_ammo() 算最终值，受 mag_size_mult 影响）
@export var reserve_max: int = 60             # 备弹上限（波间补满到此值）
@export var fire_rate: float = 0.15           # 两次开火之间的最小间隔（秒）
@export var reload_time: float = 1.5
@export var weapon_range: float = 100.0
@export var pellet_count: int = 1             # 单次开火发射的弹丸数（散弹用 8）

@export_group("Behavior")
@export var auto_fire: bool = false           # true=按住连发，false=单击单发
@export var unlocked: bool = false            # 是否已解锁。pistol.tscn 显式 true，rifle/shotgun/revolver 由 wave_manager 解锁，传说武器由拾取触发

@export_group("Recoil")
@export var recoil_pitch_deg: float = 2.2     # 每发造成的视角上抬角度（度）
@export var bullet_spread_deg: float = 0.35   # 子弹最大散布角度（度），让连射不打同点

@export_group("Legendary")
@export var is_legendary: bool = false        # 标识：HUD 用金色边框 / 抽卡条件等
@export var discard_on_empty: bool = false    # true=current+reserve 全空时自动从武器栏移除（重机枪等）

@export_group("Explosion")
# 命中点 AOE 爆炸：> 0 时启用（电磁炮 / 火箭炮等）
# 命中后在 hit_pos 触发：可视化球体 + 范围内所有 group("enemies") 受 explosion_damage * 距离衰减
@export var explosion_radius: float = 0.0
@export var explosion_damage: float = 0.0

@export_group("UI")
@export var preview_texture: Texture2D        # weapon_bar 右侧栏显示的武器预览图（可空，空则只显示武器名）

# ========== 节点引用 ==========
# shoot_raycast 由 weapon_manager 统一持有（所有武器共享同一根射线）
# weapon._ready 时从 _manager 读取并保持本地引用，避免每次 fire 都查
var shoot_raycast: RayCast3D
@onready var muzzle: Marker3D = $muzzle
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var _player: Node = get_tree().get_first_node_in_group("player")
@onready var _manager: Node = get_parent()    # weapon_manager 是父节点，buff 字段挂在它身上

# ========== 运行时状态 ==========
var current_ammo: int
var reserve_ammo: int
var is_reloading: bool = false
var _shoot_cooldown: float = 0.0
# 长按空仓时只播一次哔声：每次松开-按下由 manager 调 notify_trigger_pressed() 重置
var _dry_fire_played_this_press: bool = false
# 战术换弹 v0.3：换弹完成后置 true，下一发开火消费（每 weapon 自有，不跨武器共享）
var _reload_burst_pending: bool = false

# ========== 信号 ==========
# ammo_changed 三参版：current / reserve / 最终 mag 容量（受 mag_size_mult 影响）
signal ammo_changed(current: int, reserve: int, maximum: int)
signal reload_started(duration: float)  # duration = 应用 buff 后的实际换弹时长，HUD 进度条用
signal reload_finished
# 战斗反馈信号：HUD 用来闪命中标记、爆头提示、击杀确认
signal hit_confirmed
signal headshot_confirmed
signal kill_confirmed
# 传说武器空弹 → manager 监听此信号触发自动丢弃
signal depleted
# 每次成功开火（pellet 散射前）发一次：武器附属脚本（如 barrel_spinner）用来驱动加速 / 后坐反馈
signal shot_fired
# v0.3 视觉反馈：HUD 监听这两个信号触发屏幕闪光（暴伤瞬间反馈）
signal reload_burst_consumed   # 战术换弹首发触发（白闪）
signal last_round_fired         # 弹匣最后 N 发开火（橙闪）

func _ready() -> void:
	# 从 manager 拿共享的 raycast 引用
	if _manager and "shoot_raycast" in _manager:
		shoot_raycast = _manager.shoot_raycast
	assert(shoot_raycast != null, "weapon.gd: 父节点 weapon_manager 没有 shoot_raycast，请检查 Inspector")
	current_ammo = max_ammo()
	reserve_ammo = reserve_max
	# weapon_range 是每把武器自己的；切换时 try_shoot 不会动 target_position，改在每次开火前刷新
	ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())

func _process(delta: float) -> void:
	if _shoot_cooldown > 0.0:
		_shoot_cooldown -= delta

# ========== Buff 读取（buff 字段持久挂在 weapon_manager，所有武器共享） ==========
func _buff(field: String, default_v: Variant) -> Variant:
	if _manager and field in _manager:
		return _manager.get(field)
	return default_v

# 受 mag_size_mult 影响的最终弹匣容量
func max_ammo() -> int:
	var mult: float = _buff("mag_size_mult", 1.0)
	return maxi(1, int(round(float(mag_size) * mult)))

# ========== 切换 / 备弹 API（weapon_manager 调用） ==========
# 备弹补满（intermission 阶段调）
func refill_reserve() -> void:
	reserve_ammo = reserve_max
	ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())

# 武器被切走：取消装填、清开火 cd
func on_unequipped() -> void:
	is_reloading = false
	_shoot_cooldown = 0.0

# 武器被切到：同步 current_ammo 不超新的 max + 设置共享 raycast 的射程
func on_equipped() -> void:
	current_ammo = mini(current_ammo, max_ammo())
	if shoot_raycast:
		shoot_raycast.target_position = Vector3(0, 0, -weapon_range)
	ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())

# manager 在每次 just_pressed("shoot") 时调用一次，重置空仓哔声 latch
# 这样连发武器长按只在第一帧播 dry_fire，松开-按下能再次触发
func notify_trigger_pressed() -> void:
	_dry_fire_played_this_press = false

# manager 调用。返回 true 表示成功开火
func try_shoot() -> bool:
	if is_reloading or _shoot_cooldown > 0.0:
		return false
	# 打空自动装弹（玩家尝试开火但弹匣空，且备弹还有）；同时播空仓击发音作听觉反馈
	# 连发武器（auto_fire）长按空仓会每 fire_rate cd 播一次 → 听起来像长哔；
	# 用 _dry_fire_played_this_press 锁定，每次松开-按下时由 manager 调 notify_trigger_pressed 重置
	if current_ammo <= 0:
		if not _dry_fire_played_this_press:
			AudioManager.play_dry_fire()
			_dry_fire_played_this_press = true
		try_reload()
		return false

	current_ammo -= 1
	# 冷却：基础 fire_rate × 倍率；杀戮狂热 / 战术换弹 / 战术突进 期间进一步缩短
	var fire_rate_mult: float = _buff("fire_rate_mult", 1.0)
	var kill_rage_timer: float = _buff("kill_rage_timer", 0.0)
	var kill_rage_fr_bonus: float = _buff("kill_rage_fire_rate_bonus", 0.0)
	var cooldown: float = fire_rate * fire_rate_mult
	if kill_rage_timer > 0.0:
		var fr_b: float = kill_rage_fr_bonus
		# 节拍枪手羁绊：combo>=5 时额外 +20% 射速（常量同 wm.SYNERGY_PACEKEEPER_*）
		if _buff("synergy_pacekeeper", false) and _get_combo() >= 5:
			fr_b += 0.20
		if fr_b > 0.0:
			cooldown /= (1.0 + fr_b)
	# 战术突进：出滑铲后窗口期内射速 buff
	var sb_timer: float = _buff("slide_burst_timer", 0.0)
	var sb_bonus: float = _buff("slide_burst_fire_rate_bonus", 0.0)
	if sb_timer > 0.0 and sb_bonus > 0.0:
		cooldown /= (1.0 + sb_bonus)
	_shoot_cooldown = cooldown
	AudioManager.play_shot(weapon_id)

	if anim_player and anim_player.has_animation("recoil"):
		anim_player.stop()
		anim_player.play("recoil")

	# 功能后坐力：推动玩家视角上抬，迫使玩家"压枪"
	if _player and _player.has_method("apply_recoil"):
		_player.apply_recoil(recoil_pitch_deg)

	shot_fired.emit()

	# 散弹枪 / 多 pellet 武器：每颗独立散布锥 + 独立伤害结算
	var spread_mult: float = _buff("spread_mult", 1.0)
	var effective_spread: float = bullet_spread_deg * spread_mult
	# 开火前快照（_fire_pellet 多次调用都会读到同一份 pending / last_round 状态）
	var was_reload_burst: bool = _reload_burst_pending
	var lr_count: int = int(_buff("last_round_count", 0))
	var was_last_round: bool = lr_count > 0 and current_ammo < lr_count
	for p in pellet_count:
		_fire_pellet(effective_spread)
	# 战术换弹 pending flag：一次开火（含散弹多 pellet）算 1 发，开完即消费 + 通知 HUD
	if was_reload_burst:
		_reload_burst_pending = false
		reload_burst_consumed.emit()
	if was_last_round:
		last_round_fired.emit()

	ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())

	# 打空：传说武器若备弹也空 → 发 depleted 由 manager 决定丢弃；否则常规自动装填
	if current_ammo <= 0:
		if discard_on_empty and reserve_ammo <= 0:
			depleted.emit()
		else:
			try_reload()

	return true

# 单颗弹丸：独立 raycast + 独立伤害结算
func _fire_pellet(effective_spread: float) -> void:
	var spread_x := deg_to_rad(randf_range(-effective_spread, effective_spread))
	var spread_y := deg_to_rad(randf_range(-effective_spread, effective_spread))
	shoot_raycast.rotation = Vector3(spread_x, spread_y, 0)
	shoot_raycast.force_raycast_update()
	if not shoot_raycast.is_colliding():
		return

	var hit_pos: Vector3 = shoot_raycast.get_collision_point()
	var collider: Object = shoot_raycast.get_collider()
	# 判断命中类型：hitbox 带 damage_multiplier（头部 = HEADSHOT_BASE_MULT，身体 1.0）
	var is_headshot: bool = false
	if collider is Hitbox:
		is_headshot = (collider as Hitbox).damage_multiplier >= HEADSHOT_BASE_MULT
	_spawn_hit_effect(hit_pos, is_headshot)

	# 爆炸 AOE：墙体 / 敌人命中都触发；直接伤害仍照常结算（直接被命中的敌人吃 splash + direct 双份）
	if explosion_radius > 0.0 and explosion_damage > 0.0:
		_spawn_explosion(hit_pos)

	if not (collider and collider.has_method("take_damage")):
		return
	# 只认 Hitbox 触发伤害：命中 enemy CharacterBody3D 物理体（粗矩形 collision）
	# 视为"未中要害"，避免 mesh 与物理 collision 形状不贴合时误判（胯下/腋下空气等）
	if collider is Enemy:
		return

	# 找到承担伤害的 enemy 根节点：hitbox 转发给 parent
	var target_enemy: Node = collider as Node
	if target_enemy and target_enemy.get_parent() and (target_enemy.get_parent() as Node).has_method("is_dead"):
		target_enemy = target_enemy.get_parent()
	var was_dead: bool = false
	if target_enemy and target_enemy.has_method("is_dead"):
		was_dead = target_enemy.is_dead()

	# 弹药节省：命中生效时按概率回补 1 发（仍显示发射动画/特效）
	var ammo_save_chance: float = _buff("ammo_save_chance", 0.0)
	if ammo_save_chance > 0.0 and randf() < ammo_save_chance:
		current_ammo = mini(current_ammo + 1, max_ammo())

	# 伤害计算：base * damage_mult × (各种 mult)
	var damage_mult: float = _buff("damage_mult", 1.0)
	var elite_damage_bonus: float = _buff("elite_damage_bonus", 0.0)
	var combo_damage_threshold: int = int(_buff("combo_damage_threshold", 9999))
	var combo_damage_bonus: float = _buff("combo_damage_bonus", 0.0)
	var headshot_bonus: float = _buff("headshot_bonus", 0.0)

	var total_damage: float = damage * damage_mult
	# v0.3 新卡 mult ↓
	# 穿甲弹：暴击概率（注：try_shoot 已扣 1 弹，current_ammo 是开火后值）
	# 暴风穿透羁绊：crit 概率叠加 synergy_crit_bonus（+0.10）
	var crit_chance: float = _buff("crit_chance", 0.0) + _buff("synergy_crit_bonus", 0.0)
	if crit_chance > 0.0 and randf() < crit_chance:
		total_damage *= 3.0
		# 暴风穿透羁绊：暴击命中触发 0.2s stagger（任何敌人，不限精英）
		if _buff("synergy_crit_stagger", false) and target_enemy and target_enemy.has_method("stagger"):
			target_enemy.stagger(0.2)
	# 底牌：开火后 current_ammo < last_round_count 即触发（last_round_count=1 → 最后一发；=2 → 最后两发）
	# 弹匣艺术家羁绊：last_round 触发时也吃 reload_burst_damage_mult（首末双爆）
	var last_round_count: int = int(_buff("last_round_count", 0))
	if last_round_count > 0 and current_ammo < last_round_count:
		var lr_mult: float = 3.0
		if _buff("synergy_mag_art", false):
			var rb_for_lr: float = _buff("reload_burst_damage_mult", 0.0)
			if rb_for_lr > 1.0:
				lr_mult *= rb_for_lr
		total_damage *= lr_mult
	# 游击战：玩家移动 +bonus，静止 -penalty
	var momentum_move_bonus: float = _buff("momentum_move_bonus", 0.0)
	var momentum_static_penalty: float = _buff("momentum_static_penalty", 0.0)
	if (momentum_move_bonus > 0.0 or momentum_static_penalty > 0.0) and _player:
		var v_xz: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		if v_xz > 0.5:
			total_damage *= (1.0 + momentum_move_bonus)
		else:
			total_damage *= (1.0 - momentum_static_penalty)
	# 狂战士：玩家血量比例 < 30% 时伤害 +60%
	# 永恒战神羁绊：阈值 +0.20（30% → 50%）
	var berserker_active: bool = _buff("berserker_active", false)
	if berserker_active and _player and "current_health" in _player and "max_health" in _player:
		var bersk_thresh: float = 0.3 + _buff("synergy_berserker_threshold_bonus", 0.0)
		if _player.max_health > 0.0 and _player.current_health / _player.max_health < bersk_thresh:
			total_damage *= 1.6
	# 猎手本能：按 enemy_id 累计击杀加伤
	# 死神低语羁绊：weak_spot 触发时额外 ×1.3
	var weak_spot_enabled: bool = _buff("weak_spot_enabled", false)
	if weak_spot_enabled and _manager and target_enemy and "enemy_id" in target_enemy:
		var ws_kills: Dictionary = _manager.weak_spot_kills
		var ws_stacks: int = int(ws_kills.get(target_enemy.enemy_id, 0))
		if ws_stacks > 0:
			var ws_mult: float = 1.0 + 0.5 * float(ws_stacks)
			if _buff("synergy_reaper_whisper", false):
				ws_mult *= 1.3
			total_damage *= ws_mult
	# v0.3 新卡 mult ↑
	if elite_damage_bonus > 0.0 and target_enemy and _is_special_enemy(target_enemy):
		total_damage *= (1.0 + elite_damage_bonus)
	if combo_damage_bonus > 0.0 and _get_combo() >= combo_damage_threshold:
		total_damage *= (1.0 + combo_damage_bonus)
	# 爆头额外倍率：hitbox 自身已经乘 damage_multiplier(HEADSHOT_BASE_MULT)，这里补乘 headshot_bonus 分量
	if is_headshot and headshot_bonus > 0.0:
		total_damage *= (HEADSHOT_BASE_MULT + headshot_bonus) / HEADSHOT_BASE_MULT
	# 战术换弹：换弹后下一发开火吃 ×N 暴伤（消费 pending flag）
	# 注意：散弹枪 _fire_pellet 一次开火多次调用 → 多 pellet 都吃这个 buff，因为 flag 只在第一发被消费
	# 但散弹一次开火逻辑上算 1 发，所以"多 pellet 都吃 mult"才符合卡描述（"换弹后下一发开火"）
	# 解决：让 try_shoot 而非 _fire_pellet 消费 flag。这里只读不消费，try_shoot 末尾消费
	if _reload_burst_pending:
		var rb_mult: float = _buff("reload_burst_damage_mult", 0.0)
		if rb_mult > 1.0:
			total_damage *= rb_mult
	# 重型压制：命中精英/BOSS 概率打断（伤害判定前后都行，这里放伤害前免得 stagger 死的怪）
	var stagger_chance: float = _buff("stagger_chance", 0.0)
	if stagger_chance > 0.0 and target_enemy and _is_special_enemy(target_enemy):
		if target_enemy.has_method("stagger") and randf() < stagger_chance:
			target_enemy.stagger(_buff("stagger_duration", 0.0))
	collider.take_damage(total_damage)

	# 只在 "这一发把它打死" 时发 kill，否则发 hit / headshot
	var now_dead: bool = false
	if target_enemy and target_enemy.has_method("is_dead"):
		now_dead = target_enemy.is_dead()
	if not was_dead and now_dead:
		kill_confirmed.emit()
		AudioManager.play_kill()
		# 爆头击杀：kill + headshot 音效叠加（清脆 ping + 闷响 thud）
		# 视觉只走 kill_confirmed（红色 hit marker），避免和金黄 headshot 帧冲突
		if is_headshot:
			AudioManager.play_headshot()
		_do_hit_pause()
		# 升级系统：击杀回血 + 杀戮狂热刷新计时（写到 manager，所有武器共享）
		# 死神之舞羁绊：kill_heal +3
		var kill_heal_amount: float = _buff("kill_heal_amount", 0.0) + _buff("synergy_kill_heal_bonus", 0.0)
		var kill_rage_duration: float = _buff("kill_rage_duration", 0.0)
		if kill_heal_amount > 0.0 and _player and _player.has_method("heal"):
			_player.heal(kill_heal_amount)
		if kill_rage_duration > 0.0 and _manager:
			# 节拍枪手羁绊：combo>=5 时 kill_rage 持续 ×1.66
			var krd: float = kill_rage_duration
			if _buff("synergy_pacekeeper", false) and _get_combo() >= 5:
				krd *= 1.66
			_manager.set("kill_rage_timer", krd)
		# 死神领域羁绊：combo>=10 时所有击杀回 10 弹 + 刷 kill_rage_timer（即使没买 kill_rage 也能回弹）
		if _buff("synergy_reaper_realm", false) and _get_combo() >= 10:
			current_ammo = mini(current_ammo + 10, max_ammo())
			ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())
			if kill_rage_duration > 0.0 and _manager:
				_manager.set("kill_rage_timer", kill_rage_duration)
		# v0.3 新卡 kill 触发 ↓
		# 嗜血：伤害 X% 转治疗，单次回血上限封顶
		# 永恒战神羁绊：vampiric_rate +0.05；死神之舞羁绊：vampiric_cap +3
		var vampiric_rate: float = _buff("vampiric_rate", 0.0) + _buff("synergy_vampiric_rate_bonus", 0.0)
		if vampiric_rate > 0.0 and _player and _player.has_method("heal"):
			var vampiric_cap: float = _buff("vampiric_cap_per_kill", 9999.0) + _buff("synergy_vampiric_cap_bonus", 0.0)
			_player.heal(minf(total_damage * vampiric_rate, vampiric_cap))
		# 连锁处决：上次击杀 X 秒内再击杀 → 回弹 + 短暂无敌
		var chain_active: bool = _buff("chain_kill_active", false)
		if chain_active and _manager:
			var now_t: float = Time.get_ticks_msec() / 1000.0
			var last_t: float = float(_manager.get("_last_kill_time"))
			var window: float = _buff("chain_kill_window", 0.0)
			if now_t - last_t <= window:
				var refund: int = int(_buff("chain_kill_ammo_refund", 0))
				current_ammo = mini(current_ammo + refund, max_ammo())
				ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())
				var iv: float = _buff("chain_kill_invuln", 0.0)
				if _player and "_invuln_timer" in _player:
					_player._invuln_timer = maxf(_player._invuln_timer, iv)
			_manager.set("_last_kill_time", now_t)
		# 猎手本能：按敌种累计击杀（cap 在 manager 内部）
		if _manager and target_enemy and "enemy_id" in target_enemy:
			if _manager.has_method("record_weak_spot_kill"):
				_manager.record_weak_spot_kill(target_enemy.enemy_id)
		# v0.3 新卡 kill 触发 ↑
	elif not was_dead:
		if is_headshot:
			headshot_confirmed.emit()
			AudioManager.play_headshot()
		else:
			hit_confirmed.emit()
			AudioManager.play_hit()

# 判断敌人是否是精英或 BOSS（给 elite_hunter 用）
func _is_special_enemy(enemy: Node) -> bool:
	if "is_elite" in enemy and enemy.is_elite:
		return true
	if "is_boss" in enemy and enemy.is_boss:
		return true
	return false

# 读 wave_manager.current_combo（懒加载缓存到 manager 的 _wave_manager 上不必，简单查一次）
func _get_combo() -> int:
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	if wm and "current_combo" in wm:
		return int(wm.current_combo)
	return 0

func try_reload() -> bool:
	if is_reloading:
		return false
	if current_ammo >= max_ammo():
		return false
	if reserve_ammo <= 0:
		return false  # 备弹空：装不进去
	is_reloading = true
	var reload_time_mult: float = _buff("reload_time_mult", 1.0)
	var actual_time: float = reload_time * reload_time_mult
	reload_started.emit(actual_time)
	AudioManager.play_reload()
	get_tree().create_timer(actual_time).timeout.connect(_finish_reload)
	return true

func _finish_reload() -> void:
	# 装填中被切走（on_unequipped 把 is_reloading 清了）→ 这次回调作废
	if not is_reloading:
		return
	# 从备弹扣需要的量；备弹不足时按剩余量装填
	var needed: int = max_ammo() - current_ammo
	var available: int = mini(needed, reserve_ammo)
	current_ammo += available
	reserve_ammo -= available
	is_reloading = false
	ammo_changed.emit(current_ammo, reserve_ammo, max_ammo())
	reload_finished.emit()
	# 战术换弹：装弹完成 → 下一发开火 ×N 伤害（"无脑泼水"反对策：连发武器只是 1 发奖励，单发武器价值最大化）
	if _buff("reload_burst_enabled", false):
		_reload_burst_pending = true

# 击杀瞬间 0.08s 慢动作（Engine.time_scale=0.3），Doom / Warframe 风格肉感反馈
# 用 ignore_time_scale=true 的 timer 确保在 time_scale 缩放期间计时准确
var _hit_pause_active: bool = false
const HIT_PAUSE_DURATION: float = 0.08
const HIT_PAUSE_SCALE: float = 0.3

func _do_hit_pause() -> void:
	if _hit_pause_active:
		return
	_hit_pause_active = true
	Engine.time_scale = HIT_PAUSE_SCALE
	await get_tree().create_timer(HIT_PAUSE_DURATION, true, false, true).timeout
	# 防御：await 期间武器若被 queue_free（电磁炮最后一发既触发 splash kill 又触发 deplete），
	# 这里的赋值仍可能不执行 → 真正的兜底在 _exit_tree
	Engine.time_scale = 1.0
	_hit_pause_active = false

# 兜底：武器被 queue_free 时若 hit_pause 还激活（await 没机会跑完），
# 强制 time_scale 回正，否则整个游戏会卡在 0.3 时间流速
func _exit_tree() -> void:
	if _hit_pause_active:
		Engine.time_scale = 1.0
		_hit_pause_active = false

# 命中反馈：普通命中黄色小球；爆头用更大的红橙色球 + 向外放射 6 条小刺，像爆炸
func _spawn_hit_effect(world_pos: Vector3, is_headshot: bool = false) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08 if is_headshot else 0.05
	sphere.height = sphere.radius * 2.0
	marker.mesh = sphere

	var mat := StandardMaterial3D.new()
	var core_color: Color = Color(1.0, 0.25, 0.1) if is_headshot else Color(1.0, 0.8, 0.2)
	mat.albedo_color = core_color
	mat.emission_enabled = true
	mat.emission = core_color
	mat.emission_energy_multiplier = 5.0 if is_headshot else 3.0
	marker.material_override = mat

	get_tree().current_scene.add_child(marker)
	marker.global_position = world_pos

	if is_headshot:
		# 爆头额外放射 6 条短刺，尖端向外，tween 缩放淡出
		_spawn_headshot_burst(world_pos)
		get_tree().create_timer(0.35).timeout.connect(marker.queue_free)
	else:
		get_tree().create_timer(0.2).timeout.connect(marker.queue_free)

func _spawn_headshot_burst(world_pos: Vector3) -> void:
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(1.0, 0.3, 0.1)
	spike_mat.emission_enabled = true
	spike_mat.emission = Color(1.0, 0.5, 0.1)
	spike_mat.emission_energy_multiplier = 4.0
	var spike_mesh := BoxMesh.new()
	spike_mesh.size = Vector3(0.02, 0.02, 0.18)

	for i in 6:
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		spike.material_override = spike_mat
		get_tree().current_scene.add_child(spike)
		spike.global_position = world_pos
		# 均匀放射 6 个方向（+X, -X, +Y, -Y, +Z, -Z 混一点随机）
		var angle: float = (float(i) / 6.0) * TAU
		var dir: Vector3 = Vector3(cos(angle), sin(angle) * 0.6, sin(angle + PI * 0.5)).normalized()
		spike.look_at(world_pos + dir, Vector3.UP)
		var tween := spike.create_tween().set_parallel(true)
		tween.tween_property(spike, "global_position", world_pos + dir * 0.5, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spike, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(spike.queue_free)

# 爆炸 AOE：命中点周围所有敌人受 explosion_damage * 距离衰减
# 衰减：中心 1.0 → 边缘 0.3（避免边缘完全无效）。溅射击杀正常计 combo / kill_heal / kill_rage
func _spawn_explosion(world_pos: Vector3) -> void:
	_create_explosion_visual(world_pos)

	var any_kill: bool = false
	var kill_heal_amount: float = _buff("kill_heal_amount", 0.0)
	var kill_rage_duration: float = _buff("kill_rage_duration", 0.0)
	# 注意：实际 group 名是 "enemy"（单数），enemy.tscn 里声明，变种通过场景继承自动拥有
	var enemies := get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if not (e is Node3D) or not e.has_method("take_damage"):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		# 用敌人腰部高度（脚 + 1.0m）做距离检查，避免脚 origin 距 hit_pos 远但身体在范围内的漏判
		# （hit_pos 通常在敌人身上 hitbox 表面 y=1~2.5，脚 y=0，差距可达 2m+）
		var enemy_target: Vector3 = e.global_position + Vector3.UP * 1.0
		var dist: float = (enemy_target - world_pos).length()
		if dist > explosion_radius:
			continue
		var t: float = clampf(dist / explosion_radius, 0.0, 1.0)
		var falloff: float = lerpf(1.0, 0.3, t)
		var dmg: float = explosion_damage * falloff
		var was_dead: bool = e.is_dead() if e.has_method("is_dead") else false
		e.take_damage(dmg)
		var now_dead: bool = e.is_dead() if e.has_method("is_dead") else false
		if not was_dead and now_dead:
			kill_confirmed.emit()
			any_kill = true
			if kill_heal_amount > 0.0 and _player and _player.has_method("heal"):
				_player.heal(kill_heal_amount)
			if kill_rage_duration > 0.0 and _manager:
				_manager.set("kill_rage_timer", kill_rage_duration)
	if any_kill:
		_do_hit_pause()

# 爆炸视觉：emissive 球体 + 膨胀 + 淡出，~0.4s 销毁
func _create_explosion_visual(world_pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = explosion_radius * 0.4
	sphere.height = explosion_radius * 0.8
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = world_pos
	# 膨胀至 2.5x（接近实际伤害半径）+ alpha 淡出
	var tween: Tween = flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.5, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(1.0, 0.55, 0.15, 0.0), 0.4)
	tween.chain().tween_callback(flash.queue_free)
