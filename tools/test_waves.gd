# Dev tool: 波次系统无头冒烟测试（标准 30 波 / 无尽 双模式）。
# 真把关卡跑起来验证整条链路——编译通过并不代表链路是通的。
#
# Run:
#   godot --headless --path . --script res://tools/test_waves.gd            # 默认无尽
#   godot --headless --path . --script res://tools/test_waves.gd -- classic # 标准 30 波
#   godot --headless --path . --script res://tools/test_waves.gd -- death   # 无尽 + 波中途阵亡
#
# 无尽模式验：定时过波 / 持续刷怪 / 并发闸门 / 精英与 BOSS 排期 / 波末清场 / 接回商店
# 标准模式验：杀光过波 / 本波总数符合公式 / 无尽那套代码全程不介入（回归防线）
#
# 两种模式都让玩家无敌（只验波次系统，不验战斗平衡），并替玩家点掉每波的升级面板。
# 断言失败 print FAIL 并 exit 1；全过 print "WAVE TEST OK"。
extends SceneTree

const TARGET_WAVE: int = 6            # 至少跑完这么多波（无尽默认第 6 波是首个 BOSS 波）
const TIME_SCALE: float = 4.0
const WATCHDOG_SECONDS: float = 180.0 # 墙钟看门狗，真卡波时不至于挂死

var _endless: bool = true
var _wm: Node = null
var _panel: Node = null
var _player: Node = null
var _sample_timer: float = 0.0
var _start_msec: int = 0
var _failures: Array[String] = []
var _peak_alive: int = 0
var _waves_seen: Array[int] = []
var _last_wave_logged: int = -1
var _done: bool = false
var _booted: bool = false
var _wave_peak: Dictionary = {}       # wave -> 本波刷出的最大存活数
var _wave_specials: Dictionary = {}   # wave -> Vector2i(精英数, BOSS 数)
var _classic_totals: Dictionary = {}  # wave -> 标准模式的本波计划总数
# 阵亡场景：第 2 波打到一半把玩家打死，然后盯足够长的时间，
# 确认波次泵真的停摆了（这条 bug 就是因为原来的测试让玩家无敌才漏掉的）
var _death_mode: bool = false
var _killed_player: bool = false
var _death_msec: int = 0
var _wave_at_death: int = 0
var _alive_at_death: int = 0

func _initialize() -> void:
	_start_msec = Time.get_ticks_msec()

# 关卡在第一帧才起：这个脚本本身就是 MainLoop，编译期没有 autoload 标识符
#（Settings / AudioManager 只能在运行时按 /root/ 路径拿）
func _boot() -> void:
	_booted = true
	for a in OS.get_cmdline_user_args():
		if a == "classic":
			_endless = false
		elif a == "death":
			_death_mode = true
	var settings: Node = root.get_node_or_null("/root/Settings")
	if settings == null:
		_fail("找不到 Settings autoload")
		_finish()
		return
	settings.game_mode_idx = 0 if not _endless else 1
	settings.difficulty_idx = 1    # 日常训练
	Engine.time_scale = TIME_SCALE

	var packed: PackedScene = load("res://scenes/world_training.tscn")
	if packed == null:
		_fail("world_training.tscn 加载失败")
		_finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	print("=== WAVE SMOKE TEST ===")
	print("mode=%s difficulty=%s time_scale=%.1f" % [
		settings.get_game_mode()["key"], settings.get_difficulty_profile()["key"], TIME_SCALE
	])

