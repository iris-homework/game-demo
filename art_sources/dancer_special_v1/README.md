# 灵魂链接特殊卡面 v1

已接入 game-demo 的两张局内专用卡：`灵魂链接 黑`、`灵魂链接 白`，均为1费，实际类型为`special`（特殊），无C/B/A/S稀有度。右上圆章中的“黑／白”仅标识变体，规则仍为移除对方舞者1层灵魂连接，打出后消耗，移出本场抽弃牌循环。

使用原40张无人物卡面的1086×1448几何、费用位置、96号原生粗黑标题字、宋体规则字和斜切插画窗口。子模板`neon-comic-special-v1`为黑／白采用石墨／象牙白配色，类型牌标“特殊”。

- 成品：[黑卡](../../assets/cards/dancer_special_v1/dancer_black_card.png)、[白卡](../../assets/cards/dancer_special_v1/dancer_white_card.png)。
- 预览：[362宽双卡](previews/preview_large.png)、[173宽手牌双卡](previews/preview_hand.png)。这些是PNG布局预览，不是引擎截图。
- 生成：内置`image_gen`只生成无字插画；完整提示词、参考文件及哈希见[prompts.json](prompts.json)。黑卡引用原`noren_24`画风；白卡同时引用原样板与黑卡插画匹配成对构图，未用新图替代原样板。
- 排版：[确定性渲染器](../../tools/card_art/render_dancer_special.py)从当前专用卡JSON排入所有文字及卡框。插画保留原始字节，合成时只按固定窗口等比缩放、裁切。
- 字体：标题Noto Sans CJK SC Bold原文件及许可／来源在`fonts/`；规则使用工程原Noto Serif CJK SC Bold。字体不依赖操作系统安装。
- [成品及依赖清单](../../assets/cards/dancer_special_v1/manifest.json)、[本版目视记录](acceptance.json)。当前修订的两张原尺寸及173宽预览已检查，362宽预览已生成；没有文字溢出、主体／类型关键内容遮挡，卡面边缘透明、内部不透明。
- 用户最终认可仍为pending；已按本次制作任务接入，不把程序加载或制作者目视检查等同于用户认可。

重建（仓库根目录，需Python与Pillow）：

```sh
python3 tools/card_art/render_dancer_special.py
```

运行映射为`data/cards/card_faces_special.json`，与原40张映射分开；只在冻结定义逐字段匹配时使用。旧“黑卡／白卡”技能版快照继续原定义和文字回退。本目录有`.gdignore`，源插画／字体和预览不参与Godot资源导入；正式PNG已启用mipmap。
