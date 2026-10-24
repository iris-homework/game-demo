# 测试目录索引

2026-10-24退出清理：[audio_cleanup_tests](audio_cleanup_tests.tscn)32项检查普通／2D／3D播放对象及声音数据实际释放；[audio_quit_tests](audio_quit_tests.tscn)菜单8项、加`-- window-close`运行关闭处理7项；[resource_pipeline_cleanup_tests](resource_pipeline_cleanup_tests.tscn)58项验证真实牌库依赖图、缓存兼容与Profile／Frame／Attachment所有权。配套原12套、战斗音效113项与管线运行时111项，共18套1604项通过，最终无退出泄漏提示。必须用独立工程／用户目录及`--headless --audio-driver Dummy --verbose`，音频自然播放套件使用真实时间，不加`--fixed-fps`；关闭处理测试不操作系统窗口。见[本轮汇总](../artifacts/qa/resource-cleanup-2026-10-24/verification.json)。保存失败流程现含音频收尾共42项，上一条历史验收的41项记录保留。

2026-10-24审计修复：[cold_start_loadout_tests](cold_start_loadout_tests.tscn)140项覆盖冷启动牌库／经典及单敌演练、备份、坏档与只读隔离；[enemy_intent_phase_tests](combat/presentation/enemy_intent_phase_tests.tscn)15项覆盖易伤、力量与虚弱的展示时序；[save_failure_flow_tests](save_failure_flow_tests.tscn)41项覆盖治疗、对白、奖励、新游戏、战败与真实战斗视图的保存失败／重复重试／恢复。配套9套合计12套1274项通过。测试必须使用复制工程及独立用户目录，全部headless；完整结果及首轮夹具调整见[汇总](../artifacts/qa/audit-fixes-2026-10-24/verification.json)和修改记录。

2026-10-24 删除芬恩：`enemy_visual_library_tests`补充旧引用退役、无立绘攻防与目标区域验证；相关有图夹具改用既有小弟图。6套Godot无窗口检查929项、Node60项通过。旧机器人规则95项4失败在改动前后均复现，详见[验证汇总](../artifacts/qa/remove-finn-2026-10-24/verification.json)，不计为通过。

2026-10-24奖励金额：战后与酒馆回访统一50，金钱芯片额外30。奖励124／战斗类型122／品级概率172／回访130／跳过203／战败379，共1130项无窗口检查通过，含旧1000记录兼容和芯片合计80。扩展被动科技／重开套件的19项失败在恢复旧金额后相同，详见[本轮汇总](../artifacts/qa/battle-credits-2026-10-24/verification.json)及修改记录；未做像素／物理输入验收。

2026-10-24 三敌事件移除选项：`new_commissions_tests`当前覆盖无选项继续／跳过直接开战、旧选择页存档续接、胜败与结算；326项通过，配套跳过对白203项通过。证据`artifacts/qa/three-events-no-choice-2026-10-24/`。下方原暂离／选择检查说明为历史记录。

2026-10-24黑体标题版：卡面专项改读`neon-comic-title-v3`，本轮1538项0失败、40/40图加载；40张标题区外像素不变由制作复核验证。无Godot像素验收，证据：[汇总](../artifacts/qa/card-title-2026-10-24/verification.json)。

2026-10-24等级版卡面：原卡面专项改查`neon-comic-rarity-v2`与C／非C动态费用色，固定卡面检查新运行路径；两套分别1538／1716项，共3254项通过、40/40实图加载。静态素材配色／徽章／标题边界及像素保真另见制作目录，无Godot像素或物理输入验收。证据：[汇总](../artifacts/qa/card-rarity-2026-10-24/verification.json)。

2026-10-24 三敌对白立绘补正：`new_commissions_tests`增至300项，实际对白视图验证三张既有PNG、旁白及画外音期间出场、胜利／暂离退场、透明材质、旧角色去白保留与状态不变；配套跳过对白203项，共503项通过。证据`artifacts/qa/enemy-dialogue-portraits-2026-10-24/`；无窗口，不代表实际像素验收。

