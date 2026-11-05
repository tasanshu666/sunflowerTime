/// 天气系统 A5-b · **13 枚真美术资源接入** 验收守卫。
///
/// ## 这份文件守的是什么
/// A5-b 是「把 13 枚 288² 透明 WebP 从 `Material Icon` 换成 `Image.asset`」——
/// 改动本身很小，但**失败的形态全是静默的**：
///  · `pubspec.yaml` 漏登记 `assets/weather/` ⇒ 图静默不进包，`Image.asset` 不抛异常、
///    只在真机上显示空白（2026-09-28 序列帧已因此翻过车，见 `fx_frame_assets_guard_test`）；
///  · 文件名拼错（`WeatherKind.lightRain.name` 是驼峰 `lightRain`，磁盘契约是
///    `light_rain`）⇒ 只有小雨那一天静默退回 Material 图标，肉眼极难发现；
///  · `errorBuilder` 写成死代码（比如回退分支里又 `Image.asset` 一次）⇒ 素材一缺，
///    孩子看到的是**空框**而不是占位图标；
///  · 把 `width/height` 交给 `fit` 自适应 ⇒ 288² 原图直接撑爆天气行（A2 封版的
///    5 档压缩阶梯全部失效）。
/// 所以本文件的断言一律**从契约 / 常量 / 渲染树出期望值**，不写「某处看起来对」。
///
/// ## 与派工书的对应
/// | 用例组 | 派工书 §五 | 抓的错 |
/// |---|---|---|
/// | G1 资产实体 | 1 | 图没进仓 / 是空文件 / 不是 WebP |
/// | G2 pubspec 登记 | 2 | 图进仓但不进包 |
/// | G3 位图接线 | 3 | 还在画 Icon（= 没接）、路径拼错、已购态被换成位图 |
/// | G4 errorBuilder | 4 | 回退是死代码 / 素材缺失时空白 |
/// | G5 尺寸盒子 | 四 | 图标边长被改 / 盒子不再等于 size×size |
///
/// ⚠️ 不含 `pumpAndSettle`：天气行所在页面有无限呼吸动画，全程有界 `pump`。
library weather_art_assets_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 契约清单（**文件名即契约**，与 `assets/weather/` 逐字对应）
// ─────────────────────────────────────────────────────────────────────────────

/// 9 枚天气美术的文件名（不含目录）。
const List<String> _kWeatherArtFiles = <String>[
  'weather_sunny.webp',
  'weather_breeze.webp',
  'weather_cloudy.webp',
  'weather_overcast.webp',
  'weather_light_rain.webp',
  'weather_drought.webp',
  'weather_wind.webp',
  'weather_cold.webp',
  'weather_rainstorm.webp',
];

/// 4 枚道具美术的文件名（不含目录）。
const List<String> _kShelterArtFiles = <String>[
  'shelter_shade.webp',
  'shelter_rain.webp',
  'shelter_wind.webp',
  'shelter_warm.webp',
];

/// 素材目录（相对工程根）。
const String _kArtDir = 'assets/weather';

/// 工程根：测试从 `<root>/test/m3/` 起跑（与 `fx_frame_assets_guard_test` 同口径）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/m3') || cwd.endsWith('\\test\\m3')
      ? Directory.current.parent.parent.path
      : cwd;
}

/// WebP 容器校验：`RIFF` + `WEBP` 魔数 + 合法 chunk fourCC。
///
/// 只断「非空」不足以说明它是**图片**（一个空壳文件也能过），而真去解码又要引
/// `dart:ui` 的 codec（异步 + 与本用例无关的失败面）。校验容器头是最小充分判据：
///  · 字节 0..3 = `RIFF`、8..11 = `WEBP` ⇒ 确实是 WebP 容器；
///  · 字节 12..15 ∈ {`VP8 `, `VP8L`, `VP8X`} ⇒ 有真实图像载荷（不是只有头）。
void _expectValidWebP(Uint8List bytes, String name) {
  expect(bytes.length, greaterThan(64), reason: '$name 太小，几乎不可能是有效 WebP');
  final String riff = String.fromCharCodes(bytes.sublist(0, 4));
  final String webp = String.fromCharCodes(bytes.sublist(8, 12));
  final String chunk = String.fromCharCodes(bytes.sublist(12, 16));
  expect(riff, 'RIFF', reason: '$name 不是 RIFF 容器');
  expect(webp, 'WEBP', reason: '$name 不是 WebP（RIFF 内部签名不符）');
  expect(<String>['VP8 ', 'VP8L', 'VP8X'], contains(chunk),
      reason: '$name 的 chunk fourCC 是「$chunk」，不是合法 WebP 图像载荷');
}

