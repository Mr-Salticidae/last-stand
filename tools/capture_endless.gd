# 无尽模式配图截取工具
#
# 用法（**不能加 --headless**，需要真实渲染管线才有画面可抓）：
#   godot --path . --script res://tools/capture_endless.gd
#
# 产出两张 1920×1080 PNG 到 assets/screenshots/：
#   endless_hud.png      波内中段：右上角「第 N 波 / M:SS」+ 时间条（未转红）+ 场上若干敌人
#   endless_lastten.png  波末最后十秒：倒计时与时间条转红 + 明显的怪潮
#
# 这是真实游戏状态的真实截图：模式、波次、倒计时、敌人全部由 WaveManager 正常驱动，
# 脚本只做三件事——快进到目标波次、把相机摆向敌人、在恰当时刻抓帧。
#
# 注意：脚本直接改 Settings 的成员变量而**不调 set_xxx()**，避免把「无尽模式」
# 写进玩家自己的 user://settings.cfg。
extends SceneTree

# 用前哨站：沙地暖色调 + 有云有阴影，和仓库里现有的宣传图 combat_v0.7.png 是同一张图，
# 观感统一。训练场是灰地板 + 重雾，拍出来整片发白，不适合做宣传配图。
const WORLD: String = "res://scenes/world_outpost.tscn"
const OUT_DIR: String = "res://assets/screenshots/"

# 抓帧分辨率，与仓库现有截图一致（screenshot_handoff.md 第 3 节：宽 1920）
const SHOT_SIZE: Vector2i = Vector2i(1920, 1080)

# 两张图各自的目标状态
const SHOT_A_WAVE: int = 5          # 时长 28s，此时已解锁 runner + 有 1 只精英
const SHOT_A_MIN_ALIVE: int = 4
const SHOT_A_CAPTURE_AT: float = 15.0   # 剩余秒数（> 10 才不会触发红闪，时间条也已明显走掉一截）

const SHOT_B_WAVE: int = 16         # 并发上限 ~22、每次刷 3 只，够堆出怪潮
const SHOT_B_MIN_ALIVE: int = 12
const SHOT_B_CAPTURE_AT: float = 3.5    # <= 10 触发红闪；取 3.5 让时间条也明显偏红、接近抽干

# 构图：固定小幅下压的俯仰角，保证地平线与地面进画面。
# 不要用「瞄准敌人质心」——敌人是环绕玩家收拢的，质心会落到玩家脚下，
# atan2 于是算出接近垂直的仰角，第一次跑就拍到了一整张纯天空。
const AIM_PITCH_DEG: float = -4.0
const AIM_CONE_DEG: float = 32.0    # 半角：判定「敌人在画面内」的锥
# 太近的怪会一只占满半个屏幕，太远又只是一排小黑点。
# 用「距离带」加权：AIM_SWEET_DIST 附近权重最高，两侧线性衰减。
const AIM_MIN_DIST: float = 5.0
const AIM_MAX_DIST: float = 35.0
const AIM_SWEET_DIST: float = 14.0   # 这个距离上敌人大小最可读
const AIM_CONE_STEP_DEG: float = 10.0

# 刷完怪先让它们往玩家收拢一会儿再抓帧：刚出生的都在 28m 外的 spawn point 上
const SETTLE_TIME_SCALE: float = 3.0
const SETTLE_WANT_NEAR: int = 5      # 至少这么多只进到 SETTLE_NEAR_DIST 内
const SETTLE_NEAR_DIST: float = 22.0
# 收拢也不能过头：有怪贴到 7m 以内就立刻停，否则它会占满半个屏幕、甚至挡住 HUD
const SETTLE_TOO_CLOSE: float = 7.0

const FF_TIME_SCALE: float = 6.0    # 等怪堆积时的快进倍率；抓帧前会回到 1.0
const WATCHDOG_SEC: float = 240.0

var _done: bool = false
var _failures: Array[String] = []
var _start_msec: int = 0
var _player: Node = null

func _initialize() -> void:
	print("=== 无尽模式配图截取 ===")
	if DisplayServer.get_name() == "headless":
		push_error("本脚本需要真实渲染，不能加 --headless")
		_done = true
		return
	_start_msec = Time.get_ticks_msec()
	_run()