2026-10-24演练入口整合（统一无人物卡面前的历史验证）：`published_training_tests`改查统一模态面板，直接覆盖三场经典战斗与十敌按钮、选景嵌套禁用／恢复、Esc及焦点、无重叠和B04选景隔离；`exit_confirmation_tests`新增演练面板阻止退出确认叠加及开发快捷键，双卡面和变异鱼专项同步新入口。复制工程、专用用户目录无窗口运行演练1063／退出77／双卡面2757，共3897项0失败。证据与退出清理边界见[汇总](../artifacts/qa/unified-training-2026-10-24/verification.json)，不代表像素或物理输入验收。

2026-10-24 新增三项正式委托：[new_commissions_tests](story/new_commissions_tests.tscn)覆盖E13／E14／E15的刷新、暂离、选择、开战／结算、存读防重、演练隔离、终局及酒馆回礼计数；在复制工程和独立用户目录中无窗口运行，专项206项通过。配套剧情、刷新、回访、退役迁移、地图、跳过、演练与战败共9套3430项通过；首轮夹具修正和退出清理提示见[汇总](../artifacts/qa/new-commissions-2026-10-24/verification.json)与修改记录。不代表像素、物理输入或平衡验收。

2026-10-24：`card_library_filters` 新增战斗／委托奖励页嵌套牌库入口回归，覆盖待选／已领取／已跳过、拥有数量、关闭恢复、选卡弹层拦截及领奖离开。修复前6项入口失败，修复后86项0失败；独立复制工程无窗口运行，信号与视口合成输入，不代表物理鼠标或像素验收。证据：`artifacts/qa/reward-deck-2026-10-24/`。

2026-10-24删除艾克：通用支付测试改用内存`fixtures/payment_choice.gd`，正式目录5事件／3战斗；新增E03/B03旧节点迁移、已领取酒馆回礼保留及未领取旧回访返回地图覆盖。11套2252项后台断言通过，首轮数量断言修正及退出清理边界见修改记录；证据`artifacts/qa/remove-ike-2026-10-24/verification.json`。

2026-10-24开幕与回访：11套隔离无窗口检查共1987项断言通过；新开幕110项、回访68项。首轮夹具修正、退出清理提示及未做像素／物理输入的边界见修改记录；证据`artifacts/qa/opening-support-2026-10-24/final-summary.json`。

[酒馆回访专项](story/commission_return_tests.tscn)：任意三委托解锁／去重／开幕排除、真实付费与战胜路径、旧档入口、50信用点与普通卡牌候选（兼容旧1000记录）、领奖与选卡失败回滚、不耗时及无胜利芯片、存读防重、真实奖励选择器节点。无窗口且独立存档。

2026-10-24余项修复（统一无人物卡面前的历史验证）：新增`remaining_bug_tests.tscn`（56项，备份轮换／复制和替换失败保护、旧卡牌快照拒绝及兼容、开场结算文案、五种模态地图拖动取消）与`battle_recovery_tests.tscn`（12项，胜利保存失败、按钮重试及收益防重）；扩展`combat_preview_tests`至2311项，覆盖动态多段首段／后续伤害。另跑双卡面2762项，覆盖两套模板的动态文案边界。整合14套6795项断言0失败，全部headless及隔离路径；战败套件首轮因专用用户目录命名保护拒绝执行，补正确隔离名后309项通过，未去掉保护。原战斗模型的诊所成功夹具补足150信用点并新增扣款断言，106项通过；原先4项失败不是治疗代码错误。故障注入产生预期备份复制错误及损坏卡面偏好解析错误，部分界面套件仍有已有退出资源清理提示；无物理输入或像素验收。证据`artifacts/qa/remaining-bugs-2026-10-24/`。

2026-10-24奖励卡出售存档修复：`market/black_market_tests`新增真实领奖后出售最后副本、二次保存轮换、主档及备份重新读取、防重领及非法领取记录拒绝；支持`QA_OUT_DIR`指定证据目录。修改前140项中3项失败，修复后148项0失败；奖励78、剧情257项0失败，合计483项通过。战斗模型102项中4项诊所治疗失败，修改前原代码同样失败，未改断言或治疗逻辑。隔离复制工程及独立用户目录headless运行，证据`artifacts/qa/reward-sale-save-2026-10-24/`；未做渲染或物理输入检查。

