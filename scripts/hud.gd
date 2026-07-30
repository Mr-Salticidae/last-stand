extends CanvasLayer

@onready var ammo_label: Label = $AmmoLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var damage_vignette: ColorRect = $DamageVignette
@onready var heal_vignette: ColorRect = $HealVignette
@onready var wave_label: Label = $WaveLabel
@onready var crosshair = $Crosshair
@onready var score_label: Label = $ScoreLabel
@onready var combo_label: Label = $ComboLabel
@onready var weapon_unlock_label: Label = $WeaponUnlockLabel
@onready var execute_label: Label = $ExecuteLabel
@onready var speed_blur: RadialBlurOverlay = $RadialBlurOverlay
# v0.3 视觉提示
const LAST_ROUND_PULSE_HZ: float = 4.0
const LAST_ROUND_AMMO_COLOR: Color = Color(1.0, 0.3, 0.25, 1)
var _ammo_label_default_color: Color = Color.WHITE

var _weapon: Weapon
var _weapon_manager: Node
var _player: Node
var _wave_manager: Node
var _intermission_remaining: float = 0.0
var _intermission_next_wave: int = 0

# wave_label 的单一写入方状态机。
# 之前有 6 处直接写 wave_label.text，靠 "_intermission_remaining > 0" 做脆弱互斥；
# 无尽模式的波内倒计时是第 7 个写入方，直接加会让两个倒计时逐帧互相覆盖闪烁。
# 现在所有事件只改 _label_mode + 各自的数据字段，_process 里由 _render_wave_label() 统一出字。
enum LabelMode { IDLE, INTERMISSION, WAVE_COUNT, WAVE_TIMER, BANNER }
var _label_mode: int = LabelMode.IDLE
var _label_idle_text: String = ""      # IDLE / BANNER 模式下要显示的整句
var _label_wave_num: int = 0
var _label_wave_count: int = 0

# 无尽模式：波内倒计时
var _endless: bool = false
var _wave_time_left: float = 0.0
var _wave_time_total: float = 0.0
var _wave_timer_bar: DeployingProgressBar
const WAVE_TIMER_HOT_SECONDS: float = 10.0   # 最后 N 秒转红 + 闪烁
var _total_score: int = 0
var _currency: int = 0
# 武器解锁弹出公告：独立 label，滑入 + 淡入 → 停留 → 淡出，不劫持 wave_label
var _unlock_tween: Tween = null
var _unlock_default_y: float = 0.0
const UNLOCK_SLIDE_DELTA: float = 24.0   # 滑入起点距默认 Y 的距离

# 血迹淡化：intensity 1.0 → 0.0 约 2.5 秒；每次受伤至少抬 0.35，再按伤害量加码
const BLOOD_FADE_RATE: float = 0.4
const BLOOD_HIT_BASE: float = 0.35
const BLOOD_HIT_PER_DAMAGE: float = 0.015

# 治疗闪光：绿色脉冲，比血迹消失快（更 "反馈一瞬" 的感觉）
const HEAL_FADE_RATE: float = 0.9
const HEAL_FLASH_BASE: float = 0.45
const HEAL_FLASH_PER_AMOUNT: float = 0.008

var _blood_intensity: float = 0.0
var _vignette_material: ShaderMaterial
var _heal_intensity: float = 0.0
var _heal_vignette_material: ShaderMaterial
var _health_tween: Tween = null
var _combo_tween: Tween = null

# 换弹圆环进度条：reload_started 触发 _reload_active=true，_process 每帧填进度
var _reload_indicator: ReloadIndicator
var _reload_active: bool = false
var _reload_timer: float = 0.0
var _reload_duration: float = 1.5

# 弹尽提示：弹匣 0 + 备弹 > 0 时屏幕中央闪红字"装填 RELOAD"，正弦脉冲
var _reload_prompt_label: Label
var _reload_prompt_active: bool = false
var _reload_prompt_pulse_timer: float = 0.0

# 一次性教学提示：近战处决（玩家常不知道按 F 能处决补弹）。首次"附近有可处决敌人 + 有充能"
# 时弹一次，用 user:// ConfigFile 记录已见，永不再弹（老玩家不被打扰）。
const TIPS_CFG_PATH: String = "user://laststand_tips.cfg"
const MELEE_TIP_NEAR_DIST: float = 5.0
const MELEE_TIP_SCAN_INTERVAL: float = 0.25
var _melee_tip_scan_timer: float = 0.0
var _melee_tip_label: Label
var _melee_tip_seen: bool = false
var _melee_tip_active: bool = false