func _process(_delta: float) -> bool:
	# 每帧续无敌。放在这里是因为 _run() 的各个 await 循环都会经过 _process，
	# 一处覆盖全部等待阶段。
	if _player != null and is_instance_valid(_player):
		_player.set("_invuln_timer", 10.0)
	if not _done and float(Time.get_ticks_msec() - _start_msec) / 1000.0 > WATCHDOG_SEC:
		_fail("看门狗超时：%ds 内没截完" % int(WATCHDOG_SEC))
		_finish()
	return _done

# ---------- 主流程 ----------
func _run() -> void:
	await process_frame
	# autoload 不能在 --script 脚本里按名字引用（那时 GDScript 还没注册这些全局标识符，
	# 会编译报「Identifier not found: Settings」），只能运行时按 /root/ 路径拿。
	var settings: Node = root.get_node_or_null("/root/Settings")
	if settings == null:
		_fail("找不到 Settings autoload")
		_finish()
		return
	# 直接改成员变量，不走 set_xxx() —— 不把「无尽模式」写进玩家的 user://settings.cfg
	settings.set("game_mode_idx", 1)   # 无尽
	settings.set("difficulty_idx", 1)  # 日常训练
	print("模式=无尽  难度=日常训练")

	change_scene_to_file(WORLD)
	# 等场景实例化 + nav_region_baker 完成 bake（它自己要 await 两个物理帧）
	for _i in 40:
		await process_frame

	var wm: Node = _first("wave_manager")
	var player: Node = _first("player")
	if wm == null or player == null:
		_fail("场景里找不到 wave_manager 或 player")
		_finish()
		return
	if not bool(wm.get("_endless")):
		_fail("WaveManager 没进无尽模式（Settings.is_endless() 在它 _ready 时应为 true）")
		_finish()
		return

	_setup_window()
	_setup_player(player)

	await _shoot(wm, player, SHOT_A_WAVE, SHOT_A_MIN_ALIVE, SHOT_A_CAPTURE_AT, "endless_hud.png")
	await _shoot(wm, player, SHOT_B_WAVE, SHOT_B_MIN_ALIVE, SHOT_B_CAPTURE_AT, "endless_lastten.png")

	_finish()

# 无边框 1920×1080：Settings.apply_graphics() 默认会开全屏并跟随显示器分辨率，
# 这里覆盖掉，保证抓出来的图就是 1920 宽
func _setup_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(SHOT_SIZE)
	DisplayServer.window_set_position(Vector2i.ZERO)

func _setup_player(player: Node) -> void:
	_player = player
	# 无敌走 _invuln_timer（take_damage 在它 > 0 时直接 return），每帧在 _process 里续期。
	# 不要去改 max_health —— 那会让 HUD 血条显示成「999992 / 999999」，
	# 调试痕迹直接印在宣传图上（第一版就是这么翻车的）。
	player.set("input_locked", true)
	# 别抢用户的鼠标（CAPTURED 会把光标锁进窗口）
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ---------- 单张截图 ----------
func _shoot(wm: Node, player: Node, wave: int, min_alive: int, capture_at: float, filename: String) -> void:
	print("\n--- 准备 %s（第 %d 波，等 >= %d 只，剩 %.1fs 时抓帧）---" % [filename, wave, min_alive, capture_at])
	_clear_field(wm)
	_unlock_weapons_for_wave(wm, wave)
	_jump_to_wave(wm, wave)

	# 等本波真正进入 COMBAT
	var guard: int = 0
	while int(wm.get("_state")) != 3 and guard < 600:
		guard += 1
		await process_frame
	if int(wm.get("_state")) != 3:
		_fail("%s：等不到本波进入 COMBAT" % filename)
		return

	# 快进攒怪。攒到 min_alive 或逼近抓帧时刻就停
	Engine.time_scale = FF_TIME_SCALE
	while true:
		var alive: int = int(wm.call("alive_enemy_count"))
		var left: float = float(wm.get("wave_time_left"))
		if alive >= min_alive:
			break
		if left <= capture_at + 2.0:
			break   # 时间不够了，有多少拍多少
		await process_frame
	Engine.time_scale = 1.0

	var alive_now: int = int(wm.call("alive_enemy_count"))
	if alive_now < min_alive:
		print("  ⚠ 只攒到 %d 只（目标 %d），继续拍" % [alive_now, min_alive])

	# 让怪往玩家收拢：spawn point 在 ±22m 外，刚出生就抓帧的话画面里全是小黑点
	Engine.time_scale = SETTLE_TIME_SCALE
	var settle_guard: int = 0
	var want_near: int = mini(SETTLE_WANT_NEAR, alive_now)
	while settle_guard < 900:
		if _count_within(player, SETTLE_NEAR_DIST) >= want_near:
			break
		if _min_enemy_dist(player) < SETTLE_TOO_CLOSE:
			break
		if float(wm.get("wave_time_left")) <= capture_at + 2.0:
			break
		settle_guard += 1
		await process_frame
	Engine.time_scale = 1.0
	print("  收拢后 %.0fm 内有 %d 只" % [SETTLE_NEAR_DIST, _count_within(player, SETTLE_NEAR_DIST)])

	# 把倒计时摆到目标剩余秒数。直接写 wave_time_left，HUD 每帧读的就是这个权威值。
	wm.set("wave_time_left", capture_at)
	# 让 HUD 与时间条至少过一帧再抓，否则可能拍到上一帧的旧文本
	await process_frame
	await process_frame

	_aim_at_enemies(player)
	# 相机转向后多等几帧：敌人精灵是 billboard，要重新朝向相机；雾/阴影也要稳定
	for _i in 6:
		await process_frame

	# 波末那张要等红闪到波谷再抓，否则拍出来是橙的、看不出"转红"
	if capture_at <= 10.0:
		# HUD 不在任何组里，按节点名从当前场景取（三张地图里都叫 "HUD"）
		await _wait_for_red_pulse(current_scene.get_node_or_null("HUD"))

	await _capture(filename)
	print("  波次=%d  剩余=%.1fs  场上=%d 只" % [
		int(wm.get("current_wave")), float(wm.get("wave_time_left")), int(wm.call("alive_enemy_count"))
	])

