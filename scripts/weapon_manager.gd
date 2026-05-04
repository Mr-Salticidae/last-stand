extends Node3D

# 武器管理器：持有武器列表 + 切换 + 输入转发 + 升级 buff 的"全局存放点"
# Buff 字段挂在这里（不挂 weapon），切换武器时 buff 不丢失，所有武器共享同一份升级加成
# weapon.gd 通过 get_parent() 读这些字段

signal weapon_changed(weapon: Weapon)        # 切换完成时发出，HUD 据此重连信号
signal weapon_unlocked(weapon: Weapon)       # 解锁新武器时发出（wave_manager 调）

# ========== 武器摇摆参数（Inspector 可调） ==========
@export_group("Sway")
@export var sway_strength: float = 0.0015
@export var sway_clamp: float = 0.06
@export var sway_smoothness: float = 8.0

@export_group("Bob")
@export var bob_strength: Vector2 = Vector2(0.02, 0.015)
@export var bob_freq_walk: float = 8.0
@export var bob_freq_sprint: float = 13.0
@export var bob_return_speed: float = 6.0

# ========== 节点引用 ==========
# shoot_raycast：所有武器共享同一根射线（指向准心），在 Inspector 拖拽 Camera3D/shoot_raycast
@export var shoot_raycast: RayCast3D
@onready var player: CharacterBody3D = get_tree().get_first_node_in_group("player")

# ========== 武器栏状态 ==========
var weapons: Array[Weapon] = []   # 所有 Weapon 子节点（含未解锁的，未解锁则不可装备）
var current_weapon: Weapon = null
var current_index: int = -1

# ========== 视觉抖动 ==========
var _default_position: Vector3
var _sway_offset: Vector3 = Vector3.ZERO
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0

# ========== 切换动画 ==========
# 动画：旧武器下沉 0.12s → 中点切换武器 + emit weapon_changed → 新武器上浮 0.18s
const SWITCH_DURATION_DOWN: float = 0.12
const SWITCH_DURATION_UP: float = 0.18
const SWITCH_OFFSET_Y: float = -0.25
var _switching: bool = false
var _switch_y: float = 0.0
var _switch_tween: Tween = null

# ========== 升级 Buff（UpgradeManager.apply_effect 修改，weapon._buff() 读取） ==========
# 字段名必须和 weapon.gd 里 _buff() 调用的字符串一致
var damage_mult: float = 1.0            # 口径升级 / 重型弹药
var fire_rate_mult: float = 1.0         # 急促射击（<1 更快） / 重型弹药（>1 更慢）
var mag_size_mult: float = 1.0          # 扩容弹匣（>1 更大）→ weapon.max_ammo() 据此算
var reload_time_mult: float = 1.0       # 快速装填（<1 更快）
var headshot_bonus: float = 0.0         # 头部专精：直接加到 hitbox 倍率（默认 2.5）
var spread_mult: float = 1.0            # 弹道稳定（<1 更准）
var ammo_save_chance: float = 0.0       # 弹药节省：命中时概率不消耗弹药
var kill_heal_amount: float = 0.0       # 杀戮回血：每次击杀回复给玩家
var kill_rage_duration: float = 0.0     # 杀戮狂热：击杀后加成生效秒数
var kill_rage_fire_rate_bonus: float = 0.0  # 杀戮狂热期间的射速加成（0.3 = +30%）
var kill_rage_timer: float = 0.0        # 杀戮狂热剩余生效时间（weapon 击杀时刷新，manager tick）
var combo_damage_threshold: int = 9999  # 战斗狂热：combo ≥ 此值触发伤害加成
var combo_damage_bonus: float = 0.0     # 战斗狂热伤害加成（0.4 = +40%）
var elite_damage_bonus: float = 0.0     # 精英猎手：对 elite/boss 伤害加成

func _ready() -> void:
	add_to_group("weapon_manager")
	assert(shoot_raycast != null, "weapon_manager.gd: shoot_raycast 必须在 Inspector 里指定 Camera3D/shoot_raycast")
	# 让射线能命中 hitbox（Area3D），所有武器共享此设置
	shoot_raycast.collide_with_areas = true
	_default_position = position

	# 收集所有 Weapon 子节点（包括未解锁的；未解锁仅是不可切到，节点仍存在）
	for child in get_children():
		if child is Weapon:
			weapons.append(child)
			# 监听传说武器空弹自动丢弃
			(child as Weapon).depleted.connect(_on_weapon_depleted.bind(child))
			# 隐藏除"第一把已解锁武器"外的其他所有武器
			child.visible = false
			child.set_process(false)

	# 装备第一把已解锁武器（通常是 pistol，unlocked=true）
	for i in range(weapons.size()):
		if weapons[i].unlocked:
			equip(i)
			break

