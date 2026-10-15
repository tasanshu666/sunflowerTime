/// C74 · 专注等级：阶梯**纯函数** + 结算编排（**纯 Dart**，零 flutter / 零插件）。
///
/// ## 文件内两段
///  · **纯函数**（[levelOfMinutes] / [titleOfLevel] / …）：零 I/O、零注入，直接单测；
///  · [FocusLevelService]：把「读 SP → 读账本 → 写账本 → 推进 SP」编排起来，**可注入
///    clock / idFactory**，故 `package:test` 下可确定性验证。
///
/// ## 等级 40 级 vs 称号 9 个（C74 §2/§3/§4，🔑 全案核心）
///  · 等级门槛 `kFocusLevelThresholdMinutes`（Lv.1 = **60 分钟**，故不足 1 小时 ⇒ lv 0）；
///  · 称号只在 `kFocusLevelTitleLevels` 解锁，**当前称号 = 已解锁的最高称号节点**；
///  · 阳光**只在称号节点发**（其余 31 次普通升级：不发阳光、不播演出，只更新进度）。
///
/// ## 幂等锚点（设计 §5.24.3，🔴 核心算法）
/// `settledLevel = max(SP 值, 账本中已存在的最大称号节点 K)`
/// —— 双锚点**取大**：账本保证「同一称号节点绝不重复发」（C12 事实源），SP 补上
/// 「老用户首用不补发」这一条。只用一个锚点必在某场景出错（丢 SP 会补发 / 老用户会补发）。
///
/// ## 四条不变式
///  I1 同一称号节点**绝不重复发**（双锚点 + 每节点写前 `countByRefTypeAndRefId == 0`）；
///  I2 **不补发历史称号阳光**（首用分支只写 SP，不写任何账本行）；
///  I3 中间一条写失败**不等于永久跳过**（停在失败前一级，下轮重试）；
///  I4 崩溃不丢阳光（**先写账本、后播演出**；演出由调用方在本方法返回后再播）。
library focus_level_service;

import 'dart:math' as math;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 一、纯函数（零 I/O，直接单测）
// ═══════════════════════════════════════════════════════════════════════════

/// 最高等级（= [kFocusLevelMaxLevel] = 40）。
int get kFocusLevelMax => kFocusLevelMaxLevel;

/// 「尚未解锁」的等级值（累计专注不足 Lv.1 门槛时）。
const int kFocusLevelLocked = 0;

/// 累计专注分钟 → 等级：取满足 `minutes >= 门槛` 的**最大**等级（0..[kFocusLevelMax]）。
///
/// 🔴 **结构性差异**：这里会返回 **0**（累计不足 60 分钟）—— 不是 1。
/// 边界：`0 → 0`、`59.9 → 0`、`60 → 1`、`119.9 → 1`、`120 → 2`、…、
/// `满级门槛 → 40`（门槛值一律取自 [kFocusLevelThresholdMinutes]，此处不写字面量）。
/// 负数 / NaN 安全：一路走不到任何门槛 ⇒ 0。
int levelOfMinutes(double minutes) {
  int level = kFocusLevelLocked;
  for (int i = 0; i < kFocusLevelThresholdMinutes.length; i++) {
    if (minutes >= kFocusLevelThresholdMinutes[i]) {
      level = i + 1;
    } else {
      break; // 门槛表升序，首个不满足之后的不可能满足
    }
  }
  return level;
}

/// 等级 → 称号：**当前称号 = 已解锁的最高称号节点**（40 级里只有 9 个节点）。
///
/// 🔑 正是这条让「Lv.7 的称号仍是**Lv.5 节点**的称号」成立（称号文案一律取自
/// [kFocusLevelTitles]，本文件不写文案字面量）。
/// 未解锁（`level < 1`）返回**空串**（UI 走未解锁态）；越界上钳到最高称号。
String titleOfLevel(int level) {
  if (level < 1) return '';
  String title = '';
  for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
    if (level >= kFocusLevelTitleLevels[i]) {
      title = kFocusLevelTitles[i];
    }
  }
  return title;
}

/// 等级 → **已解锁的最高称号节点等级**（0 = 尚未解锁任何称号）。
int latestTitleNodeOfLevel(int level) {
  int node = kFocusLevelLocked;
  for (final int n in kFocusLevelTitleLevels) {
    if (level >= n) node = n;
  }
  return node;
}

/// 该等级是否**称号节点**（决定「发不发阳光 / 播不播演出」，C74 §4）。
bool isTitleLevelOf(int level) => kFocusLevelTitleLevels.contains(level);

/// 等级 → 门槛分钟（`C74` 阶梯表唯一读法；页面不得另写「1 小时」等第二份写法）。
///
/// 越界：`<= 0` → Lv.1 门槛；`> 40` → 满级门槛。
int thresholdMinutesOfLevel(int level) {
  final int idx = level.clamp(1, kFocusLevelMaxLevel) - 1;
  return kFocusLevelThresholdMinutes[idx];
}

