extends Area3D

# 传说武器拾取物。玩家走入 Area3D 即拾取（A1 方案：自动拾取，无需按键）。
# weapon_scene 在 Inspector 拖入对应武器场景（heavy_mg.tscn / railgun.tscn 等）。
# 拾取后调 weapon_manager.equip_legendary(scene)，自身销毁。
# 寿命：复用 Settings 难度档 health_pack_lifetime × LIFETIME_MULT（legendary 更稀有给更长缓冲）
# 过期：稳定期 → 5s 旋转 + 浮空 ×2 警告 → 0.4s scale fade → free

const DEFAULT_HEALTH_PACK_LIFETIME: float = 60.0
const LIFETIME_MULT: float = 1.5  # 比血包寿命更长（recruit 135s / standard 90s / breach 45s）
const FADE_WARNING_SECONDS: float = 5.0
const FADE_OUT_DURATION: float = 0.4
const WARNING_SPEED_MULT: float = 2.0

@export var weapon_scene: PackedScene
@export var rotation_speed: float = 1.5         # 自旋角速度（rad/s）
@export var float_amplitude: float = 0.15       # 浮空 sin 振幅（米）
@export var float_frequency: float = 1.2        # 浮空频率（Hz）
@export var pulse_color: Color = Color(1.0, 0.55, 0.15, 1)  # 发光颜色（橙）

@onready var _mesh_root: Node3D = $MeshRoot

var _t: float = 0.0
var _base_y: float = 0.0
var _picked: bool = false
var _speed_mult: float = 1.0  # 警告期 _process 加速旋转/浮空用

func _ready() -> void:
	add_to_group("legendary_pickup")
	# 触发器仅监测玩家
	body_entered.connect(_on_body_entered)
	_base_y = global_position.y
	_start_lifecycle()

func _process(delta: float) -> void:
	if _picked:
		return
	_t += delta * _speed_mult
	# 浮空 + 自旋（视觉辨识度，远处也能看到）；警告期 _speed_mult ×2 提示即将过期
	if _mesh_root:
		_mesh_root.rotation.y += rotation_speed * _speed_mult * delta
		_mesh_root.position.y = sin(_t * TAU * float_frequency) * float_amplitude

func _start_lifecycle() -> void:
	var hp_lifetime: float = float(Settings.get_difficulty_param("health_pack_lifetime", DEFAULT_HEALTH_PACK_LIFETIME))
	var lifetime: float = hp_lifetime * LIFETIME_MULT
	var stable_duration: float = max(0.0, lifetime - FADE_WARNING_SECONDS)
	if stable_duration > 0.0:
		await get_tree().create_timer(stable_duration).timeout
		if _picked or not is_instance_valid(self):
			return
	# 警告期：旋转 + 浮空频率 ×2
	_speed_mult = WARNING_SPEED_MULT
	await get_tree().create_timer(FADE_WARNING_SECONDS).timeout
	if _picked or not is_instance_valid(self):
		return
	_expire()

func _expire() -> void:
	_picked = true  # 防 fade 期间玩家撞上重复触发拾取路径
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, FADE_OUT_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	if is_instance_valid(self):
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if not body.is_in_group("player"):
		return
	if weapon_scene == null:
		push_warning("legendary_pickup: weapon_scene 未指定")
		queue_free()
		return
	var wpm: Node = get_tree().get_first_node_in_group("weapon_manager")
	if wpm == null or not wpm.has_method("equip_legendary"):
		push_warning("legendary_pickup: 找不到 weapon_manager / 没有 equip_legendary")
		return
	_picked = true
	wpm.equip_legendary(weapon_scene)
	AudioManager.play_pickup()
	queue_free()
