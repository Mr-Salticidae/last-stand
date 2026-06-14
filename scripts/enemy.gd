class_name Enemy extends CharacterBody3D

# Dev: 隐藏热键 Ctrl+Shift+H 置 true，已存活敌人立即开、之后每波新生成的敌人
# _ready 时自动开 hitbox 可视化（红=BodyHitbox 蓝=HeadHitbox）。重开关卡清除。
static var debug_hitbox_viz: bool = false
var _hitbox_viz_on: bool = false

# ========== 数值配置 ==========
@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 3.5
@export var stop_distance: float = 1.5   # 扑击模式下未使用，保留给未来"远程型"敌人等行为
@export var flash_duration: float = 0.15 # 受击闪红时长（秒）

@export_group("Loot")
@export var health_pack_drop_chance: float = 0.3
@export var legendary_drop_chance: float = 0.0     # 传说武器掉落概率（Grunt/Runner=0, Brute=2%, Elite=30%, Boss=100%）
@export var score_value: int = 100                 # 击杀得分（Grunt 基准；变种在 tscn 里覆盖）

@export_group("Tier")
@export var is_elite: bool = false                 # 精英：供 weapon "精英猎手"加成识别
@export var is_boss: bool = false                  # BOSS：同上
# 敌种 id：grunt / runner / brute / boss 等。"猎手本能"按 id 累计击杀加伤
@export var enemy_id: String = "grunt"

@export_group("AI")
# 视野四重判定：水平距离 + 高度差 + 正前方夹角 + raycast 墙体遮挡
@export var sight_range: float = 15.0            # 视野距离（水平）
@export var sight_angle_deg: float = 110.0       # 视野锥总夹角（单边 55°）
@export var sight_height_max: float = 4.0        # 垂直视野限制（防空中/深坑误判）
# 亲眼发现玩家 / 被击中时告警周围敌人（水平距离，忽略高度差）
@export var alert_radius: float = 18.0
# 失去视野后的搜索行为
@export var search_move_speed: float = 3.0      # 朝最后已知位置移动的速度（略高于巡逻、低于追击）
@export var search_linger: float = 3.0          # 到达最后已知位置后站定等待秒数
# 侧翼偏移：追击时目标点横向偏离玩家一段距离，让同方向来的多只敌人形成散兵线而非一列纵队
# Runner 偏移大（绕侧翼），Elite/Boss 偏移小（主 menace 直冲），近身 3m 内自动归零（直扑收尾）
@export var flank_offset_max: float = 2.0

@export_group("Attack")
# 扑击节奏：distance ≤ attack_range → WINDUP（前摇 attack_windup 秒，身体警示色脉动）
# → STRIKE（瞬时判定，仍在 attack_range 内即命中）→ COOLDOWN（attack_cooldown 秒）→ CHASE
# MISS 额外加 attack_miss_bonus_cooldown，作为玩家闪避成功的奖励
@export var attack_range: float = 1.6
@export var attack_damage: float = 12.0
@export var attack_windup: float = 0.5             # 前摇（玩家闪避/反击窗口）
@export var attack_cooldown: float = 1.2           # 命中后的基础冷却
@export var attack_miss_bonus_cooldown: float = 0.5 # 闪避奖励：MISS 追加冷却
@export var attack_tell_pulse_hz: float = 6.0      # 前摇警示色脉冲频率（Hz）
@export var max_attack_height_diff: float = 2.5    # 敌人/玩家 y 差超过此值视为不在同一层，不攻击

@export_group("Safety")
@export var fall_death_y: float = -20.0            # y 低于此值自动销毁（防虚空幽灵继续作祟）

# 飞行型敌人（EyeDrone 等）：关重力、不走 navmesh、直线追玩家、维持玩家头顶上方高度
# 破除"高地无敌点"——地面单位被 navmesh 困住时，飞行单位仍能直达玩家
@export_group("Flying")
@export var is_flying: bool = false
@export var fly_height_offset: float = 1.5  # 在玩家中心上方 N 米悬停（避免穿过玩家视野中心）
@export var fly_height_lerp_rate: float = 4.0  # 高度跟随响应速度（越大越激进）

# 状态机 → GLTF AnimationPlayer 动画名映射。每个 variant tscn override 自己的命名
# （Mech Pack 用 Punch/Death，Sci-Fi Kit 用 Attack/TurnOff），空字符串表示无对应动画跳过播放
@export_group("Animation")
@export var anim_idle: String = ""
@export var anim_walk: String = ""        # SEARCH 慢速；CHASE fallback when run 为空
@export var anim_run: String = ""         # CHASE 快速首选
@export var anim_attack: String = ""      # WINDUP 前摇
@export var anim_death: String = ""       # _die 倒地动画

# 前摇警示色（HDR > 1 让它在 tonemap 下微微发光）
const ATTACK_TELL_COLOR: Color = Color(1.4, 0.9, 0.25)
# 射线源/目标高度：敌人眼睛 + 玩家胸部，避免射线从脚底开始被地面误挡
const EYE_HEIGHT: float = 1.85
const PLAYER_TARGET_HEIGHT: float = 1.5
const HEALTH_PACK_SCENE: PackedScene = preload("res://scenes/health_pack.tscn")
const LEGENDARY_PICKUP_SCENE: PackedScene = preload("res://scenes/legendary_pickup.tscn")
# 传说武器抽奖池：50/50 重机枪 vs 电磁炮（后续可以加新成员）
# 注意：用 load() 而非 preload()，避免编译时和 weapon.gd 的 uid 注册顺序冲突
# （preload heavy_mg/railgun → 间接引用 weapon.gd uid，但 main_menu 阶段 uid_cache 尚未填充）
var LEGENDARY_POOL: Array[PackedScene] = [
	load("res://scenes/weapons/heavy_mg.tscn"),
	load("res://scenes/weapons/railgun.tscn"),
]

# 全局攻击互锁：同一时刻最多 N 只敌人进入 WINDUP（"AI 攻击欲望"）
# N 由 Settings.get_difficulty_param("max_concurrent_attackers") 提供：宽松=1 / 标准=2 / 拼命=3
# 单 slot 时多敌到 attack_range 只 1 只 windup 其他原地等待 → 观感"AI 不打玩家"
const MAX_CONCURRENT_ATTACKERS_FALLBACK: int = 2  # Settings 不可用时兜底（开发期/测试场景）
static var _active_attackers: Array[Enemy] = []

# ========== 节点引用 ==========
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
var _anim_player: AnimationPlayer = null
var _current_anim: String = ""

# ========== 状态机 ==========
# IDLE: 原地站岗，做视野检测；看到玩家 → CHASE 并告警
# CHASE: 追击玩家，每帧 look_at + 视野检测；丢失视野 → SEARCH
# SEARCH: 走向最后已知位置，到达后 linger 秒 → IDLE；期间重新看到 → CHASE
# WINDUP / COOLDOWN: 攻击子循环，独立于感知
enum State { IDLE, CHASE, SEARCH, WINDUP, COOLDOWN, RETREAT, LUNGE }

# ========== 运行时状态 ==========
var current_health: float
var _is_dead: bool = false
var _player: Node3D
var _flash_timer: float = 0.0
# 每个元素 = [material, original_color]；受击闪红 / 攻击预警共用这份副本
var _flash_cache: Array = []
# DOOM 风 2D 精灵敌人：视觉是 Sprite3D 而非 MeshInstance3D，没有材质 albedo
# 可改，闪红/预警改 modulate。每个元素 = [Sprite3D, original_modulate]
var _flash_sprites: Array = []

var _state: int = State.IDLE
var _state_timer: float = 0.0
var _tell_elapsed: float = 0.0
# stagger 计时：> 0 期间敌人完全冻结（"重型压制"升级触发）
var _stagger_timer: float = 0.0

# 感知状态
var _initial_forward: Vector3 = Vector3.FORWARD  # IDLE 朝向（_ready 时记录；SEARCH→IDLE 时更新）
var _last_known_player_pos: Vector3 = Vector3.ZERO
var _search_target: Vector3 = Vector3.ZERO
var _search_arrived: bool = false
var _search_linger_timer: float = 0.0

# 导航：path 缓存 + Pure Pursuit + progress_seg 单调推进（抗 repath 震荡）
var _nav_path: PackedVector3Array = []
var _nav_path_target: Vector3 = Vector3.ZERO
var _nav_repath_timer: float = 0.0
var _nav_progress_seg: int = 0                # 当前在 path 的第几段，只增不减（repath 时 smart 重置）
const _NAV_REPATH_INTERVAL: float = 1.5   # repath 间隔拉长，避免 path[1] 波动导致震荡
const _NAV_REPATH_TARGET_DELTA: float = 3.0  # target 变化超过 3m 才强制 repath
const _NAV_LOOKAHEAD: float = 1.5
# 转向低通平滑：近身/拥挤时 nav_dir 易每帧翻向，直接用会"原地抽搐"。
# 平滑后的朝向用于 velocity + look_at，消除高频抖动（玩家反馈 #4）
var _nav_smooth_dir: Vector3 = Vector3.ZERO
const _NAV_STEER_SMOOTH: float = 0.3   # 每物理帧朝目标方向 lerp 的比例（越小越平滑、转向越缓）

