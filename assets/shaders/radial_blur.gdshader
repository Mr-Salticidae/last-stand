shader_type canvas_item;

// 径向运动模糊：屏幕中央清晰，边缘沿径向被"拉丝"，模拟高速冲刺感
// 用法：挂在全屏 ColorRect 的 ShaderMaterial 上，外部 set intensity 控制强度

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float center_clear_radius : hint_range(0.0, 0.6) = 0.25;  // 中心清晰区半径（UV 单位）
uniform float blur_strength : hint_range(0.0, 0.15) = 0.06;       // 径向 sample 偏移强度
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	// intensity ≈ 0 时透明（让下层 3D / vignette 完整显示），不画 blur
	vec4 out_color = vec4(0.0);
	if (intensity >= 0.001) {
		vec2 dir = SCREEN_UV - vec2(0.5);
		float dist = length(dir);
		float edge_factor = smoothstep(center_clear_radius, 1.0, dist) * intensity;

		// 沿径向 sample 8 次取平均 → motion blur
		vec4 col = vec4(0.0);
		const int SAMPLES = 8;
		for (int i = 0; i < SAMPLES; i++) {
			float t = (float(i) / float(SAMPLES - 1)) - 0.5;  // -0.5 ~ +0.5
			vec2 offset = dir * blur_strength * t * edge_factor;
			col += texture(screen_texture, SCREEN_UV + offset);
		}
		col /= float(SAMPLES);

		// 原始像素 + edge_factor 决定本像素的"模糊程度"
		vec4 original = texture(screen_texture, SCREEN_UV);
		vec4 blurred = mix(original, col, edge_factor);
		// alpha 用 intensity 让 fade in/out 平滑（中心区 edge_factor=0 → blurred==original）
		blurred.a = intensity;
		out_color = blurred;
	}
	COLOR = out_color;
}
