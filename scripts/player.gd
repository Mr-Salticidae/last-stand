extends CharacterBody3D

# Player node
@onready var neck: Node3D = $neck
@onready var head: Node3D = $neck/head
@onready var eyes: Node3D = $neck/head/eyes
@onready var standing_collision_shape: CollisionShape3D = $standing_collision_shape
@onready var crouching_collision_shape: CollisionShape3D = $crouching_collision_shape
@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var camera_3d: Camera3D = $neck/head/eyes/Camera3D
@onready var animation_player: AnimationPlayer = $neck/head/eyes/AnimationPlayer

# Speed vars
var current_speed = 5.0
const walking_speed = 5.0
const sprinting_speed = 8.0
const crouching_speed = 3.0
# v0.4-A 方向感知速度：前=1.0 / 横=0.85 / 后=0.65（介于 CS 0.51 和三角洲 0.70 之间）
# 平滑插值（基于 input_dir.y 的前向投影），避免离散切换；后退禁 sprint + 禁滑铲
const STRAFE_SPEED_MULT: float = 0.85
const BACKWARD_SPEED_MULT: float = 0.65

# Slide vars
# slide_world_direction：滑铲方向锁定到世界空间（启动瞬间确定），过程中不随身体旋转变化。
# 这样玩家在滑铲中可以自由用鼠标瞄准（转 body），但运动方向仍按起始方向冲。
var slide_timer = 0.0
var slide_timer_max = 1.0
var slide_world_direction: Vector3 = Vector3.ZERO
var slide_speed = 10.0

# Head bobbing vars
const head_bobbing_sprinting_speed = 22.0
const head_bobbing_walking_speed = 14.0
const head_bobbing_crouching_speed = 10.0

const head_bobbing_sprinting_intensity = 0.2
const head_bobbing_walking_intensity = 0.1
const head_bobbing_crouching_intensity = 0.05

var head_bobbing_vector = Vector2.ZERO
var head_bobbing_index = 0.0
var head_bobbing_current_intensity = 0.0

# States
var walking = false
var sprinting = false
var crouching = false
var sliding = false
var free_looking = false

# Movement vars
var lerp_speed = 10.0
var air_lerp_speed = 3.0
var crouching_depth = -0.5
var free_looking_tilt_amount = 5
var last_velocity = Vector3.ZERO

# Input vars
var direction = Vector3.ZERO
# 鼠标灵敏度从 Settings autoload 读取（玩家可在设置面板调）；fallback 0.2
const DEFAULT_MOUSE_SENS: float = 0.2

# Aim & recoil
# 硬派压枪机制：后坐力直接推高 aim_pitch（永久上抬，不自动回落），玩家必须鼠标下拉反制
# pending_recoil_pitch：武器开火累积的"待推入"冲量（弧度），每帧按固定速度注入 aim_pitch
# 这样视角被"踢上去"有 ~90ms 过渡感，避免瞬间跳跃的生硬
var aim_pitch: float = 0.0
var pending_recoil_pitch: float = 0.0
const recoil_apply_speed: float = 25.0  # rad/s，冲量推进速度，越大越"硬"

# Jump feel (非对称重力)
# 上升段用低重力起跳敏捷，下降段用高重力快速落地，消除"月球感"。
# 经典 FPS 套路：fall_gravity > jump_gravity，让腾空和落地有不同的节奏感。
@export_group("Jump Feel")
@export var jump_velocity: float = 5.8    # 起跳初速度（提高以补偿新重力）
@export var jump_gravity: float = 15.0    # 上升段重力（越小越轻盈）
@export var fall_gravity: float = 25.0    # 下降段重力（越大落地越"实"）
# 落地动画用掉落高度配置（而非硬编码速度阈值），fall_gravity 变化时阈值自动跟随
@export var landing_min_drop: float = 1.5  # 触发 landing 动画的最低掉落高度（米）