/// 等级 → 该称号节点的阳光（**非称号等级 = 0**；`level < 1` = 0）。
int sunlightOfLevel(int level) => kFocusLevelUpSunlight[level] ?? 0;

/// 等级 → 账本 refId（`'lv{n}'`）—— 🔴 **唯一生成入口**，页面禁止拼字符串。
String levelRefIdOf(int level) => '$kFocusLevelRefIdPrefix$level';

/// `settledLevel + 1 .. currentLevel` 的**升序**等级列表（含非称号等级）；
/// 无待推进返回空列表。
List<int> pendingLevelsOf({
  required int currentLevel,
  required int settledLevel,
}) {
  if (currentLevel <= settledLevel) return const <int>[];
  return <int>[
    for (int lv = settledLevel + 1; lv <= currentLevel; lv++) lv,
  ];
}

/// 从一串待推进等级里挑出**需要发阳光的称号节点**（保持升序）。
List<int> titleLevelsOf(List<int> levels) => <int>[
      for (final int lv in levels)
        if (isTitleLevelOf(lv)) lv,
    ];

/// 一批称号节点的阳光合计（跨多级「连升 N 个称号 +N☀」用）。
int sunlightTotalOf(List<int> levels) => levels.fold(
      0,
      (int sum, int lv) => sum + sunlightOfLevel(lv),
    );

/// 累计分钟 → 徽章展示模型（纯派生，零 I/O）。
///
/// [progress] / [minutesToNext] / [nextLevel] 一律**指向下一级**（不是下一个称号）：
///  · 未解锁（`level == 0`）：下一级 = Lv.1，进度 = `minutes / 60`；
///  · 满级：进度 1.0、[minutesToNext] 0、[nextLevel] null。
FocusLevelProgress progressOf(double totalMinutes) {
  final int level = levelOfMinutes(totalMinutes);
  final String title = titleOfLevel(level);
  if (level >= kFocusLevelMaxLevel) {
    return FocusLevelProgress(
      level: level,
      title: title,
      isLocked: false,
      isMax: true,
      progress: 1.0,
      minutesToNext: 0,
      nextLevel: null,
    );
  }
  final int nextLevel = level + 1;
  final int nextThreshold = thresholdMinutesOfLevel(nextLevel);
  final int base =
      level == kFocusLevelLocked ? 0 : thresholdMinutesOfLevel(level);
  final double span = (nextThreshold - base).toDouble();
  final double done = (totalMinutes - base).clamp(0.0, span);
  final double progress = span <= 0 ? 1.0 : (done / span).clamp(0.0, 1.0);
  final int minutesToNext =
      (nextThreshold - totalMinutes).ceil().clamp(0, nextThreshold);
  return FocusLevelProgress(
    level: level,
    title: title,
    isLocked: level == kFocusLevelLocked,
    isMax: false,
    progress: progress,
    minutesToNext: minutesToNext,
    nextLevel: nextLevel,
  );
}

/// 等级 → **9 个称号节点全列表**（详情卡「9 个称号紧凑列表」用；纯派生）。
///
/// 9 个节点**全部列出**（已拍板），每行带 `unlocked` 与 `isCurrent`：
///  · `unlocked` = `level >= 节点`；
///  · `isCurrent` = 本节点 == [latestTitleNodeOfLevel]（当前称号 = 已解锁的**最高**
///    称号节点，C74 §3 —— Lv.7 时高亮的是 Lv.5 那一行）。
///
/// 🔴 节点与文案一律取自 `kFocusLevelTitleLevels` / `kFocusLevelTitles`，本文件
/// 不写字面量；列表长度恒 = 9（`kFocusLevelTitleLevels.length`）。
List<FocusLevelTitleRow> titleRowsOfLevel(int level) {
  final int currentNode = latestTitleNodeOfLevel(level);
  return List<FocusLevelTitleRow>.unmodifiable(<FocusLevelTitleRow>[
    for (int i = 0; i < kFocusLevelTitleLevels.length; i++)
      FocusLevelTitleRow(
        level: kFocusLevelTitleLevels[i],
        title: kFocusLevelTitles[i],
        unlocked: level >= kFocusLevelTitleLevels[i],
        isCurrent: kFocusLevelTitleLevels[i] == currentNode,
      ),
  ]);
}