# Stuck detection：CHASE/SEARCH 中卡住超过 _STUCK_TIMEOUT 秒就强制 repath + jitter
var _stuck_timer: float = 0.0
var _stuck_last_pos: Vector3 = Vector3.ZERO
const _STUCK_TIMEOUT: float = 1.5
const _STUCK_DIST: float = 0.3

# 侧翼偏移：生成时随机，玩家大幅移动时重算，用来让群体自然拉开散兵线
var _lateral_offset: float = 0.0
var _lateral_ref_player_pos: Vector3 = Vector3.ZERO
var _has_lateral_ref: bool = false
const _LATERAL_REFRESH_DIST: float = 5.0
# 收尾距离：敌人与玩家 < _FLANK_CLOSE_DIST 时偏移归零，直扑玩家
const _FLANK_CLOSE_DIST: float = 3.0

# 敌人互推：近身时横向推开，避免多只叠在同一格
const _SEPARATION_RADIUS: float = 0.9
const _SEPARATION_STRENGTH: float = 5.0

# v0.4-B B4：Runner 穿插行为参数（仅极限档启用）
# RUNNER_FLANK_DISTANCE：Runner 目标点 = 玩家身后 N 米
# RUNNER_FLANK_NAV_TOLERANCE：身后目标 snap 到 navmesh 容差，超过此值视为"身后不可达"fallback
const RUNNER_FLANK_DISTANCE: float = 3.5
const RUNNER_FLANK_NAV_TOLERANCE: float = 2.0
# v0.4-B B1：Grunt 包抄行为参数（仅极限档启用）
# 每只 grunt _ready 时随机抽 ±120° 内的角度作为"自己的包抄方位"，生命周期内不变
# 目标点 = 玩家位置 + (玩家面向方向 旋转 grunt_angle) × GRUNT_FLANK_RADIUS
# ±120° 覆盖玩家前 240° 弧（侧后包入），跟 runner 的"身后 180°"形成层次
const GRUNT_FLANK_RADIUS: float = 5.0
const GRUNT_FLANK_ANGLE_MAX_DEG: float = 120.0
const GRUNT_FLANK_NAV_TOLERANCE: float = 2.5
var _grunt_flank_angle_rad: float = 0.0  # _ready 时随机分配
# v0.4-B B3：撤退反扑（brute/elite，仅极限档启用）
# HP 跌破 50% 时一次性触发：后撤 1s（远离玩家方向，速度 ×0.8）→ CHASE → 下次 windup ×0.7 报复
const _RETREAT_DURATION: float = 1.0
const _RETREAT_HP_THRESHOLD: float = 0.5
const _RETREAT_SPEED_MULT: float = 0.8
const _RETREAT_WINDUP_SPEEDUP: float = 0.7
var _has_retreated: bool = false              # 一次 lifetime 只反扑一次
var _retreat_attack_speedup: bool = false     # RETREAT 结束后下次 windup ×0.7 标志位

# v0.4-B B7：所有近战敌人 LUNGE 冲撞攻击（boss 除外，仅极限档启用）
# WINDUP 抬手时锁定玩家位置 → strike 不再瞬时点判定，进入 LUNGE 朝锁定方向高速冲 0.3s
# 玩家 windup 时侧移 → LUNGE 冲到的位置玩家不在 → 落空（必须侧闪而非后退）
# LUNGE 期间持续检测玩家碰撞，命中后 hit_radius 内即触发伤害
const _LUNGE_DURATION: float = 0.3
const _LUNGE_SPEED_MULT: float = 2.5            # 冲撞速度 = move_speed × 2.5
const _LUNGE_HIT_RADIUS: float = 1.2            # 持续命中检测半径
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_did_hit: bool = false

# v0.4-B B5-A：Boss phase 系统（仅 boss + 极限档启用）
# Phase 1 (HP > 60%)：现有近战行为
# Phase 2 (30% < HP ≤ 60%)：每 10s 召唤 2 只 grunt 增援
# Phase 3 (HP ≤ 30%)：狂暴——move_speed ×1.4，attack_windup ×0.6
const BOSS_PHASE2_HP_THRESHOLD: float = 0.6
const BOSS_PHASE3_HP_THRESHOLD: float = 0.3
const BOSS_SUMMON_INTERVAL: float = 10.0
const BOSS_SUMMON_COUNT: int = 2
const BOSS_SUMMON_RADIUS: float = 3.0           # 召唤位置 = boss 周围 3m
const BOSS_PHASE3_SPEED_MULT: float = 1.4
const BOSS_PHASE3_WINDUP_MULT: float = 0.6
const BOSS_SUMMON_SCENE: PackedScene = preload("res://scenes/enemy_grunt.tscn")
# v0.4-B B5-B：Boss 远程投射物（防"玩家爬塔顶 boss 够不到"）
# CD 2s（用户测试反馈频率提高），距离 > 8m 才 fire，起手等 2s 给玩家近战感受
const BOSS_RANGED_COOLDOWN: float = 2.0
# 8 → 6：穷追的 boss 很快进近战，>8m 窗口太窄玩家根本没见过紫球；放宽射程门槛
const BOSS_RANGED_MIN_DISTANCE: float = 6.0
const BOSS_PROJECTILE_DAMAGE_MULT: float = 0.6
const BOSS_PROJECTILE_SCENE: PackedScene = preload("res://scenes/boss_projectile.tscn")
var _boss_phase: int = 1
var _boss_summon_timer: float = 0.0
var _boss_phase3_applied: bool = false           # Phase 3 狂暴 buff 已应用标记
var _boss_ranged_timer: float = BOSS_RANGED_COOLDOWN  # 起手 4s CD（不立刻 fire）

# 飞行型（Elite）雷霆走位：CHASE 中朝玩家逼近时叠加垂直于视线的正弦横摆，
# 让小体型飞球成为难打的灵活目标（而非直线肉盾）。近身线性淡出确保仍能收尾扑击。
# 玩家反馈："漂浮球体型不该是肉盾，灵活+低血才显得弹道收束升级有用"
const _FLY_WEAVE_AMPLITUDE: float = 3.2
const _FLY_WEAVE_HZ: float = 0.9
const _FLY_WEAVE_FADE_RANGE: float = 6.0  # 距离从 _FLANK_CLOSE_DIST 到 +6m 之间摆幅线性 0→满
var _fly_weave_t: float = 0.0
var _fly_weave_phase: float = 0.0  # _ready 随机，让多只飞球相位错开不同步

# DOOM 单面精灵程序动效：靠浮动/呼吸/受击挤压/死亡溶解让静态扁片"活"起来
# （试点结论：静态精灵太简陋，先验证加动效后是否成立，再决定走精灵还是回 3D）
var _juice_sprite: Sprite3D = null
var _juice_base_pos: Vector3 = Vector3.ZERO
var _juice_base_scale: Vector3 = Vector3.ONE
var _juice_t: float = 0.0
var _juice_hit_timer: float = 0.0
const _JUICE_BOB_AMP: float = 0.13
const _JUICE_BOB_HZ: float = 0.9
const _JUICE_BREATH_AMT: float = 0.045
const _JUICE_BREATH_HZ: float = 0.65
const _JUICE_HIT_DURATION: float = 0.18
const _JUICE_WINDUP_GROW: float = 0.16
# 路径B 增强程序动效：走路步频 + 攻击前刺（纯代码，无新资产）
var _walk_phase: float = 0.0          # 步频相位（按移动速度推进）
var _walk_amt: float = 0.0            # 走路动效混入量 0→1（移动平滑淡入/停止淡出）
var _juice_strike_timer: float = 0.0  # 攻击 strike 瞬间的前刺 impulse 计时
const _GAIT_HOP: float = 0.11         # 腾空上跳幅度（蹦跳步态，取代旧的左右摆）
const _GAIT_PLANT_DIP: float = 0.05   # 落脚下沉幅度（配挤压给重量感）
const _GAIT_SQUASH: float = 0.11      # 落脚横撑纵压
const _GAIT_STRETCH: float = 0.06     # 腾空纵向拉伸
const _GAIT_LURCH: float = 0.10       # 落脚向玩家前冲幅度（本地 -Z，步步紧逼的压迫感）
const _STRIKE_DURATION: float = 0.22  # 前刺 impulse 时长
const _STRIKE_LUNGE: float = 0.35     # 前刺朝玩家位移幅度

# 路径B 逐帧贴图动画（DOOM 双帧抖）：在程序 juice 之上叠加切帧
# 约定：精灵贴图 res://.../<name>.png 旁若存在同名文件夹 res://.../<name>/，
#       内含 walk_0..N / attack_0..N / death_0..N（按需），则启用帧动画；
#       否则 _has_frame_anim=false，退回单张静态图（与改动前完全一致，零破坏）。
# 走路帧与落脚相位 _walk_phase 同步（每半步 π 翻一帧），前摇切攻击帧，死亡切倒地帧。
var _frames_walk: Array[Texture2D] = []
var _frames_attack: Array[Texture2D] = []
var _frames_death: Array[Texture2D] = []
var _frame_idle: Texture2D = null     # 静止/默认帧（= 原始单张图）
var _has_frame_anim: bool = false
const _FRAME_SEQ_CAP: int = 32        # 单 clip 帧数安全上限

signal died