func _process(delta: float) -> bool:
	if _done:
		return true
	if not _booted:
		_boot()
		return _done
	# 看门狗用真实墙钟，不受 time_scale 影响
	if float(Time.get_ticks_msec() - _start_msec) / 1000.0 > WATCHDOG_SECONDS:
		_fail("看门狗超时：%ds 内没跑完 %d 波（疑似卡波）" % [int(WATCHDOG_SECONDS), TARGET_WAVE])
		_finish()
		return true

	if _wm == null or not is_instance_valid(_wm):
		_wm = get_first_node_in_group("wave_manager")
		if _wm == null:
			return false
	if _player == null or not is_instance_valid(_player):
		_player = get_first_node_in_group("player")
		if _player and "max_health" in _player:
			_player.max_health = 999999.0
			_player.current_health = 999999.0


	# 无头环境没有输入，替玩家按"继续"，否则每波结束都卡在商店。
	# 阵亡之后不能再关：那之后商店"是否弹出"本身就是被断言的对象。
	if _panel == null or not is_instance_valid(_panel):
		_panel = get_first_node_in_group("upgrade_panel")
	if _panel and _panel.visible and not _killed_player:
		_panel.call("_close_panel")

	if _death_mode:
		_death_tick()
		return _done

	var wave: int = int(_wm.current_wave)
	if wave != _last_wave_logged:
		_last_wave_logged = wave
		if wave > 0 and not _waves_seen.has(wave):
			_waves_seen.append(wave)

	var alive: int = int(_wm.alive_enemy_count())
	_peak_alive = maxi(_peak_alive, alive)
	if wave > 0:
		_wave_peak[wave] = maxi(int(_wave_peak.get(wave, 0)), alive)
		# 精英/BOSS 走的是"波内定时预定投放"这条独立代码路径，单独确认它真的走到了
		var specials: Vector2i = _count_specials()
		var prev: Vector2i = _wave_specials.get(wave, Vector2i.ZERO)
		_wave_specials[wave] = Vector2i(maxi(prev.x, specials.x), maxi(prev.y, specials.y))

	# 标准模式靠"杀光"推波，无头环境没人开枪 → 代劳，否则永远停在第 1 波
	if not _endless:
		# _wave_total 要每帧取最大值：current_wave 在 INTERMISSION 就自增了，
		# 而 _wave_total 要等 _spawn_current_wave 才写——在换波那一帧读会拿到上一波的数
		if wave > 0:
			_classic_totals[wave] = maxi(int(_classic_totals.get(wave, 0)), int(_wm.get("_wave_total")))
		_classic_kill_pass()

	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = 2.0
		print("  W%-2d  t_left=%5.1f/%4.1f  alive=%-3d  score=%-6d  cr=%-6d  state=%s" % [
			wave, float(_wm.wave_time_left), float(_wm.wave_duration),
			alive, int(_wm.total_score), int(_wm.currency), _state_name(),
		])
		_check_invariants(wave, alive)

	if _waves_seen.size() > TARGET_WAVE:
		_finish()
		return true
	return false

# 标准模式：把已落地的敌人打死（走正常 take_damage → _die → died 信号，
# 这样计分/货币/连击/清波判定全都真的跑一遍）
func _classic_kill_pass() -> void:
	for e in get_nodes_in_group("enemy"):
		if e.has_method("is_dead") and e.is_dead():
			continue
		if e.has_method("take_damage"):
			e.take_damage(999999.0)

