extends CanvasLayer

# 死亡序列：player.died → 黑白滤镜淡入 → 闭眼黑幕合拢 → 标题+按钮淡入 → R/点击重生

@onready var desaturate_rect: ColorRect = $Desaturate
@onready var eyelid_top: ColorRect = $EyelidTop
@onready var eyelid_bottom: ColorRect = $EyelidBottom
@onready var eyebrow_label: Label = $UIRoot/Center/EyebrowLabel
@onready var title_label: Label = $UIRoot/Center/TitleLabel
@onready var title_en: Label = $UIRoot/Center/TitleEN
@onready var stats_card: ChamferPanel = $UIRoot/Center/StatsCard
@onready var stats_label: RichTextLabel = $UIRoot/Center/StatsCard/StatsLabel
@onready var respawn_button: ChamferButton = $UIRoot/Center/ButtonsHBox/RespawnButton
@onready var main_menu_button: SecondaryButton = $UIRoot/Center/ButtonsHBox/MainMenuButton

var _desaturate_mat: ShaderMaterial
var _active: bool = false  # 序列进行中或等待重生输入
var _is_victory: bool = false  # true=通关结算（金色文案+白幕+wave_start 音）；false=死亡（红文案+黑幕+倒地音）
var _victory_overlay: ColorRect  # 胜利底层不透明深色 mask（完全遮盖游戏世界）
var _victory_bg: TextureRect  # 胜利背景图（在 overlay 之上做染色氛围底图）
var _title_label_orig_y: float  # 胜利标题滑入动画用的原始 y

# 时间节拍（总时长 1.9s 到可交互）
const FADE_GRAY_DURATION: float = 1.0
const EYELID_CLOSE_DURATION: float = 0.6
const UI_FADE_DURATION: float = 0.5

# 本地最高纪录存档
const RECORD_PATH: String = "user://laststand_record.cfg"
const RECORD_SECTION: String = "record"

func _ready() -> void:
	_desaturate_mat = desaturate_rect.material as ShaderMaterial
	if _desaturate_mat:
		_desaturate_mat.set_shader_parameter("desaturation", 0.0)
	_setup_victory_bg()
	_title_label_orig_y = title_label.position.y

