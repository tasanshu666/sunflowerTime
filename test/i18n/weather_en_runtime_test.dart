/// 天气系统 A6 期 · **运行时切 en 后的天气文案 + 盛开卡英文溢出** 守卫。
///
/// ## 为什么需要这份文件（A6 盘点结论）
/// A1~A5 把天气系统的 zh/en 两套 ARB **都写完了**，但运行期**从来没有一条用例
/// 真的把语言切到 en 再去看天气行**：
///  · `weather_a2_test.dart` / `weather_a5_eta_test.dart` 全在默认 zh 下跑；
///  · `test/i18n/*` 那批 en 守卫覆盖的是家长端页面 / premium_gate / 种子名，
///    **没有一条碰过 `weather_status_bar.dart` 的 9 个日型**；
///  · 唯一和天气沾边的 `weather_a4_quota_test.dart:878` 只查「文案里不许有汉字」，
///    它读的是 ARB getter，**不经过 `L10nScope`**。
///
/// 于是有一个**完全静默**的失败模式没人守：`weather_status_bar` 用
/// `l10nOf(context)` 取文案（`weather_status_bar.dart:926`），而
/// `l10nOf` 在没有 `Localizations` 祖先时会**静默退回中文**
/// （`l10n_scope.dart`）。只要有人把页面上的 `L10nScope` 摘掉、或者某个新页面
/// 忘了包，孩子看到的天气行会一直是中文 —— 不报错、不红、不抛异常。
/// 只有「切 en 之后中文必须**消失**」这个反向断言能抓到它。
///
/// ## 覆盖的 5 条天气键（对齐 F5 工单）
/// | # | key | 在哪条用例 |
/// |---|---|---|
/// | ① | `garden_help_weather_title` | E2a |
/// | ② | `garden_help_weather_body`  | E2a |
/// | ③ | `garden_shelter_confirm_title` | E2b |
/// | ④ | `garden_shelter_confirm_message` | E2b |
/// | ⑤ | `garden_shelter_confirm_ok` | E2b |
///
/// 另加 E1（9 日型 × 名字/提示语/道具名，双向）与 E3（盛开卡 en 溢出探针）。
///
/// ## 口径纪律
///  · 🔴 **期望值来自 `app_en.arb` / `app_zh.arb` 的原文**，不来自实现常量：
///    `en` / `zh` 两个 `AppLocalizations` 实例是被测文案的**唯一真源**，
///    用例只断言「渲染出来的字 == ARB 里的字」，不 reimplement 任何拼装规则。
///  · 🔴 **每条 en 断言都配一条 zh 反向断言**：只证「en 出现了」会漏掉
///    「中英同时出现」；只证「zh 不见了」会漏掉「什么都没渲染」。两条一起才有意义。
///  · 🔴 有界 pump（禁 `pumpAndSettle`：花园行里有无限动画基线）。
library weather_en_runtime_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_card.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';

/// 汉字 + 中文标点 + 全角区段（与 `test/i18n/enum_l10n_test.dart` 同口径）。
final RegExp _cjk =
    RegExp(r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]');

/// en / zh 两套真实资源实例（被测文案的唯一真源）。
final AppLocalizations _en = AppLocalizationsEn();
final AppLocalizations _zh = AppLocalizationsZh();

/// 天气行宿主：与 `garden_page.dart` 同构（`L10nScope` + 满宽）。
///
/// 宽度取 1176（1200 视口 − 2×12 内距）⇒ 压缩阶梯**必然停在最宽档 ①**，
/// 名字、提示语、道具名三块**全部在树里**。若宽度不够落到 ③/④/⑤ 档，
/// 名字会被整块撤出树 ⇒ `find.text` 零命中，那时红的是**视口设小了**，
/// 不是文案错了。这正是本条必须钉死视口的原因。
Widget _rowHost(WeatherKind kind, {double width = 1176}) {
  return MaterialApp(
    home: L10nScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: GardenWeatherRow(
              key: kWeatherRowKey,
              kind: kind,
              shelterRefType: kind.shelterRefType,
              bought: false,
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
}

/// 天气行里**所有**渲染出来的纯文本（`Text` → `RichText` → `RenderParagraph`）。
List<String> _rowTexts(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byKey(kWeatherRowKey),
        matching: find.byType(RichText),
      ),
    )
    .map((RenderParagraph p) => p.text.toPlainText())
    .toList();

/// 整棵树里**所有** `Text` 的数据（不含富文本 span 拼接）。
List<String> _allTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data)
    .whereType<String>()
    .toList();

