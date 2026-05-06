class_name HealthPack extends Area3D

# 碰撞自动捡起的血包：玩家走过就 heal + 消失
# enemy._die 里按概率 spawn
# 寿命：从 Settings 难度档读 health_pack_lifetime（recruit 90 / standard 60 / breach 30）
# 过期流程：稳定期 → 警告期（最后 5s bob 频率加倍颤抖）→ 0.4s scale fade → free

const DEFAULT_LIFETIME: float = 60.0
const FADE_WARNING_SECONDS: float = 5.0
const FADE_OUT_DURATION: float = 0.4
const WARNING_BOB_PERIOD_MULT: float = 0.4  # 警告期 bob period 缩短到 0.4 倍 = 频率加倍多

@export var heal_amount: float = 30.0
@export var bob_amplitude: float = 0.2   # 上下浮动高度
@export var bob_period: float = 1.6      # 一次完整浮动周期秒数

@onready var _mesh: MeshInstance3D = $Mesh

var _lifetime: float = DEFAULT_LIFETIME
var _picked: bool = false
var _bob_tween: Tween

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_lifetime = float(Settings.get_difficulty_param("health_pack_lifetime", DEFAULT_LIFETIME))
	_start_bob(bob_period)
	_start_lifecycle()

# bob 动画抽出来可重启：稳定期用 bob_period，警告期用 bob_period * WARNING_BOB_PERIOD_MULT
func _start_bob(period: float) -> void:
	if _mesh == null:
		return
	if _bob_tween:
		_bob_tween.kill()
	_bob_tween = _mesh.create_tween().set_loops()
	_bob_tween.tween_property(_mesh, "position:y", bob_amplitude, period * 0.5).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(_mesh, "position:y", 0.0, period * 0.5).set_trans(Tween.TRANS_SINE)

func _start_lifecycle() -> void:
	# 稳定期：满寿命 - 警告窗口
	var stable_duration: float = max(0.0, _lifetime - FADE_WARNING_SECONDS)
	if stable_duration > 0.0:
		await get_tree().create_timer(stable_duration).timeout
		if _picked or not is_instance_valid(self):
			return
	# 警告期：bob 频率加倍提示"即将过期"
	_start_bob(bob_period * WARNING_BOB_PERIOD_MULT)
	await get_tree().create_timer(FADE_WARNING_SECONDS).timeout
	if _picked or not is_instance_valid(self):
		return
	_expire()

func _expire() -> void:
	if _bob_tween:
		_bob_tween.kill()
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, FADE_OUT_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	if is_instance_valid(self):
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if body.is_in_group("player") and body.has_method("heal"):
		_picked = true
		body.heal(heal_amount)
		AudioManager.play_pickup()
		queue_free()