# 阵亡场景：第 2 波中途把玩家打死，随后观察 25 秒（模拟时间，够走完剩余波长 + 休整 + 面板延迟）。
# 断言：波号不再推进、倒计时停在原地、不再刷新敌人、升级商店绝不弹出。
func _death_tick() -> void:
	if _panel == null or not is_instance_valid(_panel):
		_panel = get_first_node_in_group("upgrade_panel")
	var wave: int = int(_wm.current_wave)

	if not _killed_player:
		# 必须在第 2 波的 COMBAT 中段动手：波次交界（INTERMISSION）时 wave_time_left 本来就是 0、
		# 场上也没怪，那种退化时机测不出任何东西
		var dur: float = float(_wm.wave_duration)
		var left: float = float(_wm.wave_time_left)
		if wave >= 2 and int(_wm.get("_state")) == 3 and left > dur * 0.3 and left < dur * 0.7:
			_killed_player = true
			_death_msec = Time.get_ticks_msec()
			_wave_at_death = wave
			_alive_at_death = int(_wm.alive_enemy_count())
			print("  第 %d 波 t_left=%.1f 时把玩家打死（此刻场上 %d 只）"
				% [wave, float(_wm.wave_time_left), _alive_at_death])
			_player.take_damage(9999999.0, null)
			if not ("_dead" in _player and _player._dead):
				_fail("take_damage 之后玩家并没有进入死亡状态，测试前提不成立")
				_finish()
		return

	# 死后观察期
	if _panel and _panel.visible:
		_fail("玩家已阵亡，升级商店仍然弹了出来（会盖住死亡结算页并夺走鼠标）")
	if int(_wm.current_wave) > _wave_at_death:
		_fail("玩家已阵亡，波次仍从第 %d 波推进到了第 %d 波" % [_wave_at_death, int(_wm.current_wave)])
	if int(_wm.alive_enemy_count()) > _alive_at_death:
		_fail("玩家已阵亡，场上敌人还在增加（%d → %d），刷怪泵没停"
			% [_alive_at_death, int(_wm.alive_enemy_count())])

	# 观察 25 秒模拟时间（time_scale 4 → 约 6 秒墙钟）
	if float(Time.get_ticks_msec() - _death_msec) / 1000.0 * TIME_SCALE > 25.0:
		print("  死后观察 25s：波号停在 %d，场上 %d 只，商店未弹出"
			% [int(_wm.current_wave), int(_wm.alive_enemy_count())])
		_finish()

func _count_specials() -> Vector2i:
	var elites: int = 0
	var bosses: int = 0
	for e in get_nodes_in_group("enemy"):
		if "is_boss" in e and e.is_boss:
			bosses += 1
		elif "is_elite" in e and e.is_elite:
			elites += 1
	return Vector2i(elites, bosses)

func _state_name() -> String:
	match int(_wm.get("_state")):
		0: return "IDLE"
		1: return "INTER"
		2: return "SPAWN"
		3: return "COMBAT"
	return "?"

func _check_invariants(wave: int, alive: int) -> void:
	if _endless:
		# 并发闸门：存活数不得超过硬上限
		var hard_cap: int = int(_wm.endless_concurrent_hard_cap)
		if alive > hard_cap:
			_fail("W%d 存活 %d 只 > 并发硬上限 %d" % [wave, alive, hard_cap])
		# 倒计时不得为负、不得超过本波总时长
		var left: float = float(_wm.wave_time_left)
		var dur: float = float(_wm.wave_duration)
		if left < -0.001 or left > dur + 0.001:
			_fail("W%d 倒计时越界 left=%.2f dur=%.2f" % [wave, left, dur])
		# 商店打开期间场上不该有活怪（清场没做干净的话玩家会在 UI 后面挨打）
		if _panel and _panel.visible and alive > 0:
			_fail("W%d 商店打开时仍有 %d 只活怪（波末清场失败）" % [wave, alive])
	else:
		# 回归防线：标准模式下无尽那套计时器必须全程不动
		if float(_wm.wave_time_left) != 0.0 or float(_wm.wave_duration) != 0.0:
			_fail("标准模式下无尽计时器被启用了 left=%.2f dur=%.2f"
				% [float(_wm.wave_time_left), float(_wm.wave_duration)])
		if int(_wm.victory_wave) != 30:
			_fail("标准模式的 victory_wave 被改成了 %d（应为 30）" % int(_wm.victory_wave))

func _fail(msg: String) -> void:
	if not _failures.has(msg):
		_failures.append(msg)
		print("  FAIL: " + msg)

