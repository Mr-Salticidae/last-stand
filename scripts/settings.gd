extends Node

# 全局设置 autoload。启动加载 user://settings.cfg、应用到 AudioServer / 玩家 / 等。
# 任何地方修改设置：调 set_xxx()，自动 save + apply。
# 当前管控：master_volume / sfx_volume / mouse_sensitivity / 9 个核心键位重绑

const CONFIG_PATH: String = "user://settings.cfg"

# 玩家可重绑的 9 个核心键盘动作（武器 1-5 / shoot / 滚轮等不在此列，避免冲突）
# 顺序就是 UI 显示顺序
const REBINDABLE_ACTIONS: Array[String] = [
	"forward", "backward", "left", "right",
	"jump", "crouch", "sprint",
	"reload", "free_looking",
]

# ========== 图形预设 ==========
# 显示模式：0=窗口（带边框）/ 1=无边框窗口 / 2=全屏
# 分辨率索引：与 RESOLUTION_PRESETS 对应；最后一项 (0,0) 表示"跟随显示器"
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(0, 0),
]
const RESOLUTION_NAMES: Array[String] = ["1280×720", "1920×1080", "2560×1440", "跟随显示器"]
# FPS 限制：0 = 无限
const FPS_PRESETS: Array[int] = [60, 120, 144, 0]
const FPS_NAMES: Array[String] = ["60", "120", "144", "无限"]
const WINDOW_MODE_NAMES: Array[String] = ["窗口", "无边框", "全屏"]

# ========== 难度 ==========
# 难度配置：每条 Dictionary 含子参数槽位，未来按需扩展（health_mult / speed_mult /
# spawn_rate_mult / drop_chance_mult 等）。enemy.gd / wave_manager.gd 等通过
# Settings.get_difficulty_param(key, default) 读取，未配置的子参数走 default。
const DIFFICULTY_PROFILES: Array[Dictionary] = [
	{  # 0 新兵报到（≈ v0.1 略低，新手友好）
		"key": "recruit",
		"name_cn": "新兵报到",
		"name_en": "RECRUIT",
		"max_concurrent_attackers": 1,    # AI 攻击欲望：同时进 WINDUP 的最大敌人数
		"enemy_health_mult": 0.85,
		"enemy_damage_mult": 0.7,
		"enemy_speed_mult": 0.95,
		"enemy_count_mult": 0.8,
		"intermission_mult": 1.3,
		"runner_unlock_wave": 3,
		"brute_unlock_wave": 5,
		"elite_wave_period": 5,
		"boss_wave_period": 15,
	},
	{  # 1 日常训练（默认 = v0.1 + 25-30% 综合压力，回应 itch.io"难度过低"反馈）
		"key": "standard",
		"name_cn": "日常训练",
		"name_en": "STANDARD",
		"max_concurrent_attackers": 2,
		"enemy_health_mult": 1.25,
		"enemy_damage_mult": 1.3,
		"enemy_speed_mult": 1.1,
		"enemy_count_mult": 1.3,
		"intermission_mult": 0.85,
		"runner_unlock_wave": 3,
		"brute_unlock_wave": 5,
		"elite_wave_period": 5,
		"boss_wave_period": 15,
	},
	{  # 2 极限突破（runner 移速碾压玩家，必须冲刺/滑铲拉距，更早出 boss/elite）
		"key": "breach",
		"name_cn": "极限突破",
		"name_en": "BREACH",
		"max_concurrent_attackers": 3,
		"enemy_health_mult": 1.7,
		"enemy_damage_mult": 1.6,
		"enemy_speed_mult": 1.4,           # runner 5.5×1.4=7.7m/s 超玩家步行
		"enemy_count_mult": 1.5,
		"intermission_mult": 0.6,
		"runner_unlock_wave": 1,           # 第一波就出 runner
		"brute_unlock_wave": 3,
		"elite_wave_period": 3,
		"boss_wave_period": 10,            # 提前 5 波出 boss
	},
]
const DIFFICULTY_NAMES_CN: Array[String] = ["新兵报到", "日常训练", "极限突破"]

# ========== 关卡（地图）==========
# key → 场景路径；level_select 和 main_menu 都从这里取
# available 决定关卡是否可选（false = 卡片置灰显示"即将到来"）
const ARENAS: Array[Dictionary] = [
	{"key": "training",  "name": "训练场",   "desc": "开阔野外，混合掩体\n中距离对枪",       "scene": "res://scenes/world_training.tscn",  "available": true},
	{"key": "warehouse", "name": "工业仓库", "desc": "室内 + 货架走廊\n中近距离 / 转角战斗", "scene": "res://scenes/world_warehouse.tscn", "available": true},
	{"key": "outpost",   "name": "前哨站",   "desc": "沙漠哨所 + 中央哨塔\n沙袋 / 油桶 / 长视距",  "scene": "res://scenes/world_outpost.tscn",   "available": true},
]