/// 有界帧推进（禁 `pumpAndSettle`）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 4}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// ── E3 用的固定物种 / 盛开株 ─────────────────────────────────────────────────

/// 向日葵（`growthHoursPerStage` 与种子表同口径，不在测试里另编数值）。
const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: 'Sunflower',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

final DateTime _bloomedAt = DateTime(2026, 5, 12, 9);

Plant _bloomedPlant() => Plant(
      id: 'plant-en-bloomed',
      speciesId: _sunflower.id,
      potIndex: 0,
      stage: PlantStage.adult,
      stageStartedAt: _bloomedAt,
      growthProgress: 1.0,
      growthFactor: 1.0,
      status: PlantStatus.bloomed,
      plantedAt: _bloomedAt,
      bloomedAt: _bloomedAt,
      bloomCount: 1,
    );

PlantCareQuota _quotaAt(DateTime at, WeatherDay day) => PlantCareQuota(
      waterUsedToday: 0,
      fertilizeUsedToday: 0,
      minutesUntilNextWater: 0,
      waterBlockReason: null,
      fertilizeBlockReason: null,
      waterQuota: 3,
      weather: day,
      observedAt: at,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // E1 · 9 日型：en 下渲染英文名 / 英文提示语 / 英文道具名，且中文整体不在树里
  //
  // 为什么用 `for (kind)` 生成**独立** `testWidgets`（工单明确要求）：
  //   若写成「一条 testWidgets 内层 for 循环 9 个日型」，第一个日型断言失败会
  //   **中断整条用例**，后 8 个日型根本不执行 ⇒ 一次只暴露一个 bug，
  //   修完再跑又红下一个。独立用例才能一次报全 9 个，且失败名直接点出日型。
  // ══════════════════════════════════════════════════════════════════════════
  group('E1 · 运行时切 en：9 日型的天气行', () {
    for (final WeatherKind kind in WeatherKind.values) {
      testWidgets('${kind.name}：en 渲染英文名/提示/道具名，中文一并消失',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200 * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        AppLocaleController.init(AppLanguage.en);
        addTearDown(() => AppLocaleController.init(AppLanguage.system));

        final String enName = weatherNameOf(kind, _en);
        final String zhName = weatherNameOf(kind, _zh);

        // ── 前置：中英名字必须真的不同，否则下面「zh 消失」恒真（假绿）──────
        expect(enName, isNot(equals(zhName)),
            reason: '前置：${kind.name} 的 en/zh 名字相同（都=$enName），'
                '「切 en 后 zh 消失」这条断言会恒绿、等于没测');
        // 前置：en 名字本身不得含汉字（ARB 漏翻 / 复制粘贴错了）。
        expect(_cjk.hasMatch(enName), isFalse,
            reason: 'app_en.arb 的 weather_name(${kind.name}) 含汉字：$enName');

        await tester.pumpWidget(_rowHost(kind));
        await _pumpFrames(tester);

        // ── ① en 正向：英文名在树里 ──────────────────────────────────────
        expect(find.text(enName), findsOneWidget,
            reason: 'en 下 ${kind.name} 必须渲染英文名「$enName」');
        // ── ② en 反向：中文名必须整体消失（这条才抓得到「忘了包 L10nScope」）──
        expect(find.text(zhName), findsNothing,
            reason: 'en 下不得出现中文名「$zhName」—— 出现即说明文案回退到了 zh；'
                '`l10nOf` 在没有 Localizations 祖先时会**静默**回退中文，不报错');

        // ── ③ 提示语（大风 / 极寒返回 null，这两档没有提示语，是独立结构分支）──
        final String? enHint = weatherHintOf(kind, _en);
        final String? zhHint = weatherHintOf(kind, _zh);
        if (enHint == null) {
          // 风 / 寒：`weatherHintOf` 契约就是 null（PRD §5.4：强制动作已由按钮表达）。
          expect(zhHint, isNull,
              reason: '${kind.name} 的 en 提示语为 null，zh 却非 null —— 两套 ARB 不一致');
          expect(find.textContaining('· '), findsNothing,
              reason: '${kind.name} 不该有提示语（`weatherHintOf` 返回 null），'
                  '但树里出现了「· …」');
        } else {
          // 提示语在实现里拼成 `'· $hint'`（`weather_status_bar.dart:813`）。
          // 这里断言的是**完整那句**（前缀 + ARB 原文），不改写。
          expect(find.text('· $enHint'), findsOneWidget,
              reason: 'en 下 ${kind.name} 必须渲染英文提示语「· $enHint」');
          expect(find.text('· $zhHint'), findsNothing,
              reason: 'en 下不得出现中文提示语「· $zhHint」');
          expect(_cjk.hasMatch(enHint), isFalse,
              reason: 'app_en.arb 的 garden_weather_hint(${kind.name}) 含汉字：$enHint');
        }

        // ── ④ 道具名（只有极端日才有按钮；温和日 `shelterRefType == null`）────
        final String? refType = kind.shelterRefType;
        if (refType == null) {
          expect(find.byKey(kShelterButtonVisualKey), findsNothing,
              reason: '${kind.name} 是温和日，道具按钮整个不得渲染');
        } else {
          final String enShelter = shelterNameOf(refType, _en);
          final String zhShelter = shelterNameOf(refType, _zh);
          expect(enShelter, isNot(equals(zhShelter)),
              reason: '前置：道具名 en/zh 相同（都=$enShelter），反向断言会恒绿');
          expect(find.text(enShelter), findsOneWidget,
              reason: 'en 下 ${kind.name} 必须渲染英文道具名「$enShelter」');
          expect(find.text(zhShelter), findsNothing,
              reason: 'en 下不得出现中文道具名「$zhShelter」');
        }

        // ── ⑤ 行内**全部**文本零汉字：不靠「我列了哪几条」，靠全扫 ──────────
        // 这一条是兜底：将来行里新增任何一块文本（比如加一句天气说明），
        // 忘了接 l10n 就会被它抓到，而不必再来补一条用例。
        final List<String> texts = _rowTexts(tester);
        expect(texts, isNotEmpty, reason: '前置：天气行里必须有文本，否则上面全是空转');
        final List<String> leak = texts.where(_cjk.hasMatch).toList();
        expect(leak, isEmpty,
            reason: 'en 下天气行里仍有汉字：$leak（全行文本=$texts）');
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // E2a · 玩法弹窗的天气段（`garden_help_weather_title` / `_body`）
  //
  // 弹窗自己包了 `L10nScope`（`garden_help_sheet.dart:56`「底部弹层上下文在页面
  // scope 之外」），所以这条用例**故意不包**外层 L10nScope —— 验的就是弹窗
  // **自带**作用域这条约定。若有人删掉它内部那层，本用例立刻红。
  // ══════════════════════════════════════════════════════════════════════════
  group('E2a · 玩法弹窗：天气段运行时切 en', () {
    testWidgets('en 下渲染英文天气段标题与正文，中文一并消失',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      AppLocaleController.init(AppLanguage.en);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));

      await tester.pumpWidget(
        // 🔴 故意**不**在宿主包 L10nScope：弹窗必须自带（见上方注释）。
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GardenHelpSheet(capacity: 4, expandCost: 120),
            ),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text(_en.garden_help_weather_title), findsOneWidget,
          reason: 'en 下必须渲染天气段标题「${_en.garden_help_weather_title}」'
              '（若弹窗内部那层 L10nScope 被删，这里会退回中文并红）');
      expect(find.text(_zh.garden_help_weather_title), findsNothing,
          reason: 'en 下不得出现中文标题「${_zh.garden_help_weather_title}」');

      expect(find.text(_en.garden_help_weather_body), findsOneWidget,
          reason: 'en 下必须渲染天气段正文');
      expect(find.text(_zh.garden_help_weather_body), findsNothing,
          reason: 'en 下不得出现中文正文');

      // 正文本身不得含汉字（ARB 漏翻）。
      expect(_cjk.hasMatch(_en.garden_help_weather_body), isFalse,
          reason: 'app_en.arb 的 garden_help_weather_body 含汉字');

      // 第十一批新增「花园天气」通俗介绍段（玄参：玩法里要介绍天气）——
      // 同样必须随语言切换，且英文 ARB 不得漏翻。
      expect(find.text(_en.garden_help_weather_intro_title), findsOneWidget,
          reason: 'en 下必须渲染「花园天气」段标题');
      expect(find.text(_zh.garden_help_weather_intro_title), findsNothing,
          reason: 'en 下不得出现中文「花园天气」标题');
      expect(find.text(_en.garden_help_weather_intro_body), findsOneWidget,
          reason: 'en 下必须渲染花园天气介绍正文');
      expect(find.text(_zh.garden_help_weather_intro_body), findsNothing,
          reason: 'en 下不得出现中文介绍正文');
      expect(_cjk.hasMatch(_en.garden_help_weather_intro_body), isFalse,
          reason: 'app_en.arb 的 garden_help_weather_intro_body 含汉字');
      expect(_cjk.hasMatch(_en.garden_help_weather_intro_title), isFalse,
          reason: 'app_en.arb 的 garden_help_weather_intro_title 含汉字');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // E2b · 搭棚确认卡 3 键（资源层直取）
  //
  // 为什么这 3 条走 `AppLocalizationsEn()` 而不是 pump widget：确认卡由
  // `showDialog` 在页面栈顶弹出，装配它要拉起整个花园页状态（阳光余额 / 账本 /
  // 天气快照），成本远高于收益 —— 而这 3 条键**没有任何运行期变量**，唯一需要
  // 守住的是「en 有译文、译文不残、语义不丢」。资源层直取是**更窄、更准**的口径。
  // ══════════════════════════════════════════════════════════════════════════
  group('E2b · 搭棚确认卡 3 键（资源层）', () {
    test('title 带占位符插值，且与 zh 不同、不含汉字', () {
      // 用 ARB 里真实存在的道具名做插值实参（不是编的字符串）。
      const String enShelter = 'Shade awning';
      final String enTitle = _en.garden_shelter_confirm_title(enShelter);
      final String zhTitle = _zh.garden_shelter_confirm_title('遮阳棚');

      expect(enTitle.contains(enShelter), isTrue,
          reason: 'en title 必须把道具名插进去，实测「$enTitle」不含「$enShelter」');
      expect(enTitle, isNot(equals(zhTitle)),
          reason: 'en title 与 zh title 相同（都=$enTitle）—— 说明 en 漏翻');
      expect(_cjk.hasMatch(enTitle), isFalse,
          reason: 'en title 含汉字：「$enTitle」');
    });

    test('message 保留「棚只管一天」语义（这句是玩法核心，不许在翻译里丢）', () {
      final String enMsg = _en.garden_shelter_confirm_message;
      expect(enMsg.trim(), isNotEmpty, reason: 'en message 不得为空');
      expect(_cjk.hasMatch(enMsg), isFalse, reason: 'en message 含汉字：「$enMsg」');
      // 🔴 语义守卫：zh 原文是「棚只管今天，明天要重新搭」，这是**玩法规则**
      //    （棚次日失效，见 F2-Q2 的跨零点用例）。译文把「只一天」翻丢了，
      //    孩子/家长就会以为搭一次永久有效。
      expect(enMsg.toLowerCase().contains('one day'), isTrue,
          reason: 'en message 必须保留「只一天」语义（实测「$enMsg」）。'
              '丢掉它 = 翻译把玩法规则翻没了，而 zh 用例一条都抓不住');
    });

    test('ok 按钮文案非空、不含汉字、且与 message/title 都不同', () {
      final String enOk = _en.garden_shelter_confirm_ok;
      expect(enOk.trim(), isNotEmpty, reason: 'en ok 不得为空');
      expect(_cjk.hasMatch(enOk), isFalse, reason: 'en ok 含汉字：「$enOk」');
      expect(enOk, isNot(equals(_en.garden_shelter_confirm_message)),
          reason: 'ok 与 message 同文 —— 按钮上会显示一整段话');
      expect(enOk, isNot(equals(_en.garden_help_weather_title)),
          reason: 'ok 与天气段标题同文 —— 疑似复制粘贴串键');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // E3 · 盛开卡 en 窄宽溢出探针
  //
  // en 的 `card_hint_bloomed`（"In bloom 🌻 daily care keeps tomorrow's dew
  // sunlight full"）比中文长得多（中文 20 字 → 英文 60 字符），窄宽下最容易
  // RenderFlex overflow。既有 `qa_b2_ui_probes_test.dart` 那 4 条花期剩余用例
  // **全在 zh 下跑**，en 的三行文案一次都没在真宽度里排过版。
  // ══════════════════════════════════════════════════════════════════════════
  group('E3 · 盛开卡 en 窄宽（300）', () {
    testWidgets('零溢出异常、英文「已开花」提示在树里、整卡无汉字',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(300 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      AppLocaleController.init(AppLanguage.en);
      addTearDown(() => AppLocaleController.init(AppLanguage.system));

      final Plant plant = _bloomedPlant();
      // 前置：盛开依据是进度已满（`_nextStageHint` 的 `remaining == 0` 来源）。
      expect(plant.growthProgress, 1.0, reason: '前置：盛开态进度必须是 1.0');

      await tester.pumpWidget(
        MaterialApp(
          home: L10nScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 300,
                  child: PlantCard(
                    plant: plant,
                    species: _sunflower,
                    quota: _quotaAt(_bloomedAt, WeatherSystem.ofDay(_bloomedAt)),
                    onWater: () {},
                    onFertilize: () {},
                    onClear: () {},
                    onShovel: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, frames: 6);

      // ── ① 渲染期零异常（RenderFlex overflow 会在这里抛）─────────────────
      expect(tester.takeException(), isNull,
          reason: 'en 的盛开提示比中文长得多，300 宽下不得溢出。'
              '（若这里红，多半是某行忘了 maxLines / Flexible）');

      // ── ② 英文提示在树里（且中文那条不在）──────────────────────────────
      expect(find.text(_en.card_hint_bloomed), findsOneWidget,
          reason: 'en 下盛开卡必须渲染英文「已开花」提示');
      expect(find.text(_zh.card_hint_bloomed), findsNothing,
          reason: 'en 下不得出现中文盛开提示（l10nOf 静默回退中文的典型症状）');

      // ── ③ 整卡零汉字（兜底：卡片里任何一块漏接 l10n 都会被这条抓到）─────
      final List<String> texts = _allTexts(tester);
      expect(texts, isNotEmpty, reason: '前置：卡片里必须有文本');
      final List<String> leak = texts.where(_cjk.hasMatch).toList();
      expect(leak, isEmpty,
          reason: 'en 下盛开卡里仍有汉字：$leak（全卡文本=$texts）');
    });
  });
}
