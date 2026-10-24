# Balatro音效对照与分类

这份表帮助你从75个候选中选择声音：先看原名与原游戏调用用途，再试听分类副本。
“建议用途”是为《午夜委托》提出的安排，全部待用户试听、正式未接入。
2026-10-25已接入[音效测试台](音效测试台使用说明.md)，可在正式场景模拟中试听与绑定。

整理日期：2026-10-24（Asia/Shanghai）。按用户选择分入总分类目录，保留下载目录原件。

## 找到的说明与核查边界

本地提取包只有75个OGG，没有附带README、用途表或许可文本。
[社区下载页](https://sounds.spriters-resource.com/pc_computer/balatro/asset/452647/)也只列文件名，没有逐声音用途说明。
本轮使用社区公开的原游戏调用代码、Steamodded维护者的版本音效配置交叉核对，
据此编写本中文对照；未找到原作者提供的完整对应手册。
社区代码版本与这份提取包的原游戏版本未逐字比对，证据用于确认已见到的调用场景，
不代表某声音只用于那一个场景。

- `paper1`用于卡牌悬停，`cardSlide1`用于选中，`cardSlide2`用于取消选中。
- `voice1`至`voice11`用于角色说话时随机播放，可优先试听作对话短音。
- `highlight1/2`用于通知、结算或阶段变化；按实际调用归类。
- `multhit1/2`表示加倍率／乘倍率反馈，不能按名字直接当作怪物多段攻击声。
- `card3`、长揉皱声、部分coin变体及少数效果未定位具体调用，保留待确认标记。

## 存放结果

分类副本统一加`balatro`来源标识，遵循小写英文、下划线、两位序号；OGG字节保持原样。
下表数量只计分类副本；另有75份原名备份。

| 分类 | 数量 | 工程内目录 |
| --- | --- | --- |
| 按钮与刷新 | 3 | [incoming/ui/](../assets/audio/incoming/ui/) |
| 卡牌与消耗牌效果 | 30 | [incoming/cards/](../assets/audio/incoming/cards/) |
| 角色说话短音 | 11 | [incoming/dialogue/](../assets/audio/incoming/dialogue/) |
| 结算、奖励、通知与转场 | 18 | [incoming/world/](../assets/audio/incoming/world/) |
| 通用效果候选 | 9 | [incoming/combat/](../assets/audio/incoming/combat/) |
| 环境混音层 | 4 | [incoming/ambience/](../assets/audio/incoming/ambience/) |

原名原件和来源记录放在[balatro_452647原件目录](../assets/audio/incoming/_originals/balatro_452647/)。
逐文件哈希、音频头参数、候选状态与证据链接见[完整清单JSON](../assets/audio/incoming/_originals/balatro_452647/manifest.json)。
已有`dialogue/text-blip-14855.mp3`继续保留，未被覆盖或重新分类。

## 优先试听

先试听下列文件，最贴近当前操作反馈缺口。选定后再配置播放时点、音量和重复间隔。

| 用途 | 候选 |
| --- | --- |
| 按钮点击 | [ui_click_balatro_01.ogg](../assets/audio/incoming/ui/ui_click_balatro_01.ogg) |
| 卡牌悬停 | [card_hover_balatro_01.ogg](../assets/audio/incoming/cards/card_hover_balatro_01.ogg) |
| 点击选中 | [card_select_balatro_01.ogg](../assets/audio/incoming/cards/card_select_balatro_01.ogg) |
| 取消选中 | [card_deselect_balatro_01.ogg](../assets/audio/incoming/cards/card_deselect_balatro_01.ogg) |
| 抽牌／出牌 | [card_draw_balatro_01.ogg](../assets/audio/incoming/cards/card_draw_balatro_01.ogg) |
| 对话短音 | [dialogue_blip_balatro_01.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_01.ogg)，其余10份在同目录比较 |
| 信用点到账 | [credits_coin_balatro_01.ogg](../assets/audio/incoming/world/credits_coin_balatro_01.ogg) |
| 胜利 | [victory_balatro_01.ogg](../assets/audio/incoming/world/victory_balatro_01.ogg) |

## 按钮与刷新

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `button.ogg` | 界面按钮点击；也用于部分数字更新 | 通用按钮点击 | [ui_click_balatro_01.ogg](../assets/audio/incoming/ui/ui_click_balatro_01.ogg) | 0.500 | [调用1](https://github.com/futouyiba/cardLua/blob/main/engine/ui.lua#L989) |
| `cancel.ogg` | 取消／负面反馈；结算未达标与盲注变化也复用 | 取消、返回或拒绝提示候选 | [ui_cancel_balatro_01.ogg](../assets/audio/incoming/ui/ui_cancel_balatro_01.ogg) | 0.485 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L810)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L3213) |
| `other1.ogg` | 商店刷新、重掷Boss时触发 | 界面刷新提示候选 | [ui_refresh_balatro_01.ogg](../assets/audio/incoming/ui/ui_refresh_balatro_01.ogg) | 0.518 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L2764)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L2836) |

