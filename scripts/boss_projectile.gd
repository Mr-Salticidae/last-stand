class_name BossProjectile extends Area3D

# Boss 远程攻击投射物（v0.4-B B5-B）
# 直线匀速运动，命中玩家 → take_damage + queue_free；命中墙/地 → queue_free
# 速度 6 m/s 慢速，给玩家侧移闪避窗口（玩家 sprint 8 m/s 能跑过）
# 寿命 5s 自动销毁（防飞出地图永生）
# collision_layer = 0：武器 raycast 不会误伤这个投射物
# collision_mask = 1：能检测玩家 + 静态地形（layer 1 默认）

const PROJECTILE_SPEED: float = 12.0    # v0.4-B：6→12，给点紧急感（玩家 sprint 8 都跑不过，必须侧移）
const PROJECTILE_LIFETIME: float = 5.0
# 脉冲闪烁：跟玩家自己开枪命中特效区分（用户反馈"区分度低"）
# 紫色基底（跟玩家武器橙黄/血色形成强反差）+ 亮度脉冲 + 颜色脉冲（紫 ↔ 亮粉白）双叠加
const PULSE_HZ: float = 6.0
const PULSE_EMISSION_MIN: float = 1.5
const PULSE_EMISSION_MAX: float = 8.0
const PULSE_COLOR_DARK: Color = Color(1.0, 0.2, 1.5)    # 深紫（低能量帧）
const PULSE_COLOR_BRIGHT: Color = Color(2.5, 1.5, 3.0)  # 亮粉白（高能量帧）

@onready var _mesh: MeshInstance3D = $MeshInstance3D
var _direction: Vector3 = Vector3.FORWARD
var _damage: float = 24.0
var _lifetime: float = PROJECTILE_LIFETIME
var _pulse_time: float = 0.0
var _pulse_mat: BaseMaterial3D = null   # 独立 material 副本（每个投射物独立闪烁相位）

func _ready() -> void:
	# 入组供无尽模式波末清场用：只清敌人不清在飞的弹，玩家会在被锁输入的商店界面里挨打
	add_to_group("boss_projectile")
	collision_layer = 0   # 不被武器 raycast 击中
	collision_mask = 1    # 检测 layer 1（玩家 + 世界几何）
	monitorable = false
	monitoring = true
	body_entered.connect(_on_body_entered)
	# 复制 material 让每个投射物独立闪烁（共享 material 会让所有同时同步闪，看起来不自然）
	if _mesh:
		var orig: Material = _mesh.get_surface_override_material(0)
		if orig is BaseMaterial3D:
			_pulse_mat = (orig as BaseMaterial3D).duplicate()
			_mesh.set_surface_override_material(0, _pulse_mat)
	# 随机起始相位：让多个投射物不同步闪烁
	_pulse_time = randf() * (1.0 / PULSE_HZ)

# Boss 调用：发射前设方向 + 伤害
func set_direction(dir: Vector3) -> void:
	if dir.length_squared() < 0.001:
		_direction = Vector3.FORWARD
	else:
		_direction = dir.normalized()
	# 朝运动方向旋转 mesh（视觉对齐）
	if _direction.length() > 0.001:
		look_at(global_position + _direction, Vector3.UP)

func set_damage(dmg: float) -> void:
	_damage = dmg

func _physics_process(delta: float) -> void:
	global_position += _direction * PROJECTILE_SPEED * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	# 脉冲闪烁：emission 强度 + 颜色双脉冲（紫深→粉白亮→紫深）
	if _pulse_mat:
		_pulse_time += delta
		var pulse: float = 0.5 + 0.5 * sin(_pulse_time * PULSE_HZ * TAU)  # [0, 1]
		_pulse_mat.emission_energy_multiplier = lerp(PULSE_EMISSION_MIN, PULSE_EMISSION_MAX, pulse)
		_pulse_mat.emission = PULSE_COLOR_DARK.lerp(PULSE_COLOR_BRIGHT, pulse)

func _on_body_entered(body: Node3D) -> void:
	if body == self:
		return
	# 玩家命中：调 take_damage（含击退）
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(_damage, self)
	# 不管命中什么 body 都消失（玩家 / 墙 / 地 / 敌人）
	queue_free()