# Mantle (攀爬翻越)
# 空中 + 前向输入 + 前方墙顶位于胸部附近时，自动抓边翻上。
# 由 tween 直接推动 global_position，期间跳过物理流程。
@export_group("Mantle")
@export var mantle_min_height: float = 0.5         # 低于此高度交给普通跳跃，避免干扰 1m 阶梯
@export var mantle_max_height: float = 1.6         # 超出此高度够不到，视为翻不过
@export var mantle_forward_distance: float = 0.9   # 前向探测距离（需大于胶囊半径 0.5）
@export var mantle_duration: float = 0.35          # 翻越动画时长（秒）
var mantling: bool = false

# Health & combat reception (伤害接收层)
# 直接实现 take_damage，敌人调用即可；未来也可重构为 hitbox 模式
@export_group("Health")
@export var max_health: float = 100.0
@export var invulnerability_time: float = 0.5   # 受击后无敌时长，防被多怪瞬秒
@export var pushback_force: float = 6.0         # 受击后远离 source 的初速度
@export var shake_intensity: float = 0.05       # 摄像机震晃强度（弧度）
@export var shake_duration: float = 0.2         # 震晃时长（秒）

var current_health: float
var _dead: bool = false
var _invuln_timer: float = 0.0
var _shake_timer: float = 0.0

# 升级系统写入的全局倍率 / bonus（UpgradeManager.apply_effect 修改，玩家行为里读）
var speed_mult: float = 1.0       # 疾风步伐：移动速度倍率
var jump_mult: float = 1.0        # 鹰跃：起跳初速度倍率
var heal_mult: float = 1.0        # 战地医疗 / 不朽之躯：回血量倍率
var max_air_jumps: int = 0        # 二段跳：空中额外跳次数（触地归零）
var _air_jumps_used: int = 0
# v0.3 新卡：杀戮节拍 / 战术突进
var combo_speed_threshold: int = 9999  # combo ≥ 此值临时叠 combo_speed_bonus
var combo_speed_bonus: float = 0.0     # 每 stack +0.15
var _combo_speed_active: float = 0.0   # 每帧根据 combo 动态算出的实际加成
var slide_burst_enabled: bool = false  # 战术突进：滑铲期间 invuln + 出滑铲触发 wm.slide_burst_timer
var _was_sliding: bool = false         # 追踪 sliding 上一帧值，用于检测"出滑铲"瞬间
# v0.3 PR-B 羁绊（synergy_manager.gd 写入）
var synergy_slide_speed_bonus: float = 0.0   # 闪电战：滑铲速度 +50%
var synergy_invuln_after_slide: float = 0.0  # 闪电战：滑铲结束后短暂无敌秒数（叠加到 _invuln_timer）
# v0.3 视觉：杀戮节拍激活时 FOV +5°，lerp 进出
const COMBO_SPEED_FOV_BONUS: float = 5.0
const FOV_LERP_RATE: float = 6.0
var _base_fov: float = 0.0  # _ready 缓存
var _fov_extra: float = 0.0  # 当前 FOV 额外量（lerp 平滑）

# 输入锁：升级面板等模态 UI 开启时置 true，屏蔽移动 / 视角 / 射击
var input_locked: bool = false

# 击退冲量：take_damage 写入，_physics_process 每帧衰减并合成到 velocity
# 独立字段避免被玩家输入（velocity.x = dir.x * speed）直接覆盖
var _knockback: Vector3 = Vector3.ZERO
const _KNOCKBACK_DECAY: float = 18.0  # m/s²，pushback_force=6 的话约 0.33s 衰减完

# === 隐藏调试工具：飞行 / Noclip ===
# 触发热键 Ctrl+Shift+F（直接读 InputEventKey，不走 InputMap，键位设置面板里玩家看不见）。
# 用途：地图调试、卡位逃脱、关卡审视。封版后保留为开发工具，更新时仍可使用。
# 行为：关闭碰撞穿墙、关闭重力、WASD 沿摄像机朝向飞、Space/Ctrl 升降、Sprint 加速、过程中免伤。
var _noclip: bool = false
const NOCLIP_SPEED: float = 12.0
const NOCLIP_SPRINT_MULT: float = 3.0
var _noclip_saved_layer: int = 0
var _noclip_saved_mask: int = 0

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal healed(amount: float)
signal died

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_health = max_health
	# 延迟一帧发送，确保 HUD 已经连接 health_changed 后再同步初始值
	call_deferred("emit_signal", "health_changed", current_health, max_health)
	# 缓存 base FOV，杀戮节拍激活时叠加 _fov_extra
	if camera_3d:
		_base_fov = camera_3d.fov

