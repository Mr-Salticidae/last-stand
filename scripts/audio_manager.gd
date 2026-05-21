extends Node

# 全局 autoload 音效管理器。
# 用 AudioStreamPlayer pool（预创建）代替 new/add_child/queue_free，消除"首次播放延迟"。
# 所有 stream 默认用程序化 WAV 生成；Inspector 可替换为真实素材。

# ========== 参数化音效 slot ==========
@export_group("Weapon")
# 每把武器独立 shot 音效，dispatch 走 weapon.weapon_id
# 槽位为空 → 走对应 _fallback["shot_<id>"]，再 fallback 到通用 _fallback["shot"]
@export var pistol_shot_stream: AudioStream
@export var rifle_shot_stream: AudioStream
@export var shotgun_shot_stream: AudioStream
@export var revolver_shot_stream: AudioStream
@export var heavy_mg_shot_stream: AudioStream
@export var railgun_shot_stream: AudioStream
@export var reload_stream: AudioStream
@export var dry_fire_stream: AudioStream
@export var hit_stream: AudioStream
@export var headshot_stream: AudioStream
@export var kill_stream: AudioStream
@export var execute_stream: AudioStream

@export_group("Player")
@export var player_damaged_stream: AudioStream
@export var player_healed_stream: AudioStream
@export var player_body_fall_stream: AudioStream
@export var player_tinnitus_stream: AudioStream

@export_group("Enemy")
@export var enemy_windup_stream: AudioStream
@export var enemy_attack_hit_stream: AudioStream

@export_group("Pickups / Waves")
@export var pickup_stream: AudioStream
@export var wave_start_stream: AudioStream

@export_group("UI")
@export var ui_click_stream: AudioStream

@export_group("Settings")
@export var sfx_bus: String = "Sfx"          # 玩家可调音量的 sfx 总线（受 Settings.sfx_volume 控制）
@export var music_bus: String = "Music"       # BGM 总线（受 Settings.music_volume 控制）
@export var enemy_sfx_max_distance: float = 40.0
const KEEPALIVE_BUS: String = "Master"        # keepalive 显式走 Master，避免被 sfx_volume 静音破坏 WASAPI 防挂起

# ========== BGM 资源（单轨贯穿菜单+战斗）==========
const BGM_MAIN_PATH: String = "res://assets/audio/bgm/bunker_watch.mp3"
const BGM_FADE_IN: float = 1.5      # 启动 / 切歌 淡入秒数
const BGM_FADE_OUT: float = 0.6     # stop_bgm 淡出秒数
const BGM_BASE_VOLUME_DB: float = 0.0  # 播放时的目标音量（音量调节走 Music bus，这里固定 0dB）

# ========== SFX 资源自动加载 ==========
# autoload 脚本的 @export 槽在 Inspector 里赋不了值，改用文件名约定加载
# 文件名（不含扩展名）→ export 字段名 的映射；在 _ready 里 load 后覆盖 null 槽
# 文件不存在 → 保持 null → 走 _fallback 程序生成（开发期占位时仍然有声）
const SFX_DIR: String = "res://assets/audio/sfx/"
# 武器射击 dB 偏移（按武器口径手感调整音量）
# 仅 pistol 衰减是因为目前 ElevenLabs 生成的手枪 sfx 偏响；其他后续按听感微调
const SHOT_VOLUMES_DB: Dictionary = {
	"pistol":   -14.0,
	"rifle":     0.0,
	"shotgun":   0.0,
	"revolver":  0.0,
	"heavy_mg":  0.0,
	"railgun":   0.0,
}

