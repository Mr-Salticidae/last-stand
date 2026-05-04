extends Control

# HUD 右侧纵向武器栏（5 格垂直堆叠：1-4 普通武器，5 传说位）。
# 槽布局：name+key 左上小字 / 预览图（线稿）居中 / ammo 右下小字
# 5 格全展示（含未解锁的 LOCKED 占位 + 第 5 槽传说空位特殊样式）。
# 所有已解锁武器均显示弹药信息（订阅每把武器的 ammo_changed）。
# 解锁新武器时边框闪烁告知玩家：传说武器金红特殊闪烁，普通武器黄色闪烁。

const SLOT_COUNT: int = 5
const LEGENDARY_SLOT_IDX: int = 4   # 第 5 槽专属传说位
const SLOT_SIZE: Vector2 = Vector2(148, 64)
const SLOT_SEP: int = 6
# 预览图区域：槽内居中，留出顶 name / 底 ammo 位（避免和 ammo outline 撞边框）
# 4.57:1 纵横比匹配渲染输出（render_previews.tscn 的 1024×224 SubViewport）
const PREVIEW_RECT: Rect2 = Rect2(10, 18, 128, 28)

var _weapon_manager: Node
var _slots: Array[Panel] = []
var _previews: Array[TextureRect] = []
var _name_labels: Array[Label] = []
var _ammo_labels: Array[Label] = []
var _flash_tweens: Array[Tween] = []
# 已订阅 ammo_changed 的武器（避免重复订阅；legendary 拾取时新加入的武器走此路径）
var _subscribed: Dictionary = {}

# StyleBox 状态变体（动态构建）
var _sb_locked: StyleBoxFlat
var _sb_unlocked: StyleBoxFlat
var _sb_current: StyleBoxFlat
var _sb_legendary: StyleBoxFlat
var _sb_legendary_empty: StyleBoxFlat   # 第 5 槽空状态：暗紫边表示"传说位等待掉落"

func _ready() -> void:
	_build_styleboxes()
	_build_slots()

	_weapon_manager = get_tree().get_first_node_in_group("weapon_manager")
	if _weapon_manager == null:
		push_warning("weapon_bar.gd: 未找到 'weapon_manager' group")
		_refresh_all()
		return
	_weapon_manager.weapon_changed.connect(_on_weapon_changed)
	_weapon_manager.weapon_unlocked.connect(_on_weapon_unlocked)
	# 订阅所有现有武器的 ammo_changed；后续 legendary 加入时在 _on_weapon_unlocked 补订
	for w in _weapon_manager.weapons:
		_subscribe_weapon(w)
	_refresh_all()

func _build_styleboxes() -> void:
	_sb_locked    = _make_sb(Color(0.06, 0.06, 0.06, 0.55), Color(0.20, 0.18, 0.16, 0.7), 2)
	_sb_unlocked  = _make_sb(Color(0.10, 0.10, 0.12, 0.70), Color(0.55, 0.55, 0.55, 0.85), 2)
	_sb_current   = _make_sb(Color(0.18, 0.16, 0.08, 0.85), Color(1.0, 0.85, 0.30, 1.0), 3)
	_sb_legendary = _make_sb(Color(0.18, 0.10, 0.18, 0.85), Color(1.0, 0.55, 0.10, 1.0), 3)
	# 传说空位：暗紫底 + 暗紫边，比普通 LOCKED 显眼，提示"这是个特殊槽"
	_sb_legendary_empty = _make_sb(Color(0.10, 0.06, 0.12, 0.55), Color(0.45, 0.25, 0.50, 0.75), 2)

