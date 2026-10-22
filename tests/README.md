# 测试目录索引

敌人 PNG 制作、校准和发布另见[敌人制作台](../enemy_asset_pipeline/README.md)。
按用户指定，其隔离试用入口位于 `enemy_asset_pipeline/test/test_workbench.tscn`；
该目录还保存管线、运行时及图形集成检查，不计入下述历史 81 组统计。

增强战斗测试台位于
[`combat/workbench/`](combat/workbench/README.md)，提供左右双栏的地图、卡牌、
诺伦与多敌人动作测试。在Godot打开该目录的 `battle_background_preview.tscn`，
按F6运行。`launch.ps1 -Check` 用于执行专项检查。

本目录保存午夜委托的逻辑回归、渲染展示与输入验证。目录按游戏模块组织，
共 **81 组套件、243 个文件**。每组以 `.tscn` 为运行入口，同名 `.gd`
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

## 完整套件索引

下表按功能列出全部 81 组。场景链接便于直接查看测试入口；需要修改断言时，
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
| 地图 (`map`) | [map_config_tests](map/map_config_tests.tscn) · [map_input_stability](map/map_input_stability.tscn) · [map_model_tests](map/map_model_tests.tscn) · [map_visual](map/map_visual.tscn) · [map_zoom_visual](map/map_zoom_visual.tscn) |
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
