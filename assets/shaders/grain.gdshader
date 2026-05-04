shader_type canvas_item;
render_mode blend_mix;

// Film grain：每帧根据时间步进切换 noise，模拟 design 1.6s steps(4) infinite + opacity 0.18
// design 用 mix-blend-mode: overlay，这里简化成低 alpha mix blend，视觉差异不大

uniform float strength : hint_range(0.0, 0.5) = 0.18;
uniform float step_rate : hint_range(0.5, 10.0) = 2.5; // 1.6s / steps(4) = 0.4s/step → 2.5 steps/s

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float t_step = floor(TIME * step_rate);
	vec2 jitter = vec2(hash21(vec2(t_step, 1.7)), hash21(vec2(7.3, t_step))) * 100.0;
	vec2 cell = floor(FRAGCOORD.xy + jitter);
	float n = hash21(cell);
	// 中心化到 ±0.5 → ±strength
	float v = (n - 0.5) * 2.0 * strength;
	// overlay-ish: positive 加亮、negative 加暗，alpha 平均
	COLOR = vec4(vec3(0.5 + v), strength);
}
