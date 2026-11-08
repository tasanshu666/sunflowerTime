/// QA 独立验收（2026-11-08 新物种批）：**荷花 / 蓝莓** 接入的端到端独立复验。
///
/// ## 立场
/// 本文件**不复用**工程师本轮改过的任何断言口径，也不调用实现里的私有常量反推期望值：
///  · 期望值一律**写死独立常量**（27 帧 / 20 碎片 / 300 阳光 / 10 碎片 / 480h / 240h），
///    实现改了也不会「跟着一起改对」，改错必红；
///  · 资产验证走 **AssetManifest 实测**（证明「打进了包」），不走 `File()` 读磁盘
///    —— 磁盘有、pubspec 漏登记 = 真机静默缺图，是本项目吃过两次亏的经典坑；
///  · 头像卡布局验证用**真实渲染几何**（`getRect` 量卡片与尾行），不用实现里的行高常量。
///
/// ## 覆盖（对应验收单五条）
///  A. AssetManifest 打包实测：14 张静态图 / 6 个成长帧叶子目录各 27 帧连续 / 6 段 mp3；
///  B. 定价与成长时长单点派生：species_lotus / species_blueberry 的档位、时长与种下价；
///  C. 头像卡溢出（本轮 lib 改动最需独立验）：320×568 / 800×600 无溢出，
///     1024×1366 卡片不得被 `Flexible` 拉满（含实测高度数值），11 项均可滚动触达；
///  D. i18n 无残留：头像卡 10 物种英文全命中、选种卡背面图鉴英文无 CJK、zh 与 ARB 逐字一致；
///  E. 成长音效回退链：`growSfxAssetCandidates` 第一候选是物种专属且文件真实存在，
///     第二候选才是通用兜底。
library qa_new_species_lotus_blueberry_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/child_avatar.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ───────────────────────────────────────────────────────────────────────────
// 独立期望值（硬常量，**不从实现反推**）
// ───────────────────────────────────────────────────────────────────────────

/// 新物种：中文名 / speciesId / 资产目录名（玄参 2026-11-08 物种定义）。
const Map<String, String> _kNewSpeciesIdByDir = <String, String>{
  'lotus': 'species_lotus',
  'blueberry': 'species_blueberry',
};

/// 每个物种的静态图**恰好 7 张**（成株 / 幼苗 各 4 状态 + 各 3 缺省态）。
const List<String> _kStaticArtSuffixes = <String>[
  'adult',
  'adult_bloomed',
  'adult_dead',
  'adult_wilting',
  'sprout',
  'sprout_dead',
  'sprout_wilting',
];

/// 成长过渡目录名（素材交付目录，**硬写**，不读实现枚举）。
const List<String> _kTransitionDirs = <String>[
  'seed_to_sprout',
  'sprout_to_adult',
  'adult_to_bloomed',
];

/// 每段成长帧帧数（玄参交付 27 帧；写死 > 从实现常量取）。
const int _kFramesPerTransition = 27;

/// 头像卡选项 = 阳光 + 10 物种 = 11。
const int _kAvatarOptionCount = 11;

/// 英文物种名（10 种；硬写 ARB en 期望值，防止实现漏 i18n 也一起「自洽」）。
const Map<String, String> _kEnglishSpeciesName = <String, String>{
  'species_sunflower': 'Sunflower',
  'species_moon_orchid': 'Moon Orchid',
  'species_tomato': 'Tomato',
  'species_strawberry': 'Strawberry',
  'species_coral_orchid': 'Coral Ridge Orchid',
  'species_jade_hydrangea': 'Jade Hydrangea',
  'species_grape': 'Grape',
  'species_rose': 'Rose',
  'species_lotus': 'Lotus',
  'species_blueberry': 'Blueberry',
};

/// 中文物种名（10 种；zh 逐字比对用）。
const Map<String, String> _kChineseSpeciesName = <String, String>{
  'species_sunflower': '向日葵',
  'species_moon_orchid': '月光兰',
  'species_tomato': '番茄',
  'species_strawberry': '草莓',
  'species_coral_orchid': '珊瑚岭兰',
  'species_jade_hydrangea': '翡翠绣球',
  'species_grape': '葡萄',
  'species_rose': '玫瑰',
  'species_lotus': '荷花',
  'species_blueberry': '蓝莓',
};

