shader_type canvas_item;
render_mode blend_add;

// Vertical 220px-tall red/orange band that fades at top and bottom.
// design: linear-gradient(180deg,
//   transparent 0%,
//   rgba(218,46,51,0.0) 30%,
//   rgba(255,115,80,0.06) 50%,
//   rgba(218,46,51,0.0) 70%,
//   transparent 100%)
//
// 用 add blend 近似 mix-blend-mode: screen（design 用 screen）

void fragment() {
	float t = UV.y; // 0..1 vertical
	// 5-stop gradient
	float a;
	if (t < 0.30) {
		a = mix(0.0, 0.0, t / 0.30);
	} else if (t < 0.50) {
		a = mix(0.0, 0.06, (t - 0.30) / 0.20);
	} else if (t < 0.70) {
		a = mix(0.06, 0.0, (t - 0.50) / 0.20);
	} else {
		a = 0.0;
	}
	vec3 col = mix(vec3(0.855, 0.18, 0.20), vec3(1.0, 0.45, 0.31), smoothstep(0.30, 0.50, t));
	COLOR = vec4(col * a, a);
}