const SFX_FILE_MAP: Dictionary = {
	"pistol_shot":      "pistol_shot_stream",
	"rifle_shot":       "rifle_shot_stream",
	"shotgun_shot":     "shotgun_shot_stream",
	"revolver_shot":    "revolver_shot_stream",
	"heavy_mg_shot":    "heavy_mg_shot_stream",
	"railgun_shot":     "railgun_shot_stream",
	"reload":           "reload_stream",
	"dry_fire":         "dry_fire_stream",
	"hit":              "hit_stream",
	"headshot":         "headshot_stream",
	"kill":             "kill_stream",
	"execute":          "execute_stream",
	"player_damaged":   "player_damaged_stream",
	"player_healed":    "player_healed_stream",
	"enemy_windup":     "enemy_windup_stream",
	"enemy_attack_hit": "enemy_attack_hit_stream",
	"pickup":           "pickup_stream",
	"wave_start":       "wave_start_stream",
	"ui_click":         "ui_click_stream",
}

# ========== Pool + fallback ==========
const POOL_SIZE_2D: int = 16
const POOL_SIZE_3D: int = 12

var _fallback: Dictionary = {}
var _2d_pool: Array[AudioStreamPlayer] = []
var _3d_pool: Array[AudioStreamPlayer3D] = []
var _2d_idx: int = 0
var _3d_idx: int = 0
# Keepalive player：永久 loop 播 -80dB 静音，阻止 Windows audio session 进入挂起状态
# 否则静默 1+ 秒后第一次播放会被 OS 冷启动延迟吃掉（症状：装填后第一发哑炮）
var _keepalive: AudioStreamPlayer

# BGM 持久 player（autoload 上，跨场景持续不间断）
var _bgm_player: AudioStreamPlayer = null
var _bgm_main_stream: AudioStream = null
var _bgm_tween: Tween = null

func _ready() -> void:
	_init_fallback_streams()
	_autoload_sfx_files()
	_init_pools()
	_init_keepalive()
	_init_bgm()
	_warmup()
	# music/master 音量变化时同步 keepalive 状态（玩家把 BGM 调到 0 → 重新启 keepalive 防挂起）
	Settings.settings_changed.connect(_update_keepalive_state)
	# 启动初值：BGM 还没起，先 play keepalive 防 main_menu 加载期间 WASAPI 挂起
	_update_keepalive_state()

# 按 SFX_FILE_MAP 把 assets/audio/sfx/<name>.mp3 加载到对应 export 字段
# 找不到的文件保持 null，play_xxx 函数会走 _fallback 兜底
func _autoload_sfx_files() -> void:
	for filename in SFX_FILE_MAP:
		var path: String = SFX_DIR + filename + ".mp3"
		if ResourceLoader.exists(path):
			set(SFX_FILE_MAP[filename], load(path))

func _init_fallback_streams() -> void:
	_fallback["shot"]            = _gen_wav(180.0, 0.08, 2.5, 0.85, 0.6)
	_fallback["reload"]          = _gen_wav(500.0, 0.12, 1.5, 0.4, 0.25)
	# 空仓击发：高频短促咔哒（金属撞击感），duration 极短防玩家觉得是普通枪声
	_fallback["dry_fire"]        = _gen_wav(2400.0, 0.04, 4.5, 0.7, 0.35)
	_fallback["hit"]             = _gen_wav(1200.0, 0.10, 2.5, 0.15, 0.35)
	_fallback["headshot"]        = _gen_wav(2200.0, 0.18, 2.0, 0.2, 0.5)
	_fallback["kill"]            = _gen_wav(140.0, 0.32, 1.8, 0.35, 0.5)
	# 处决：低频重击 + 大量噪声（撕裂湿响），比 kill 更猛更长
	_fallback["execute"]         = _gen_wav(90.0, 0.34, 1.5, 0.7, 0.8)
	_fallback["player_damaged"]  = _gen_wav(110.0, 0.28, 1.8, 0.2, 0.55)
	_fallback["player_healed"]   = _gen_wav(660.0, 0.22, 1.3, 0.0, 0.35)
	# 倒地声：40Hz sub-bass + 40ms 软攻击，重心下压感的"扑通"闷响（避免像中弹）
	_fallback["player_body_fall"] = _gen_body_fall()
	# 耳鸣：3500Hz 纯正弦慢衰减 2.5s，模拟爆炸/枪击后听力受损的高频 ringing
	_fallback["player_tinnitus"] = _gen_wav(3500.0, 2.5, 0.6, 0.0, 0.16)
	_fallback["enemy_windup"]    = _gen_wav(95.0, 0.38, 1.2, 0.3, 0.5)
	_fallback["enemy_attack_hit"]= _gen_wav(220.0, 0.14, 2.0, 0.4, 0.5)
	_fallback["pickup"]          = _gen_wav(880.0, 0.15, 1.2, 0.0, 0.4)
	_fallback["wave_start"]      = _gen_wav(75.0, 0.45, 1.5, 0.35, 0.7)
	_fallback["ui_click"]        = _gen_wav(1000.0, 0.06, 2.0, 0.0, 0.3)

