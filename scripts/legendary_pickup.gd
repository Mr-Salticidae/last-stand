extends Area3D

# 传说武器拾取物。玩家走入 Area3D 即拾取（A1 方案：自动拾取，无需按键）。
# weapon_scene 在 Inspector 拖入对应武器场景（heavy_mg.tscn / railgun.tscn 等）。
# 拾取后调 weapon_manager.equip_legendary(scene)，自身销毁。

@export var weapon_scene: PackedScene
@export var rotation_speed: float = 1.5         # 自旋角速度（rad/s）
@export var float_amplitude: float = 0.15       # 浮空 sin 振幅（米）
@export var float_frequency: float = 1.2        # 浮空频率（Hz）
@export var pulse_color: Color = Color(1.0, 0.55, 0.15, 1)  # 发光颜色（橙）

@onready var _mesh_root: Node3D = $MeshRoot

var _t: float = 0.0
var _base_y: float = 0.0
var _picked: bool = false

func _ready() -> void:
	add_to_group("legendary_pickup")
	# 触发器仅监测玩家
	body_entered.connect(_on_body_entered)
	_base_y = global_position.y

func _process(delta: float) -> void:
	if _picked:
		return
	_t += delta
	# 浮空 + 自旋（视觉辨识度，远处也能看到）
	if _mesh_root:
		_mesh_root.rotation.y += rotation_speed * delta
		_mesh_root.position.y = sin(_t * TAU * float_frequency) * float_amplitude

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
