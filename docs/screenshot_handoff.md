# 截图交接单 — 《LastStand 从 0 到发布制作教程》配图

> **交接对象**：Claude 桌面应用（或任何能操作本机 Windows 桌面的接手方）
> **交接方**：Claude Code @ `e:\last-stand`
> **状态**：教程正文已完成，缺 5 张操作过程截图（S1–S5）
> **本文档自足**，不需要上游对话上下文即可执行。

---

## 0. 一句话任务

在 Godot 编辑器和浏览器里补拍 **5 张操作过程截图**，存到 `e:\last-stand\assets\screenshots\tutorial\`，然后把 [zero_to_release.md](zero_to_release.md) 里对应的 5 处「📷 待补截图」占位块替换成图片引用。

---

## 1. 背景

[docs/zero_to_release.md](zero_to_release.md) 是一份讲「一个人用 Godot 做完一款 FPS 并发布到 GitHub + itch.io」的教程，体例是四段式：成品展示 → 所用工具 → 操作方法 → 总结与错误示范。

正文、代码块、检查清单都已写完并核对过真实数据。**唯独缺"操作过程截图"**——就是那种手把手教程里"这个按钮在这儿、这个面板长这样"的图。成品截图（游戏画面、itch 上架页、hitbox 可视化）已经有了，不用管。

---

## 2. 环境前提

| 项 | 值 |
|---|---|
| 项目路径 | `e:\last-stand` |
| Godot 可执行文件 | `d:\Godot\Godot_v4.7.1-stable_win64.exe` |
| 编辑器语言 | **简体中文**（菜单是「场景 / 项目 / 调试 / 编辑器 / 帮助」） |
| 截图保存目录 | `e:\last-stand\assets\screenshots\tutorial\`（已建好） |
| GitHub 仓库 | https://github.com/Mr-Salticidae/last-stand |

**开始前先把编辑器打开**（S1–S5 都要用）：

```powershell
Start-Process "d:\Godot\Godot_v4.7.1-stable_win64.exe" -ArgumentList '--path','e:\last-stand','--editor'
```

首次打开会导入资源，等文件系统面板加载完再截图。

> ⚠️ Godot 会为新加入的 png 自动生成 `.import` 元数据文件。**这是正常的，要一起提交**，不要删。

---

## 3. 统一规范

**格式与尺寸**

- 格式：PNG
- 全窗口截图：宽 **1920**（与仓库现有截图一致），不要缩放后再放大
- 面板局部裁剪：按内容实际大小裁，宽度不低于 320
- 不加边框、不加阴影、不打水印、不画箭头标注（正文用文字说明位置）

**内容要求**

- Godot 编辑器保持**默认深色主题**，不要改配色
- 截图前把无关面板收起，让目标区域占画面主体
- 中文界面，不要切英文（正文里的菜单路径是中文写的）

**隐私红线**（这份文档会进公开仓库）

- ❌ 不要拍到桌面其他窗口、任务栏通知、聊天软件
- ❌ 不要拍到浏览器的书签栏、其他标签页、登录邮箱
- ❌ 不要拍到本机除 `e:\last-stand` 和 `d:\Godot` 以外的绝对路径
- ✅ GitHub / itch.io 的公开页面内容可以拍（用户名 `Mr-Salticidae` 本来就是公开的）

---

## 4. 待拍清单

### S1 — Autoload 全局单例面板

- **文件名**：`s1_autoload.png`
- **操作路径**：菜单 **项目 → 项目设置 → 全局（Autoload）** 标签页
- **必须可见**：四个单例的名称与路径全部在画面内
  - `Settings` → `res://scripts/settings.gd`
  - `AudioManager` → `res://scripts/audio_manager.gd`
  - `UpgradeManager` → `res://scripts/upgrade_manager.gd`
  - `SynergyManager` → `res://scripts/synergy_manager.gd`
- **构图**：截整个项目设置对话框即可，确保「全局」标签处于选中态

### S2 — 文件系统面板目录结构

- **文件名**：`s2_filesystem.png`
- **操作路径**：编辑器左下「文件系统」面板
- **必须可见**：`res://` 下五个顶层目录，**各展开一层**
  - `assets/` `docs/` `scenes/` `scripts/` `tools/`
- **构图**：只裁文件系统面板（参考已有的 `assets/screenshots/部分文件树.png`，竖长条形）
- ⚠️ **这张是替换过期图**：现有的 `部分文件树.png` 里有个 `design_drops/` 目录，早在仓库瘦身时删掉了，不能再用

### S3 — 检查器里的 @export 分组

- **文件名**：`s3_inspector_export.png`
- **操作路径**：打开任意一张地图场景（如 `scenes/world_training.tscn`）→ 在场景树里选中 **WaveManager** 节点 → 看右侧检查器
- **必须可见**：至少三个 `@export_group` 分组标题及其下的参数
  - `Wave Scaling`（含 `Base Enemy Count = 4`、`Max Enemies Per Wave = 20`）
  - `Timing`
  - `Victory`（含 `Victory Wave = 30`）
- **构图**：裁检查器面板即可，不用带整个编辑器
- **意图**：这张图要让读者看懂"难度参数不用改代码，在编辑器里就能调"