/// CJK（汉字 + 扩展 A + 中日韩标点 + 全角符号）—— 英文文案里出现任一字符即残留。
final RegExp _kCjk = RegExp(
  r'[\u3400-\u4DBF\u4E00-\u9FFF\u3000-\u303F\uFF00-\uFFEF\u3040-\u30FF]',
);

// ───────────────────────────────────────────────────────────────────────────
// 工具
// ───────────────────────────────────────────────────────────────────────────

/// 工程根（`flutter test` 一般以工程根为 cwd；兼容从子目录运行）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  if (File('$cwd/pubspec.yaml').existsSync()) return cwd;
  Directory dir = Directory.current;
  for (int i = 0; i < 5; i++) {
    dir = dir.parent;
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
  }
  return cwd;
}

Map<String, dynamic> _readArb(String lang) {
  final File f = File('${_projectRoot()}/lib/l10n/app_$lang.arb');
  expect(f.existsSync(), isTrue, reason: 'ARB 缺失：${f.path}');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

PlantSpecies _species(String id) =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == id);

// ───────────────────────────────────────────────────────────────────────────
// 最小 Fake 仓储（只为本文件的定价探针服务，不依赖 Drift）
// ───────────────────────────────────────────────────────────────────────────

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepo implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 0;
  @override
  Future<double> balance() async => 0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}

class _FakeFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async =>
      const FocusStats(totalFocusMinutes: 0, totalSessions: 0, totalValidDays: 0);
}

class _FakePlantRepo implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

/// 走**生产计价单点** `PlantGrowthService.plantPaymentOptions`（不自己复算倍率）。
PlantGrowthService _pricingService() {
  final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
  return PlantGrowthService(
    plants: _FakePlantRepo(),
    focus: _FakeFocusRepo(),
    ledger: _FakeSunlightRepo(),
    settings: _FakeSettingsRepo(),
    bloomRewards: bloom,
  );
}

// ───────────────────────────────────────────────────────────────────────────
// 头像卡宿主（直接挂 showChildAvatarPickerDialog，独立于「我的」页整页链路）
// ───────────────────────────────────────────────────────────────────────────

const ValueKey<String> _kDialogKey = ValueKey<String>('child_avatar_dialog');

Future<void> _pumpAvatarCard(
  WidgetTester tester, {
  required Size logicalSize,
  required AppLanguage lang,
  Set<String> planted = const <String>{},
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppLocaleController.init(lang);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      child: Scaffold(
        body: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                showChildAvatarPickerDialog(
                  ctx,
                  currentAvatar: kChildAvatarSun,
                  plantedSpeciesIds: planted,
                  species: kSeedPlantSpecies,
                );
              },
              child: const Text('open-avatar-card'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open-avatar-card'));
  await tester.pump(); // 推入 Dialog 路由
  await tester.pumpAndSettle();
  expect(find.byKey(_kDialogKey), findsOneWidget,
      reason: '头像卡未打开：装配失败（后续断言会假绿，必须先卡住）');
}

/// 断言「第 11 项（蓝莓）」在当前视口下可经滚动触达：能 `ensureVisible` 到屏内、
/// 且真的可命中（不是被裁掉的半截）。
Future<void> _expectLastOptionReachable(
  WidgetTester tester, {
  required double viewportHeight,
}) async {
  final Finder last =
      find.byKey(const ValueKey<String>('avatar_option_species_blueberry'));
  expect(last, findsOneWidget, reason: '第 11 项（蓝莓）不在树内');
  await tester.ensureVisible(last);
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull, reason: '滚到第 11 项时不应抛异常');

  final Rect r = tester.getRect(last);
  // ignore: avoid_print
  print('[QA-reachable] 视口高 $viewportHeight：蓝莓选项 rect=$r');
  expect(r.top, greaterThanOrEqualTo(0.0),
      reason: '滚到眼前后不得超出屏幕顶部：top=${r.top}');
  expect(r.bottom, lessThanOrEqualTo(viewportHeight),
      reason: '滚到眼前后不得超出屏幕底部：bottom=${r.bottom}（视口 $viewportHeight）');
  expect(last.hitTestable(), findsOneWidget,
      reason: '第 11 项滚到眼前后必须可命中（≥44pt 触点且在视口内）');
}

// ───────────────────────────────────────────────────────────────────────────
// 选种卡（花园「选择要种的植物」弹窗）宿主 —— 供图鉴文案（卡背面）探针
// ───────────────────────────────────────────────────────────────────────────
Future<void> _pumpGardenPickDialog(
  WidgetTester tester, {
  required AppLanguage lang,
}) async {
  // 逻辑视口 390×844（iPhone 档），物理 = 逻辑 × dpr。
  tester.view.physicalSize = const Size(390 * 3.0, 844 * 3.0);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  AppLocaleController.init(lang);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  final InMemoryBloomRewardRepository bloom = InMemoryBloomRewardRepository();
  await bloom.setPremiumFragmentBalance(20);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepo()),
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepo()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepo()),
      bloomRewardRepositoryProvider.overrideWithValue(bloom),
    ],
    child: const MaterialApp(
      home: L10nScope(child: Scaffold(body: GardenPage(embedded: true))),
    ),
  ));

  // 有界帧推进（花园页有呼吸动画 → 不能用 pumpAndSettle）。
  bool ready = false;
  for (int i = 0; i < 90; i++) {
    if (find.byType(EmptyPot).evaluate().isNotEmpty) {
      ready = true;
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready, isTrue, reason: '花园页未渲染出空花盆（装配失败）');

  await tester.tap(find.byType(EmptyPot).first);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));

  // 防假绿：选种弹窗必须真的打开（否则后续「找不到荷花」的失败会被误读成 i18n 问题）。
  expect(find.byType(Dialog), findsWidgets, reason: '选种弹窗未打开（装配失败）');
}

