# 战斗科技专属图标

2026-10-24追加三枚被动芯片，现共六张正式科技图标；来源、实际尺寸和完整生成提示词见[被动芯片记录](PASSIVE-CHIPS.md)。下文为首批三项的历史制作记录。

2026-10-23，按用户提供的黑市参考图下排实体道具插画风格，使用内置 imagegen 为现有三项科技各生成一张真实透明PNG。黑色金属、硬边描线、旧化米白边缘、粉红发光与少量青色灯光；未新增科技或更改效果、价格与冷却。

| 科技 | 正式素材 | 形象 |
| --- | --- | --- |
| 异次元口袋 | [dimensional_pocket-v1.png](icons/dimensional_pocket-v1.png) | 打开后显露空间漩涡的装甲收纳袋 |
| 加速时钟 | [accelerated_clock-v1.png](icons/accelerated_clock-v1.png) | 带加速光环的机械计时器 |
| 后备能源 | [backup_energy-v1.png](icons/backup_energy-v1.png) | 带双端子与发光电量指示的备用电池 |

参考原图：`/Users/anyone/Desktop/ChatGPT 图像 2026年10月1日 18_33_52.png`，原图未修改。三图各1254×1254、RGBA透明；直接复制生成文件，未二次抠图或覆盖源图。检查数据见`artifacts/qa/technology-icons-2026-10-23/image-inspection.json`。

统一入口为`scripts/technology_icons.gd`，按稳定科技ID解析，不向战斗快照写入素材路径。商场商品和确认框、地图科技配置的已有项与携带槽、战斗科技激活卡、主菜单只读科技档案共用这三张PNG。空槽及未知／历史测试ID不套用错误图标。旧商场SVG为历史素材，已不被科技界面读取。

生成源位于`/Users/anyone/.codex/generated_images/01a16966-56dd-7202-aee0-8ba4af1de36e/`：
- 口袋：`exec-c2f34919-6522-4664-bac5-a337bb09cd32.png`
- 时钟：`exec-f52ee2b9-e28c-44f1-b659-3618aac08da4.png`
- 能源：`exec-fe8fe39d-5eb7-4465-acae-8bd52fb94ea2.png`

## 内置 imagegen 最终提示词

### dimensional_pocket

> Use case: stylized-concept. Create ONE premium illustrated cyberpunk inventory item icon for a Godot card game, square 1024x1024 canvas, REAL TRANSPARENT alpha background. The attached reference is STYLE ONLY: emulate the small physical gadget illustrations in the LOWER ROW (injector, memory chip, round jammer, battery). Hand-inked anime comic game asset, bold irregular near-black contour, angular cel-shaded chunky industrial metal, subtle scratches and worn cream edge highlights, deep navy/charcoal material with restrained hot magenta/red accents and tiny cyan indicator lights. 3/4 isometric view, readable compact silhouette, manually drawn feel, no photorealism, no plastic 3D render, no flat outline vector icon. Center isolated object, fills about 78% canvas with equal clear margins, all parts inside canvas. No card frame, no tile, no background, no shadow plane, no UI, no labels, no letters, no words, no numbers, no watermark, no extra objects. Subject: dimensional pocket technology. A compact angular tactical belt pouch / portable storage satchel, black armored shell, visible cloth side folds, magenta buckles, lid slightly open showing a contained vivid violet/magenta geometric spatial portal inside its mouth, tiny cyan edge lights. Distinctly a dimensional POCKET, not a cube or a battery. The portal stays contained inside the open pouch, no huge aura or particles. Main silhouette wider at base, one short strap loop.

### accelerated_clock

> Use case: stylized-concept. Create ONE premium illustrated cyberpunk inventory item icon for a Godot card game, square 1024x1024 canvas, REAL TRANSPARENT alpha background. The attached reference is STYLE ONLY: emulate the small physical gadget illustrations in the LOWER ROW (injector, memory chip, round jammer, battery). Hand-inked anime comic game asset, bold irregular near-black contour, angular cel-shaded chunky industrial metal, subtle scratches and worn cream edge highlights, deep navy/charcoal material with restrained hot magenta/red accents and tiny cyan indicator lights. 3/4 isometric view, readable compact silhouette, manually drawn feel, no photorealism, no plastic 3D render, no flat outline vector icon. Center isolated object, fills about 78% canvas with equal clear margins, all parts inside canvas. No card frame, no tile, no background, no shadow plane, no UI, no labels, no letters, no words, no numbers, no watermark, no extra objects. Subject: accelerated clock technology. A rugged compact futuristic pocket chronometer with clearly recognizable circular dial and two simple sharp clock hands (no digits), exposed angular dark metal rim, magenta segmented accelerator ring, one cyan glass inset and small side control knob. A couple of sharp short magenta arc strokes hug the device edge to suggest time acceleration. Distinct watch-shaped silhouette, not a floating portal.

### backup_energy

> Use case: stylized-concept. Create ONE premium illustrated cyberpunk inventory item icon for a Godot card game, square 1024x1024 canvas, REAL TRANSPARENT alpha background. The attached reference is STYLE ONLY: emulate the small physical gadget illustrations in the LOWER ROW (injector, memory chip, round jammer, battery). Hand-inked anime comic game asset, bold irregular near-black contour, angular cel-shaded chunky industrial metal, subtle scratches and worn cream edge highlights, deep navy/charcoal material with restrained hot magenta/red accents and tiny cyan indicator lights. 3/4 isometric view, readable compact silhouette, manually drawn feel, no photorealism, no plastic 3D render, no flat outline vector icon. Center isolated object, fills about 78% canvas with equal clear margins, all parts inside canvas. No card frame, no tile, no background, no shadow plane, no UI, no labels, no letters, no words, no numbers, no watermark, no extra objects. Subject: backup energy technology. A squat rectangular industrial backup power cell module, charcoal armored casing with angular ivory edge plates, two prominent metal terminals on top, black handle inset, one hot-magenta illuminated energy slit and three small cyan indicator dots, subtle red diagonal hazard paint shapes without text. Chunky physical battery pack, readable electrical power hardware, no medical plus symbol, no glowing lightning in empty space.