func _init_pools() -> void:
	for i in POOL_SIZE_2D:
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_2d_pool.append(p)
	for i in POOL_SIZE_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = sfx_bus
		p.max_distance = enemy_sfx_max_distance
		add_child(p)
		_3d_pool.append(p)

# Keepalive：30 秒次低音正弦 loop，让 Windows audio session 视为 "active output"
# 历史教训（编辑器 vs .exe 不同）：编辑器 F5 环境对 keepalive 信号要求宽松（编辑器自身维持会话），
# .exe 独立进程 WASAPI 严格检测，-75dBFS 输出已不够。
# 当前方案：30Hz 次低音 sin + ±5000 振幅（-16dBFS digital，OS 充分识别）+ volume_db -36
# 输出 ~-52dBFS @ 30Hz，但因等响曲线在 30Hz 处 SPL 比 1kHz 低 25-30dB，
# 加上消费级耳机普遍 30Hz 几乎不再现 → 听感等效 ~-78dBFS @ 1kHz（人耳门槛之下）
# v0.2：好耳机仍能听到 30Hz 嗡嗡。改成"按需启动"——BGM 在播且音量 > 0 时停 keepalive
# （BGM 本身就是足够强的信号防 WASAPI 挂起），仅在 BGM 静音时启动 keepalive 兜底。
func _init_keepalive() -> void:
	_keepalive = AudioStreamPlayer.new()
	_keepalive.bus = KEEPALIVE_BUS
	_keepalive.volume_db = -36.0
	var stream: AudioStreamWAV = _gen_keepalive_loop(30.0)
	_keepalive.stream = stream
	add_child(_keepalive)
	# 不在此处 play()：等 _init_bgm 完成 + _update_keepalive_state 决定是否启动
	# （主菜单进入立即调 play_main_bgm，绝大多数情况 BGM 在播，keepalive 不会启动）

# 按 BGM 实际是否有声决定 keepalive 启停。BGM 在播且 music/master 都 > 0 时停 keepalive
# （BGM stream 本身已让 WASAPI session 保持活跃）；否则启动 keepalive 防挂起
# 触发点：_ready 末尾、play_main_bgm 末尾、stop_bgm、Settings.settings_changed
func _update_keepalive_state() -> void:
	if _keepalive == null:
		return
	var bgm_audible: bool = (
		_bgm_player != null
		and _bgm_player.playing
		and Settings.music_volume > 0.001
		and Settings.master_volume > 0.001
	)
	if bgm_audible:
		if _keepalive.playing:
			_keepalive.stop()
	else:
		if not _keepalive.playing:
			_keepalive.play()

# 次低音 sin loop：30Hz 给足 buffer 信号能量保持会话活跃，但耳机听感极弱
# 比白噪声更适合做 keepalive：能量集中在单频且远离人耳敏感带（2-4kHz）
func _gen_keepalive_loop(duration: float) -> AudioStreamWAV:
	const SR: int = 22050
	var num: int = int(SR * duration)
	var bytes := PackedByteArray()
	bytes.resize(num * 2)
	var freq: float = 30.0
	var amp: int = 5000   # ±5000 / 32767 ≈ -16dBFS digital，OS 充分识别为活跃信号
	for i in num:
		var t: float = float(i) / float(SR)
		var s16: int = clampi(int(sin(t * freq * TAU) * amp), -32767, 32767)
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = num
	return s

