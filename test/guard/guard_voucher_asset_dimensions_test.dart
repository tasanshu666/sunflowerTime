/// 券卡素材**尺寸守卫**（Guard-B13.10，玄参 2026-11-11 同意）。
///
/// ## 为什么需要它
/// 券卡插画在代码里用 `AspectRatio 276 / 294` 排版（三处：`guard_art.dart` 回退块、
/// `guard_result_card.dart` 主券卡与第二张券卡、`guard_buff_chip.dart` 横排卡）。
/// 这个比例**只对二次裁切后的 276×294 素材成立**——一旦有人把源目录里未裁的
/// **360×507 原件**覆盖回去（360×507 四周还有 15~16px 纯黑边，见经验 E39），
/// UI 会同时出现「黑框 + 变形」，而 widget 测试**全绿**（它们只断言比例常量，
/// 不读素材真身）。本文件就是那道缺口的补丁：**直读 4 张 webp 真身解码取宽高**。
///
/// ## 纪律
///  · 期望值 **276 / 294 是字面量**，不 import 任何 `kGuard*` 常量、不读实现里的
///    `AspectRatio` —— 否则「素材 + 常量一起被改错」也能全绿；
///  · 用 `dart:ui` 的 `instantiateImageCodec` 解码（这些素材是 **WebP**，不是 PNG，
///    不能按 PNG IHDR 猜尺寸，也不该假设 RIFF/VP8 头布局）；
///  · 测试 cwd = 工程根，故 `File('assets/guard/buff_voucher/water.webp')` 可直读。
///
/// 🔴 **换素材必须同步改这里**：任何一次券卡素材更新（改尺寸 / 改比例 / 换图）
/// 都要先改本文件的字面量，再改上面三处 `AspectRatio`，最后才允许入库。
library guard_voucher_asset_dimensions_test;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 券卡美术原比（**字面量**，与 `guard_art.dart` / `guard_result_card.dart` /
/// `guard_buff_chip.dart` 里的 `AspectRatio 276 / 294` 同值）。
///
/// ⚠️ 这里的数字是「素材契约」，不是「实现读数」：改素材 → 改这四个数字 →
/// 再改那三处 `AspectRatio`。三处引用刻意**不抽常量**（改动面越小越安全，
/// 且本守卫的职责正是「人改了素材忘了改代码」时立刻变红）。
const int kExpectedVoucherWidth = 276;
const int kExpectedVoucherHeight = 294;

/// 四张券卡真身（浇水 / 劳动 / 施肥·中文 / 施肥·英文）。
const List<String> _voucherAssets = <String>[
  'assets/guard/buff_voucher/water.webp',
  'assets/guard/buff_voucher/labor.webp',
  'assets/guard/buff_voucher/fertilize_zh.webp',
  'assets/guard/buff_voucher/fertilize_en.webp',
];

/// 解码一张素材，返回它的**真实像素宽高**。
///
/// 抛 `TestFailure`（而非裸异常）以便失败信息里带上文件路径。
Future<({int width, int height})> _decodeSize(String assetPath) async {
  final File file = File(assetPath);
  if (!file.existsSync()) {
    fail('素材缺失：$assetPath（测试工作目录应为工程根）');
  }
  final Uint8List bytes = await file.readAsBytes();
  expect(bytes.length, greaterThan(0), reason: '空文件：$assetPath');

  // 🔴 这些是 WebP：交给引擎解码，别自己解析容器头。
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final int width = image.width;
  final int height = image.height;
  image.dispose();
  codec.dispose();
  expect(width, greaterThan(0), reason: '解码出 0 宽：$assetPath');
  expect(height, greaterThan(0), reason: '解码出 0 高：$assetPath');
  return (width: width, height: height);
}

void main() {
  // 🔴 解码要引擎，先初始化 binding（flutter_test 下 `dart:ui` 可用）。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('券卡素材尺寸守卫（276×294 · 二次裁切后）', () {
    test('四张券卡真身存在且可解码（缺一张即红）', () async {
      for (final String path in _voucherAssets) {
        final ({int width, int height}) size = await _decodeSize(path);
        expect(size.width, greaterThan(0), reason: path);
      }
      expect(_voucherAssets.length, 4, reason: '券卡固定 4 张（水 / 劳 / 施肥zh / 施肥en）');
    });

    test('每张都必须恰好 276×294（字面量，独立于实现）', () async {
      for (final String path in _voucherAssets) {
        final ({int width, int height}) size = await _decodeSize(path);
        expect(size.width, kExpectedVoucherWidth,
            reason: '$path 实测宽 ${size.width} ≠ 276 —— '
                '很可能把 360×507 未裁原件覆盖回去了（重新跑二次裁切）');
        expect(size.height, kExpectedVoucherHeight,
            reason: '$path 实测高 ${size.height} ≠ 294 —— '
                '很可能把 360×507 未裁原件覆盖回去了（重新跑二次裁切）');
      }
    });

    test('四张尺寸必须完全一致（防止只换一张导致并排错位）', () async {
      final List<({int width, int height})> sizes =
          <({int width, int height})>[
        for (final String path in _voucherAssets) await _decodeSize(path),
      ];
      final ({int width, int height}) first = sizes.first;
      for (int i = 1; i < sizes.length; i++) {
        expect(
          (width: sizes[i].width, height: sizes[i].height),
          (width: first.width, height: first.height),
          reason: '${_voucherAssets[i]} = ${sizes[i].width}×${sizes[i].height} '
              '≠ ${_voucherAssets.first} = ${first.width}×${first.height}',
        );
      }
    });

    test('解码出的宽高比 == 代码里 AspectRatio 的 276/294（容差 1e-6）', () async {
      // 🔴 期望值是**字面量算式 276 / 294**（= 0.9387755102…），不 import 实现。
      const double expectedAspect = 276 / 294;
      for (final String path in _voucherAssets) {
        final ({int width, int height}) size = await _decodeSize(path);
        final double actualAspect = size.width / size.height;
        expect((actualAspect - expectedAspect).abs(), lessThan(1e-6),
            reason: '$path 实际宽高比 ${actualAspect.toStringAsFixed(9)} vs '
                'AspectRatio 276/294 = ${expectedAspect.toStringAsFixed(9)}'
                '（360×507 原件 = 0.710059，差别远大于容差 ⇒ 换错素材必红）');
      }
    });
  });
}
