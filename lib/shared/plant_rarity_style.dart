/// 植物**稀有度配色单点收口**（C63，2026-10-13 玄参反馈「精英植物要有颜色区分」）。
///
/// ## 为什么单点
/// 精英/普通的配色原本散落在各处字面量里（选种卡强调色、徽章底色…），
/// 现按项目「防孪生」总纪律收口到本文件 —— 任何按档位变色的 UI（选种卡 /
/// 花盆文字胶囊 / 植物属性卡）都从这里取色，**不得再写字面量**。
///
/// ## 口径（沿用既有，不新造）
///  · **精英**（`Rarity.rare` / `Rarity.legendary`）= **紫** `#7E57C2`；
///  · **普通**（`Rarity.common`）= **绿** `#5FA854`；
///  · 淡色底：精英 `#F3E5F5` / 普通 `#E8F5E9`（徽章、胶囊用）。
///
/// ⚠️ 与「植物碎片」的紫、「施肥」的绿**同色但语义不同**（那两处不是稀有度），
/// 故本文件只服务稀有度语义，不要把碎片/施肥也搬进来。
library plant_rarity_style;

import 'package:flutter/widgets.dart';

import '../domain/entities/enums.dart';

/// 精英（`rare` / `legendary`）强调色 —— 紫。
const Color kRarityEliteAccent = Color(0xFF7E57C2);

/// 普通（`common`）强调色 —— 绿。
const Color kRarityCommonAccent = Color(0xFF5FA854);

/// 精英淡底（徽章 / 徽标用）—— 淡紫。
const Color kRarityEliteTint = Color(0xFFF3E5F5);

/// 普通淡底（徽章用）—— 淡绿。
const Color kRarityCommonTint = Color(0xFFE8F5E9);

/// 精英植物**属性卡**底色（比 [kRarityEliteTint] 更淡，铺满整卡不抢内容）。
const Color kRarityEliteCardTint = Color(0xFFFBF7FE);

// ⚠️ C64 修订（2026-10-13 iPad 实测）：花盆文字胶囊**不再用淡紫底**——玄参口径
// 「只增加紫色描边就行了，底还用半透明白底就行」。故此处删掉原先的
// `kRarityElitePillColor`（唯一用点已改回半透明白 `_labelPillColor`），避免留死代码。

/// 是否精英档（`rare` / `legendary` 同属 UI 上的「精英」）。
bool isEliteRarity(Rarity rarity) =>
    rarity == Rarity.rare || rarity == Rarity.legendary;

/// 稀有度强调色（精英紫 / 普通绿）。
Color rarityAccent(Rarity rarity) =>
    isEliteRarity(rarity) ? kRarityEliteAccent : kRarityCommonAccent;

/// 稀有度淡底（精英淡紫 / 普通淡绿）。
Color rarityTint(Rarity rarity) =>
    isEliteRarity(rarity) ? kRarityEliteTint : kRarityCommonTint;