/// 详情卡副标题文案：**非满级 → 「距 Lv.{n} 还差 {r}」；满级 → 满级文案**。
///
/// 🔑 数据**全部复用** [FocusLevelProgress] 已有字段（`nextLevel` /
/// `minutesToNext` = 「下一级门槛分钟 − 累计有效分钟」，由 [progressOf] 纯派生），
/// 本函数只做**文案装配** —— UI 层禁止再重写一遍 duration 算式（S14）。
String nextLevelGapTextOf(FocusLevelProgress progress) {
  if (progress.isMax) {
    return kLevelMaxTextTemplate.replaceAll('{t}', progress.title);
  }
  final int next = progress.nextLevel ?? progress.level + 1;
  return kLevelDetailNextTextTemplate
      .replaceAll('{n}', '$next')
      .replaceAll('{r}', formatDurationMinutes(progress.minutesToNext));
}

/// 时长展示格式化（≥ 60 分钟 → 「X 小时 Y 分钟」，否则「Y 分钟」）。
///
/// 儿童向：避免把「满级门槛那么大的分钟数」直接给孩子看（C74 §2）。
/// 分钟取余为 0 时只出小时。
String formatDurationMinutes(int minutes) {
  final int safe = minutes < 0 ? 0 : minutes;
  final int h = safe ~/ 60;
  final int m = safe % 60;
  if (h <= 0) return '$m 分钟';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分钟';
}

/// 幂等关键：从 `settledLevel + 1` 起向上走，返回「**连续**已结算的最后一个等级」。
///
/// 非称号等级自动通过（[isGranted] 只需回答「称号节点是否已入账」）；某条称号节点
/// 写失败时会停在失败前一级（I3）→ 下次进页**重试那一条**（既不是永久跳过，也不会
/// 重复发已发过的节点）。
int nextSettledLevelOf({
  required int settledLevel,
  required int currentLevel,
  required bool Function(int level) isGranted,
}) {
  int next = settledLevel;
  for (int lv = settledLevel + 1; lv <= currentLevel; lv++) {
    if (isTitleLevelOf(lv) && !isGranted(lv)) break;
    next = lv;
  }
  return next;
}

// ═══════════════════════════════════════════════════════════════════════════
// 二、结算服务（纯 Dart，串行编排；依赖全部可注入）
// ═══════════════════════════════════════════════════════════════════════════

