# 测试目录索引

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

## 主线新增回归（2026-10-23 合并）

这些新增入口保留在 `tests/` 根目录；原有套件继续使用分类后的目录。
科技图形测试继承 `combat/interaction/interaction_visual.gd`，不能再引用旧根目录路径。

| 范围 | 套件 |
| --- | --- |
| 事件刷新池、时间与日期（无窗口） | [event_refresh_tests](story/event_refresh_tests.tscn)：6候选全局3上限、按地点一致、入口防绕过、保留补位／失效、查询只读、区间闭边界、完成与失败事务、真实付费／战败／胜利／奖励、第7天封顶／非法日期拒绝及存读、旧档补池不追算、演练及HUD／地点刷新文案；关闭保存，save/meta专用路径 |
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