func _ready() -> void:
	current_health = max_health
	_find_player()
	# 每只敌人独立随机侧翼偏移（含符号），让同方向来的多只自然分左/中/右
	if flank_offset_max > 0.0:
		_lateral_offset = randf_range(-flank_offset_max, flank_offset_max)
	# v0.4-B B1：grunt 包抄角度（±120° 内随机抽，整个 lifetime 不变，让 N 只 grunt 自然分布在玩家周围弧上）
	if enemy_id == "grunt":
		var max_rad: float = deg_to_rad(GRUNT_FLANK_ANGLE_MAX_DEG)
		_grunt_flank_angle_rad = randf_range(-max_rad, max_rad)
	_fly_weave_phase = randf() * TAU

	# 记录初始朝向作为 IDLE 姿态（world.tscn 里的 transform 决定敌人开局面朝哪）
	_initial_forward = -global_transform.basis.z
	_initial_forward.y = 0.0
	if _initial_forward.length_squared() < 0.001:
		_initial_forward = Vector3.FORWARD
	else:
		_initial_forward = _initial_forward.normalized()

	# 复制材质副本，避免多个敌人实例共享材质导致集体变色
	# 递归扫整个子树，兼容旧 capsule+box 占位和新 GLTF 模型（含 Skeleton 下的多 MeshInstance3D）
	_collect_flash_cache_from(self)

	# GLTF 自带 AnimationPlayer 一般在 model 子树里，递归找
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer

	# 精灵敌人：抓首个 Sprite3D 作程序动效目标，记录基准 transform（动效在其之上叠加）
	if not _flash_sprites.is_empty():
		_juice_sprite = _flash_sprites[0][0]
		_juice_base_pos = _juice_sprite.position
		_juice_base_scale = _juice_sprite.scale
		_load_frame_sets()

	if Enemy.debug_hitbox_viz:
		enable_hitbox_viz()

func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D

# Dev tool: 给所有 hitbox 子节点的 BoxShape3D 生成同 size/position 的半透明 mesh
# BodyHitbox = 红色，HeadHitbox = 蓝色。让 hitbox 范围在运行时可见，方便对照视觉模型调
# 由 wave_manager debug spawn 路径调用。封版保留，供未来调新敌人 hitbox 用。
func enable_hitbox_viz() -> void:
	if _hitbox_viz_on:
		return
	_hitbox_viz_on = true
	for area_child in get_children():
		if not (area_child is Area3D):
			continue
		var is_head: bool = (area_child as Node).name.to_lower().contains("head")
		var color: Color = Color(0.2, 0.4, 1.0, 0.35) if is_head else Color(1.0, 0.3, 0.3, 0.35)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for shape_child in area_child.get_children():
			if not (shape_child is CollisionShape3D):
				continue
			var cs: CollisionShape3D = shape_child
			var viz_mesh: Mesh = _make_viz_mesh_for_shape(cs.shape)
			if viz_mesh == null:
				continue
			var viz: MeshInstance3D = MeshInstance3D.new()
			viz.mesh = viz_mesh
			viz.transform = cs.transform
			viz.material_override = mat
			area_child.add_child(viz)