/// C74 专注等级结算服务。
///
/// 三条分支（设计 §5.24.3 + C74 §9）：
///  ① **快路径**（占绝大多数进页）：SP 有值 且 `current <= SP` ⇒ **零账本查询**；
///  ② **首用分支**：SP 未写过 且 账本无 `focus_level_up` 行 ⇒ 只写 SP（= current），
///     返回 `firstUseSilent = true`（🔴 不补发历史称号阳光、不播演出）；
///  ③ **结算分支**：`settled = max(SP ?? 0, K)` → 逐节点发阳光（先写账本）→ 推进 SP。
///     只有**称号节点**会写账本；普通升级只把 SP 推进到当前等级（零阳光、零演出）。
class FocusLevelService {
  FocusLevelService({
    required SunlightRepository ledger,
    required FocusLevelSettledStore store,
    required String Function() idFactory,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _store = store,
        _idFactory = idFactory,
        _clock = clock ?? DateTime.now;

  final SunlightRepository _ledger;
  final FocusLevelSettledStore _store;
  final String Function() _idFactory;

  /// 可注入时钟（🟢 夹具时间戳一律相对 `DateTime.now()`，测试不写死绝对时间）。
  final DateTime Function() _clock;

  /// 本轮结算。**先写账本**（崩溃不丢阳光，I4），演出由**调用方**在本方法返回后播。
  ///
  /// 🔑 返回值里 `granted` **只含称号节点** —— 调用方据此判断「是否播演出」
  /// （空 ⇒ 普通升级或首用，一律不播）。
  Future<FocusLevelSettleResult> settle(double totalFocusMinutes) async {
    final int current = levelOfMinutes(totalFocusMinutes);
    final int? sp = await _store.read();

    // ① 快路径：已结算到的等级 >= 当前等级 ⇒ 无需改动，**零账本查询**。
    if (sp != null && current <= sp) {
      return FocusLevelSettleResult(
        currentLevel: current,
        settledLevel: sp,
        settledBefore: sp,
        granted: const <LevelGrant>[],
        totalSunlight: 0,
        firstUseSilent: false,
      );
    }

    // 慢路径：必须问账本（双锚点取大 / 首用判定，都依赖「账本里已发到哪一级」）。
    final int grantedMax = await probeGrantedMaxTitleNode(current);

    // ② 首用分支：SP 未写过 **且** 账本一行都没有 ⇒ 老用户首用：**静默**。
    //    （🔴 C74 §9：直接给到应得等级与称号，**不补发历史称号阳光**）
    if (sp == null && grantedMax == kFocusLevelLocked) {
      await _store.write(current);
      // 🔴 `settledBefore = current`：首用静默**不算升级**（用户没有看到等级变化），
      // 故 `leveledUp == false` ⇒ 不播任何演出（C74 §7 追加拍板 ②）。
      return FocusLevelSettleResult(
        currentLevel: current,
        settledLevel: current,
        settledBefore: current,
        granted: const <LevelGrant>[],
        totalSunlight: 0,
        firstUseSilent: true,
      );
    }

    // ③ 结算分支：settled = max(SP 值（null 视为「未解锁」0）, 账本已发最高节点)。
    final int settled = math.max(sp ?? kFocusLevelLocked, grantedMax);
    final List<int> pending = pendingLevelsOf(
      currentLevel: current,
      settledLevel: settled,
    );
    final List<int> pendingTitles = titleLevelsOf(pending);
    final List<LevelGrant> granted = <LevelGrant>[];
    final Map<int, bool> settledOk = <int, bool>{};

    for (final int lv in pendingTitles) {
      final String refId = levelRefIdOf(lv);
      // 二级幂等（I1）：账本已有该称号节点 ⇒ 跳过（即便双锚点漏判也不会重发）。
      final int already = await countRef(refId);
      if (already > 0) {
        settledOk[lv] = true;
        continue;
      }
      final int amount = sunlightOfLevel(lv);
      try {
        final double before = await _ledger.balance();
        await _ledger.append(
          SunlightEntry(
            id: _idFactory(),
            ts: _clock(),
            type: SunlightType.earn,
            gross: amount.toDouble(),
            net: amount.toDouble(),
            balanceAfter: before + amount,
            refType: kFocusLevelUpRefType,
            refId: refId,
            dayKey: dayKey(_clock()),
          ),
        );
      } catch (_) {
        // 🔴 append-only 账本：写失败**绝不重试**（重试只会产生重复行 → 重复发阳光），
        // 跳过本条继续下一节点 —— 下次进页由 [nextSettledLevelOf] 停在失败前一级重试。
        continue;
      }
      granted.add(LevelGrant(level: lv, amount: amount));
      settledOk[lv] = true;
    }

    final int newSettled = nextSettledLevelOf(
      settledLevel: settled,
      currentLevel: current,
      isGranted: (int lv) => settledOk[lv] == true,
    );
    if (newSettled != settled || granted.isEmpty) {
      // granted 为空时也要回写：把 SP 推进到「当前等级/已结算节点」，
      // 既覆盖普通升级（只推等级），也修复「SP 落后于账本」的场景。
      await _store.write(newSettled); // 实现内部只增不减
    }

    return FocusLevelSettleResult(
      currentLevel: current,
      settledLevel: newSettled,
      // 🔑 推进**前**的锚点（= 双锚点取大）：调用方据此判「本轮升没升级」，
      // 而 `granted` 只回答「有没有解锁称号」—— 两件事在 C74 §6 修订二后**解耦**
      // （普通升级也播演出，但 `granted` 为空）。
      settledBefore: settled,
      granted: granted,
      totalSunlight: sunlightTotalOf(
        granted.map((LevelGrant g) => g.level).toList(growable: false),
      ),
      firstUseSilent: false,
    );
  }

  /// 只读判定（供 UI 展示；快路径下**零账本查询**，同 [settle]）。
  Future<int> settledLevelOf(double totalFocusMinutes) async {
    final FocusLevelSettleResult result = await settle(totalFocusMinutes);
    return result.settledLevel;
  }

  /// 账本里已存在的**最大称号节点**（≤ [upTo]），没有则返回 0。
  ///
  /// ⚠️ 只在「SP 未写过」或「当前等级已超过 SP」的罕见路径跑一次（≤ 9 次计数查询）；
  /// 快路径（绝大多数进页）**不调用**本方法。
  Future<int> probeGrantedMaxTitleNode(int upTo) async {
    for (int i = kFocusLevelTitleLevels.length - 1; i >= 0; i--) {
      final int level = kFocusLevelTitleLevels[i];
      if (level > upTo) continue;
      final int count = await countRef(levelRefIdOf(level));
      if (count > 0) return level;
    }
    return kFocusLevelLocked;
  }

  /// 「该 refId 在账本里已有几条」（全时段）。
  ///
  /// ⚠️ 走既有接口 [SunlightRepository.countByRefTypeAndRefIdSince]（`since = epoch`）
  /// 而不是新增接口方法 —— 实测：**Dart 的 `implements` 会要求实现**「带默认实现的
  /// 具体方法」，给 `SunlightRepository` 加方法会让仓内 **45 处**
  /// `implements SunlightRepository` 的测试假实现全部编译失败（打破设计 Q-B 的乐观
  /// 假设）。语义与「全时段计数」完全一致（`since = 1970-01-01`）。
  Future<int> countRef(String refId) => _ledger.countByRefTypeAndRefIdSince(
        kFocusLevelUpRefType,
        refId,
        DateTime.utc(1970),
      );
}
