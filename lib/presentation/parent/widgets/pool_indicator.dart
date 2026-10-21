/// 周阳光池用量指示（§5 T-F；**C90-C 修订**）：展示当周阳光池消耗进度，
/// 与每周兑换额度的静态说明。
///
/// 合并卡 [WeeklyPoolCard]：原「每周阳光池预算」Card 与 `PoolIndicator` 两张卡合二为一，
/// 自上而下为：标题（含 weekKey）→ 预算大字 → 进度条 → 已用/池 → 静态说明。
///
/// 🔴 **C90-C（玄参 2026-10-18 拍板）**：
///  · 自动放行（C5 免确认）功能已删除 —— 原「当前档免确认上限」行与
///    `WeeklyPoolService.autoApproveCap` 引用一并移除；
///  · **高年级默认不限额**：`pool.budget <= kWeeklyPoolBudgetUnlimited`（0）时
///    显示「不限额」，兑换只受阳光余额约束。
///
/// 🔴 **C90-C 同日二次修订（玄参 2026-10-18）**：原卡内「本周预算调整」手动输入
/// 控件（50–500）**整块删除** —— 预算完全按年级默认值走，不再有编辑路径；
/// 原「家长手动设额入口保留」口径作废。原位改为静态说明文字：每周兑换额度默认值
/// —— 低年级 [kPoolBudgetDefaultLow] ☀ / 中年级 [kPoolBudgetDefaultMid] ☀ /
/// 高年级不限（按哨兵 [kWeeklyPoolBudgetUnlimited] 显示「不限」）。
/// `decide()/releaseQueue()/forceRelease()` 的
/// `budget > kWeeklyPoolBudgetUnlimited` 不限额守卫逻辑不变。
///
/// 数据来源：`WeeklyPoolService.pool(weekKey(DateTime.now()))` + 设置中的 ageTier。
///
/// 🔴 **C91 修订（玄参平板真机反馈）**：预算**即时派生** —— 服务层 `pool()` 已
/// 不再读池行 budget 列（年级默认值现算），本卡零改动即获得「存量 400 行立即纠正」；
/// 展示同步两处：
///  · 不限额（高年级）时「已用 x / 共 y」的 y 无意义 → **只显示已用**；
///  · 所属页下方「每周阳光池：免确认自动放行上限」小字已随本修订整行删除
///    （自动放行功能 C90-C 已废，见 `parent_reward_page.dart`）。
///
/// 🔴 **C91 二轮修订（玄参 iOS 模拟器反馈：不限额时进度横条一直闪烁）**：
/// 闪烁根因 = `LinearProgressIndicator(value: null)` 走**不确定态无限循环动画**
/// （AnimationController repeat，逐帧重绘永不收敛）→ 真机上表现为「进度条一直刷新」。
/// 修法：不限额（高年级）时进度条**整块不渲染**（口径：无分母则无进度可言），
/// 绝不做动画 / 循环刷新；限额时照常渲染确定性进度条（`value = used/budget`）。
/// 守卫 `test/c91/pool_card_unlimited_static_test.dart`：不限额下连续 pump 后
/// 不得再有未决帧（`hasScheduledFrame == false`）。
library pool_indicator;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 周阳光池合并卡：预算展示 + 进度（C90-C 同日二次修订：手动输入控件删除）。
///
/// 只读展示当周池预算与用量；说明行由 [kPoolBudgetDefaultLow] /
/// [kPoolBudgetDefaultMid] / [kWeeklyPoolBudgetUnlimited] 三个单点常量派生，
/// 页面不出现内联数字。
class WeeklyPoolCard extends ConsumerStatefulWidget {
  const WeeklyPoolCard({super.key});

  @override
  ConsumerState<WeeklyPoolCard> createState() => _WeeklyPoolCardState();
}

class _WeeklyPoolCardState extends ConsumerState<WeeklyPoolCard> {
  late Future<WeeklyPool> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WeeklyPool> _load() async {
    return ref
        .read(weeklyPoolServiceProvider)
        .pool(weekKey(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    // i18n B2：文案经 [l10nOf]（页级 scope 内取；裸宿主回退 zh）。
    final AppLocalizations t = l10nOf(context);
    return FutureBuilder<WeeklyPool>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<WeeklyPool> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.parent_reward_pool_load_failed('${snap.error}')),
            ),
          );
        }

        final WeeklyPool pool = snap.data!;
        final int usedTotal = pool.used + pool.autoReleased;
        // C90-C：budget <= kWeeklyPoolBudgetUnlimited（0）= 高年级默认不限额。
        final bool unlimited =
            pool.budget <= kWeeklyPoolBudgetUnlimited;
        final int budget = pool.budget;
        final double ratio = unlimited
            ? 0.0
            : budget > 0
                ? (usedTotal / budget).clamp(0.0, 1.0)
                : 0.0;

        // 高年级说明词：按哨兵常量派生（哨兵 <= 0 显示「不限」，否则显示其数值）。
        final String highTierLabel = kWeeklyPoolBudgetUnlimited <= 0
            ? t.shared_unlimited
            : '$kWeeklyPoolBudgetUnlimited☀';

        return Container(
          decoration: creamCardDecoration(),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                t.parent_reward_pool_title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              // 大号预算数字，一眼可见（家长最关心的「这周孩子能自己花多少」）。
              // i18n B2：英文「Unlimited」远宽于中文「不限」（大号 40pt 下尤甚）→
              // 整行用 [FittedBox] 兜底：放得下按原尺寸渲染，放不下才等比缩小，
              // 避免 320 窄屏 / 系统大字号下 RenderFlex 溢出。
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      unlimited ? t.shared_unlimited : '$budget',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8D6E00),
                      ),
                    ),
                    if (!unlimited) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(t.parent_reward_pool_unit,
                          style: const TextStyle(
                              fontSize: 18, color: Colors.brown)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 🔴 C91 二轮：不限额时进度条整块不渲染 —— 旧实现 value: null =
              // 不确定态无限循环动画（真机「进度横条一直闪烁」的根因）。
              if (!unlimited) ...<Widget>[
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 6),
              ],
              // C91：不限额时「共 y」无意义 → 只显示已用；限额时保留「已用 x / 共 y」。
              Text(
                unlimited
                    ? t.parent_reward_pool_unlimited_line(usedTotal)
                    : t.parent_reward_pool_used_line(usedTotal, budget),
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 14),
              // C90-C 同日二次修订：原「本周预算调整」输入控件（50–500）整块删除，
              // 原位改为静态说明（数字一律引用单点常量，禁内联字面量）。
              Text(
                t.parent_reward_pool_default_note(
                  kPoolBudgetDefaultLow,
                  kPoolBudgetDefaultMid,
                  highTierLabel,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.brown,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
