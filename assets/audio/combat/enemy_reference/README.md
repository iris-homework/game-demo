# 敌人攻击音效

2026-11-02按用户要求接入聊天中搜索并提供试听的两段素材。MP3保持公开预览的原始字节，并非原站原始WAV。完整来源、许可链接与SHA256见[sources.json](sources.json)。

- `monster_bite_lucasduff_467701.mp3`：LucasDuff，Freesound `monster bite`，CC0 1.0。用于变异鱼和行李潜伏客。
- `impact_strong_punch_mixkit_2155.mp3`：Mixkit `Impact of a strong punch`，Sound Effects Free License。用于诺斯左右手拍击。

播放器为`scripts/combat/combat_audio.gd`，SFX总线，各−12 dB。播放分别从0.38和0.04秒开始，跳过开头近静音；音频文件不裁剪或重编码。普通攻击与编排攻击逐段播放；格挡额外保留原合成金属反馈。爬墙线鼠按最新要求恢复现有挥砍声，保留原扑刺动作和特效。