func _input(event: InputEvent) -> void:
	# 隐藏调试热键 Ctrl+Shift+F：放在 _dead/input_locked 检查前，
	# 这样玩家死亡或升级面板开着时也能切回飞行（开发场景常见）。
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		if ke.physical_keycode == KEY_F and ke.ctrl_pressed and ke.shift_pressed:
			_toggle_noclip()
			return

	if _dead or input_locked:
		return
	if event is InputEventMouseMotion:
		var sens: float = Settings.mouse_sensitivity if Settings else DEFAULT_MOUSE_SENS
		if free_looking:
			neck.rotate_y(deg_to_rad(-event.relative.x * sens))
			neck.rotation.y = clamp(neck.rotation.y, deg_to_rad(-120), deg_to_rad(120))
		else:
			rotate_y(deg_to_rad(-event.relative.x * sens))
			# 注意：只改 aim_pitch，不直接改 head.rotation.x（避免和后坐力冲突）
			aim_pitch -= deg_to_rad(event.relative.y * sens)
			aim_pitch = clamp(aim_pitch, deg_to_rad(-89), deg_to_rad(89))

# 武器调用此方法产生后坐力（pitch_deg 为视角上抬角度）
func apply_recoil(pitch_deg: float) -> void:
	pending_recoil_pitch += deg_to_rad(pitch_deg)

