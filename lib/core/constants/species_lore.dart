/// 物种图鉴（C29 种植卡「翻面」背面文案，玄参 2026-10-05 需求）。
///
/// 单点真源：种植弹窗卡片背面展示该物种的**简短介绍 + 一个小故事**。
/// 内容为儿童友好的短文案（一句话介绍 + 三行内小故事）；缺物种 id 时回退
/// [kFallbackSpeciesLore]，未知物种（如老库自造）不会崩。
///
/// ⚠️ 文案改动只动本文件，UI 不写死任何物种文案。
library species_lore;

/// 一条物种图鉴文案。
class SpeciesLore {
  const SpeciesLore({required this.intro, required this.story});

  /// 一句话介绍（卡片背面第二行）。
  final String intro;

  /// 小故事（卡片背面正文，2~3 行内）。
  final String story;
}

/// 未知物种的兜底文案。
const SpeciesLore kFallbackSpeciesLore = SpeciesLore(
  intro: '花园里的小植物',
  story: '每种植物都有自己的小故事，等着你去发现哦。',
);

/// 物种 id → 图鉴文案（id 与 `plant_seed.dart` 物种表一致）。
const Map<String, SpeciesLore> kSpeciesLore = <String, SpeciesLore>{
  'species_sunflower': SpeciesLore(
    intro: '跟着太阳转头的金脸盘',
    story: '小向日葵每天仰着头看太阳，太阳去哪儿它就看哪儿，'
        '慢慢就长出了金灿灿的圆脸盘，成了花园里最亮的小太阳。',
  ),
  'species_tomato': SpeciesLore(
    intro: '一串串红红的小灯笼',
    story: '番茄小时候是绿色的，晒着晒着就害羞起来，'
        '脸越来越红，熟透了就像小灯笼一样挂在枝头。',
  ),
  'species_strawberry': SpeciesLore(
    intro: '带芝麻点的心形果子',
    story: '草莓身上布满了小芝麻——其实每粒「芝麻」都是一颗真正的小种子，'
        '一颗草莓能藏两百粒种子呢！',
  ),
  'species_moon_orchid': SpeciesLore(
    intro: '月光下才肯开放',
    story: '月光兰白天呼呼大睡，月亮升起才轻轻张开花瓣，'
        '把月光酿成淡淡的香气，陪小朋友甜甜入睡。',
  ),
  'species_star_flower': SpeciesLore(
    intro: '把星星别在花瓣上',
    story: '流星划过夜空时撒下了小星屑，星辰花用花瓣轻轻接住它们，'
        '所以它的花心里总是一闪一闪的。',
  ),
  'species_rainbow_fern': SpeciesLore(
    intro: '叶子会折出七彩光',
    story: '虹影蕨住在彩虹落脚的森林里，雨点挂在叶尖时会折出小小的彩虹，'
        '风一吹就满天飞舞。',
  ),
  'species_coral_orchid': SpeciesLore(
    intro: '像海底珊瑚一样粉',
    story: '传说它是海里的珊瑚上岸做的梦，梦里开出了粉色的花，'
        '从此叶子间总藏着小海螺的悄悄话。',
  ),
  'species_jade_hydrangea': SpeciesLore(
    intro: '许多小花抱成一个大球',
    story: '翡翠绣球由几十朵小花手拉手抱成一团，风再大也吹不散，'
        '因为它相信：团结的花最漂亮。',
  ),
};

/// 取物种图鉴文案（未知 id → [kFallbackSpeciesLore]）。
SpeciesLore speciesLoreOf(String speciesId) =>
    kSpeciesLore[speciesId] ?? kFallbackSpeciesLore;
