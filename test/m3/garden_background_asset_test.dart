/// 背景图**源尺寸守卫**测试（QA 2026-09-23 建议的加固项）。
///
/// ## 为什么需要
/// `kGardenBackgroundSize` 是木牌热区、花盆区底界等一切几何映射的**基准**。玄参换图时
/// 若只改 PNG 忘了改常量（或反之），整套映射会静默错位，而普通用例仍可能「自洽地全绿」
/// （因为期望值也来自同一个常量）。本用例**直接读 PNG 文件头（IHDR）的真实像素**，
/// 与 [kGardenBackgroundSize] 硬核对——**换图不同步改常量 → 必红**。
///
/// ## 读法
/// PNG 前 8 字节为签名，其后 IHDR 数据块：宽（4 字节 big-endian）+ 高（4 字节）位于
/// 文件偏移 16..24。无需引入图像解码库，纯 dart `dart:io` 即可，且不依赖 widget 宿主。
library garden_background_asset_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';

/// 解析 PNG 的 IHDR 宽高（偏移 16..24，big-endian）。
({int width, int height}) _readPngSize(Uint8List bytes) {
  const List<int> signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (int i = 0; i < signature.length; i++) {
    expect(bytes[i], signature[i], reason: 'PNG 签名不匹配（第 $i 字节）');
  }
  final ByteData view = ByteData.sublistView(bytes, 16, 24);
  return (
    width: view.getUint32(0, Endian.big),
    height: view.getUint32(4, Endian.big),
  );
}

void main() {
  test('background.png 真实像素 == kGardenBackgroundSize（换图必同步改常量）', () {
    final File file = File('assets/garden/background.png');
    expect(file.existsSync(), isTrue,
        reason: '找不到 assets/garden/background.png（测试工作目录应为工程根）');

    final Uint8List bytes = file.readAsBytesSync();
    final ({int width, int height}) size = _readPngSize(bytes);

    expect(size.width, kGardenBackgroundSize.width,
        reason: '换图后未同步 kGardenBackgroundSize.width（图=$size.width 常量=${kGardenBackgroundSize.width}）');
    expect(size.height, kGardenBackgroundSize.height,
        reason: '换图后未同步 kGardenBackgroundSize.height（图=$size.height 常量=${kGardenBackgroundSize.height}）');
  });
}
