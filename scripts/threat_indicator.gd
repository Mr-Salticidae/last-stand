extends Control

# 屏幕边缘威胁指示器：红色三角指向屏幕外正在 WINDUP 的敌人。
# 敌人在屏幕内可见时不显示（玩家已经看到警示色脉冲）。

@export var indicator_color: Color = Color(1.0, 0.2, 0.15, 0.9)
@export var indicator_size: float = 28.0
@export var edge_padding: float = 60.0   # 三角指向屏幕边缘 inset 多少像素
@export var pulse_hz: float = 4.0         # 脉冲闪烁频率，营造紧迫感
@export var visibility_margin: float = 40.0  # 敌人投影超出 viewport 这么多像素就算"屏幕外"

var _camera: Camera3D
var _elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 延迟一帧找 camera，等 player 初始化完成
	await get_tree().process_frame
	_refresh_camera()

func _refresh_camera() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		_camera = player.find_child("Camera3D", true, false) as Camera3D

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	if _camera == null:
		_refresh_camera()
		return
	if not is_instance_valid(_camera):
		_camera = null
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = viewport_size * 0.5
	# 脉冲 alpha：0.5-1.0 间正弦
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * pulse_hz * TAU)
	var draw_color: Color = indicator_color
	draw_color.a *= pulse

	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("is_winding_up"):
			continue
		if not e.is_winding_up():
			continue

		var enemy_pos: Vector3 = e.global_position + Vector3.UP * 1.0  # 胸部高度
		var behind: bool = _camera.is_position_behind(enemy_pos)
		var screen_pos: Vector2 = _camera.unproject_position(enemy_pos)

		# 敌人在屏幕内 + 相机前方 → 玩家已经看到，不画指示器
		var in_view: bool = (
			not behind
			and screen_pos.x >= -visibility_margin
			and screen_pos.x <= viewport_size.x + visibility_margin
			and screen_pos.y >= -visibility_margin
			and screen_pos.y <= viewport_size.y + visibility_margin
		)
		if in_view:
			continue

		# 计算指示器放在屏幕边缘的哪个位置
		# 敌人在相机后方时 unproject 结果不可信，用相机 forward + enemy 方向重算角度
		var indicator_dir: Vector2
		if behind:
			# 敌人在身后：把方向反向并在屏幕下半显示
			var to_enemy: Vector3 = enemy_pos - _camera.global_position
			var cam_right: Vector3 = _camera.global_transform.basis.x
			var side: float = cam_right.dot(to_enemy)
			# 身后的敌人：左右取 camera 的左右维度，竖直维度一律朝下（表示"在身后"）
			indicator_dir = Vector2(sign(side) if absf(side) > 0.01 else 1.0, 1.0).normalized()
		else:
			indicator_dir = (screen_pos - screen_center).normalized()
			if indicator_dir.length_squared() < 0.01:
				continue

		# 从屏幕中心沿 indicator_dir 射线，到屏幕边缘 inset
		var half_w: float = screen_center.x - edge_padding
		var half_h: float = screen_center.y - edge_padding
		# 计算射线到矩形边界的交点
		var t_x: float = INF if indicator_dir.x == 0.0 else half_w / absf(indicator_dir.x)
		var t_y: float = INF if indicator_dir.y == 0.0 else half_h / absf(indicator_dir.y)
		var t: float = min(t_x, t_y)
		var draw_pos: Vector2 = screen_center + indicator_dir * t

		_draw_triangle(draw_pos, indicator_dir, draw_color)

# 画一个朝向 dir 的三角（尖端在 tip，底在反方向）
func _draw_triangle(tip: Vector2, dir: Vector2, color: Color) -> void:
	var perp: Vector2 = Vector2(-dir.y, dir.x)  # dir 的左垂直
	var base: Vector2 = tip - dir * indicator_size
	var left: Vector2 = base + perp * (indicator_size * 0.5)
	var right: Vector2 = base - perp * (indicator_size * 0.5)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
	# 黑色描边增强对比
	var outline: Color = Color(0, 0, 0, color.a * 0.85)
	draw_polyline(PackedVector2Array([tip, left, right, tip]), outline, 2.0)