func _ready() -> void:
	# 武器管理器：通过 weapon_changed 信号知道当前武器是谁，切换时重连信号
	_weapon_manager = get_tree().get_first_node_in_group("weapon_manager")
	if _weapon_manager == null:
		push_warning("hud.gd: 未在场景中找到 'weapon_manager' group")
	else:
		_weapon_manager.weapon_changed.connect(_on_weapon_changed)
		_weapon_manager.weapon_unlocked.connect(_on_weapon_unlocked)
		# manager._ready 已经跑过 equip(0)，这里立即同步当前武器
		if _weapon_manager.current_weapon:
			_on_weapon_changed(_weapon_manager.current_weapon)

	score_label.text = "得分 0 · 资金 0"
	# 缓存 ammo label 默认颜色，底牌进入区时改红，离开恢复
	_ammo_label_default_color = ammo_label.modulate

	# 玩家（血量）
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("hud.gd: 未在场景中找到 'player' group 的玩家节点")
	else:
		_player.health_changed.connect(_on_health_changed)
		_player.damaged.connect(_on_damaged)
		_player.healed.connect(_on_healed)
		# 主动同步一次：player._ready 可能已经跑过但信号还没连上
		_on_health_changed(_player.current_health, _player.max_health)
		if _player.has_signal("execute_charges_changed"):
			_player.execute_charges_changed.connect(_on_execute_charges_changed)
			# 初始值由 player._ready 的 call_deferred emit 同步，无需在此手动调

	# 血迹 + 治疗材质句柄（每帧衰减用）
	if damage_vignette and damage_vignette.material is ShaderMaterial:
		_vignette_material = damage_vignette.material as ShaderMaterial
		_vignette_material.set_shader_parameter("intensity", 0.0)
	if heal_vignette and heal_vignette.material is ShaderMaterial:
		_heal_vignette_material = heal_vignette.material as ShaderMaterial
		_heal_vignette_material.set_shader_parameter("intensity", 0.0)

	# 武器解锁公告 label：记录默认 Y，初始隐藏（动画时回到此位置）
	if weapon_unlock_label:
		_unlock_default_y = weapon_unlock_label.position.y
		weapon_unlock_label.modulate.a = 0.0

	# 弹尽提示 label：屏幕中央偏下（准星下方约 50px，靠近换弹圆环不冲突）
	_reload_prompt_label = Label.new()
	_reload_prompt_label.text = "[ 装  填 ]    RELOAD"
	_reload_prompt_label.add_theme_font_size_override("font_size", 32)
	_reload_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.22, 1))
	_reload_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_reload_prompt_label.add_theme_constant_override("outline_size", 6)
	_reload_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reload_prompt_label.anchor_left = 0.0
	_reload_prompt_label.anchor_top = 0.5
	_reload_prompt_label.anchor_right = 1.0
	_reload_prompt_label.anchor_bottom = 0.5
	_reload_prompt_label.offset_top = 30
	_reload_prompt_label.offset_bottom = 75
	_reload_prompt_label.modulate.a = 0.0
	_reload_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reload_prompt_label)

	# 近战处决教学提示：读取已见状态 + 创建提示 label（中央偏上，避开下方换弹提示）
	_load_tips_seen()
	_melee_tip_label = Label.new()
	_melee_tip_label.text = "敌人逼近 ——  按 [ F ] 处决：瞬杀杂兵，并补满当前武器弹药"
	_melee_tip_label.add_theme_font_size_override("font_size", 26)
	_melee_tip_label.add_theme_color_override("font_color", Color(0.98, 0.72, 0.28, 1))
	_melee_tip_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_melee_tip_label.add_theme_constant_override("outline_size", 6)
	_melee_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_melee_tip_label.anchor_left = 0.0
	_melee_tip_label.anchor_top = 0.5
	_melee_tip_label.anchor_right = 1.0
	_melee_tip_label.anchor_bottom = 0.5
	_melee_tip_label.offset_top = -170
	_melee_tip_label.offset_bottom = -120
	_melee_tip_label.modulate.a = 0.0
	_melee_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_melee_tip_label)

	# 换弹圆环进度条：屏幕中央偏下（准星下方 80px），无换弹时不可见
	_reload_indicator = ReloadIndicator.new()
	_reload_indicator.size = Vector2(80, 80)
	_reload_indicator.anchor_left = 0.5
	_reload_indicator.anchor_top = 0.5
	_reload_indicator.anchor_right = 0.5
	_reload_indicator.anchor_bottom = 0.5
	_reload_indicator.offset_left = -40
	_reload_indicator.offset_top = 80
	_reload_indicator.offset_right = 40
	_reload_indicator.offset_bottom = 160
	_reload_indicator.modulate.a = 0.0
	_reload_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reload_indicator)

	# 无尽模式波内倒计时条：右上角 wave_label 与 score_label 之间的细长条
	# 复用 DeployingOverlay 那根现成的进度条控件；HUD 是 CanvasLayer 没有布局容器，
	# 与 _reload_indicator 一样走"代码 new + 手写 anchor/offset"
	_wave_timer_bar = DeployingProgressBar.new()
	_wave_timer_bar.anchor_left = 1.0
	_wave_timer_bar.anchor_right = 1.0
	_wave_timer_bar.offset_left = -360
	_wave_timer_bar.offset_right = -24
	# 夹在 WaveLabel（20..106，两行 32px 文字实测约 84px 高）与 ScoreLabel（132..182）之间
	_wave_timer_bar.offset_top = 112
	_wave_timer_bar.offset_bottom = 124
	_wave_timer_bar.visible = false
	_wave_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wave_timer_bar)

	# 波次管理器
	_endless = Settings.is_endless()
	_wave_manager = get_tree().get_first_node_in_group("wave_manager")
	if _wave_manager == null:
		_label_mode = LabelMode.IDLE
		_label_idle_text = ""
	else:
		_wave_manager.wave_started.connect(_on_wave_started)
		_wave_manager.wave_progress.connect(_on_wave_progress)
		_wave_manager.wave_completed.connect(_on_wave_completed)
		_wave_manager.intermission_started.connect(_on_intermission_started)
		_wave_manager.score_changed.connect(_on_score_changed)
		_wave_manager.currency_changed.connect(_on_currency_changed)
		_wave_manager.combo_changed.connect(_on_combo_changed)
		if _wave_manager.has_signal("wave_timer_started"):
			_wave_manager.wave_timer_started.connect(_on_wave_timer_started)
		_label_mode = LabelMode.IDLE
		_label_idle_text = "待命中"
	_render_wave_label()

	# v0.3 PR-B 羁绊系统：监听激活信号 → 屏幕中央漂浮 toast
	if has_node("/root/SynergyManager"):
		SynergyManager.synergy_activated.connect(_on_synergy_activated)