## 卡牌与消耗牌效果

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `paper1.ogg` | 卡牌悬停；手牌排序和文字逐字也复用 | 优先试听：卡牌悬停 | [card_hover_balatro_01.ogg](../assets/audio/incoming/cards/card_hover_balatro_01.ogg) | 0.065 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L4303)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L38)、[调用3](https://github.com/futouyiba/cardLua/blob/main/engine/text.lua#L201) |
| `cardSlide1.ogg` | 卡牌加入高亮选中区 | 优先试听：按下选中卡牌 | [card_select_balatro_01.ogg](../assets/audio/incoming/cards/card_select_balatro_01.ogg) | 0.449 | [调用1](https://github.com/futouyiba/cardLua/blob/main/cardarea.lua#L140) |
| `cardSlide2.ogg` | 再次点击已选卡牌、取消高亮 | 取消选牌 | [card_deselect_balatro_01.ogg](../assets/audio/incoming/cards/card_deselect_balatro_01.ogg) | 0.356 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L4607) |
| `card1.ogg` | 抽／移动卡牌、翻牌等多个卡牌动作共用 | 抽牌、成功出牌的候选 | [card_draw_balatro_01.ogg](../assets/audio/incoming/cards/card_draw_balatro_01.ogg) | 0.651 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L416)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1107) |
| `card3.ogg` | 本轮调用资料未定位到具体触发 | 通用卡牌动作候选，先试听再定用途 | [card_action_balatro_03.ogg](../assets/audio/incoming/cards/card_action_balatro_03.ogg) | 0.498 | 原触发待确认 |
| `cardFan2.ogg` | 出牌区状态文字、商店／回合结算展示、页面遮罩 | 展开卡牌、洗牌或面板展开候选；尚未认可 | [card_fan_balatro_02.ogg](../assets/audio/incoming/cards/card_fan_balatro_02.ogg) | 0.766 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L457)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L3024)、[调用3](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L3077) |
| `crumple1.ogg` | 卡牌溶解、生成，以及菜单转换时随机使用 | 弃牌或消耗牌的揉皱质感候选 | [card_crumple_balatro_01.ogg](../assets/audio/incoming/cards/card_crumple_balatro_01.ogg) | 0.743 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212) |
| `crumple2.ogg` | 卡牌溶解、生成，以及菜单转换时随机使用 | 弃牌或消耗牌的揉皱质感候选 | [card_crumple_balatro_02.ogg](../assets/audio/incoming/cards/card_crumple_balatro_02.ogg) | 0.743 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212) |
| `crumple3.ogg` | 卡牌溶解、生成，以及菜单转换时随机使用 | 弃牌或消耗牌的揉皱质感候选 | [card_crumple_balatro_03.ogg](../assets/audio/incoming/cards/card_crumple_balatro_03.ogg) | 0.743 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212) |
| `crumple4.ogg` | 卡牌溶解、生成，以及菜单转换时随机使用 | 弃牌或消耗牌的揉皱质感候选 | [card_crumple_balatro_04.ogg](../assets/audio/incoming/cards/card_crumple_balatro_04.ogg) | 0.743 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212) |
| `crumple5.ogg` | 卡牌溶解、生成，以及菜单转换时随机使用 | 弃牌或消耗牌的揉皱质感候选 | [card_crumple_balatro_05.ogg](../assets/audio/incoming/cards/card_crumple_balatro_05.ogg) | 0.743 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212) |
| `crumpleLong1.ogg` | 文件名表示长揉皱声；本轮未定位具体触发 | 较长的卡牌消散／转场候选 | [card_crumple_long_balatro_01.ogg](../assets/audio/incoming/cards/card_crumple_long_balatro_01.ogg) | 3.959 | 原触发待确认 |
| `crumpleLong2.ogg` | 文件名表示长揉皱声；本轮未定位具体触发 | 较长的卡牌消散／转场候选 | [card_crumple_long_balatro_02.ogg](../assets/audio/incoming/cards/card_crumple_long_balatro_02.ogg) | 3.959 | 原触发待确认 |
| `magic_crumple.ogg` | 启动画面与菜单进入／转换的魔法揉皱效果 | 消耗牌溶解、稀有卡出现候选 | [card_magic_crumple_balatro_01.ogg](../assets/audio/incoming/cards/card_magic_crumple_balatro_01.ogg) | 6.385 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1390)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1579) |
| `magic_crumple2.ogg` | 启动画面与菜单进入／转换的魔法揉皱效果 | 消耗牌溶解、稀有卡出现候选 | [card_magic_crumple_balatro_02.ogg](../assets/audio/incoming/cards/card_magic_crumple_balatro_02.ogg) | 2.493 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1390)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1579) |
| `magic_crumple3.ogg` | 启动画面与菜单进入／转换的魔法揉皱效果 | 消耗牌溶解、稀有卡出现候选 | [card_magic_crumple_balatro_03.ogg](../assets/audio/incoming/cards/card_magic_crumple_balatro_03.ogg) | 1.567 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1390)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1579) |
| `glass1.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_01.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_01.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `glass2.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_02.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_02.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `glass3.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_03.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_03.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `glass4.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_04.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_04.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `glass5.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_05.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_05.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `glass6.ogg` | 玻璃牌碎裂时随机选取 | 卡牌破碎或科技碎裂效果候选 | [card_glass_shatter_balatro_06.ogg](../assets/audio/incoming/cards/card_glass_shatter_balatro_06.ogg) | 0.746 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2103) |
| `foil1.ogg` | 闪箔版本应用；解锁提示也复用 | 奖励卡或能力生效候选 | [card_foil_apply_balatro_01.ogg](../assets/audio/incoming/cards/card_foil_apply_balatro_01.ogg) | 0.655 | [调用1](https://github.com/Steamodded/smods/blob/main/src/game_object.lua#L3581)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L438) |
| `foil2.ogg` | 版本效果结算与通知提示 | 奖励、能力触发提示候选 | [card_foil_trigger_balatro_02.ogg](../assets/audio/incoming/cards/card_foil_trigger_balatro_02.ogg) | 0.655 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L854)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L1809) |
| `holo1.ogg` | 镭射版本应用；部分特殊效果复用 | 能力生效或科技激活候选 | [card_holo_apply_balatro_01.ogg](../assets/audio/incoming/cards/card_holo_apply_balatro_01.ogg) | 1.116 | [调用1](https://github.com/Steamodded/smods/blob/main/src/game_object.lua#L3581)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L439) |
| `polychrome1.ogg` | 多彩版本应用 | 较强的奖励卡或科技效果候选 | [card_polychrome_apply_balatro_01.ogg](../assets/audio/incoming/cards/card_polychrome_apply_balatro_01.ogg) | 1.541 | [调用1](https://github.com/Steamodded/smods/blob/main/src/game_object.lua#L3581)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L440) |
| `negative.ogg` | 负片版本应用；战败界面降调复用 | 负面状态或战败候选；不是专用错误按钮声 | [card_negative_apply_balatro_01.ogg](../assets/audio/incoming/cards/card_negative_apply_balatro_01.ogg) | 1.086 | [调用1](https://github.com/Steamodded/smods/blob/main/src/game_object.lua#L3581)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L3525) |
| `gold_seal.ogg` | 卡牌添加蜡封；盲注设置也复用 | 奖励卡、科技装配提示候选 | [card_seal_apply_balatro_01.ogg](../assets/audio/incoming/cards/card_seal_apply_balatro_01.ogg) | 0.543 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L470) |
| `tarot1.ogg` | 消耗牌效果与牌型变化；tarot2也用于无法执行提示 | 技能／能力、错误提示候选；需按听感选择 | [card_tarot_effect_balatro_01.ogg](../assets/audio/incoming/cards/card_tarot_effect_balatro_01.ogg) | 0.339 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1102)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L281)、[调用3](https://github.com/futouyiba/cardLua/blob/main/functions/state_events.lua#L492) |
| `tarot2.ogg` | 消耗牌效果与牌型变化；tarot2也用于无法执行提示 | 技能／能力、错误提示候选；需按听感选择 | [card_tarot_effect_balatro_02.ogg](../assets/audio/incoming/cards/card_tarot_effect_balatro_02.ogg) | 0.454 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1102)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L281)、[调用3](https://github.com/futouyiba/cardLua/blob/main/functions/state_events.lua#L492) |

## 角色说话短音

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `voice1.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_01.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_01.ogg) | 0.171 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice2.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_02.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_02.ogg) | 0.171 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice3.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_03.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_03.ogg) | 0.171 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice4.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_04.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_04.ogg) | 0.171 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice5.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_05.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_05.ogg) | 0.174 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice6.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_06.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_06.ogg) | 0.176 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice7.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_07.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_07.ogg) | 0.177 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice8.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_08.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_08.ogg) | 0.174 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice9.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_09.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_09.ogg) | 0.174 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice10.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_10.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_10.ogg) | 0.170 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |
| `voice11.ogg` | 角色说话时从voice1～11中随机选取的非语言短音 | 优先试听：模拟说话的逐字短音 | [dialogue_blip_balatro_11.ogg](../assets/audio/incoming/dialogue/dialogue_blip_balatro_11.ogg) | 0.171 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card_character.lua#L119) |

