# 罗兰「逻辑工作室」枪声音源

2026-10-18，从社区 Library of Ruina - Organized Assets 的 Audio / Sound Effects / Guests / Impurity / The Black Silence 1 下载两段WAV，原文件名与字节保持不变。

| 文件 | 音源 | 时长 | 格式 |
| --- | --- | --- | --- |
| `Roland_Revolver.wav` | 罗兰左轮枪声 | 1.180秒 | 44.1 kHz／16-bit／双声道PCM WAV |
| `Roland_Shotgun.wav` | 罗兰霰弹枪声 | 1.776秒 | 44.1 kHz／16-bit／双声道PCM WAV |

[逻辑工作室书页资料](https://library-of-ruina.fandom.com/zh/wiki/%E9%80%BB%E8%BE%91%E5%B7%A5%E4%BD%9C%E5%AE%A4)记录前两段的特效为 `BlackSilence_Revolver`、第三段为 `BlackSilence_Shotgun`。结合社区[罗兰音效目录](https://drive.google.com/drive/folders/1qd6WQIrNYT66D-MGH7KdvfmGh64KS9Mm)中的文件名，对应本目录两段枪声音源；本轮未与本地安装的原版游戏逐段比对。

文件已通过PCM WAV头、非空和SHA256一致性检查。2026-10-18用户选定后，`combat_audio.gd` 已用 `Roland_Shotgun.wav` 替换射击音效，播放音量维持−13 dB；左轮仍为备选。斩击与响指的文件、音量和触发不变。源文件链接与参数见 [sources.json](sources.json)，权利说明沿用 [RIGHTS.txt](../RIGHTS.txt)。

连续试听在 `artifacts/qa/ruina-roland-2026-10-18/试听_罗兰左轮_罗兰霰弹枪.wav`，顺序为左轮→霰弹枪；仅试听副本统一48 kHz单声道并降低6 dB，原始资源未改。原始下载及网页快照在 `artifacts/audio_sources/ruina_roland_2026-10-18/`。
