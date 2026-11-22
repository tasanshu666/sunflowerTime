/// QA 独立差分守卫 · C128 三修复（严过关 / 独立编写，防假绿）。
///
/// 🔴 背景：受控变异实测发现工程师新增测试存在两处**自证式假绿**——
///  · participation 用例 ② 把判据公式复制进测试自证、③ 手动传 `didAttack:true`
///    未驱动 field 真实判据 ⇒ field:873 判据被改坏时 5 例仍全绿；
///  · held_walk 用例断言全为相对量（在动 / 同速）⇒ killMs 记账丢失
///    （Map 回退 Set、外推起点偏移）时窗口内速度不变，全绿。
/// 本文件用**源码结构守卫**钉死这些无法经行为层区分的私有接线，期望值
/// 全部独立写死，变异一旦落地即转红：
///  · M1 field 判据去掉 ultimateKillCount   ⇒ G1 红
///  · M5 记账 Map→Set / killMs 消费丢失     ⇒ G2 红
///  · M4 result_card noFireTitle 判据反转    ⇒ G3 红
library qa_c128_differential_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _root() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/guard') || cwd.endsWith('\\test\\guard')
      ? Directory.current.parent.parent.path
      : cwd;
}

String _src(String rel) => File('${_root()}/$rel').readAsStringSync();

/// 去掉 `//` 行注释与 `/* */` 块注释（注释里的公式/字面量不算实现）。
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

void main() {
  group('C128-G1 · 参战判据（field 真实公式 + 透传链）', () {
    test('field 终局判据逐字 = hasFired || ultimateKillCount > 0', () {
      final String code = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_battle_field.dart'));
      // 期望公式独立写死（不是经 sim 复算自证）：
      // `didAttack = _sim.hasFired || _sim.ultimateKillCount > 0;`
      expect(
        code.contains(
            'final bool didAttack = _sim.hasFired || _sim.ultimateKillCount > 0;'),
        isTrue,
        reason: '🔴 C128：只用大招通关（hasFired=false + ultimateKillCount>0）'
            '必须算参战；判据若退化回纯 hasFired，真机会误弹「守卫失败」',
      );
      // 判据结果必须传给终局回调（不许算了不用）。
      expect(code.contains('didAttack: didAttack'), isTrue,
          reason: '判据结果必须沿 _GameResult/onFinished 透传，不许局部丢弃');
    });

    test('透传链完整：scene_card → today_page → result_card + claim(hasFired:)', () {
      final String card = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_scene_card.dart'));
      expect(card.contains('void Function(int stolenSun, bool didAttack)? onBattleFinished'), isTrue);
      expect(card.contains('onBattleFinished?.call(stolenSun, didAttack)'), isTrue,
          reason: 'field 的 didAttack 必须原样转发页面');

      final String page = _codeOnly(
          _src('lib/presentation/child/pages/child_today_page.dart'));
      expect(page.contains('_onBattleFinished(int battleStolenSun, bool didAttack)'), isTrue);
      expect(page.contains('didAttack: didAttack'), isTrue,
          reason: '页面必须把 didAttack 传给结算卡');
      expect(page.contains('claim(hasFired: didAttack)'), isTrue,
          reason: '页面必须把 didAttack 传给 domain claim（未参战不发必得阳光）');

      final String result = _codeOnly(
          _src('lib/presentation/child/widgets/guard_result_card.dart'));
      expect(
        result.contains(
            'final bool noFireTitle = !widget.didAttack || widget.stolenSun > 0;'),
        isTrue,
        reason: '结算卡失败标题判据 = 未参战 或 被偷（真机反馈 4：开火但被偷也要'
            '判失败，否则与卡面被偷行自相矛盾；反转即回归）',
      );
      expect(result.contains('final bool noFire = !widget.didAttack;'), isTrue,
          reason: '未参战 −3 红色行同口径');
    });

    test('domain claim(hasFired:) 契约不动（参数名保留历史口径）', () {
      final String svc = _codeOnly(_src('lib/domain/services/guard_service.dart'));
      expect(svc.contains('bool hasFired = true,'), isTrue);
      expect(svc.contains('final int winSun = hasFired ? guardGrantWinSunOf(state) : 0;'), isTrue,
          reason: '未参战 ⇒ 不发必得阳光（C120-13 口径不回归）');
    });
  });

  group('C128-G2 · 大招 held 怪记账（killMs 必须记账且被消费）', () {
    test('field 记账 Map<int,int> + 渲染消费 killMs（Set 回退即假绿缺口）', () {
      final String code = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_battle_field.dart'));
      // ① 记账结构必须是 Map<index, 被清时刻>（Set 只保「不消失」，丢时刻）。
      expect(code.contains('final Map<int, int> _ultimateHeldMonsters = <int, int>{};'),
          isTrue,
          reason: '🔴 Map<int,int> 记「被清时刻」；回退 Set ⇒ 外推起点丢失，'
              '怪会瞬移到更靠门的位置（held_walk 相对量断言测不出，唯此守卫能抓）');
      // ② 被清时记账：index → ms。
      expect(code.contains('_ultimateHeldMonsters[e.monsterIndex] = ms;'), isTrue,
          reason: '清怪当帧必须记账被清时刻');
      // ③ 渲染时消费记账值（不许传 0 / 常量）。
      expect(code.contains('killMs: _ultimateHeldMonsters[m.index]!'), isTrue,
          reason: '外推起点必须取记账的被清时刻；传 0 = 从出生全程外推（假绿变异实测通过）');
      // ④ 判 held 行走态仍存在（C126 语义）。
      expect(code.contains('_ultimateHeldMonsters.containsKey(m.index)'), isTrue);
    });

    test('外推纯函数：档位速度来自 prd 常量 + 钳门口', () {
      final String code = _codeOnly(_src(
          'lib/presentation/child/widgets/guard_battle_field.dart'));
      final int fnAt = code.indexOf('static double _ultimateHeldWalkX(');
      expect(fnAt, greaterThanOrEqualTo(0), reason: '外推纯函数必须存在');
      final int nextFn = code.indexOf('bool get _ultimateActive', fnAt);
      final String fn = code.substring(fnAt, nextFn > 0 ? nextFn : code.length);
      // 三档速度必须引用 prd 常量（写死 0 = 冻结回归；写死别的数 = 速度漂移）。
      expect(fn.contains('kGuardMonsterSpeedM1'), isTrue);
      expect(fn.contains('kGuardMonsterSpeedM2'), isTrue);
      expect(fn.contains('kGuardMonsterSpeedM3'), isTrue);
      expect(fn.contains('kGuardBattleFieldTravelPt'), isTrue,
          reason: '外推必须钳到门口 330，绝不穿门/压战士');
    });
  });
}