func _finish() -> void:
	_done = true
	Engine.time_scale = 1.0
	print("---")
	if _death_mode:
		if not _killed_player:
			_fail("始终没能把玩家打死，阵亡场景没有真正跑到")
		if _failures.is_empty():
			print("WAVE TEST OK")
			quit(0)
		else:
			print("WAVE TEST FAILED (%d)" % _failures.size())
			quit(1)
		return
	print("跑完波次: %s   峰值同屏: %d 只" % [str(_waves_seen), _peak_alive])
	if _wm and is_instance_valid(_wm):
		var keys: Array = _wave_peak.keys()
		keys.sort()
		# 最后一波刚开就收工，没有采样价值，从对账里剔除
		if keys.size() > 1:
			keys.remove_at(keys.size() - 1)
		if _endless:
			_report_endless(keys)
		else:
			_report_classic(keys)
	if _waves_seen.size() <= TARGET_WAVE:
		_fail("只推进到第 %d 波，未达目标 %d 波" % [_waves_seen.size(), TARGET_WAVE])
	if _peak_alive <= 0:
		_fail("全程没有任何敌人生成")
	if _failures.is_empty():
		print("WAVE TEST OK")
		quit(0)
	else:
		print("WAVE TEST FAILED (%d)" % _failures.size())
		quit(1)

func _report_endless(keys: Array) -> void:
	for w in keys:
		var k: float = float(int(w) - 1)
		var budget: float = minf(
			float(_wm.endless_budget_base) + float(_wm.endless_budget_per_wave) * k
				+ float(_wm.endless_budget_quad) * k * k,
			float(_wm.endless_budget_max)
		)
		var sp: Vector2i = _wave_specials.get(w, Vector2i.ZERO)
		print("  W%-2d 刷出 %-3d 只（精英 %d / BOSS %d）  本波总预算 %.1f 威胁点"
			% [int(w), int(_wave_peak[w]), sp.x, sp.y, budget])
	# 单调性：波次推进后刷出的怪不该反而变少（抓"预算被重复扣费"一类的静默回退）
	for i in range(1, keys.size()):
		var prev: int = int(_wave_peak[keys[i - 1]])
		var cur: int = int(_wave_peak[keys[i]])
		if cur < prev:
			_fail("W%d 只刷出 %d 只，比上一波的 %d 只还少（预算没发出去？）"
				% [int(keys[i]), cur, prev])
	# 精英从第 3 波起、BOSS 从第 6 波起，这两条排期必须真的走到
	var elite_start: int = int(_wm.endless_elite_start_wave)
	var boss_start: int = int(_wm.endless_boss_start_wave)
	for w in keys:
		var wi: int = int(w)
		var sp2: Vector2i = _wave_specials.get(w, Vector2i.ZERO)
		var is_boss_wave: bool = wi >= boss_start \
			and (wi - boss_start) % int(_wm.endless_boss_period) == 0
		if is_boss_wave and sp2.y <= 0:
			_fail("W%d 应该是 BOSS 波，但一只 boss 都没出现" % wi)
		if wi >= elite_start and not is_boss_wave and sp2.x <= 0:
			_fail("W%d 应该有精英，但一只都没出现" % wi)

func _report_classic(keys: Array) -> void:
	var base_n: int = int(_wm.base_enemy_count)
	var per: int = int(_wm.enemy_count_per_wave)
	var cap: int = int(_wm.max_enemies_per_wave)
	var settings: Node = root.get_node_or_null("/root/Settings")
	var mult: float = float(settings.get_difficulty_param("enemy_count_mult", 1.0))
	for w in keys:
		var wi: int = int(w)
		var expected: int = mini(int(round(float(base_n + (wi - 1) * per) * mult)), cap)
		var actual: int = int(_classic_totals.get(wi, -1))
		print("  W%-2d 本波总数 %-3d （公式预期 %d）" % [wi, actual, expected])
		# 召唤增援会把 _wave_total 往上加，所以只查"不小于"
		if actual < expected:
			_fail("W%d 本波总数 %d < 公式预期 %d（标准模式数量公式被改坏了）"
				% [wi, actual, expected])
