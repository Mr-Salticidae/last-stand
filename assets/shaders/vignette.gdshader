shader_type canvas_item;

// LAST STAND vignette — 径向暗角，对应 design persistent chrome #9
// 中心 transparent → 边缘 rgba(0,0,0,0.85)

uniform float inner: hint_range(0.0, 1.0) = 0.35;
uniform float outer: hint_range(0.0, 1.5) = 1.0;
uniform float strength: hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec2 c = UV - vec2(0.5);
	// 椭圆形 vignette（左右更宽，上下更紧）
	c.x *= 1.4;
	float d = length(c);
	float a = smoothstep(inner, outer, d) * strength;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
