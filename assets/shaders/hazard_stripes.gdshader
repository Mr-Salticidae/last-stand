shader_type canvas_item;

// LAST STAND hazard chevron border — 4 边 45° 黄黑斜条带
// design persistent chrome #10：repeating-linear-gradient(45deg, yellow 0 16, black 16 32)
// 用 SCREEN_PIXEL_SIZE 推算 viewport 大小，shader 内部判断像素是否在边带内 + 斜条 pattern
// 黑条用 discard 让背景透出，无须真画黑色（避免叠加变更深）

uniform vec3 stripe_color : source_color = vec3(0.784, 0.635, 0.231);
uniform float thickness = 6.0;
uniform float inset = 24.0;
uniform float stripe_size = 16.0;
uniform float opacity = 0.35;

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 vsz = 1.0 / SCREEN_PIXEL_SIZE;
	float w = vsz.x;
	float h = vsz.y;

	bool in_top = (px.y >= inset && px.y < inset + thickness);
	bool in_bot = (px.y >= h - inset - thickness && px.y < h - inset);
	bool in_left = (px.x >= inset && px.x < inset + thickness);
	bool in_right = (px.x >= w - inset - thickness && px.x < w - inset);
	bool in_h_range = (px.x >= inset && px.x < w - inset);
	bool in_v_range = (px.y >= inset && px.y < h - inset);

	bool in_band = ((in_top || in_bot) && in_h_range) || ((in_left || in_right) && in_v_range);
	if (!in_band) {
		discard;
	}

	float d = px.x + px.y;
	float m = mod(d, stripe_size * 2.0);
	if (m >= stripe_size) {
		discard;
	}

	COLOR = vec4(stripe_color, opacity);
}