/// 弹窗内全部 `Text` 的**渲染字符串**（树序）。
List<String> _dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Text),
    ))
    .map((Text t) => t.data ?? '')
    .where((String s) => s.isNotEmpty)
    .toList();

/// 把某物种选种卡翻到背面，返回卡背面 intro / story 的**渲染文本** + 本次布局异常。
///
/// 取文本的方式**不假设卡片内部结构**：翻面前后对弹窗内文本做集合差，
/// 新增文本恰为 `[翻回提示, intro, story]`（树序）—— 与实现布局解耦。
///
/// 布局异常**只收集、不在此处断言**：本 helper 服务于「文案内容」探针（D 组），
/// 布局缺陷由 X1 单独钉（内容正确 ≠ 布局正确，两件事分开判）。
Future<({String intro, String story, Object? layoutError})> _flipCardToBack(
  WidgetTester tester,
  String renderedName,
  String flipBackLabel,
) async {
  final Finder name = find.text(renderedName);
  expect(name, findsOneWidget, reason: '选种卡未渲染：$renderedName');
  await tester.ensureVisible(name);
  await tester.pump(const Duration(milliseconds: 100));

  final List<String> before = _dialogTexts(tester);

  // 点卡面空白 → 翻面（卡片自身 GestureDetector.onTap）。
  await tester.tap(name);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  // 翻面时若有布局溢出：drain 掉（否则会以「未处理异常」判失败），并记录在案。
  final Object? layoutError = tester.takeException();
  expect(find.text(flipBackLabel), findsWidgets,
      reason: '$renderedName 卡未翻到背面（找不到 "$flipBackLabel"）');

  final List<String> added =
      _dialogTexts(tester).where((String s) => !before.contains(s)).toList();
  final List<String> lore = added.where((String s) => s != flipBackLabel).toList();
  expect(lore, hasLength(2),
      reason: '卡背面应当恰有 intro + story 两段文案，实测新增文本=$added');
  return (intro: lore[0], story: lore[1], layoutError: layoutError);
}

