# 黑市店铺插画 v1

2026-10-23后续调整：角色和环境按源图亮度直接显示，移除全屏暗色与纵向渐暗遮罩；老板底部对白框和成交对白已删除，右侧商品区仍有独立深色底板。

2026-10-23，使用内置 imagegen 生成并接入桌面工程。`black-market-shop-v1.png`是老板与环境同层的背景插画；真实卡面、九货位、回收区、HUD、价格与文字由Godot绘制。

- 角色参考：工作区`卡牌游戏美术资源/角色/黑市老板.png`，保留白发、金瞳、青色三角发饰、黑／酒红外套与白衬衣；原图未修改。
- 风格／构图参考：用户提供的`ChatGPT 图像 2026年10月1日 18_33_52.png`；只参考街巷、柜台与霓虹漫画画法。
- 运行绑定：`data/assets.json`的`black_market_shop`，由`black_market.gd`加载。未替换普通地点背景`market`的历史占位项。
- 生成源：`/Users/anyone/.codex/generated_images/01a16948-cca1-7420-bd4c-615229755069/exec-8f8db2f3-614a-46a8-967f-3acee4971c7b.png`；正式工程保存独立副本，不依赖该外部路径。
- 状态：已做插画目视检查、导入和无窗口节点／交易检查；布局预览在工作区`output/黑市界面/`，不是Godot运行截图；尚未做实际Godot像素与物理输入验收，也未获得用户最终美术认可。

最终提示词（原文）：

> Create a production 16:10 landscape background illustration for a playable Godot black-market card shop interface, 1536x960 or similar wide landscape. Image 1 is the EXACT shopkeeper character identity reference: long straight ivory white hair, golden amber eyes, black/deep burgundy angular jacket with magenta red trim, white shirt, black gloves, distinctive cyan triangular hair ornament, no hat, no glasses. Preserve her recognizable design and angular ink drawing. Image 2 is ONLY environment style and composition reference. Hand-drawn anime cyberpunk comic art, bold irregular black ink outlines, hard cel shadows, scratchy dark navy/purple metal, restrained hot-pink and cyan neon. Composition: LEFT 27 percent contains this white-haired shopkeeper shown waist-up, smiling with knowing confidence, behind a cluttered dark metal counter, one black-gloved hand holding a small glowing cyan card, face around x=16%, y=36%, head entirely below y=19%. Some holographic terminals low on left and draped cables high on left. RIGHT 70 percent: dim quiet broad empty merchandise display area on two dark horizontal counter tiers, suitable for programmatically overlaying 5 real vertical cards per row (nine sale cards and one sell slot), no cards drawn, no outlined empty card placeholders, no interface panels. Right area behind cards must stay dark and low-detail so real UI remains readable. Background includes industrial black-market alley, distant neon windows, metal beams, overhead cables. Top 9 percent stays dark and quiet for real HUD, below that a dark empty hanging sign on the left for real title text. Bottom 8 percent quiet counter edge for real navigation. NO text, NO letters, NO HUD, NO numbers, NO logos, NO cards, NO buttons, NO other people. This is the environment+shopkeeper layer only, cards and all text added by the game.
