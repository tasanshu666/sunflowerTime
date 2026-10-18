/// 孩子端「我的」tab（M3 导航重构 / §4.4 成就展示）。
///
/// 采用**累计制**成就（累计专注时长 / 次数 / 有效专注天数 / 任务打卡 / 开花植物 /
/// 阳光余额），刻意**不做「连续 N 天」这类断档清零指标**（§4.4：连续断了归零本身是
/// 挫败源）。
///
/// 底部有**调试区**（`DEBUG 加1000阳光`）—— 2026-09-24 按玄参要求**加回来**供调试用
/// （此前 P0 清理时被删，玄参反馈「调试时需要」）。
/// ⚠️ 该区受 `kDebugMode` 约束：**release 构建自动不渲染**，不必再担心「提审前忘了删」。
library child_profile_page;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/core/utils/sunlight_display.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show levelOfMinutes, thresholdMinutesOfLevel;
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';

/// 年龄段短文案（C90 期 2 第二批「我的」页展示用；完整档位文案见
/// `child_profile_bar.dart`）。
String _childTierLabel(AgeTier tier) {
  switch (tier) {
    case AgeTier.low:
      return '低年级';
    case AgeTier.mid:
      return '中年级';
    case AgeTier.high:
      return '高年级';
  }
}

/// 孩子端「我的」：累计成就。
class ChildProfilePage extends ConsumerStatefulWidget {
  const ChildProfilePage({super.key});