# BGM 持久 player：autoload 上挂一个 AudioStreamPlayer，跨场景不释放
# play_main_bgm() 调用时若已在播同一首则忽略，让主菜单 → 战斗 BGM 自然延续
func _init_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = music_bus
	_bgm_player.volume_db = -80.0
	add_child(_bgm_player)
	if not ResourceLoader.exists(BGM_MAIN_PATH):
		push_warning("[BGM] 资源不存在：%s" % BGM_MAIN_PATH)
		return
	_bgm_main_stream = load(BGM_MAIN_PATH) as AudioStream
	# .mp3 / .ogg 默认不循环，强制开 loop（覆盖 .import 文件的设置）
	if _bgm_main_stream is AudioStreamMP3:
		(_bgm_main_stream as AudioStreamMP3).loop = true
	elif _bgm_main_stream is AudioStreamOggVorbis:
		(_bgm_main_stream as AudioStreamOggVorbis).loop = true

# 预热 AudioServer：用 -80dB 静音播一帧，让所有 player 的 voice 初始化完成
# 注：keepalive player 永久 loop 静音保持 audio session 不挂起，warmup 仍保留作为初始化保险
func _warmup() -> void:
	for p in _2d_pool:
		p.stream = _fallback["shot"]
		p.volume_db = -80.0
		p.play()
	for p in _3d_pool:
		p.stream = _fallback["shot"]
		p.volume_db = -80.0
		p.global_position = Vector3.ZERO
		p.play()

# ========== 对外 play 接口 ==========
# 开枪用临时 player：每次新建一个 AudioStreamPlayer，播完自动销毁
# Why: pool / 复用方案下偶发"装填后第一发哑炮"。诊断日志显示 play() 被调用、was_playing=false、
#      stream/bus 参数全部正常，但实际无声 —— 推断是 Godot 4 stop()→play() 之间 AudioStreamPlayback
#      内部状态有 race。临时 player 完全无共享状态，规避所有复用问题。
# 开火频率最高 ~12.5/秒，AudioStreamPlayer 创建开销在 Godot 4 里非常低，不会成为瓶颈。
# weapon_id 来自 weapon.weapon_id（"pistol" / "rifle" / "shotgun" / "revolver" / "heavy_mg" / "railgun"）
func play_shot(weapon_id: String = "pistol") -> void:
	var stream: AudioStream = _resolve_shot_stream(weapon_id)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = sfx_bus
	p.stream = stream
	p.volume_db = SHOT_VOLUMES_DB.get(weapon_id, 0.0)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# 按 weapon_id 解析 shot stream：先查 export 槽，没有则查 fallback dict
func _resolve_shot_stream(weapon_id: String) -> AudioStream:
	match weapon_id:
		"pistol":   return pistol_shot_stream if pistol_shot_stream else _fallback["shot"]
		"rifle":    return rifle_shot_stream if rifle_shot_stream else _fallback["shot"]
		"shotgun":  return shotgun_shot_stream if shotgun_shot_stream else _fallback["shot"]
		"revolver": return revolver_shot_stream if revolver_shot_stream else _fallback["shot"]
		"heavy_mg": return heavy_mg_shot_stream if heavy_mg_shot_stream else _fallback["shot"]
		"railgun":  return railgun_shot_stream if railgun_shot_stream else _fallback["shot"]
	return _fallback["shot"]
func play_reload() -> void:
	_play_2d(reload_stream if reload_stream else _fallback["reload"])
func play_dry_fire() -> void:
	_play_2d(dry_fire_stream if dry_fire_stream else _fallback["dry_fire"], -4.0)
func play_hit() -> void:
	_play_2d(hit_stream if hit_stream else _fallback["hit"], -4.0, randf_range(0.95, 1.05))
func play_headshot() -> void:
	_play_2d(headshot_stream if headshot_stream else _fallback["headshot"], 0.0, randf_range(0.95, 1.05))
func play_kill() -> void:
	_play_2d(kill_stream if kill_stream else _fallback["kill"])

