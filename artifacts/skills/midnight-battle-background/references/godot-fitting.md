# 后巷实例与 Godot 试装

以下是 2026-10-18 的已确认实例，不是所有地图的固定参数。
工程通常在 D:/Major Project/game-demo；确认当前工作区，路径不存在时查找当前工程，
不重建旧资料目录。下面的文件与验证结果属于历史，使用前核对当前版本。

## 入口与资源

- 独立场景：tests/battle_background_preview.tscn；编辑器 F6 单独运行，Tab 显隐工具。
- 实现：tests/battle_background_preview.gd、battle_background_preview_view.gd。
- 卡牌试装：tests/battle_background_preview_card.gd。
- 检查入口：tests/battle_background_preview_check.tscn。
- 样图：tests/fixtures/battle_background/alley_sample_v4_detail.png。
- 来源与参数：tests/fixtures/battle_background/source.json。
- 提示词：artifacts/qa/alley-detail-2026-10-18/imagegen-prompts.txt。
- 实机参照：artifacts/qa/alley-fit-hand-2026-10-18/1600-fixed/06-three-wide.png。
- 选中卡牌参照：同目录 11-hand-selected.png。

其他地点不要直接覆盖后巷默认图。按本批次范围保存各地点素材和参数；
需要切换样图时优先扩展测试入口的地点选择，不创建无关的正式路由。

## 确认参数

| 参数 | 后巷实例值 |
| --- | --- |
| 背景比例 | 0.53 |
| 水平偏移 | 0 |
| 垂直偏移 | -61 |
| 亮度 | 1.05 |
| 饱和度 | 1.15 |
| 对比度 | 0.92，枢轴 0.25 |
| 底部渐暗起点 | 610 |
| 底部渐暗强度 | 0.94 |

原图背景／地面约 46／54；试装基准也按顶部 HUD 下方裁剪区的 46／54 放置。
最终 Y=-61 将墙脚上移，最终可见比例不再是精确 46／54。
滑条沿用 REFERENCE_SPAN_RATIO=0.50 的近似校准，不表示画布只覆盖屏幕 53%。
生成门窗大小是近似视觉匹配，不能声称与旧图逐像素一致。

镜头保险为左右各 512、上下各 256 源像素镜像区域。最右攻击近景可能出现重复
招牌和纹理，必须诚实标注。新地点优先生成真实延伸，不把镜像作为最终美术标准。

用户曾要求仅在 tests 中将待选手牌上移 60 逻辑像素（900 高逻辑画布）；
悬停仍为原 home 上方 140，选中仍为原 home 上方 150，终态缩放 1.12、转角 0。
制作新背景不需要再次改变这些值。

## 接入与验证

保留角色脚底位置、真实镜头、固定 HUD 和输入；背景在人物后方并随战场镜头移动。
区分背景裁剪区域和战斗逻辑区域，不能因改战场尺寸影响站位、目标命中和镜头计算。
分别观察单敌、三敌、近景、最远目标攻击与归位。

试装禁用保存，直接保存函数使用测试路径。Godot 自动加载发生在场景根节点之前，
不能仅凭根节点关闭保存就声称没有读取用户文件。
QA 隔离 APPDATA / LOCALAPPDATA，图形输入验证顺序执行。

Godot 路径从 tools/local_paths.json 或当前配置读取。
Windows 使用 Start-Process -WindowStyle Hidden -Wait -PassThru，保留 stdout/stderr；
不把引擎启动标题当作运行完成。支持 --output-dir 的检查写入新证据目录，保留失败记录。
音频设备不可用时图形专项可用 Dummy 音频驱动，并明确不验收声音。

历史最终两尺寸各 96 项通过，不代表新图已验证。新地点按改动选择检查，
报告本轮结果、截图和限制；不能运行 Godot 时记录“素材已生成，实机未验证”。

## 批次最小记录

每地点记录：地点 ID、参考路径与用途、比例及计算区域、角色参照、输出文件和 SHA256、
生成器、完整提示词路径、源图实际分界、试装参数、镜头余量方式、截图、运行命令和结果、
状态及遗留问题。

用批次 JSON 加地点参数或已有项目清单即可，不要求新架构。
只有用户实际确认后才能标记“用户已确认”。