# 胜利双层底图：(1) VictoryOverlay 深暖色全屏 mask 完全遮盖游戏世界
# (2) VictoryBg 染色氛围底图叠在 overlay 之上 alpha 0.45 不喧宾夺主
# 节点顺序：Desaturate(0) → VictoryOverlay(1) → VictoryBg(2) → EyelidTop(3) → ...
func _setup_victory_bg() -> void:
	_victory_overlay = ColorRect.new()
	_victory_overlay.name = "VictoryOverlay"
	_victory_overlay.color = Color(0.05, 0.03, 0.03, 0.0)  # 黑红基调（接近 stats_card bg 0.06, 0.04, 0.04）
	_victory_overlay.anchor_right = 1.0
	_victory_overlay.anchor_bottom = 1.0
	_victory_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_victory_overlay)
	move_child(_victory_overlay, 1)

	_victory_bg = TextureRect.new()
	_victory_bg.name = "VictoryBg"
	_victory_bg.texture = load("res://assets/textures/victory_bg.png")
	_victory_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_victory_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_victory_bg.anchor_right = 1.0
	_victory_bg.anchor_bottom = 1.0
	# modulate rgb 染深红棕（与游戏黑红主调一致），alpha 0=不可见
	_victory_bg.modulate = Color(0.5, 0.22, 0.18, 0.0)
	_victory_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_victory_bg)
	move_child(_victory_bg, 2)

	# 初始状态：所有效果都"收起"
	eyelid_top.anchor_bottom = 0.0
	eyelid_bottom.anchor_top = 1.0
	eyebrow_label.modulate.a = 0.0
	title_label.modulate.a = 0.0
	title_en.modulate.a = 0.0
	stats_card.modulate.a = 0.0
	respawn_button.modulate.a = 0.0
	respawn_button.disabled = true
	main_menu_button.modulate.a = 0.0
	main_menu_button.disabled = true

	# 监听玩家死亡
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("died"):
		player.died.connect(_on_player_died)

	# 监听通关（活到 wave_manager.victory_wave 默认 30）
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	if wm and wm.has_signal("game_completed"):
		wm.game_completed.connect(_on_game_completed)

	respawn_button.pressed.connect(_on_respawn_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

func _unhandled_input(event: InputEvent) -> void:
	# R 键快速重生（只在按钮可交互后生效）
	if not _active or respawn_button.disabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_respawn()

func _on_player_died() -> void:
	if _active:
		return
	_active = true
	# 死亡瞬间从 WaveManager 拉数据填统计（先填好，稍后随 UI 一起淡入）
	_fill_stats()
	_play_sequence()

# 通关：到达 victory_wave 且本波清空。改文案/颜色/幕色为胜利感，复用 _play_sequence 视觉
func _on_game_completed(_wave: int) -> void:
	if _active:
		return
	_active = true
	_is_victory = true
	# 立即锁玩家输入（移动/视角/开火）+ 解锁鼠标，避免胜利序列期间玩家继续操作
	# 参考 upgrade_panel.show_panel 的模式
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "input_locked" in player:
		player.input_locked = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_victory_theme()
	_fill_stats()
	_play_sequence()

func _apply_victory_theme() -> void:
	# 凯旋强调色：用游戏标志红，与 EyebrowLabel/TitleEN 死亡版颜色一致，保持黑红主调
	var victory_color: Color = Color(0.855, 0.18, 0.2, 1)
	eyebrow_label.text = "// MISSION COMPLETE  ·  SECTOR HELD"
	eyebrow_label.add_theme_color_override("font_color", victory_color)
	title_label.text = "凯  旋  归  来"
	# 字号 96 → 110；颜色与 main_menu 米白(1, 0.918, 0.851)一致，黑 outline 加厚作凯旋张力
	title_label.add_theme_font_size_override("font_size", 110)
	title_label.add_theme_color_override("font_color", Color(1, 0.918, 0.851, 1))
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title_label.add_theme_constant_override("outline_size", 10)
	title_en.text = "MISSION COMPLETE"
	title_en.add_theme_color_override("font_color", victory_color)
	var stats_eyebrow: Node = stats_card.get_node_or_null("StatsEyebrow")
	if stats_eyebrow and stats_eyebrow is Label:
		(stats_eyebrow as Label).text = "// SURVIVAL REPORT"
		(stats_eyebrow as Label).add_theme_color_override("font_color", victory_color)
	respawn_button.cn_label = "再战一局"
	respawn_button.en_label = "REPLAY"
	# 幕色改暖白（凯旋光感）替代死亡黑幕
	var curtain: Color = Color(0.95, 0.92, 0.85, 1)
	eyelid_top.color = curtain
	eyelid_bottom.color = curtain

func _fill_stats() -> void:
	var wm: Node = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		stats_label.text = ""
		return
	var wave_reached: int = int(wm.current_wave) if "current_wave" in wm else 0
	var score: int = int(wm.total_score) if "total_score" in wm else 0
	var combo: int = int(wm.max_combo) if "max_combo" in wm else 0
	var elapsed: float = 0.0
	if wm.has_method("run_elapsed_seconds"):
		elapsed = wm.run_elapsed_seconds()

	# 读 + 比较 + 写纪录
	var record: Dictionary = _load_record()
	var is_wave_new: bool = wave_reached > record.wave
	var is_score_new: bool = score > record.score
	var is_time_new: bool = elapsed > record.time
	var is_combo_new: bool = combo > record.combo
	var best_wave: int = max(record.wave, wave_reached)
	var best_score: int = max(record.score, score)
	var best_time: float = max(record.time, elapsed)
	var best_combo: int = max(record.combo, combo)
	if is_wave_new or is_score_new or is_time_new or is_combo_new:
		_save_record(best_wave, best_score, best_time, best_combo)

	var time_text: String = _format_time(elapsed)
	var best_time_text: String = _format_time(best_time)
	var wave_suffix: String = _new_record_tag() if is_wave_new else _best_tag("最高 %d" % best_wave)
	var score_suffix: String = _new_record_tag() if is_score_new else _best_tag("最高 %d" % best_score)
	var time_suffix: String = _new_record_tag() if is_time_new else _best_tag("最长 %s" % best_time_text)
	var combo_suffix: String = _new_record_tag() if is_combo_new else _best_tag("最高 ×%d" % best_combo)
	stats_label.text = "[center]存活至  第 %d 波%s\n得分     %d%s\n用时     %s%s\n连击     ×%d%s[/center]" % [
		wave_reached, wave_suffix,
		score, score_suffix,
		time_text, time_suffix,
		combo, combo_suffix
	]

# 金色 + 加粗 + 强描边的"★新纪录"，让 captain 一眼能看到破纪录
func _new_record_tag() -> String:
	return "  [color=#ffcf3a][b]★新纪录[/b][/color]"

func _best_tag(text: String) -> String:
	return "  [color=#888888](%s)[/color]" % text

func _format_time(sec: float) -> String:
	var total: int = int(sec)
	return "%02d:%02d" % [total / 60, total % 60]

func _load_record() -> Dictionary:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(RECORD_PATH)
	if err != OK:
		return {"wave": 0, "score": 0, "time": 0.0, "combo": 0}
	return {
		"wave": int(cfg.get_value(RECORD_SECTION, "wave", 0)),
		"score": int(cfg.get_value(RECORD_SECTION, "score", 0)),
		"time": float(cfg.get_value(RECORD_SECTION, "time", 0.0)),
		"combo": int(cfg.get_value(RECORD_SECTION, "combo", 0)),
	}

func _save_record(wave: int, score: int, time: float, combo: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(RECORD_SECTION, "wave", wave)
	cfg.set_value(RECORD_SECTION, "score", score)
	cfg.set_value(RECORD_SECTION, "time", time)
	cfg.set_value(RECORD_SECTION, "combo", combo)
	cfg.save(RECORD_PATH)

func _play_sequence() -> void:
	# 胜利：wave_start 凯旋音（不黑白化，保留场景颜色）；死亡：倒地+耳鸣 + 黑白化
	if _is_victory:
		AudioManager.play_wave_start()
	else:
		AudioManager.play_player_death_audio()
	# 阶段 1+2: 死亡=黑白化+黑幕合拢；胜利=背景图淡入（不合幕，保留全屏图作为画面张力）
	var tween := create_tween().set_parallel(true)
	if _is_victory:
		# Overlay 不透明深色完全遮盖游戏世界 + VictoryBg 染色氛围底图同时淡入
		tween.tween_property(_victory_overlay, "color:a", 1.0, FADE_GRAY_DURATION) \
			.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(_victory_bg, "modulate:a", 0.35, FADE_GRAY_DURATION) \
			.set_trans(Tween.TRANS_QUAD)
	else:
		tween.tween_method(
			_set_desaturation,
			0.0, 1.0, FADE_GRAY_DURATION
		).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(eyelid_top, "anchor_bottom", 0.5, EYELID_CLOSE_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.3)
		tween.tween_property(eyelid_bottom, "anchor_top", 0.5, EYELID_CLOSE_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.3)
	await tween.finished

	# 阶段 3: 标题 + 统计 + 按钮淡入；胜利时标题从上滑入加凯旋亮相戏剧感
	if _is_victory:
		title_label.position.y = _title_label_orig_y - 40
	var ui_tween := create_tween().set_parallel(true)
	ui_tween.tween_property(eyebrow_label, "modulate:a", 1.0, UI_FADE_DURATION)
	ui_tween.tween_property(title_label, "modulate:a", 1.0, UI_FADE_DURATION).set_delay(0.05)
	if _is_victory:
		ui_tween.tween_property(title_label, "position:y", _title_label_orig_y, 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05)
	ui_tween.tween_property(title_en, "modulate:a", 1.0, UI_FADE_DURATION).set_delay(0.1)
	ui_tween.tween_property(stats_card, "modulate:a", 1.0, UI_FADE_DURATION).set_delay(0.2)
	ui_tween.tween_property(respawn_button, "modulate:a", 1.0, UI_FADE_DURATION).set_delay(0.3)
	ui_tween.tween_property(main_menu_button, "modulate:a", 1.0, UI_FADE_DURATION).set_delay(0.4)
	await ui_tween.finished

	# 可交互（不主动 grab_focus，鼠标 / Tab 才点亮）
	respawn_button.disabled = false
	main_menu_button.disabled = false
	# 释放鼠标让玩家能点按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 激活反馈：按钮过亮一闪再回落，配 ui_click 短促提示，告诉玩家可以按了
	AudioManager.play_ui_click()
	_flash_button(respawn_button, Color(1.6, 1.45, 1.15, 1.0))
	_flash_button(main_menu_button, Color(1.3, 1.2, 1.05, 1.0))

func _flash_button(btn: Control, peak: Color) -> void:
	btn.modulate = peak
	var t := create_tween()
	t.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_desaturation(v: float) -> void:
	if _desaturate_mat:
		_desaturate_mat.set_shader_parameter("desaturation", v)

func _respawn() -> void:
	if not _active:
		return
	_active = false
	# 清空升级状态（autoload 不会随 reload 重置）
	UpgradeManager.reset()
	# 重置鼠标模式（reload_current_scene 会由新 player._ready 重新 capture，但双保险）
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().reload_current_scene()

func _on_respawn_pressed() -> void:
	AudioManager.play_ui_click()
	_respawn()

func _to_main_menu() -> void:
	if not _active:
		return
	_active = false
	UpgradeManager.reset()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_main_menu_pressed() -> void:
	AudioManager.play_ui_click()
	_to_main_menu()
