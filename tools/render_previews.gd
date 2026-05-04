extends Node

# 一次性预览图渲染脚本：实例化 6 把武器，3/4 视角拍照存 PNG
# 用法：在 Godot 编辑器打开 tools/render_previews.tscn，按 F6 单独运行此场景
# 完成后 Output 面板打印 "全部渲染完成"，可手动关窗口
# PNG 输出：res://assets/ui/weapons/<weapon_id>.png

const WEAPONS: Array[Dictionary] = [
	{"path": "res://scenes/weapons/pistol.tscn",   "id": "pistol"},
	{"path": "res://scenes/weapons/rifle.tscn",    "id": "rifle"},
	{"path": "res://scenes/weapons/revolver.tscn", "id": "revolver"},
	{"path": "res://scenes/weapons/shotgun.tscn",  "id": "shotgun"},
	{"path": "res://scenes/weapons/heavy_mg.tscn", "id": "heavy_mg"},
	{"path": "res://scenes/weapons/railgun.tscn",  "id": "railgun"},
]

const OUTPUT_DIR: String = "res://assets/ui/weapons/"

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/Camera3D

func _ready() -> void:
	# 确保输出目录存在
	if not DirAccess.dir_exists_absolute(OUTPUT_DIR):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	print("=== 渲染 %d 把武器预览图 ===" % WEAPONS.size())

	for w in WEAPONS:
		await _render_weapon(w["path"], w["id"])

	print("\n=== 全部渲染完成 ===")
	print("PNG 输出位置: %s" % OUTPUT_DIR)
	print("回 Godot 编辑器，FileSystem 面板会自动 reimport，确认 6 个 PNG 都在")
	print("（可以关闭运行窗口了）")

func _render_weapon(scene_path: String, weapon_id: String) -> void:
	var weapon_scene: PackedScene = load(scene_path)
	if weapon_scene == null:
		push_error("加载失败：%s" % scene_path)
		return

	var weapon: Node3D = weapon_scene.instantiate() as Node3D
	if weapon == null:
		push_error("instantiate 失败：%s" % scene_path)
		return
	# weapon.gd._ready() 有断言要求父节点是 weapon_manager（带 shoot_raycast）
	# 渲染上下文下父是 SubViewport 不满足，移除 root 脚本绕过（mesh/动画在子节点不受影响）
	weapon.set_script(null)
	viewport.add_child(weapon)

	# 替换所有 MeshInstance3D 的材质成"灰色 flat + 黑色描边"线稿风
	_apply_outline_style(weapon)

	await get_tree().process_frame

	var aabb: AABB = _compute_aabb(weapon)
	if aabb.size == Vector3.ZERO:
		push_warning("%s AABB 为零，跳过" % weapon_id)
		weapon.queue_free()
		return

	var center: Vector3 = aabb.get_center()
	var size: Vector3 = aabb.size

	# 纯侧视（相机在 -X 方向，看 +X 方向）使武器枪口朝左
	# 武器 mesh 长度沿 -Z，宽度沿 Y。从 -X 看，相机右轴 = 世界 +Z，所以 -Z（枪口）显示在屏幕左
	# camera.size 是视口垂直方向的世界单位数；横向覆盖 = camera.size * aspect
	# 正交投影下相机距离不影响成像（仅影响 near/far clip），位置只要够远即可
	var aspect: float = float(viewport.size.x) / float(viewport.size.y)
	var pad: float = 1.08
	var sz_for_z: float = size.z / aspect * pad
	var sz_for_y: float = size.y * pad
	camera.size = maxf(sz_for_z, sz_for_y)
	camera.position = center + Vector3(-(maxf(size.x, 1.0) * 2.0 + 1.0), 0, 0)
	camera.look_at(center)

	# 触发一次渲染（UPDATE_ONCE），等几帧让 GPU 完成
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = viewport.get_texture().get_image()
	var output_path: String = OUTPUT_DIR + weapon_id + ".png"
	var err: int = img.save_png(output_path)
	if err == OK:
		print("  [%s] -> %s (bbox=%v)" % [weapon_id, output_path, size])
	else:
		push_error("[%s] save_png 失败 err=%d" % [weapon_id, err])

	weapon.queue_free()
	await get_tree().process_frame

# 递归收集所有 MeshInstance3D 的 AABB，转到 root 局部空间合并
func _compute_aabb(root: Node) -> AABB:
	var combined: AABB = AABB()
	var first: bool = true
	var queue: Array = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = node as MeshInstance3D
			var mesh_aabb: AABB = mi.mesh.get_aabb()
			var rel: Transform3D = _relative_transform(mi, root as Node3D)
			var transformed: AABB = rel * mesh_aabb
			if first:
				combined = transformed
				first = false
			else:
				combined = combined.merge(transformed)
		for c in node.get_children():
			queue.append(c)
	return combined

func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t

# 三角洲行动风：灰色 unshaded fill + 黑色 inverted-hull 描边
# 用 next_pass 一气呵成，不需要每个 weapon 配独立 shader
func _make_outline_material() -> StandardMaterial3D:
	var fill: StandardMaterial3D = StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.albedo_color = Color(0.55, 0.55, 0.58)
	var outline: StandardMaterial3D = StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color(0.05, 0.05, 0.05)
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.03
	fill.next_pass = outline
	return fill

func _apply_outline_style(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _make_outline_material()
	for child in node.get_children():
		_apply_outline_style(child)
