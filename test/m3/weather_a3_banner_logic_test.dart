/// 天气系统 A3 期 · 条幅**三态纯函数**穷举单测（V1~V5 + 文案单点映射）。
///
/// ## 为什么这些断言必须写在纯单测里
/// 三态判定是「4 种极端 × 动作判据 × 道具 × 会话缓存」的组合空间；只要它住在
/// widget / 页面里，就只能靠泵页面碰运气（还要被「今天到底是什么天气」绑架）。
/// `resolveWeatherBanner` 是零 IO / 零时钟 / 零 context 的纯函数 ⇒ 这里把
/// **9 种日型 × 4 组笛卡尔积**全部穷举一遍。
///
/// ## 期望值的来源（**独立于实现**）
/// · 「哪 4 种是极端日」= 方案 §9.1 与 `WeatherKind.isExtreme` 的口径；
/// · 「动作齐」按日型的规则 = 方案 §5.1 规则表（干旱看浇水、暴雨看施肥、
///   大风 / 极寒只看棚）；
/// · 「完成 = 动作 **且** 道具」= 方案 §9.3。
/// 本文件**不引用实现里的私有判据**（`_actionsComplete`），只喂入参与断言输出。
library weather_a3_banner_logic_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/weather_banner_logic.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_banner.dart';

/// 4 种极端日型（写死 —— 这是方案 §9.1 的覆盖域，不引用 `isExtreme` 自证）。
const List<WeatherKind> _kExtremeKinds = <WeatherKind>[
  WeatherKind.drought,
  WeatherKind.wind,
  WeatherKind.cold,
  WeatherKind.rainstorm,
];

/// 5 种温和日型（写死，同上）。
const List<WeatherKind> _kMildKinds = <WeatherKind>[
  WeatherKind.sunny,
  WeatherKind.breeze,
  WeatherKind.cloudy,
  WeatherKind.overcast,
  WeatherKind.lightRain,
];

