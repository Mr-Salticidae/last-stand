shader_type canvas_item;

// 屏幕灰度滤镜：death_screen.gd 把 desaturation 从 0 tween 到 1，让画面由彩色渐变为黑白
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	// Rec.709 亮度权重：人眼对绿色最敏感、蓝色最不敏感
	float gray = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(mix(c.rgb, vec3(gray), desaturation), 1.0);
}