2026-10-24被动科技：`passive_technology_tests.tscn`137项覆盖三枚定义、首回合加牌、禁止激活、冻结四槽、胜利独立收益与防重、封顶、战败／演练、存读／旧档／失败回滚；`technology_icons_tests.tscn`扩展至301项覆盖六张PNG、所有入口、被动点击／快捷键拒绝、主动并存和收益只读。商场UI98、配置131；相关核心回归结果及已知限制见`artifacts/qa/passive-technology-2026-10-24/backend-summary.json`和`artifacts/qa/passive-technologies-2026-10-24/`。共12套1758断言通过；无窗口、未使用正式存档，浏览器预览不替代Godot像素和物理输入验收。下文旧计数属于对应历史轮次。

后排绕行裁剪专项：[rear_lane_clipping_tests](combat/presentation/rear_lane_clipping_tests.tscn)，无窗口验证三种地面高度下的旧边界复现、完整绕行期间身体与玩家目标边界、接近终点、手牌区裁剪及脚底排序；不移动系统鼠标、不写正式存档，不替代渲染像素验收。

科技图标统一接入：[technology_icons_tests](technology_icons_tests.tscn)175项，检查三张透明PNG、商场／确认框、配置／携带槽、战斗科技卡和只读档案，包含资源一致性、尺寸／遮挡、空位、历史快照、冷却、卸装与无状态写入。另跑商场UI80、配置131，共386项通过，证据`artifacts/qa/technology-icons-2026-10-23/`；无窗口检查不替代Godot像素和物理输入。

沃斯商场：[technology_shop_tests](market/technology_shop_tests.tscn)覆盖原有科技货单、0—6货位、测试占位拒绝、交易保护、保存失败回滚、读档、装备及战斗效果；[technology_shop_ui_tests](market/technology_shop_ui_tests.tscn)覆盖三商品三空位、默认已拥有、确认／取消、模态焦点、余额／已有态及返回。使用专项存档路径、headless运行，修订证据位于`artifacts/qa/technology-shop-2026-10-23/existing-only/`。界面专项导出真实节点布局JSON供浏览器预览，不能代表Godot像素或物理输入验收。
黑市交易专项：[black_market_tests](market/black_market_tests.tscn)127项（库存、日期、买卖、存读／迁移、实际删牌、演练、失败回滚、浮动价冻结及价格版本原地迁移）；[market_ui_tests](market/market_ui_tests.tscn)103项（真实主场景路由、分层纹理／透明度／原生像素余量／前景遮挡、两行货架、确认／取消、余额、售罄、出售选择、Tab／Esc／F1隔离、HUD和第4天刷新）。均headless运行，仅写专项路径，不能代表实际像素或物理鼠标验收。交易证据：`artifacts/qa/black-market-2026-10-23/`，本轮分层证据：`artifacts/qa/black-market-layers-2026-10-23/`。

无人物版卡面专项：[card_face_style_tests](card_face_style_tests.tscn)。保留原入口名，当前以隔离用户目录及独立存档路径headless运行，覆盖40张无人物实图、主菜单无卡面按钮、旧偏好不影响显示、浏览与放大复用、40牌双形态动态排版及快照不变。不能代替实际像素和物理输入验收；本轮结果见修改记录。`artifacts/qa/card-face-style-2026-10-23/`及本页较早双卡面数量为移除切换前的历史证据。

十种已发布敌人的菜单演练专项：[published_training_tests](combat/enemies/published_training_tests.tscn)，在隔离复制工程中headless运行；覆盖十选择、真实战斗视图及攻击回调、咬击／射击演出、胜负与退出恢复、临时注册清理、存档哨兵、原三入口及模态焦点／Esc／锁定。只验证逻辑和节点时序，不替代像素渲染或真实鼠标验收，不启动桌面窗口。

## 2026-10-23 事件删减与无前置回归

[removed_events_tests](story/removed_events_tests.tscn)检查五事件／四战斗目录、空前置、三项刷新上限、无目标对白与支付选项，以及全部退役事件的对白／战斗／奖励／战败旧档迁移、既有收益与快照保留。本次以远端PR交付，仅做静态检查，未运行Godot；建议合并前在隔离环境执行本专项及现有事件刷新、完整剧情、迁移、地图、战败和奖励回归。通用单敌演练夹具改用B02；退役敌人画面专项通过仅测试可用的内存夹具保留，不重新接入生产目录。