func _physics_process(delta: float) -> void:
	# 死亡后放弃输入 / 移动 / 攻击相关的所有逻辑；倒地 tween 独立运行
	# 让重力 / move_and_slide 停掉，玩家保持倒地位置不漂移
	if _dead:
		velocity = Vector3.ZERO
		return
	# 调试飞行：跳过常规物理 / 滑铲 / 攀爬 / 重力，全程独立处理
	if _noclip:
		_process_noclip(delta)
		return
	# 升级面板等模态 UI 开启时：玩家输入被锁，水平速度归零但重力仍然生效（自然落地）
	if input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= fall_gravity * delta
		move_and_slide()
		return

	# 无敌 / 震晃计时（即使攀爬中也继续衰减，避免状态卡住）
	if _invuln_timer > 0.0:
		_invuln_timer = max(0.0, _invuln_timer - delta)
	if _shake_timer > 0.0:
		_shake_timer = max(0.0, _shake_timer - delta)
		var shake_t: float = _shake_timer / shake_duration
		camera_3d.h_offset = (randf() * 2.0 - 1.0) * shake_intensity * shake_t
		camera_3d.v_offset = (randf() * 2.0 - 1.0) * shake_intensity * shake_t
		if _shake_timer <= 0.0:
			camera_3d.h_offset = 0.0
			camera_3d.v_offset = 0.0

	# 硬派压枪：把 pending 冲量按速率推入 aim_pitch（永久上抬，不回落）
	# 玩家压枪（鼠标下拉）会主动减小 aim_pitch 抵消后坐力
	# 攀爬中仍允许后坐力推进，避免视角卡顿
	if pending_recoil_pitch > 0.0:
		var step: float = min(pending_recoil_pitch, recoil_apply_speed * delta)
		aim_pitch += step
		pending_recoil_pitch -= step
		aim_pitch = clamp(aim_pitch, deg_to_rad(-89), deg_to_rad(89))
	head.rotation.x = aim_pitch

	# 攀爬中跳过常规物理（tween 直接推动位置）
	if mantling:
		return

	# Getting movement input
	var input_dir := Input.get_vector("left", "right", "forward", "backward")

	# 攀爬检测：空中 + 向前输入时尝试抓边
	if not is_on_floor() and input_dir.y < 0.0:
		_try_mantle()
		if mantling:
			return
	# Handle movement state
	# Crouching
	if Input.is_action_pressed("crouch"):
		current_speed = lerp(current_speed, crouching_speed, delta * lerp_speed)
		head.position.y = lerp(head.position.y, crouching_depth, delta * lerp_speed)
		
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
		
		# Slide begin logic
		# 滑铲不再强制 free_looking：鼠标直接控制 body 旋转，玩家可正常瞄准
		# 方向锁世界空间快照，避免身体旋转改变 slide 运动方向
		# 触发宽容：不严格要求 sprinting=true，只要 current_speed > walking_speed*0.95
		# （在跑步状态，含松开 sprint 后 lerp 减速窗口）+ 有移动方向就触发，玩家反馈
		# "滑铲不好用出来"主因是 sprint 必须按住时机太严
		# v0.4-A 方向感知：滑铲必须前向触发（input.y < 0），后退冲刺禁了滑铲也一并禁
		if current_speed > walking_speed * 0.95 and input_dir.y < 0.0:
			sliding = true
			slide_timer = slide_timer_max
			slide_world_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		walking = false
		sprinting = false
		crouching = true
	elif !ray_cast_3d.is_colliding():
		# Standing
		head.position.y = lerp(head.position.y, 0.0, delta * lerp_speed)
		
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true
		# v0.4-A 方向感知：后退方向（input.y > 0）禁 sprint，玩家想后退快只能掉头跑
		var can_sprint: bool = input_dir.y <= 0.0
		if Input.is_action_pressed("sprint") and can_sprint:
			# Sprinting
			current_speed = lerp(current_speed, sprinting_speed, delta * lerp_speed)
			walking = false
			sprinting = true
			crouching = false
		else:
			# Walking
			current_speed = lerp(current_speed, walking_speed, delta * lerp_speed)
			walking = true
			sprinting = false
			crouching = false
			
	# Free-look：仅在玩家显式按住时启用（已与 sliding 解耦）
	if Input.is_action_pressed("free_looking"):
		free_looking = true
		eyes.rotation.z = -deg_to_rad(neck.rotation.y * free_looking_tilt_amount)
	else:
		free_looking = false
		neck.rotation.y = lerp(neck.rotation.y, 0.0, delta * lerp_speed)

	# 视角 Z 轴倾斜：sliding 时强制 -5°（视觉反馈，不影响 aim 方向）；
	# 非 sliding 且非 free_looking 时归零（free_looking 自己管 z）
	if sliding:
		eyes.rotation.z = lerp(eyes.rotation.z, -deg_to_rad(5.0), delta * lerp_speed)
	elif not free_looking:
		eyes.rotation.z = lerp(eyes.rotation.z, 0.0, delta * lerp_speed)
	
	# Handle sliding
	if sliding:
		slide_timer -= delta
		# 战术突进：滑铲期间维持 invuln（每帧刷到 0.1，结束时立即归零，不与正常受击 invuln 冲突）
		if slide_burst_enabled:
			_invuln_timer = maxf(_invuln_timer, 0.1)
		if slide_timer <= 0:
			sliding = false
	# 战术突进：出滑铲瞬间触发 weapon_manager.slide_burst_timer = duration（射速 buff）
	if _was_sliding and not sliding and slide_burst_enabled:
		var wm_sb: Node = get_tree().get_first_node_in_group("weapon_manager")
		if wm_sb and "slide_burst_duration" in wm_sb:
			wm_sb.slide_burst_timer = wm_sb.slide_burst_duration
	# 闪电战羁绊：出滑铲瞬间延长无敌（与 slide_burst 解耦，单独条件触发）
	if _was_sliding and not sliding and synergy_invuln_after_slide > 0.0:
		_invuln_timer = maxf(_invuln_timer, synergy_invuln_after_slide)
	_was_sliding = sliding
	# 杀戮节拍：combo ≥ 阈值时叠加 combo_speed_bonus 到移速（动态，不污染 base speed_mult）
	# 同时驱动 FOV 增加（视觉提示），lerp 平滑
	var wm_combo: Node = get_tree().get_first_node_in_group("wave_manager")
	var combo_active: bool = wm_combo and "current_combo" in wm_combo and wm_combo.current_combo >= combo_speed_threshold and combo_speed_bonus > 0.0
	if combo_active:
		_combo_speed_active = combo_speed_bonus
	else:
		_combo_speed_active = 0.0
	var fov_target: float = COMBO_SPEED_FOV_BONUS if combo_active else 0.0
	_fov_extra = lerpf(_fov_extra, fov_target, clampf(delta * FOV_LERP_RATE, 0.0, 1.0))
	if camera_3d and _base_fov > 0.0:
		camera_3d.fov = _base_fov + _fov_extra
	
	# Handle headbob
	if sprinting:
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
	elif walking:
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif crouching:
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta
		
	if is_on_floor() && !sliding && input_dir != Vector2.ZERO:
		head_bobbing_vector.y = sin(head_bobbing_index)
		head_bobbing_vector.x = sin(head_bobbing_index / 2) + 0.5
		
		eyes.position.y = lerp(eyes.position.y, head_bobbing_vector.y * (head_bobbing_current_intensity / 2.0), delta * lerp_speed)
		eyes.position.x = lerp(eyes.position.x, head_bobbing_vector.x * head_bobbing_current_intensity, delta * lerp_speed)
	else:
		eyes.position.y = lerp(eyes.position.y, 0.0, delta * lerp_speed)
		eyes.position.x = lerp(eyes.position.x, 0.0, delta * lerp_speed)
	# 非对称重力：上升轻盈、下降干脆，消除"月球漂浮"感
	if not is_on_floor():
		var g: float = fall_gravity if velocity.y < 0.0 else jump_gravity
		velocity.y -= g * delta

	# Handle jump（含空中二段跳：max_air_jumps > 0 时空中还能再跳）
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity * jump_mult
			sliding = false
			animation_player.play("jump")
		elif _air_jumps_used < max_air_jumps:
			velocity.y = jump_velocity * jump_mult
			_air_jumps_used += 1
			animation_player.play("jump")
	# 触地归零 air jumps（滑铲等状态不影响）
	if is_on_floor():
		_air_jumps_used = 0
	
	# 落地动画：按掉落高度派生速度阈值（v = sqrt(2 * g * h)），随重力设定自适应
	if is_on_floor():
		var drop_speed: float = -last_velocity.y
		if drop_speed >= sqrt(2.0 * fall_gravity * landing_min_drop):
			animation_player.play("landing")
			

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	if is_on_floor():
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * lerp_speed)
	else:
		if input_dir != Vector2.ZERO:
			direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * air_lerp_speed)
		
	if sliding:
		# 用世界空间快照而非 transform.basis * input_dir，确保 body 旋转不改变 slide 方向
		direction = slide_world_direction
		# 闪电战羁绊：滑铲速度 +50%（synergy_slide_speed_bonus 默认 0.0 → 不影响）
		current_speed = (slide_timer + 0.1) * slide_speed * (1.0 + synergy_slide_speed_bonus)
		
	# 杀戮节拍 _combo_speed_active 在 _physics_process 早期算好，叠到 speed_mult 上
	# v0.4-A 方向感知：基于 input.y 的前向投影平滑插值（前 1.0 / 横 0.85 / 后 0.65）
	# 滑铲期间不应用（slide_world_direction 已锁定瞬间速度，方向感知会跟滑铲方向不一致）
	var dir_mult: float = 1.0
	if not sliding:
		dir_mult = _directional_speed_mult(input_dir)
	var total_speed_mult: float = speed_mult * (1.0 + _combo_speed_active) * dir_mult
	if direction:
		velocity.x = direction.x * current_speed * total_speed_mult
		velocity.z = direction.z * current_speed * total_speed_mult
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed * total_speed_mult)
		velocity.z = move_toward(velocity.z, 0, current_speed * total_speed_mult)
		
	# 击退冲量合成：放在玩家输入设定 velocity 之后，避免被 `velocity.x = dir.x * speed` 覆盖
	if _knockback.length_squared() > 0.01:
		velocity.x += _knockback.x
		velocity.z += _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, _KNOCKBACK_DECAY * delta)

	last_velocity = velocity

	move_and_slide()