  @override
  ConsumerState<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends ConsumerState<ChildProfilePage>
    with ChildTabAutoRefresh<ChildProfilePage> {
  double _totalFocusMinutes = 0;
  int _totalSessions = 0;
  int _totalValidDays = 0;
  int _totalCheckIns = 0;
  int _bloomedPlants = 0;
  int _totalEyeCares = 0;
  double _balance = 0;
  bool _loading = true;

  /// 当前孩子展示名（C90 期 2 第二批：昵称跟档案走 —— 显示当前孩子档案
  /// `name`，随 [childProfileRevisionProvider] 刷新。旧 SP 键 `kPrefChildNickname`
  /// **停止读取**，孩子端改名入口已删（改名只在家长天地维护）。档案源不可用时
  /// 回落 [kDefaultChildNickname]，与旧展示兜底一致）。
  String _childName = kDefaultChildNickname;

  /// 当前孩子年龄段（跟档案走；档案源不可用回落 high，与 settings 空表默认一致）。
  AgeTier _childTier = AgeTier.high;

  @override
  void initState() {
    super.initState();
    _reload();
    // 注：经济修订号监听放在 [build] 里（见下方注释），Riverpod 的 ref.listen
    // 有 `debugDoingBuild` 断言，**只能在 build 中调用**，不能放 initState。
  }

  /// 调试入口：**加 1000 阳光**（玄参 2026-09-24 要求加回，用于调试验收）。
  ///
  /// 追加一条 +1000 的账本流水（`refType='debug_grant'`），随后自增经济修订号
  /// 让全端（花园胶囊 / 商店 / 本页）立即重算 —— 早期版本只调 `_reload()`，
  /// 其它页面仍显示旧值。
  ///
  /// ⚠️ 调用点受 `kDebugMode` 约束（见 [build]），release 构建不会出现此入口。
  Future<void> _grantDebugSunlight() async {
    final DateTime now = DateTime.now();
    final double balance =
        await ref.read(sunlightRepositoryProvider).balance();
    await ref.read(sunlightRepositoryProvider).append(SunlightEntry(
          id: const Uuid().v4(),
          ts: now,
          type: SunlightType.earn,
          gross: 1000,
          net: 1000,
          balanceAfter: balance + 1000,
          refType: 'debug_grant',
          refId: null,
          dayKey: dayKey(now),
        ));
    // 关键：自增修订号（而非只刷本页），否则花园胶囊 / 商店仍是旧值。
    ref.read(economyRevisionProvider.notifier).state++;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DEBUG：已加 1000 阳光'),
        duration: Duration(seconds: 2),
      ),
    );
    await _reload(silent: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // C90 期 2 第二批 · 当前孩子档案联动（昵称 / 年龄段跟档案走）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 读取当前孩子档案（玄参反馈：孩子端「我的」显示档案 name + 年龄段文案）。
  ///
  /// 读 [AccountService.currentProfile]（内存活跃档案快照）。🔴 不直读仓储 ——
  /// AccountService 桩模式（测试未注入依赖）下 `currentProfile()` 返回 null
  /// **零触库**；仓储真源读取会在未 override 平台通道的测试环境挂起（真实库
  /// Lazy open 依赖 path_provider）。缓存新鲜度：唯一改档入口（家长天地编辑）
  /// 成功后已 `switchTo` 重读，快照即时。
  Future<void> _loadCurrentChild() async {
    try {
      // 🔴 有界等待（Q-E 先例）：档案源不可用（测试环境真实库 Lazy open 挂起等）
      // → 超时回退 null，绝不挂住本页 _reload。
      final ChildProfile? profile = await ref
          .read(accountServiceProvider)
          .currentProfile()
          .timeout(kChildProfileReadTimeout);
      if (profile == null) return;
      _childName = profile.name;
      _childTier = profile.ageTier;
    } catch (_) {
      // 档案源不可用 → 保旧展示值。
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // T3 · 调试区：等级结算快捷入口（仅 kDebugMode）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 追加一条**真实的**专注会话（[minutes] 分钟）并走真实结算 + 演出。
  ///
  /// ⚠️ 「模拟」= 写一条真实会话记录（驱动量 `FocusStats.totalFocusMinutes` 本来就
  /// 由会话聚合而来），**不是**假造等级数字 —— 结算仍走**等级服务 `settle()`** 的
  /// 同一条代码路径（双锚点 / 幂等 / 写账本全都在），与今日页调用的是同一个方法。
  Future<void> _debugAddFocusMinutes(double minutes) async {
    final DateTime now = DateTime.now();
    await ref.read(focusRepositoryProvider).saveSession(
          FocusSession(
            id: const Uuid().v4(),
            start: now.subtract(Duration(minutes: minutes.round())),
            end: now,
            plannedMin: minutes.round(),
            actualFocusMin: minutes,
            status: FocusStatus.completed,
            sunlightEarned: 0,
            createdAt: now,
          ),
        );
    if (!mounted) return;
    await _reload(silent: true);
    if (!mounted) return;
    await _debugSettleAndShowFx();
  }

  /// 直接跳到**下一个称号节点**：补足到该节点门槛所需的分钟数。
  Future<void> _debugJumpToNextTitleNode() async {
    final double current =
        (await ref.read(focusRepositoryProvider).totalStats())
            .totalFocusMinutes;
    final int level = levelOfMinutes(current);
    final int? nextTitleNode = _nextTitleNodeAfter(level);
    if (nextTitleNode == null) {
      _snack('已经是最高称号节点（Lv.$level）');
      return;
    }
    final int target = thresholdMinutesOfLevel(nextTitleNode);
    final double add = (target - current).ceilToDouble();
    if (add <= 0) {
      _snack('已在 Lv.$nextTitleNode 之上，无需补');
      return;
    }
    await _debugAddFocusMinutes(add);
    _snack('已补 ${add.round()} 分钟 → 目标 Lv.$nextTitleNode');
  }

  /// 重置等级结算锚点（**只清 SP，不动账本**）。
  ///
  /// ⚠️ 账本 `sunlight_ledger` 是 append-only 事实源（C12）→ 清了 SP 之后，下次结算
  /// 会因**双锚点取大**被账本里已发过的节点顶回去，**已发过的阳光不会重发**
  /// （这是幂等红线 I1，不是 bug）。按钮文案已如实注明这一点。
  Future<void> _debugResetLevelAnchor() async {
    await ref.read(focusLevelStoreProvider).clear();
    if (!mounted) return;
    await _reload(silent: true);
    _snack('已清 SP 锚点（账本已发过的不会重发）');
  }

  /// 走**真实**结算 + 演出（与今日页 `_settleFocusLevel` 同一条 `settle()` 路径）。
  Future<void> _debugSettleAndShowFx() async {
    final double total =
        (await ref.read(focusRepositoryProvider).totalStats())
            .totalFocusMinutes;
    final FocusLevelSettleResult result =
        await ref.read(focusLevelServiceProvider).settle(total);
    if (!mounted) return;
    if (result.granted.isNotEmpty) {
      // 阳光已落袋 → 同步孩子端经济展示（与今日页同款）。
      ref.read(economyRevisionProvider.notifier).state++;
    }
    await showLevelUpFxAuto(context, result);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  /// 严格大于 [level] 的**最小**称号节点（没有则返回 null）。
  int? _nextTitleNodeAfter(int level) {
    for (final int n in kFocusLevelTitleLevels) {
      if (n > level) return n;
    }
    return null;
  }

  // ── C68：自动刷新接线（切回本 tab / 回前台 / 跨 08:00 或跨天）───────────────
  @override
  int? get refreshTabIndex => kChildTabIndexOfProfile;

  @override
  Future<void> onTabRefreshRequested() => _reload(silent: true);

  /// [silent] = true 时不整页转圈（经济修订号 / C68 自动刷新后台刷新），
  /// 避免每次消费后切回本 tab 都闪一次全屏 loading。
  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final FocusStats stats =
          await ref.read(focusRepositoryProvider).totalStats();
      final int checkIns =
          await ref.read(taskRepositoryProvider).totalCheckInCount();
      final List<Plant> plants =
          await ref.read(plantRepositoryProvider).plants();
      final double balance =
          await ref.read(sunlightRepositoryProvider).balance();
      // 累计护眼次数（玄参 2026-10-09）：以**阳光账本**为权威口径
      // （`refType='eye_care_break'`，含上线以来全部历史；跳过不发奖励、天然不计数）。
      final int eyeCares = await ref
          .read(sunlightRepositoryProvider)
          .countByRefType(kEyeCareRefType);
      // C90 期 2：当前孩子档案（name + 年龄段）随每次刷新重读 —— 家长改档 /
      // 切孩子后 childProfileRevisionProvider 自增 → ChildTabAutoRefresh 无条件
      // 触发本方法，展示即时跟随。
      await _loadCurrentChild();
      if (!mounted) return;
      setState(() {
        _totalFocusMinutes = stats.totalFocusMinutes.toDouble();
        _totalSessions = stats.totalSessions;
        _totalValidDays = stats.totalValidDays;
        _totalCheckIns = checkIns;
        _bloomedPlants =
            plants.where((Plant p) => p.status == PlantStatus.bloomed).length;
        _totalEyeCares = eyeCares;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 经济修订号变化（浇水 / 扩容 / 施肥 / 兑换 / 成长打卡）→ 静默重拉本页。
    // 「我的」是底部导航 IndexedStack **保活**页，切 tab 不会重建；不监听的话，
    // 花园扣费后切回本页仍显示扣费前的余额（真机实测：我的页 1000+、花园页 900+）。
    // 账本本身是准的，此处只是补上「重新读一次」。
    // 必须写在 build 内：Riverpod 的 ref.listen 有 `debugDoingBuild` 断言；
    // 订阅随 element unmount 自动关闭（无泄漏），回调内判 mounted 防止 dispose 后 setState。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
          decoration: creamCardDecoration(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 36,
                      child: Icon(Icons.person, size: 40),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // C90 期 2：只读展示「名字 · 年龄段」（昵称跟档案走，
                          // 改名只在家长天地；本页不再有改名入口）。
                          Flexible(
                            child: Text(
                              '$_childName · ${_childTierLabel(_childTier)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '我的阳光：${sunlightDisplayInt(_balance)} ☀',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    // 右上角标签：点击进入阳光来源记录（用户 2026-09-21 反馈 ③）。
                    TextButton.icon(
                      onPressed: () =>
                          context.push('/child/sunlight-history'),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('来源'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD98F00),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('累计成就'),
        _AchievementTile(
          icon: Icons.schedule,
          label: '累计专注时长',
          value: '${_totalFocusMinutes.round()} 分钟',
          accent: const Color(0xFF4C8DF6),
        ),
        _AchievementTile(
          icon: Icons.timer,
          label: '累计专注次数',
          value: '$_totalSessions 次',
          accent: const Color(0xFFF2994A),
        ),
        _AchievementTile(
          icon: Icons.event_available,
          label: '累计有效专注天数',
          value: '$_totalValidDays 天',
          accent: const Color(0xFF3BB273),
        ),
        _AchievementTile(
          icon: Icons.checklist,
          label: '累计成长打卡',
          value: '$_totalCheckIns 次',
          accent: const Color(0xFF8E7CF0),
        ),
        _AchievementTile(
          icon: Icons.local_florist,
          label: '累计开花植物',
          value: '$_bloomedPlants 株',
          accent: const Color(0xFFE8628C),
        ),
        // 累计护眼（玄参 2026-10-09）：账本 refType='eye_care_break' 全量计数。
        _AchievementTile(
          icon: Icons.visibility,
          label: '累计护眼',
          value: '$_totalEyeCares 次',
          accent: const Color(0xFF2FA8B8),
          isLast: true,
        ),
        // ── 调试区（玄参 2026-09-24 要求加回，供调试验收）────────────────────
        // ⚠️ 受 kDebugMode 约束：**release 构建自动不渲染** —— 既满足调试需要，
        // 又不必再担心「提审前忘了删」。测试用源码守卫锁住这条约束
        // （test/m4/child_shell_app_cap_test.dart 的「C 清理回归」）。
        if (kDebugMode) ...<Widget>[
          const SizedBox(height: 24),
          const _SectionTitle('调试区'),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: _grantDebugSunlight,
            child: const Text('DEBUG 加1000阳光'),
          ),
          // ── T3 · 等级演出调试入口（玄参 2026-10-14 要，用于测演出）────────
          // ⚠️ 三个按钮都走**真实**的 `FocusLevelService.settle()`（写真实会话、
          // 真实写账本、真实播演出），没有另写假结算。
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
            onPressed: () => _debugAddFocusMinutes(30),
            child: const Text('DEBUG 累计专注 +30 分钟（模拟）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
            onPressed: _debugJumpToNextTitleNode,
            child: const Text('DEBUG 直接跳到下一个称号节点'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey),
            onPressed: _debugResetLevelAnchor,
            // ⚠️ 文案如实注明：账本是 append-only 事实源，清 SP 后双锚点取大会
            // 被已发节点顶回去 —— **已发过的阳光不会重发**（幂等红线 I1）。
            child: const Text('DEBUG 重置等级结算锚点（账本已发过的不会重发）'),
          ),
        ],
      ],
    );
  }
}

/// 分组标题。
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      );
}

/// 单条成就行。
///
/// [accent] 为该卡的专属强调色：用于左侧圆角图标块底色，并派生出卡片本身的
/// **极浅色调**底色（兼容深色主题，不写死白底）。每张卡传入不同暖色以区分内容。
class _AchievementTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  /// 是否为列表中的**最后一张**卡：最后一张不再留底部间距。
  /// 这样既保证「卡与卡之间有间距」，又避免在末尾多出一段空白把页面撑高
  /// （页面总高度需落在测试视口 800×600 内，否则底部调试按钮会被顶出可点区域）。
  final bool isLast;

  const _AchievementTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    // 卡片底色 = accent 的极浅色调（10% 透明度）叠加到当前主题 surface 之上，
    // 既与 creamCardDecoration 的「浅底大圆角 + 柔阴影」观感一致，又能随深色主题自适应。
    final Color tintedSurface = Color.alphaBlend(
      accent.withValues(alpha: 0.10),
      Theme.of(context).colorScheme.surface,
    );
    return Container(
      // 非末卡留 12 的纵向间距，使相邻成就卡清晰分开（末卡不留，避免多余空白）。
      margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tintedSurface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
