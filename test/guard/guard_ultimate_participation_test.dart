/// 🔴 C128（玄参 2026-11-22 真机反馈）：两次大招、零普攻通关的场，结算卡
/// 误显示「守卫失败，怪物偷走了阳光」并误扣 −3。
///
/// 根因（定位结论）：参战判定原本只看 sim `hasFired`（开火才置位），大招
/// 参战不计数 ⇒ 只放大招通关的场被误标「未参战」，走了 C120-13 的
/// 「未开火固定惩罚」分支（标题切失败文案 + 恒 −3 + `claim` 短路必得阳光）。
///
/// 修复（纯表现层，sim 域一个字节不动）：L4 field 在终局回调时把参战判据
/// 扩为 `hasFired || ultimateKillCount > 0`，改名 `didAttack` 沿
/// field → scene card → page → result card 透传；domain `claim(hasFired:)`
/// 参数名保留历史口径，语义已扩（见 guard_service.dart 文档）。
///
/// 本文件用**独立期望值**钉住三件事：
///  ① sim 域事实：只用大招通关的场 = victory + `hasFired == false` +
///     `ultimateKillCount > 0`（这是修复所依赖的 sim 契约，若 sim 行为变化
///     必须先回来改 field 判据）；
///  ② 表现层判据：`didAttack = hasFired || ultimateKillCount > 0` 对
///     「大招通关场」为 true、对「整场挂机到点撤退场」为 false（两分支同源）；
///  ③ 结算卡渲染：按 ② 的 didAttack 喂卡 ⇒ 大招通关场显示成功标题 + 正数
///     阳光（绝不出现「守卫失败」/红色 −3）；挂机场显示失败标题 + −3（既有
///     C120-13 口径不回归）。
///
/// 期望值全部手写死（文案 / 数字 / 颜色来自 l10n 与 C120-13 口径表），
/// 与被测实现无自证循环。
library guard_ultimate_participation_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';

const String _dayKey = '2026-11-22';
const String _childId = 'participation-kid';

/// 5 只怪、hitsToKill=99（普通子弹极难打死）、无闪避：清场只能归因于大招。
GuardBattleScript _script() {
  return GuardBattleScript(
    windowMs: 30000,
    monsters: <GuardBattleMonsterSpec>[
      for (int i = 0; i < 5; i++)
        GuardBattleMonsterSpec(
          index: i,
          kind: GuardBattleMonsterKind.m1,
          spawnMs: 0,
          speedPtPerSec: 15,
          dodgeProb: 0.0,
          hitsToKill: 99,
          steal: 1,
          laneYPt: 100 + i * 4,
          wobbleAmpPt: 0,
          wobbleFreqHz: 0,
          wobblePhaseRad: 0,
        ),
    ],
  );
}

GuardBattleSim _sim() => GuardBattleSim(
      script: _script(),
      dayKey: _dayKey,
      childId: _childId,
    );

GuardTodayView _view({int winSun = 4}) {
  return GuardTodayView(
    mode: GuardPillMode.pendingFree,
    state: GuardDayState(
      dayKey: _dayKey,
      status: GuardDayStatus.pending,
      thiefKind: null,
      winSun: winSun,
    ),
    energyAvailable: 0,
    balance: 20,
  );
}

Future<AppLocalizations> _loadZh() async =>
    AppLocalizations.delegate.load(const Locale('zh'));

Widget _shell(Widget child) {
  return Localizations(
    locale: const Locale('zh'),
    delegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ),
  );
}

/// 阳光卡上的数字（+N / −N / N）。
String _sunNumber(WidgetTester tester) {
  final Iterable<String> texts = find
      .descendant(
        of: find.byKey(GuardResultCard.sunRewardKey),
        matching: find.byType(Text),
      )
      .evaluate()
      .map((Element e) => (e.widget as Text).data ?? '');
  return texts.firstWhere(
    (String s) =>
        s.startsWith('+') ||
        s.startsWith('−') ||
        (s.length <= 2 && int.tryParse(s) != null),
  );
}

/// 阳光卡上的数字颜色。
Color _sunColor(WidgetTester tester) {
  final Iterable<Text> texts = find
      .descendant(
        of: find.byKey(GuardResultCard.sunRewardKey),
        matching: find.byType(Text),
      )
      .evaluate()
      .map((Element e) => e.widget as Text);
  return texts
      .firstWhere((Text t) =>
          (t.data ?? '').startsWith('+') ||
          (t.data ?? '').startsWith('−') ||
          ((t.data ?? '').length <= 2 && int.tryParse(t.data ?? '') != null))
      .style!
      .color!;
}

