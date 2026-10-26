# 市场与地点服务素材

2026-10-25首次到访对白改为标准左右独立立绘：`market`背景绑定本目录无人底图`black-market-background-v2.png`，店主立绘为原参考`卡牌游戏美术资源/角色/黑市老板.png`逐字节复制到`assets/characters/black_market_keeper.png`，保留原透明度，来源与哈希见同目录manifest。首次对白不再使用整套`black_market_art`，交易页继续沿用下方分层版本。没有生成或重绘角色。


## 地下诊所地点背景（2026-10-26）

用户提供的 clinic.png 已作为 data/assets.json 中 clinic 的地点背景接入，尺寸为 1586×992，不含透明通道。地点页、对白、战败与周结算通过既有 backgroundAssetId 和 Game.texture() 共用该纹理；资源按无损、线性 mipmap 导入，与黑市及实验室地点背景一致。本次只补背景绑定与来源记录，未修改治疗价格、剧情、界面布局或存档结构。

验证使用无窗口 Godot 4.7.2：资源绑定、纹理加载、尺寸与 mipmap 共 8 项通过，诊所付费治疗专项 87 项通过。源图已目视核对；未做窗口截图、GPU 像素或物理输入验收。
## 当前分层版本 v2（2026-10-24）

针对人物偏模糊的问题，使用内置imagegen分别制作无人背景与透明人物层，保留当前白发、金瞳、青色发饰、抬手持卡的形象，人物保持明亮。当前使用：

- `black-market-background-v2.png`：1586×992，无人物背景。
- `black-market-shopkeeper-layer-v2.png`：1086×1448、真实RGBA透明人物，独立显示在(30,139)，尺寸540×720；每逻辑像素约有2×2原生像素。
- 前景柜台：由`black_market_art.gd`使用背景同一纹理和匹配UV的多边形遮挡，不另行重画柜台，保留屏幕、杯子与柜台的前后关系。

运行时由`black_market.gd`加载`black_market_art.gd`，顺序为无人背景→透明人物→柜台→原有HUD／商品界面。素材按无损导入，线性采样，无全局压暗，不使用模糊滤镜；缺少分层素材时回退v1。旧图及用户原始立绘保留。

生成来源分别为`exec-14969282-18b9-45fd-a3e4-cef845a8a8c6.png`和`exec-2df641cc-af4d-4c2f-b5c4-5aefeb2a4a87.png`，正式副本已在本目录；完整实际提示词见[layers-v2-prompts.json](layers-v2-prompts.json)。工具没有按提示输出1536×2048，记录以上实际尺寸，不把普通放大当作新增细节。无人背景移除了旧人物，人物表情／手部属依据原图重绘，并非原图像素直接抠出。

本轮导入无脚本错误，界面专项103项通过，覆盖独立层、原生像素余量、透明通道、柜台层级与交易回归。浏览器布局预览已目视核对，不是Godot运行截图；真实屏幕清晰度、不同窗口尺寸及物理输入仍待验收。用户最终美术认可尚未取得。

## v1 历史来源与回退

2026-10-23后续调整：角色和环境按源图亮度直接显示，移除全屏暗色与纵向渐暗遮罩；老板底部对白框和成交对白已删除，右侧商品区仍有独立深色底板。

2026-10-23，使用内置 imagegen 生成并接入桌面工程。`black-market-shop-v1.png`是老板与环境同层的背景插画；真实卡面、九货位、回收区、HUD、价格与文字由Godot绘制。

- 角色参考：工作区`卡牌游戏美术资源/角色/黑市老板.png`，保留白发、金瞳、青色三角发饰、黑／酒红外套与白衬衣；原图未修改。
- 风格／构图参考：用户提供的`ChatGPT 图像 2026年10月1日 18_33_52.png`；只参考街巷、柜台与霓虹漫画画法。
- 运行绑定：`data/assets.json`的`black_market_shop`，由`black_market.gd`加载。未替换普通地点背景`market`的历史占位项。
- 生成源：`/Users/anyone/.codex/generated_images/01a16948-cca1-7420-bd4c-615229755069/exec-8f8db2f3-614a-46a8-967f-3acee4971c7b.png`；正式工程保存独立副本，不依赖该外部路径。
- 状态：已做插画目视检查、导入和无窗口节点／交易检查；布局预览在工作区`output/黑市界面/`，不是Godot运行截图；尚未做实际Godot像素与物理输入验收，也未获得用户最终美术认可。

最终提示词（原文）：

> Create a production 16:10 landscape background illustration for a playable Godot black-market card shop interface, 1536x960 or similar wide landscape. Image 1 is the EXACT shopkeeper character identity reference: long straight ivory white hair, golden amber eyes, black/deep burgundy angular jacket with magenta red trim, white shirt, black gloves, distinctive cyan triangular hair ornament, no hat, no glasses. Preserve her recognizable design and angular ink drawing. Image 2 is ONLY environment style and composition reference. Hand-drawn anime cyberpunk comic art, bold irregular black ink outlines, hard cel shadows, scratchy dark navy/purple metal, restrained hot-pink and cyan neon. Composition: LEFT 27 percent contains this white-haired shopkeeper shown waist-up, smiling with knowing confidence, behind a cluttered dark metal counter, one black-gloved hand holding a small glowing cyan card, face around x=16%, y=36%, head entirely below y=19%. Some holographic terminals low on left and draped cables high on left. RIGHT 70 percent: dim quiet broad empty merchandise display area on two dark horizontal counter tiers, suitable for programmatically overlaying 5 real vertical cards per row (nine sale cards and one sell slot), no cards drawn, no outlined empty card placeholders, no interface panels. Right area behind cards must stay dark and low-detail so real UI remains readable. Background includes industrial black-market alley, distant neon windows, metal beams, overhead cables. Top 9 percent stays dark and quiet for real HUD, below that a dark empty hanging sign on the left for real title text. Bottom 8 percent quiet counter edge for real navigation. NO text, NO letters, NO HUD, NO numbers, NO logos, NO cards, NO buttons, NO other people. This is the environment+shopkeeper layer only, cards and all text added by the game.
