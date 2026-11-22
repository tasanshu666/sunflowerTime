/// 统一大招帧接入护栏（🔴 C129 玄参拍板：**中英统一一套帧，区别只在音效**）
/// + fx 上移 + 调试加能量动作 API。
///
/// C129 语义（取代 2026-11-21 的「中文大招」双帧目录口径）：
///  · 帧目录单一化：`kUltimateFxCastDir` = `assets/guard/soldier_ultimate`
///    （统一帧，语言无关），zh 帧目录 `soldier_ultimate_zh/` +
///    `kUltimateFxCastDirZh` 已删除 —— lib / pubspec **零残留**（源码守卫）；
///  · `soldierUltimateCast` 恒用统一目录、`playToken` 不再裹语言后缀
///    （zh/en locale 下同一目录同一 token）；
///  · cast **音效仍分语言**：`kUltimateFxCastSfxZh` / `guardUltimateCastSfxForLocale`
///    零改动；
///  · 🔴 C130（玄参「你不要给我切割」）：帧真身 = 27 张 webp 全部 **720×720**
///    **全画布不裁切**（取代 C129 的 277×266 裁窗口径）；战士实体帧子集
///    （001..009/027）导出后 luma ≈ **156.77**（= 待机参考，玄参
///    「战士亮度与待机对齐」；导出自检实测 156.95，容差 ±2）。
///    「战士与待机大小一致」由绘制框侧补偿（几何断言见
///    `guard_cast_size_alignment_test.dart`）。
library guard_ultimate_zh_asset_test;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardSceneCardHeight,
        kUltimateFxCastDir,
        kUltimateFxCastFrames,
        kUltimateFxCastSfx,
        kUltimateFxCastSfxZh,
        kUltimateFxVisualCenterY;
import 'package:sunflower_time/core/di/providers.dart'
    show guardUltimateServiceProvider;
import 'package:sunflower_time/core/i18n/app_locale_controller.dart'
    show AppLocaleController;
import 'package:sunflower_time/data/local/guard_ultimate_energy_prefs_store.dart'
    show GuardUltimateEnergyPrefsStore;
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy;
import 'package:sunflower_time/domain/services/guard_ultimate_service.dart'
    show GuardUltimateService;
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart'
    show
        debugGrantUltimateCellsProvider,
        kDebugUltimateFillKey,
        kDebugUltimateGrantCellKey;
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart'
    show FrameSequencePlayer, fxFrameAssets, kGrowFxFrameExt;
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show
        GuardUltimateFx,
        guardUltimateCastSfxForLocale,
        kUltimateFxAspectRatio;

// ── 素材契约字面量（换素材必须同步改这里，与券卡尺寸守卫同纪律）────────────

/// 统一帧真身尺寸（🔴 C130：全画布不裁切；管线自检 size=[(720, 720)]）。
const int kExpectedUnifiedCastWidth = 720;
const int kExpectedUnifiedCastHeight = 720;

/// 战士实体帧子集（0 基：001..009 + 027）—— 亮度校准与自检口径。
const List<int> _soldierOnlyFrameIndices = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 26];

