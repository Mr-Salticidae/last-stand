extends RefCounted

# 版本号单一真源。改版本只改这里。
#
# 为什么要有这个文件：v0.8.0 发布时，版本号写死在三个互不相干的地方——
#   1. scripts/ui/atmosphere_background.gd 的 hud_bot_right @export 默认值
#   2. scenes/ui_common/atmosphere_background.tscn 里 HudBot/Right 这个 Label 的序列化 text
#   3. scenes/settings_menu.tscn 的 ProfileCard/ProfileGrid/V2
# bump 版本时三处全漏改，结果 v0.8.0 的菜单页角上印着「v0.7.0 DEMO BUILD」，
# 而且是发布之后才在截图里发现的。
#
# 现在 UI 一律在运行时从这里取，tscn 里不再留任何版本字符串。
#
# 为什么不是 autoload、也不用 class_name：
#   - autoload 不行：atmosphere_background.gd 是 @tool 脚本，在编辑器里运行时
#     autoload 单例并不存在。
#   - class_name 不行：全局类要靠编辑器扫描写进 .godot/global_script_class_cache.cfg
#     才认，在编辑器外新建的文件没有注册，headless 跑会报
#     「Identifier "GameVersion" not declared」。
# 所以消费方一律用 const GameVersion = preload("res://scripts/game_version.gd")，
# 不依赖任何缓存或单例。
const STRING: String = "1.0.0"
const DATE: String = "2026.08"

# 菜单页右下角角标
const BUILD_LABEL: String = "v" + STRING + " RELEASE"
# 设置页 ProfileCard 的版本行
const PROFILE_LABEL: String = "v" + STRING + " / " + DATE