敌人 PNG 制作、校准和发布另见[敌人制作台](../enemy_asset_pipeline/README.md)。
按用户指定，其隔离试用入口位于 `enemy_asset_pipeline/test/test_workbench.tscn`；
该目录还保存管线、运行时及图形集成检查，不计入下述历史 81 组统计。

增强战斗测试台位于
[`combat/workbench/`](combat/workbench/README.md)，提供左右双栏的地图、卡牌、
诺伦与多敌人动作测试。在Godot打开该目录的 `battle_background_preview.tscn`，
按F6运行。`launch.ps1 -Check` 用于执行专项检查。

本目录保存午夜委托的逻辑回归、渲染展示与输入验证。最初按游戏模块整理了
**81 组套件、243 个文件**；该数量不含下述主线新增回归及制作台专项。每组以 `.tscn` 为运行入口，同名 `.gd`
实现检查，`.gd.uid` 保存导入标识；本索引中的链接均指向整理后的新位置。

## 目录职责

测试按功能分为 `combat`、`characters`、`map`、`story`、`menu` 和
`integration`。战斗目录继续按规则、卡牌、敌人、表现和输入拆分；敌人专项
保留 `fish`、`gang`、`robot` 子目录。图形测试的截图、日志和报告输出到
`artifacts/qa`，`tests/fixtures` 保留测试输入数据。

| 目录 | 职责 |
| --- | --- |
| `combat/rules` | 战斗模型、Buff、虚弱、命中事件及弹反弹药展示 |
| `combat/cards` | 卡牌目录、预览、牌组、奖励及诺伦卡牌 |
| `combat/enemies` | 敌人形象库与各敌人规则、动作和展示 |
| `combat/presentation` | 舞台、HUD、意图、能量、动画和音频表现 |
| `combat/interaction` | 选牌、拖牌、数字键与牌堆输入 |
| `characters` | 可玩角色配置与战斗临时科技 |
| `map` | 地图配置、模型、缩放与指针输入 |
| `story` | 对白、跳过、佣兵迁移及剧情流程 |
| `menu` | 主菜单展示、输入和生命周期 |
| `integration` | R1 集成检查与历史早期入口 |
| `fixtures` | 测试夹具和只读输入，不属于游戏存档 |

## 2026-10-24 艾克事件退役

`story/removed_events_tests`补充E03／B03四种上下文与全部历史节点迁移；`story/commission_return_tests`验证三项现存委托解锁，以及原艾克完成记录曾参与回礼资格时，待选／已领取／已跳过的历史回礼仍可读且不可重复领取。支付条件、跳过和点击回归改用[通用支付夹具](fixtures/payment_choice.gd)的`QA_PAYMENT`内存事件，不恢复正式艾克内容。剧情、事件刷新、地图和被动科技回归已适配目录删减。本段为覆盖说明，实际运行结果由本轮记录给出。

## 2026-10-24 开幕芯片支援

[opening_support_tests](story/opening_support_tests.tscn)覆盖金钱／治疗／迅捷芯片三选一的实际拥有与自动携带、满槽不替换、存读及防重、非法科技与动作批次回滚、选择保存失败回滚、旧目标选择档不追发，以及真实对白三选项和结算节点结构。支持`QA_OUT_DIR`，仅写专项检查点；按headless运行，不调用系统鼠标，不代表像素或物理输入验收。配套更新事件刷新三分支、完整剧情、对话记录、跳过及点击断言；E01R回访奖励另由其专项覆盖。本条为新增覆盖说明，实际运行结果由本轮验证记录给出。

## 主线新增回归（2026-10-23 合并）

这些新增入口保留在 `tests/` 根目录；原有套件继续使用分类后的目录。
科技图形测试继承 `combat/interaction/interaction_visual.gd`，不能再引用旧根目录路径。