# 默认值（与 default_bus_layout 一致：0dB = 1.0 线性 = 100%）
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 0.4         # BGM 默认稍低，避免压过音效（v0.2: 0.7→0.4，玩家反馈首次进入太吵）
var mouse_sensitivity: float = 0.20    # player.mouse_sens 默认值

# 图形（默认：全屏 + 跟随显示器 + VSync 关 + 不限帧）
var window_mode: int = 2          # 0/1/2 见 WINDOW_MODE_NAMES
var resolution_idx: int = 3       # 跟随显示器
var vsync_enabled: bool = false
var fps_limit_idx: int = 3        # 无限

# 语言（占位，未来 i18n 用；当前不实际切文本）
var locale: String = "zh_CN"

# 上次选择的关卡 key（默认训练场）
var last_arena: String = "training"

# 难度索引（DIFFICULTY_PROFILES 下标），默认 1=标准
var difficulty_idx: int = 1

signal settings_changed   # 任何字段变更时 emit，UI / player 等可订阅同步

func _ready() -> void:
	load_settings()
	apply_audio()
	apply_graphics()
	# 灵敏度由 player 在 _input 时直接读 Settings.mouse_sensitivity，无需 push

# ========== 持久化 ==========
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return  # 首次运行，用默认值
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music_volume", music_volume))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	window_mode = int(cfg.get_value("graphics", "window_mode", window_mode))
	resolution_idx = int(cfg.get_value("graphics", "resolution_idx", resolution_idx))
	vsync_enabled = bool(cfg.get_value("graphics", "vsync_enabled", vsync_enabled))
	fps_limit_idx = int(cfg.get_value("graphics", "fps_limit_idx", fps_limit_idx))
	locale = String(cfg.get_value("language", "locale", locale))
	last_arena = String(cfg.get_value("arena", "last_arena", last_arena))
	difficulty_idx = int(cfg.get_value("gameplay", "difficulty_idx", difficulty_idx))
	_load_keybinds(cfg)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "resolution_idx", resolution_idx)
	cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
	cfg.set_value("graphics", "fps_limit_idx", fps_limit_idx)
	cfg.set_value("language", "locale", locale)
	cfg.set_value("arena", "last_arena", last_arena)
	cfg.set_value("gameplay", "difficulty_idx", difficulty_idx)
	_save_keybinds(cfg)
	cfg.save(CONFIG_PATH)

# ========== 键位重绑 ==========
# 持久化策略：仅记录每个 action 的第一个键盘 physical_keycode；
# 鼠标 / 滚轮事件由 InputMap 默认值保留，不被覆盖。

func _save_keybinds(cfg: ConfigFile) -> void:
	for action in REBINDABLE_ACTIONS:
		var keycode: int = 0
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keycode = (e as InputEventKey).physical_keycode
				break
		cfg.set_value("controls", "key_" + action, keycode)

func _load_keybinds(cfg: ConfigFile) -> void:
	for action in REBINDABLE_ACTIONS:
		if not cfg.has_section_key("controls", "key_" + action):
			continue
		var keycode: int = int(cfg.get_value("controls", "key_" + action, 0))
		if keycode == 0:
			continue
		_replace_keyboard_event(action, keycode)

# 把 action 当前的所有键盘事件清空，绑定单一新 keycode（physical）
# 鼠标按钮事件（如 shoot）保留不动
func _replace_keyboard_event(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)

# UI 调用：把 action 重绑到 new_keycode。若该键已绑给其他 REBINDABLE action，自动解绑（silent overwrite）
# 这样玩家不会因为冲突卡住流程，丢失绑定的 action 在 UI 显示"(未绑定)"，玩家可再去绑
func rebind_action(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	# 解绑其他 action 上同 keycode 的事件
	for other in REBINDABLE_ACTIONS:
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == physical_keycode:
				InputMap.action_erase_event(other, e)
	# 替换目标 action 的键盘事件
	_replace_keyboard_event(action, physical_keycode)
	save_settings()
	settings_changed.emit()

# 恢复默认按键：从 project.godot 重新读取 InputMap 全部 action
func reset_keybinds_to_default() -> void:
	InputMap.load_from_project_settings()
	save_settings()
	settings_changed.emit()

# 取 action 第一个键盘事件的可读名（OS.get_keycode_string）
func get_action_key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "(未绑定)"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var ev := e as InputEventKey
			var keycode: int = ev.physical_keycode
			if keycode == 0:
				keycode = ev.keycode
			return OS.get_keycode_string(keycode)
	return "(未绑定)"

# ========== 应用 ==========
# 把 0-1 线性值转 dB，0 时强制 -80dB（视为静音）
func _linear_to_db_safe(v: float) -> float:
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v)