void main() {
  group('C128 参战判据（真机：两次大招零普攻通关被误判守卫失败）', () {
    test('① sim 契约：只用大招通关 = victory + hasFired=false + ultimateKillCount=5',
        () {
      final GuardBattleSim sim = _sim();
      sim.step(1000, <int>[]); // 全部入场 walking（未开火）
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events); // 一发大招清完 walking 怪

      expect(sim.phase, GuardBattlePhase.victory,
          reason: 'walking 全清 ⇒ 判胜（既有 P0-05 契约）');
      expect(sim.endReason, GuardBattleEndReason.allDead);
      expect(sim.hasFired, isFalse,
          reason: '🔴 根因事实：大招参战不置位 hasFired（修复所依赖的 sim 契约）');
      expect(sim.ultimateKillCount, 5,
          reason: '大招参战只在 ultimateKillCount 里');
      expect(sim.stolenSun, 0, reason: '怪从未到门 ⇒ 被偷合计 0');
    });

    test('① sim 契约（对照组）：整场挂机到点撤退 = hasFired=false +大招击杀 0',
        () {
      final GuardBattleSim sim = _sim();
      // 逐步推进到窗口结束：不发 fire、不放大招。
      for (int t = 100; t <= 30000; t += 100) {
        sim.step(t, <int>[]);
        if (sim.isOver) break;
      }
      expect(sim.isOver, isTrue);
      expect(sim.endReason, GuardBattleEndReason.windowExpired);
      expect(sim.hasFired, isFalse);
      expect(sim.ultimateKillCount, 0,
          reason: '全场零攻击 ⇒ 大招击杀数也是 0（真正未参战）');
    });

    test('② 表现层判据：didAttack = hasFired || ultimateKillCount > 0', () {
      // 大招通关场（field 终局时将按同一判据回调 didAttack=true）。
      final GuardBattleSim win = _sim();
      win.step(1000, <int>[]);
      win.castUltimate(1000, <GuardBattleEvent>[]);
      final bool didAttackWin = win.hasFired || win.ultimateKillCount > 0;
      expect(didAttackWin, isTrue,
          reason: '🔴 C128 修复核心：只用大招通关的场必须算「参战」');

      // 挂机到点撤退场（未参战，维持 C120-13 惩罚口径）。
      final GuardBattleSim idle = _sim();
      for (int t = 100; t <= 30000; t += 100) {
        idle.step(t, <int>[]);
        if (idle.isOver) break;
      }
      final bool didAttackIdle = idle.hasFired || idle.ultimateKillCount > 0;
      expect(didAttackIdle, isFalse,
          reason: '零攻击场仍算未参战（惩罚必达不回归）');
    });

    testWidgets('③ 大招通关场（didAttack=true）⇒ 成功标题 + 「+4」金色，绝不显示失败/−3',
        (WidgetTester tester) async {
      final AppLocalizations zh = await _loadZh();
      await tester.pumpWidget(
        _shell(
          GuardResultCard(
            view: _view(winSun: 4),
            l10n: zh,
            onCollect: () async => throw UnimplementedError(),
            stolenSun: 0, // 大招通关未到门 ⇒ 实扣 0（页面传 stolenCharged）
            didAttack: true, // ② 判据对大招通关场的取值
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('花园守卫成功，赶走了贪吃的小动物'), findsOneWidget,
          reason: '🔴 C128：只用大招通关的场 = 参战 ⇒ 成功标题（误显示「守卫失败」是本轮真机 bug）');
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsNothing,
          reason: '失败文案绝不出现');
      expect(_sunNumber(tester), '+4',
          reason: '参战场显示 +winSunToGrant（winSun=4），绝不允许 −3');
      expect(_sunColor(tester), const Color(0xFFB37400),
          reason: '金色 = 到账语义（红色 −N 是未参战专属）');
    });

    testWidgets('③ 对照组：挂机场（didAttack=false）⇒ 失败标题 + 「−3」红色（C120-13 不回归）',
        (WidgetTester tester) async {
      final AppLocalizations zh = await _loadZh();
      await tester.pumpWidget(
        _shell(
          GuardResultCard(
            view: _view(winSun: 4),
            l10n: zh,
            onCollect: () async => throw UnimplementedError(),
            stolenSun: 3, // 未参战惩罚：页面恒传 kGuardWinSunMin=3
            didAttack: false, // ② 判据对挂机场的取值
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '真正未参战场维持 C120-13 失败文案');
      expect(_sunNumber(tester), '−3',
          reason: '未参战惩罚恒 −3');
      expect(_sunColor(tester), const Color(0xFFB3261E),
          reason: '红色 = 被偷走的损失语义');
    });
  });
}