| 范围 | 套件 |
| --- | --- |
| 事件刷新池、时间与日期（无窗口） | [event_refresh_tests](story/event_refresh_tests.tscn)：6候选全局3上限、按地点一致、入口防绕过、保留补位／失效、查询只读、区间闭边界、开幕三芯片分支逐句／跳过均保持第1天及存读、完成与失败事务、真实付费／战败／胜利／奖励、第7天封顶／非法日期拒绝及存读、旧档补池不追算、演练及HUD／地点刷新文案；关闭保存，save/meta专用路径 |
| 地图事件类型标记（无窗口） | [map_event_types_tests](map/map_event_types_tests.tscn)，覆盖类型映射、混合计数、Boss特效开关及角标点击边界；不含渲染验收 |
| 战斗类型、冻结与旧档（无窗口） | [battle_type_tests](combat/rules/battle_type_tests.tscn) |
| 按战斗类型的奖励概率（无窗口） | [card_reward_rates_tests](combat/cards/card_reward_rates_tests.tscn) |
| 战败终局（无窗口） | [defeat_tests](defeat_tests.tscn)：八场失败、致死落盘、旧档、继续禁用、防绕过、胜利／演练／新局与UI结构；不代替实际渲染验收 |
| 战斗开局恢复 | [battle_restart_tests](battle_restart_tests.tscn) · [battle_restart_integration](battle_restart_integration.tscn) |
| 地图科技配置与保存 | [technology_loadout_tests](technology_loadout_tests.tscn) |
| 新科技效果 | [technology_effects_tests](technology_effects_tests.tscn) · [technology_effects_visual](technology_effects_visual.tscn) |
| 固定卡面 | [fixed_card_face_tests](fixed_card_face_tests.tscn) · [fixed_card_face_visual](fixed_card_face_visual.tscn) |
| 牌库筛选与退出确认 | [card_library_filters](card_library_filters.tscn) · [exit_confirmation_tests](exit_confirmation_tests.tscn) |

## 原有分类套件索引

下表按功能列出原有 81 组。场景链接便于直接查看测试入口；需要修改断言时，
再打开对应的 `.gd` 文件。同名脚本和 UID 文件与各自场景放在同一目录。

### 战斗：规则

| 分类 | 套件 |
| --- | --- |
| 战斗规则 (`combat/rules`) | [buff_library_tests](combat/rules/buff_library_tests.tscn) · [combat_tests](combat/rules/combat_tests.tscn) · [weak_tests](combat/rules/weak_tests.tscn) · [combat_hit_events](combat/rules/combat_hit_events.tscn) · [parry_ammo_visual](combat/rules/parry_ammo_visual.tscn) |

### 战斗：卡牌与奖励

| 分类 | 套件 |
| --- | --- |
| 卡牌与奖励 (`combat/cards`) | [card_console_visual](combat/cards/card_console_visual.tscn) · [card_library_visual](combat/cards/card_library_visual.tscn) · [card_revision_integration](combat/cards/card_revision_integration.tscn) · [current_deck_visual](combat/cards/current_deck_visual.tscn) · [combat_preview_tests](combat/cards/combat_preview_tests.tscn) · [combat_preview_visual](combat/cards/combat_preview_visual.tscn) · [noren_cards_tests](combat/cards/noren_cards_tests.tscn) · [noren_cards_visual](combat/cards/noren_cards_visual.tscn) · [noren_reward_visual](combat/cards/noren_reward_visual.tscn) · [noren_update_integration](combat/cards/noren_update_integration.tscn) · [reward_tests](combat/cards/reward_tests.tscn) · [reward_visual](combat/cards/reward_visual.tscn) |

### 战斗：敌人

| 分类 | 套件 |
| --- | --- |
| 敌人通用 (`combat/enemies`) | [enemy_visual_library_tests](combat/enemies/enemy_visual_library_tests.tscn) |
| 鱼 (`combat/enemies/fish`) | [fish_death_burst_visual](combat/enemies/fish/fish_death_burst_visual.tscn) · [fish_death_visual](combat/enemies/fish/fish_death_visual.tscn) · [fish_enemy_visual](combat/enemies/fish/fish_enemy_visual.tscn) · [fish_rules_tests](combat/enemies/fish/fish_rules_tests.tscn) · [fish_rules_visual](combat/enemies/fish/fish_rules_visual.tscn) · [fish_spit_visual](combat/enemies/fish/fish_spit_visual.tscn) |
| 黑帮 (`combat/enemies/gang`) | [gang_battle_visual](combat/enemies/gang/gang_battle_visual.tscn) · [gang_enemy_visual](combat/enemies/gang/gang_enemy_visual.tscn) · [gang_rules_tests](combat/enemies/gang/gang_rules_tests.tscn) |
| 机器人 (`combat/enemies/robot`) | [robot_laser_visual](combat/enemies/robot/robot_laser_visual.tscn) · [robot_rules_tests](combat/enemies/robot/robot_rules_tests.tscn) |

