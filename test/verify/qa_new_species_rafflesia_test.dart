/// QA 独立验收（2026-11-20 大王花接入）：**大王花 species_rafflesia** 的端到端复验。
///
/// ## 立场
/// 与 `qa_new_species_lotus_blueberry_test.dart` 同款纪律：期望值一律**写死独立常量**
/// （480h / 20 碎片 / 7 张静态图 / 3 段 × 27 帧 / 3 条 mp3），不拿实现常量自反推；
/// 既查实现暴露的纯函数契约，也查磁盘真实素材与 pubspec 登记 + AssetManifest 进包。
library qa_new_species_rafflesia_test;

import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/species_l10n.dart';
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
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';

// ───────────────────────────────────────────────────────────────────────────
// 独立期望值（硬常量，**不从实现反推**）
// ───────────────────────────────────────────────────────────────────────────

/// 玄参 2026-11-20 物种定义。
const String _kSpeciesId = 'species_rafflesia';
const String _kDir = 'rafflesia';
const String _kZhName = '大王花';
const String _kEnName = 'Rafflesia';

/// 精英档口径（F144）：20 碎片、480h/阶段（硬写期望，不用实现常量代替）。
const int _kPremiumFragmentCost = 20;
const double _kPremiumGrowthHours = 480.0;

/// 静态图恰好 7 张。
const List<String> _kStaticSuffixes = <String>[
  'adult',
  'adult_bloomed',
  'adult_dead',
  'adult_wilting',
  'sprout',
  'sprout_dead',
  'sprout_wilting',
];

/// 成长过渡目录 + 通用兜底音效（素材交付目录名，硬写）。
const Map<String, String> _kTransitionFallback = <String, String>{
  'seed_to_sprout': 'assets/audio/sfx/grow_seed_to_sprout.mp3',
  'sprout_to_adult': 'assets/audio/sfx/grow_sprout_to_adult.mp3',
  'adult_to_bloomed': 'assets/audio/sfx/grow_adult_to_bloomed.mp3',
};

/// 每段 27 帧（玄参交付 2026-11-20）。
const int _kFramesPerTransition = 27;

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

PlantSpecies _rafflesia() =>
    kSeedPlantSpecies.firstWhere((PlantSpecies s) => s.id == _kSpeciesId);

void _expectFileExists(String rel, {String reason = ''}) {
  final File f = File('${_projectRoot()}/$rel');
  expect(f.existsSync(), isTrue, reason: '缺素材：$rel${reason.isEmpty ? '' : ' —— $reason'}');
  expect(f.lengthSync(), greaterThan(0), reason: '素材为空文件：$rel');
}

// ───────────────────────────────────────────────────────────────────────────
// 计价探针用最小 Fake 仓储（与 qa_new_species_lotus_blueberry_test 同款）
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

