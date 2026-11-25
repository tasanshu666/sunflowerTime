/// 家长端·解锁全部功能页（付费墙 · 阶段 3 第二批）。
///
/// 职责：把「一次性永久买断」的完整购买体验收在一处 ——
///  · 展示**商店返回的本地化价格**（`IapProduct.price`，绝不硬编码金额 / `$`）；
///  · 发起购买、提供 **Apple 硬性要求的「恢复购买」** 入口；
///  · 把一次性买断的**真实边界**如实写给家长（非订阅 / 换机可恢复 / 跨平台不可
///    恢复 / 支付由 Apple 完成、开发者不接触支付信息）。
///
/// 状态机（全部覆盖）：`加载中` / `加载失败·商店不可用`（降级文案 + 主按钮禁用，
/// 绝不崩）/ `未解锁` / `已解锁` / `购买中` / `激活中`（Android 激活码）。
///
/// ## Android 官网直供版（激活码解锁）
///
/// Android 版**不上任何应用商店**（国内买断制无法在国产品牌商店上架），故 Android 侧
/// 没有可用的 Play Billing 商品：本页在 Android 上**不查商店**（否则必然落到「暂时连不上
/// 商店」的降级态），主按钮直接变成「输入激活码解锁」→ 弹框粘贴 → 域层离线验签
/// （`RedeemCodeActivator`）→ 票据落库即解锁。
///
/// 🔴 **iOS 链路一字未动**：iOS（及桌面调试 / widget 测试宿主）上
/// [defaultRedeemCodeEntryEnabled] 为 false，主按钮 / 商店加载 / 说明文案
/// **逐字节保持原样**，仍走 StoreKit → `purchaseLifetime`。
///
/// C83 布局纪律：**主按钮 + 恢复入口常驻吸底**（`Scaffold.bottomNavigationBar`），
/// 不随列表滚动 —— 真实 400×800 视口下原先两者在列表末尾，家长要滑 ≈480pt 才看到
/// 「立即解锁」。底栏高度由内容撑开（禁写死高度，平板 textScaler 1.3× 亦不溢出）。
///
/// 设计纪律（对齐架构 §「门控单点收口」+ 依赖倒置）：
///  · 平台细节全部走**纯 Dart 契约** [`IapClient`]（本页**不** import
///    `in_app_purchase`），故可脱离真实插件单测；
///  · 购买 / 恢复走**域层** [`EntitlementService`]（落库票据 + 更新内存态），成功后
///    刷新 [`entitlementProvider`]，使家长端设置页副标题与本页状态同步；
///  · 商店不可用 / 取消 / 失败一律安全降级（域服务已保证不裸抛），本页再兜一层 try/catch。
library parent_premium_page;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/widgets/premium_unlock_table.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
// 场景卡称号条数别名 kPremiumTitlePerkCount 的唯一来源（守卫⑤：家长端禁直引等级常量）。
import 'package:sunflower_time/presentation/shared/premium_gate.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 页内统一色（暖色儿童风：深字 + 柔灰字，白底卡由 [creamCardDecoration] 提供）。
const Color _kInk = Color(0xFF6B6252);
const Color _kInkSoft = Color(0xFF9C917E);
const Color _kUnlocked = Color(0xFF2E7D32);

/// 主购买按钮 Key（供测试稳定定位；文案随状态变化）。
const Key kPremiumMainButtonKey = Key('premiumMainButton');

/// 「恢复购买」按钮 Key。
const Key kPremiumRestoreButtonKey = Key('premiumRestoreButton');

/// 激活码输入框 Key（Android 弹框内，供测试定位）。
const Key kPremiumRedeemCodeFieldKey = Key('premiumRedeemCodeField');

/// 激活码弹框「解锁」确认按钮 Key。
const Key kPremiumRedeemCodeConfirmKey = Key('premiumRedeemCodeConfirm');

/// 读剪贴板的超时上限（超过即当作「剪贴板为空」）。
///
/// 正常剪贴板读取是毫秒级；设 2s 是为了兜住「平台通道缺失 → Future 永不完成」的
/// 极端情况（`flutter test` 宿主即如此，实测会一直挂着）。
const Duration kPremiumClipboardTimeout = Duration(seconds: 2);

