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

var _weapon: Weapon
var _weapon_manager: Node
var _player: Node
var _wave_manager: Node
var _intermission_remaining: float = 0.0
var _intermission_next_wave: int = 0
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

	# 波次管理器
	_wave_manager = get_tree().get_first_node_in_group("wave_manager")
	if _wave_manager == null:
		wave_label.text = ""
	else:
		_wave_manager.wave_started.connect(_on_wave_started)
		_wave_manager.wave_progress.connect(_on_wave_progress)
		_wave_manager.wave_completed.connect(_on_wave_completed)
		_wave_manager.intermission_started.connect(_on_intermission_started)
		_wave_manager.score_changed.connect(_on_score_changed)
		_wave_manager.currency_changed.connect(_on_currency_changed)
		_wave_manager.combo_changed.connect(_on_combo_changed)
		wave_label.text = "待命中"

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

	# 波间倒计时文本更新
	if _intermission_remaining > 0.0:
		_intermission_remaining = max(0.0, _intermission_remaining - delta)
		wave_label.text = "第 %d 波\n%.1fs 后开始" % [_intermission_next_wave, _intermission_remaining]
		# 最后 1 秒切红色闪烁警告，提示玩家准备迎敌
		if _intermission_remaining <= 1.0:
			var t_sec: float = Time.get_ticks_msec() / 1000.0
			var pulse: float = 0.5 + 0.5 * sin(t_sec * 6.0 * TAU)   # 6Hz 闪烁
			var base: Color = Color(1.0, 0.25, 0.25)
			var bright: Color = Color(1.0, 0.9, 0.6)
			wave_label.modulate = base.lerp(bright, pulse)
		else:
			wave_label.modulate = Color.WHITE

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

func _on_wave_started(wave_num: int, count: int) -> void:
	_intermission_remaining = 0.0
	wave_label.modulate = Color.WHITE
	wave_label.text = "第 %d 波\n剩 %d 只" % [wave_num, count]

func _on_wave_progress(remaining: int) -> void:
	# intermission 期间不覆盖倒计时文本
	if _intermission_remaining > 0.0:
		return
	if _wave_manager:
		wave_label.text = "第 %d 波\n剩 %d 只" % [_wave_manager.current_wave, remaining]

func _on_wave_completed(wave_num: int) -> void:
	wave_label.text = "第 %d 波已清" % wave_num
	_show_wave_cleared_toast(wave_num)

# 顶部居中漂浮"区域肃清"toast：上滑入 0.2s + 停留 0.3s + 上飘淡出 0.5s
# 总时长 1s 对齐 wave_manager.WAVE_END_DELAY，toast 淡出末尾接升级面板弹出
func _show_wave_cleared_toast(wave_num: int) -> void:
	var toast := Label.new()
	toast.text = "区  域  肃  清    WAVE %02d" % wave_num
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

func _on_intermission_started(wave_num: int, seconds: float) -> void:
	_intermission_next_wave = wave_num
	_intermission_remaining = seconds
	wave_label.text = "第 %d 波\n%.1fs 后开始" % [wave_num, seconds]

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

func _on_score_changed(score: int) -> void:
	_total_score = score
	_refresh_score_label()

func _on_currency_changed(amount: int) -> void:
	_currency = amount
	_refresh_score_label()

func _refresh_score_label() -> void:
	score_label.text = "得分 %d · 资金 %d" % [_total_score, _currency]

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
