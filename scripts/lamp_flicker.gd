extends OmniLight3D

@export var failure_chance_per_sec: float = 0.04
@export var flicker_count_min: int = 2
@export var flicker_count_max: int = 4
@export var off_time_min: float = 0.04
@export var off_time_max: float = 0.12
@export var on_time_min: float = 0.05
@export var on_time_max: float = 0.18

var _base_energy: float = 0.0
var _timer: float = 0.0

func _ready() -> void:
	_base_energy = light_energy
	_timer = randf()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		if randf() < failure_chance_per_sec:
			_flicker()

func _flicker() -> void:
	var count := randi_range(flicker_count_min, flicker_count_max)
	for i in count:
		light_energy = 0.0
		await get_tree().create_timer(randf_range(off_time_min, off_time_max)).timeout
		if not is_inside_tree(): return
		light_energy = _base_energy
		await get_tree().create_timer(randf_range(on_time_min, on_time_max)).timeout
		if not is_inside_tree(): return
	light_energy = _base_energy
