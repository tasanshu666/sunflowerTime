/// 家长端·会员与购买页（付费墙 · 阶段 3 第二批）。
///
/// 职责：把「一次性永久买断」的完整购买体验收在一处 ——
///  · 展示**商店返回的本地化价格**（`IapProduct.price`，绝不硬编码金额 / `$`）；
///  · 发起购买、提供 **Apple 硬性要求的「恢复购买」** 入口；
///  · 把一次性买断的**真实边界**如实写给家长（非订阅 / 换机可恢复 / 跨平台不可
///    恢复 / 支付由 Apple 完成、开发者不接触支付信息）。
///
/// 状态机（全部覆盖）：`加载中` / `加载失败·商店不可用`（降级文案 + 主按钮禁用，
/// 绝不崩）/ `未解锁` / `已解锁` / `购买中`。
///
/// 设计纪律（对齐架构 §「门控单点收口」+ 依赖倒置）：
///  · 平台细节全部走**纯 Dart 契约** [`IapClient`]（本页**不** import
///    `in_app_purchase`），故可脱离真实插件单测；
///  · 购买 / 恢复走**域层** [`EntitlementService`]（落库票据 + 更新内存态），成功后
///    刷新 [`entitlementProvider`]，使家长端设置页副标题与本页状态同步；
///  · 商店不可用 / 取消 / 失败一律安全降级（域服务已保证不裸抛），本页再兜一层 try/catch。
library parent_premium_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/services/iap_contract.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/shared/theme.dart';

/// 页内统一色（暖色儿童风：深字 + 柔灰字，白底卡由 [creamCardDecoration] 提供）。
const Color _kInk = Color(0xFF6B6252);
const Color _kInkSoft = Color(0xFF9C917E);
const Color _kUnlocked = Color(0xFF2E7D32);

/// 主购买按钮 Key（供测试稳定定位；文案随状态变化）。
const Key kPremiumMainButtonKey = Key('premiumMainButton');

/// 「恢复购买」按钮 Key。
const Key kPremiumRestoreButtonKey = Key('premiumRestoreButton');

