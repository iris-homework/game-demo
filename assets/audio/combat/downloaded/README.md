# 网络下载战斗音效

2026-10-18 下载并整理，供 Godot 4 工程直接导入。这里是候选素材；当前 `combat_audio.gd` 仍读取上一级已有的程序合成音效，本次未替换实际战斗声音。

统一规格：**WAV、PCM 16-bit、单声道、48 kHz、无循环**。已去直流偏移，按需裁剪头尾静音，保留起音并增加短淡入淡出，峰值约 −3 dBFS。峰值一致不代表主观响度一致，接入时仍需按场景调音量。

| 文件 | 用途 | 时长 | 授权 |
| --- | --- | --- | --- |
| `slash.wav` | 刀刃斩击，StarNinjas 的 sword.4 | 0.545 秒 | CC0 |
| `shotgun.wav` | 真实霰弹枪单发，Tabasco 的 shotty | 0.698 秒 | CC BY 3.0，需署名 |
| `finger_snap.wav` | 单次响指，Vinrax 的第 5 个样本 | 0.109 秒 | CC0 |
| `alternatives/slash_metal_06.wav` | 另一种金属斩击 | 0.477 秒 | CC0 |
| `alternatives/slash_whoosh.wav` | 挥刀破风 | 0.539 秒 | CC0 |
| `alternatives/slash_melee.wav` | 通用近战挥动 | 0.605 秒 | CC0 |
| `alternatives/finger_snap_03.wav` | 响指备选 3 | 0.095 秒 | CC0 |
| `alternatives/finger_snap_08.wav` | 响指备选 8 | 0.095 秒 | CC0 |

授权和作者见 [CREDITS.txt](CREDITS.txt)，精确来源、处理方式、时长和 SHA256 见 [sources.json](sources.json)。枪声网页标注 CC0，但下载包内 `creativecommons.txt` 明确标注 CC BY 3.0，因此按包内要求保留署名。原作者也说明枪声录音设备存在失真；标准化处理不代表修复了原始录音音色。

项目路径可直接用于 `AudioStreamPlayer.stream`，例如 `res://assets/audio/combat/downloaded/slash.wav`。如果后续选定这组声音，可在 `scripts/combat/combat_audio.gd` 的 `CLIPS` 表将三个预加载路径指向本目录，保留原有动作触发时点。

原始下载包、未加工样本、原始授权说明和网页快照：`artifacts/audio_sources/web_sfx_2026-10-18/`。可在 macOS 使用该目录的 `prepare_audio.py` 重新生成本组 WAV。

连续试听位于 `artifacts/qa/web-sfx-2026-10-18/preview_slash_shotgun_snap.wav`，顺序为斩击 → 开枪 → 响指，声音之间留有 0.8 秒间隔，试听整体降低约 4 dB。试听中枪声部分同样须保留 CC BY 3.0 署名。