### 战斗：表现与输入

消耗牌特效专项见 [exhaust_fx_tests](combat/presentation/exhaust_fx_tests.tscn)：无窗口检查自身消耗、能力牌、拆卸弹药所选手牌与普通弃牌分流、完整原卡与动态文字的合成结构、选中与输入禁用、过程模型不变、四区守恒、忙碌防重入和正常／切页中途清理。关闭保存并使用专用路径，不调用截图或系统鼠标；不代表实际渲染与审美验收。

角色形态悬停专项见 [stance_hover_tests](combat/presentation/stance_hover_tests.tscn)：无窗口检查双形态说明内容、视口合成悬停命中、人物移动／镜头缩放后范围跟随、选牌／忙碌／弹层隐藏与恢复及模型不变；关闭保存并使用专用路径，不移动系统鼠标，不代表实际渲染或物理鼠标验收。

弹药槽专项见 [ammo_hud_tests](combat/presentation/ammo_hud_tests.tscn)：无窗口检查科技上方布局、十槽两行、0—10发精确亮槽、橙色文字、悬停说明卡结构、真实远程耗弹／无弹拒绝／近战回弹、旧容量及非诺伦隐藏；关闭保存并使用测试专用路径。不调用截图、窗口调整或鼠标移动，不代表渲染与真实悬停验收。

手牌排布专项见 [hand_layout_tests](combat/presentation/hand_layout_tests.tscn)：无窗口检查1／5／7／10／20／40张手牌的放大及上移、旋转卡面横向边界、卡面倾斜与排列圆弧一致、朝内上角无明显突出、每张卡的可见命中区域、命中查询与悬停姿态、选中及取消、补牌落稳与移除后的重排；关闭保存并使用测试专用路径，不截图、不移动系统鼠标。原`hand_fan_visual`保留为图形检查入口。

出牌收益特效专项见 [card_gain_fx_tests](combat/presentation/card_gain_fx_tests.tscn)：无窗口检查成功出牌的实际格挡／抽牌触发、切近战附带抽牌、条件未满足／无牌可抽／失败不触发、复合效果、忙碌锁、模型不重复结算及视图清理。关闭保存并使用专用路径；截图与渲染证据另见 `artifacts/qa/card-gain-fx-2026-10-23/`。

自身目标牌的敌人选择框专项见 [self_skill_targets_tests](combat/interaction/self_skill_targets_tests.tscn)：无窗口检查近远程目标判断、选牌／取消、敌人悬停和提示保留；使用视口合成事件，不移动系统鼠标，禁用保存并使用专用路径。

角色 mipmap A/B 专项位于[敌人制作台测试](../enemy_asset_pipeline/test/mipmap_workbench_qa.tscn)，
验证正式工作台的运行期纹理、四动作过滤及截图，支持`QA_OUT_DIR`。

角色目录名专项见[character_names_check](combat/workbench/character_names_check.tscn)：
检查两个测试台的选择项、HUD、目标、提示及内部ID保持，支持headless与实际截图。

归位残影矩阵专项见[return_ghost_transform](combat/presentation/return_ghost_transform.tscn)：
检查镜像／旋转／斜切及制作台诺伦近战、持枪受伤归位，支持headless与实际截图。
关闭正式保存；自动运行时另外隔离用户目录。日志与截图写入
`artifacts/qa/return-ghost-transform-2026-10-21/`。

