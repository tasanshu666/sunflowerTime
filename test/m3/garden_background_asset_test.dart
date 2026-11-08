/// 背景图**源尺寸守卫**测试（QA 2026-09-23 建议的加固项）。
///
/// ## 为什么需要
/// `kGardenBackgroundSize` 是木牌热区、花盆区底界等一切几何映射的**基准**。玄参换图时
/// 若只改图片忘了改常量（或反之），整套映射会静默错位，而普通用例仍可能「自洽地全绿」
/// （因为期望值也来自同一个常量）。本用例**直接读图片文件头的真实像素**，
/// 与 [kGardenBackgroundSize] 硬核对——**换图不同步改常量 → 必红**。
///
/// ## 读法（2026-11-06：背景图 png → jpg，改读 JPEG SOF marker）
/// JPEG 由一串 `0xFFxx` marker 组织；尺寸在 SOF0/SOF1/SOF2（baseline / extended /
/// progressive，`0xFFC0~0xFFC2`）的 frame header 里：精度(1) + 高(2, big-endian) +
/// 宽(2)。无需图像解码库，纯 dart `dart:io` 即可，且不依赖 widget 宿主。
library garden_background_asset_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';

/// 解析 JPEG 的 SOF0/SOF1/SOF2 宽高（跳过中间所有 marker 段）。
({int width, int height}) _readJpegSize(Uint8List bytes) {
  const List<int> signature = <int>[0xFF, 0xD8, 0xFF];
  for (int i = 0; i < signature.length; i++) {
    expect(bytes[i], signature[i], reason: 'JPEG 签名不匹配（第 $i 字节）');
  }
  int i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final int marker = bytes[i + 1];
    // SOF0(baseline) / SOF1(extended) / SOF2(progressive) 才带尺寸；
    // 0x01~0xBF 之间的其它 marker 与 0xD8/0x01 无长度段，逐字节绕过。
    final bool isSof = marker >= 0xC0 && marker <= 0xC2;
    if (isSof) {
      final ByteData view = ByteData.sublistView(bytes, i + 5, i + 9);
      return (
        height: view.getUint16(0, Endian.big),
        width: view.getUint16(2, Endian.big),
      );
    }
    // APPn/COM/DQT 等有长度段（2 字节 big-endian，含自身）；RSTn/TEM 无。
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
    } else {
      final int segLen = ByteData.sublistView(bytes, i + 2, i + 4)
          .getUint16(0, Endian.big);
      i += 2 + segLen;
    }
  }
  fail('未找到 JPEG SOF0/SOF1/SOF2 marker——assets/garden/background.jpg 可能损坏');
}

void main() {
  test('background.jpg 真实像素 == kGardenBackgroundSize（换图必同步改常量）', () {
    final File file = File('assets/garden/background.jpg');
    expect(file.existsSync(), isTrue,
        reason: '找不到 assets/garden/background.jpg（测试工作目录应为工程根）');

    final Uint8List bytes = file.readAsBytesSync();
    final ({int width, int height}) size = _readJpegSize(bytes);

    expect(size.width, kGardenBackgroundSize.width,
        reason: '换图后未同步 kGardenBackgroundSize.width（图=$size.width 常量=${kGardenBackgroundSize.width}）');
    expect(size.height, kGardenBackgroundSize.height,
        reason: '换图后未同步 kGardenBackgroundSize.height（图=$size.height 常量=${kGardenBackgroundSize.height}）');
  });
}