func play_execute() -> void:
	_play_2d(execute_stream if execute_stream else _fallback["execute"])
func play_player_damaged() -> void:
	_play_2d(player_damaged_stream if player_damaged_stream else _fallback["player_damaged"])
func play_player_healed() -> void:
	_play_2d(player_healed_stream if player_healed_stream else _fallback["player_healed"])
# 死亡音效组合：倒地声 + 耳鸣双层，比单一 thump 更符合 FPS 战场代入感
# 低频被等响曲线衰减给 +2dB；耳鸣持续覆盖到 UI 淡入阶段，让玩家感受到"听力受损"
func play_player_death_audio() -> void:
	_play_2d(player_body_fall_stream if player_body_fall_stream else _fallback["player_body_fall"], 2.0)
	_play_2d(player_tinnitus_stream if player_tinnitus_stream else _fallback["player_tinnitus"], -2.0)
func play_enemy_windup(pos: Vector3) -> void:
	_play_3d(enemy_windup_stream if enemy_windup_stream else _fallback["enemy_windup"], pos)
func play_enemy_attack_hit(pos: Vector3) -> void:
	_play_3d(enemy_attack_hit_stream if enemy_attack_hit_stream else _fallback["enemy_attack_hit"], pos)
func play_pickup() -> void:
	_play_2d(pickup_stream if pickup_stream else _fallback["pickup"])
func play_wave_start() -> void:
	# 淡入避免突兀吓到玩家：临时 player 用 tween 把 volume_db 从 -80 拉到目标
	# 不走 _play_2d 池是因为 pool 共享 player 不便单独 fade，且 wave_start 频率极低（每波 1 次）
	var stream: AudioStream = wave_start_stream if wave_start_stream else _fallback["wave_start"]
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = sfx_bus
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play()
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", -8.0, 0.3)
	p.finished.connect(p.queue_free)
func play_ui_click() -> void:
	_play_2d(ui_click_stream if ui_click_stream else _fallback["ui_click"], -4.0)

# ========== BGM API ==========
# 进入主菜单时调一次 play_main_bgm()，跨场景延续；战斗中不再调（同一首贯穿）
# stop_bgm() 仅在退出游戏 / 极端场景需要静音时用
func play_main_bgm() -> void:
	if _bgm_player == null or _bgm_main_stream == null:
		return
	# 已在播同一首 → 不重启，让 BGM 在场景切换间无缝延续
	if _bgm_player.playing and _bgm_player.stream == _bgm_main_stream:
		return
	_bgm_player.stream = _bgm_main_stream
	_bgm_player.volume_db = -80.0
	_bgm_player.play()
	_bgm_fade_to(BGM_BASE_VOLUME_DB, BGM_FADE_IN)
	# BGM 起来了，停 keepalive（避免好耳机听到 30Hz 嗡嗡）
	_update_keepalive_state()

func stop_bgm() -> void:
	if _bgm_player == null or not _bgm_player.playing:
		return
	_bgm_fade_to(-80.0, BGM_FADE_OUT, true)
	# stop_bgm 是退出场景，立即启 keepalive 兜底 WASAPI（fade 0.6s 重叠期可接受）
	if _keepalive and not _keepalive.playing:
		_keepalive.play()

func _bgm_fade_to(target_db: float, duration: float, stop_after: bool = false) -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_player, "volume_db", target_db, duration)
	if stop_after:
		_bgm_tween.tween_callback(_bgm_player.stop)