/// 按日型取真源参数（`WeatherSystem.ofKind` 是纯查表，不涉及日期）。
WeatherDay _dayOf(WeatherKind kind) => WeatherSystem.ofKind(kind);

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // V1 · 覆盖域：9 日型 → 三态（4 极端出、5 温和不出）
  // ══════════════════════════════════════════════════════════════════════════
  group('V1 · 覆盖域', () {
    for (final WeatherKind kind in _kExtremeKinds) {
      test('${kind.name}：无动作无棚 ⇒ todo（条幅出）', () {
        final WeatherBannerState st = resolveWeatherBanner(
          day: _dayOf(kind),
          anyWateredToday: false,
          anyFertilizedToday: false,
          shelterBoughtToday: false,
          sessionDone: false,
        );
        expect(st.mood, WeatherBannerMood.todo, reason: '${kind.name} 是极端日');
        expect(st.kind, kind);
        expect(st.visible, isTrue);
        expect(st.shelterRefType, kind.shelterRefType,
            reason: '条幅给的 refType 必须与日型的道具一致');
        expect(st.shelterRefType, isNotNull);
      });
    }

    for (final WeatherKind kind in _kMildKinds) {
      test('${kind.name}：入参**任意组合**都必须是 none（温和日不问入参）', () {
        // 2^3 = 8 组「动作齐 / 施肥齐 / 有棚」组合 × 2 组 sessionDone = 16 次。
        for (int mask = 0; mask < 8; mask++) {
          for (final bool sessionDone in <bool>[false, true]) {
            final WeatherBannerState st = resolveWeatherBanner(
              day: _dayOf(kind),
              anyWateredToday: mask & 1 != 0,
              anyFertilizedToday: mask & 2 != 0,
              shelterBoughtToday: mask & 4 != 0,
              sessionDone: sessionDone,
            );
            expect(
              st.mood,
              WeatherBannerMood.none,
              reason: '${kind.name} 是温和日：mask=$mask sessionDone=$sessionDone '
                  '也必须 none（M-A3-2 / M-A3-3 的抓手）',
            );
            expect(st.visible, isFalse);
            expect(st.shelterRefType, isNull,
                reason: '温和日没有推荐道具');
          }
        }
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V2 · 完成判据 = 动作 **且** 道具（4 组笛卡尔积全覆盖）
  // ══════════════════════════════════════════════════════════════════════════
  group('V2 · 完成 = 动作齐 且 道具已买', () {
    // 干旱看浇水、暴雨看施肥 —— 这两种日型的动作判据不同，各跑一遍笛卡尔积。
    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.drought,
      WeatherKind.rainstorm,
    ]) {
      final bool drought = kind == WeatherKind.drought;
      // (动作, 道具) → 期望
      const Map<String, WeatherBannerMood> expectations = <String, WeatherBannerMood>{
        '动作齐 + 有棚': WeatherBannerMood.done,
        '动作齐 + 无棚': WeatherBannerMood.todo,
        '无动作 + 有棚': WeatherBannerMood.todo,
        '无动作 + 无棚': WeatherBannerMood.todo,
      };
      for (final MapEntry<String, WeatherBannerMood> e in expectations.entries) {
        test('${kind.name}：${e.key} ⇒ ${e.value.name}', () {
          final bool actionDone = e.key.startsWith('动作齐');
          final bool shelter = e.key.endsWith('有棚');
          final WeatherBannerState st = resolveWeatherBanner(
            day: _dayOf(kind),
            // 干旱的动作是浇水；暴雨的动作是施肥 —— 只点亮「对的那个」入参。
            anyWateredToday: drought && actionDone,
            anyFertilizedToday: !drought && actionDone,
            shelterBoughtToday: shelter,
            sessionDone: false,
          );
          expect(st.mood, e.value, reason: '${kind.name}：${e.key}');
        });
      }
    }

    test('干旱：**只施肥**不算动作齐（浇水与施肥不可互换）', () {
      expect(
        resolveWeatherBanner(
          day: _dayOf(WeatherKind.drought),
          anyWateredToday: false,
          anyFertilizedToday: true,
          shelterBoughtToday: true,
          sessionDone: false,
        ).mood,
        WeatherBannerMood.todo,
      );
    });

    test('暴雨：**只浇水**不算动作齐（暴雨浇水额度为 0，强制动作是施肥）', () {
      expect(
        resolveWeatherBanner(
          day: _dayOf(WeatherKind.rainstorm),
          anyWateredToday: true,
          anyFertilizedToday: false,
          shelterBoughtToday: true,
          sessionDone: false,
        ).mood,
        WeatherBannerMood.todo,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V3 · 大风 / 极寒不判动作（只看棚）
  // ══════════════════════════════════════════════════════════════════════════
  group('V3 · 大风 / 极寒只看棚', () {
    for (final WeatherKind kind in <WeatherKind>[
      WeatherKind.wind,
      WeatherKind.cold,
    ]) {
      test('${kind.name}：动作入参全 false，有棚 ⇒ done', () {
        expect(
          resolveWeatherBanner(
            day: _dayOf(kind),
            anyWateredToday: false,
            anyFertilizedToday: false,
            shelterBoughtToday: true,
            sessionDone: false,
          ).mood,
          WeatherBannerMood.done,
          reason: '${kind.name} 的强制动作就是「买棚」一件事 —— '
              '若动作入参参与判定，这里会恒 todo（M-A3-4）',
        );
      });

      test('${kind.name}：动作入参全 true，无棚 ⇒ todo（有动作也不能免棚）', () {
        expect(
          resolveWeatherBanner(
            day: _dayOf(kind),
            anyWateredToday: true,
            anyFertilizedToday: true,
            shelterBoughtToday: false,
            sessionDone: false,
          ).mood,
          WeatherBannerMood.todo,
        );
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V4 · sessionDone 优先，且**只对极端日生效**
  // ══════════════════════════════════════════════════════════════════════════
  group('V4 · sessionDone 优先级', () {
    test('极端日 + sessionDone ⇒ done（不需要任何账本事实）', () {
      for (final WeatherKind kind in _kExtremeKinds) {
        expect(
          resolveWeatherBanner(
            day: _dayOf(kind),
            anyWateredToday: false,
            anyFertilizedToday: false,
            shelterBoughtToday: false,
            sessionDone: true,
          ).mood,
          WeatherBannerMood.done,
          reason: '${kind.name}：完成瞬间必须立刻切态（不等异步账本查询）',
        );
      }
    });

    test('温和日 + sessionDone ⇒ 仍 none（内存 Set 不许点亮温和日）', () {
      for (final WeatherKind kind in _kMildKinds) {
        expect(
          resolveWeatherBanner(
            day: _dayOf(kind),
            anyWateredToday: true,
            anyFertilizedToday: true,
            shelterBoughtToday: true,
            sessionDone: true,
          ).mood,
          WeatherBannerMood.none,
          reason: '${kind.name}：M-A3-3 的抓手',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // V5 · 幂等重算（事实不变时结果恒定；与「查询顺序」无关）
  // ══════════════════════════════════════════════════════════════════════════
  group('V5 · 幂等重算', () {
    test('同一组事实连续调用 3 次，结果恒定（账本 append-only ⇒ 重算幂等）', () {
      for (final WeatherKind kind in _kExtremeKinds) {
        final List<WeatherBannerMood> moods = <WeatherBannerMood>[
          for (int i = 0; i < 3; i++)
            resolveWeatherBanner(
              day: _dayOf(kind),
              anyWateredToday: true,
              anyFertilizedToday: true,
              shelterBoughtToday: true,
              sessionDone: false,
            ).mood,
        ];
        expect(moods, <WeatherBannerMood>[
          WeatherBannerMood.done,
          WeatherBannerMood.done,
          WeatherBannerMood.done,
        ], reason: '${kind.name}：重算必须幂等');
      }
    });

    test('「先买棚后做动作」与「先做动作后买棚」结果相同（无隐藏顺序依赖）', () {
      WeatherBannerState stepwise = resolveWeatherBanner(
        day: _dayOf(WeatherKind.drought),
        anyWateredToday: false,
        anyFertilizedToday: false,
        shelterBoughtToday: true,
        sessionDone: false,
      );
      expect(stepwise.mood, WeatherBannerMood.todo);
      stepwise = resolveWeatherBanner(
        day: _dayOf(WeatherKind.drought),
        anyWateredToday: true,
        anyFertilizedToday: false,
        shelterBoughtToday: true,
        sessionDone: false,
      );
      expect(stepwise.mood, WeatherBannerMood.done);

      final WeatherBannerState reverse = resolveWeatherBanner(
        day: _dayOf(WeatherKind.drought),
        anyWateredToday: true,
        anyFertilizedToday: false,
        shelterBoughtToday: true,
        sessionDone: false,
      );
      expect(reverse.mood, stepwise.mood);
    });

    test('不同日型的结论互不串台（同入参、不同 kind ⇒ 各自独立）', () {
      expect(
        resolveWeatherBanner(
          day: _dayOf(WeatherKind.sunny),
          anyWateredToday: false,
          anyFertilizedToday: false,
          shelterBoughtToday: false,
          sessionDone: false,
        ).mood,
        WeatherBannerMood.none,
      );
      expect(
        resolveWeatherBanner(
          day: _dayOf(WeatherKind.drought),
          anyWateredToday: false,
          anyFertilizedToday: false,
          shelterBoughtToday: false,
          sessionDone: false,
        ).mood,
        WeatherBannerMood.todo,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 文案单点映射（8 个 ARB 键：4 todo + 4 done；温和日不给文案）
  // ══════════════════════════════════════════════════════════════════════════
  group('文案映射（8 键 · zh/en 都不为空）', () {
    final AppLocalizations zh = AppLocalizationsZh();
    final AppLocalizations en = AppLocalizationsEn();

    for (final WeatherKind kind in _kExtremeKinds) {
      test('${kind.name}：todo / done 在 zh 与 en 都有非空文案', () {
        final WeatherBannerState todo = resolveWeatherBanner(
          day: _dayOf(kind),
          anyWateredToday: false,
          anyFertilizedToday: false,
          shelterBoughtToday: false,
          sessionDone: false,
        );
        final WeatherBannerState done = resolveWeatherBanner(
          day: _dayOf(kind),
          anyWateredToday: true,
          anyFertilizedToday: true,
          shelterBoughtToday: true,
          sessionDone: false,
        );
        expect(todo.mood, WeatherBannerMood.todo);
        expect(done.mood, WeatherBannerMood.done);
        for (final AppLocalizations t in <AppLocalizations>[zh, en]) {
          expect(weatherBannerTextOf(todo, t), isNotEmpty,
              reason: '${kind.name} todo 文案不得为空');
          expect(weatherBannerTextOf(done, t), isNotEmpty,
              reason: '${kind.name} done 文案不得为空');
          // 🔴 **不许 ellipsis**：文案本体不得自带 `…`（渲染层也不许加，
          //    见 `weather_banner.dart` 的 `overflow: clip` + FittedBox）。
          expect(weatherBannerTextOf(todo, t).contains('…'), isFalse);
          expect(weatherBannerTextOf(done, t).contains('…'), isFalse);
        }
        // 中文档与英文档必须不同（防「en 漏翻，直接抄了中文」）。
        expect(weatherBannerTextOf(todo, zh),
            isNot(weatherBannerTextOf(todo, en)));
        expect(weatherBannerTextOf(done, zh),
            isNot(weatherBannerTextOf(done, en)));
      });
    }

    test('温和日：文案为空串（条幅根本不渲染，避免「空条幅」被当成合法态）', () {
      for (final WeatherKind kind in _kMildKinds) {
        final WeatherBannerState st = resolveWeatherBanner(
          day: _dayOf(kind),
          anyWateredToday: true,
          anyFertilizedToday: true,
          shelterBoughtToday: true,
          sessionDone: true,
        );
        expect(weatherBannerTextOf(st, zh), isEmpty);
        expect(weatherBannerTextOf(st, en), isEmpty);
      }
    });
  });
}
