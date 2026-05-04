class_name SpawnPoint extends Marker3D

# 生成点：WaveManager 调 play_smoke_effect 先播红烟警示，await 完成后实例化敌人
# 烟雾用 MeshInstance + 程序材质临时代替，后续替换为 GPUParticles3D 粒子

const SMOKE_COLOR: Color = Color(0.85, 0.1, 0.08, 0.8)
const SMOKE_EMISSION: Color = Color(1.0, 0.2, 0.1)

# duration: 烟雾从初始到消散的总秒数；敌人在 await 结束后由外部生成
func play_smoke_effect(duration: float = 0.8) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = SMOKE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = SMOKE_EMISSION
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat

	get_tree().current_scene.add_child(mesh)
	mesh.global_position = global_position + Vector3.UP * 0.7

	# Tween：球体膨胀 + 前 30% 时间后开始淡出
	var tween := mesh.create_tween().set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * 7.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_delay(duration * 0.3)

	await get_tree().create_timer(duration).timeout
	if is_instance_valid(mesh):
		mesh.queue_free()
