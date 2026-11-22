/// QA 独立差分复验 · 守卫大招真机反馈 bug1/3/5（严过关 / 独立编写）。
///
/// 🔴 与工程师新增的 4 个测试**完全独立**：所有期望值写死为字面量或独立推导，
/// 绝不 import 被测 Key 常量来「自己验自己」（防假绿）。三层防守：
///  · ① 纯函数真值表 / 几何独立算值（行为层，能被恒 true / 锚点回退变异转红）；
///  · ② widget 真实上树（说明卡 / 轻提示 / 能量格配色 / cast-fx Key 分离）；
///  · ③ 源码结构守卫（私有状态机的接线：**通知只在判据后触发**、**锚点 cast 当帧
///     抓取**、**cast 本体无坐标**、**fx 不含 cast 帧**——这些私有逻辑无法单测，
///     用源码守卫钉死，变异一旦落地即转红）。
///
/// 受控变异锚点（对应用例）：
///  · canStartFxStage → 恒 true       ⇒ T01 真值表转红
///  · notify 改成 cast 启动即调        ⇒ T02/T03 源码守卫转红
///  · cast 段挂回怪物区               ⇒ T06/T07 几何 + 源码守卫转红
///  · fx 段混进 cast 帧               ⇒ T08/T20 源码守卫转红
///  · 锚点改成「收到通知才抓」         ⇒ T04 源码守卫转红
///  · 能量格 X 锚点回退旧能量球        ⇒ T09 几何转红
///  · _litFill 改回橙黄               ⇒ T13/T14 转红
///  · 待机态改走门控引导              ⇒ T15/T17 转红
///  · 轻提示改回 showQuotaNotice      ⇒ T16/T18 转红
library qa_bugfix5_independent_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart'
    show AppLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show kUltimateFxCastLeadMs, kUltimateFxDurationMs;
import 'package:sunflower_time/core/di/providers.dart' show entitlementProvider;
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart'
    show GuardDayState, GuardDayStatus;
import 'package:sunflower_time/domain/entities/guard_thief.dart'
    show GuardThiefKind;
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleMonsterSnapshot, kGuardBattleFieldTravelPt;
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart'
    show GuardCardLayout;
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart'
    show GuardSceneCard;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_energy_bar.dart'
    show GuardUltimateEnergyBar;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show GuardUltimateFx, canStartFxStage;
import 'package:sunflower_time/presentation/shared/brief_notice.dart'
    show hideBriefNotice;
import 'package:sunflower_time/presentation/shared/premium_gate.dart'
    show onGuardUltimateTap;
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show ChildConfirmCard;

String _root() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/guard') || cwd.endsWith('\\test\\guard')
      ? Directory.current.parent.parent.path
      : cwd;
}

String _src(String rel) => File('${_root()}/$rel').readAsStringSync();

