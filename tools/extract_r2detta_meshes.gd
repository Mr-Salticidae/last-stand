@tool
extends EditorScript

# 一次性脚本：从 r2detta FBX pack 抽出 4 个候选武器，把每把武器的根节点 + 所有子 MeshInstance3D
# （弹匣 / Top / Front 等部件）合并到单个 ArrayMesh 存成 .tres 文件
# 用法：
#   1. 在 Godot 编辑器里打开本文件
#   2. 点 File → Run（或 Ctrl+Shift+X）
#   3. 看 Output 面板：每把武器会显示 "merged ... bbox=... surfaces=N (从 M 个 MeshInstance3D 合并)"
#
# 输出位置：res://assets/weapons/models/r2detta_<NAME>.tres
#
# Minigun 特殊处理：识别 barrel 子节点（名字含 "barrel" / "rotor"）
# 输出两个 .tres：r2detta_Minigun_body.tres + r2detta_Minigun_barrel.tres
# barrel 顶点以 barrel 自身 AABB 中心为原点，便于 heavy_mg.tscn 里绕 z 轴旋转。
# 仍保留 r2detta_Minigun.tres 兼容旧场景。

const FBX_PATH: String = "res://assets/weapons_r2detta/low-poly-weapon-asset-pack/source/Weapons_SketchFab.fbx"
const OUTPUT_DIR: String = "res://assets/weapons/models/"
const WEAPONS: Array[String] = ["M60", "M249", "Minigun", "FN2000"]

# 武器名 → 是否拆分 barrel
const SPLIT_BARREL: Dictionary = {"Minigun": true}
# barrel 子节点名匹配关键字（小写，子串匹配）
# r2detta 的 Minigun 把"前段（旋转枪管 + 枪罩）"打包在 Minigun_Front 子节点里，
# 视觉上整段一起转就是加特林的标准效果，所以 "front" 也算 barrel
const BARREL_KEYWORDS: Array[String] = ["barrel", "rotor", "front"]

func _run() -> void:
	var packed: PackedScene = load(FBX_PATH)
	if packed == null:
		push_error("FBX 加载失败：%s" % FBX_PATH)
		return
	var scene_root: Node = packed.instantiate()
	if scene_root == null:
		push_error("FBX instantiate 失败")
		return

	print("=== r2detta FBX 节点树 ===")
	_dump_tree(scene_root, 0)
	print("==========================")

	for wname in WEAPONS:
		print("--- 处理 %s ---" % wname)
		var weapon_root: Node3D = _find_node3d(scene_root, wname)
		if weapon_root == null:
			push_warning("未找到武器节点：%s" % wname)
			continue

		# 收集 weapon_root 子树下所有 MeshInstance3D 的 mesh + 它们相对 weapon_root 的累积 transform
		var collected: Array = []
		_collect_mesh_instances(weapon_root, weapon_root, collected)

		if collected.is_empty():
			push_warning("%s 子树没有 mesh" % wname)
			continue

		# 1) 总是输出原版合并 .tres（兼容现有场景）
		var merged: ArrayMesh = ArrayMesh.new()
		for entry in collected:
			_append_to_merged(merged, entry.mesh, entry.transform, entry.node_name)
		var save_path: String = "%sr2detta_%s.tres" % [OUTPUT_DIR, wname]
		var err: int = ResourceSaver.save(merged, save_path)
		if err == OK:
			var aabb: AABB = merged.get_aabb()
			print("merged %s | bbox=%v | surfaces=%d (从 %d 个 MeshInstance3D 合并)" % [save_path, aabb.size, merged.get_surface_count(), collected.size()])
		else:
			push_error("保存失败 %s err=%d" % [save_path, err])

		# 2) 需要拆 barrel 的武器：再输出 body / barrel 两个独立 .tres
		if SPLIT_BARREL.get(wname, false):
			_split_and_save(wname, collected)

	scene_root.queue_free()
	print("=== 完成 ===")