/// 家长端·会员与购买页。
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

  /// 商店返回的买断商品（`price` 为商店本地化价格串）。
  IapProduct? _product;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  /// 拉取商品详情（本地化价格）。失败 / 商店不可用 → 置降级态，绝不抛。
  Future<void> _loadProduct() async {
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
    setState(() => _buying = true);
    try {
      await ref.read(entitlementServiceProvider).purchaseLifetime();
      final Entitlement e = await ref.read(entitlementServiceProvider).load();
      ref.read(entitlementProvider.notifier).state = e;
      _snack(e.isPremium ? '已解锁，感谢支持 🌻' : '购买未完成，可稍后再试');
    } catch (_) {
      _snack('购买失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  /// 恢复购买：三态各有明确反馈（**Apple 硬性要求入口**）。
  Future<void> _restore() async {
    if (_restoring || _buying) return;
    setState(() => _restoring = true);
    try {
      final RestoreResult r =
          await ref.read(entitlementServiceProvider).restore();
      final Entitlement e = await ref.read(entitlementServiceProvider).load();
      ref.read(entitlementProvider.notifier).state = e;
      switch (r) {
        case RestoreResult.restored:
          _snack('已恢复购买，欢迎回来 🌻');
        case RestoreResult.nothingToRestore:
          _snack('没有找到可恢复的购买记录');
        case RestoreResult.failed:
          _snack('恢复失败，请检查网络后重试');
      }
    } catch (_) {
      _snack('恢复失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final Entitlement entitlement = ref.watch(entitlementProvider);
    return Theme(
      data: parentThemeFor(Theme.of(context).brightness),
      child: Scaffold(
        appBar: AppBar(title: const Text('会员与购买')),
        body: _buildBody(entitlement.isPremium),
      ),
    );
  }

  Widget _buildBody(bool unlocked) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _buildHeroCard(unlocked),
        const SizedBox(height: 16),
        if (_storeUnavailable) ...<Widget>[
          _buildUnavailableCard(),
          const SizedBox(height: 16),
        ],
        _buildMainButton(unlocked),
        const SizedBox(height: 10),
        _buildRestoreButton(),
        const SizedBox(height: 22),
        _buildNotesCard(),
      ],
    );
  }

  /// 顶部主卡（奶油风白底大圆角）：功能说明 + 当前状态胶囊。
  ///
  /// ⚠️ 图标已改为向日葵美术（玄参 2026-10-14 反馈），见 [_PremiumSunflowerIcon]。
  Widget _buildHeroCard(bool unlocked) {
    final ({Color bg, Color fg}) tone = macaronColorById('premium');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: creamCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 2026-10-14 玄参截图反馈：主卡图标 emoji 🌻 → **仓库现有向日葵美术**
          // （`species_sunflower_adult_bloomed.png`，1200×2000 带盆盛开图）。
          // 马卡龙圆角容器同款风格；下午二轮反馈「cover 把花盆整个切掉」→
          // 改 **BoxFit.contain** 完整展示整株（含盆），容器放大到 52×52 补
          // contain 的视觉损失（圆角仍 14 与其余图标块一致）。
          _PremiumSunflowerIcon(bg: tone.bg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '升级解锁全部功能',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '一次买断 · 永久解锁，陪孩子一起专注成长',
                  style: TextStyle(fontSize: 13, color: _kInkSoft),
                ),
                const SizedBox(height: 10),
                pillLabel(
                  text: unlocked ? '已解锁' : '未解锁',
                  bg: unlocked ? const Color(0xFFD9F2DD) : const Color(0xFFEFEAE0),
                  fg: unlocked ? _kUnlocked : _kInkSoft,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 商店不可用（离线降级）：说明 + 重试，绝不崩。
  Widget _buildUnavailableCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: creamCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, color: Color(0xFFB98A2E)),
              SizedBox(width: 8),
              Text(
                '暂时连不上商店',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '现在无法获取商品信息，不影响你继续使用 App 的其他功能。'
            '请检查网络后再试。',
            style: TextStyle(fontSize: 13, height: 1.45, color: _kInkSoft),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadProduct,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 主按钮：未解锁 → 「一次买断 · <本地化价格>」；已解锁 → 不可点的「已解锁」。
  Widget _buildMainButton(bool unlocked) {
    if (unlocked) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: kPremiumMainButtonKey,
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('已解锁'),
        ),
      );
    }
    final String price = _product?.price ?? '';
    final bool enabled =
        !_storeUnavailable && !_buying && !_restoring && price.isNotEmpty;
    final String label = _buying
        ? '购买中…'
        : _storeUnavailable || price.isEmpty
            ? '暂不可购买'
            : '一次买断 · $price';
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: kPremiumMainButtonKey,
        onPressed: enabled ? _buy : null,
        child: Text(label),
      ),
    );
  }

  /// 「恢复购买」入口（Apple 对可恢复内购的硬性要求，**不得删除**）。
  Widget _buildRestoreButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: kPremiumRestoreButtonKey,
        onPressed: (_restoring || _buying) ? null : _restore,
        icon: const Icon(Icons.restore),
        label: Text(_restoring ? '恢复中…' : '恢复购买'),
      ),
    );
  }

  /// 诚实说明：一次性买断的真实边界（家长必读）。
  Widget _buildNotesCard() {
    const List<String> notes = <String>[
      '一次买断、永久解锁 —— 不是订阅，不会自动续费。',
      '同一 Apple ID 换手机 / 卸载重装后，点「恢复购买」即可找回。',
      '⚠️ 在 iOS 上购买的内容，无法在 Android 设备上「恢复购买」（反之亦然）。',
      '支付通过 Apple App Store 完成，开发者不会接触到你的任何支付信息。',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: creamCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '购买前请知悉',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _kInk,
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
                        fontSize: 13,
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

/// 会员状态文案（供**家长端设置页**入口卡副标题复用）。
///
/// 刻意收敛在此文件（权益命名空间白名单内），避免设置页散落权益判定 —— 设置页只
/// 需嵌入本组件即可随 [`entitlementProvider`] 自动刷新「未解锁 / 已解锁」。
class PremiumStatusText extends ConsumerWidget {
  const PremiumStatusText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Entitlement e = ref.watch(entitlementProvider);
    final bool unlocked = e.isPremium;
    return Text(
      unlocked ? '已解锁' : '未解锁',
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
/// 用仓库现有美术 `assets/plants/sunflower/species_sunflower_adult_bloomed.png`
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
            'assets/plants/sunflower/species_sunflower_adult_bloomed.png',
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