/// 待机亮度参考（管线 IDLE_LUMA_REFERENCE，实测 19 帧均值）。
const double kIdleLumaReference = 156.77;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Locale savedLocale = AppLocaleController.current;

  tearDown(() {
    // 静态 locale 是进程级状态：每条用例必须还原，污染其它测试文件会假绿 / 假红。
    AppLocaleController.current = savedLocale;
  });

  group('C129 统一大招帧：常量与目录单一化', () {
    test('统一目录字面量、帧数 27、帧列表首尾路径', () {
      expect(kUltimateFxCastDir, 'assets/guard/soldier_ultimate');
      expect(kUltimateFxCastFrames, 27);
      final List<String> frames = fxFrameAssets(
        kUltimateFxCastDir,
        kUltimateFxCastFrames,
        ext: kGrowFxFrameExt,
      );
      expect(frames.length, 27);
      expect(frames.first, 'assets/guard/soldier_ultimate/frame001.webp');
      expect(frames.last, 'assets/guard/soldier_ultimate/frame027.webp');
    });

    test('源码守卫：zh 帧目录零残留（lib / pubspec / 本文件外的 test）', () {
      // 🔴 C129：`soldier_ultimate_zh` 只允许存在于历史备份目录
      // （assets/_originals/，不入包）与转换管线的历史口径注释里；lib 与
      // pubspec 资产声明必须零引用，否则目录声明 / 常量会指向不存在的目录。
      final String prdSrc =
          File('lib/core/constants/prd_params.dart').readAsStringSync();
      expect(prdSrc.contains('soldier_ultimate_zh'), isFalse,
          reason: 'prd_params 不得再有 kUltimateFxCastDirZh / zh 目录字面量');
      final String artSrc =
          File('lib/presentation/child/widgets/guard_art.dart').readAsStringSync();
      expect(artSrc.contains('soldier_ultimate_zh'), isFalse,
          reason: 'guard_art 不得再按语言选帧目录');
      expect(artSrc.contains('isEn'), isFalse,
          reason: '统一帧后 soldierUltimateCast 无语言分支');
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/guard/soldier_ultimate_zh/'), isFalse,
          reason: 'pubspec 不得再声明已删除的 zh 帧目录');
      expect(pubspec.contains('assets/guard/soldier_ultimate/'), isTrue,
          reason: '统一帧目录仍须声明（不递归，逐行列出）');
      // 物理目录已删除（防止幽灵资产进包）。
      expect(
        Directory('assets/guard/soldier_ultimate_zh').existsSync(),
        isFalse,
        reason: 'zh 帧目录必须已物理删除',
      );
    });

    test('cast 音效仍分语言（C129 只统一帧，不动音效）；fx 音效通用', () {
      expect(kUltimateFxCastSfx, 'assets/audio/sfx/guard_ultimate_cast.mp3');
      expect(kUltimateFxCastSfxZh,
          'assets/audio/sfx/guard_ultimate_cast_zh.mp3');
      expect(guardUltimateCastSfxForLocale(true), kUltimateFxCastSfx);
      expect(guardUltimateCastSfxForLocale(false), kUltimateFxCastSfxZh);
      expect(guardUltimateCastSfxForLocale(true),
          isNot(guardUltimateCastSfxForLocale(false)));
    });
  });

  group('C129 统一大招帧：语言无关（zh/en 同目录同 token）', () {
    Future<FrameSequencePlayer> pumpCast(
      WidgetTester tester,
      Locale locale,
    ) async {
      AppLocaleController.current = locale;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          // ValueKey 强制换树：静态 locale 改变本身不会触发 Flutter rebuild。
          child: SizedBox(
            key: ValueKey<String>('cast-${locale.languageCode}'),
            width: 60,
            height: 60,
            child: GuardArt.soldierUltimateCast(
              playToken: 7,
              onComplete: () {},
            ),
          ),
        ),
      ));
      return tester.widget<FrameSequencePlayer>(
          find.byKey(GuardArt.ultimateCastKey));
    }

    testWidgets('en / zh / zh_CN 三个 locale 都用同一统一目录、同一 playToken',
        (WidgetTester tester) async {
      final FrameSequencePlayer en = await pumpCast(
          tester, const Locale('en'));
      expect(en.frames.first, startsWith(kUltimateFxCastDir));
      expect(en.playToken, 7,
          reason: '🔴 C129：token 不再裹语言后缀（帧列表语言无关，无重启诉求）'
              '—— 调用方传什么就是什么，不做字符串拼接');
      expect(en.fit, BoxFit.fitHeight,
          reason: '全画布 + 绘制框按实体占比补偿（C130），沿用 fitHeight');

      final FrameSequencePlayer zh = await pumpCast(
          tester, const Locale('zh'));
      expect(zh.frames.first, startsWith(kUltimateFxCastDir),
          reason: 'zh locale 也用统一目录（不再切 zh 帧目录）');
      expect(zh.frames, en.frames, reason: '两语言帧列表逐位相同');

      final FrameSequencePlayer systemZh = await pumpCast(
          tester, const Locale('zh', 'CN'));
      expect(systemZh.frames, en.frames);
      expect(systemZh.playToken, en.playToken,
          reason: '语言切换不再触发帧重播（音效切换由卡侧状态机负责）');
    });
  });

  group('C129 统一大招帧：真身尺寸与亮度（解码实测）', () {
    /// 解码一张 webp：返回 (宽, 高, alpha>128 掩码加权 luminance)。
    Future<(int, int, double)> decodeAssetFrame(String path) async {
      final File file = File(path);
      if (!file.existsSync()) {
        fail('素材缺失：$path（测试工作目录应为工程根）');
      }
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo info = await codec.getNextFrame();
      final ui.Image image = info.image;
      final int w = image.width;
      final int h = image.height;
      final ByteData? data = await image.toByteData(
        // 🔴 rawStraightRgba（直通 alpha）：rawRgba 是**预乘 alpha** 格式，
        // 半透明像素 RGB 会被预乘变暗，亮度统计会偏低（与管线 Pillow 口径
        // 「RGB 不预乘」不一致）。亮度校准用直通色。
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      expect(data, isNotNull, reason: 'rawRgba 导出失败：$path');
      final Uint8List px = data!.buffer.asUint8List();
      double sum = 0;
      double weight = 0;
      for (int i = 0; i < px.length; i += 4) {
        final int a = px[i + 3];
        if (a > 128) {
          sum += 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
          weight += 1;
        }
      }
      expect(weight, greaterThan(0), reason: '全透明帧异常：$path');
      return (w, h, sum / weight);
    }

    test('27 帧全部 720×720（🔴 C130 全画布不裁切）；战士实体帧亮度 = 待机参考', () async {
      final List<double> soldierLumas = <double>[];
      for (int i = 1; i <= 27; i++) {
        final String path =
            'assets/guard/soldier_ultimate/frame${i.toString().padLeft(3, '0')}.webp';
        final (int w, int h, double luma) = await decodeAssetFrame(path);
        expect(w, kExpectedUnifiedCastWidth,
            reason: '$path 宽度应为 $kExpectedUnifiedCastWidth'
                '（🔴 C130 玄参「你不要给我切割」：全画布，禁止裁边回归）');
        expect(h, kExpectedUnifiedCastHeight,
            reason: '$path 高度应为 $kExpectedUnifiedCastHeight'
                '（🔴 C130 玄参「你不要给我切割」：全画布，禁止裁边回归）');
        if (_soldierOnlyFrameIndices.contains(i - 1)) {
          soldierLumas.add(luma);
        }
      }
      final double avg =
          soldierLumas.reduce((double a, double b) => a + b) /
              soldierLumas.length;
      expect(avg, closeTo(kIdleLumaReference, 2.0),
          reason: '🔴 战士实体帧（001..009/027）导出亮度必须对齐待机参考 '
              '$kIdleLumaReference（玄参「战士亮度与待机对齐」；导出自检实测 '
              '156.95，WebP 有损容差 ±2）');
    });
  });

  group('fx 视觉重心贴地（0.68 → 0.52，玄参「打在半空没落地」）', () {
    testWidgets('top = anchor.dy − 0.68h；left 仍按几何中心', (WidgetTester tester) async {
      const Offset anchor = Offset(240, 70);
      const double uiScale = 1.0;
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: GuardUltimateFx(anchor: anchor, uiScale: uiScale),
          ),
        ),
      ));
      final Positioned box =
          tester.widget<Positioned>(find.byKey(GuardUltimateFx.fxKey));
      const double h = kGuardSceneCardHeight * uiScale;
      const double w = h * kUltimateFxAspectRatio;
      expect(kUltimateFxVisualCenterY, 0.52);
      expect(box.top, closeTo(anchor.dy - 0.52 * h, 0.01));
      expect(box.top! < anchor.dy - 0.5 * h, isTrue,
          reason: '必须比旧的几何中心公式更靠上');
      expect(box.left, closeTo(anchor.dx - w / 2, 0.01),
          reason: 'X 不受上移影响');
      expect(box.width, closeTo(w, 0.01));
      expect(box.height, closeTo(h, 0.01));
    });
  });

  group('调试「增加大招次数」动作 API', () {
    test('1 → 加一格；2 → 充满；fractionMin/幂等集合/总量不动；按钮 Key 稳定', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final GuardUltimateEnergyPrefsStore store =
          GuardUltimateEnergyPrefsStore(
              await SharedPreferences.getInstance());
      const String child = 'debug-kid';
      final GuardUltimateService service = GuardUltimateService(
        store: store,
        childId: () => child,
      );
      // 制造「攒了一半 + 已有幂等账本」的现场，验证调试动作不碰这两笔账。
      await store.write(child,
          const UltimateEnergy(filledCells: 0, fractionMin: 17, totalFocusMin: 12.5));
      await store.writeCreditedSessionIds(child, <String>{'real-session'});

      final ProviderContainer container = ProviderContainer(overrides: <Override>[
        guardUltimateServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);

      final UltimateEnergy one = await container.read(debugGrantUltimateCellsProvider)(1);
      expect(one.filledCells, 1);
      expect(one.fractionMin, 0, reason: '加整格后零头清零');
      expect(one.totalFocusMin, 12.5, reason: '不伪造累计专注分钟');

      final UltimateEnergy two = await container.read(debugGrantUltimateCellsProvider)(2);
      expect(two.filledCells, 2, reason: '充满两格');
      expect(two.fractionMin, 0);
      expect(two.totalFocusMin, 12.5);
      expect((await store.readCreditedSessionIds(child)), <String>{'real-session'},
          reason: '幂等账本一个不动');
      expect((await service.read()).filledCells, 2);

      expect(kDebugUltimateGrantCellKey, 'debug_ultimate_grant_cell');
      expect(kDebugUltimateFillKey, 'debug_ultimate_fill');
    });
  });
}
