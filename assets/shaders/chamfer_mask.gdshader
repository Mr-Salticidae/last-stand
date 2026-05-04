shader_type canvas_item;

// 给 _draw 自绘 Control（如 LevelThumbnail）做 chamfer 切角 mask：
// chamfer 切角"外"区域 fragment discard，让下层（LevelCard 切角处的 atmosphere）显示出来。
//
// 用 uniform control_size 把 UV (0..1) 转成像素，因为 chamfer_size 是 px 不变量。
// 只 discard 顶部 2 个角（thumb 一般不接触 LevelCard 底部 chamfer，省 2 个判断）。

uniform float chamfer_size : hint_range(0.0, 50.0) = 14.0;
uniform vec2 control_size = vec2(526.0, 330.0);

void fragment() {
	vec2 p = UV * control_size;
	// top-left
	if (p.x + p.y < chamfer_size) discard;
	// top-right
	if ((control_size.x - p.x) + p.y < chamfer_size) discard;
}