# ========== pool 分配 ==========
# 必须先 stop() 再换 stream + play()。Godot 4 中复用的 player 即使 stream 已结束，
# .playing 状态刷新有 race —— 不 stop 直接换 stream + play 会出现"新流没从头播"的现象。
# 症状：装填后第一发开枪没声、波次刷新瞬间紧接的 play_shot 没声。
func _play_2d(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _2d_pool.is_empty():
		return
	# 优先找空闲 player；全忙时 round-robin 覆盖最老的
	var p: AudioStreamPlayer = null
	for candidate in _2d_pool:
		if not candidate.playing:
			p = candidate
			break
	if p == null:
		p = _2d_pool[_2d_idx]
		_2d_idx = (_2d_idx + 1) % _2d_pool.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()

func _play_3d(stream: AudioStream, pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _3d_pool.is_empty():
		return
	var p: AudioStreamPlayer3D = null
	for candidate in _3d_pool:
		if not candidate.playing:
			p = candidate
			break
	if p == null:
		p = _3d_pool[_3d_idx]
		_3d_idx = (_3d_idx + 1) % _3d_pool.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.global_position = pos
	p.play()

# 倒地声专用：双层叠加 — 冲击层（扑）+ 重量层（weight），整体 0.5s
# 单层 sub-bass 慢衰减会变成"嗡"的持续低鸣（缺前端冲击点），所以拆两层：
#   Layer A（冲击）：160Hz + 噪声，18ms 快攻击 + 0.20s 陡降 → 砸地的"扑"
#   Layer B（重量）：50Hz 纯低频，25ms 软攻击 + 0.40s 中衰 → 身体重量感
func _gen_body_fall() -> AudioStreamWAV:
	const SR: int = 22050
	const DURATION: float = 0.5
	var num: int = int(SR * DURATION)
	var bytes := PackedByteArray()
	bytes.resize(num * 2)
	# 冲击层参数
	const A_ATTACK: float = 0.018
	const A_DECAY: float = 0.20         # 冲击层只持续 0.2s，前端定义"扑"
	const A_FREQ: float = 160.0
	const A_NOISE: float = 0.45         # 噪声做木质砸地的纹理
	const A_WEIGHT: float = 0.65
	# 重量层参数
	const B_ATTACK: float = 0.025
	const B_FREQ: float = 50.0
	const B_FADE_EXP: float = 1.6
	const B_WEIGHT: float = 0.45
	const GAIN: float = 0.95
	for i in num:
		var t: float = float(i) / float(SR)
		# Layer A: 冲击层包络（attack ramp + 短促陡降，0.2s 后归零）
		var env_a: float = 0.0
		if t < A_ATTACK:
			env_a = t / A_ATTACK
		elif t < A_ATTACK + A_DECAY:
			var da: float = (t - A_ATTACK) / A_DECAY
			env_a = pow(1.0 - da, 2.5)
		var tone_a: float = sin(t * A_FREQ * TAU)
		var noise_v: float = randf() * 2.0 - 1.0
		var layer_a: float = env_a * (tone_a * (1.0 - A_NOISE) + noise_v * A_NOISE)
		# Layer B: 重量层包络（软攻击 + 中速衰减覆盖整段）
		var env_b: float = 0.0
		if t < B_ATTACK:
			env_b = t / B_ATTACK
		else:
			var db: float = (t - B_ATTACK) / (DURATION - B_ATTACK)
			env_b = pow(1.0 - db, B_FADE_EXP)
		var layer_b: float = env_b * sin(t * B_FREQ * TAU)
		var amp: float = (layer_a * A_WEIGHT + layer_b * B_WEIGHT) * GAIN
		var s16: int = clampi(int(amp * 32767.0), -32767, 32767)
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	return s

# ========== 程序化生成 AudioStreamWAV ==========
func _gen_wav(freq: float, duration: float, fade_exp: float, noise_mix: float, gain: float) -> AudioStreamWAV:
	const SR: int = 22050
	var num: int = int(SR * duration)
	var bytes := PackedByteArray()
	bytes.resize(num * 2)
	for i in num:
		var t: float = float(i) / float(SR)
		var env: float = pow(1.0 - t / duration, fade_exp)
		var tone: float = sin(t * freq * TAU)
		var noise_v: float = randf() * 2.0 - 1.0
		var amp: float = env * (tone * (1.0 - noise_mix) + noise_v * noise_mix) * gain
		var s16: int = clampi(int(amp * 32767.0), -32767, 32767)
		bytes[i * 2] = s16 & 0xFF
		bytes[i * 2 + 1] = (s16 >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	return s