# 清掉上一张遗留的敌人，让每张图的「场上几只」是本波自己刷出来的
func _clear_field(wm: Node) -> void:
	for e in get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	var arr: Array = wm.get("_alive_enemies")
	if arr != null:
		arr.clear()
	wm.set("_spawns_pending", 0)

# 快进到指定波次：把波号退一格，强制 IDLE，再走正常的 start_next_wave()，
# 顺手把波间休整压到几乎为 0。走正常入口是为了让时长/预算/精英排期全部按公式算出来。
func _jump_to_wave(wm: Node, wave: int) -> void:
	wm.set("current_wave", wave - 1)
	wm.set("_state", 0)              # State.IDLE
	wm.call("start_next_wave")
	wm.set("_intermission_timer", 0.02)

# 摆相机：以 10° 步长扫一圈 yaw，取「视锥内敌人最多」的那个朝向；俯仰用固定小幅下压。
# 越近的敌人权重越高，让画面里有扑到近处的怪，而不是一排远处的小黑点。
func _aim_at_enemies(player: Node) -> void:
	var eye: Vector3 = (player as Node3D).global_position + Vector3.UP * 1.5
	var flats: Array[Vector3] = []      # 各敌人的水平方向（已归一化）
	var dists: Array[float] = []
	for e in get_nodes_in_group("enemy"):
		if not (is_instance_valid(e) and e is Node3D):
			continue
		var d: Vector3 = (e as Node3D).global_position - eye
		var flat: Vector3 = Vector3(d.x, 0.0, d.z)
		var dist: float = flat.length()
		# 过近的也要收进来 —— 它们不加分，但要在评分时扣分（见下），
		# 否则「贴脸挡住半个屏幕和 HUD」这件事对朝向选择完全不可见
		if dist < 0.5 or dist > AIM_MAX_DIST:
			continue
		flats.append(flat / dist)
		dists.append(dist)

	if not flats.is_empty():
		var cone_cos: float = cos(deg_to_rad(AIM_CONE_DEG))
		var best_yaw: float = (player as Node3D).rotation.y
		var best_score: float = -1.0
		var steps: int = int(round(360.0 / AIM_CONE_STEP_DEG))
		for step in steps:
			var yaw: float = deg_to_rad(float(step) * AIM_CONE_STEP_DEG)
			var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))   # 玩家前向是 -Z
			var score: float = 0.0
			for i in flats.size():
				if fwd.dot(flats[i]) < cone_cos:
					continue
				if dists[i] < AIM_MIN_DIST:
					score -= 4.0   # 贴脸的是遮挡物，不是卖点
					continue
				# 距离带权重：AIM_SWEET_DIST 处为 1，往两边线性掉到 0.15 保底
				var off: float = absf(dists[i] - AIM_SWEET_DIST)
				score += maxf(1.0 - off / AIM_SWEET_DIST, 0.15)
			if score > best_score:
				best_score = score
				best_yaw = yaw
		(player as Node3D).rotation.y = best_yaw

	var pitch: float = deg_to_rad(AIM_PITCH_DEG)
	player.set("aim_pitch", pitch)
	# aim_pitch 由 _physics_process 写进 head.rotation.x；这里同步写一次，
	# 免得抓帧比下一个物理帧更早导致朝向没生效
	var head: Node = player.get_node_or_null("neck/head")
	if head:
		(head as Node3D).rotation.x = pitch
	# neck 是 free_look 用的，确保它归零
	var neck: Node = player.get_node_or_null("neck")
	if neck:
		(neck as Node3D).rotation.y = 0.0

