extends NavigationRegion3D

# 顺序关键：
# 1. 先 bake NavigationMesh（scene tree 里只有纯 MeshInstance3D 作为源）
# 2. 再给 MeshInstance3D 生成 StaticBody3D + ConcavePolygonShape3D 做物理碰撞
# 如果反过来，StaticBody 子节点可能干扰 bake 识别 MeshInstance
#
# 另：NavigationServer 的 map 内部数据在 bake 后需要手动 force_update 才 sync，
# 否则 map_get_path 返回空 path（敌人罚站经典原因）

func _ready() -> void:
	await get_tree().physics_frame
	bake_navigation_mesh(false)
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)
	await get_tree().physics_frame
	_generate_collisions(self)

func _generate_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			child.create_trimesh_collision()
		_generate_collisions(child)
