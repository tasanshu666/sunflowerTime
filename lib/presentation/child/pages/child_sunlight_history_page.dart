/// 孩子端「阳光来源记录」页（用户 2026-09-21 反馈 ③）。
///
/// 「我的」页阳光卡右上角标签点击进入。按时间倒序列出阳光账本每一笔：
/// 来源（refType → 中文文案）/ 增减（net 正负着色）/ 当时余额 / 时间。
/// 数据来自 [SunlightRepository.all]（append-only 账本，可追溯）。
library child_sunlight_history_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
// F130：平板 UI 倍率（文字之外的定尺寸元素一律乘 `uiScaleOf(context)`）。
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// refType → 来源文案（i18n B3 起为**函数**：文案走 ARB，英文环境同源）。
///
/// ## 纪律（既有铁律：字形由中文改为 ARB key，语义不变）
/// 新增 refType **必须同步本函数**，否则孩子端「阳光来源记录」一律显示「其他」，
/// 阳光来源对不上账（`test/m3/child_sunlight_history_ref_labels_test.dart` 钉死）。
///
/// ## B3 变更
/// 原 `const Map<String, String> _refLabels`（中文硬编码）→ 本函数（ARB key）。
/// refType **字符串值一律冻结**（append-only）：`'bloom_reward_24h'` 等历史值
/// 保留原样作为 case —— 换语言只换文案、绝不换值。
///
/// 注：`bloom_reward` / `bloom_reward_24h` 为成株后循环玩法 Batch 1 的开花奖励
/// refType（后者字符串值仍是历史遗留的 `'..._24h'`，见 `prd_params.dart` 中的冻结说明）。
String refLabelOf(String? refType, AppLocalizations t) {
  switch (refType ?? '') {
    // C48（玄参 2026-10-10）：专注入账的真实 refType 是 `focus_session` /
    // `focus_task_reward`（见 sunlight_service.dart），此前映射表只有 'focus'，
    // 专注记录全部落空显示「其他」—— 补齐（旧 'focus' 键保留作历史兼容）。
    case 'focus':
      return t.child_hist_ref_focus;
    case 'focus_session':
      return t.child_hist_ref_focus_session;
    case 'focus_task_reward':
      return t.child_hist_ref_focus_task_reward;
    case 'task_checkin':
      return t.child_hist_ref_task_checkin;
    case 'plant_plant':
      return t.child_hist_ref_plant_plant;
    case 'plant_water':
      return t.child_hist_ref_plant_water;
    case 'plant_fertilize':
      return t.child_hist_ref_plant_fertilize;
    case 'plant_revive':
      return t.child_hist_ref_plant_revive;
    case 'plant_expand':
      return t.child_hist_ref_plant_expand;
    // 花园干扰物（口径 C26）：漏配这两个 refType 时孩子端会一律显示「其他」，
    // 阳光来源对不上账 —— 新增 refType 必须同步本映射（既有铁律）。
    case 'plant_weed':
      return t.child_hist_ref_plant_weed;
    case 'plant_pest':
      return t.child_hist_ref_plant_pest;
    case 'plant_death_refund':
      return t.child_hist_ref_plant_death_refund;
    // C28 少儿护眼休息（玄参 2026-10-03 拍板）：完整完成一次 60 秒护眼 → +2 阳光，
    // `refType='eye_care_break'`（**字符串值一经写入即冻结**，改名会与历史行分裂）。
    // 漏配这条时孩子端会一律显示「其他」，阳光来源对不上账（新增 refType 必须同步本映射）。
    case 'eye_care_break':
      return t.child_hist_ref_eye_care_break;
    // C29 铲除返还（玄参 2026-10-05 拍板）：铲除植物按种下时定好的返还额入账
    // （普通 150 / 精英 250 / 免费首株与死亡株 0），refType 值冻结。
    case 'plant_shovel_refund':
      return t.child_hist_ref_plant_shovel_refund;
    case 'bloom_reward':
      return t.child_hist_ref_bloom_reward;
    case 'bloom_reward_24h':
      return t.child_hist_ref_bloom_reward_24h;
    // 兑换入账真实 refType（redemption_orchestration_service.dart 写 'redemption'），
    // 旧 'redeem' 键保留作历史兼容 —— 漏配时同样显示「其他」。
    case 'redeem':
      return t.child_hist_ref_redeem;
    case 'redemption':
      return t.child_hist_ref_redemption;
    case 'queueRelease':
      return t.child_hist_ref_queue_release;
    case 'parent_gift':
      return t.child_hist_ref_parent_gift;
    case 'debug_grant':
      return t.child_hist_ref_debug_grant;
    // C74 专注等级升级一次性阳光（玄参 2026-10-14 拍板；refType 值冻结）。
    // 🔴 C78（2026-10-15）：升级不再发阳光（零账本行）——本标签仅供**历史行**显示，
    //    账本 append-only 不清理，故映射必须保留。
    // 🔴 新增 refType 必须同步本映射，否则孩子端显示「其他」，阳光来源对不上账（既有铁律）。
    case kFocusLevelUpRefType:
      return t.child_hist_ref_focus_level_up;
    default:
      // 未知 refType 安全兜底（与原 `?? hist_other` 同语义）。
      return t.hist_other;
  }
}