PlantGrowthService _pricingService() => PlantGrowthService(
      plants: _FakePlantRepo(),
      focus: _FakeFocusRepo(),
      ledger: _FakeSunlightRepo(),
      settings: _FakeSettingsRepo(),
      bloomRewards: InMemoryBloomRewardRepository(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // A · 实现契约（种子表 / i18n / 美术路径 / 成长音效路径）
  // ═══════════════════════════════════════════════════════════════════════
  group('A · 大王花接入的实现契约', () {
    test('A1 · kSeedPlantSpecies 含第 11 种大王花：精英档 + 480h + 不订阅限定', () {
      final List<PlantSpecies> hits = kSeedPlantSpecies
          .where((PlantSpecies s) => s.id == _kSpeciesId)
          .toList();
      expect(hits, hasLength(1), reason: '物种表必须恰好有一条 species_rafflesia');
      expect(kSeedPlantSpecies.length, 11, reason: '2026-11-20 起应为 11 种');
      expect(kSeedPlantSpecies.last.id, _kSpeciesId,
          reason: '大王花应追加在物种表末尾（展示顺序）');

      final PlantSpecies sp = hits.single;
      expect(sp.name, _kZhName, reason: '落库基线名');
      expect(sp.rarity, Rarity.rare);
      expect(sp.isPremium, isTrue, reason: '精英档 = Rarity.rare');
      expect(sp.growthHoursPerStage, _kPremiumGrowthHours,
          reason: '精英档 480h/阶段（硬期望）');
      expect(sp.baseCostHigh, 0);
      expect(sp.baseCostLow, 0);
      expect(sp.subscriptionOnly, isFalse);
    });

    test('A2 · 种下价：只能 20 碎片（无阳光 / 无免费）', () async {
      final PlantGrowthService svc = _pricingService();
      final PlantSpecies sp = _rafflesia();
      final List<PlantPaymentOption> opts = await svc.plantPaymentOptions(sp);
      expect(
        opts.map((PlantPaymentOption o) => (o.kind, o.amount)).toList(),
        <(PlantCostKind, int)>[(PlantCostKind.fragments, _kPremiumFragmentCost)],
        reason: '精英档只允许碎片 20 一种支付方式',
      );
      expect(svc.fragmentCostOf(sp), _kPremiumFragmentCost);
    });

    test('A3 · kKnownSpeciesIds / speciesNameOrNull：大王花中英文命中', () {
      expect(kKnownSpeciesIds, contains(_kSpeciesId));
      expect(kKnownSpeciesIds.length, 11);
      expect(speciesNameOrNull(_kSpeciesId, AppLocalizationsZh()), _kZhName);
      expect(speciesNameOrNull(_kSpeciesId, AppLocalizationsEn()), _kEnName);
      expect(speciesNameOrNull('species_no_such_plant', AppLocalizationsZh()),
          isNull,
          reason: '未知 id 仍须返回 null（兜底口径不变）');
    });

    test('A4 · PlantArtCandidates.forPlant：5 条候选路径 dir=rafflesia', () {
      expect(
        PlantArtCandidates.forPlant(
          speciesId: _kSpeciesId,
          stage: 'adult',
          status: 'bloomed',
        ),
        <String>[
          'assets/plants/rafflesia/species_rafflesia_adult_bloomed.webp',
          'assets/plants/rafflesia/species_rafflesia_adult.webp',
          'assets/plants/rafflesia/species_rafflesia.webp',
          'assets/plants/shared/shared_adult_bloomed.webp',
          'assets/plants/shared/shared_adult.webp',
        ],
      );
      expect(
        PlantArtCandidates.forPlant(
          speciesId: _kSpeciesId,
          stage: 'sprout',
          status: 'wilting',
        ).first,
        'assets/plants/rafflesia/species_rafflesia_sprout_wilting.webp',
      );
      expect(growSpeciesDir(_kSpeciesId), _kDir);
    });

    test('A5 · growSfxAssetCandidates：3 段物种专属路径 + 通用兜底', () {
      final Map<String, GrowTransition> byDir = <String, GrowTransition>{
        'seed_to_sprout': GrowTransition.seedToSprout,
        'sprout_to_adult': GrowTransition.sproutToAdult,
        'adult_to_bloomed': GrowTransition.adultToBloomed,
      };
      for (final MapEntry<String, String> e in _kTransitionFallback.entries) {
        final List<String> c = growSfxAssetCandidates(
          byDir[e.key]!,
          _kDir,
          e.value,
        );
        expect(c, hasLength(2), reason: '${e.key} 候选必须恰好两级');
        expect(c.first, 'assets/audio/sfx/grow_rafflesia_${e.key}.mp3',
            reason: '${e.key} 第一候选必须是大王花专属音效');
        expect(c.last, e.value, reason: '${e.key} 第二候选必须是通用兜底');
        expect(c.last.contains('rafflesia'), isFalse,
            reason: '${e.key} 兜底不能仍是物种专属');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B · 磁盘素材真实存在 + pubspec 登记
  // ═══════════════════════════════════════════════════════════════════════
  group('B · 大王花素材落盘与登记', () {
    test('B1 · 7 张静态图真实存在（2026-11-25 起为 WebP q95）', () {
      for (final String suffix in _kStaticSuffixes) {
        _expectFileExists('assets/plants/rafflesia/species_rafflesia_$suffix.webp');
      }
    });

    test('B2 · 3 段各 27 张 WebP、编号连续、目录内无 PNG 残留', () {
      for (final String t in _kTransitionFallback.keys) {
        final Directory dir =
            Directory('${_projectRoot()}/assets/fx/grow/rafflesia/$t');
        expect(dir.existsSync(), isTrue, reason: '缺目录：$t');
        for (int i = 1; i <= _kFramesPerTransition; i++) {
          _expectFileExists(
            'assets/fx/grow/rafflesia/$t/frame${i.toString().padLeft(3, '0')}.webp',
            reason: '第 $i 帧',
          );
        }
        final List<String> png = dir
            .listSync()
            .whereType<File>()
            .map((File f) => f.path)
            .where((String p) => p.endsWith('.png'))
            .toList();
        expect(png, isEmpty, reason: '$t 残留 PNG（代码只读 webp，会包体翻倍）：$png');
      }
    });

    test('B3 · 3 条成长音效 mp3 真实存在且非空', () {
      for (final String t in _kTransitionFallback.keys) {
        _expectFileExists('assets/audio/sfx/grow_rafflesia_$t.mp3');
      }
    });

    test('B4 · pubspec.yaml 登记 4 个新叶子目录（目录声明不递归）', () {
      final String pubspec =
          File('${_projectRoot()}/pubspec.yaml').readAsStringSync();
      for (final String dir in <String>[
        'assets/plants/rafflesia',
        'assets/fx/grow/rafflesia/seed_to_sprout',
        'assets/fx/grow/rafflesia/sprout_to_adult',
        'assets/fx/grow/rafflesia/adult_to_bloomed',
      ]) {
        expect(pubspec.contains('    - $dir/'), isTrue,
            reason: 'pubspec 漏登记「$dir/」= 真机静默缺图/缺帧');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // C · AssetManifest 实测（证明真的打进了包，不只是磁盘上有）
  // ═══════════════════════════════════════════════════════════════════════
  group('C · AssetManifest 进包实测', () {
    late Set<String> manifest;

    setUpAll(() async {
      final AssetManifest m = await AssetManifest.loadFromAssetBundle(rootBundle);
      manifest = m.listAssets().toSet();
      expect(manifest, isNotEmpty, reason: '资产清单为空 → 后续断言不可信');
    });

    test('C1 · 静态图 / 帧 / 音效全部在包内', () {
      final List<String> expected = <String>[
        for (final String s in _kStaticSuffixes)
          'assets/plants/rafflesia/species_rafflesia_$s.webp',
        for (final String t in _kTransitionFallback.keys)
          for (int i = 1; i <= _kFramesPerTransition; i++)
            'assets/fx/grow/rafflesia/$t/frame${i.toString().padLeft(3, '0')}.webp',
        for (final String t in _kTransitionFallback.keys)
          'assets/audio/sfx/grow_rafflesia_$t.mp3',
      ];
      expect(expected, hasLength(7 + 81 + 3));
      final List<String> missing =
          expected.where((String p) => !manifest.contains(p)).toList();
      expect(missing, isEmpty,
          reason: '这些资源没进包（pubspec 漏登记 / 扩展名错）：\n${missing.join('\n')}');
    });
  });
}