func _make_sb(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb

# 程序化构建：1 个 VBoxContainer + 5 个 Panel slot
func _build_slots() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", SLOT_SEP)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	for i in SLOT_COUNT:
		var slot := Panel.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(slot)
		_slots.append(slot)
		_flash_tweens.append(null)

		# 预览图（无边框，居中区域）：仅 TextureRect，KEEP_ASPECT_CENTERED 防变形
		# 期望线稿尺寸 ~256×64 单色（实际显示约 128×28，等比缩放）
		var preview := TextureRect.new()
		preview.position = PREVIEW_RECT.position
		preview.size = PREVIEW_RECT.size
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(preview)
		_previews.append(preview)

		# 武器名 + 数字键（左上角小字 "[1] 手枪"）
		var nm := Label.new()
		nm.position = Vector2(6, 2)
		nm.size = Vector2(SLOT_SIZE.x - 12, 16)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		nm.clip_contents = true
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		nm.add_theme_constant_override("outline_size", 3)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(nm)
		_name_labels.append(nm)

		# 弹药 / 状态（右下角小字 "12 / 60" 或 "未解锁"）
		# 边距：右 8 / 下 8 = 给当前槽 3px 边框 + 1px outline 留充足呼吸空间
		# 与 preview 底部 4px 重叠（但 preview 该区一般为空白/阴影，影响极小）
		var am := Label.new()
		am.position = Vector2(SLOT_SIZE.x - 80 - 8, SLOT_SIZE.y - 14 - 8)
		am.size = Vector2(80, 14)
		am.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		am.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		am.clip_contents = true
		am.add_theme_font_size_override("font_size", 12)
		am.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		am.add_theme_constant_override("outline_size", 1)
		am.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(am)
		_ammo_labels.append(am)

# 全量刷新所有槽位
func _refresh_all() -> void:
	for i in SLOT_COUNT:
		_refresh_slot(i)

# 单槽刷新
func _refresh_slot(idx: int) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	var slot: Panel = _slots[idx]
	var preview: TextureRect = _previews[idx]
	var nm: Label = _name_labels[idx]
	var am: Label = _ammo_labels[idx]

	# 第 5 槽（传说位）空状态：weapons[] 没有第 5 把 或 第 5 把不是传说武器
	# → 暗紫边特殊样式，提示"等待传说掉落"
	if idx == LEGENDARY_SLOT_IDX:
		var has_legendary: bool = (
			_weapon_manager != null
			and idx < _weapon_manager.weapons.size()
			and _weapon_manager.weapons[idx].is_legendary
		)
		if not has_legendary:
			slot.add_theme_stylebox_override("panel", _sb_legendary_empty)
			preview.texture = null
			nm.text = "[5] 传说"
			am.text = "等待掉落"
			nm.modulate = Color(0.75, 0.55, 0.80)
			am.modulate = Color(0.70, 0.50, 0.75)
			preview.modulate = Color(1, 1, 1)
			return

	# 槽位超出武器列表 → 普通 LOCKED 占位
	if _weapon_manager == null or idx >= _weapon_manager.weapons.size():
		slot.add_theme_stylebox_override("panel", _sb_locked)
		preview.texture = null
		nm.text = "[%d]  —" % (idx + 1)
		am.text = ""
		nm.modulate = Color(0.55, 0.55, 0.55)
		am.modulate = Color(0.55, 0.55, 0.55)
		return

	var w: Weapon = _weapon_manager.weapons[idx]
	nm.text = "[%d]  %s" % [idx + 1, w.weapon_name]

	if not w.unlocked:
		slot.add_theme_stylebox_override("panel", _sb_locked)
		# 未解锁不显示预览（避免剧透"将来会出现这把枪"），仅显示槽位号 + 武器名灰
		preview.texture = null
		am.text = "未解锁"
		nm.modulate = Color(0.55, 0.55, 0.55)
		am.modulate = Color(0.55, 0.55, 0.55)
		preview.modulate = Color(0.5, 0.5, 0.5)
		return

	# 已解锁：显示预览图（如果武器挂了 preview_texture）+ 始终显示弹药
	preview.texture = w.preview_texture
	preview.modulate = Color(1, 1, 1)
	am.text = "%d / %d" % [w.current_ammo, w.reserve_ammo]

	var is_current: bool = (w == _weapon_manager.current_weapon)
	if is_current:
		slot.add_theme_stylebox_override("panel", _sb_legendary if w.is_legendary else _sb_current)
		nm.modulate = Color(1.0, 0.95, 0.55) if w.is_legendary else Color(1.0, 0.95, 0.65)
		am.modulate = Color(1, 1, 1)
	else:
		slot.add_theme_stylebox_override("panel", _sb_unlocked)
		nm.modulate = Color(0.85, 0.85, 0.85)
		am.modulate = Color(0.75, 0.75, 0.75)   # 略暗以视觉区分非当前武器

# ========== 信号回调 ==========
# 切换武器：仅刷新所有槽以更新高亮（弹药由 _on_any_ammo_changed 单独维护）
func _on_weapon_changed(_weapon: Weapon) -> void:
	_refresh_all()

# 任何武器的弹药变化：刷新对应槽
func _on_any_ammo_changed(_current: int, _reserve: int, _maximum: int, w: Weapon) -> void:
	if _weapon_manager == null:
		return
	var idx: int = _weapon_manager.weapons.find(w)
	if idx >= 0:
		_refresh_slot(idx)

# 解锁新武器：刷新 + 边框闪烁；传说拾取时新武器需要订阅 ammo_changed
# 传说武器：金红色 8 次闪烁 / 普通武器：黄色 6 次闪烁
func _on_weapon_unlocked(weapon: Weapon) -> void:
	if _weapon_manager == null:
		return
	_subscribe_weapon(weapon)
	var idx: int = _weapon_manager.weapons.find(weapon)
	if idx < 0:
		return
	_refresh_all()
	_flash_slot(idx, weapon.is_legendary)

# 幂等订阅：同一武器多次调用只连接一次。Dictionary 用 weapon 实例做 key
func _subscribe_weapon(w: Weapon) -> void:
	if w == null or _subscribed.has(w):
		return
	w.ammo_changed.connect(_on_any_ammo_changed.bind(w))
	_subscribed[w] = true

func _flash_slot(idx: int, legendary: bool) -> void:
	if idx < 0 or idx >= _slots.size():
		return
	var slot: Panel = _slots[idx]
	var prev: Tween = _flash_tweens[idx]
	if prev and prev.is_valid():
		prev.kill()

	var flash_color: Color = Color(1.0, 0.25, 0.10) if legendary else Color(1.0, 0.85, 0.20)
	var loops: int = 8 if legendary else 6
	# self_modulate 仅作用 Panel 自身（背景 + 边框），不影响子 Label，避免和 _refresh_slot 冲突
	slot.self_modulate = Color(1, 1, 1)
	var tw: Tween = create_tween()
	tw.set_loops(loops)
	tw.tween_property(slot, "self_modulate", flash_color, 0.18)
	tw.tween_property(slot, "self_modulate", Color(1, 1, 1), 0.18)
	tw.finished.connect(func() -> void: slot.self_modulate = Color(1, 1, 1))
	_flash_tweens[idx] = tw