func _process(delta: float) -> void:
	if _blood_intensity > 0.0:
		_blood_intensity = max(0.0, _blood_intensity - BLOOD_FADE_RATE * delta)
		if _vignette_material:
			_vignette_material.set_shader_parameter("intensity", _blood_intensity)
	if _heal_intensity > 0.0:
		_heal_intensity = max(0.0, _heal_intensity - HEAL_FADE_RATE * delta)
		if _heal_vignette_material:
			_heal_vignette_material.set_shader_parameter("intensity", _heal_intensity)
	# 换弹进度填充
	if _reload_active:
		_reload_timer += delta
		_reload_indicator.progress = clampf(_reload_timer / _reload_duration, 0.0, 1.0)
	# 弹尽 RELOAD 提示正弦脉冲（0.5~1.0 alpha 周期 0.8s）
	if _reload_prompt_active:
		_reload_prompt_pulse_timer += delta
		_reload_prompt_label.modulate.a = 0.75 + 0.25 * sin(_reload_prompt_pulse_timer * TAU / 0.8)

	# v0.3 视觉提示：每帧根据 weapon / wm 状态驱动准心红环 / ammo 脉冲 / 速度线
	_update_v03_overlays(delta)

	# 近战处决一次性教学提示。它要全量遍历 enemy 组，同屏 40 只时每帧扫太贵，
	# 而这只是个教学提示，0.25s 一次完全够用
	_melee_tip_scan_timer -= delta
	if _melee_tip_scan_timer <= 0.0:
		_melee_tip_scan_timer = MELEE_TIP_SCAN_INTERVAL
		_check_melee_tip()

	# 波次标签：推进各模式的计时，然后由唯一的 _render_wave_label 出字
	_tick_wave_label(delta)

# ---------- 波次标签：唯一写入方 ----------
func _tick_wave_label(delta: float) -> void:
	match _label_mode:
		LabelMode.INTERMISSION:
			_intermission_remaining = max(0.0, _intermission_remaining - delta)
		LabelMode.WAVE_TIMER:
			# 每帧读 WaveManager 的权威值，绝不本地 -= delta。本地递减在 3 秒休整里
			# 看不出漂移，60 秒的波内会明显表现成"进度条走完了怪还在刷"。
			if _wave_manager:
				_wave_time_left = float(_wave_manager.wave_time_left)
				_wave_time_total = float(_wave_manager.wave_duration)
	_render_wave_label()

