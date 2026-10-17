# 《废墟图书馆》音效参考

追加音源：[罗兰「逻辑工作室」左轮与霰弹枪](roland/README.md)，保存于 `roland/`；其中 `Roland_Shotgun.wav` 已按用户要求替换当前射击音效，左轮保留备选。

2026-10-18：上一组网络音效经用户试听不满意，改为查找《废墟图书馆》游戏音源。已从社区的 Library of Ruina - Organized Assets 下载本目录7段WAV，按原始文件名保存，逐字节复制，不裁剪、不归一化、不合成、不改变音色。全部为PCM 16-bit双声道，Godot 4可直接导入。

| 文件 | 社区目录 | 时长 | 采样率 |
| --- | --- | --- | --- |
| `kuro_Hori.wav` | Guests / Urban Plague / Kurokumo Clan，横向斩击 | 1.066秒 | 48 kHz |
| `kuro_Vert.wav` | 同上，纵向斩击 | 1.066秒 | 48 kHz |
| `Atk_LeweiGun.wav` | Guests / Urban Plague / Full-Stop Office | 0.789秒 | 44.1 kHz |
| `Atk_Stepan.wav` | 同上 | 0.958秒 | 44.1 kHz |
| `Atk_Tamaki.wav` | 同上 | 1.372秒 | 44.1 kHz |
| `Thumb_Gun_Normal.wav` | Guests / Star of the City / The Thumb | 1.907秒 | 44.1 kHz |
| `Finger_Snapping.wav` | Other，响指 | 2.500秒 | 48 kHz |

来源入口：

- [Library of Ruina - Organized Assets](https://drive.google.com/drive/folders/12ifYsKtsT7SdkjCiJOGaH40aJ-0uJ4X9)
- [Sound Effects](https://drive.google.com/drive/folders/12oCyStslJKwrw4gRjwCiKtN1IhJ63q9A)
- [黑云会](https://drive.google.com/drive/folders/1tmWpL-KEqjH_OXSqyLql_5Bgr8C5IOzF)
- [终止事务所](https://drive.google.com/drive/folders/1mnAVaaLF2EeL2wIY5cY2wx0yPPx7js9J)
- [拇指](https://drive.google.com/drive/folders/1psqyvgd32yCmKtPO-XOhSLJQm1-b_zpB)
- [通用音效与响指](https://drive.google.com/drive/folders/1FP1Rb728Ac37vgcqWpNzDOKjpm375RP-)

精确文件链接、原始参数、SHA256与来源限制见 [sources.json](sources.json)。这些文件是社区标注的游戏音源，本轮未与本地安装的原版游戏比对。

版权归属与复用边界见 [RIGHTS.txt](RIGHTS.txt)。本目录不采用CC0或CC BY标记，也不继承社区其他代码仓库的MIT授权；未找到将这些音效用于另一个公开发行游戏的授权。

2026-10-18 用户试听选定后，`scripts/combat/combat_audio.gd` 已实际接入：斩击／突刺使用整段试听第2段 `kuro_Vert.wav`，射击初选第3段 `Atk_LeweiGun.wav`，随后按用户要求换为 `roland/Roland_Shotgun.wav`，归位响指使用 `Finger_Snapping.wav`。其他4段保留为备选。沿用动作触发时点和独立播放器；实际叠加播放发现削波后，三类播放音量统一降低5 dB，最终为斩击−12 dB、射击−13 dB、响指−10 dB。素材本身原样保留。

连续试听：`artifacts/qa/ruina-sfx-2026-10-18/试听_横斩_纵斩_四种枪声_响指.wav`。顺序与上表一致，间隔0.75秒；只有试听文件转为48 kHz单声道并整体降低6 dB，不对每段单独归一化。原始资料在 `artifacts/audio_sources/ruina_2026-10-18/`。