# 三次射线检测决定能否攀爬：ledge 顶 → 净空 → 中间墙面
# 都通过则把玩家 tween 到 ledge 上方
# v0.4-A 方向感知速度：input_dir.y 范围 -1（前）~ +1（后）
# 平滑插值：前向投影 = -dir.y → 1.0 = 纯前 / 0.0 = 纯横 / -1.0 = 纯后
# 输出：前 1.0 → 横 STRAFE_SPEED_MULT → 后 BACKWARD_SPEED_MULT
# 例：左前 (-1, -1) normalized 后投影 0.707 → 1.0 + (1-0.707)/(1-0)*(0.85-1.0) = 0.96
func _directional_speed_mult(dir: Vector2) -> float:
	if dir == Vector2.ZERO:
		return 1.0
	var fwd_dot: float = -dir.normalized().y  # 1=纯前, 0=纯横, -1=纯后
	if fwd_dot >= 0.0:
		return lerp(STRAFE_SPEED_MULT, 1.0, fwd_dot)
	else:
		return lerp(STRAFE_SPEED_MULT, BACKWARD_SPEED_MULT, -fwd_dot)

func _try_mantle() -> void:
	if mantling or is_on_floor():
		return

	var space := get_world_3d().direct_space_state
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()

	# 1. 从前上方向下探测，寻找可攀顶面
	var ledge_from: Vector3 = global_position + forward * mantle_forward_distance + Vector3.UP * mantle_max_height
	var ledge_to: Vector3 = global_position + forward * mantle_forward_distance + Vector3.UP * mantle_min_height
	var ledge_query := PhysicsRayQueryParameters3D.create(ledge_from, ledge_to)
	ledge_query.exclude = [get_rid()]
	var ledge_hit: Dictionary = space.intersect_ray(ledge_query)
	if ledge_hit.is_empty():
		return

	var ledge_top: Vector3 = ledge_hit.position

	# 2. 确保 ledge 顶面上方 2m 无遮挡（玩家能站得下，避免钻进夹层）
	var clearance_from: Vector3 = ledge_top + Vector3.UP * 0.05
	var clearance_to: Vector3 = clearance_from + Vector3.UP * 2.0
	var clearance_query := PhysicsRayQueryParameters3D.create(clearance_from, clearance_to)
	clearance_query.exclude = [get_rid()]
	if not space.intersect_ray(clearance_query).is_empty():
		return

	# 3. 验证玩家到 ledge 之间确实有墙面（否则可能瞬移到空中浮岛）
	var wall_from: Vector3 = global_position + Vector3.UP * max((ledge_top.y - global_position.y) * 0.5, 0.3)
	var wall_to: Vector3 = wall_from + forward * mantle_forward_distance
	var wall_query := PhysicsRayQueryParameters3D.create(wall_from, wall_to)
	wall_query.exclude = [get_rid()]
	if space.intersect_ray(wall_query).is_empty():
		return

	# 终点比 ledge 边再往前一点，确保玩家落点不会悬在边缘
	_start_mantle(ledge_top + forward * 0.5)