// ───────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // A · AssetManifest 打包实测（pubspec 漏登记的经典坑）
  // ═══════════════════════════════════════════════════════════════════════
  group('A · AssetManifest 实测：新物种素材是否真的打进了包', () {
    late Set<String> manifest;

    setUpAll(() async {
      final AssetManifest m = await AssetManifest.loadFromAssetBundle(rootBundle);
      manifest = m.listAssets().toSet();
      expect(manifest, isNotEmpty, reason: '资产清单为空 → 清单链路已断，后续断言不可信');
    });

    test('A0 · 负向对照：磁盘有、pubspec 未声明的目录**不进包**（证明 A1 不是读磁盘假绿）',
        () {
      // `assets/_originals/**` 是设计稿备份（刻意不进包），磁盘上真实存在。
      // 若清单里能查到它，说明本文件的 manifest 断言口径可疑（例如实际在读磁盘）。
      const String undeclared =
          'assets/_originals/plants/lotus/species_lotus_adult.png';
      expect(File('${_projectRoot()}/$undeclared').existsSync(), isTrue,
          reason: '负向对照样本不在磁盘上，本用例失效：$undeclared');
      expect(manifest.contains(undeclared), isFalse,
          reason: '未在 pubspec 声明的目录居然进了包 —— 清单口径不可信');
    });

    test('A1 · 14 张静态图全部在包内（lotus 7 + blueberry 7）', () {
      final List<String> missing = <String>[];
      for (final MapEntry<String, String> e in _kNewSpeciesIdByDir.entries) {
        final String dir = e.key;
        final String id = e.value;
        for (final String suffix in _kStaticArtSuffixes) {
          final String path = 'assets/plants/$dir/${id}_$suffix.png';
          if (!manifest.contains(path)) missing.add(path);
        }
      }
      expect(missing, isEmpty,
          reason: '这些静态图**没有打进包**（pubspec 目录漏登记 / 文件名不符）：\n'
              '${missing.join('\n')}');
      // 恰好 7 张/物种：反向确认没有多出未登记的奇怪命名（清单里该目录下 png 计数）。
      for (final MapEntry<String, String> e in _kNewSpeciesIdByDir.entries) {
        final int n = manifest
            .where((String p) =>
                p.startsWith('assets/plants/${e.key}/') && p.endsWith('.png'))
            .length;
        expect(n, 7, reason: 'assets/plants/${e.key}/ 清单内 png 数应为 7，实际 $n');
      }
    });

    test('A2 · 6 个成长帧叶子目录各 27 帧、frame001~frame027 连续无缺号', () {
      final List<String> problems = <String>[];
      for (final String dir in _kNewSpeciesIdByDir.keys) {
        for (final String t in _kTransitionDirs) {
          final String prefix = 'assets/fx/grow/$dir/$t/frame';
          final List<String> got = manifest
              .where((String p) =>
                  p.startsWith(prefix) && p.endsWith('.webp'))
              .toList()
            ..sort();
          final List<String> expected = <String>[
            for (int i = 1; i <= _kFramesPerTransition; i++)
              '$prefix${i.toString().padLeft(3, '0')}.webp',
          ];
          if (got.length != _kFramesPerTransition) {
            problems.add('$dir/$t 帧数 ${got.length} ≠ $_kFramesPerTransition');
          } else if (!_listEquals(got, expected)) {
            problems.add('$dir/$t 帧名不连续/缺号：${got.take(3)}…${got.skip(got.length - 2)}');
          }
        }
      }
      expect(problems, isEmpty, reason: '成长帧打包不符合契约：\n${problems.join('\n')}');
    });

    test('A3 · 6 段成长音效 mp3 在包内', () {
      final List<String> expected = <String>[
        for (final String dir in _kNewSpeciesIdByDir.keys)
          for (final String t in _kTransitionDirs)
            'assets/audio/sfx/grow_${dir}_$t.mp3',
      ];
      expect(expected, hasLength(6));
      final List<String> missing =
          expected.where((String p) => !manifest.contains(p)).toList();
      expect(missing, isEmpty,
          reason: '这些成长音效**没有打进包**：\n${missing.join('\n')}');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B · 定价与成长时长走单点派生
  // ═══════════════════════════════════════════════════════════════════════
  group('B · 档位 / 成长时长 / 种下价（硬常量 20 / 300 / 10 / 480 / 240）', () {
    test('B1 · 荷花 = 精英（Rarity.rare）+ 480h/阶段', () {
      final PlantSpecies lotus = _species('species_lotus');
      expect(lotus.name, '荷花', reason: '落库基线名必须与物种定义一致');
      expect(lotus.rarity, Rarity.rare);
      expect(lotus.isPremium, isTrue, reason: '荷花在玄参定义里是精英档');
      expect(lotus.growthHoursPerStage, 480.0,
          reason: '荷花成长时长必须是 480h/阶段（硬常量）');
      expect(lotus.growthHoursPerStage, kPlantGrowthHoursPerStagePremium,
          reason: '必须走单点常量 kPlantGrowthHoursPerStagePremium（不是裸写数）');
      expect(lotus.subscriptionOnly, isFalse);
    });

    test('B2 · 蓝莓 = 普通（Rarity.common）+ 240h/阶段', () {
      final PlantSpecies blueberry = _species('species_blueberry');
      expect(blueberry.name, '蓝莓');
      expect(blueberry.rarity, Rarity.common);
      expect(blueberry.isPremium, isFalse);
      expect(blueberry.growthHoursPerStage, 240.0,
          reason: '蓝莓成长时长必须是 240h/阶段（硬常量）');
      expect(blueberry.growthHoursPerStage, kPlantGrowthHoursPerStageDefault);
      expect(blueberry.subscriptionOnly, isFalse);
    });

    test('B3 · 种下价：荷花**只能**碎片 20（无阳光 / 无免费选项）', () async {
      final PlantGrowthService svc = _pricingService();
      final List<PlantPaymentOption> opts =
          await svc.plantPaymentOptions(_species('species_lotus'));
      expect(opts.map((PlantPaymentOption o) => (o.kind, o.amount)).toList(),
          <(PlantCostKind, int)>[(PlantCostKind.fragments, 20)],
          reason: '精英档只允许碎片 20 一种支付方式（阳光 / 免费都不该出现）');
      expect(svc.fragmentCostOf(_species('species_lotus')), 20);
    });

    test('B4 · 种下价：蓝莓 = 300 阳光 或 10 碎片（二选一，无免费）', () async {
      final PlantGrowthService svc = _pricingService();
      final List<PlantPaymentOption> opts =
          await svc.plantPaymentOptions(_species('species_blueberry'));
      expect(opts.map((PlantPaymentOption o) => (o.kind, o.amount)).toList(),
          <(PlantCostKind, int)>[
            (PlantCostKind.sunlight, 300),
            (PlantCostKind.fragments, 10),
          ],
          reason: '普通档必须恰好「阳光 300 + 碎片 10」两项，顺序亦为口径顺序');
      expect(svc.fragmentCostOf(_species('species_blueberry')), 10);
      expect(opts.any((PlantPaymentOption o) => o.kind == PlantCostKind.free),
          isFalse,
          reason: '蓝莓不是初始物种，不得出现免费选项');
    });

    test('B5 · 新物种不污染既有物种：物种表 10 种且顺序末尾为 荷花 → 蓝莓', () {
      expect(kSeedPlantSpecies.length, 10);
      expect(
        kSeedPlantSpecies.map((PlantSpecies s) => s.id).toList(),
        <String>[
          'species_sunflower',
          'species_moon_orchid',
          'species_tomato',
          'species_strawberry',
          'species_coral_orchid',
          'species_jade_hydrangea',
          'species_grape',
          'species_rose',
          'species_lotus',
          'species_blueberry',
        ],
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C · 头像卡溢出（本轮 lib 改动：Column → Flexible(SingleChildScrollView)）
  // ═══════════════════════════════════════════════════════════════════════
  group('C · 头像卡在窄屏 / 默认 / 大视口下的布局与可触达性', () {
    List<String> allOptionKeys() => <String>[
          'avatar_option_$kChildAvatarSun',
          for (final PlantSpecies s in kSeedPlantSpecies) 'avatar_option_${s.id}',
        ];

    testWidgets('C1 · 窄屏 320×568：无 RenderFlex 溢出，11 个选项全部在树内',
        (WidgetTester tester) async {
      await _pumpAvatarCard(
        tester,
        logicalSize: const Size(320, 568),
        lang: AppLanguage.zh,
      );

      expect(tester.takeException(), isNull,
          reason: '320×568 下头像卡不得抛异常（含 RenderFlex overflowed）');
      final List<String> keys = allOptionKeys();
      expect(keys, hasLength(_kAvatarOptionCount));
      for (final String k in keys) {
        expect(find.byKey(ValueKey<String>(k)), findsOneWidget,
            reason: '窄屏下 $k 必须存在于树中（不允许被裁掉/丢弃）');
      }
      // 再滚一遍，确认滚动过程中也不溢出。
      await tester.drag(find.byType(SingleChildScrollView).last,
          const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '窄屏滚动后仍不得溢出');
    });

    testWidgets('C2 · 默认 800×600：无 RenderFlex 溢出，11 项同样可触达',
        (WidgetTester tester) async {
      await _pumpAvatarCard(
        tester,
        logicalSize: const Size(800, 600),
        lang: AppLanguage.zh,
      );
      expect(tester.takeException(), isNull,
          reason: '默认 800×600 下头像卡不得抛异常（含 RenderFlex overflowed）');
      for (final String k in allOptionKeys()) {
        expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: '$k 缺失');
      }
      // 800×600 也要求「第 11 项可触达」（此视口下可能已经一屏放下，仍走同一断言）。
      await _expectLastOptionReachable(tester, viewportHeight: 600);
    });

    testWidgets('C3 · 大视口 1024×1366：卡片高度不得被 Flexible 拉满（无大片空白）',
        (WidgetTester tester) async {
      await _pumpAvatarCard(
        tester,
        logicalSize: const Size(1024, 1366),
        lang: AppLanguage.zh,
      );
      expect(tester.takeException(), isNull);

      final Rect dialog = tester.getRect(find.byKey(_kDialogKey));
      final Rect lastOption = tester.getRect(
          find.byKey(const ValueKey<String>('avatar_option_species_blueberry')));
      // 视口可用高 = 1366 − insetPadding 上下 24×2。
      const double viewportHeight = 1366;
      const double availableHeight = viewportHeight - 48;
      // 卡内底部留白 = 卡片 bottom − 尾行 bottom（设计上 = 卡内 padding-bottom 22）。
      final double bottomGap = dialog.bottom - lastOption.bottom;

      // 实测值打到测试输出（交付报告要引用真实数值）。
      // ignore: avoid_print
      print('[QA-C3] 1024×1366 卡片实测：dialog=w${dialog.width}xh${dialog.height} '
          'bottom=${dialog.bottom} 尾行 bottom=${lastOption.bottom} '
          '卡内底部留白=${bottomGap.toStringAsFixed(2)} '
          '（视口可用高 ${availableHeight.toStringAsFixed(0)}）');

      expect(dialog.height, lessThan(availableHeight * 0.7),
          reason: '卡片被 Flexible 拉满了：height=${dialog.height} vs 可用 $availableHeight'
              '（内容不足时卡片必须按内容收缩，不得出现大片空白）');
      expect(dialog.height, greaterThan(200),
          reason: '卡片高度异常偏小（内容未渲染？）：${dialog.height}');
      expect(bottomGap, inInclusiveRange(10.0, 44.0),
          reason: '尾行之下出现多余空白：留白=${bottomGap.toStringAsFixed(2)}'
              '（设计值 ≈ 卡内 padding-bottom 22）');
    });

    testWidgets('C4 · 任意视口下第 11 项（蓝莓）可经滚动触达并可点',
        (WidgetTester tester) async {
      await _pumpAvatarCard(
        tester,
        logicalSize: const Size(320, 568),
        lang: AppLanguage.zh,
      );

      final Finder last =
          find.byKey(const ValueKey<String>('avatar_option_species_blueberry'));
      // 未种植 → 锁定态；先确认它在滚动视图内可被滚到眼前。
      await _expectLastOptionReachable(tester, viewportHeight: 568);

      // 锁定项可点 → 出提示（不静默），说明它真的可交互而不是被裁掉的半截。
      await tester.tap(last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(kChildAvatarLockedHint), findsOneWidget,
          reason: '第 11 项必须可交互（锁定态点击应给出提示）');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // D · i18n 无残留
  // ═══════════════════════════════════════════════════════════════════════
  group('D · i18n：英文无 CJK 残留、中文与 ARB zh 逐字一致', () {
    testWidgets('D1 · 英文头像卡：10 个物种名全部命中英文（含 Lotus / Blueberry）且无 CJK',
        (WidgetTester tester) async {
      await _pumpAvatarCard(
        tester,
        logicalSize: const Size(1024, 1366),
        lang: AppLanguage.en,
      );

      for (final MapEntry<String, String> e in _kEnglishSpeciesName.entries) {
        expect(find.text(e.value), findsOneWidget,
            reason: '英文下 ${e.key} 必须显示「${e.value}」');
      }
      // 中文名一个都不许出现（残留反证）。
      for (final String zh in _kChineseSpeciesName.values) {
        expect(find.text(zh), findsNothing, reason: '英文界面残留中文名「$zh」');
      }

      final Iterable<Text> texts = tester.widgetList<Text>(find.descendant(
        of: find.byKey(_kDialogKey),
        matching: find.byType(Text),
      ));
      final List<String> cjkHits = texts
          .map((Text t) => t.data ?? '')
          .where((String s) => _kCjk.hasMatch(s))
          .toList();
      expect(cjkHits, isEmpty,
          reason: '英文头像卡里出现 CJK 残留：$cjkHits');
    });

    testWidgets('D2 · 英文选种卡背面（荷花 / 蓝莓）：intro + story 为英文且无 CJK',
        (WidgetTester tester) async {
      final Map<String, dynamic> en = _readArb('en');
      await _pumpGardenPickDialog(tester, lang: AppLanguage.en);

      for (final MapEntry<String, String> e in _kNewSpeciesIdByDir.entries) {
        final String id = e.value;
        final String renderedName = _kEnglishSpeciesName[id]!;
        final ({String intro, String story, Object? layoutError}) lore =
            await _flipCardToBack(tester, renderedName, 'Tap to flip back');
        // 布局缺陷（英文长名卡背面头部溢出）由 X1 单独钉；此处只判「文案内容」。
        // ignore: avoid_print
        print('[QA-D2] $id 翻面 layoutError=${lore.layoutError ?? "none"}');

        expect(lore.intro, en['species_lore_${id.substring(8)}_intro'],
            reason: '$id 背面 intro 与 ARB en 不一致');
        expect(lore.story, en['species_lore_${id.substring(8)}_story'],
            reason: '$id 背面 story 与 ARB en 不一致');
        expect(_kCjk.hasMatch(lore.intro), isFalse,
            reason: '$id 英文 intro 含 CJK：${lore.intro}');
        expect(_kCjk.hasMatch(lore.story), isFalse,
            reason: '$id 英文 story 含 CJK：${lore.story}');
        // 英文文案必须真的是英文（至少含 ASCII 字母，防「空串 / 符号」假绿）。
        expect(RegExp(r'[A-Za-z]{3,}').hasMatch(lore.intro), isTrue);
        expect(RegExp(r'[A-Za-z]{3,}').hasMatch(lore.story), isTrue);
      }
    });

    testWidgets('D3 · 中文选种卡背面（荷花 / 蓝莓）：文案与 ARB zh 逐字一致',
        (WidgetTester tester) async {
      final Map<String, dynamic> zh = _readArb('zh');
      await _pumpGardenPickDialog(tester, lang: AppLanguage.zh);

      for (final MapEntry<String, String> e in _kNewSpeciesIdByDir.entries) {
        final String id = e.value;
        final String renderedName = _kChineseSpeciesName[id]!;
        final ({String intro, String story, Object? layoutError}) lore =
            await _flipCardToBack(tester, renderedName, '点此翻回正面');
        expect(lore.layoutError, isNull,
            reason: '中文名短，卡背面不应溢出（若这里也红，说明布局改动波及中文）');

        expect(lore.intro, zh['species_lore_${id.substring(8)}_intro'],
            reason: '$id 背面 zh intro 与 ARB zh 不逐字一致');
        expect(lore.story, zh['species_lore_${id.substring(8)}_story'],
            reason: '$id 背面 zh story 与 ARB zh 不逐字一致');
        expect(_kCjk.hasMatch(lore.intro), isTrue,
            reason: '中文 intro 居然没有汉字：${lore.intro}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // E · 成长音效回退链
  // ═══════════════════════════════════════════════════════════════════════
  group('E · 成长音效两级回退链（物种专属 → 通用兜底）', () {
    test('E1 · lotus + seed_to_sprout：第一候选 = grow_lotus_seed_to_sprout.mp3 且真实存在',
        () {
      final List<String> c = growSfxAssetCandidates(
        GrowTransition.seedToSprout,
        'lotus',
        AudioCue.growthSeedToSprout.assetPath,
      );
      expect(c, hasLength(2), reason: '候选链必须恰好两级');
      expect(c.first, 'assets/audio/sfx/grow_lotus_seed_to_sprout.mp3',
          reason: '第一候选必须是物种专属音效（否则永远走通用兜底 = 物种音效白交付）');
      expect(File('${_projectRoot()}/${c.first}').existsSync(), isTrue,
          reason: '第一候选文件不存在 → 运行期会静默回退到通用兜底：${c.first}');
      expect(c[1], 'assets/audio/sfx/grow_seed_to_sprout.mp3',
          reason: '第二候选必须是通用兜底 grow_{过渡}.mp3');
      expect(c[1].contains('lotus'), isFalse,
          reason: '第二候选不能是物种专属（那就没有兜底了）');
      expect(File('${_projectRoot()}/${c[1]}').existsSync(), isTrue,
          reason: '兜底文件也不存在 → 静默无声：${c[1]}');
    });

    test('E2 · 2 物种 × 3 过渡：第一候选全部指向物种专属且文件存在', () {
      final Map<GrowTransition, AudioCue> fallback = <GrowTransition, AudioCue>{
        GrowTransition.seedToSprout: AudioCue.growthSeedToSprout,
        GrowTransition.sproutToAdult: AudioCue.growthSproutToAdult,
        GrowTransition.adultToBloomed: AudioCue.growthAdultToBloomed,
      };
      final List<String> problems = <String>[];
      for (final String dir in _kNewSpeciesIdByDir.keys) {
        for (final MapEntry<GrowTransition, AudioCue> e in fallback.entries) {
          final List<String> c =
              growSfxAssetCandidates(e.key, dir, e.value.assetPath);
          final String expectedFirst =
              'assets/audio/sfx/grow_${dir}_${e.key.dirName}.mp3';
          if (c.first != expectedFirst) {
            problems.add('$dir/${e.key.dirName} 第一候选=${c.first} ≠ $expectedFirst');
          }
          if (!File('${_projectRoot()}/${c.first}').existsSync()) {
            problems.add('$dir/${e.key.dirName} 第一候选文件缺失：${c.first}');
          }
          if (c.last != e.value.assetPath) {
            problems.add('$dir/${e.key.dirName} 兜底=${c.last} ≠ ${e.value.assetPath}');
          }
        }
      }
      expect(problems, isEmpty, reason: '回退链不符合契约：\n${problems.join('\n')}');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // X · 已知缺陷（**红用例**，只报告不修实现）
  // ═══════════════════════════════════════════════════════════════════════
  group('X · 已知缺陷（红用例）：英文长名选种卡**背面头部**水平溢出', () {
    // 现象（实测，2026-11-08）：390×844 逻辑视口 + en，把选种卡翻到背面 →
    // `RenderFlex overflowed by N pixels on the right`（N 随英文名长度增长）。
    //   Sunflower 21 / Moon Orchid 48 / Strawberry 35 / Coral Ridge Orchid 141 /
    //   Jade Hydrangea 88 / **Blueberry 21** ；Tomato / Grape / Rose / Lotus = 0。
    // 归因：`garden_page.dart::_PlantTile._backFace` 的头部 Row
    //   = [icon, Text(名), Spacer, Text(翻回提示)] —— 名**没有** Flexible/Expanded，
    //   英文名一长就把 Row 顶出可用宽度。
    // 定性：**pre-existing（非本批引入）** —— garden_page.dart 本批未改动；
    //   且 8 物种时代的 Sunflower / Moon Orchid / Strawberry / Coral Ridge Orchid /
    //   Jade Hydrangea 同样溢出（同一 Row），与荷花/蓝莓无关。
    // 影响：新物种「蓝莓」EN 名 9 字符 → 同样中招（21px）：debug 露黄黑条，
    //   release 下「Tap to flip back」被裁；中文名短不受影响。
    testWidgets('X1 · en 下逐个翻 10 张选种卡背面：不得出现任何 RenderFlex 溢出',
        (WidgetTester tester) async {
      final Map<String, String> overflow = <String, String>{};
      for (final MapEntry<String, String> e in _kEnglishSpeciesName.entries) {
        await _pumpGardenPickDialog(tester, lang: AppLanguage.en);
        final ({String intro, String story, Object? layoutError}) lore =
            await _flipCardToBack(tester, e.value, 'Tap to flip back');
        if (lore.layoutError != null) {
          overflow[e.key] = '${lore.layoutError}';
        }
      }
      // 清掉最后一张卡留下的其它异常，避免误报为「未处理异常」。
      tester.takeException();
      expect(
        overflow,
        isEmpty,
        reason: '英文选种卡**背面头部 Row** 溢出（garden_page.dart::_backFace：'
            '名未包 Flexible）。实测：$overflow\n'
            '注：Sunflower 等 8 物种时代的老物种同样溢出 → 属既有缺陷，'
            '但新物种 blueberry 也在其中。',
      );
    });
  });
}

/// 极简列表相等（避免引入额外依赖）。
bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