/// 当前进程是否**真的**运行在 Android 上（真机 / 模拟器 / 集成测试）。
///
/// 🔴 **为什么不用 `defaultTargetPlatform`**（这是本页踩过的真坑）：
/// `flutter_test` 会把 `defaultTargetPlatform` **硬钉成 `TargetPlatform.android`**
/// —— 那是 Material 的样式默认值，**不代表真实设备**。若本页直接采信它，
/// Android 专属分支（不查商店 / 主按钮变激活码 / 隐藏恢复购买 / 换说明文案）
/// 会在**所有** widget 测试里生效，把 iOS 口径的既有守卫（主按钮文案、
/// 吸底结构、Apple 要求的「恢复购买」入口、320pt 零溢出）全部推翻（实测 18 个用例红）。
///
/// 故这里读 `dart:io` 的真实宿主平台，口径与 `AppLocaleController` 的
/// 「测试宿主」判定一致：`kIsWeb` 先行、`Platform` 调用包在 try 里（拿不到 → false，
/// 安全侧：宁可不显示激活码入口，也不要污染 iOS / 桌面端）。
bool get isAndroidRuntime {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

/// 「是否显示激活码入口」的**当前生效解析器**。
///
/// 生产恒为 [defaultRedeemCodeEntryEnabled]；**测试可整体替换**
/// （先例：`core/utils/external_link.dart` 的 `externalLinkOpener`），
/// 从而在 macOS 宿主的 widget 测试里也能覆盖 Android 分支的真实 UI 行为。
///
/// ⚠️ 替换后务必在 `addTearDown` 里还原成 [defaultRedeemCodeEntryEnabled]，
/// 否则同文件后续用例共享脏状态（本仓已因「全局单例残留」翻过车，见 F155）。
bool Function() redeemCodeEntryEnabledResolver = defaultRedeemCodeEntryEnabled;

/// 生产判定（测试还原时引用它，禁止再新写一份逻辑）。
///
/// 策略：**只有 Android 用激活码解锁**。iOS 必须继续走 StoreKit（绕过 Apple IAP
/// 会被拒审），macOS / Windows / Linux 仅用于开发者调试，一律保持 IAP 原状。
bool defaultRedeemCodeEntryEnabled() => isAndroidRuntime;

/// 家长端·解锁全部功能页。
class ParentPremiumPage extends ConsumerStatefulWidget {
  const ParentPremiumPage({super.key});

  @override
  ConsumerState<ParentPremiumPage> createState() => _ParentPremiumPageState();
}

class _ParentPremiumPageState extends ConsumerState<ParentPremiumPage> {
  /// 首屏商品加载中。
  bool _loading = true;

  /// 商店不可用 / 商品拉取失败（离线降级）。
  bool _storeUnavailable = false;

  /// 购买进行中。
  bool _buying = false;

  /// 恢复购买进行中。
  bool _restoring = false;

  /// 激活码激活进行中（Android）。
  bool _activating = false;

  /// 商店返回的买断商品（`price` 为商店本地化价格串）。
  IapProduct? _product;

  /// 当前平台是否用激活码解锁（Android 官网直供版）。
  ///
  /// 每次 getter 现算而**不缓存**：解析器可能被测试整体替换，现算才能让
  /// 「同一次 pump 前后切换平台」立即生效（不缓存 = 没有「上次平台」的脏状态）。
  bool get _usesRedeemCode => redeemCodeEntryEnabledResolver();

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  /// 拉取商品详情（本地化价格）。失败 / 商店不可用 → 置降级态，绝不抛。
  ///
  /// 🔴 Android（官网直供版）**不查商店**：Play Billing 未接入、商品也未在商店登记，
  /// 查询必然返回空列表 → 页面会落到「暂时连不上商店」的降级态并禁用主按钮，而
  /// Android 的价格来自官网、根本不需要商店串。故此处直接置「可用」并跳过查询。
  Future<void> _loadProduct() async {
    if (_usesRedeemCode) {
      if (mounted) {
        setState(() {
          _loading = false;
          _storeUnavailable = false;
          _product = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _storeUnavailable = false;
      });
    }
    IapProduct? product;
    try {
      final IapClient client = ref.read(iapServiceProvider);
      final List<IapProduct> products = await client.loadProducts();
      product = _pickLifetime(products);
    } catch (_) {
      // IapService.loadProducts 已保证不抛；此处再兜一层，双保险。
      product = null;
    }
    if (!mounted) return;
    setState(() {
      _product = product;
      _storeUnavailable = product == null;
      _loading = false;
    });
  }

  /// 从商品列表中挑出**买断商品**（必须 ID 命中，避免误展示其它商品的价格）。
  static IapProduct? _pickLifetime(List<IapProduct> products) {
    for (final IapProduct p in products) {
      if (p.id == kIapProductIdLifetime) return p;
    }
    return null;
  }

  /// 购买：走域层（落库票据 + 刷新内存态），再同步 [entitlementProvider]。
  Future<void> _buy() async {
    if (_buying || _restoring || _storeUnavailable) return;
    // i18n B2：SnackBar 在 overlay 内重建 → 文案在此处（页级 scope 内）取好。
    final AppLocalizations t = l10nOf(context);
    setState(() => _buying = true);
    try {
      await ref.read(entitlementServiceProvider).purchaseLifetime();
      final Entitlement e = await ref.read(entitlementServiceProvider).load();
      ref.read(entitlementProvider.notifier).state = e;
      _snack(e.isPremium
          ? t.parent_premium_snack_unlocked
          : t.parent_premium_snack_incomplete);
    } catch (_) {
      _snack(t.parent_premium_snack_buy_failed);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  /// 恢复购买：三态各有明确反馈（**Apple 硬性要求入口**）。
  Future<void> _restore() async {
    if (_restoring || _buying) return;
    final AppLocalizations t = l10nOf(context);
    setState(() => _restoring = true);
    try {
      final RestoreResult r =
          await ref.read(entitlementServiceProvider).restore();
      final Entitlement e = await ref.read(entitlementServiceProvider).load();
      ref.read(entitlementProvider.notifier).state = e;
      switch (r) {
        case RestoreResult.restored:
          _snack(t.parent_premium_snack_restored);
        case RestoreResult.nothingToRestore:
          _snack(t.parent_premium_snack_nothing);
        case RestoreResult.failed:
          _snack(t.parent_premium_snack_restore_net);
      }
    } catch (_) {
      _snack(t.parent_premium_snack_restore_failed);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// 用**激活码**解锁（Android 官网直供版）。
  ///
  /// 流程：弹框（输入框 + 「从剪贴板粘贴」）→ 域层离线验签（`RedeemCodeActivator`）
  /// → 成功则刷新 [`entitlementProvider`] 并提示；六种结果各有明确反馈，
  /// **全程不抛**（域服务已保证 + 本页再兜一层 try/catch）。
  ///
  /// 能力探测走 `is RedeemCodeActivator`（本项目的能力扩展模式）：拿不到该能力时
  /// 退化为一句「请稍后重试或联系我们」，不崩、不误放。
  Future<void> _activateWithCode() async {
    if (_activating || _buying || _restoring) return;
    // i18n B2：SnackBar / 弹框在 overlay 内重建 → 文案在此处（页级 scope 内）取好。
    final AppLocalizations t = l10nOf(context);
    final EntitlementService service = ref.read(entitlementServiceProvider);
    // 能力探测（本项目的能力扩展模式）：不实现该接口的实现类自动降级为「无激活能力」。
    // ⚠️ 必须显式 down-cast：Dart 的 `is` 只在「被测类型是声明类型的子类型」时才做
    // 类型提升，而 [RedeemCodeActivator] 与 [EntitlementService] 是**平级的两条接口**
    // （谁也不是谁的子类型）→ 不 cast 直接调会编译报错（F142 首次实现即踩过）。
    if (service is! RedeemCodeActivator) {
      _snack(t.parent_premium_code_snack_retry);
      return;
    }
    final RedeemCodeActivator activator = service as RedeemCodeActivator;

    final String? code = await _promptRedeemCode(t);
    if (code == null || !mounted) return;

    setState(() => _activating = true);
    try {
      final RedeemActivationResult result = await activator.activate(code);
      // 无论成功与否都重读一次票据：`alreadyPremium` 也需要把 UI 态对齐真实票据
      // （例如上一次激活写库成功但进程被杀，UI 还停在 free）。
      final Entitlement e = await service.load();
      ref.read(entitlementProvider.notifier).state = e;
      switch (result) {
        case RedeemActivationResult.activated:
          _snack(t.parent_premium_snack_unlocked);
        case RedeemActivationResult.alreadyPremium:
          _snack(t.parent_premium_code_snack_already);
        case RedeemActivationResult.malformedCode:
          _snack(t.parent_premium_code_snack_malformed);
        case RedeemActivationResult.invalidCode:
          _snack(t.parent_premium_code_snack_invalid);
        case RedeemActivationResult.notConfigured || RedeemActivationResult.failed:
          // 这两种都不是用户的错（配置 / 落库异常）→ 统一「稍后重试或联系我们」，
          // 绝不谎报「激活码无效」而让已付费用户以为自己被骗。
          _snack(t.parent_premium_code_snack_retry);
      }
    } catch (_) {
      _snack(t.parent_premium_code_snack_retry);
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  /// 弹「输入激活码」对话框；返回清理后的码，用户取消 → null。
  Future<String?> _promptRedeemCode(AppLocalizations t) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _RedeemCodeDialog(t: t),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final Entitlement entitlement = ref.watch(entitlementProvider);
    final ThemeData theme = parentThemeFor(Theme.of(context).brightness);
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析；Builder 的
    // 上下文在 scope **之内**，故可直调 `AppLocalizations.of`。
    return L10nScope(
      child: Builder(builder: (BuildContext context) {
        final AppLocalizations t = AppLocalizations.of(context);
        return Theme(
          data: theme,
          child: Scaffold(
            appBar: AppBar(title: Text(t.parent_premium_title)),
            body: _buildBody(t, entitlement.isPremium),
            // C83 吸底（玄参反馈：真实视口下「立即解锁」需滚动 ≈480pt 才可见）：
            // 主按钮 + 恢复购买入口搬到 `bottomNavigationBar` 槽位常驻底部 ——
            // 这是**唯一**允许的吸底方式（不用 Stack/Positioned 盖 body，不用
            // persistentFooterButtons 造重复按钮）。
            // `_loading` 时给 null：底栏整体不渲染，避免先闪一下「暂不可购买」。
            bottomNavigationBar: _loading
                ? null
                : _buildStickyBottomBar(t, entitlement.isPremium, theme),
          ),
        );
      }),
    );
  }

  Widget _buildBody(AppLocalizations t, bool unlocked) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      // C83：主按钮 / 恢复按钮已移入吸底栏，页面底部不再需要为它们留白
      // （32 → 16，仅保留常规页边距）。
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: <Widget>[
        _buildHeroCard(t, unlocked),
        const SizedBox(height: 16),
        if (_storeUnavailable) ...<Widget>[
          _buildUnavailableCard(t),
          const SizedBox(height: 16),
        ],
        // 批次 2 Ⓑ（玄参 2026-10-23 拍板）：权益速览 3 场景卡**上移**到对比表之前
        // —— 「价值速览 → 明细对比 → 条款」的决策顺序。
        _buildPreviewBadges(t),
        const SizedBox(height: 16),
        // 阶段 5：主卡与主按钮之间插入「解锁前后对比表」。
        PremiumUnlockTable(isUnlocked: unlocked),
        const SizedBox(height: 16),
        // 批次 2 Ⓑ：「购买前请知悉」合规条款**沉底 + 视觉减淡**（原在对比表之前）。
        // C83：`_buildMainButton` / `_buildRestoreButton` 在吸底栏（不在此列表）。
        _buildNotesCard(t),
      ],
    );
  }

  /// 吸底操作区（C83）：主按钮 + 「恢复购买」入口常驻屏幕底部。
  ///
  /// 结构：`SafeArea(top: false)` → 顶部分隔线 + 向上轻阴影的容器 → 10pt 内边距
  /// → `Column(mainAxisSize: min)`（主按钮外壳 / 6pt / 恢复按钮）。
  ///
  /// 🔴 高度**必须由内容撑开**（`MainAxisSize.min` + 无任何写死 height）：
  /// 平板 textScaler 1.3× 时主按钮文案变高，写死高度必溢出。
  /// 🔴 槽内**不用** `Center` / `Align` 包裹（若日后要用，必须写 `heightFactor: 1`，
  /// 本仓曾因漏写导致 body 归零、全页空白）。
  ///
  /// [theme] 由 [build] 传入（本方法内的 `context` 还在 `Theme` 之上，取不到
  /// [parentThemeFor] 的结果），底色取 `colorScheme.surface`：浅色模式下是近白奶白，
  /// 深色模式下自动跟随，无需第二套写死色值。
  Widget _buildStickyBottomBar(
    AppLocalizations t,
    bool unlocked,
    ThemeData theme,
  ) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: const Border(
            top: BorderSide(color: Color(0x1F6B6252), width: 1),
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildMainButton(t, unlocked),
            // 「恢复购买」是 **Apple 对可恢复 IAP 的硬性要求**，iOS 必须常驻。
            // Android 官网直供版没有 Play Billing 交易可恢复（换了手机重输激活码即可，
            // 域层 activate 是幂等的），故 Android 上不渲染，避免家长点了必然失败。
            if (!_usesRedeemCode) ...<Widget>[
              const SizedBox(height: 6),
              _buildRestoreButton(t),
            ],
          ],
        ),
      ),
    );
  }

  /// 顶部主卡（阶段 5 视觉升级：极淡金渐变底 + 金描边 1.5 + 暖金柔光 + 👑 徽章 +
  /// 金胶囊 + 图标径向金光）。
  ///
  /// ⚠️ 图标仍为向日葵美术（玄参 2026-10-14 反馈），见 [_PremiumSunflowerIcon]；
  /// 🔴 主卡保留**精确**「已解锁 / 未解锁」胶囊文案（测试依赖 `find.text('已解锁')`）。
  Widget _buildHeroCard(AppLocalizations t, bool unlocked) {
    final ({Color bg, Color fg}) tone = macaronColorById('premium');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFFDF7), Color(0xFFFFF0C9)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8C56A), width: 1.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33E8A600),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 图标容器外包一层**径向金光**（不换素材、不改 [_PremiumSunflowerIcon]。
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[Color(0xFFFFE7B0), Color(0xFFFFF7E0)],
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: _PremiumSunflowerIcon(bg: tone.bg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.parent_premium_title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.parent_premium_hero_subtitle,
                      style: const TextStyle(fontSize: 13, color: _kInkSoft),
                    ),
                    const SizedBox(height: 10),
                    // C84（F121）：两枚胶囊由 `Row` 改 `Wrap` —— 320pt 窄屏 /
                    // 系统字号调大时并排会横向溢出 18px（Row 不换行），Wrap 放不下
                    // 就自动换行，宽屏视觉与此前一致（两枚仍在同一行）。
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        pillLabel(
                          text: unlocked
                              ? t.parent_premium_pill_unlocked
                              : t.parent_premium_pill_locked,
                          bg: unlocked
                              ? const Color(0xFFD9F2DD)
                              : const Color(0xFFEFEAE0),
                          fg: unlocked ? _kUnlocked : _kInkSoft,
                        ),
                        _GoldPill(text: t.parent_premium_gold_pill),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 右上角金徽章 👑（不参与布局，允许溢出到卡片内边距）。
          Positioned(
            top: -8,
            right: -8,
            child: Text('👑', style: TextStyle(fontSize: 20 * uiScaleOf(context))),
          ),
        ],
      ),
    );
  }

  /// 商店不可用（离线降级）：说明 + 重试，绝不崩。
  Widget _buildUnavailableCard(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: creamCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, color: Color(0xFFB98A2E)),
              const SizedBox(width: 8),
              // i18n B2：英文标题（`Store is unreachable`）比中文长 → 吃 `Expanded`
              // 换行，避免窄屏 / 大字号下 RenderFlex 溢出。
              Expanded(
                child: Text(
                  t.parent_premium_unavailable_title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.parent_premium_unavailable_body,
            style: const TextStyle(
                fontSize: 13, height: 1.45, color: _kInkSoft),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadProduct,
            icon: const Icon(Icons.refresh),
            label: Text(t.shared_retry),
          ),
        ],
      ),
    );
  }

  /// 主按钮：未解锁 → 「立即解锁 · <本地化价格>」；已解锁 → 不可点的「已解锁 · 感谢支持」。
  ///
  /// C83：本方法**整体原样搬运**到吸底栏（[_buildStickyBottomBar] 第一行），
  /// 返回树与 Key 归属一概未动 —— 只换了挂载位置。
  ///
  /// 🔴 按钮本体**必须**仍是 [ButtonStyleButton]（[FilledButton]）且 key 保持
  /// [kPremiumMainButtonKey] —— `premium_page_test` 对 `find.byKey(kPremiumMainButtonKey)`
  /// 做 `tester.widget<ButtonStyleButton>(...)` 强转。阶段 5 的金渐变只加在**外层
  /// 装饰**（[_goldButtonShell]）上，按钮本体透明。
  Widget _buildMainButton(AppLocalizations t, bool unlocked) {
    if (unlocked) {
      return _goldButtonShell(
        active: true,
        child: FilledButton.icon(
          key: kPremiumMainButtonKey,
          onPressed: null,
          style: _goldButtonStyle(),
          icon: const Icon(Icons.verified),
          label: Text(t.parent_premium_btn_unlocked_done),
        ),
      );
    }
    // Android 官网直供版：主按钮即「输入激活码」入口（不查商店、不吃商店价格）。
    if (_usesRedeemCode) {
      return _goldButtonShell(
        active: !_activating,
        child: FilledButton.icon(
          key: kPremiumMainButtonKey,
          onPressed: _activating ? null : _activateWithCode,
          style: _goldButtonStyle(),
          icon: const Icon(Icons.vpn_key_rounded),
          label: Text(
            _activating
                ? t.parent_premium_code_activating
                : t.parent_premium_code_btn_unlock,
          ),
        ),
      );
    }
    final String price = _product?.price ?? '';
    final bool enabled =
        !_storeUnavailable && !_buying && !_restoring && price.isNotEmpty;
    final String label = _buying
        ? t.parent_premium_btn_buying
        : _storeUnavailable || price.isEmpty
            ? t.parent_premium_btn_unavailable
            : t.parent_premium_btn_unlock_now(price);
    return _goldButtonShell(
      active: enabled,
      child: FilledButton(
        key: kPremiumMainButtonKey,
        onPressed: enabled ? _buy : null,
        style: _goldButtonStyle(),
        child: Text(label),
      ),
    );
  }

  /// 主按钮本体样式（透明底；金渐变由外层 [_goldButtonShell] 提供）。
  ButtonStyle _goldButtonStyle() => FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
      );

  /// 金渐变胶囊外壳（阶段 5）：圆角 999 + 暖金渐变 + 暖金阴影。
  ///
  /// [active] = false（商店不可用 / 加载中）时降为**灰金**，但按钮本体仍是可测的
  /// [ButtonStyleButton]（禁用态由 `onPressed == null` 表达，测试依赖）。
  Widget _goldButtonShell({required Widget child, required bool active}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? const <Color>[Color(0xFFFFCE5C), Color(0xFFE8A600)]
              : const <Color>[Color(0xFFE8DFC6), Color(0xFFD8CBA6)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33B8860B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// 权益速览 **3 场景卡**（批次 2 Ⓑ，玄参 2026-10-23 拍板）。
  ///
  /// 把 5 枚能力徽标归并为家长可感知的 3 个场景（消除与对比表的信息重复）：
  ///  🌻 花园更宽敞（花盆上限读矩阵买断档配额）；
  ///  📚 习惯随心配（成长项 / 奖励模板不限量，纯定性）；
  ///  👑 专属成长加成（称号属性条数 / 档案数均读常量）。
  ///
  /// 🔴 数字派生纪律（C108-4 同源）：`potMax` = [kPremiumGardenPotQuota]（矩阵
  /// 买断档别名）、`perkCount` = [kPremiumTitlePerkCount]（premium_gate 收口别名）、
  /// `profileMax` = [kPremiumChildProfileCount] —— **零字面权益数字**。
  /// 🔴 合规：只列真实生效项；「一键养护」真实存在（花园悬浮一键，会员档放开）。
  Widget _buildPreviewBadges(AppLocalizations t) {
    const int potMax = kPremiumGardenPotQuota;
    // 🔴 称号条数必须走 [kPremiumTitlePerkCount] 别名（premium_gate 收口）：
    // 守卫 ⑤ 禁家长端文件出现等级常量子串（含注释），不得直引 prd_params 等级表。
    final int perkCount = kPremiumTitlePerkCount;
    const int profileMax = kPremiumChildProfileCount;
    // 🔴 IntrinsicHeight 必须包：本 Row 在 ListView 里拿的是无界高度，
    // `CrossAxisAlignment.stretch` 直上会把三张卡撑到无穷高（a11y 窄屏用例实证）。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sceneCard(
            emoji: '🌻',
            title: t.parent_premium_scene_garden_title,
            detail: t.parent_premium_scene_garden_detail(potMax),
          ),
          const SizedBox(width: 8),
          _sceneCard(
            emoji: '📚',
            title: t.parent_premium_scene_routine_title,
            detail: t.parent_premium_scene_routine_detail,
          ),
          const SizedBox(width: 8),
          _sceneCard(
            emoji: '👑',
            title: t.parent_premium_scene_perk_title,
            detail: t.parent_premium_scene_perk_detail(perkCount, profileMax),
          ),
        ],
      ),
    );
  }

  /// 单张场景卡：暖金底圆角 + emoji + 标题 + 一行说明（窄屏自动折行，卡等高）。
  Widget _sceneCard({
    required String emoji,
    required String title,
    required String detail,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0E2BC)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF8D6E00),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: _kInkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「恢复购买」入口（Apple 对可恢复内购的硬性要求，**不得删除**）。
  ///
  /// C83：从列表末尾移到吸底栏主按钮下方，并收成**紧凑文字按钮** —— 底栏里再放一个
  /// 48pt 高的大描边按钮会把操作区顶到 ≈130pt，挤占内容。文案 `恢复中… / 恢复购买`
  /// 一字不改（Apple 审核认这几字，**不得删、不得换词**）。
  ///
  /// C84（2026-10-17 玄参拍板）：**可点范围撑到 44pt 高**（Apple HIG 最小点按尺寸），
  /// 横向 padding 放宽到 16pt —— 手指不易点偏；字仍是 13pt，视觉几乎无变化。
  /// ⚠️ `tapTargetSize: shrinkWrap` 必须保留：否则 Material 会再垫一层到 48pt，
  /// 底栏白多 4pt 且 [_expectContentDrivenBar] 的高度不变量失真。
  ///
  /// 字号只写 `fontSize: 13`（**不**再乘 [uiScaleOf]）：文字缩放统一由 `textScaler`
  /// 负责，两者相乘会在平板上放大两次。
  Widget _buildRestoreButton(AppLocalizations t) {
    return TextButton.icon(
      key: kPremiumRestoreButtonKey,
      onPressed: (_restoring || _buying) ? null : _restore,
      icon: const Icon(Icons.restore, size: 16),
      label: Text(
        _restoring
            ? t.parent_premium_restoring
            : t.parent_premium_restore,
        style: const TextStyle(fontSize: 13),
      ),
      style: TextButton.styleFrom(
        foregroundColor: _kInkSoft,
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  /// 诚实说明：一次性买断的真实边界（家长必读）。
  ///
  /// 批次 2 Ⓑ：合规条款**沉底 + 视觉减淡**——标题降为 `_kInkSoft` 小一号，
  /// 正文 13 → 12.5；信息一字不改（note_1–note_4 如实保留，Apple 合规红线）。
  Widget _buildNotesCard(AppLocalizations t) {
    // Android 官网直供版：note_2（Apple ID 恢复）/ note_4（Apple 收款）在安卓上不成立，
    // 换成一条「官网付款 → 收到激活码」的说明；note_1（一次买断）与 note_3（跨平台
    // 不可互认）仍然为真，保留原文。
    final List<String> notes = _usesRedeemCode
        ? <String>[
            t.parent_premium_note_1,
            t.parent_premium_note_android,
            t.parent_premium_note_3,
          ]
        : <String>[
            t.parent_premium_note_1,
            t.parent_premium_note_2,
            t.parent_premium_note_3,
            t.parent_premium_note_4,
          ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: creamCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.parent_premium_notes_title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _kInkSoft,
            ),
          ),
          const SizedBox(height: 10),
          for (final String n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('·  ', style: TextStyle(color: _kInkSoft)),
                  Expanded(
                    child: Text(
                      n,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: _kInkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 解锁状态文案（供**家长端设置页**入口卡副标题复用）。
///
/// 刻意收敛在此文件（权益命名空间白名单内），避免设置页散落权益判定 —— 设置页只
/// 需嵌入本组件即可随 [`entitlementProvider`] 自动刷新「未解锁 / 已解锁」。
class PremiumStatusText extends ConsumerWidget {
  const PremiumStatusText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Entitlement e = ref.watch(entitlementProvider);
    final bool unlocked = e.isPremium;
    final AppLocalizations t = l10nOf(context);
    return Text(
      unlocked
          ? t.parent_premium_pill_unlocked
          : t.parent_premium_pill_locked,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: unlocked ? _kUnlocked : _kInkSoft,
      ),
    );
  }
}

/// 主卡的**向日葵形象**图标（玄参 2026-10-14 截图反馈：换掉 emoji 🌻）。
///
/// 用仓库现有美术 `assets/plants/sunflower/species_sunflower_adult_bloomed.webp`
/// （向日葵盛开图，1200×2000 带盆竖版）。二轮反馈（同日下午）：44×44 +
/// `BoxFit.cover` 会把非方形竖图的**花盆整个裁掉** → 改 **52×52 +
/// `BoxFit.contain`** 完整展示整株（含盆）；52 而非 48：contain 后可见宽度只有
/// 块宽 × 0.6（1200/2000），52 → 花头 ≈31pt 比 48 的 ≈29pt 再大 8%，主卡是页
/// 面头牌、值得这 4pt；圆角仍 14，风格不跳。
///
/// ⚠️ `Image.asset` 必须**显式宽高**（项目硬规则：loose 约束下不给尺寸会按原图
/// 1200×2000 撑爆布局）；`errorBuilder` 回退 emoji 🌻 —— 素材缺失时不会开天窗。
class _PremiumSunflowerIcon extends StatelessWidget {
  const _PremiumSunflowerIcon({required this.bg});

  /// 马卡龙底色（与其余图标块同款，由 `macaronColorById('premium')` 给出）。
  final Color bg;

  /// 图标块边长（44 → **52**：补 `BoxFit.contain` 对竖版图的视觉损失，见类文档）。
  static const double _size = 52;

  /// 圆角（与其余图标块一致）。
  static const double _radius = 14;

  @override
  Widget build(BuildContext context) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Image.asset(
            'assets/plants/sunflower/species_sunflower_adult_bloomed.webp',
            width: _size,
            height: _size,
            // 玄参二轮反馈：cover 会裁掉花盆 → contain 完整展示整株（含盆）。
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('🌻', style: TextStyle(fontSize: 24)),
            ),
          ),
        ),
      );
}

/// 「输入激活码」对话框（Android 官网直供版）。
///
/// 为什么单独一个 [StatefulWidget] 而不是 `showDialog` 里塞 `StatefulBuilder`：
///  - 需要一个 `TextEditingController` 的**生命周期归属**（`dispose` 必调，
///    `StatefulBuilder` 没有 dispose 钩子 → 每次开框都会漏一个 controller）；
///  - 「从剪贴板粘贴」是异步的，需要 `setState` 刷新错误提示；
///  - 文案由外部 [AppLocalizations] 传入而**不在框内 `l10nOf(context)`**：对话框挂在
///    root overlay 上，可能不在页级 `L10nScope` 内，直接取会退化成默认语言
///    （这是本仓 i18n B2 的既有坑）。
///
/// 返回值：用户点「解锁」→ 清理后的码；点「取消」/ 返回 → null。
class _RedeemCodeDialog extends StatefulWidget {
  const _RedeemCodeDialog({required this.t});

  /// 页级取好的本地化表（在 scope 内取得，故一定是当前语言）。
  final AppLocalizations t;

  @override
  State<_RedeemCodeDialog> createState() => _RedeemCodeDialogState();
}

class _RedeemCodeDialogState extends State<_RedeemCodeDialog> {
  final TextEditingController _controller = TextEditingController();

  /// 输入框下方的错误提示（目前只有「剪贴板为空 / 空提交」两种，均非致命）。
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 从系统剪贴板取文本填进输入框（失败 / 为空 / 超时 → 就地给提示，绝不抛）。
  ///
  /// ⚠️ 不在这里做「清理空格 / 连字符」：那是域层 `normalizeRedeemCode` 的职责，
  /// 这里只 `trim()` 去掉首尾空白（中间的 `-` 是数据字符，绝不能删）。
  ///
  /// 🔴 必须 `.timeout`：`Clipboard.getData` 走平台通道，**通道不在（如测试宿主、
  /// 部分定制系统）时它既不返回也不抛** —— 不设超时的话按钮点了毫无反应，用户只会
  /// 以为 App 卡死（本仓实测：`flutter test` 里该 Future 永不完成）。
  Future<void> _pasteFromClipboard() async {
    String text = '';
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain)
          .timeout(kPremiumClipboardTimeout);
      text = data?.text ?? '';
    } catch (_) {
      // 无剪贴板权限 / 通道缺失 / 超时：一律降级为「空」，交给下面的提示。
      text = '';
    }
    if (!mounted) return;
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = widget.t.parent_premium_code_snack_paste_empty);
      return;
    }
    setState(() {
      _error = null;
      _controller.text = trimmed;
    });
  }

  /// 提交：空输入 → 就地提示「请完整复制」；否则把码交回调用方。
  void _submit() {
    final String code = _controller.text.trim();
    if (code.isEmpty) {
      setState(
          () => _error = widget.t.parent_premium_code_snack_malformed);
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.t.parent_premium_code_dialog_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.t.parent_premium_code_dialog_hint,
            style: const TextStyle(fontSize: 13, height: 1.45, color: _kInkSoft),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kPremiumRedeemCodeFieldKey,
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, letterSpacing: 0.4),
            decoration: InputDecoration(
              labelText: widget.t.parent_premium_code_dialog_field,
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 2,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: Text(widget.t.parent_premium_code_dialog_paste),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.t.parent_premium_code_dialog_cancel),
        ),
        FilledButton(
          key: kPremiumRedeemCodeConfirmKey,
          onPressed: _submit,
          child: Text(widget.t.parent_premium_code_dialog_confirm),
        ),
      ],
    );
  }
}

/// 顶部金胶囊（阶段 5）：金渐变底 + 白字，用于主卡「一次买断 · 永久」。
class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.text});

  /// 胶囊文案。
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFFFCE5C), Color(0xFFE8A600)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
}
