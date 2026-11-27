/// QA：2026-11-27 雪方位图 + 家长天地入口图标接入守卫。
///
/// 覆盖三个最容易翻车的点：
///  ① 素材确实落盘（WebP q95，原 PNG 只在 gitignored 的 _originals 备份）；
///  ② 雪粒子总数 / 位图编号不变 —— 3 张图都要被用到，且编号不越界；
///  ③ **pubspec 目录声明生效**：`rootBundle` 真能读到图（本项目老坑：目录
///     声明漏一行 = 图静默不进包、线上直接回退代码形状，单看文件存在发现不了）；
///  ④ 二轮反馈：家长入口**所有页面统一 48dp 裸图标、无白胶囊**（玄参 11-27）。
library snow_sprite_parent_icon_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_weather_fx.dart';
import 'package:sunflower_time/presentation/child/widgets/parent_entry_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const List<String> snowPaths = <String>[
    'assets/fx/snow/snow_01.webp',
    'assets/fx/snow/snow_02.webp',
    'assets/fx/snow/snow_03.webp',
  ];
  const String parentIcon = 'assets/ui/parent_hub.webp';

  test('雪方位图与家长入口图标已落盘且非空', () {
    for (final String path in <String>[...snowPaths, parentIcon]) {
      final File f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path 未落盘');
      expect(f.lengthSync(), greaterThan(1000), reason: '$path 疑似空文件');
    }
  });

  test('极寒粒子总数与位图编号不变：44 颗覆盖 3 张雪花、编号不越界', () {
    expect(kGardenWeatherSnowSpriteCount, 3);
    final Set<int> indexes = buildGardenWeatherFxParticles(WeatherKind.cold)
        .map((GardenWeatherFxParticle p) => p.spriteIndex)
        .toSet();
    expect(indexes, <int>{0, 1, 2});
    expect(
      indexes.every((int i) => i >= 0 && i < kGardenWeatherSnowSpriteCount),
      isTrue,
    );
    // 本批只换画法、不换粒子数（三档 20 + 14 + 10 = 44）。
    expect(
      buildGardenWeatherFxParticles(WeatherKind.cold).length,
      kGardenWeatherFxParticleCap[WeatherKind.cold],
    );
  });

  test('pubspec 声明生效：rootBundle 可加载全部 4 张新素材', () async {
    for (final String path in <String>[...snowPaths, parentIcon]) {
      final ByteData data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(1000), reason: '$path 未在包内');
    }
  });

  /// 玄参 11-27 二轮反馈：图标外那圈白色区域（原 immersive 白胶囊）去掉，
  /// 所有页面统一 48dp（原白胶囊可视尺寸）。两种 immersive 形态必须**逐位一致**。
  for (final bool immersive in <bool>[true, false]) {
    testWidgets('家长入口 immersive=$immersive：无白胶囊、图标 48dp', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ParentEntryAction(immersive: immersive)),
          ),
        ),
      );
      // ① 裸 IconButton：不得存在白底 Container（原白胶囊回退会红）。
      expect(find.byWidgetPredicate((Widget w) {
        if (w is! Container || w.decoration is! BoxDecoration) return false;
        final BoxDecoration d = w.decoration! as BoxDecoration;
        // 原白胶囊 alpha 0.78 ≈ 199 = 0xC7。
        return d.color != null &&
            d.color!.toARGB32() == const Color(0xC7FFFFFF).toARGB32();
      }), findsNothing);
      // ② 美术图标 48dp（缩回 28dp 会红）。
      final Image icon = tester.widget<Image>(find.byType(Image));
      expect(icon.width, 48);
      expect(icon.height, 48);
      expect(icon.image is AssetImage, isTrue);
      expect(
        (icon.image as AssetImage).assetName,
        parentIcon,
      );
      // ③ iconKey 仍挂在 IconButton 上（徽章右对齐读同一 RenderBox）。
      expect(find.byKey(ParentEntryAction.iconKey), findsOneWidget);
    });
  }
}