/// 去掉 `//` 行注释与 `/* */` 块注释，只留代码（避免注释里的字面量误伤守卫断言）。
String _codeOnly(String src) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < src.length) {
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

/// 截取 [from] 起到 [to] 之前的源码片段（找不到边界则整段返回，便于断言失败定位）。
String _between(String src, String from, String to) {
  final int a = src.indexOf(from);
  if (a < 0) return '';
  final int b = to.isEmpty ? src.length : src.indexOf(to, a + from.length);
  return b < 0 ? src.substring(a) : src.substring(a, b);
}

GuardTodayView _view(GuardPillMode mode, {required bool premium}) {
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-11-21',
      status: mode == GuardPillMode.fighting
          ? GuardDayStatus.fighting
          : GuardDayStatus.pending,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
      tutorialSeen: true,
    ),
    energyAvailable: 1,
    balance: 10,
    isPremium: premium,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  // ① bug5 · 两段串行：canStartFxStage 真值表（变异恒 true 必转红）
  // ═══════════════════════════════════════════════════════════════════════
  group('S1 · canStartFxStage 三假一真真值表（行为层）', () {
    test('仅「帧完成 ∧ 音轨完成」为真，其余三态全假', () {
      // 期望全部写死，不引用被测函数自证。
      expect(canStartFxStage(castFramesDone: false, castAudioDone: false),
          isFalse,
          reason: '两路都没完成：fx 绝不启动');
      expect(canStartFxStage(castFramesDone: true, castAudioDone: false), isFalse,
          reason: '帧完成但音轨未完：fx 不得抢跑（玄参「音效被卡断」根因）');
      expect(canStartFxStage(castFramesDone: false, castAudioDone: true), isFalse,
          reason: '音轨完成但帧未完：fx 不得抢跑（玄参「动作被卡断」根因）');
      expect(canStartFxStage(castFramesDone: true, castAudioDone: true), isTrue,
          reason: '两路都完成才放行第二段');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ② bug5 · 私有状态机接线守卫（变异「通知提前」必转红）
  // ═══════════════════════════════════════════════════════════════════════
  group('S2 · cast→fx 状态机源码接线（防假绿）', () {
    final String card = _src('lib/presentation/child/widgets/guard_scene_card.dart');

    test('T02 notify 由 2s timer 或 4s 判据兜底驱动，仍只发一次', () {
      // cast 启动段只允许**预约**通知，绝不允许直接通知 field（否则 fx 抢跑）。
      final String castFn = _between(card, 'Future<void> _castUltimate() async {', 'void _onCastFrameDone()');
      expect(castFn, isNotEmpty, reason: '_castUltimate 必须存在');
      expect(castFn.contains('notifyUltimateCastDone'), isFalse,
          reason: 'cast 启动即通知 = fx 抢跑：notify 只能走 _onFxStartDue 单点');
      expect(castFn.contains('const Duration(milliseconds: kUltimateFxCastLeadMs)'), isTrue,
          reason: '必须在 cast 第 2 秒预约提前挂 fx');
      expect(castFn.contains('_onFxStartDue'), isTrue,
          reason: '预约的回调必须是唯一的 notify 发点');

      // _onFxStartDue：闸门去重 + 唯一通知发点。
      final String startFn = _between(card, 'void _onFxStartDue() {', 'void _maybeEnterFxStage() {');
      expect(startFn.contains('if (_fxStageStarted || !mounted) return;'), isTrue,
          reason: '闸门去重：timer 与兜底判据同场只放行一次');
      expect(startFn.contains('_battleHandle.notifyUltimateCastDone();'), isTrue,
          reason: '经 handle 反向通知 field 挂 fx');

      // _maybeEnterFxStage 保留 4s 收尾判据，通知改为兜底调用同一方法。
      final String gateFn = _between(card, 'void _maybeEnterFxStage() {', '@override\n  Widget build');
      expect(gateFn.contains('canStartFxStage('), isTrue,
          reason: 'cast 4s 收尾仍须经 canStartFxStage 判据');
      expect(gateFn.contains('_onFxStartDue();'), isTrue,
          reason: '兜底也走同一个去重发点，不得再写第二处 notify');
      final int gateAt = gateFn.indexOf('canStartFxStage(');
      final int fallbackAt = gateFn.indexOf('_onFxStartDue();');
      expect(gateAt, greaterThanOrEqualTo(0));
      expect(fallbackAt, greaterThan(gateAt),
          reason: '判据调用必须写在兜底通知之前（顺序不可倒置）');
      final int calls = 'X$card'.split('_battleHandle.notifyUltimateCastDone();').length - 1;
      expect(calls, 1, reason: '全文件只允许一处反向通知，杜绝第二处提前触发');
    });

    test('T03 帧回调与音轨回调都汇聚到 _maybeEnterFxStage；无抢跑 delay', () {
      final String frameFn = _between(card, 'void _onCastFrameDone() {', 'void _onCastAudioDone()');
      final String audioFn = _between(card, 'void _onCastAudioDone() {', 'void _maybeEnterFxStage()');
      expect(frameFn.contains('_castFramesDone = true'), isTrue);
      expect(frameFn.contains('_maybeEnterFxStage()'), isTrue);
      expect(audioFn.contains('_castAudioDone = true'), isTrue);
      expect(audioFn.contains('_maybeEnterFxStage()'), isTrue);
      // cast 音轨 Timer 与帧序列仍同用一个 4s 时长常量；没有 ~/2 抢跑。
      expect(card.contains('const Duration(milliseconds: kUltimateFxDurationMs)'), isTrue);
      expect(card.contains('kUltimateFxDurationMs ~/ 2'), isFalse,
          reason: '旧实现 Future.delayed(duration~/2) 抢跑 fx 音轨，已删除');
      expect(kUltimateFxCastLeadMs, 2000,
          reason: '2026-11-24 真机反馈 4：总演出 6s = 4s + (4s − 2s)');
      expect(card.contains('const Duration(milliseconds: kUltimateFxCastLeadMs)'), isTrue,
          reason: 'cast 第 2 秒提前挂 fx 的单点常量必须真的接线');
      final String fxSrc = _codeOnly(
          _src('lib/presentation/child/widgets/guard_ultimate_fx.dart'));
      expect(fxSrc.contains('Future.delayed'), isFalse,
          reason: 'fx 段不得自带延时抢跑');
    });

    test('T04 锚点 cast 当帧先抓（walking 怪还活着），通知时只消费不重算', () {
      final String field = _src('lib/presentation/child/widgets/guard_battle_field.dart');
      // 抓取发生在 _onTick 的大招清场分支里，紧跟 castUltimate 事件产出。
      final String tick = _between(field, 'void _onTick(Duration elapsed) {', 'int _deathFxRemainMs()');
      expect(tick.contains('if (_pendingUltimate) {'), isTrue);
      expect(tick.contains('.where('), isTrue,
          reason: 'cast 前先从快照筛 walking 怪');
      expect(tick.contains('GuardBattleMonsterPhase.walking.id'), isTrue);
      final int castAt = tick.indexOf('_sim.castUltimate(');
      final int captureAt = tick.indexOf('_captureUltimateFxAnchor(');
      expect(castAt, greaterThanOrEqualTo(0));
      expect(captureAt, greaterThanOrEqualTo(0));
      expect(captureAt, greaterThan(castAt),
          reason: '必须在 castUltimate（怪全 dead）之前拿到 walking 列表后抓锚点');
      // 通知回调只读 _pendingUltimateFxAnchor，不再调用 ultimateFxAnchor 重算。
      final String doneFn = _between(field, 'void _onUltimateCastDone() {', 'int get fxClockMs');
      expect(doneFn.contains('final Offset? anchor = _pendingUltimateFxAnchor;'), isTrue);
      expect(doneFn.contains('_pendingUltimateFxAnchor = null;'), isTrue);
      expect(doneFn.contains('ultimateFxAnchor('), isFalse,
          reason: '收到通知才抓锚点 = 怪已全 dead 取不到；只能消费 cast 时抓的值');
      // 重开 / 卸载清待挂锚点。
      expect(field.contains('_pendingUltimateFxAnchor = null;'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ③ bug5 · 原位无多出战士（几何 + widget Key 分离）
  // ═══════════════════════════════════════════════════════════════════════
  group('S3 · cast 在战士本体 / fx 在怪物区', () {
    test('T05 ultimateCastRect == soldierRect；fx 锚点离战士中轴 > 30pt', () {
      const GuardCardLayout l = GuardCardLayout(390);
      // soldierRect 独立推导：房宽 88×1984/1118=156.17；左=156.17+2；中轴=+30。
      expect(l.soldierRect, l.ultimateCastRect,
          reason: '释放动作帧画在战士本体矩形，不在战场另起形象');
      expect(l.soldierRect.center.dx, closeTo(188.17, 0.1));

      const GuardBattleMonsterSnapshot mid = GuardBattleMonsterSnapshot(
        index: 0, kindId: 'm2', phaseId: 'walking',
        x: kGuardBattleFieldTravelPt / 2, y: 100, spawnMs: 0,
        hitsTaken: 0, stolen: 0,
      );
      final Offset fx = l.ultimateFxAnchor(<GuardBattleMonsterSnapshot>[mid]);
      expect((fx.dx - l.soldierRect.center.dx).abs(), greaterThan(30),
          reason: 'fx 挂怪物聚集区，离战士中轴 > 30pt');
      // 无 walking 怪回退也不落战士脚下。
      final Offset fallback = l.ultimateFxAnchor(<GuardBattleMonsterSnapshot>[]);
      expect((fallback.dx - l.soldierRect.center.dx).abs(), greaterThan(30));
    });

    test('T06 源码：soldierUltimateCast 无坐标/无 Positioned/fitHeight', () {
      final String art = _src('lib/presentation/child/widgets/guard_art.dart');
      final String fn = _between(art, 'static Widget soldierUltimateCast({', '/// 素材位：怪物行走帧');
      expect(fn, isNotEmpty);
      expect(fn.contains('Positioned'), isFalse,
          reason: 'cast 段若自带 Positioned/anchor 即挂回怪物区，战场多出战士');
      expect(fn.contains('anchor:'), isFalse);
      expect(fn.contains('fit: BoxFit.fitHeight'), isTrue);
      expect(fn.contains('kUltimateFxCastDir'), isTrue,
          reason: 'cast 用释放动作帧目录');
      expect(fn.contains('key: ultimateCastKey'), isTrue,
          reason: 'cast 播放器带本体 Key（常量字面量在下方单独钉死）');
      // Key 常量字面量写死，不 import 自证（变异改 Key 值即转红）。
      expect(art.contains("ultimateCastKey = Key('guardSoldierUltimateCast')"),
          isTrue);
    });

    testWidgets('T07 widget：cast 播放器带本体 Key；fx 段带 fx Key 且无 cast Key',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            SizedBox(
              width: 60,
              height: 60,
              child: GuardArt.soldierUltimateCast(playToken: 0, onComplete: () {}),
            ),
            const SizedBox(
              width: 120,
              height: 60,
              child: GuardUltimateFx(anchor: Offset(240, 70), uiScale: 1.0),
            ),
          ]),
        ),
      ));
      expect(find.byKey(const Key('guardSoldierUltimateCast')), findsOneWidget);
      expect(find.byKey(const Key('guardUltimateFxStage')), findsOneWidget);
      expect(find.byKey(const Key('guardSoldierUltimateCast')).evaluate().length,
          1,
          reason: '全树只有一个战士 cast Key，fx 段绝不能混入释放帧');
    });

    test('T08 源码：fx 段只用特效目录，不含 cast 目录 / cast Key', () {
      final String fx = _codeOnly(
          _src('lib/presentation/child/widgets/guard_ultimate_fx.dart'));
      // 精确钉 _fxFrames 初始化块：必须加载 effect 目录，绝不能是 cast 目录
      // （字面量或常量都不能出现）——否则 fx 段会渲染战士释放帧。
      final String framesInit = _between(fx, '_fxFrames = fxFrameAssets(', ');');
      expect(framesInit, isNotEmpty);
      expect(framesInit.contains('kUltimateFxEffectDir'), isTrue,
          reason: 'fx 段帧列表必须来自特效目录');
      expect(framesInit.contains('kUltimateFxEffectFrames'), isTrue);
      expect(framesInit.contains('kUltimateFxCastDir'), isFalse,
          reason: 'fx 段混入 cast 帧 = 战场多出战士');
      expect(framesInit.contains('soldier_ultimate'), isFalse,
          reason: 'fx 段不得指向 cast 帧目录字面量');
      expect(fx.contains('guardSoldierUltimateCast'), isFalse);
      expect(fx.contains("Key('guardUltimateFxStage')"), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ④ bug1 · 几何（X 分离 / Y 头顶 / 三档屏宽）
  // ═══════════════════════════════════════════════════════════════════════
  group('S4 · 能量格几何', () {
    test('T09 390 屏：X 锚 = 战士中轴 188.17，与旧能量点相距 ≈90pt', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Rect bar0 = l.ultimateBarRect(0);
      final Rect bar1 = l.ultimateBarRect(1);
      final Rect dot0 = l.energyDotRect(0);
      // 两格组中轴 = (bar0.center + bar1.center)/2 独立算值。
      final double groupCenter = (bar0.center.dx + bar1.center.dx) / 2;
      expect(groupCenter, closeTo(188.17, 0.1),
          reason: '能量格锚定战士中轴，不是房子中轴 78.09+20=98.09');
      // 旧能量点锚 = 房子中轴 78.09 + 旋钮 20 = 98.09；格锚与其相距 ≈90pt。
      // 注意能量点是「两点组」：dot0 中心 = 锚 −10 = 88.09，故格↔dot0 = 100.08。
      const double energyAnchorX = 98.09;
      expect((groupCenter - energyAnchorX).abs(), closeTo(90.08, 0.3),
          reason: '能量格与旧能量点链路锚 X 相距 ≈90pt');
      expect((groupCenter - dot0.center.dx).abs(), greaterThan(60),
          reason: '与左能量球实际圆心明显错开，两条链路不重叠');
      expect(bar0.overlaps(dot0), isFalse);
      // 总宽独立写死 2×20+3=43。
      expect(bar1.right - bar0.left, closeTo(43.0, 0.01));
    });

    test('T10 390 屏：能量格底 = 战士顶−5（不压脸），不越卡', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Rect soldier = l.soldierRect;
      final Rect bar = l.ultimateBarRect(0);
      expect(soldier.top, closeTo(42.0, 0.01));
      expect(bar.bottom, closeTo(37.0, 0.01));
      expect(bar.bottom, lessThan(soldier.top));
      expect(bar.left, greaterThanOrEqualTo(0));
    });

    test('T11 三档屏宽：贴头顶、总宽随 e 缩放、不越左右边界', () {
      for (final (double w, double s, double e) in <(double, double, double)>[
        (320, 1.0, 0.85),
        (390, 1.0, 1.0),
        (834, 1.6, 1.6),
      ]) {
        final GuardCardLayout l = GuardCardLayout(w, s);
        final Rect b0 = l.ultimateBarRect(0);
        final Rect b1 = l.ultimateBarRect(1);
        expect(l.soldierRect.top - b0.bottom, closeTo(5.0 * e, 0.01),
            reason: 'w=$w 头顶间距随 e 缩放');
        expect(b1.right - b0.left, closeTo(43.0 * e, 0.01));
        expect(b0.left, greaterThanOrEqualTo(0));
        expect(b1.right, lessThan(w));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ⑤ bug1 · 配色（_litFill 青绿非橙黄）
  // ═══════════════════════════════════════════════════════════════════════
  group('S5 · 能量格未满填充配色', () {
    testWidgets('T12 widget：未满格内条填充色 = 青绿 0xFF3FB6A8(α.75)，非橙黄',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 112,
              child: GuardUltimateEnergyBar(
                energy: UltimateEnergy(filledCells: 0, fractionMin: 15),
                unlocked: true,
                uiScale: 1.0,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final List<Color> colors = <Color>[];
      for (final Element el in find.byType(Container).evaluate()) {
        final Object w = el.widget;
        if (w is Container && w.decoration is BoxDecoration) {
          final Color? c = (w.decoration! as BoxDecoration).color;
          if (c != null) colors.add(c);
        }
      }
      // 期望青绿（独立写死）；变异回 0xFFF5B301 即转红。
      const Color expectedTeal = Color(0xFF3FB6A8);
      expect(colors, contains(expectedTeal.withValues(alpha: 0.75)));
      // 用 ARGB 位比较 RGB 低 24 位，避开已弃用的 r/g/b getter。
      const int orangeRGB = 0xF5B301;
      final bool hasOrange =
          colors.any((Color c) => (c.toARGB32() & 0xFFFFFF) == orangeRGB);
      expect(hasOrange, isFalse, reason: '不得出现橙黄 0xFFF5B301（与旧能量球混淆）');
    });

    testWidgets('T12b widget：免费档两格只画灰色虚线框，无亮色填充（真机反馈 2）',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 112,
              child: GuardUltimateEnergyBar(
                energy: UltimateEnergy(filledCells: 1, fractionMin: 0),
                unlocked: false,
                uiScale: 1.0,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      // 免费档不得残留青绿百分比条 / 金色实心（灰框里不能有亮色填充）。
      final List<Color> colors = <Color>[];
      for (final Element el in find.byType(Container).evaluate()) {
        final Object w = el.widget;
        if (w is Container && w.decoration is BoxDecoration) {
          final Color? c = (w.decoration! as BoxDecoration).color;
          if (c != null) colors.add(c);
        }
      }
      for (final Color c in colors) {
        expect((c.toARGB32() & 0xFFFFFF) == 0x3FB6A8, isFalse,
            reason: '免费档灰框内不得残留青绿填充');
      }
      // 两格各一个虚线画板，且尺寸非零（不留白、不塌缩）。
      final List<RenderCustomPaint> painters = find
          .descendant(
            of: find.byType(GuardUltimateEnergyBar),
            matching: find.byType(CustomPaint),
          )
          .evaluate()
          .map((Element e) => e.renderObject! as RenderCustomPaint)
          .toList();
      expect(painters.length, 2, reason: '免费档两格各画一个虚线框');
      for (final RenderCustomPaint p in painters) {
        expect(p.size, isNot(Size.zero), reason: '虚线框必须有非零尺寸');
      }
    });

    test('T13 源码：能量条文件 _litFill=0xFF3FB6A8，无 0xFFF5B301', () {
      final String bar = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_ultimate_energy_bar.dart'));
      expect(bar.contains('Color(0xFF3FB6A8)'), isTrue);
      expect(bar.contains('0xFFF5B301'), isFalse,
          reason: '橙黄是入场券能量球配色，大招能量格必须冷调青绿');
    });

    test('T13b 源码：免费档灰色虚线空框，买断档亮色路径保留（真机反馈 2）', () {
      final String bar = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_ultimate_energy_bar.dart'));
      // 免费档改走自绘虚线画师 + 中性灰，旧「Opacity 0.55 虚化」已弃用。
      expect(bar.contains('class _DashedCellPainter extends CustomPainter'),
          isTrue);
      expect(bar.contains('Color(0xFF9E9E9E)'), isTrue,
          reason: '免费档描边必须是中性灰，不得带金 / 青绿亮色');
      expect(bar.contains('opacity: unlocked ? 1.0 : 0.55'), isFalse,
          reason: '纯虚化观感不佳，真机反馈 2 已弃用');
      // 买断档原样路径必须还在（零回归）。
      expect(bar.contains('? _cell(context, t, layout, i)'), isTrue);
      expect(bar.contains(': _lockedCell(context, t, layout, i)'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ⑥ bug3 · 点击分态（待机说明卡 / 战斗轻提示）
  // ═══════════════════════════════════════════════════════════════════════
  group('S6 · 点击战士分态', () {
    Future<void> pumpCard(WidgetTester tester, {required bool premium}) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Localizations(
          locale: const Locale('zh'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 390,
                    child: GuardSceneCard(
                      view: _view(GuardPillMode.pendingPaid, premium: premium),
                      dayKey: '2026-11-21',
                      childId: 'qa-kid',
                      onStart: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    for (final bool premium in <bool>[false, true]) {
      testWidgets('T14 待机态（premium=$premium）：点战士弹居中说明卡，不弹买断引导',
          (WidgetTester tester) async {
        await pumpCard(tester, premium: premium);
        await tester.tap(find.byKey(const Key('guardBattleSoldier')),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const Key('guardUltimateHelpCard')), findsOneWidget,
            reason: '待机态先讲玩法（免费/买断都弹）');
        expect(find.text('知道了'), findsOneWidget);
        expect(find.byType(ChildConfirmCard), findsNothing,
            reason: '待机态绝不弹买断引导卡');
      });
    }

    testWidgets('T15 战斗买断档 0 格：弹轻提示文案，1s 后淡出自清',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(ProviderScope(
        overrides: <Override>[
          entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: _Probe())),
        ),
      ));
      final BuildContext ctx = tester.element(find.byType(_Probe));
      int allowed = 0;
      onGuardUltimateTap(ctx, hasEnergy: false, onAllowed: () => allowed++);
      await tester.pump(const Duration(milliseconds: 200));
      expect(allowed, 0);
      // 文案字面量写死，不 import getter 自证。
      expect(find.text('请专注去获得能量吧'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.text('请专注去获得能量吧'), findsNothing,
          reason: '1s 保持 + 淡出自清，不是 2.8s 常驻');
      hideBriefNotice();
      await tester.pumpAndSettle();
    });

    test('T16 源码：待机分支先讲玩法；战斗分支才走门控 helper', () {
      final String card = _src('lib/presentation/child/widgets/guard_scene_card.dart');
      final String onTap = _between(card, 'onTap: () {', 'child: SizedBox(\n                        key: GuardSceneCard.soldierKey');
      expect(onTap.contains('if (!fighting) {'), isTrue);
      expect(onTap.contains('_showUltimateHelp(t);'), isTrue);
      expect(onTap.contains('onGuardUltimateTap('), isTrue);
      final int helpAt = onTap.indexOf('_showUltimateHelp(t);');
      final int gateAt = onTap.indexOf('onGuardUltimateTap(');
      expect(helpAt, lessThan(gateAt),
          reason: '先判待机态弹说明卡并 return，战斗态才落到门控');
      // 说明卡确实调用 showGuardUltimateHelpDialog。
      final String helpFn = _between(card, 'void _showUltimateHelp(AppLocalizations t) {', '// ── 常驻战士');
      expect(helpFn.contains('showGuardUltimateHelpDialog('), isTrue);
    });

    test('T17 源码：轻提示走 showBriefNotice，不再用 showQuotaNotice', () {
      final String gate = _src('lib/presentation/shared/premium_gate.dart');
      final String hintFn = _between(gate, 'void _showGuardUltimateEmptyHint(BuildContext context) {', '/// 付费引导卡片');
      expect(hintFn.contains('showBriefNotice('), isTrue);
      expect(hintFn.contains('guard_ultimate_empty_hint_light'), isTrue);
      expect(hintFn.contains('showQuotaNotice'), isFalse,
          reason: 'showQuotaNotice 是 2.8s 配额卡，不是 1s 淡出轻提示');
      // brief_notice 默认保持 1s。
      final String brief = _src('lib/presentation/shared/brief_notice.dart');
      expect(brief.contains('Duration(milliseconds: 1000)'), isTrue);
    });

    test('T18 说明卡源码：居中 + 知道了按钮 + 参数化文案（零硬编码中文）', () {
      final String dlg = _src(
          'lib/presentation/child/widgets/guard_ultimate_help_dialog.dart');
      expect(dlg.contains('showGeneralDialog'), isTrue);
      expect(dlg.contains('Center('), isTrue);
      expect(dlg.contains('required this.confirmLabel'), isTrue);
      expect(dlg.contains('Navigator.of(context).pop()'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ⑦ 契约：i18n / 常量 / 目录
  // ═══════════════════════════════════════════════════════════════════════
  group('S7 · 契约守护', () {
    test('T19 4 个新 i18n key 中英齐全 + generated 三件套一致', () {
      const List<String> keys = <String>[
        'guard_ultimate_help_title',
        'guard_ultimate_help_body',
        'guard_ultimate_help_confirm',
        'guard_ultimate_empty_hint_light',
      ];
      final String zh = _src('lib/l10n/app_zh.arb');
      final String en = _src('lib/l10n/app_en.arb');
      for (final String k in keys) {
        expect(zh.contains('"$k"'), isTrue, reason: 'zh 缺 key $k');
        expect(en.contains('"$k"'), isTrue, reason: 'en 缺 key $k');
        for (final String f in <String>[
          'lib/l10n/generated/app_localizations.dart',
          'lib/l10n/generated/app_localizations_zh.dart',
          'lib/l10n/generated/app_localizations_en.dart',
        ]) {
          expect(_src(f).contains(k), isTrue, reason: '$f 缺 getter $k');
        }
      }
    });

    test('T20 两段目录/常量独立：cast≠fx，帧数 27，时长 4000', () {
      final String p = _src('lib/core/constants/prd_params.dart');
      expect(p.contains("kUltimateFxCastDir = 'assets/guard/soldier_ultimate'"), isTrue);
      expect(p.contains("kUltimateFxEffectDir = 'assets/guard/ultimate_fx'"), isTrue);
      expect(p.contains('kUltimateFxCastFrames = 27'), isTrue);
      expect(p.contains('kUltimateFxEffectFrames = 27'), isTrue);
      expect(kUltimateFxDurationMs, 4000);
    });
  });
}

/// ProviderScope 内最小宿主，供门控 helper 取真实容器。
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