# 把 collected 按子节点名拆成 body / barrel 两组，分别合并为独立 ArrayMesh 存盘。
# barrel 顶点平移到以 barrel AABB 中心为原点，便于场景里绕 z 轴自旋。
func _split_and_save(wname: String, collected: Array) -> void:
	var body_entries: Array = []
	var barrel_entries: Array = []
	for entry in collected:
		var nm_lower: String = (entry.node_name as String).to_lower()
		var is_barrel: bool = false
		for kw in BARREL_KEYWORDS:
			if kw in nm_lower:
				is_barrel = true
				break
		if is_barrel:
			barrel_entries.append(entry)
		else:
			body_entries.append(entry)

	if barrel_entries.is_empty():
		push_warning("%s 没找到 barrel 子节点（关键字：%s）；候选子节点：%s" % [wname, BARREL_KEYWORDS, _list_names(collected)])
		return

	print("  → barrel 子节点 %d 个：%s" % [barrel_entries.size(), _list_names(barrel_entries)])
	print("  → body 子节点 %d 个：%s" % [body_entries.size(), _list_names(body_entries)])

	# barrel pivot：所有 barrel mesh 在 weapon-local 空间下顶点的总体 AABB 中心
	var pivot: Vector3 = _compute_pivot(barrel_entries)
	print("  → barrel pivot (weapon-local)：%v" % pivot)
	print("    在 heavy_mg.tscn 里 barrel MeshInstance3D 的 transform.origin 应填这个值")

	# body：用原 transform 直接合并
	var body_mesh: ArrayMesh = ArrayMesh.new()
	for entry in body_entries:
		_append_to_merged(body_mesh, entry.mesh, entry.transform, entry.node_name)
	var body_path: String = "%sr2detta_%s_body.tres" % [OUTPUT_DIR, wname]
	var berr: int = ResourceSaver.save(body_mesh, body_path)
	if berr == OK:
		print("  saved %s | bbox=%v | surfaces=%d" % [body_path, body_mesh.get_aabb().size, body_mesh.get_surface_count()])
	else:
		push_error("body 保存失败 err=%d" % berr)

	# barrel：transform 减去 pivot，使 barrel mesh 以自身中心为原点
	var pivot_offset: Transform3D = Transform3D(Basis.IDENTITY, -pivot)
	var barrel_mesh: ArrayMesh = ArrayMesh.new()
	for entry in barrel_entries:
		var shifted: Transform3D = pivot_offset * entry.transform
		_append_to_merged(barrel_mesh, entry.mesh, shifted, entry.node_name)
	var barrel_path: String = "%sr2detta_%s_barrel.tres" % [OUTPUT_DIR, wname]
	var rerr: int = ResourceSaver.save(barrel_mesh, barrel_path)
	if rerr == OK:
		print("  saved %s | bbox=%v | surfaces=%d (顶点已相对 pivot 平移)" % [barrel_path, barrel_mesh.get_aabb().size, barrel_mesh.get_surface_count()])
	else:
		push_error("barrel 保存失败 err=%d" % rerr)

# 把 entries 列表所有 mesh 的顶点变换到 weapon-local 空间，求 AABB 中心
func _compute_pivot(entries: Array) -> Vector3:
	var have_any: bool = false
	var aabb: AABB = AABB()
	for entry in entries:
		var src_mesh: Mesh = entry.mesh
		var xform: Transform3D = entry.transform
		for si in range(src_mesh.get_surface_count()):
			var arr: Array = src_mesh.surface_get_arrays(si)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = xform * v
				if not have_any:
					aabb = AABB(p, Vector3.ZERO)
					have_any = true
				else:
					aabb = aabb.expand(p)
	return aabb.position + aabb.size * 0.5

func _list_names(entries: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for entry in entries:
		names.append(entry.node_name)
	return ", ".join(names)

# 递归收集 mi 子树所有 MeshInstance3D 的 mesh + 相对 root 的 transform
func _collect_mesh_instances(node: Node, root: Node3D, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = node as MeshInstance3D
		var rel: Transform3D = _relative_transform(mi, root)
		out.append({"mesh": mi.mesh, "transform": rel, "node_name": mi.name})
	for child in node.get_children():
		_collect_mesh_instances(child, root, out)

# 计算 node 相对 root 的累积 transform（vertex 从 node 局部空间 → root 局部空间）
func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t

# 把 src_mesh 的所有 surfaces 复制到 merged，每个顶点应用 xform，每个 surface 保留各自材质
func _append_to_merged(merged: ArrayMesh, src_mesh: Mesh, xform: Transform3D, source_label: String) -> void:
	for si in range(src_mesh.get_surface_count()):
		var arr: Array = src_mesh.surface_get_arrays(si)
		# 应用 xform 到 vertex 位置
		if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var new_verts: PackedVector3Array = PackedVector3Array()
			new_verts.resize(verts.size())
			for i in range(verts.size()):
				new_verts[i] = xform * verts[i]
			arr[Mesh.ARRAY_VERTEX] = new_verts
		# 法线只用 basis 旋转（不平移），并归一化（防 scale 不均匀导致变形）
		if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var new_normals: PackedVector3Array = PackedVector3Array()
			new_normals.resize(normals.size())
			for i in range(normals.size()):
				new_normals[i] = (xform.basis * normals[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = new_normals
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat: Material = src_mesh.surface_get_material(si)
		if mat != null:
			merged.surface_set_material(merged.get_surface_count() - 1, mat)
		# 打印每个 surface 的材质 albedo（用于诊断"白模"是不是颜色本身就是白）
		var albedo_str: String = "<not StandardMaterial3D>"
		if mat is StandardMaterial3D:
			albedo_str = str((mat as StandardMaterial3D).albedo_color)
		print("    [%s] surface[%d] mat=%s albedo=%s" % [source_label, si, mat, albedo_str])

# 找名字含 name_substr 的第一个 Node3D（深度优先，先匹配浅层）
func _find_node3d(node: Node, name_substr: String) -> Node3D:
	if node is Node3D and name_substr.to_lower() in node.name.to_lower():
		return node
	for child in node.get_children():
		var r: Node3D = _find_node3d(child, name_substr)
		if r != null:
			return r
	return null

func _dump_tree(node: Node, depth: int) -> void:
	var prefix: String = "  ".repeat(depth)
	var type_str: String = " (MeshInstance3D)" if node is MeshInstance3D else ""
	print("%s%s%s" % [prefix, node.name, type_str])
	for child in node.get_children():
		_dump_tree(child, depth + 1)
