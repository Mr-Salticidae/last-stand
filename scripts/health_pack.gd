class_name HealthPack extends Area3D

# 碰撞自动捡起的血包：玩家走过就 heal + 消失
# enemy._die 里按概率 spawn

@export var heal_amount: float = 30.0
@export var bob_amplitude: float = 0.2   # 上下浮动高度
@export var bob_period: float = 1.6      # 一次完整浮动周期秒数

@onready var _mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# 上下浮动循环，给玩家视觉提示"这是可互动道具"
	if _mesh:
		var tween := _mesh.create_tween().set_loops()
		tween.tween_property(_mesh, "position:y", bob_amplitude, bob_period * 0.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(_mesh, "position:y", 0.0, bob_period * 0.5).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("heal"):
		body.heal(heal_amount)
		AudioManager.play_pickup()
		queue_free()
