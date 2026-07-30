class_name SpawnPoint extends Marker3D

# 生成点：WaveManager 调 play_smoke_effect 先播红烟警示，await 完成后实例化敌人
# 烟雾用 MeshInstance + 程序材质临时代替，后续替换为 GPUParticles3D 粒子

const SMOKE_COLOR: Color = Color(0.85, 0.1, 0.08, 0.8)
const SMOKE_EMISSION: Color = Color(1.0, 0.2, 0.1)
# 同一个点连续刷怪时，多团红烟会叠在一起糊成一坨。冷却期内跳过视觉、只等时间，
# 敌人照常生成——三张图各只有 6 个生成点，无尽后期同点复用很密集。
const SMOKE_MIN_INTERVAL: float = 0.5

var _last_smoke_msec: int = -100000

# duration: 烟雾从初始到消散的总秒数；敌人在 await 结束后由外部生成
# allow_skip: 仅无尽模式传 true。标准模式必须恒为 false——
#   它的生成是「洗牌 + 0.1s stagger」，换轮时同一个点的间隔可以短到 0.1s，
#   一旦允许跳过，第 7 波起就会有敌人完全没有红烟预警凭空出现。
func play_smoke_effect(duration: float = 0.8, allow_skip: bool = false) -> void:
	var now: int = Time.get_ticks_msec()
	if allow_skip and float(now - _last_smoke_msec) / 1000.0 < SMOKE_MIN_INTERVAL:
		await get_tree().create_timer(duration).timeout
		return
	_last_smoke_msec = now

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
