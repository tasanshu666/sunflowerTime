/// C61 响应式基线（平板适配）的**纯函数护栏**（2026-10-13）。
///
/// 只测 `lib/shared/responsive.dart` 的判定与派生值，不需要 widget 宿主。
/// 核心不变式：**手机档（shortestSide < 600）派生值与原实现逐位相等**，
/// 保证平板改造对手机端是零像素变化。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/shared/responsive.dart';

void main() {
  group('C61 断点判定：shortestSide >= 600 为平板', () {
    test('阈值边界 599.9 / 600', () {
      expect(isTabletShortestSide(599.9), isFalse);
      expect(isTabletShortestSide(600), isTrue);
    });

    test('手机各档判为非平板', () {
      expect(isTabletShortestSide(320), isFalse); // 极窄屏
      expect(isTabletShortestSide(360), isFalse); // 常见安卓竖屏
      expect(isTabletShortestSide(390), isFalse); // iPhone 17
      expect(isTabletShortestSide(402), isFalse); // iPhone 17 Pro
    });

    test('平板与桌面档判为平板', () {
      expect(isTabletShortestSide(600), isTrue); // 荣耀平板 9 最小可能档
      expect(isTabletShortestSide(800), isTrue); // 荣耀平板 9 竖屏（估）
      expect(isTabletShortestSide(1280), isTrue); // 桌面 / 大屏
    });

    test('⚠️ 选 shortestSide 的理由：手机横屏的短边仍是短边', () {
      // 手机横屏窗口宽 ≈780（会被「按窗口宽度判」误判成平板），
      // 但 shortetSide 仍 = 短边 390 → 正确判为非平板。
      const double phoneLandscapeShortSide = 390;
      expect(isTabletShortestSide(phoneLandscapeShortSide), isFalse);
      // 反证：若按「窗口宽度」判，780 >= 600 会误判
      expect(780 >= kTabletShortestSideThreshold, isTrue);
    });
  });

  group('C61 成长演出卡宽度', () {
    test('手机各档 = 屏短边 × 比例（与原实现逐位相等）', () {
      for (final double s in <double>[320, 360, 390, 402]) {
        expect(growFxCardWidthOf(s), s * kGrowFxCardWidthRatio);
      }
    });

    test('反证：平板 800 不钳制会得到 624（远超屏短边的 0.78 倍语义）', () {
      expect(800 * kGrowFxCardWidthRatio, closeTo(624, 0.001));
    });

    test('平板钳到 kGrowFxCardMaxWidth', () {
      expect(growFxCardWidthOf(800), kGrowFxCardMaxWidth);
      expect(growFxCardWidthOf(1280), kGrowFxCardMaxWidth);
    });

    test('钳制切换点：短边 × 比例 恰越过上限时', () {
      const double pivot = kGrowFxCardMaxWidth / kGrowFxCardWidthRatio;
      expect(growFxCardWidthOf(pivot - 0.1), lessThan(kGrowFxCardMaxWidth));
      expect(growFxCardWidthOf(pivot + 0.1), kGrowFxCardMaxWidth);
    });
  });

  group('C61 花园网格净宽', () {
    test('手机各档 = 页面宽 − 左右内边距（与原实现逐位相等）', () {
      for (final double w in <double>[320, 360, 390, 402]) {
        expect(gardenGridNetWidthOf(w, pagePadH: 12), w - 24);
      }
    });

    test('平板钳到 kGardenGridMaxWidth（居中留白）', () {
      expect(gardenGridNetWidthOf(800, pagePadH: 12), kGardenGridMaxWidth);
      expect(gardenGridNetWidthOf(1280, pagePadH: 12), kGardenGridMaxWidth);
    });

    test('⚠️ 钳制后必须 ≤ 页面可用宽（否则 Padding 内溢出）', () {
      for (final double w in <double>[600, 800, 1280]) {
        expect(
          gardenGridNetWidthOf(w, pagePadH: 12),
          lessThanOrEqualTo(w - 24),
        );
      }
    });

    test('格宽确实放大，但没有失控（1.5× ~ 1.9× 手机格宽）', () {
      const double spacing = 6; // = garden_page.dart 的 gridSpacing（crossAxisSpacing ×2）
      const double tabletCellW = (kGardenGridMaxWidth - spacing * 2) / 3;
      const double phoneCellW = (390 - 24 - spacing * 2) / 3;
      const double ratio = tabletCellW / phoneCellW;
      // C64（2026-10-13）：480 → 620 后比值 ≈1.72（原 ≈1.32）—— 玄参 iPad 实测
      // 「盆栽偏小、下半草地空一大块」后拍板放大，故上界同步放宽。
      expect(ratio, greaterThan(1.5), reason: '平板格宽应明显放大');
      expect(ratio, lessThan(1.9), reason: '放大不能失控（再大默认 6 盆就不再是一屏可见）');
    });

    test('⚠️ 格宽越大 → 格内纵向余量越大：平板比手机更安全（不会溢出）', () {
      // 格内内容高（源自 GardenGrid.cellAspectRatio 的推导注释）：
      //   = (格宽 − 4) × kGardenArtWidthRatio × kGardenArtAspect + footer + 上下内边距 8
      // C65：平板上标签文字放大 1.3× → 底栏高必须同步放大（gardenPotFooterHeightFor）。
      double contentH(double cellW, double footer) =>
          (cellW - 4) * kGardenArtWidthRatio * kGardenArtAspect + footer + 8;
      double cellH(double cellW) => cellW / GardenGrid.cellAspectRatio;

      const double spacing = 6;
      const double tabletCellW = (kGardenGridMaxWidth - spacing * 2) / 3;
      const double phoneCellW = (390 - 24 - spacing * 2) / 3;
      const double tightestCellW = (320 - 24 - spacing * 2) / 3; // 最紧的 320 屏

      final double phoneFooter = gardenPotFooterHeightFor(1.0);
      final double tabletFooter = gardenPotFooterHeightFor(kTabletUiScale);
      expect(phoneFooter, kGardenPotFooterHeight, reason: '手机底栏 = 基准 32pt（零回归）');
      expect(tabletFooter, greaterThan(phoneFooter), reason: '平板底栏必须随字号长高');

      for (final (double w, double f) in <(double, double)>[
        (tightestCellW, phoneFooter),
        (phoneCellW, phoneFooter),
        (tabletCellW, tabletFooter), // ← 平板按放大后的底栏复核
      ]) {
        expect(contentH(w, f), lessThan(cellH(w)), reason: '格宽 $w 时不得溢出');
      }
      expect(
        cellH(tabletCellW) - contentH(tabletCellW, tabletFooter),
        greaterThan(cellH(phoneCellW) - contentH(phoneCellW, phoneFooter)),
        reason: '格宽越大余量越大 → 平板限宽后比手机更安全',
      );
    });
  });

  group('C65 平板 UI 放大：文字缩放的注入与钳制', () {
    test('常量锁定：倍率 1.3 / 总倍率上限 1.6', () {
      expect(kTabletUiScale, 1.3, reason: 'C65 拍板值（与 C64 盆栽 1.29× 同比）');
      expect(kTabletTextScaleMax, 1.6, reason: '防「iOS 超大字体 ×1.3」撑破布局');
    });

    test('设备默认字号 → 平板 1.3×', () {
      expect(tabletTextScaler(TextScaler.noScaling).scale(1.0), kTabletUiScale);
    });

    test('⚠️ 与设备自带缩放**相乘**后再钳上限（不覆盖无障碍设置）', () {
      // 1.2 × 1.3 = 1.56 < 1.6 → 原样保留用户的放大
      expect(
        tabletTextScaler(const TextScaler.linear(1.2)).scale(1.0),
        closeTo(1.56, 1e-9),
      );
      // 1.3 × 1.3 = 1.69 → 钳到 1.6；1.35 × 1.3 = 1.755 → 同样钳到 1.6
      expect(
        tabletTextScaler(const TextScaler.linear(1.3)).scale(1.0),
        kTabletTextScaleMax,
      );
      expect(
        tabletTextScaler(const TextScaler.linear(1.35)).scale(1.0),
        kTabletTextScaleMax,
      );
    });

    test('下限：平板文字不得小于手机基准（倍率 < 1 的设备档被抬到 1.0）', () {
      expect(
        tabletTextScaler(const TextScaler.linear(0.5)).scale(1.0),
        greaterThanOrEqualTo(1.0),
      );
    });

    test('⚠️ 手机档原样返回（同一实例 → 调用方不包 MediaQuery，零回归）', () {
      const MediaQueryData phone = MediaQueryData(size: Size(390, 844));
      expect(
        identical(applyTabletTextScaling(phone), phone),
        isTrue,
        reason: '手机必须返回同一对象，app.dart 据此跳过 MediaQuery 包装',
      );
    });

    test('平板档注入 textScaler，其余字段逐位不变', () {
      const MediaQueryData tablet = MediaQueryData(size: Size(834, 1210));
      final MediaQueryData out = applyTabletTextScaling(tablet);
      expect(identical(out, tablet), isFalse, reason: '必须有变化');
      expect(out.textScaler.scale(1.0), kTabletUiScale);
      expect(out.size, tablet.size);
      expect(out.devicePixelRatio, tablet.devicePixelRatio);
    });

    test('注入点边界：短边 599.9 不注入 / 600 注入', () {
      const MediaQueryData just = MediaQueryData(size: Size(599.9, 900));
      const MediaQueryData edge = MediaQueryData(size: Size(600, 900));
      expect(identical(applyTabletTextScaling(just), just), isTrue);
      expect(
        applyTabletTextScaling(edge).textScaler.scale(1.0),
        kTabletUiScale,
      );
    });
  });

  group('C65 花盆底栏高随倍率长高（固定高被放大文字撑破的收口）', () {
    test('手机 32 → 平板 1.3× 36.8 → 上限 1.6× 41.6', () {
      expect(gardenPotFooterHeightFor(1.0), kGardenPotFooterHeight);
      expect(gardenPotFooterHeightFor(1.3), closeTo(36.8, 1e-9));
      expect(gardenPotFooterHeightFor(kTabletTextScaleMax), closeTo(41.6, 1e-9));
    });

    test('⚠️ 底栏增量必须 ≥ 标签文字行高增量，否则文案被挤（16 的取值依据）', () {
      const double labelFontSize = 11; // garden_pot 标签胶囊字号
      const double lineHeightFactor = 1.17; // prd_params 注释里的默认行高系数假设
      final double textGain =
          labelFontSize * (kTabletUiScale - 1) * lineHeightFactor;
      final double footerGain =
          gardenPotFooterHeightFor(kTabletUiScale) - kGardenPotFooterHeight;
      expect(footerGain, greaterThanOrEqualTo(textGain));
      // 且不能过度富余：多留 > 1 行字高就会把三类格子底边推得不齐（视觉断层）
      expect(footerGain, lessThan(labelFontSize * kTabletUiScale));
    });
  });
}
