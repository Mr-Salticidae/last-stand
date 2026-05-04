shader_type canvas_item;
render_mode blend_mix, unshaded;

// 屏幕边缘血迹提示：中心透明、边缘红色
// intensity 由 hud.gd 受伤时拉高、每帧衰减；为 0 时完全不可见
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 blood_color : source_color = vec4(0.55, 0.02, 0.02, 1.0);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.28;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.72;

// 廉价伪随机：打破过于规整的圆形 vignette，视觉上更像"血溅"
float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);
	float dist = length(centered);
	float mask = smoothstep(inner_radius, outer_radius, dist);
	float n = hash(floor(SCREEN_UV * 200.0));
	mask *= mix(0.75, 1.0, n);
	COLOR = vec4(blood_color.rgb, mask * intensity);
}
