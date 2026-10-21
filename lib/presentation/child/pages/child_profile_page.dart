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
import 'package:sunflower_time/domain/services/account_service.dart'
    show AccountService;
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show levelOfMinutes, thresholdMinutesOfLevel;
import 'package:sunflower_time/presentation/child/widgets/child_avatar.dart';
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

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
  /// 当前页文案（build 期在 L10nScope 内赋值；异步回调经 [_t] 取，
  /// 尚未 build 过的极端早回调回退中文，与迁移前行为一致）。
  AppLocalizations? _l10n;

  /// 文案统一取用入口（i18n B1）。
  AppLocalizations get _t => _l10n ?? AppLocalizationsZh();


  /// 当前孩子展示名（C90 期 2 第二批：昵称跟档案走 —— 显示当前孩子档案
  /// `name`，随 [childProfileRevisionProvider] 刷新。旧 SP 键 `kPrefChildNickname`
  /// **停止读取**，孩子端改名入口已删（改名只在家长天地维护）。档案源不可用时
  /// 回落 [kDefaultChildNickname]，与旧展示兜底一致）。
  String _childName = kDefaultChildNickname;

  /// 当前孩子头像（**C90-C**：'sun' = 阳光；否则物种 id。跟档案走，
  /// 档案源不可用回落阳光默认）。
  String _childAvatar = kChildAvatarSun;

  /// 当前孩子**已种植过**的物种 id 集合（C90-C：头像候选判定依据；
  /// plants() 仓储层已按当前孩子过滤，此处只做 distinct）。
  Set<String> _plantedSpecies = const <String>{};

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
      // C91：只取 name + avatar（年龄段不再上屏——不是给孩子看的标签）。
      _childName = profile.name;
      _childAvatar = profile.avatar;
    } catch (_) {
      // 档案源不可用 → 保旧展示值。
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // C90-C · 头像（默认阳光；点头像弹选择面板，可选项 = 已种植物种）
  // ═════════════════════════════════════════════════════════════════════

  /// 打开头像选择卡片；选中可选项 → 落库（child_profiles.avatar）→ 刷新。
  ///
  /// 口径：卡片内未种植物种由 [showChildAvatarPickerDialog] 置灰加锁并提示，
  /// 不会 pop；故走到这里的 value 必为可选项（阳光或已种植物种）。
  /// C91：弹层从底部抽屉改为屏幕居中 Dialog 卡片（视觉美化，功能不变）。
  Future<void> _openAvatarPicker() async {
    final List<PlantSpecies> species =
        await ref.read(plantRepositoryProvider).species();
    if (!mounted) return;
    final String? picked = await showChildAvatarPickerDialog(
      context,
      currentAvatar: _childAvatar,
      plantedSpeciesIds: _plantedSpecies,
      species: species,
    );
    if (picked == null || !mounted) return; // 收起未选 / 点遮罩关闭
    if (picked == _childAvatar) return; // 重复选同一头像，无需落库
    await _saveAvatar(picked);
  }

  /// 落库头像：update（改名/调档不变，仅 avatar 变）→ switchTo 刷新 AccountService
  /// 活跃快照（仿家长天地编辑流程）→ 修订号自增 → 静默重拉。
  Future<void> _saveAvatar(String avatar) async {
    final AccountService account = ref.read(accountServiceProvider);
    final ChildProfile? profile =
        await account.currentProfile().timeout(kChildProfileReadTimeout);
    if (profile == null) return; // 桩模式（无档案源）：无可存目标，静默返回
    await ref.read(childProfileRepositoryProvider).update(
          profile.id,
          name: profile.name,
          ageTier: profile.ageTier,
          avatar: avatar,
        );
    // 刷新活跃快照（switchTo 重读仓储），使展示即时跟档（与家长编辑同套路）。
    await account.switchTo(profile.id);
    ref.read(childProfileRevisionProvider.notifier).state++;
    await _reload(silent: true);
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
      final List<PlantSpecies> species =
          await ref.read(plantRepositoryProvider).species();
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
        // C90-C：当前孩子已种植过的物种（distinct speciesId）。
        final Set<String> speciesIds =
            species.map((PlantSpecies s) => s.id).toSet();
        _plantedSpecies = plants
            .map((Plant p) => p.speciesId)
            .where(speciesIds.contains)
            .toSet();
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
    // 必须写在 build() 内：Riverpod 的 ref.listen 有 `debugDoingBuild` 断言；
    // 订阅随 element unmount 自动关闭（无泄漏），回调内判 mounted 防止 dispose 后 setState。
    // 且必须在 ConsumerWidget.build **顶层**调用 —— 断言不允许在嵌套 Builder
    // 闭包内调用，故注册在进入页级 L10nScope 之前。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });
    // 🔴 页级 L10nScope（i18n B1）：全页文案经 AppLocalizations 解析；
    // Builder 的 context 位于 scope 之下，并把实例存入 [_l10n] 供异步回调使用。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          _l10n = AppLocalizations.of(context);
        // 经济修订号监听已上移至 build() 顶层（Riverpod 断言要求，见上方 ref.listen）。

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
                        // C90-C：头像默认阳光；点按弹选择面板（阳光 + 已种植物种可选，
                        // 未种植置灰加锁可点提示）。稳定 Key 供测试定位。
                        GestureDetector(
                          key: const ValueKey<String>('child_avatar_tap'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _openAvatarPicker,
                          child: ChildAvatarView(avatar: _childAvatar),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // C91 修订（玄参）：只显示**昵称本身**，去掉
                              // 「· 低年级 / 8 岁及以下」档位后缀（年龄段不是给孩子
                              // 看的）。昵称跟档案走，改名只在家长天地。
                              Flexible(
                                child: Text(
                                  _childName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _t.profile_balance_line(sunlightDisplayInt(_balance)),
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
                          label: Text(_t.profile_source_label),
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
            _SectionTitle(_t.profile_achievements_title),
            _AchievementTile(
              icon: Icons.schedule,
              label: _t.profile_stat_focus_minutes,
              value: _t.profile_value_minutes(_totalFocusMinutes.round()),
              accent: const Color(0xFF4C8DF6),
            ),
            _AchievementTile(
              icon: Icons.timer,
              label: _t.profile_stat_sessions,
              value: _t.profile_value_times(_totalSessions),
              accent: const Color(0xFFF2994A),
            ),
            _AchievementTile(
              icon: Icons.event_available,
              label: _t.profile_stat_valid_days,
              value: _t.profile_value_days(_totalValidDays),
              accent: const Color(0xFF3BB273),
            ),
            _AchievementTile(
              icon: Icons.checklist,
              label: _t.profile_stat_checkins,
              value: _t.profile_value_times(_totalCheckIns),
              accent: const Color(0xFF8E7CF0),
            ),
            _AchievementTile(
              icon: Icons.local_florist,
              label: _t.profile_stat_bloomed,
              value: _t.profile_value_plants(_bloomedPlants),
              accent: const Color(0xFFE8628C),
            ),
            // 累计护眼（玄参 2026-10-09）：账本 refType='eye_care_break' 全量计数。
            _AchievementTile(
              icon: Icons.visibility,
              label: _t.profile_stat_eyecare,
              value: _t.profile_value_times(_totalEyeCares),
              accent: const Color(0xFF2FA8B8),
              isLast: true,
            ),
            // ── 调试区（玄参 2026-09-24 要求加回，供调试验收）────────────────────
            // ⚠️ 受 `kDebugMode` 约束：**release 构建自动不渲染** —— 既满足调试需要，
            // 又不必再担心「提审前忘了删」。测试用源码守卫锁住这条约束
            // （test/m4/child_shell_app_cap_test.dart 的「C 清理回归」）。
            // 🔴 2026-10-19（玄参）：截商店图时 debug 包的调试按钮会入镜 → 增加构建期
            // 开关 [kHideDebugUi]（`--dart-define=HIDE_DEBUG_UI=true`）显式关闭。
            // 两个条件并列：release 恒不渲染；debug 仅在截图构建时隐藏。
            if (shouldShowDebugUi(
              debugMode: kDebugMode,
              hideForScreenshots: kHideDebugUi,
            )) ...<Widget>[
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
        }, // builder 闭包
      ), // Builder
    ); // L10nScope
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