// ─────────────────────────────────────────────────────────────────────────────
// 渲染宿主
// ─────────────────────────────────────────────────────────────────────────────

/// 极简宿主：只要求 `Material` 上下文（`Image` / `Icon` 都用不到主题）。
Widget _bare(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );

/// 天气行宿主（与 `weather_a6_tablet_matrix_test.dart` 同源）。
Widget _rowHost({required WeatherKind kind, required bool bought}) => MaterialApp(
      home: L10nScope(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 390,
              child: GardenWeatherRow(
                kind: kind,
                shelterRefType: kind.shelterRefType,
                bought: bought,
                affordable: true,
                showShelterButton: true,
                onShelterTap: () {},
                onPillTap: null,
              ),
            ),
          ),
        ),
      ),
    );

/// 有界推进（禁 `pumpAndSettle`）。
Future<void> _pumpBounded(WidgetTester tester, {int frames = 8}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final String root = _projectRoot();

  // ───────────────────────────────────────────────────────────────────────────
  // G1 · 资产实体（派工书 §五.1）
  // ───────────────────────────────────────────────────────────────────────────
  group('G1 · 13 枚素材实体存在且是有效 WebP', () {
    test('目录里正好这 13 枚，不多不少（文件名即契约，改名/漏交付都会红）', () {
      final Directory dir = Directory('$root/$_kArtDir');
      expect(dir.existsSync(), isTrue, reason: '素材目录缺失：$_kArtDir');
      final Set<String> onDisk = dir
          .listSync()
          .whereType<File>()
          .map((File f) => f.path.split(Platform.pathSeparator).last)
          .where((String n) => !n.startsWith('.')) // .DS_Store 之类不算素材
          .toSet();
      expect(
        onDisk,
        <String>{..._kWeatherArtFiles, ..._kShelterArtFiles},
        reason: '素材清单与契约不一致（多一个=塞了没登记的图；少一个=漏交付）',
      );
      expect(onDisk.length, 13);
    });

    test('每个文件非空且容器头合法（RIFF · WEBP · VP8/VP8L/VP8X）', () {
      for (final String name in <String>[
        ..._kWeatherArtFiles,
        ..._kShelterArtFiles,
      ]) {
        final File f = File('$root/$_kArtDir/$name');
        expect(f.existsSync(), isTrue, reason: '缺文件：$_kArtDir/$name');
        final Uint8List bytes = f.readAsBytesSync();
        expect(bytes.length, greaterThan(0), reason: '$name 是空文件');
        _expectValidWebP(bytes, name);
      }
    });

    test('13 枚都能被 rootBundle 读到且非空（= 真的打进了 asset bundle）', () async {
      // 🔴 这条与 G2（pubspec 文本）是**两道独立防线**：
      //    G2 断的是「配置里写了」，这条断的是「运行时真能读到」。
      //    只有前者时，改了缩进 / 写错路径前缀仍然会静默失效。
      for (final String name in <String>[
        ..._kWeatherArtFiles,
        ..._kShelterArtFiles,
      ]) {
        final ByteData data = await rootBundle.load('$_kArtDir/$name');
        expect(data.lengthInBytes, greaterThan(0),
            reason: 'rootBundle 读到 0 字节：$_kArtDir/$name');
        _expectValidWebP(data.buffer.asUint8List(), name);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // G2 · pubspec 登记（派工书 §五.2）
  // ───────────────────────────────────────────────────────────────────────────
  test('pubspec.yaml 已声明 `assets/weather/` 叶子目录（目录不递归）', () {
    final String pubspec = File('$root/pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('    - assets/weather/'),
      isTrue,
      reason: '🔴 Flutter 的 assets 目录声明**不递归**，漏这一行 = 13 枚图静默不进包'
          '（`Image.asset` 不抛异常，真机只显示空白）',
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // G3 · 位图接线（派工书 §五.3）
  // ───────────────────────────────────────────────────────────────────────────
  group('G3 · 真美术接线', () {
    test('9 种日型都有美术路径，且 9 条互不相同、都指向 weather_*.webp', () {
      final Set<String> paths = <String>{};
      for (final WeatherKind kind in WeatherKind.values) {
        final String p = weatherArtPathOf(kind);
        expect(p, startsWith('$_kArtDir/weather_'));
        expect(p, endsWith('.webp'));
        expect(paths.add(p), isTrue, reason: '${kind.name} 的路径与前面某型重复了');
      }
      expect(paths.length, WeatherKind.values.length,
          reason: '9 种日型必须一一对应 9 个不同文件');
      // 驼峰陷阱：`lightRain.name` 是 `lightRain`，磁盘契约是 `light_rain`。
      expect(weatherArtPathOf(WeatherKind.lightRain),
          endsWith('weather_light_rain.webp'),
          reason: '小雨的路径必须用**下划线**；用 kind.name 拼会拼成 lightRain');
      // 路径集合 == 磁盘文件集合（多/少都在这里红）。
      expect(paths, <String>{for (final String n in _kWeatherArtFiles) '$_kArtDir/$n'});
    });

    test('4 种道具都有美术路径；未知 refType 返回 null（不编路径）', () {
      const List<String> refTypes = <String>[
        kWeatherShelterRefTypeShade,
        kWeatherShelterRefTypeRain,
        kWeatherShelterRefTypeWind,
        kWeatherShelterRefTypeWarm,
      ];
      final Set<String> paths = <String>{};
      for (final String refType in refTypes) {
        final String? p = shelterArtPathOf(refType);
        expect(p, isNotNull, reason: '道具「$refType」必须有美术');
        expect(paths.add(p!), isTrue);
      }
      expect(paths, <String>{for (final String n in _kShelterArtFiles) '$_kArtDir/$n'});
      expect(shelterArtPathOf('shelter_unknown'), isNull,
          reason: '未知 refType 必须返回 null（让调用方直接给盾牌 Icon），'
              '不许编一个注定 404 的路径');
    });

    testWidgets('weatherArtOf：9 种日型渲染出来的都是 Image，路径逐一对得上',
        (WidgetTester tester) async {
      for (final WeatherKind kind in WeatherKind.values) {
        await tester.pumpWidget(_bare(weatherArtOf(kind, size: 18)));
        await tester.pump();
        expect(find.byType(Image), findsOneWidget,
            reason: '${kind.name} 必须画位图（若 findsNothing ⇒ 还在画 Icon = 没接）');
        final Image img = tester.widget<Image>(find.byType(Image));
        expect((img.image as AssetImage).assetName, weatherArtPathOf(kind));
        expect(find.byType(Icon), findsNothing,
            reason: '正常路径（素材存在）不该出现回退图标');
      }
    });

    testWidgets('shelterArtOf：4 种道具都是 Image；未知 refType 直接给盾牌 Icon',
        (WidgetTester tester) async {
      for (final String refType in <String>[
        kWeatherShelterRefTypeShade,
        kWeatherShelterRefTypeRain,
        kWeatherShelterRefTypeWind,
        kWeatherShelterRefTypeWarm,
      ]) {
        await tester.pumpWidget(_bare(shelterArtOf(refType, size: 14)));
        await tester.pump();
        expect(find.byType(Image), findsOneWidget, reason: '道具「$refType」必须是位图');
        final Image img = tester.widget<Image>(find.byType(Image));
        expect((img.image as AssetImage).assetName, shelterArtPathOf(refType));
      }

      await tester.pumpWidget(_bare(shelterArtOf('shelter_unknown', size: 14)));
      await tester.pump();
      expect(find.byType(Image), findsNothing,
          reason: '未知 refType 不该建 Image（省一次注定失败的异步 load）');
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        shelterIconOf('shelter_unknown'),
      );
    });

    testWidgets('整行装配：未购态 = 天气位图 + 道具位图；已购态 = 道具仍是 ✓ 图标',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      AppLocaleController.init(AppLanguage.zh);
      addTearDown(tester.view.reset);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));

      // ① 未购：天气胶囊 1 张图 + 道具按钮 1 张图 = 2 张，且**没有** ✓ 图标。
      await tester.pumpWidget(_rowHost(kind: WeatherKind.drought, bought: false));
      await _pumpBounded(tester);
      expect(find.byType(Image), findsNWidgets(2),
          reason: '未购态：天气图标 + 道具图标都必须走位图');
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      // ② 已购：道具侧**必须**仍是 Material ✓（§9.5 完成态语义优先于美术），
      //    所以只剩天气那 1 张图。
      await tester.pumpWidget(_rowHost(kind: WeatherKind.drought, bought: true));
      await _pumpBounded(tester);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget,
          reason: '已购态换成位图会让「做成 / 没做成」的判别变模糊（A2 已封版）');
      expect(find.byType(Image), findsOneWidget,
          reason: '已购态只剩天气那一张位图；道具侧不该再画 Image');
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // G4 · errorBuilder 回退（派工书 §五.4 —— 证明它不是死代码）
  // ───────────────────────────────────────────────────────────────────────────
  group('G4 · errorBuilder 回退路径可验证', () {
    // 注入方式：两个美术函数都留了 `assetPath` 可选参数（**生产恒不传**），
    // 测试传一个必然不存在的路径 ⇒ `Image.asset` 的异步加载失败 ⇒ 走 errorBuilder。
    const String missing = '$_kArtDir/__definitely_not_here__.webp';

    testWidgets('weatherArtOf(坏路径)：回退到同尺寸 Material 图标，无 RawImage、无异常',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _bare(weatherArtOf(WeatherKind.sunny, size: 18, assetPath: missing)),
      );
      await _pumpBounded(tester);

      // 🔴 关键断言：`Icon` **只可能**由 errorBuilder 产生（成功路径里没有 Icon）。
      //    它出现 = 回退真的跑了；不出现 = errorBuilder 是死代码 / 根本没触发。
      expect(find.byType(Icon), findsOneWidget,
          reason: '素材缺失时必须回退成 Material 图标，而不是留一块空白');
      final Icon icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, weatherIconOf(WeatherKind.sunny));
      expect(icon.size, 18, reason: '回退图标的盒子必须与位图同为 size ⇒ 几何不跳动');
      expect(icon.color, kWeatherTextColor,
          reason: '回退色必须与 A2 时期一致（否则「有美术/没美术」两种环境观感不同）');
      expect(find.byType(RawImage), findsNothing,
          reason: '回退态不该有任何位图在渲染');
      expect(tester.takeException(), isNull,
          reason: '美术缺失绝不许把异常抛进 build（`growth_icons.dart:8` 的口径）');
    });

    testWidgets('shelterArtOf(坏路径)：同上，且回退到 GoldNoticeStyle.buttonFg',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _bare(shelterArtOf(kWeatherShelterRefTypeShade,
            size: 14, assetPath: missing)),
      );
      await _pumpBounded(tester);

      expect(find.byType(Icon), findsOneWidget);
      final Icon icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, shelterIconOf(kWeatherShelterRefTypeShade));
      expect(icon.size, 14);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('对照组：同一函数传真实路径时**不产生** Icon（证明 G4 断的是回退分支）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _bare(weatherArtOf(WeatherKind.sunny, size: 18)),
      );
      await _pumpBounded(tester);
      expect(find.byType(Icon), findsNothing,
          reason: '有素材时不该走回退 —— 若这里也 findsOneWidget，'
              '说明 G4 上一条是「恒回退」而不是「选对分支」');
      expect(find.byType(Image), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // G5 · 尺寸盒子不变（派工书 §四：18 / 14 一个字都不许改）
  // ───────────────────────────────────────────────────────────────────────────
  group('G5 · 图标边长与盒子尺寸', () {
    test('逻辑尺寸常量仍是 18 / 14（改了会让 A2 的 5 档压缩阶梯与 noHint 阈值失效）', () {
      expect(kWeatherPillIconSize, 18);
      expect(kShelterIconSize, 14);
      // 顺带把「道具图标故意比天气小一档」这条设计意图也钉住。
      expect(kShelterIconSize, lessThan(kWeatherPillIconSize));
    });

    testWidgets('weatherArtOf 的宿主盒子正好是 size×size（与 Icon(size:) 逐位同尺寸）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_bare(weatherArtOf(WeatherKind.sunny, size: 18)));
      await tester.pump();
      final Size s = tester.getSize(find.byType(Image));
      expect(s.width, 18);
      expect(s.height, 18,
          reason: '🔴 `Image` 若不给 width/height，会按原图 288² 布局 ⇒ 直接撑爆天气行');
    });

    testWidgets('shelterArtOf 的宿主盒子正好是 size×size', (WidgetTester tester) async {
      await tester.pumpWidget(
        _bare(shelterArtOf(kWeatherShelterRefTypeRain, size: 14)),
      );
      await tester.pump();
      final Size s = tester.getSize(find.byType(Image));
      expect(s.width, 14);
      expect(s.height, 14);
    });
  });
}