func apply_audio() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, _linear_to_db_safe(master_volume))
	var sfx_idx: int = AudioServer.get_bus_index("Sfx")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, _linear_to_db_safe(sfx_volume))
	var music_idx: int = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, _linear_to_db_safe(music_volume))

# ========== Setter（UI 绑定）==========
func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_mouse_sensitivity(v: float) -> void:
	mouse_sensitivity = clampf(v, 0.05, 0.5)
	save_settings()
	settings_changed.emit()

# ========== 图形 ==========
# 应用所有图形设置：window_mode → resolution → vsync → fps_limit
# 全屏模式下分辨率忽略（用桌面分辨率），避免 EXCLUSIVE_FULLSCREEN 复杂度
func apply_graphics() -> void:
	# 1. 显示模式
	match window_mode:
		0: # 窗口
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1: # 无边框
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2: # 全屏
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# 2. 分辨率：仅窗口 / 无边框模式应用；全屏跟随桌面
	if window_mode != 2:
		var preset_idx: int = clampi(resolution_idx, 0, RESOLUTION_PRESETS.size() - 1)
		var res: Vector2i = RESOLUTION_PRESETS[preset_idx]
		if res.x <= 0 or res.y <= 0:
			res = DisplayServer.screen_get_size()
		DisplayServer.window_set_size(res)
		# 居中窗口
		var screen_size: Vector2i = DisplayServer.screen_get_size()
		DisplayServer.window_set_position(Vector2i((screen_size - res) / 2))

	# 3. VSync
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)

	# 4. FPS 限制
	var preset_fps: int = clampi(fps_limit_idx, 0, FPS_PRESETS.size() - 1)
	Engine.max_fps = FPS_PRESETS[preset_fps]

func set_window_mode(idx: int) -> void:
	window_mode = clampi(idx, 0, 2)
	apply_graphics()
	save_settings()
	settings_changed.emit()

func set_resolution_idx(idx: int) -> void:
	resolution_idx = clampi(idx, 0, RESOLUTION_PRESETS.size() - 1)
	apply_graphics()
	save_settings()
	settings_changed.emit()

func set_vsync_enabled(v: bool) -> void:
	vsync_enabled = v
	apply_graphics()
	save_settings()
	settings_changed.emit()

func set_fps_limit_idx(idx: int) -> void:
	fps_limit_idx = clampi(idx, 0, FPS_PRESETS.size() - 1)
	apply_graphics()
	save_settings()
	settings_changed.emit()

# ========== 语言（占位）==========
func set_locale(v: String) -> void:
	locale = v
	save_settings()
	settings_changed.emit()

# ========== 关卡 ==========
func set_last_arena(key: String) -> void:
	# 仅接受 ARENAS 中存在且 available 的 key（防止把 last_arena 设成未实装关卡）
	for a in ARENAS:
		if a["key"] == key and a["available"]:
			last_arena = key
			save_settings()
			settings_changed.emit()
			return

# ========== 难度 ==========
func set_difficulty_idx(idx: int) -> void:
	difficulty_idx = clampi(idx, 0, DIFFICULTY_PROFILES.size() - 1)
	save_settings()
	settings_changed.emit()

# 当前难度的 profile dict（未越界后已 clamp，安全）
func get_difficulty_profile() -> Dictionary:
	return DIFFICULTY_PROFILES[clampi(difficulty_idx, 0, DIFFICULTY_PROFILES.size() - 1)]

# 读取当前难度的子参数；未配置的子参数返回 default
func get_difficulty_param(key: String, default = null):
	return get_difficulty_profile().get(key, default)

# 取当前 last_arena 的场景路径（如果 last_arena 因故无效，回退到第一个可用关卡）
func get_current_arena_scene() -> String:
	for a in ARENAS:
		if a["key"] == last_arena and a["available"]:
			return a["scene"]
	for a in ARENAS:
		if a["available"]:
			return a["scene"]
	return ""
