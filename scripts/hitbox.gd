class_name Hitbox extends Area3D

# 伤害转发层：武器 raycast 打中 hitbox 后调用此处的 take_damage，
# 按倍率放大再转发给父节点（通常是敌人根）。
# "爆头 = 头部 hitbox 倍率 2.5" 只是数据配置，武器无需感知身体部位。
@export var damage_multiplier: float = 1.0

func take_damage(amount: float) -> void:
	var target: Node = get_parent()
	if target and target.has_method("take_damage"):
		target.take_damage(amount * damage_multiplier)