| 分类 | 套件 |
| --- | --- |
| 战斗表现 (`combat/presentation`) | [actor_hud_visual](combat/presentation/actor_hud_visual.tscn) · [b04_scenery_choice_visual](combat/presentation/b04_scenery_choice_visual.tscn) · [battle_grounding_visual](combat/presentation/battle_grounding_visual.tscn) · [battle_scenery_visual](combat/presentation/battle_scenery_visual.tscn) · [buff_tooltip_visual](combat/presentation/buff_tooltip_visual.tscn) · [combat_audio_tests](combat/presentation/combat_audio_tests.tscn) · [combat_depth_visual](combat/presentation/combat_depth_visual.tscn) · [combat_neon_render](combat/presentation/combat_neon_render.tscn) · [combat_neon_visual](combat/presentation/combat_neon_visual.tscn) · [combat_stage_visual](combat/presentation/combat_stage_visual.tscn) · [enemy_follow_hud_visual](combat/presentation/enemy_follow_hud_visual.tscn) · [enemy_hp_layout_visual](combat/presentation/enemy_hp_layout_visual.tscn) · [enemy_intent_tooltip_visual](combat/presentation/enemy_intent_tooltip_visual.tscn) · [enemy_intent_visual](combat/presentation/enemy_intent_visual.tscn) · [energy_hud_visual](combat/presentation/energy_hud_visual.tscn) · [hand_fan_visual](combat/presentation/hand_fan_visual.tscn) · [noren_slash_visual](combat/presentation/noren_slash_visual.tscn) · [pile_count_visual](combat/presentation/pile_count_visual.tscn) · [random_melee_tests](combat/presentation/random_melee_tests.tscn) · [return_glitch_visual](combat/presentation/return_glitch_visual.tscn) · [shuffle_visual](combat/presentation/shuffle_visual.tscn) · [stance_timing_tests](combat/presentation/stance_timing_tests.tscn) · [turn_banner_visual](combat/presentation/turn_banner_visual.tscn) · [weapon_shift_visual](combat/presentation/weapon_shift_visual.tscn) |
| 战斗输入 (`combat/interaction`) | [combat_bugfix_visual](combat/interaction/combat_bugfix_visual.tscn) · [drag_visual](combat/interaction/drag_visual.tscn) · [hand_number_keys_visual](combat/interaction/hand_number_keys_visual.tscn) · [interaction_visual](combat/interaction/interaction_visual.tscn) · [noren_input_visual](combat/interaction/noren_input_visual.tscn) · [pile_visual](combat/interaction/pile_visual.tscn) · [skill_drag_visual](combat/interaction/skill_drag_visual.tscn) |

### 角色、地图、剧情与菜单

| 分类 | 套件 |
| --- | --- |
| 角色与科技 (`characters`) | [character_cyberware_tests](characters/character_cyberware_tests.tscn) · [character_cyberware_visual](characters/character_cyberware_visual.tscn) · [cyberware_tests](characters/cyberware_tests.tscn) · [cyberware_visual](characters/cyberware_visual.tscn) · [player_character_tests](characters/player_character_tests.tscn) · [player_character_visual](characters/player_character_visual.tscn) |
| 地图 (`map`) | [clinic_payment_tests](map/clinic_payment_tests.tscn) · [map_config_tests](map/map_config_tests.tscn) · [map_input_stability](map/map_input_stability.tscn) · [map_model_tests](map/map_model_tests.tscn) · [map_visual](map/map_visual.tscn) · [map_zoom_visual](map/map_zoom_visual.tscn) |
| 剧情 (`story`) | [dialogue_click_visual](story/dialogue_click_visual.tscn) · [dialogue_history_tests](story/dialogue_history_tests.tscn) · [dialogue_skip_tests](story/dialogue_skip_tests.tscn) · [dialogue_skip_visual](story/dialogue_skip_visual.tscn) · [mercenary_tests](story/mercenary_tests.tscn) · [mercenary_visual](story/mercenary_visual.tscn) · [run](story/run.tscn) |
| 主菜单 (`menu`) | [menu_visual](menu/menu_visual.tscn) |

### 集成与历史入口

| 分类 | 套件 |
| --- | --- |
| 集成与历史入口 (`integration`) | [r1_visual](integration/r1_visual.tscn) · [visual](integration/visual.tscn) |

`integration` 中的名称来自既有文件，含义并不相同：`visual` 是早期截图
脚本，`r1_visual` 是 R1 图形集成入口，`story/run` 是剧情流程回归入口。
保留这些名称和入口，便于追溯历史结果；它们不能互相替代。

## 运行方式

