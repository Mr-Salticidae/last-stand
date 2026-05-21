// 表面 grunge 着色器：纯色基底 + 大尺度低对比脏污 + 缝隙变暗 + 可选腐蚀渗色。
// 设计要点：脏感靠"低频 + 低对比"，避免高频细节累眼。world-space 取样无需 UV、无平铺接缝。
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float grunge_scale = 0.11;          // 越小特征越大越缓（低频）
uniform float grunge_strength : hint_range(0.0, 1.0) = 0.3;  // 脏污变暗幅度（低=温和）
uniform float micro_scale = 1.3;            // 细层尺度
uniform float micro_strength : hint_range(0.0, 0.3) = 0.05;  // 细层强度（极低，给质感不给噪点）
uniform vec3 corruption_color : source_color = vec3(0.5, 0.07, 0.05);
uniform float corruption_amount : hint_range(0.0, 1.0) = 0.0; // 缝隙腐蚀渗色

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
				   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
				   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return s / 0.875; // 归一化到 ~0..1
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float macro = fbm(world_pos * grunge_scale);          // 0..1 大块脏污
	float micro = fbm(world_pos * micro_scale);            // 细层
	// 脏污变暗：macro 低处更暗，低对比（strength 控制）
	float shade = 1.0 - grunge_strength * (1.0 - macro) - micro_strength * (1.0 - micro);
	vec3 col = base_color * clamp(shade, 0.4, 1.0);
	// 腐蚀渗色：只在最暗的缝隙渗红
	float seep = corruption_amount * (1.0 - smoothstep(0.0, 0.45, macro));
	col = mix(col, corruption_color, clamp(seep, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}
