/// 大招能量状态机性质测试（架构 §1.2 / PRD §5.2 全表 / A1–A4 / B1）。
///
/// 🔴 期望值**独立写死**（29→96.7 / 15→50.0 / 1→3.3 / 0→0.0 / 30→100.0），
/// 禁止复用被测函数 `fillPercent` 自证（QA 会做受控变异验证防假绿）。
library guard_ultimate_energy_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';

void main() {
  group('纯函数 · credit 攒能量（§5.2 全表）', () {
    test('累计分钟 → (filledCells, fractionMin) 逐行对表', () {
      final List<(double, int, int)> rows = <(double, int, int)>[
        (0, 0, 0),
        (15, 0, 15),
        (29, 0, 29),
        (30, 1, 0),
        (44, 1, 14),
        (59, 1, 29),
        (60, 2, 0),
      ];
      for (final (double min, int cells, int frac) in rows) {
        final UltimateEnergy e = credit(UltimateEnergy.empty, min);
        expect(e.filledCells, cells, reason: '$min min → filledCells');
        expect(e.fractionMin, frac, reason: '$min min → fractionMin');
      }
    });

    test('跨会话累加：29 + 1 = 30 ⇒ 点亮 1 格（A1/A3）', () {
      UltimateEnergy e = credit(UltimateEnergy.empty, 29);
      expect(e.filledCells, 0);
      expect(e.fractionMin, 29);
      e = credit(e, 1);
      expect(e.filledCells, 1);
      expect(e.fractionMin, 0);
    });

    test('59 + 1 = 60 ⇒ 2 格全亮（A4）', () {
      UltimateEnergy e = credit(UltimateEnergy.empty, 59);
      expect(e.filledCells, 1);
      expect(e.fractionMin, 29);
      e = credit(e, 1);
      expect(e.filledCells, 2);
      expect(e.fractionMin, 0);
      expect(e.isFull, isTrue);
    });

    test('整分钟入账：实际分钟 floor（架构 U-2）', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 29.9);
      expect(e.fractionMin, 29);
      expect(e.totalFocusMin, 29.9); // 原始 double 仍记总量
    });
  });

  group('定死点② · 满 2 格零头归零 + 溢出丢弃（B1）', () {
    test('满 2 格那一刻 fractionMin 强制 0', () {
      // 1 格 + 29 零头，再加 31 分钟 → 应进位到第 2 格并丢弃溢出。
      const UltimateEnergy base = UltimateEnergy(filledCells: 1, fractionMin: 29);
      final UltimateEnergy e = credit(base, 31);
      expect(e.filledCells, 2);
      expect(e.fractionMin, 0, reason: '满 2 格必须丢弃溢出、零头归零');
    });

    test('满 2 格后继续专注：早返回，状态与总量都不增长', () {
      const UltimateEnergy full = UltimateEnergy(
        filledCells: 2,
        fractionMin: 0,
        totalFocusMin: 60.0,
      );
      final UltimateEnergy e = credit(full, 120);
      expect(e, same(full), reason: '池满时原样返回同一实例');
      expect(e.filledCells, 2);
      expect(e.fractionMin, 0);
      expect(e.totalFocusMin, 60.0);
    });
  });

  group('fillPercent · 期望值独立写死', () {
    test('29min → 96.7%（不是 9.7，也不是 96.6）', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 29);
      expect(fillPercent(e, 0), 96.7);
      expect(fillPercent(e, 1), 0.0);
    });

    test('15min → 50.0%', () {
      expect(fillPercent(credit(UltimateEnergy.empty, 15), 0), 50.0);
    });

    test('1min → 3.3%（round 到一位小数）', () {
      expect(fillPercent(credit(UltimateEnergy.empty, 1), 0), 3.3);
    });

    test('0min → 0.0%', () {
      expect(fillPercent(UltimateEnergy.empty, 0), 0.0);
    });

    test('30min → 点亮格 100.0% + 第 2 格 0.0%', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 30);
      expect(fillPercent(e, 0), 100.0);
      expect(fillPercent(e, 1), 0.0);
    });

    test('1 格满 + 第 2 格进行中（44min）→ 100.0% / 46.7%', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 44);
      expect(fillPercent(e, 0), 100.0);
      expect(fillPercent(e, 1), 46.7);
    });

    test('满 2 格 → 两格均 100.0%', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 60);
      expect(fillPercent(e, 0), 100.0);
      expect(fillPercent(e, 1), 100.0);
    });
  });

  group('spend 释放 · 只扣整格不动零头（PRD §5.1）', () {
    test('满 2 格释放 → 1 格 0 零头（B1 路径）', () {
      final UltimateEnergy e = spend(credit(UltimateEnergy.empty, 60));
      expect(e.filledCells, 1);
      expect(e.fractionMin, 0);
    });

    test('未满 2 格释放 → 零头保留', () {
      // 1 格 + 14 零头（44min）释放 → 0 格 + 14 零头（PRD 明文，不推翻）。
      final UltimateEnergy e = spend(credit(UltimateEnergy.empty, 44));
      expect(e.filledCells, 0);
      expect(e.fractionMin, 14);
    });

    test('0 格释放 no-op（返回同一实例）', () {
      final UltimateEnergy e = spend(UltimateEnergy.empty);
      expect(e, same(UltimateEnergy.empty));
    });

    test('一场多次释放：2 → 1 → 0', () {
      UltimateEnergy e = credit(UltimateEnergy.empty, 60);
      e = spend(e);
      expect(e.filledCells, 1);
      e = spend(e);
      expect(e.filledCells, 0);
      expect(spend(e).filledCells, 0);
    });
  });

  group('不变量 isValid（架构 §1.2）', () {
    test('合法状态全部通过', () {
      for (final UltimateEnergy e in <UltimateEnergy>[
        UltimateEnergy.empty,
        const UltimateEnergy(filledCells: 0, fractionMin: 29),
        const UltimateEnergy(filledCells: 1, fractionMin: 0),
        const UltimateEnergy(filledCells: 1, fractionMin: 29),
        const UltimateEnergy(filledCells: 2, fractionMin: 0),
      ]) {
        expect(isValid(e), isTrue, reason: '$e 应满足不变量');
      }
    });

    test('非法状态被拒（越界 / 满格带零头）', () {
      expect(isValid(const UltimateEnergy(filledCells: 3, fractionMin: 0)), isFalse);
      expect(isValid(const UltimateEnergy(filledCells: 0, fractionMin: 30)), isFalse);
      expect(isValid(const UltimateEnergy(filledCells: -1, fractionMin: 0)), isFalse);
      expect(isValid(const UltimateEnergy(filledCells: 2, fractionMin: 1)), isFalse);
    });

    test('credit 结果恒满足不变量（性质断言）', () {
      for (int min = 0; min <= 500; min += 7) {
        UltimateEnergy e = credit(UltimateEnergy.empty, min.toDouble());
        expect(isValid(e), isTrue, reason: '$min min 的不变量');
        e = credit(e, 3.5);
        expect(isValid(e), isTrue);
      }
    });
  });

  group('JSON 持久化（冷启动不变，P0-01③）', () {
    test('round-trip 保真', () {
      final UltimateEnergy e = credit(UltimateEnergy.empty, 44);
      final UltimateEnergy back = UltimateEnergy.fromJson(e.toJson());
      expect(back, e);
    });

    test('坏数据降级 + 强制满足不变量', () {
      expect(UltimateEnergy.fromJson(<String, Object?>{}), UltimateEnergy.empty);
      final UltimateEnergy bad = UltimateEnergy.fromJson(<String, Object?>{
        'filledCells': 9,
        'fractionMin': 99,
      });
      expect(bad.filledCells, 2);
      expect(bad.fractionMin, 0);
      expect(isValid(bad), isTrue);
    });
  });
}