# 波末红闪是 6Hz 正弦，在「红」与「亮金」之间来回 lerp。随手抓帧大概率落在中间相位、
# 拍出来是橙色，看不出「转红」。这里等到波谷（绿通道最低≈最红）再抓。
# 只是挑相位，不改颜色——改颜色就是伪造了。
func _wait_for_red_pulse(hud: Node) -> void:
	if hud == null:
		return
	var label: Node = hud.get_node_or_null("WaveLabel")
	if label == null:
		return
	for _i in 40:
		if (label as CanvasItem).modulate.g < 0.35:
			return
		await process_frame

# ---------- 抓帧 ----------
func _capture(filename: String) -> void:
	# 必须等本帧画完，否则 get_image() 拿到的是上一帧甚至空纹理
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = root.get_texture()
	if tex == null:
		_fail("%s：root.get_texture() 为空" % filename)
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		_fail("%s：抓到的图像为空" % filename)
		return
	var abs_dir: String = ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var abs_path: String = ProjectSettings.globalize_path(OUT_DIR + filename)
	var err: int = img.save_png(abs_path)
	if err != OK:
		_fail("%s：save_png 失败 err=%d" % [filename, err])
		return
	print("  √ 已存 %s  %d×%d" % [filename, img.get_width(), img.get_height()])
	if img.get_width() != SHOT_SIZE.x:
		print("  ⚠ 实际宽度 %d ≠ 目标 %d（显示器可能小于 1920，或窗口被系统限制）"
			% [img.get_width(), SHOT_SIZE.x])

# ---------- 杂项 ----------
# 按目标波次补齐武器解锁。解锁表（第 2 波 rifle / 4 波 shotgun / 6 波 revolver）只在
# 那几波恰好命中，而我们是直接跳过去的，不补的话第 16 波的武器栏会全是「未解锁」，
# 和画面上的波号自相矛盾。反过来也不能一次全解锁——第 5 波不该有左轮。
func _unlock_weapons_for_wave(wm: Node, wave: int) -> void:
	var wpm: Node = _first("weapon_manager")
	if wpm == null or not wpm.has_method("unlock_weapon"):
		return
	var schedule: Dictionary = wm.get("weapon_unlock_schedule")
	if schedule == null:
		return
	for w in schedule.keys():
		if int(w) <= wave:
			wpm.call("unlock_weapon", String(schedule[w]))
	if wpm.has_method("refill_all_reserves"):
		wpm.call("refill_all_reserves")

func _min_enemy_dist(player: Node) -> float:
	var origin: Vector3 = (player as Node3D).global_position
	var best: float = INF
	for e in get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D:
			best = minf(best, origin.distance_to((e as Node3D).global_position))
	return best

func _count_within(player: Node, radius: float) -> int:
	var origin: Vector3 = (player as Node3D).global_position
	var n: int = 0
	for e in get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D:
			if origin.distance_to((e as Node3D).global_position) <= radius:
				n += 1
	return n

func _first(group: String) -> Node:
	return get_first_node_in_group(group)

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FAIL: %s" % msg)

func _finish() -> void:
	Engine.time_scale = 1.0
	print("---")
	if _failures.is_empty():
		print("CAPTURE OK")
		_done = true
		quit(0)
	else:
		print("CAPTURE FAILED (%d)" % _failures.size())
		_done = true
		quit(1)