func _start_mantle(target_pos: Vector3) -> void:
	mantling = true
	velocity = Vector3.ZERO
	sliding = false  # 保险：攀爬中强制取消滑铲态
	free_looking = false

	var tween: Tween = create_tween()
	# 随物理帧更新位置，避免和 CharacterBody3D 的帧同步错位导致抖动
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_pos, mantle_duration)
	tween.tween_callback(func() -> void:
		mantling = false
		velocity = Vector3.ZERO
	)

# 隐藏调试：切换飞行 / Noclip 状态
# 切到 ON：保存 collision layer/mask 然后清零（穿墙），velocity 清零；同时取消滑铲/攀爬/free_look。
# 切到 OFF：还原 collision、velocity 清零（避免累积速度让玩家弹飞）。
func _toggle_noclip() -> void:
	if _dead:
		return
	_noclip = not _noclip
	if _noclip:
		_noclip_saved_layer = collision_layer
		_noclip_saved_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		sliding = false
		mantling = false
		free_looking = false
	else:
		collision_layer = _noclip_saved_layer
		collision_mask = _noclip_saved_mask
		velocity = Vector3.ZERO

# 飞行物理：摄像机朝向（含俯仰）作为前向，Space/Ctrl 直接控制 Y 轴
func _process_noclip(delta: float) -> void:
	# 同步视角俯仰：主流程被早返回跳过了，必须在这里手动消化 recoil 冲量并写 head.rotation.x，
	# 否则鼠标上下移动只改 aim_pitch 不显示——飞行截图时无法构图
	if pending_recoil_pitch > 0.0:
		var step: float = min(pending_recoil_pitch, recoil_apply_speed * delta)
		aim_pitch += step
		pending_recoil_pitch -= step
		aim_pitch = clamp(aim_pitch, deg_to_rad(-89), deg_to_rad(89))
	head.rotation.x = aim_pitch

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var move_basis: Basis = camera_3d.global_transform.basis
	var move_vec: Vector3 = (move_basis * Vector3(input_dir.x, 0.0, input_dir.y))
	var speed: float = NOCLIP_SPEED
	if Input.is_action_pressed("sprint"):
		speed *= NOCLIP_SPRINT_MULT
	velocity = move_vec.normalized() * speed if move_vec.length() > 0.01 else Vector3.ZERO
	if Input.is_action_pressed("jump"):
		velocity.y += speed
	if Input.is_action_pressed("crouch"):
		velocity.y -= speed
	move_and_slide()

