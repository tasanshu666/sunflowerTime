奖励物美术资源目录（玄参 2026-09-27「奖励物图标化」；2026-10-03 种子分档修订）
=============================================================================

小朋友在花园里看到的花朵「头顶奖励图标」，由本目录的图片驱动；
**文件缺失时自动回退内置 Icons**，因此可随时补齐素材、无需改代码。

命名契约（丢进本目录即自动生效）：

  · sunlight.png          阳光（回退 Icons.wb_sunny）
  · fragment.png          植物碎片（回退 Icons.auto_awesome）
  · seed_common.png       种子 · 普通（**2026-10-03 新增**，玄参提供分档图）
  · seed_premium.png      种子 · 精英（**2026-10-03 新增**，玄参提供分档图）
  · seed.png              种子 · 通用（**保留作回退**：物种档位未知或分档图缺失时使用；
                          回退 Icons.eco）
  · seed_{speciesId}.png  （已废弃，C20 曾引入、未实际使用）

种子解析顺序（2026-10-03 C20 口径修订）：物种精英 → seed_premium.png；物种普通 →
seed_common.png；分档图缺失或档位未知 → seed.png；再缺失 → Icons.eco。
解析逻辑单点在 `bloom_reward_icons.dart` 的 `resolveRewardAsset`（护栏测试
`test/m3/reward_asset_resolve_test.dart`）。

规格建议：透明底 PNG，正方形，96×96 或 144×144（会按图标视觉尺寸缩放到 ~20px；
非正方形图按 cover 居中裁切，建议长宽比不超过 4:5）。

「历史遗留」的待收集奖励（本能力上线前登记、三列全零 = 未预先定奖）统一显示
通用礼包图标 Icons.card_giftcard，不使用本目录资源。