### S4 — 导出对话框

- **文件名**：`s4_export_dialog.png`
- **操作路径**：菜单 **项目 → 导出**
- **必须可见**：
  - 左侧预设列表里 **Windows Desktop** 处于选中态
  - 右侧的导出路径（应为 `../LastStand-v0.7.0-windows.zip` 一类）
  - 架构 `x86_64`
- **构图**：截整个导出对话框
- ⚠️ **只截图，不要真的点「导出项目」**——不需要产出构建文件

### S5 — GitHub Release 页面

- **文件名**：`s5_github_release.png`
- **操作路径**：浏览器打开 https://github.com/Mr-Salticidae/last-stand/releases/tag/v0.7.0
- **必须可见**：tag 名 `v0.7.0`、更新日志正文、底部的附件（zip）
- **构图**：浏览器窗口，**书签栏和其他标签页要隐藏**（按 F11 全屏，或截图后裁掉顶部）
- 💡 页面很长，截到能看见附件区就行，不用完整长截图

---

## 5. 拍完怎么回填

打开 [zero_to_release.md](zero_to_release.md)，找到 6 处形如下面的占位块（每处两行，以 `> 📷` 开头）：

```markdown
> 📷 **待补截图 S1** → `assets/screenshots/tutorial/s1_autoload.png`
> 内容：项目设置的「全局/Autoload」标签页，四个单例全部可见。详见 [截图交接单](screenshot_handoff.md)。
```

**整块替换成**图片引用（注意路径前缀是 `../`，因为文档在 `docs/` 下）：

```markdown
![Autoload 全局单例面板](../assets/screenshots/tutorial/s1_autoload.png)
```

五处的替换文本对照：

| 占位 | 替换为 |
|---|---|
| S1 | `![Autoload 全局单例面板](../assets/screenshots/tutorial/s1_autoload.png)` |
| S2 | `![文件系统目录结构](../assets/screenshots/tutorial/s2_filesystem.png)` |
| S3 | `![检查器中的 @export 分组](../assets/screenshots/tutorial/s3_inspector_export.png)` |
| S4 | `![导出对话框](../assets/screenshots/tutorial/s4_export_dialog.png)` |
| S5 | `![GitHub Release 页面](../assets/screenshots/tutorial/s5_github_release.png)` |

---

## 6. 验收清单

```
□ 5 个 png 全部落在 assets/screenshots/tutorial/，文件名与上表完全一致
□ 每张图的「必须可见」项逐条核对过
□ zero_to_release.md 里 5 处 "📷 待补截图" 占位块已全部替换，全文搜不到 "待补截图"
□ 图片路径前缀是 ../，在 GitHub 上能正常渲染（可用 VSCode 的 Markdown 预览验证）
□ 隐私红线逐条过一遍：无第三方窗口、无书签栏、无无关绝对路径
□ Godot 生成的 .import 文件一并保留
□ 过期的 assets/screenshots/部分文件树.png 已被 S2 取代（旧文件删不删由用户决定，别擅自删）
```

---

## 7. 边界：不要做的事

- **不要改教程正文的文字内容**。数字（87 个提交、10048 行、55 个脚本等）都是从仓库实测出来的，改了会失真。只动占位块。
- **不要真的执行导出、发版、推送**。S4 只截图，S5 只看现有页面。
- **不要 git commit / push**。改完告诉用户，由用户决定何时提交。
- **不要新增截图**。清单是 5 张，多拍的图不会被引用。
- **不要去拍"敌人精灵帧文件夹"**。教程 三.4 讲了 `walk_0.png` 那套帧目录约定，但**仓库里目前一个帧文件夹都没有**——`assets/sprites/enemies/` 只有 4 张单图，帧动画系统已在 `enemy.gd` 落地但美术还没画。正文已如实说明这点，不需要配图。
- **不要动 `assets/screenshots/` 下的现有文件**。`godot展示.png`、`itch上架首页.png`、`碰撞.png` 已在正文中被引用。

---

## 附：已在正文中使用、不用重拍的图

| 文件 | 用在哪 | 说明 |
|---|---|---|
| `banner.png` | 一、成品展示 | 项目 key art |
| `assets/screenshots/上传itch/01_menu.png` | 一、成品展示 | 主菜单 |
| `assets/screenshots/上传itch/02_combat.png` | 一、成品展示 | 战斗画面 |
| `assets/screenshots/上传itch/04_update.png` | 一、成品展示 | 升级三选一 |
| `assets/screenshots/godot展示.png` | 二、所用工具 1 | 编辑器四区域全景 |
| `assets/screenshots/itch上架首页.png` | 三、操作方法 6 | itch.io 上架页 |
| `assets/screenshots/碰撞.png` | 四、错误示范 ① | hitbox 运行时可视化，**历史存档，不可替换** |

---

## 附：接手方没有截屏能力时

如果你（接手方）无法直接操作桌面截图，**不要跳过或伪造**。改为：

1. 把第 4 节的 6 条规格逐条转述给用户，一次给一条，等对方拍完再给下一条
2. 用户把图存好后，你负责按第 5 节做回填、按第 6 节做验收
3. 收到图后**逐条核对「必须可见」项**——拍漏了要说出来，让对方重拍