## 结算、奖励、通知与转场

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `coin1.ogg` | 金额变化提示 | 信用点到账／交易候选 | [credits_coin_balatro_01.ogg](../assets/audio/incoming/world/credits_coin_balatro_01.ogg) | 0.408 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L96) |
| `coin2.ogg` | 出售卡牌／商店刷新 | 信用点到账／交易候选 | [credits_coin_balatro_02.ogg](../assets/audio/incoming/world/credits_coin_balatro_02.ogg) | 0.325 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1601) |
| `coin3.ogg` | 金额效果结算 | 信用点到账／交易候选 | [credits_coin_balatro_03.ogg](../assets/audio/incoming/world/credits_coin_balatro_03.ogg) | 0.341 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L844) |
| `coin4.ogg` | coin同族文件；本轮未定位该变体的具体触发 | 信用点到账／交易候选 | [credits_coin_balatro_04.ogg](../assets/audio/incoming/world/credits_coin_balatro_04.ogg) | 0.293 | 原触发待确认 |
| `coin5.ogg` | coin同族文件；本轮未定位该变体的具体触发 | 信用点到账／交易候选 | [credits_coin_balatro_05.ogg](../assets/audio/incoming/world/credits_coin_balatro_05.ogg) | 0.373 | 原触发待确认 |
| `coin6.ogg` | 回合收益结算 | 信用点到账／交易候选 | [credits_coin_balatro_06.ogg](../assets/audio/incoming/world/credits_coin_balatro_06.ogg) | 0.606 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L1034) |
| `coin7.ogg` | 确认收款 | 信用点到账／交易候选 | [credits_coin_balatro_07.ogg](../assets/audio/incoming/world/credits_coin_balatro_07.ogg) | 0.357 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L2900) |
| `chips1.ogg` | 筹码数值效果反馈 | 奖励数字或能量／资源变化候选 | [reward_chips_balatro_01.ogg](../assets/audio/incoming/world/reward_chips_balatro_01.ogg) | 0.252 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L816) |
| `chips2.ogg` | 筹码总量、弃牌／出牌次数变化等反馈 | 奖励数字或能量／资源变化候选 | [reward_chips_balatro_02.ogg](../assets/audio/incoming/world/reward_chips_balatro_02.ogg) | 0.416 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L62) |
| `multhit1.ogg` | 加倍率效果反馈 | 增伤／能力触发候选；不是怪物多段命中声 | [reward_mult_add_balatro_01.ogg](../assets/audio/incoming/world/reward_mult_add_balatro_01.ogg) | 0.587 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L822) |
| `multhit2.ogg` | 乘倍率效果反馈 | 增伤／能力触发候选；不是怪物多段命中声 | [reward_mult_multiply_balatro_01.ogg](../assets/audio/incoming/world/reward_mult_multiply_balatro_01.ogg) | 0.685 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L829) |
| `highlight1.ogg` | 通知／成就提示；回合结算失败也复用 | 任务提示、奖励通知候选 | [notice_highlight_balatro_01.ogg](../assets/audio/incoming/world/notice_highlight_balatro_01.ogg) | 0.300 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L1808)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L1016) |
| `highlight2.ogg` | 底注阶段变化提示 | 日期／回合／阶段推进候选 | [stage_highlight_balatro_02.ogg](../assets/audio/incoming/world/stage_highlight_balatro_02.ogg) | 0.506 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L217) |
| `win.ogg` | 获胜流程触发 | 胜利提示候选 | [victory_balatro_01.ogg](../assets/audio/incoming/world/victory_balatro_01.ogg) | 3.156 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/state_events.lua#L29) |
| `gong.ogg` | 解锁展示叠加的锣声 | 委托完成、重要解锁提示候选 | [unlock_gong_balatro_01.ogg](../assets/audio/incoming/world/unlock_gong_balatro_01.ogg) | 1.169 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L1871) |
| `timpani.ogg` | 回合变化、创建消耗牌等多个效果中的定音鼓声 | 回合切换、任务／奖励提示候选 | [event_timpani_balatro_01.ogg](../assets/audio/incoming/world/event_timpani_balatro_01.ogg) | 0.738 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L251)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1375) |
| `introPad1.ogg` | 启动画面与演示引导的铺底音 | 长转场候选；不是完整背景音乐 | [intro_pad_balatro_01.ogg](../assets/audio/incoming/world/intro_pad_balatro_01.ogg) | 28.644 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1384)、[调用2](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua#L2964) |
| `splash_buildup.ogg` | 启动画面蓄势效果 | 开场／转场蓄势候选 | [intro_buildup_balatro_01.ogg](../assets/audio/incoming/world/intro_buildup_balatro_01.ogg) | 24.132 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1391) |