# 伤害接收层：敌人 / 子弹 / 环境都通过此方法扣血
# source 传入攻击者节点（用于推力反馈）；没有明确来源时传 null
func take_damage(amount: float, source: Node = null) -> void:
	if _dead or amount <= 0.0 or _invuln_timer > 0.0:
		return
	if _noclip:
		return  # 调试飞行免伤

	current_health = max(0.0, current_health - amount)
	_invuln_timer = invulnerability_time
	_shake_timer = shake_duration

	damaged.emit(amount)
	health_changed.emit(current_health, max_health)
	AudioManager.play_player_damaged()

	# 击退冲量写入 _knockback，由 _physics_process 在 velocity 计算之后叠加
	# 这样玩家输入不会覆盖冲量，推力能真正产生位移（约 1m）
	if source is Node3D:
		var away: Vector3 = global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			_knockback = away.normalized() * pushback_force

	if current_health <= 0.0:
		_die()

# 血包 / 未来其他回血来源调用
func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	var effective: float = amount * heal_mult
	var before: float = current_health
	current_health = min(current_health + effective, max_health)
	var gained: float = current_health - before
	if gained > 0.0:
		health_changed.emit(current_health, max_health)
		healed.emit(gained)
		AudioManager.play_player_healed()

func _die() -> void:
	if _dead:
		return
	_dead = true

	# 镜头倒地：head 下沉接近地面 + 侧翻 85°，给"被放倒"的沉重感
	# 放 head 而不是 camera，因为 head_bobbing 用的是 eyes.position，不冲突
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(head, "position:y", -1.3, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(head, "rotation:z", deg_to_rad(85.0), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	died.emit()

# 切后台返回兜底：Windows 失焦时 OS 会释放鼠标 capture，回来时 Godot 内部 mode 状态可能与 OS 错位。
# 仅在游戏中（无 panel/menu/死亡接管）时强制重 apply CAPTURED；input_locked 表示有 panel 在管，让 panel 自己处理。
# 同时 time_scale = 1.0 兜底，防 hit_pause 在失焦瞬间泄漏。
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if _dead or input_locked:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Engine.time_scale = 1.0