从工程根目录运行当前 QA 包装脚本，日志、结果和截图写入 `artifacts/qa`。
地图与主菜单包装脚本为 Godot 子进程设置隔离目录；使用 `tools/qa.ps1` 或直接
启动场景时，还需按下文设置用户目录隔离。参数与套件入口见
[开发工具与工作流](../docs/开发工具与工作流.md#qa-入口)。

### 无窗口规则测试

以下入口已由现有文档或 QA 入口明确按 headless 运行：

- `story/event_refresh_tests`：统一事件刷新池、时间区间、完成耗时及存读／演练隔离；含无窗口UI节点结构检查，不代表渲染或真实输入验收。
- `story/run`：剧情流程与配置回归。
- `combat/rules/combat_tests`：战斗模型回归。
- `map/map_config_tests` 和 `map/map_model_tests`：地图配置与模型。
- `characters/player_character_tests`、`characters/character_cyberware_tests`
  和 `characters/cyberware_tests`：角色与科技逻辑。

示例：

```powershell
godot --headless --path . res://tests/story/run.tscn
godot --headless --path . res://tests/combat/rules/combat_tests.tscn
godot --headless --path . res://tests/map/map_model_tests.tscn
```

其他 `*_tests` 场景也可能只做逻辑检查，但文件名不能作为证据。运行前应确认
脚本不依赖渲染视口、截图或界面焦点；有依赖时改用渲染窗口。

### 图形展示与输入

视觉展示、截图和合成输入检查需要 Godot 渲染窗口。`map_input_stability`
虽不以 `visual` 结尾，也按可见窗口输入套件处理，照常例保持窗口焦点并
顺序运行。示例：

```powershell
godot --path . --resolution 1280x800 res://tests/story/dialogue_click_visual.tscn
godot --path . --resolution 1280x800 res://tests/combat/interaction/interaction_visual.tscn
godot --path . --resolution 1280x800 res://tests/map/map_input_stability.tscn
```

图形测试会占用光标和窗口焦点，必须逐个运行，执行时不要操作测试窗口。
合成指针检查证明场景内的输入处理结果，仍需单独记录是否完成了物理鼠标、
触控板或完整游玩验收。

## 存档隔离与证据

测试不得写入用户的正式 `checkpoint.json`、`checkpoint.json.bak` 或
`meta_profile.json`。优先使用 QA 包装脚本的隔离 `APPDATA`。直接启动测试时，
先把用户目录指向任务专用位置，并确认测试自身使用内存夹具或测试专用保存路径：

```powershell
$qaRoot = Join-Path (Get-Location) 'artifacts/qa/<task-name>'
New-Item -ItemType Directory -Force -Path (Join-Path $qaRoot 'appdata') | Out-Null
$env:APPDATA = Join-Path $qaRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $qaRoot 'appdata'
```

截图、stdout／stderr、`result.json`、失败报告和动图统一保存在
`artifacts/qa/<任务日期-用途>/`。失败日志保留，不能通过删除断言、降低检查
标准或只保留最后一次通过来形成结论。

`tests/fixtures` 保存测试输入，例如
`fixtures/battle_background/scene_profiles.json.bak`。这些文件不是用户存档，
按照测试夹具维护；运行测试时不要用正式存档覆盖它们。

## 历史限制

此前记录中的通过数量只对应当轮工程、入口和证据，不代表本次整理后重新运行。
旧日志仍包含历史断言失败、退出时资源占用提示，以及合成输入不等同物理输入的
限制；另有一些界面专项只覆盖单一窗口尺寸。排查时先查
[修改记录](../docs/修改记录.md)确认对应日期和范围，再查
[维护文档](../docs/维护文档.md)中的当前规则与已知边界。历史原始输出见
[验收记录](../docs/验收记录.txt)，不能作为本轮通过证明。

本次整理保留测试名称、断言与旧测试。确认本轮验证范围时，以
[修改记录](../docs/修改记录.md)及对应的实际执行日志为准。

## 攻击演出模板专项

[attack_templates_qa.tscn](../enemy_asset_pipeline/test/attack_templates_qa.tscn)
使用隔离catalog和关闭保存的真实工作台，检查近战接近、咬击闭合命中、远程
全程原地、显式动作覆盖默认、逐段回调、真实敌方回合及慢放恢复。
远程夹具使用已有noren素材，不冒充缺少idle的09a已完成接入。
Node扫描、参数、发布与回退测试为
`enemy_asset_pipeline/test/attack_templates.test.cjs`，已加入该工具的`npm test`。