func _unhandled_input(event: InputEvent) -> void:
	if current_weapon == null:
		return

	# 鼠标移动 → sway 位移（切换动画期间也允许，否则掉帧感更强）
	if event is InputEventMouseMotion:
		_sway_offset.x += -event.relative.x * sway_strength
		_sway_offset.y += event.relative.y * sway_strength
		_sway_offset.x = clamp(_sway_offset.x, -sway_clamp, sway_clamp)
		_sway_offset.y = clamp(_sway_offset.y, -sway_clamp, sway_clamp)

	# 切换动画期间所有武器交互锁死（开火 / 装填 / 切换全屏蔽）
	if _switching:
		return

	if event.is_action_pressed("reload"):
		current_weapon.try_reload()

	# 数字键切武器：1/2/3/4/5 直接切到对应槽位（5 是传说位）
	for i in range(mini(weapons.size(), 5)):
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			equip(i)
			return

	# 滚轮切武器：在已解锁武器中循环（跳过未解锁）
	if event.is_action_pressed("weapon_next"):
		_cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		_cycle_weapon(-1)

func _process(delta: float) -> void:
	# 杀戮狂热计时器（所有武器共享）
	if kill_rage_timer > 0.0:
		kill_rage_timer -= delta

	if current_weapon == null:
		return

	# 玩家死亡 / 升级面板开启时禁开火（避免点击 UI 按钮时鼠标左键被当成开火指令）
	if player and "_dead" in player and player._dead:
		return
	if player and "input_locked" in player and player.input_locked:
		return

	# 切换动画期间禁开火，但 sway/bob 继续算（避免 0.3s 内画面僵硬感）
	if not _switching:
		if current_weapon.auto_fire:
			if Input.is_action_pressed("shoot"):
				current_weapon.try_shoot()
		else:
			if Input.is_action_just_pressed("shoot"):
				current_weapon.try_shoot()

	# Sway：每帧向 0 回归，实现"拖拽滞后"感
	_sway_offset = _sway_offset.lerp(Vector3.ZERO, delta * sway_smoothness)

	# Bob：走动时上下 + 左右晃动
	var is_moving: bool = player != null and player.is_on_floor() and player.velocity.length() > 0.5
	if is_moving:
		var freq: float = bob_freq_sprint if player.get("sprinting") else bob_freq_walk
		_bob_time += delta * freq
		_bob_offset.x = sin(_bob_time) * bob_strength.x
		_bob_offset.y = absf(cos(_bob_time)) * bob_strength.y
	else:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * bob_return_speed)

	position = _default_position + _sway_offset + _bob_offset + Vector3(0, _switch_y, 0)

# ========== 武器切换 ==========
# 切换到 weapons[idx]。idx 越界 / 未解锁 / 同一把 → 静默忽略
# 首次装备（_ready 时 current_index=-1）或 fallback（current_weapon=null）跳过动画立即生效
# 否则触发 tween 动画：下沉 0.12s → 中点 _do_swap + emit → 上浮 0.18s
func equip(idx: int) -> void:
	if idx < 0 or idx >= weapons.size():
		return
	if not weapons[idx].unlocked:
		return
	if idx == current_index:
		return

	# 首次装备 / 传说武器空弹后回退：跳过动画立即生效
	if current_index < 0 or current_weapon == null:
		_do_swap(idx)
		return

	# 启动 tween 动画
	if _switch_tween and _switch_tween.is_valid():
		_switch_tween.kill()
	_switching = true
	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "_switch_y", SWITCH_OFFSET_Y, SWITCH_DURATION_DOWN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_switch_tween.tween_callback(_do_swap.bind(idx))
	_switch_tween.tween_property(self, "_switch_y", 0.0, SWITCH_DURATION_UP) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_switch_tween.tween_callback(_finish_switch)