/// 孩子端阳光来源记录页。
class ChildSunlightHistoryPage extends ConsumerStatefulWidget {
  const ChildSunlightHistoryPage({super.key});

  @override
  ConsumerState<ChildSunlightHistoryPage> createState() =>
      _ChildSunlightHistoryPageState();
}

class _ChildSunlightHistoryPageState
    extends ConsumerState<ChildSunlightHistoryPage> {
  List<SunlightEntry> _entries = <SunlightEntry>[];
  double _balance = 0;
  bool _loading = true;
  /// 当前页文案（build 期在 L10nScope 内赋值；异步回调经 [_t] 取，
  /// 尚未 build 过的极端早回调回退中文，与迁移前行为一致）。
  AppLocalizations? _l10n;

  /// 文案统一取用入口（i18n B1）。
  AppLocalizations get _t => _l10n ?? AppLocalizationsZh();


  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final List<SunlightEntry> entries =
          await ref.read(sunlightRepositoryProvider).all();
      final double balance =
          await ref.read(sunlightRepositoryProvider).balance();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    // 🔴 页级 L10nScope（i18n B1）：全页文案经 AppLocalizations 解析；
    // Builder 的 context 位于 scope 之下，并把实例存入 [_l10n] 供异步回调使用。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          _l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(_t.hist_title),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: _t.shared_refresh,
                onPressed: _loading ? null : _reload,
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(_t.hist_empty_hint,
                          style: const TextStyle(fontSize: 16)),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: <Widget>[
                        _BalanceBanner(balance: _balance),
                        const SizedBox(height: 12),
                        ..._entries.map(_EntryTile.new),
                      ],
                    ),
        );
        }, // builder 闭包
      ), // Builder
    ); // L10nScope
  }
}

/// 余额横幅（与「我的」页阳光卡一致）。
class _BalanceBanner extends StatelessWidget {
  final double balance;
  const _BalanceBanner({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6DC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            // 阳光美术图（2026-10-06 玄参交付；缺失/失败回退内置图标）。
            // F130（QA 二轮）：图标尺寸 **24 → 24×倍率** —— 同卡的文案已走
            // textScaler（1.6 倍下「当前拥有阳光」放大到 ≈22pt），图标却写死 24pt，
            // 就是「字大图标不动」的同款病。⚠️ 只改图标尺寸：卡片 padding / 圆角
            // 属另一类改动（无报障、无测试），本轮不动。
            Image.asset(
              'assets/rewards/sunlight.png',
              width: 24 * uiScaleOf(context),
              height: 24 * uiScaleOf(context),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  Icon(Icons.wb_sunny,
                      color: const Color(0xFFE8A600),
                      size: 24 * uiScaleOf(context)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10nOf(context).hist_balance_label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              // F105 口径：展示一律向下取整。
              '${sunlightDisplayInt(balance)} ☀',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD98F00)),
            ),
          ],
        ),
      );
}

/// 单条账本记录。
class _EntryTile extends StatelessWidget {
  final SunlightEntry entry;
  const _EntryTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final String label = refLabelOf(entry.refType, t);
    final bool earned = entry.net >= 0;
    final String amountText = '${entry.net > 0 ? '+' : ''}${entry.net.toInt()} ☀';
    final String time =
        DateFormat('MM-dd HH:mm').format(entry.ts);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: creamCardDecoration(),
      child: ListTile(
        leading: Icon(
          earned ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: earned ? Colors.green : Colors.red,
        ),
        title: Text(label),
        subtitle: Text(l10nOf(context)
            .hist_subtitle(time, entry.balanceAfter.toInt())),
        trailing: Text(
          amountText,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: earned ? Colors.green.shade700 : Colors.red.shade700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
