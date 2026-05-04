extends Node3D

# 加特林枪管旋转：挂在 minigun barrel MeshInstance3D 上。
# 订阅父武器的 shot_fired 信号 → 每发抬一格转速；停火后按摩擦衰减。
# 设计目标：开火 ~0.3s 内拉满，停火后再"咕噜"转 ~0.6s 才停。

@export var max_spin_speed: float = 28.0       # 满转速度（rad/s）
@export var spin_accel_per_shot: float = 9.0   # 每发增量（rad/s）
@export var spin_friction: float = 14.0        # 自然减速（rad/s²，停火期间）
@export var spin_axis: Vector3 = Vector3(0, 0, 1)   # 围绕本地哪个轴转，默认 z

var _spin_speed: float = 0.0
var _weapon: Node = null

func _ready() -> void:
	# 上溯找最近的 Weapon 父节点（barrel 通常是 weapon/mesh/barrel 这种 2 层结构）
	var n: Node = get_parent()
	while n != null:
		if n is Weapon:
			_weapon = n
			break
		n = n.get_parent()
	if _weapon != null:
		(_weapon as Weapon).shot_fired.connect(_on_shot_fired)

func _on_shot_fired() -> void:
	_spin_speed = minf(_spin_speed + spin_accel_per_shot, max_spin_speed)

func _process(delta: float) -> void:
	# 自然衰减（开火再次 emit 会刷新峰值，所以这里只负责"放手减速"）
	if _spin_speed > 0.0:
		_spin_speed = maxf(_spin_speed - spin_friction * delta, 0.0)
	if _spin_speed > 0.0:
		rotate(spin_axis.normalized(), _spin_speed * delta)