# 中点回调：交换武器节点 + emit weapon_changed（HUD 在此时刷新，与视觉同步）
func _do_swap(idx: int) -> void:
	if current_weapon:
		current_weapon.on_unequipped()
		current_weapon.visible = false
		current_weapon.set_process(false)

	current_index = idx
	current_weapon = weapons[idx]
	current_weapon.visible = true
	current_weapon.set_process(true)
	current_weapon.on_equipped()

	weapon_changed.emit(current_weapon)

func _finish_switch() -> void:
	_switching = false
	_switch_y = 0.0

# 滚轮切换：在已解锁武器索引中循环（跳过未解锁的传说武器槽位等）
func _cycle_weapon(direction: int) -> void:
	var unlocked_indices: Array[int] = []
	for i in weapons.size():
		if weapons[i].unlocked:
			unlocked_indices.append(i)
	if unlocked_indices.size() < 2:
		return
	var pos: int = unlocked_indices.find(current_index)
	if pos < 0:
		pos = 0
	var next_pos: int = (pos + direction + unlocked_indices.size()) % unlocked_indices.size()
	equip(unlocked_indices[next_pos])

# 解锁某把武器（wave_manager 在 wave 2/4/6 调）
# weapon_id 匹配 weapon.weapon_id 字段
func unlock_weapon(id: String) -> bool:
	for w in weapons:
		if w.weapon_id == id and not w.unlocked:
			w.unlocked = true
			weapon_unlocked.emit(w)
			return true
	return false

# 装备 / 替换传说武器（拾取触发）。第 5 槽（idx=4）专属。
# 已有传说武器：先切回 fallback、移除、queue_free；再 instantiate 新武器追加到 weapons[]
# 不自动切换到新武器：沿用解锁公告 / weapon_bar 闪烁引导玩家按 5 切
func equip_legendary(scene: PackedScene) -> void:
	if scene == null:
		return

	# 移除任何已存在的传说武器（旧武器被替换，弹药未空也丢弃）
	for i in range(weapons.size() - 1, -1, -1):
		var existing: Weapon = weapons[i]
		if not existing.is_legendary:
			continue
		# 当前装备就是这把传说？_do_swap 会自动 on_unequipped + visibility 收起
		if existing == current_weapon:
			var fallback: int = -1
			for j in weapons.size():
				if j != i and weapons[j].unlocked and not weapons[j].is_legendary:
					fallback = j
					break
			if fallback >= 0:
				_do_swap(fallback)
		weapons.remove_at(i)
		existing.queue_free()

	# 实例化新传说武器，配置并加入 weapons[]
	var new_w: Weapon = scene.instantiate() as Weapon
	if new_w == null:
		push_warning("equip_legendary: 场景根节点不是 Weapon")
		return
	new_w.unlocked = true
	add_child(new_w)
	new_w.visible = false
	new_w.set_process(false)
	new_w.depleted.connect(_on_weapon_depleted.bind(new_w))
	weapons.append(new_w)

	weapon_unlocked.emit(new_w)

# 备弹补满（intermission 阶段调）：所有解锁的非传说武器
func refill_all_reserves() -> void:
	for w in weapons:
		if w.unlocked and not w.is_legendary:
			w.refill_reserve()

# UpgradeManager 改 mag_size_mult 后调，让当前武器立即同步 HUD
func notify_ammo_recompute() -> void:
	if current_weapon:
		current_weapon.current_ammo = mini(current_weapon.current_ammo, current_weapon.max_ammo())
		current_weapon.ammo_changed.emit(
			current_weapon.current_ammo,
			current_weapon.reserve_ammo,
			current_weapon.max_ammo()
		)

# ========== 传说武器空弹丢弃 ==========
# weapon.depleted 信号（current+reserve 全空）触发：从栏中移除 + 切回上一把已解锁武器
func _on_weapon_depleted(weapon: Weapon) -> void:
	if not weapon.discard_on_empty:
		return
	var idx: int = weapons.find(weapon)
	if idx < 0:
		return
	# 找上一把可用武器（优先低索引，通常是 pistol）
	var fallback_idx: int = -1
	for i in range(weapons.size()):
		if i != idx and weapons[i].unlocked:
			fallback_idx = i
			break
	weapons.remove_at(idx)
	weapon.queue_free()
	if fallback_idx >= 0:
		# 删除一项后索引可能位移
		if fallback_idx > idx:
			fallback_idx -= 1
		current_weapon = null
		current_index = -1
		equip(fallback_idx)