func _render_wave_label() -> void:
	var show_bar: bool = false
	match _label_mode:
		LabelMode.INTERMISSION:
			wave_label.text = "第 %d 波\n%.1fs 后开始" % [_intermission_next_wave, _intermission_remaining]
			# 最后 1 秒切红色闪烁警告，提示玩家准备迎敌
			_pulse_wave_label(_intermission_remaining <= 1.0)
		LabelMode.WAVE_COUNT:
			wave_label.text = "第 %d 波\n剩 %d 只" % [_label_wave_num, _label_wave_count]
			_pulse_wave_label(false)
		LabelMode.WAVE_TIMER:
			show_bar = _wave_time_total > 0.0
			var alive: int = 0
			if _wave_manager and _wave_manager.has_method("alive_enemy_count"):
				alive = int(_wave_manager.alive_enemy_count())
			wave_label.text = "第 %d 波\n%s   ☠ %d" % [
				_label_wave_num, _format_mmss(_wave_time_left), alive
			]
			# 波末 10 秒进入与"休整最后 1 秒"同款的红闪，紧迫感直接复用
			_pulse_wave_label(_wave_time_left <= WAVE_TIMER_HOT_SECONDS)
		_:
			wave_label.text = _label_idle_text
			_pulse_wave_label(false)

	_wave_timer_bar.visible = show_bar
	if show_bar:
		_wave_timer_bar.progress = clampf(_wave_time_left / _wave_time_total, 0.0, 1.0)
		# 平时危险黄（和血条的红拉开距离），最后 10 秒渐变成红
		var hot: float = 1.0 - clampf(_wave_time_left / WAVE_TIMER_HOT_SECONDS, 0.0, 1.0)
		_wave_timer_bar.fill_color = UiPalette.HAZARD_Y.lerp(UiPalette.RED, hot)

# 6Hz 红色脉冲警告。hot=false 时复位成白色——所有复位路径统一走这里，
# 避免"某条分支忘了复位、标签一直红着"
func _pulse_wave_label(hot: bool) -> void:
	if not hot:
		wave_label.modulate = Color.WHITE
		return
	var t_sec: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.5 + 0.5 * sin(t_sec * 6.0 * TAU)
	wave_label.modulate = Color(1.0, 0.25, 0.25).lerp(Color(1.0, 0.9, 0.6), pulse)

# 波内倒计时用 M:SS。向上取整，让最后一秒显示 0:01 而不是提前跳 0:00
func _format_mmss(sec: float) -> String:
	var total: int = int(ceil(maxf(sec, 0.0)))
	return "%d:%02d" % [total / 60, total % 60]

# 无尽模式：本波倒计时开始
func _on_wave_timer_started(wave_num: int, duration: float) -> void:
	_label_wave_num = wave_num
	_wave_time_total = duration
	_wave_time_left = duration
	_label_mode = LabelMode.WAVE_TIMER
	_render_wave_label()