# Box / Cylinder 支持（其他 shape 类型按需扩展）
func _make_viz_mesh_for_shape(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = (shape as BoxShape3D).size
		return bm
	if shape is CylinderShape3D:
		var cyl: CylinderShape3D = shape
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = cyl.radius
		cm.bottom_radius = cyl.radius
		cm.height = cyl.height
		return cm
	if shape is SphereShape3D:
		var sm: SphereMesh = SphereMesh.new()
		var r: float = (shape as SphereShape3D).radius
		sm.radius = r
		sm.height = r * 2.0
		return sm
	return null

# 递归收集子树里所有 MeshInstance3D 的 BaseMaterial3D 副本
# 既支持基类 enemy.tscn 的 body/head 占位（surface_override material），
# 也支持继承场景里 instance 的 GLTF 模型（mesh 自带 surface material）
# 收到的副本写回 surface_override，运行时改 albedo_color 实现闪红 / 警示色脉冲
func _collect_flash_cache_from(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh != null:
				var surface_count: int = mi.mesh.get_surface_count()
				for i in surface_count:
					var mat: Material = mi.get_surface_override_material(i)
					if mat == null:
						mat = mi.mesh.surface_get_material(i)
					if mat is BaseMaterial3D:
						var unique_mat: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
						mi.set_surface_override_material(i, unique_mat)
						_flash_cache.append([unique_mat, unique_mat.albedo_color])
		elif child is Sprite3D:
			var spr: Sprite3D = child
			_flash_sprites.append([spr, spr.modulate])
		_collect_flash_cache_from(child)

# 供 HUD 威胁指示器查询：当前是否在攻击前摇（即将出拳）
func is_winding_up() -> bool:
	return _state == State.WINDUP and not _is_dead

# 供 weapon 判击杀反馈
func is_dead() -> bool:
	return _is_dead

# 供玩家近战处决：boss 不可处决（HP 墙），其余存活敌人均可
func is_executable() -> bool:
	return not _is_dead and not is_boss

# 处决致死：绕过 HP / 伤害结算，直接走标准死亡流程（掉落 + 死亡动画）
func die_by_execution() -> void:
	if _is_dead:
		return
	_die()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return


	# 虚空清理：掉出关卡范围的敌人立即销毁
	# 必须先 emit died 让 wave_manager 移除引用，否则 _alive_enemies 留 invalid 节点
	# 永远不空 → 推不下一波 = 幽灵怪 progression blocker
	if global_position.y < fall_death_y:
		_release_attack_lock()
		if not _is_dead:
			_is_dead = true
			died.emit()
		queue_free()
		return

	# 受击闪红计时（优先级最高：盖过攻击警示色脉冲）
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_restore_colors()

	# Stagger：完全冻结 AI 与移动（玩家"重型压制"触发，仅 elite/boss）
	# 闪红仍正常显示；fall_death_y 在前面已经处理过
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# 玩家可能还没 ready，延迟查找
	if _player == null:
		_find_player()
		return

	# 分离水平距离 / 高度差
	var raw_to_player: Vector3 = _player.global_position - global_position
	var height_diff: float = raw_to_player.y
	var to_player: Vector3 = raw_to_player
	to_player.y = 0.0
	var distance: float = to_player.length()

	# v0.4-B B5-A：Boss Phase 2 召唤计时（与 state 解耦，CHASE/WINDUP/COOLDOWN/RETREAT 都跑）
	if is_boss and _boss_phase == 2:
		_boss_summon_timer -= delta
		if _boss_summon_timer <= 0.0:
			_summon_grunts(BOSS_SUMMON_COUNT)
			_boss_summon_timer = BOSS_SUMMON_INTERVAL

	# v0.4-B B5-B：Boss 远程投射物（仅 boss + 极限档）
	# CHASE/COOLDOWN 中、距离 > 8m、视野通畅时 fire；防"玩家爬塔顶 boss 够不到"
	# WINDUP/LUNGE/RETREAT 不 fire（专心近战，避免边挥拳边喷球的视觉混乱）
	if is_boss and _player != null and bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
		_boss_ranged_timer -= delta
		if _boss_ranged_timer <= 0.0 and (_state == State.CHASE or _state == State.COOLDOWN):
			var ranged_dist: float = global_position.distance_to(_player.global_position)
			if ranged_dist > BOSS_RANGED_MIN_DISTANCE and _can_see_player(true):
				_fire_ranged_projectile()
				_boss_ranged_timer = BOSS_RANGED_COOLDOWN

	match _state:
		State.IDLE:
			_tick_idle()
		State.CHASE:
			_tick_chase(distance, to_player, height_diff)
		State.SEARCH:
			_tick_search(delta)
		State.WINDUP:
			_tick_windup(delta, distance)
		State.COOLDOWN:
			_tick_cooldown(delta)
		State.RETREAT:
			_tick_retreat(delta)
		State.LUNGE:
			_tick_lunge(delta)

	# 飞行型跳过 navmesh-based stuck detection 和敌人互推（飞行单位无地面约束）
	if not is_flying:
		# Stuck detection：追击 / 未到达的搜索中 1.5s 没移动 → 强制 repath + jitter
		# 跳过"到达后 linger"状态（那是预期的停驻）
		var active_movement: bool = (
			_state == State.CHASE
			or (_state == State.SEARCH and not _search_arrived)
		)
		if active_movement:
			if global_position.distance_to(_stuck_last_pos) < _STUCK_DIST:
				_stuck_timer += delta
				if _stuck_timer >= _STUCK_TIMEOUT:
					_nav_path.clear()
					_nav_repath_timer = 0.0
					_nav_progress_seg = 0
					_stuck_timer = 0.0
					# 给一个随机方向的小冲量跳出卡死
					velocity.x += randf_range(-2.5, 2.5)
					velocity.z += randf_range(-2.5, 2.5)
			else:
				_stuck_timer = 0.0
				_stuck_last_pos = global_position
		else:
			_stuck_timer = 0.0
			_stuck_last_pos = global_position

		# 敌人互推：仅在追击/搜索中生效（IDLE/WINDUP/COOLDOWN 不推，避免站桩被挤走）
		if _state == State.CHASE or _state == State.SEARCH:
			_apply_enemy_separation()

	# 重力 vs 高度跟随
	if is_flying:
		# 飞行型：根据状态决定目标高度，PD 控制 velocity.y 让它平滑接近
		var target_y: float = global_position.y
		if _player and (_state == State.CHASE or _state == State.WINDUP or _state == State.COOLDOWN):
			target_y = _player.global_position.y + fly_height_offset
		elif _state == State.SEARCH:
			target_y = _search_target.y + fly_height_offset
		velocity.y = clamp((target_y - global_position.y) * fly_height_lerp_rate, -move_speed, move_speed)
	elif not is_on_floor():
		velocity += get_gravity() * delta

	_update_sprite_juice(delta)
	_update_anim()
	move_and_slide()

# 状态机驱动 GLTF 动画。每帧调，内部去重避免重复 play 同一个
# CHASE 优先 run，没有就 walk fallback；SEARCH 用 walk；WINDUP 用 attack；其余 idle
func _update_anim() -> void:
	if _anim_player == null:
		return
	var target: String = ""
	match _state:
		State.IDLE:
			target = anim_idle
		State.CHASE:
			target = anim_run if not anim_run.is_empty() else anim_walk
		State.SEARCH:
			target = anim_walk if not anim_walk.is_empty() else anim_idle
		State.WINDUP:
			target = anim_attack
		State.COOLDOWN:
			target = anim_idle
	_play_anim(target)

# 单面精灵程序动效：基准 transform 上叠加 浮动 + 呼吸缩放 + 受击挤压 + 前摇胀大
# 不碰 modulate（那归受击闪红/攻击预警系统所有）。死亡动效另由 _play_death_sequence 接管
func _update_sprite_juice(delta: float) -> void:
	if _juice_sprite == null:
		return
	_juice_t += delta
	if _juice_hit_timer > 0.0:
		_juice_hit_timer -= delta
	if _juice_strike_timer > 0.0:
		_juice_strike_timer -= delta
	var ph: float = _fly_weave_phase
	var bob: float = sin((_juice_t + ph) * TAU * _JUICE_BOB_HZ) * _JUICE_BOB_AMP
	var breath: float = 1.0 + sin((_juice_t + ph) * TAU * _JUICE_BREATH_HZ) * _JUICE_BREATH_AMT
	var scale_mod: Vector3 = Vector3(breath, breath, breath)
	var offset: Vector3 = Vector3(0.0, bob, 0.0)
	# 走路步频（路径B）：移动时叠加 落脚颠簸 + 横向摆 + 落脚挤压，平滑淡入/淡出
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = (_state == State.CHASE or _state == State.SEARCH) and horiz_speed > 0.4 and not is_flying
	_walk_amt = lerpf(_walk_amt, 1.0 if moving else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if _walk_amt > 0.001:
		_walk_phase += delta * (5.0 + horiz_speed * 1.1)  # 越快步频越急
		# 蹦跳步态：apex=腾空(1)…plant=落脚(0)。去掉旧的纯横摆，换“跳起→落脚砸”的重量感
		var apex: float = absf(sin(_walk_phase))
		var plant: float = 1.0 - apex
		var amt: float = _walk_amt
		# 垂直：腾空上跳 + 落脚下沉
		offset.y += (apex * _GAIT_HOP - plant * _GAIT_PLANT_DIP) * amt
		# 落脚瞬间向玩家(本地 -Z)前冲一下，读作步步紧逼
		offset.z -= plant * _GAIT_LURCH * amt
		# 挤压拉伸：落脚横撑纵压、腾空纵拉，给“肉感”和重量
		var sx: float = 1.0 + plant * _GAIT_SQUASH * amt - apex * _GAIT_STRETCH * 0.4 * amt
		var sy: float = 1.0 - plant * _GAIT_SQUASH * 0.8 * amt + apex * _GAIT_STRETCH * amt
		scale_mod *= Vector3(sx, sy, sx)
	# 受击挤压：横撑纵压，快速衰减（被打"咯噔"一下）
	if _juice_hit_timer > 0.0:
		var k: float = _juice_hit_timer / _JUICE_HIT_DURATION
		scale_mod *= Vector3(1.0 + 0.28 * k, 1.0 - 0.22 * k, 1.0 + 0.28 * k)
	# 攻击前摇：随 windup 进度逐渐胀大，强化"要出手"预兆（叠加在颜色脉冲之上）
	if _state == State.WINDUP and attack_windup > 0.0:
		var wp: float = clampf(1.0 - _state_timer / attack_windup, 0.0, 1.0)
		scale_mod *= 1.0 + _JUICE_WINDUP_GROW * wp
	# 攻击前刺（路径B）：strike 瞬间朝玩家(-Z 本地)快速突刺 + scale 弹一下，半程冲半程收
	if _juice_strike_timer > 0.0:
		var s: float = _juice_strike_timer / _STRIKE_DURATION   # 1→0
		var lunge: float = sin(s * PI)                          # 0→1→0 冲出再收回
		offset.z -= lunge * _STRIKE_LUNGE
		scale_mod *= 1.0 + 0.18 * lunge
	_juice_sprite.position = _juice_base_pos + offset
	_juice_sprite.scale = _juice_base_scale * scale_mod
	# 程序变换敲定后再选帧（_walk_phase 此刻已是最新，走路帧才能与落脚同步）
	_update_sprite_frame()

# 启动期扫描约定文件夹，按 clip 装载帧序列；找不到则保持静态（_has_frame_anim=false）
func _load_frame_sets() -> void:
	if _juice_sprite == null:
		return
	var tex: Texture2D = _juice_sprite.texture
	if tex == null:
		return
	_frame_idle = tex
	var src: String = tex.resource_path     # 例：res://assets/sprites/enemies/grunt.png
	if src.is_empty():
		return
	var base_dir: String = src.get_basename()  # 去扩展名 → res://assets/sprites/enemies/grunt
	_frames_walk = _load_frame_seq(base_dir, "walk")
	_frames_attack = _load_frame_seq(base_dir, "attack")
	_frames_death = _load_frame_seq(base_dir, "death")
	_has_frame_anim = not (_frames_walk.is_empty() and _frames_attack.is_empty() and _frames_death.is_empty())

# 从 base_dir 顺序探测 <clip>_0.png, <clip>_1.png … 直到缺失。ResourceLoader.exists 导出安全
func _load_frame_seq(base_dir: String, clip: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var i: int = 0
	while i < _FRAME_SEQ_CAP:
		var p: String = "%s/%s_%d.png" % [base_dir, clip, i]
		if not ResourceLoader.exists(p):
			break
		var t: Texture2D = load(p) as Texture2D
		if t == null:
			break
		out.append(t)
		i += 1
	return out

# 每帧按状态选贴图：前摇攻击 > 移动走路 > 静止默认。死亡帧由 _play_death_sequence 接管
func _update_sprite_frame() -> void:
	if not _has_frame_anim or _juice_sprite == null or _is_dead:
		return
	# 前摇：按 windup 进度推进攻击帧（通常 1-2 帧，到位即举手/张口）
	if _state == State.WINDUP and not _frames_attack.is_empty():
		var wp: float = 1.0
		if attack_windup > 0.0:
			wp = clampf(1.0 - _state_timer / attack_windup, 0.0, 1.0)
		var ai: int = clampi(int(wp * _frames_attack.size()), 0, _frames_attack.size() - 1)
		_juice_sprite.texture = _frames_attack[ai]
		return
	# 移动：双帧抖，与落脚相位同步（_walk_phase 每过 π = 一次落脚 = 翻一帧）
	if _walk_amt > 0.5 and not _frames_walk.is_empty():
		var wi: int = int(_walk_phase / PI) % _frames_walk.size()
		_juice_sprite.texture = _frames_walk[wi]
		return
	# 静止 / 无走路帧：回默认帧
	_juice_sprite.texture = _frame_idle

func _play_anim(anim_name: String, force: bool = false) -> void:
	if _anim_player == null or anim_name.is_empty():
		return
	if not _anim_player.has_animation(anim_name):
		return
	if not force and _current_anim == anim_name and _anim_player.is_playing():
		return
	_anim_player.play(anim_name)
	_current_anim = anim_name

# ---------- 状态 tick ----------
func _tick_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	# 保持初始朝向（不追玩家）
	look_at(global_position + _initial_forward, Vector3.UP)

	# SEARCH→IDLE 后的敌人不再局限视野锥，改为全向警觉（距离+raycast 判定）
	# 避免玩家站在 IDLE 敌人视野锥外但还在 sight_range 内时被忽略
	if _can_see_player(true):
		_last_known_player_pos = _player.global_position
		_state = State.CHASE
		_alert_nearby_enemies()

func _tick_chase(distance: float, to_player: Vector3, height_diff: float) -> void:
	# 视野检查：CHASE 中 forward 朝 nav_dir 不朝玩家，用 ignore_angle 只判距离+高度+raycast
	# 只有墙遮挡才会让敌人"丢失视野"切 SEARCH
	if _can_see_player(true):
		_last_known_player_pos = _player.global_position
	elif is_boss:
		# Boss 永不"索敌索不着"：一旦交战就持续锁定玩家真实位置穷追，绝不切 SEARCH
		# 破"躲墙角清完小兵拿 AK 把沙包 boss 突突死"的体验（玩家反馈）
		_last_known_player_pos = _player.global_position
	else:
		var new_target: Vector3 = _last_known_player_pos
		# 只有 search_target 大幅变动才 reset arrived；target 稳定时保持 linger 状态
		# 防止 CHASE/SEARCH 频繁切换导致 linger_timer 永远走不完
		if _search_target.distance_to(new_target) > 1.5:
			_search_arrived = false
		_search_target = new_target
		_state = State.SEARCH
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# 攻击判定：水平近 + 高度同层。在攻击距离内直接朝玩家、准备开打
	var in_range: bool = distance <= attack_range and absf(height_diff) <= max_attack_height_diff
	if in_range:
		if distance > 0.01:
			look_at(global_position + to_player, Vector3.UP)
		if _can_claim_attack_lock():
			if not _active_attackers.has(self):
				_active_attackers.append(self)
			_enter_windup()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		return

	# 飞行型直线追击（不走 navmesh，破除高地无敌点）；地面型用 nav path + 散兵线偏移
	if is_flying:
		_move_flying_toward(_compute_fly_chase_target(distance), move_speed)
	else:
		_move_along_nav_path(_compute_chase_target(to_player, distance), move_speed)

func _tick_search(delta: float) -> void:
	# 视野优先：重新发现玩家 → CHASE（不重复告警，已在 combat）
	if _can_see_player():
		_last_known_player_pos = _player.global_position
		_state = State.CHASE
		return

	if not _search_arrived:
		# 距离 < 1m 视为到达（改用直线距离，不依赖 NavigationAgent3D 的 is_navigation_finished）
		var dist_to_target: float = Vector2(
			_search_target.x - global_position.x,
			_search_target.z - global_position.z
		).length()
		if dist_to_target < 1.0:
			_search_arrived = true
			_search_linger_timer = search_linger
			velocity.x = 0.0
			velocity.z = 0.0
		elif is_flying:
			_move_flying_toward(_search_target, search_move_speed)
		else:
			_move_along_nav_path(_search_target, search_move_speed)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_search_linger_timer -= delta
		if _search_linger_timer <= 0.0:
			# 保留当前朝向作为新 IDLE 姿态（不要转回原位，更自然）
			var cur_forward: Vector3 = -global_transform.basis.z
			cur_forward.y = 0.0
			if cur_forward.length_squared() > 0.001:
				_initial_forward = cur_forward.normalized()
			_state = State.IDLE

# 敌人互推：扫邻近敌人，水平距离 < _SEPARATION_RADIUS 时给一个横向推力
# 只让活敌人之间排斥，避免多只叠在同一格（enemy 之间不互相碰撞，必须手动做）
func _apply_enemy_separation() -> void:
	var push: Vector3 = Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		if (other as Enemy)._is_dead:
			continue
		var diff: Vector3 = global_position - (other as Node3D).global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d < 0.01 or d > _SEPARATION_RADIUS:
			continue
		# 权重与距离成反比：越近推力越大（最近处接近 1，远端趋近 0）
		push += diff.normalized() * (_SEPARATION_RADIUS - d)
	if push.length_squared() > 0.0001:
		velocity.x += push.x * _SEPARATION_STRENGTH
		velocity.z += push.z * _SEPARATION_STRENGTH

# 计算追击目标点：玩家位置 + 横向偏移（right 向量 × _lateral_offset）
# 近身 _FLANK_CLOSE_DIST 内偏移归零，避免最后扑击时绕路
# 玩家大幅移动（>_LATERAL_REFRESH_DIST）时重新随机偏移方向
func _compute_chase_target(to_player: Vector3, distance: float) -> Vector3:
	# v0.4-B B4：Runner 穿插（仅极限档启用），目标 = 玩家身后 3.5m
	# 近身（<_FLANK_CLOSE_DIST）取消穿插直扑收尾，避免最后扑击时绕路
	if enemy_id == "runner" and distance >= _FLANK_CLOSE_DIST:
		if bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
			var rf_target: Vector3 = _compute_runner_flank_target()
			if rf_target != Vector3.ZERO:
				return rf_target
			# 身后被墙挡 / nav 不可达 → fallback 到下面的标准侧翼逻辑
	# v0.4-B B1：Grunt 包抄（仅极限档启用），目标 = 玩家周围 5m 圆环上的固定角度位置
	# 每只 grunt 角度在 _ready 已随机分配（±120°），N 只 grunt 自然分布在 240° 弧上
	if enemy_id == "grunt" and distance >= _FLANK_CLOSE_DIST:
		if bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
			var gf_target: Vector3 = _compute_grunt_flank_target()
			if gf_target != Vector3.ZERO:
				return gf_target

	if flank_offset_max <= 0.0 or distance < _FLANK_CLOSE_DIST:
		return _player.global_position
	# 刷新偏移：首帧或玩家位置漂移过远
	if not _has_lateral_ref or _lateral_ref_player_pos.distance_to(_player.global_position) > _LATERAL_REFRESH_DIST:
		_lateral_offset = randf_range(-flank_offset_max, flank_offset_max)
		_lateral_ref_player_pos = _player.global_position
		_has_lateral_ref = true
	var to_player_dir: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	if to_player_dir.length_squared() < 0.001:
		return _player.global_position
	to_player_dir = to_player_dir.normalized()
	var right: Vector3 = Vector3.UP.cross(to_player_dir)
	return _player.global_position + right * _lateral_offset

# v0.4-B B4：Runner 穿插目标点 = 玩家身后 RUNNER_FLANK_DISTANCE 米
# 身后向量取 player.global_transform.basis.z（Godot Z+ 是身后，Z- 是前向）
# 用 NavigationServer 检查目标是否在 navmesh 范围内（超 RUNNER_FLANK_NAV_TOLERANCE 视为不可达 → fallback）
# 不缓存：玩家朝向变化时让 nav repath 自然处理（_NAV_REPATH_TARGET_DELTA=3m 容差能吸收小幅变化）
func _compute_runner_flank_target() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var player_back: Vector3 = _player.global_transform.basis.z
	player_back.y = 0.0
	if player_back.length_squared() < 0.001:
		return Vector3.ZERO
	player_back = player_back.normalized()
	var target: Vector3 = _player.global_position + player_back * RUNNER_FLANK_DISTANCE
	# Snap 到 navmesh 上离 target 最近的点；如果 snap 距 target 太远说明身后是墙/虚空，fallback
	var map_rid: RID = get_world_3d().navigation_map
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, target)
	if snapped.distance_to(target) > RUNNER_FLANK_NAV_TOLERANCE:
		return Vector3.ZERO
	return snapped

# v0.4-B B1：Grunt 包抄目标 = 玩家周围圆环固定角度位置
# 玩家朝向作为基准（-basis.z），向左/右旋转 _grunt_flank_angle_rad 度（_ready 随机分配 ±120°）
# N 只 grunt 各自独立角度 → 自然分布在玩家前 240° 弧上 → 玩家枪线难以同时覆盖
# nav_snap 不可达（距离 > tolerance）→ 返回 ZERO 让 caller fallback 到现有 _lateral_offset
func _compute_grunt_flank_target() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var player_forward: Vector3 = -_player.global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length_squared() < 0.001:
		return Vector3.ZERO
	player_forward = player_forward.normalized()
	var direction: Vector3 = player_forward.rotated(Vector3.UP, _grunt_flank_angle_rad)
	var target: Vector3 = _player.global_position + direction * GRUNT_FLANK_RADIUS
	var map_rid: RID = get_world_3d().navigation_map
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, target)
	if snapped.distance_to(target) > GRUNT_FLANK_NAV_TOLERANCE:
		return Vector3.ZERO
	return snapped

# 飞行型雷霆走位目标：玩家位置 + 垂直视线的正弦横摆
# 远处摆幅满（难打的灵活目标），近身（< _FLANK_CLOSE_DIST）线性收敛到 0 让它能收尾扑击
func _compute_fly_chase_target(distance: float) -> Vector3:
	var base: Vector3 = _player.global_position
	if distance < _FLANK_CLOSE_DIST:
		return base
	_fly_weave_t += get_physics_process_delta_time()
	var to_p: Vector3 = base - global_position
	to_p.y = 0.0
	if to_p.length_squared() < 0.001:
		return base
	var right: Vector3 = Vector3.UP.cross(to_p.normalized())
	var fade: float = clampf((distance - _FLANK_CLOSE_DIST) / _FLY_WEAVE_FADE_RANGE, 0.0, 1.0)
	var offset: float = sin((_fly_weave_t + _fly_weave_phase) * TAU * _FLY_WEAVE_HZ) * _FLY_WEAVE_AMPLITUDE * fade
	return base + right * offset

# 飞行型直线追击：水平方向直奔目标，y 方向由 _physics_process 末尾的高度跟随控制
# 不走 navmesh = 无视墙壁绕路、无视高低差，能直达 watchtower / 浮岛上的玩家
func _move_flying_toward(target: Vector3, speed: float) -> void:
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir: Vector3 = to_target / dist
	look_at(global_position + dir, Vector3.UP)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

# Pure Pursuit：每帧求敌人在 path 上的进度（最近 segment + 参数 t），
# 朝 path 上前方 1.5m 的点走。不依赖 waypoint index 状态，彻底消除 repath 抖动。
func _move_along_nav_path(target: Vector3, speed: float) -> void:
	_nav_repath_timer -= get_physics_process_delta_time()
	var needs_repath: bool = (
		_nav_path.size() < 2
		or _nav_progress_seg >= _nav_path.size() - 1   # path 走完了立即重算，避免敌人呆站等 interval
		or _nav_repath_timer <= 0.0
		or _nav_path_target.distance_to(target) > _NAV_REPATH_TARGET_DELTA
	)
	if needs_repath:
		var map_rid: RID = get_world_3d().navigation_map
		# optimize=false 保留 polygon portal waypoint（含斜坡入口点），让 pure pursuit
		# 能引导敌人正确绕到斜坡底部而不是撞斜坡侧壁。progress_seg 防震荡，
		# stuck detection 防死锁。
		_nav_path = NavigationServer3D.map_get_path(map_rid, global_position, target, false)
		_nav_path_target = target
		_nav_repath_timer = _NAV_REPATH_INTERVAL
		# smart 重置 progress：找新 path 中离 agent 最近的 segment
		_nav_progress_seg = _find_closest_segment()

	if _nav_path.size() < 2:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var lookahead: Vector3 = _get_lookahead_point(_NAV_LOOKAHEAD)

	var nav_vec: Vector3 = lookahead - global_position
	nav_vec.y = 0.0
	if nav_vec.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var nav_dir: Vector3 = nav_vec.normalized()
	# 转向低通平滑：把每帧目标方向 lerp 进 _nav_smooth_dir，消除近身/拥挤时的方向震荡
	if _nav_smooth_dir.length_squared() < 0.0001:
		_nav_smooth_dir = nav_dir
	else:
		_nav_smooth_dir = _nav_smooth_dir.lerp(nav_dir, _NAV_STEER_SMOOTH)
		if _nav_smooth_dir.length_squared() < 0.0001:
			_nav_smooth_dir = nav_dir
		else:
			_nav_smooth_dir = _nav_smooth_dir.normalized()
	look_at(global_position + _nav_smooth_dir, Vector3.UP)
	velocity.x = _nav_smooth_dir.x * speed
	velocity.z = _nav_smooth_dir.z * speed

# Repath 时调：找 path 中离 agent 水平最近的 segment index
func _find_closest_segment() -> int:
	if _nav_path.size() < 2:
		return 0
	var pos2: Vector2 = Vector2(global_position.x, global_position.z)
	var best_seg: int = 0
	var best_dist: float = INF
	for i in range(_nav_path.size() - 1):
		var a2: Vector2 = Vector2(_nav_path[i].x, _nav_path[i].z)
		var b2: Vector2 = Vector2(_nav_path[i + 1].x, _nav_path[i + 1].z)
		var ab: Vector2 = b2 - a2
		var l2: float = ab.length_squared()
		var t: float = 0.0
		if l2 > 0.001:
			t = clamp((pos2 - a2).dot(ab) / l2, 0.0, 1.0)
		var closest: Vector2 = a2 + ab * t
		var d: float = pos2.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_seg = i
	return best_seg

# Pure Pursuit + progress_seg 单调推进：从 _nav_progress_seg 开始向前找 lookahead
# 到达 segment 末端才推进 progress，不倒退避免 repath 震荡
func _get_lookahead_point(lookahead_dist: float) -> Vector3:
	if _nav_path.size() < 2:
		return global_position
	var pos2: Vector2 = Vector2(global_position.x, global_position.z)

	# 推进 progress_seg：agent 过了当前 segment 末端（t≥0.9）就前进
	while _nav_progress_seg < _nav_path.size() - 1:
		var a2: Vector2 = Vector2(_nav_path[_nav_progress_seg].x, _nav_path[_nav_progress_seg].z)
		var b2: Vector2 = Vector2(_nav_path[_nav_progress_seg + 1].x, _nav_path[_nav_progress_seg + 1].z)
		var ab: Vector2 = b2 - a2
		var l2: float = ab.length_squared()
		if l2 < 0.001:
			_nav_progress_seg += 1
			continue
		var t: float = clamp((pos2 - a2).dot(ab) / l2, 0.0, 1.0)
		if t >= 0.9:
			_nav_progress_seg += 1
		else:
			break

	if _nav_progress_seg >= _nav_path.size() - 1:
		return _nav_path[_nav_path.size() - 1]

	# 从 (_nav_progress_seg, current_t) 沿 path 向前走 lookahead_dist
	var a: Vector3 = _nav_path[_nav_progress_seg]
	var b: Vector3 = _nav_path[_nav_progress_seg + 1]
	var a2: Vector2 = Vector2(a.x, a.z)
	var b2: Vector2 = Vector2(b.x, b.z)
	var ab: Vector2 = b2 - a2
	var l2: float = ab.length_squared()
	var current_t: float = 0.0
	if l2 > 0.001:
		current_t = clamp((pos2 - a2).dot(ab) / l2, 0.0, 1.0)

	var remaining: float = lookahead_dist
	var seg: int = _nav_progress_seg
	var t_param: float = current_t
	while seg < _nav_path.size() - 1:
		var sa: Vector3 = _nav_path[seg]
		var sb: Vector3 = _nav_path[seg + 1]
		var seg_len: float = Vector2(sb.x - sa.x, sb.z - sa.z).length()
		var remaining_in_seg: float = seg_len * (1.0 - t_param)
		if remaining <= remaining_in_seg and seg_len > 0.001:
			var new_t: float = t_param + remaining / seg_len
			return sa.lerp(sb, new_t)
		remaining -= remaining_in_seg
		seg += 1
		t_param = 0.0
	return _nav_path[_nav_path.size() - 1]

func _tick_windup(delta: float, distance: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	# 攻击态继续面朝玩家
	var to_player_flat: Vector3 = _player.global_position - global_position
	to_player_flat.y = 0.0
	if to_player_flat.length() > 0.01:
		look_at(global_position + to_player_flat, Vector3.UP)

	_state_timer -= delta
	_tell_elapsed += delta

	# 脉冲警示色
	if _flash_timer <= 0.0:
		var pulse: float = 0.55 + 0.45 * sin(_tell_elapsed * attack_tell_pulse_hz * TAU)
		_apply_overlay_pulse(pulse)

	if _state_timer <= 0.0:
		# v0.4-B B7：所有近战敌人（boss 除外）改 LUNGE 冲撞，强制玩家"看抬手就侧闪"
		# boss 仍走 _strike 瞬时点判定（体型大动作慢，Lunge 视觉怪）
		# 仅极限档启用 LUNGE，其他档位保持原 _strike 逻辑
		var use_lunge: bool = (
			not is_boss
			and bool(Settings.get_difficulty_param("enable_advanced_ai", false))
		)
		if use_lunge:
			_enter_lunge()
		else:
			_strike(distance)

func _tick_cooldown(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	# 冷却也保持朝向玩家，准备下一次攻击
	var to_player_flat: Vector3 = _player.global_position - global_position
	to_player_flat.y = 0.0
	if to_player_flat.length() > 0.01:
		look_at(global_position + to_player_flat, Vector3.UP)

	_state_timer -= delta
	if _state_timer <= 0.0:
		# COOLDOWN 结束回 CHASE（CHASE 第一帧会决定继续追 / 切 SEARCH）
		_state = State.CHASE

# ---------- 感知 ----------
# 视野四重判定：距离 → 高度差 → 夹角 → raycast 遮挡
# CHASE 状态传 ignore_angle=true：已经锁定目标，敌人脑子里有玩家方位，
# 不需要 forward 对齐（用 nav 导航时 forward 朝移动方向，不朝玩家）；
# 只靠 raycast 墙体遮挡来丢失视野。IDLE/SEARCH 保留夹角检查（模拟"看向"）。
func _can_see_player(ignore_angle: bool = false) -> bool:
	if _player == null:
		return false
	# 玩家已死不算看见（避免死后被追）
	if "_dead" in _player and _player._dead:
		return false

	var to_vec: Vector3 = _player.global_position - global_position
	var horizontal := Vector3(to_vec.x, 0.0, to_vec.z)
	var dist: float = horizontal.length()

	# 贴身视为看见，跳过后续判定避免除零
	if dist < 0.01:
		return true
	if dist > sight_range:
		return false
	if absf(to_vec.y) > sight_height_max:
		return false

	# 夹角（单边 = 总夹角 / 2）— CHASE 状态可跳过（已锁定目标）
	if not ignore_angle:
		var forward: Vector3 = -global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.001:
			return false
		forward = forward.normalized()
		var to_dir: Vector3 = horizontal / dist   # 已有 dist > 0.01，可直接除
		var dot_val: float = forward.dot(to_dir)
		var half_rad: float = deg_to_rad(sight_angle_deg * 0.5)
		if dot_val < cos(half_rad):
			return false

	# 遮挡 raycast：眼睛 → 玩家胸部。只有击中玩家本身或无击中才算看见
	var space := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * EYE_HEIGHT
	var to: Vector3 = _player.global_position + Vector3.UP * PLAYER_TARGET_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == _player

# ---------- 告警 ----------
# 只有"亲眼发现"和"被击中"才发告警；被告警的敌人不传播，避免链式警觉风暴
func _alert_nearby_enemies() -> void:
	if _player == null:
		return
	var pos: Vector3 = _player.global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or e == null or not (e is Enemy):
			continue
		var other: Enemy = e
		if other._is_dead:
			continue
		# 水平距离：和视野/攻击判定保持一致，"告警=呼叫"的语义不该被高度压缩
		var hd: float = Vector2(
			other.global_position.x - global_position.x,
			other.global_position.z - global_position.z
		).length()
		if hd <= alert_radius:
			other._receive_alert(pos)

func _receive_alert(player_pos: Vector3) -> void:
	if _is_dead:
		return
	# 只有 IDLE / SEARCH 响应告警；CHASE / WINDUP / COOLDOWN 已经在 combat
	if _state == State.IDLE or _state == State.SEARCH:
		_last_known_player_pos = player_pos
		_state = State.CHASE
		# 故意不再次 _alert_nearby_enemies() — 切断传播链

# ---------- Boss Phase（B5-A） ----------
# Phase 切换在 take_damage 末尾调；HP 阈值穿越时单向推进 phase（不能回退）
# Phase 2 进入时立即召唤一次（满足"刚跌破 60% 立刻看到增援"反馈）
# Phase 3 进入时立即应用狂暴 buff（move_speed ×1.4 + attack_windup 在 _enter_windup 应用 ×0.6）
func _check_boss_phase_transition() -> void:
	if max_health <= 0.0:
		return
	var hp_pct: float = current_health / max_health
	if _boss_phase == 1 and hp_pct <= BOSS_PHASE2_HP_THRESHOLD:
		_boss_phase = 2
		_boss_summon_timer = 0.0  # 立刻召唤一次
	if _boss_phase <= 2 and hp_pct <= BOSS_PHASE3_HP_THRESHOLD:
		_boss_phase = 3
		if not _boss_phase3_applied:
			move_speed *= BOSS_PHASE3_SPEED_MULT
			_boss_phase3_applied = true

# v0.4-B B5-B：Boss 发射远程投射物
# 起始位置：boss 头顶（EYE_HEIGHT + 0.3）；目标 = 玩家胸部（PLAYER_TARGET_HEIGHT）
# 投射物 6 m/s 慢速 + 玩家 sprint 8 m/s 能跑过，但站定 / 后退跑不过（必须侧移闪）
# 伤害 = attack_damage × 0.6（boss 极限档 50×1.6×1.30×0.6 ≈ 62/发）
func _fire_ranged_projectile() -> void:
	if _player == null:
		return
	var p: BossProjectile = BOSS_PROJECTILE_SCENE.instantiate() as BossProjectile
	if p == null:
		return
	var spawn_pos: Vector3 = global_position + Vector3.UP * (EYE_HEIGHT + 0.3)
	var target_pos: Vector3 = _player.global_position + Vector3.UP * PLAYER_TARGET_HEIGHT
	var to_target: Vector3 = target_pos - spawn_pos
	get_tree().current_scene.add_child(p)
	p.global_position = spawn_pos
	p.set_direction(to_target)
	# 难度系数：极限档 enemy_damage_mult 1.6 让远程伤害也跟近战一样涨
	var dmg_mult: float = float(Settings.get_difficulty_param("enemy_damage_mult", 1.0))
	p.set_damage(attack_damage * dmg_mult * BOSS_PROJECTILE_DAMAGE_MULT)
	AudioManager.play_enemy_windup(global_position)  # 复用前摇音效作"喷球"提示

# 召唤 N 只 grunt 在 boss 周围圆环上，纳入 wave_manager 的"必须杀完"列表
# 让 boss 在场期间持续掉血（不只杀 boss 本体），强化 phase 2 压力感
func _summon_grunts(count: int) -> void:
	if count <= 0:
		return
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	for i in count:
		var g: Enemy = BOSS_SUMMON_SCENE.instantiate() as Enemy
		if g == null:
			continue
		var angle: float = float(i) / float(count) * TAU + randf_range(-0.3, 0.3)
		var spawn_offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * BOSS_SUMMON_RADIUS
		g.transform = global_transform
		g.global_position = global_position + spawn_offset
		get_tree().current_scene.add_child(g)
		# 注册到 wave_manager 让本波 progress 包含召唤的小弟（玩家必须杀完才能过波）
		if wm and wm.has_method("register_summoned_enemy"):
			wm.register_summoned_enemy(g)

# ---------- 撤退反扑（B3） ----------
# 进入 RETREAT 状态：后撤 1s，结束后切 CHASE + 下次 windup ×0.7
# 让出攻击锁让其他敌人接手，避免 retreat 期间锁位浪费
func _enter_retreat() -> void:
	_state = State.RETREAT
	_state_timer = _RETREAT_DURATION
	_has_retreated = true
	_release_attack_lock()
	velocity.x = 0.0
	velocity.z = 0.0

# RETREAT tick：朝远离玩家方向直线后撤（不走 navmesh，1s 距离短不易撞墙）
# timer 到 0 → CHASE，置 _retreat_attack_speedup 让下次 windup 应用 ×0.7
func _tick_retreat(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0 or _player == null:
		_state = State.CHASE
		_retreat_attack_speedup = true
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var away: Vector3 = global_position - _player.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	away = away.normalized()
	look_at(global_position + away, Vector3.UP)
	velocity.x = away.x * move_speed * _RETREAT_SPEED_MULT
	velocity.z = away.z * move_speed * _RETREAT_SPEED_MULT

# ---------- 攻击 ----------
# v0.4-B B2：from_sync=true 表示由其他敌人同步广播触发，避免无限递归（被同步的不再广播）
func _enter_windup(from_sync: bool = false) -> void:
	_state = State.WINDUP
	# v0.4-B B3：撤退反扑后下次 windup ×0.7（更快出招报复）
	var w: float = attack_windup
	if _retreat_attack_speedup:
		w *= _RETREAT_WINDUP_SPEEDUP
		_retreat_attack_speedup = false
	# v0.4-B B5-A：Boss Phase 3 狂暴 windup ×0.6（与 retreat speedup 乘法叠加）
	if is_boss and _boss_phase >= 3:
		w *= BOSS_PHASE3_WINDUP_MULT
	_state_timer = w
	_tell_elapsed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	if _flash_timer <= 0.0:
		_apply_overlay_solid(ATTACK_TELL_COLOR)
	# 强制从头播 attack 动画一次，避免 _update_anim 每帧检测 is_playing 误重启
	_play_anim(anim_attack, true)
	AudioManager.play_enemy_windup(global_position)
	# v0.4-B B2：协同攻击同步——通知 attack_range 内同种敌人也 windup
	# 玩家闪避一个会被另两个同时打中（破"打一只闪一下走"无脑节奏）
	# max_concurrent_attackers 仍生效（最多同时 3 个 windup），同步只是"换成同帧"
	if not from_sync and bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
		_broadcast_sync_windup()

# v0.4-B B2：广播同步 windup 给同种 enemy（在 1.2× attack_range 容差内）
# 容差 1.2× 让"刚走到边界"的同伴也能搭车一起 windup（差几厘米不算就太苛刻）
func _broadcast_sync_windup() -> void:
	if _player == null:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not (e is Enemy):
			continue
		var other: Enemy = e
		if other._is_dead or other._state != State.CHASE:
			continue
		if other.enemy_id != enemy_id:
			continue  # 只同种敌人同步（grunt 同步 grunt，runner 同步 runner）
		var pd: float = other.global_position.distance_to(_player.global_position)
		if pd > other.attack_range * 1.2:
			continue
		if other._can_claim_attack_lock():
			if not _active_attackers.has(other):
				_active_attackers.append(other)
			other._enter_windup(true)  # from_sync=true，不再次广播

# v0.4-B B7：进入 LUNGE 冲撞——锁定 windup 末尾时玩家位置，朝该方向高速冲 _LUNGE_DURATION 秒
# 玩家 windup 期间侧移 → LUNGE 冲到的位置玩家不在 → 落空（迫使侧闪而非后退）
# 玩家 windup 期间后退 → LUNGE 冲撞距离覆盖到 → 仍命中
# 玩家 windup 期间站定 → 必命中
func _enter_lunge() -> void:
	if _state != State.WINDUP:
		return
	# 恢复颜色（同 _strike 开头）+ 释放攻击锁让其他敌人接手
	if _flash_timer <= 0.0:
		_restore_colors()
	_release_attack_lock()
	# 玩家不在了 → 跳过 lunge 直接 cooldown
	if _player == null:
		_state = State.COOLDOWN
		_state_timer = attack_cooldown + attack_miss_bonus_cooldown
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.001:
		_state = State.COOLDOWN
		_state_timer = attack_cooldown + attack_miss_bonus_cooldown
		return
	_lunge_direction = to_player.normalized()
	_state = State.LUNGE
	_state_timer = _LUNGE_DURATION
	_lunge_did_hit = false
	look_at(global_position + _lunge_direction, Vector3.UP)
	AudioManager.play_enemy_attack_hit(global_position)  # 复用打击音效作为 lunge 启动音

# LUNGE tick：朝锁定方向高速直线冲 + 持续命中检测
# 期间不能转向（玩家侧移闪避的关键）；timer 到 0 / 已命中 → COOLDOWN
func _tick_lunge(delta: float) -> void:
	_state_timer -= delta
	# 持续命中检测：玩家进入 _LUNGE_HIT_RADIUS 即触发伤害（每次 lunge 只命中一次）
	if not _lunge_did_hit and _player != null and _player.has_method("take_damage"):
		var d: Vector3 = _player.global_position - global_position
		var height_ok: bool = absf(d.y) <= max_attack_height_diff
		d.y = 0.0
		if height_ok and d.length() <= _LUNGE_HIT_RADIUS:
			_lunge_did_hit = true
			var dmg_mult: float = float(Settings.get_difficulty_param("enemy_damage_mult", 1.0))
			_player.take_damage(attack_damage * dmg_mult, self)
	# Timer 结束 → COOLDOWN（命中省 miss 奖励 cooldown）
	if _state_timer <= 0.0:
		_state = State.COOLDOWN
		_state_timer = attack_cooldown + (0.0 if _lunge_did_hit else attack_miss_bonus_cooldown)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	# 高速冲撞（不转向）
	velocity.x = _lunge_direction.x * move_speed * _LUNGE_SPEED_MULT
	velocity.z = _lunge_direction.z * move_speed * _LUNGE_SPEED_MULT

func _strike(distance: float) -> void:
	# 守卫：只有 WINDUP 状态才能 strike
	if _state != State.WINDUP:
		push_warning("[%s] _strike called in non-WINDUP state %d, ignored" % [name, _state])
		return

	if _flash_timer <= 0.0:
		_restore_colors()
	_release_attack_lock()
	_juice_strike_timer = _STRIKE_DURATION  # 路径B：精灵前刺动效（命中与否都挥）

	# 实时水平距离 + 高度差再验一次
	var actual_dist: float = distance
	var same_layer: bool = true
	if _player:
		var d: Vector3 = _player.global_position - global_position
		same_layer = absf(d.y) <= max_attack_height_diff
		d.y = 0.0
		actual_dist = d.length()

	# v0.4-B Fix C: strike 距离容差 ×1.25——windup 期间敌人停下不动，玩家走位让 strike MISS
	# 容差 1.25 让"刚走出 attack_range"也算命中（视觉合理：敌人挥拳手臂能甩 25%）
	var strike_range: float = attack_range * 1.25
	var hit: bool = actual_dist <= strike_range and same_layer and _player and _player.has_method("take_damage")
	if hit:
		# 难度系数：极限突破 1.6 让敌人伤害成倍提升
		var dmg_mult: float = float(Settings.get_difficulty_param("enemy_damage_mult", 1.0))
		_player.take_damage(attack_damage * dmg_mult, self)
		AudioManager.play_enemy_attack_hit(global_position)

	_state = State.COOLDOWN
	_state_timer = attack_cooldown + (0.0 if hit else attack_miss_bonus_cooldown)

func _can_claim_attack_lock() -> bool:
	# 先清理已失效（free / dead）的占位防止占满槽位（敌人 die 时 _release 已 erase，
	# 但 fall_death_y 等异常路径可能漏 erase，filter 兜底）
	_active_attackers = _active_attackers.filter(
		func(e): return is_instance_valid(e) and not e._is_dead
	)
	if _active_attackers.has(self):
		return true  # 已占有槽位
	var max_n: int = int(Settings.get_difficulty_param("max_concurrent_attackers", MAX_CONCURRENT_ATTACKERS_FALLBACK))
	return _active_attackers.size() < max_n

func _release_attack_lock() -> void:
	_active_attackers.erase(self)

# ---------- 伤害接收 ----------
# weapon.gd 通过 duck typing 调用（collider.has_method("take_damage")）
func take_damage(amount: float) -> void:
	if _is_dead:
		return
	current_health -= amount
	_flash_red()
	_juice_hit_timer = _JUICE_HIT_DURATION

	# 痛感告警：IDLE / SEARCH 中被击中立即切 CHASE 并告警
	# （被打中说明玩家在附近，即使视野没看到也该反击）
	if _state == State.IDLE or _state == State.SEARCH:
		if _player:
			_last_known_player_pos = _player.global_position
			_state = State.CHASE
			_alert_nearby_enemies()

	if current_health <= 0.0:
		_die()
	# v0.4-B B3：撤退反扑（brute/elite，仅极限档启用）
	# 受击后 HP 跌破 50% 一次性触发：后撤 1s + 下次 windup ×0.7 报复
	# 若已在 RETREAT/WINDUP 中或已反扑过则跳过
	elif not _has_retreated and bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
		if (enemy_id == "brute" or enemy_id == "elite") and _state != State.RETREAT:
			if max_health > 0.0 and current_health / max_health < _RETREAT_HP_THRESHOLD:
				_enter_retreat()
	# v0.4-B B5-A：Boss phase 切换（仅 boss + 极限档）
	if is_boss and not _is_dead and bool(Settings.get_difficulty_param("enable_advanced_ai", false)):
		_check_boss_phase_transition()

# weapon "重型压制"升级触发：暂时冻结 AI 与移动，正在前摇的攻击被打断
# 调用方应已确认 is_elite 或 is_boss（普通 grunt 不该被 stagger）
func stagger(duration: float) -> void:
	if _is_dead:
		return
	_stagger_timer = maxf(_stagger_timer, duration)
	# 前摇被打断 → 攻击作废，转回 CHASE 让玩家拿到节奏空档
	if _state == State.WINDUP:
		_release_attack_lock()
		_state = State.CHASE
		_state_timer = 0.0

func _flash_red() -> void:
	_apply_overlay_solid(Color(2.0, 0.2, 0.2))
	_flash_timer = flash_duration

# 视觉反馈层同时驱动 3D 材质(albedo)与 2D 精灵(modulate)，各调用点不再各自遍历
func _apply_overlay_solid(c: Color) -> void:
	for entry in _flash_cache:
		entry[0].albedo_color = c
	for s in _flash_sprites:
		s[0].modulate = c

func _apply_overlay_pulse(pulse: float) -> void:
	for entry in _flash_cache:
		entry[0].albedo_color = ATTACK_TELL_COLOR * pulse + entry[1] * (1.0 - pulse)
	for s in _flash_sprites:
		s[0].modulate = ATTACK_TELL_COLOR * pulse + s[1] * (1.0 - pulse)

func _restore_colors() -> void:
	for entry in _flash_cache:
		entry[0].albedo_color = entry[1]
	for s in _flash_sprites:
		s[0].modulate = s[1]

func _die() -> void:
	_is_dead = true
	collision.disabled = true
	# 禁用 hitbox 避免 weapon 打到尸体触发额外 kill/hit 反馈
	# 双保险让 weapon raycast (collide_with_areas=true) 真正穿透尸体：
	# (1) area.collision_layer=0 让 raycast.mask=1 不再命中此 area
	# (2) area 内 CollisionShape3D 也 disabled（layer 直接赋值到物理空间同步可能延迟，
	#     CollisionShape3D 用 set_deferred("disabled") 是 Godot 推荐的最稳方式）
	# 仅关 monitorable 不够（那只影响 area↔area 信号，不挡 raycast）
	for child in get_children():
		if child is Area3D:
			var area: Area3D = child
			area.monitorable = false
			area.collision_layer = 0
			for shape_child in area.get_children():
				if shape_child is CollisionShape3D:
					(shape_child as CollisionShape3D).set_deferred("disabled", true)
	_release_attack_lock()
	if _flash_timer <= 0.0:
		_restore_colors()
	_drop_loot()
	died.emit()
	_play_death_sequence()

# 倒地序列：优先用 GLTF 自带 death 动画，没有则 fallback 到 tween rotation。
# 统一 1.4s 后 queue_free（足够 Mech Pack Death + Sci-Fi TurnOff 播完）
func _play_death_sequence() -> void:
	if _juice_sprite != null:
		# 有倒地帧则先切到最末帧（最"塌"的姿态），再叠缩小/上飘/淡出溶解
		if not _frames_death.is_empty():
			_juice_sprite.texture = _frames_death[_frames_death.size() - 1]
		# 精灵死亡：缩小 + 上飘 + 淡出溶解（root 旋转对 billboard 无效，必须动精灵本身）
		var stw: Tween = create_tween()
		stw.set_parallel(true)
		stw.tween_property(_juice_sprite, "scale", _juice_base_scale * 0.05, 0.45).set_ease(Tween.EASE_IN)
		stw.tween_property(_juice_sprite, "position", _juice_base_pos + Vector3(0.0, 0.7, 0.0), 0.45)
		stw.tween_property(_juice_sprite, "modulate:a", 0.0, 0.45)
	elif _anim_player and not anim_death.is_empty() and _anim_player.has_animation(anim_death):
		_anim_player.play(anim_death)
	else:
		var tween: Tween = create_tween()
		tween.tween_property(self, "rotation:x", deg_to_rad(90), 0.6).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.4).timeout
	if is_instance_valid(self):
		queue_free()

func _drop_loot() -> void:
	# 升级系统"战场拾荒"给所有敌人叠全局 drop 加成
	var bonus: float = UpgradeManager.drop_chance_bonus if UpgradeManager else 0.0
	if randf() < health_pack_drop_chance + bonus:
		var pack: Node3D = HEALTH_PACK_SCENE.instantiate()
		get_tree().current_scene.add_child(pack)
		pack.global_position = global_position + Vector3.UP * 0.1

	# 传说武器掉落：按敌人 tier 配置概率（Brute 2% / Elite 30% / Boss 100%）
	# 抽 LEGENDARY_POOL 一把，instantiate pickup 并指向该武器场景
	if legendary_drop_chance > 0.0 and randf() < legendary_drop_chance and not LEGENDARY_POOL.is_empty():
		var pickup: Node3D = LEGENDARY_PICKUP_SCENE.instantiate()
		pickup.set("weapon_scene", LEGENDARY_POOL[randi() % LEGENDARY_POOL.size()])
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position + Vector3.UP * 0.5

	# 处决次数补给：5% 概率直接给玩家 +1（v1 直接到账，未来可改实体拾取）
	if randf() < 0.05:
		var pl: Node = get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("add_execute_charge"):
			pl.add_execute_charge(1)