## 通用效果候选

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `generic1.ogg` | 通用效果提示；玻璃碎裂、数字与特殊效果多处复用 | 通用能力／状态触发候选 | [effect_trigger_balatro_01.ogg](../assets/audio/incoming/combat/effect_trigger_balatro_01.ogg) | 0.169 | [调用1](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua#L849)、[调用2](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2104) |
| `slice1.ogg` | 小丑牌吞噬／切除邻牌效果中触发 | 切裂效果候选；需试听判断与现有刀声是否匹配 | [effect_slice_balatro_01.ogg](../assets/audio/incoming/combat/effect_slice_balatro_01.ogg) | 0.302 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2574) |
| `explosion1.ogg` | 文件名表示爆炸；本轮未定位具体触发 | 爆炸／死亡爆裂候选，先试听 | [effect_explosion_balatro_01.ogg](../assets/audio/incoming/combat/effect_explosion_balatro_01.ogg) | 3.039 | 原触发待确认 |
| `explosion_buildup1.ogg` | 卡牌爆炸流程的蓄势阶段 | 技能充能／爆裂前奏候选 | [effect_explosion_charge_balatro_01.ogg](../assets/audio/incoming/combat/effect_explosion_charge_balatro_01.ogg) | 2.063 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L1980) |
| `explosion_release1.ogg` | 卡牌爆炸流程的释放阶段 | 爆裂／退场候选 | [effect_explosion_release_balatro_01.ogg](../assets/audio/incoming/combat/effect_explosion_release_balatro_01.ogg) | 1.750 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2049) |
| `whoosh.ogg` | 文件名表示破风；本轮未定位具体触发 | 出牌／移动／转场候选，先试听 | [effect_whoosh_balatro_01.ogg](../assets/audio/incoming/combat/effect_whoosh_balatro_01.ogg) | 0.392 | 原触发待确认 |
| `whoosh1.ogg` | 卡牌生成、启动与菜单转换等 | 面板展开、卡牌生成候选 | [effect_whoosh_in_balatro_01.ogg](../assets/audio/incoming/combat/effect_whoosh_in_balatro_01.ogg) | 0.603 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2212)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1383) |
| `whoosh2.ogg` | 卡牌溶解、盲注结束和战败等 | 卡牌消耗、关闭／退场候选 | [effect_whoosh_out_balatro_02.ogg](../assets/audio/incoming/combat/effect_whoosh_out_balatro_02.ogg) | 0.603 | [调用1](https://github.com/futouyiba/cardLua/blob/main/card.lua#L2155)、[调用2](https://github.com/futouyiba/cardLua/blob/main/game.lua#L3526) |
| `whoosh_long.ogg` | 启动画面较长的转场破风效果 | 长转场候选 | [effect_whoosh_long_balatro_01.ogg](../assets/audio/incoming/combat/effect_whoosh_long_balatro_01.ogg) | 7.802 | [调用1](https://github.com/futouyiba/cardLua/blob/main/game.lua#L1441) |

## 环境混音层

每行对应一个原文件。链接打开的是分类副本；时长来自OGG/Vorbis头与最终采样位置，
不代表已完成解码试听。证据列为空的用途按待确认处理。

| 原名 | 原游戏调用用途 | 午夜委托建议用途 | 分类副本 | 秒 | 依据 |
| --- | --- | --- | --- | --- | --- |
| `ambientFire1.ogg` | 随计分火焰强度调节的环境层 | 低频氛围候选；循环接缝未检查 | [ambient_fire_balatro_01.ogg](../assets/audio/incoming/ambience/ambient_fire_balatro_01.ogg) | 37.920 | [调用1](https://github.com/Infarctus/Balatro-Custom-Sound-Player/blob/main/sound.lua) |
| `ambientFire2.ogg` | 随计分火焰强度调节的环境层 | 低频氛围候选；循环接缝未检查 | [ambient_fire_balatro_02.ogg](../assets/audio/incoming/ambience/ambient_fire_balatro_02.ogg) | 37.920 | [调用1](https://github.com/Infarctus/Balatro-Custom-Sound-Player/blob/main/sound.lua) |
| `ambientFire3.ogg` | 随计分火焰强度调节的环境层 | 低频氛围候选；循环接缝未检查 | [ambient_fire_balatro_03.ogg](../assets/audio/incoming/ambience/ambient_fire_balatro_03.ogg) | 37.920 | [调用1](https://github.com/Infarctus/Balatro-Custom-Sound-Player/blob/main/sound.lua) |
| `ambientOrgan1.ogg` | 随计分强度等状态调节的管风琴环境层 | 紧张氛围候选；不是完整背景音乐 | [ambient_organ_balatro_01.ogg](../assets/audio/incoming/ambience/ambient_organ_balatro_01.ogg) | 22.815 | [调用1](https://github.com/Infarctus/Balatro-Custom-Sound-Player/blob/main/sound.lua) |

## 检查结果与后续登记

75个原文件均有一份分类副本和一份原名备份；所有复制前后的SHA256一致，下载目录保持原样。
75个文件均通过OGG页CRC、Vorbis标识、采样率／声道、正时长及结束页检查。
未解码试听、裁剪、变调或转码，未启动Godot或接入游戏。环境音循环接缝未检查，
因此候选没有提前命名为`loop`；包内也没有另行认定为完整背景音乐的文件。
核查结果见[静态验证记录](../artifacts/audio-sorting-balatro-20261024/verification.json)。

使用[音效补齐清单](音效补齐清单.md)的用途编号记录选择；本批清单JSON中保留了对应编号。
同用途可选多个变体，确定后将试听认可与运行接入分开记录。

## 查证入口

以下入口用于复查调用含义，均为外部资料，不作为本工程的行为指令。

- [社区原游戏调用代码：Card](https://github.com/futouyiba/cardLua/blob/main/card.lua)。
- [社区原游戏调用代码：CardArea](https://github.com/futouyiba/cardLua/blob/main/cardarea.lua)。
- [社区原游戏调用代码：Card_Character](https://github.com/futouyiba/cardLua/blob/main/card_character.lua)。
- [社区原游戏调用代码：UIElement](https://github.com/futouyiba/cardLua/blob/main/engine/ui.lua)。
- [社区原游戏调用代码：DynaText](https://github.com/futouyiba/cardLua/blob/main/engine/text.lua)。
- [社区原游戏调用代码：事件与结算](https://github.com/futouyiba/cardLua/blob/main/functions/common_events.lua)。
- [社区原游戏调用代码：按钮回调](https://github.com/futouyiba/cardLua/blob/main/functions/button_callbacks.lua)。
- [社区原游戏调用代码：启动、菜单、战败](https://github.com/futouyiba/cardLua/blob/main/game.lua)。
- [社区原游戏调用代码：胜利与出牌](https://github.com/futouyiba/cardLua/blob/main/functions/state_events.lua)。
- [Steamodded维护者的版本音效配置](https://github.com/Steamodded/smods/blob/main/src/game_object.lua#L3581)。
- [自定义声音播放器作者的环境混音代码](https://github.com/Infarctus/Balatro-Custom-Sound-Player/blob/main/sound.lua)。