# 武器解锁：独立 label 滑入 + 淡入 → 停留 1.7s → 淡出，不影响 wave_label / 玩家操作
# 总时长 ~2.65s。多次解锁连续触发：kill 旧 tween 重新启动，最新一条覆盖
func _on_weapon_unlocked(weapon: Weapon) -> void:
	if weapon_unlock_label == null:
		return
	# 找到武器在 manager.weapons 数组中的索引（数字键编号 = idx + 1）
	var idx: int = -1
	if _weapon_manager and "weapons" in _weapon_manager:
		idx = _weapon_manager.weapons.find(weapon)
	var key_hint: String = ("  ·  按 %d 切换" % (idx + 1)) if idx >= 0 else ""
	weapon_unlock_label.text = "★ %s 已解锁%s" % [weapon.weapon_name, key_hint]

	# 取消上一条进行中的动画
	if _unlock_tween and _unlock_tween.is_valid():
		_unlock_tween.kill()

	# 重置初始状态：上方 24px + 透明
	weapon_unlock_label.modulate.a = 0.0
	weapon_unlock_label.position.y = _unlock_default_y - UNLOCK_SLIDE_DELTA

	_unlock_tween = create_tween()
	# Phase 1：fade in + slide down（并行 0.35s）
	_unlock_tween.tween_property(weapon_unlock_label, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_unlock_tween.parallel().tween_property(weapon_unlock_label, "position:y", _unlock_default_y, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Phase 2：停留 1.7s
	_unlock_tween.tween_interval(1.7)
	# Phase 3：淡出 0.6s
	_unlock_tween.tween_property(weapon_unlock_label, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	AudioManager.play_pickup()

# 切换武器：断开旧武器信号、连上新武器、立即同步显示
func _on_weapon_changed(weapon: Weapon) -> void:
	# 断开旧连接（如果同一武器再切回，先 disconnect 防重复）
	if _weapon and is_instance_valid(_weapon):
		if _weapon.ammo_changed.is_connected(_on_ammo_changed):
			_weapon.ammo_changed.disconnect(_on_ammo_changed)
		if _weapon.reload_started.is_connected(_on_reload_started):
			_weapon.reload_started.disconnect(_on_reload_started)
		if _weapon.reload_finished.is_connected(_on_reload_finished):
			_weapon.reload_finished.disconnect(_on_reload_finished)
		if _weapon.hit_confirmed.is_connected(_on_hit_confirmed):
			_weapon.hit_confirmed.disconnect(_on_hit_confirmed)
		if _weapon.headshot_confirmed.is_connected(_on_headshot_confirmed):
			_weapon.headshot_confirmed.disconnect(_on_headshot_confirmed)
		if _weapon.kill_confirmed.is_connected(_on_kill_confirmed):
			_weapon.kill_confirmed.disconnect(_on_kill_confirmed)
		if _weapon.has_signal("leg_confirmed") and _weapon.leg_confirmed.is_connected(_on_leg_confirmed):
			_weapon.leg_confirmed.disconnect(_on_leg_confirmed)
		if _weapon.reload_burst_consumed.is_connected(_on_reload_burst_consumed):
			_weapon.reload_burst_consumed.disconnect(_on_reload_burst_consumed)
		if _weapon.last_round_fired.is_connected(_on_last_round_fired):
			_weapon.last_round_fired.disconnect(_on_last_round_fired)
	_weapon = weapon
	if _weapon == null:
		ammo_label.text = ""
		return
	_weapon.ammo_changed.connect(_on_ammo_changed)
	_weapon.reload_started.connect(_on_reload_started)
	_weapon.reload_finished.connect(_on_reload_finished)
	_weapon.hit_confirmed.connect(_on_hit_confirmed)
	_weapon.headshot_confirmed.connect(_on_headshot_confirmed)
	_weapon.kill_confirmed.connect(_on_kill_confirmed)
	if _weapon.has_signal("leg_confirmed"):
		_weapon.leg_confirmed.connect(_on_leg_confirmed)
	_weapon.reload_burst_consumed.connect(_on_reload_burst_consumed)
	_weapon.last_round_fired.connect(_on_last_round_fired)
	_on_ammo_changed(_weapon.current_ammo, _weapon.reserve_ammo, _weapon.max_ammo())

# ammo 显示："弹匣 / 备弹"，e.g. "12 / 48"
func _on_ammo_changed(current: int, reserve: int, _maximum: int) -> void:
	ammo_label.text = "%d / %d" % [current, reserve]
	# 弹匣 0 + 备弹 > 0 → 闪 RELOAD 提示；其他状态淡出
	var should_prompt: bool = current <= 0 and reserve > 0
	if should_prompt and not _reload_prompt_active:
		_reload_prompt_active = true
		_reload_prompt_pulse_timer = 0.0
	elif not should_prompt and _reload_prompt_active:
		_reload_prompt_active = false
		var t: Tween = create_tween()
		t.tween_property(_reload_prompt_label, "modulate:a", 0.0, 0.15)

func _on_reload_started(duration: float) -> void:
	ammo_label.text = "装填中..."
	_reload_active = true
	_reload_timer = 0.0
	_reload_duration = max(duration, 0.01)
	_reload_indicator.progress = 0.0
	_reload_indicator.modulate.a = 1.0

func _on_reload_finished() -> void:
	if _weapon:
		_on_ammo_changed(_weapon.current_ammo, _weapon.reserve_ammo, _weapon.max_ammo())
	_reload_active = false
	_reload_indicator.progress = 1.0
	# 换弹完成短暂保留满进度（"已装填"反馈）+ 淡出
	var tween: Tween = create_tween()
	tween.tween_interval(0.15)
	tween.tween_property(_reload_indicator, "modulate:a", 0.0, 0.2)

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	# 用 tween 从当前 bar value 过渡到新值，bar 和数字 label 同步更新
	if _health_tween and _health_tween.is_valid():
		_health_tween.kill()
	var start_val: float = health_bar.value
	var max_val: float = float(maximum)
	_health_tween = create_tween()
	_health_tween.tween_method(
		func(v: float) -> void:
			health_bar.value = v
			health_label.text = "%d / %d" % [int(ceil(v)), int(max_val)],
		start_val, float(current), 0.35
	).set_trans(Tween.TRANS_QUAD)

func _on_damaged(amount: float) -> void:
	_blood_intensity = clamp(_blood_intensity + BLOOD_HIT_BASE + amount * BLOOD_HIT_PER_DAMAGE, 0.0, 1.0)
	if _vignette_material:
		_vignette_material.set_shader_parameter("intensity", _blood_intensity)

func _on_healed(amount: float) -> void:
	_heal_intensity = clamp(_heal_intensity + HEAL_FLASH_BASE + amount * HEAL_FLASH_PER_AMOUNT, 0.0, 1.0)
	if _heal_vignette_material:
		_heal_vignette_material.set_shader_parameter("intensity", _heal_intensity)

func _on_execute_charges_changed(current: int, maximum: int) -> void:
	if execute_label == null:
		return
	# 图标化：实心 ◆ = 可用，空心 ◇ = 已耗尽（比数字直观）
	var maxc: int = maxi(maximum, current)
	var pips: String = ""
	for i in maxc:
		pips += "◆" if i < current else "◇"
	execute_label.text = "处决 " + pips
	execute_label.modulate = Color(1, 1, 1, 0.4) if current <= 0 else Color.WHITE

func _on_wave_started(wave_num: int, count: int) -> void:
	_intermission_remaining = 0.0
	_label_wave_num = wave_num
	if _endless:
		# count 在无尽模式恒为 0（没有"计划总数"）。文本交给 wave_timer_started 接管。
		return
	_label_wave_count = count
	_label_mode = LabelMode.WAVE_COUNT
	_render_wave_label()

func _on_wave_progress(remaining: int) -> void:
	# 无尽模式没有"剩余数"，且高频击杀会把倒计时文本冲掉。
	# WaveManager 在无尽下本就不 emit 这条，这里是双保险。
	if _endless:
		return
	# intermission 期间不覆盖倒计时文本
	if _label_mode == LabelMode.INTERMISSION:
		return
	if _wave_manager:
		_label_wave_num = int(_wave_manager.current_wave)
		_label_wave_count = remaining
		_label_mode = LabelMode.WAVE_COUNT
		_render_wave_label()

func _on_wave_completed(wave_num: int) -> void:
	# 无尽模式是"时间到"而不是"清空"——收场文案与感觉都不同
	_label_idle_text = ("第 %d 波 · 时间到" % wave_num) if _endless else ("第 %d 波已清" % wave_num)
	_label_mode = LabelMode.BANNER
	_render_wave_label()
	_show_wave_cleared_toast(wave_num)

# 顶部居中漂浮"区域肃清"toast：上滑入 0.2s + 停留 0.3s + 上飘淡出 0.5s
# 总时长 1s 对齐 wave_manager.WAVE_END_DELAY，toast 淡出末尾接升级面板弹出
func _show_wave_cleared_toast(wave_num: int) -> void:
	var toast := Label.new()
	toast.text = ("时  间  到    WAVE %02d" if _endless else "区  域  肃  清    WAVE %02d") % wave_num
	toast.add_theme_font_size_override("font_size", 56)  # 40 → 56 加大
	toast.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1))  # 更亮的暖金
	toast.add_theme_color_override("font_outline_color", Color(0.35, 0.18, 0.04, 0.95))  # 深金 outline
	toast.add_theme_constant_override("outline_size", 9)  # 5 → 9 加厚
	# drop shadow 加层次，离地面感
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	toast.add_theme_constant_override("shadow_offset_x", 0)
	toast.add_theme_constant_override("shadow_offset_y", 4)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.0
	toast.anchor_right = 1.0
	toast.anchor_top = 0.0
	toast.anchor_bottom = 0.0
	# 入场起点（更高），tween 滑到 70/150 到位
	toast.offset_top = 50
	toast.offset_bottom = 130
	toast.modulate.a = 0.0
	add_child(toast)
	var tween := create_tween()
	# 入场：alpha + 上滑到位（0.25s），back-out 给点弹性
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(toast, "offset_top", 70.0, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(toast, "offset_bottom", 150.0, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.3)
	# 出场：上飘 + 淡出 0.5s
	tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(toast, "offset_top", 35.0, 0.5)
	tween.parallel().tween_property(toast, "offset_bottom", 115.0, 0.5)
	tween.tween_callback(toast.queue_free)

# v0.3 PR-B 羁绊激活 toast：屏幕中央偏上漂浮
# "羁绊激活" 副标题 + 名字主标题 + 效果描述（让玩家立刻知道激活了什么、有什么用）；稀有金色，史诗紫色
# 触发于商店面板激活瞬间，UI 仍在显示，所以 toast 用 layer 90 盖在 panel(20) 之上
# 队列化：同时激活多个羁绊时依次播放，避免 toast 重叠
var _synergy_toast_queue: Array[String] = []
var _synergy_toast_playing: bool = false

func _on_synergy_activated(id: String) -> void:
	_synergy_toast_queue.append(id)
	_try_play_next_synergy_toast()

func _try_play_next_synergy_toast() -> void:
	if _synergy_toast_playing or _synergy_toast_queue.is_empty():
		return
	var next_id: String = _synergy_toast_queue.pop_front()
	_synergy_toast_playing = true
	_show_synergy_toast(next_id)

func _show_synergy_toast(id: String) -> void:
	var s: Dictionary = SynergyManager.get_synergy(id)
	if s.is_empty():
		_synergy_toast_playing = false
		_try_play_next_synergy_toast()
		return
	var is_epic: bool = int(s.tier) == SynergyManager.Tier.EPIC
	var main_color: Color = Color(0.85, 0.55, 1.0, 1) if is_epic else Color(1.0, 0.78, 0.32, 1)
	var outline_color: Color = Color(0.20, 0.05, 0.30, 0.95) if is_epic else Color(0.35, 0.18, 0.04, 0.95)

	# 容器：CenterContainer 居中，里面 VBoxContainer 上下两行
	var holder := Control.new()
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.offset_left = -300
	holder.offset_right = 300
	holder.offset_top = 200
	holder.offset_bottom = 320
	holder.modulate.a = 0.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var subtitle := Label.new()
	subtitle.text = "羁绊激活 · SYNERGY UNLOCKED"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", main_color)
	subtitle.add_theme_color_override("font_outline_color", outline_color)
	subtitle.add_theme_constant_override("outline_size", 4)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.0
	subtitle.anchor_bottom = 0.0
	subtitle.offset_top = 0
	subtitle.offset_bottom = 30
	holder.add_child(subtitle)

	var title := Label.new()
	title.text = ("★  %s  ★" if is_epic else "◆  %s  ◆") % str(s.name)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", main_color)
	title.add_theme_color_override("font_outline_color", outline_color)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.0
	title.anchor_bottom = 0.0
	title.offset_top = 30
	title.offset_bottom = 110
	holder.add_child(title)

	# 效果描述：玩家最关心"这羁绊有什么用"，激活瞬间直接给出，不用回商店 hover
	var desc := Label.new()
	desc.text = str(s.desc)
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(1, 0.918, 0.851, 1))
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	desc.add_theme_constant_override("outline_size", 5)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.anchor_left = 0.0
	desc.anchor_right = 1.0
	desc.anchor_top = 0.0
	desc.anchor_bottom = 0.0
	desc.offset_top = 116
	desc.offset_bottom = 168
	holder.add_child(desc)

	add_child(holder)

	# 入场：淡入 + 上滑（与"区域肃清"toast 风格一致）
	var tween: Tween = create_tween()
	tween.tween_property(holder, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(holder, "offset_top", 220.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(holder, "offset_bottom", 340.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.4)   # 多停留，让玩家读完效果描述
	tween.tween_property(holder, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(holder, "offset_top", 180.0, 0.5)
	tween.parallel().tween_property(holder, "offset_bottom", 300.0, 0.5)
	tween.tween_callback(holder.queue_free)
	# 队列：当前 toast 播完 → 标记空闲 → 触发下一个
	tween.tween_callback(func() -> void:
		_synergy_toast_playing = false
		_try_play_next_synergy_toast()
	)

func _on_intermission_started(wave_num: int, seconds: float) -> void:
	_intermission_next_wave = wave_num
	_intermission_remaining = seconds
	_label_mode = LabelMode.INTERMISSION
	_render_wave_label()

func _on_hit_confirmed() -> void:
	if crosshair and crosshair.has_method("flash_hit"):
		crosshair.flash_hit()

func _on_headshot_confirmed() -> void:
	if crosshair and crosshair.has_method("flash_headshot"):
		crosshair.flash_headshot()

func _on_kill_confirmed() -> void:
	# 得分由 WaveManager 统一管理（score_changed 信号刷 label），这里只负责视觉反馈
	if crosshair and crosshair.has_method("flash_kill"):
		crosshair.flash_kill()

func _on_leg_confirmed() -> void:
	# G18 打腿彩蛋：琥珀色命中标记
	if crosshair and crosshair.has_method("flash_leg"):
		crosshair.flash_leg()

# v0.3 新卡视觉反馈：聚焦到准心层（仿 hit/headshot/kill marker），不再用全屏闪
func _on_reload_burst_consumed() -> void:
	if crosshair and crosshair.has_method("flash_reload_burst"):
		crosshair.flash_reload_burst()

func _on_last_round_fired() -> void:
	if crosshair and crosshair.has_method("flash_last_round"):
		crosshair.flash_last_round()

# 每帧驱动持续型视觉：准心红环 / ammo 红色脉冲 / 速度线 intensity
func _update_v03_overlays(delta: float) -> void:
	# 准心：战术换弹 pending 时画红环
	if crosshair and _weapon and is_instance_valid(_weapon):
		crosshair.reload_burst_ready = _weapon._reload_burst_pending
	# Ammo label 底牌区脉冲（current_ammo > 0 且 ≤ last_round_count）
	var in_last_round_zone: bool = false
	if _weapon and is_instance_valid(_weapon) and _weapon_manager:
		var lr_count: int = int(_weapon_manager.get("last_round_count"))
		in_last_round_zone = lr_count > 0 and _weapon.current_ammo > 0 and _weapon.current_ammo <= lr_count
	if in_last_round_zone:
		var t_sec: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.5 + 0.5 * sin(t_sec * LAST_ROUND_PULSE_HZ * TAU)
		ammo_label.modulate = _ammo_label_default_color.lerp(LAST_ROUND_AMMO_COLOR, pulse)
	else:
		ammo_label.modulate = _ammo_label_default_color
	# 径向运动模糊：杀戮节拍激活（player._combo_speed_active > 0）+ 实际在移动时启用
	if speed_blur and _player and is_instance_valid(_player):
		var combo_active: bool = "_combo_speed_active" in _player and _player._combo_speed_active > 0.0
		var v_len: float = Vector2(_player.velocity.x, _player.velocity.z).length() if "velocity" in _player else 0.0
		var moving: bool = v_len > 0.5
		speed_blur.set_target(1.0 if (combo_active and moving) else 0.0)

func _on_score_changed(score: int) -> void:
	_total_score = score
	_refresh_score_label()

func _on_currency_changed(amount: int) -> void:
	_currency = amount
	_refresh_score_label()

func _refresh_score_label() -> void:
	score_label.text = "得分 %d · 资金 %d" % [_total_score, _currency]

# ========== 近战处决一次性教学提示 ==========
func _load_tips_seen() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TIPS_CFG_PATH) == OK:
		_melee_tip_seen = bool(cfg.get_value("tips", "melee_seen", false))

func _check_melee_tip() -> void:
	if _melee_tip_seen or _melee_tip_active:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if "_dead" in _player and _player._dead:
		return
	# 有处决充能 + 附近有可处决敌人 = "用得上"的时机，此时教学最有效
	if not ("execute_charges" in _player) or _player.execute_charges <= 0:
		return
	var ppos: Vector3 = _player.global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("is_executable") or not e.is_executable():
			continue
		var d: float = Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length()
		if d <= MELEE_TIP_NEAR_DIST:
			_show_melee_tip()
			return

func _show_melee_tip() -> void:
	_melee_tip_active = true
	_melee_tip_seen = true   # 立即标记，整局/跨局只弹一次
	_save_tip_seen("melee_seen")
	var t: Tween = create_tween()
	t.tween_property(_melee_tip_label, "modulate:a", 1.0, 0.3)
	t.tween_interval(6.0)
	t.tween_property(_melee_tip_label, "modulate:a", 0.0, 0.6)
	t.tween_callback(func() -> void: _melee_tip_active = false)

func _save_tip_seen(key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(TIPS_CFG_PATH)   # 文件不存在时忽略错误，直接新建
	cfg.set_value("tips", key, true)
	cfg.save(TIPS_CFG_PATH)

func _on_combo_changed(count: int, broken: bool) -> void:
	if _combo_tween and _combo_tween.is_valid():
		_combo_tween.kill()
	# 单杀（count=1）不算"连击"，不显示；断连 / count≤1 → 淡出
	if broken or count <= 1:
		_combo_tween = create_tween()
		_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.25)
		return
	# 连击递增：弹一下（初始大一点然后回缩）+ 模拟心跳
	combo_label.text = "COMBO ×%d" % count
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2(1.4, 1.4)
	_combo_tween = create_tween()
	_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
