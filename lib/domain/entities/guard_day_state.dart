/// 花园守卫「当日状态」不可变实体（纯数据 + `copyWith` + JSON 往返）。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §4（状态机）/ §7.2（存储结构）。
///
/// ## 本批范围
/// **只做实体，不做存储**（`GuardStateStore` 接口 + `SharedPreferences` 实现是
/// 第二批）。因此本文件**零 IO、零 flutter import**、可 `dart test` 直跑。
///
/// ## 为什么当日状态必须落盘（不能全靠派生）
/// | 数据 | 为什么不能派生 | 落点 |
/// |---|---|---|
/// | 今日已消耗能量点数 | 消耗是「动作」，免费路径**不写账本** | 状态的 [GuardDayState.energyUsed] |
/// | 当日小偷 / 落骰结果 / 领取状态 / 当前 buff | 完全新的状态 | 本实体 |
///
/// 阳光 / 被偷 / 付费走既有阳光账本（append-only），植物进度走 `plants` 表 ——
/// 本实体**只装账本与进度表装不下的那部分**。
///
/// ## 关键纪律
///  · [dayKey] 是幂等唯一真源：`storedDayKey == today` ⇒ 空操作；
///  · prefs 键必须带 childId（见 [kGuardDayStatePrefPrefix]），否则「A 的小偷出现在
///    B 的今日页」；
///  · 线名（[GuardDayStatus.id] / [GuardThiefSpec.id] / [GuardDropSpec.id]）一经写入
///    即冻结 —— 换名字等于让老存档全部读不出来。
library guard_day_state;

import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';

/// 胶囊 5 态（PRD §4）。
///
/// `absent`（无小偷）**不是**本枚举的值：它由「本地无当日状态 / 全园无存活株」
/// 在展示层判定，因为「今天没有贼」这件事本身不需要落盘。
enum GuardDayStatus {
  /// 已生成、未处理（待处理态；免费/付费由成本判定决定，不在这里区分）。
  none,

  /// 待处理（胶囊可见、可点）。
  pending,

  /// 战斗中（动画播放中；落骰已定，只回放结果）。
  fighting,

  /// 已领取（阳光已入账、buff 已写入）。
  claimed,

  /// 余额不足（无能量 且 余额 < 免罚线；当天免罚、胶囊不可点）。
  short;

  /// 冻结的 JSON 线名。
  String get id {
    switch (this) {
      case GuardDayStatus.none:
        return 'none';
      case GuardDayStatus.pending:
        return 'pending';
      case GuardDayStatus.fighting:
        return 'fighting';
      case GuardDayStatus.claimed:
        return 'claimed';
      case GuardDayStatus.short:
        return 'short';
    }
  }
}

/// 线名反查状态（未知线名兜底 [GuardDayStatus.none]，不抛异常）。
GuardDayStatus guardDayStatusFromId(String? id) {
  if (id == null) return GuardDayStatus.none;
  for (final GuardDayStatus status in GuardDayStatus.values) {
    if (status.id == id) return status;
  }
  return GuardDayStatus.none;
}

/// 当日 buff（= 那张券的「额度 / 已用」账）。
///
/// 与 [GuardDropKind] 的关系：`kind` 决定「这张券怎么用」，[quota] 是**记账字段**
/// （浇水券 6 / 劳动券 4 / 施肥券次数 / 免费券 1 次）。🔴 B13.4：浇水 / 劳动券
/// 已改**当日不限次**（减免不看额度，见 `GuardVoucherKind.isUnlimitedDaily`），
/// 这两类的 `quota` 仅作存量存档兼容；施肥 / 免费券仍「用完即止」。
/// 页面**不得**自行 `-1`。
class GuardBuffState {
  /// 券的种类。
  final GuardDropKind kind;

  /// 当日额度上限（单位随种类：浇水/劳动/施肥券 = ☀，免费券 = 次数）。
  final int quota;

  /// 已用掉的数量（单位同 [quota]）。
  final int used;

  const GuardBuffState({
    required this.kind,
    required this.quota,
    this.used = 0,
  });

  /// 还剩多少（永不为负；只有「无道具档」会恒为 0）。
  int get remaining {
    if (quota <= used) return 0;
    return quota - used;
  }

  /// 是否已用完（用完后券仍显示，只是不再减免）。
  bool get isExhausted => remaining <= 0;

  /// 是否还有可用的额度。
  bool get hasRemaining => !isExhausted;

  /// 记账一笔核销后的不可变副本。
  ///
  /// [amount] 会被钳制到「不超过剩余额度」，所以**重复调用不会把 used 顶过
  /// quota**（这正是「当日累计封顶」的实现形态）。负数 / 0 视为空操作。
  GuardBuffState consume(int amount) {
    if (amount <= 0) return this;
    final int delta = amount > remaining ? remaining : amount;
    if (delta == 0) return this;
    return GuardBuffState(kind: kind, quota: quota, used: used + delta);
  }

  /// 不可变副本。
  GuardBuffState copyWith({GuardDropKind? kind, int? quota, int? used}) {
    return GuardBuffState(
      kind: kind ?? this.kind,
      quota: quota ?? this.quota,
      used: used ?? this.used,
    );
  }

  /// 序列化（线名冻结）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.id,
      'quota': quota,
      'used': used,
    };
  }

  /// 反序列化（缺字段 / 未知券名一律兜底为「无道具档、额度 0、已用 0」）。
  factory GuardBuffState.fromJson(Map<String, Object?> json) {
    return GuardBuffState(
      kind: guardDropKindFromId(json['kind'] as String?),
      quota: _intOf(json['quota']),
      used: _intOf(json['used']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuardBuffState &&
          other.kind == kind &&
          other.quota == quota &&
          other.used == used;

  @override
  int get hashCode => Object.hash(kind, quota, used);

  @override
  String toString() => 'GuardBuffState(${kind.id}, quota=$quota, used=$used)';
}

/// 某一天的守卫状态（**不可变**；每次变化产出新实例）。
class GuardDayState {
  /// 状态归属的自然日（`yyyy-MM-dd`）。幂等的唯一真源。
  final String dayKey;

  /// 胶囊状态。
  final GuardDayStatus status;

  /// 当日的贼（`null` = 尚未生成 / 全园无存活株，没有贼）。
  final GuardThiefKind? thiefKind;

  /// 今日已消耗的能量点数（免费路径的唯一记账，上限见
  /// [kGuardEnergyDailyMaxFree] / [kGuardEnergyDailyMaxPremium]）。
  final int energyUsed;

  /// 今日已付出的阳光（付费路径；0 = 没花钱）。
  final int paidSun;

  /// 今日必得阳光的数额（`resolve` 时定死，`claim` 时入账）。
  final int winSun;

  /// 今日掉落档。
  final GuardDropKind dropKind;

  /// 今日被偷走的阳光（未处理结算时记；0 = 没被偷）。
  final int sunStolen;

  /// 今日被偷走的成长（`plantId -> pp`）。PRD §7.2 JSON 的 `growthStolen`。
  ///
  /// 用于「每株每天 ≤ [kGuardGrowthStealPerPlantDailyCap]」的对账与埋点
  /// （`guard_stolen` 的 `plantCount`）。
  final Map<String, double> growthStolen;

  /// 当前 buff（`null` = 没有券 / 券已过期）。
  final GuardBuffState? buff;

  /// 🔴 B13.5：第二张券的掉落档（`none` = 今天没有第二张）。
  ///
  /// ⚠️ **Guard-B13.11 起本字段不再被掉落层写入**（`deriveGuardRoll` 恒产出
  /// `none`）：第二张券搬进高级宝箱，真源是 [chestBonusDropKind]。
  /// 保留本字段只为两件事：① 读得懂**升级前**写入的旧存档（当天的双券不丢）；
  /// ② 旧测试 / 旧埋点不必改字段名。新代码请一律读 [chestBonusDropKind]。
  final GuardDropKind bonusDropKind;

  /// 🔴 B13.5：第二张券的额度账（`null` = 没有第二张 / 未领取）。
  ///
  /// 生效规则与 [buff] 完全一致：`GuardVoucherService` 按**券种匹配**取用
  /// （浇水动作只吃浇水券那张，两张券互不干扰、可同时生效）。
  final GuardBuffState? bonusBuff;

  /// 教学浮层（「15 分钟 = 1 能量点」）是否已看过（守卫战 v2 · B1 追加）。
  ///
  /// 只播一次的持久化标记：`fromJson` 缺字段兜底 `false`，老存档向后兼容
  /// （老用户首次进战斗前会看到一次教学，之后不再弹）。
  final bool tutorialSeen;

  /// 当日**场次序号**（0 = 今天的第 1 场；B10/B4 追加）。单位：次。
  ///
  /// ## 🔴 为什么需要它（玄参第五轮「第二次花 5 阳光不扣」）
  /// 账本的 `guard_pay` / `guard_win` id 是 `guard_pay_<child>_<dayKey>` —— 每天
  /// **一行**。生产口径下一天只有一个贼、只领一次，这没问题；但调试重置后同一
  /// 天会打第二场，第二次领取要么被账本主键去重丢掉、要么被「今天已有
  /// `guard_win` 行 ⇒ 视为已领取」的幂等网挡住 ⇒ **花了钱不扣、赢了不发**。
  ///
  /// 本字段把「第几场」写进状态（幂等键不再只有 dayKey）：
  ///  · 每次 `resolve()` / `forceThiefForDebug()` 生成当日状态时，从账本
  ///    **当日 `guard_win` 行数**派生（每个完成的场次恰好一行）；
  ///  · id 只在 `battleAttempt > 0` 时追加 `_a<attempt>` 后缀 ⇒
  ///    **第 1 场（生产路径）的账本 id 与历史逐位相同，老数据零影响**；
  ///  · 账本层幂等网的判据变成「当日 `guard_win` 行数 > 本场序号」——
  ///    同一场内重复领取仍然只记一次钱（同 id 主键冲突），生产幂等**一格没松**。
  final int battleAttempt;

  // ── 高级宝箱（Guard-B13.11 · 玄参 2026-11-11）────────────────────────────
  //
  // 六个字段全部**加性**：`resolve()` 时一次性由 `deriveGuardChest` 定死并落盘，
  // `claim()` 只按落盘结果发放（`expire()` 的 fighting 补发分支同源读它）。
  // 🔴 宝箱阶段**不新增 `GuardDayStatus`**：宝箱是表现层演出阶段，加了新状态会让
  //    「开箱时强杀 App」的孩子次日被 `expire()` 判成「没处理」而扣损失
  //    （设计 §2.3 方案 B 被否决的理由）。

  /// 本场宝箱档位（缺省 [GuardChestTier.normal]）。
  ///
  /// ⚠️ 缺省是 `normal` 而不是「无宝箱」：普通宝箱 = 改造前的全部内容
  /// （必得阳光 + 主券），所以**旧存档读成 normal 一分钱都不会多发**。
  final GuardChestTier chestTier;

  /// 高级宝箱里的**第二张券**（`none` = 没有第二张）。
  ///
  /// 与 [bonusDropKind] 的关系：🔴 Guard-B13.11 起第二张券**只在高级宝箱里出现**，
  /// 掉落层（[bonusDropKind]）恒 `none`。本字段才是「第二张券」的真源；
  /// [bonusDropKind] 只为旧存档 / 旧测试保留。
  final GuardDropKind chestBonusDropKind;

  /// 高级宝箱的碎片数量（片/次；`0` = 没有碎片，正常为 1~2）。
  final int chestFragmentQty;

  /// 高级宝箱的种子档位（`none` = 没有种子）。
  final GuardSeedKind chestSeedKind;

  /// 高级宝箱种子的具体物种 id（[chestSeedKind] == none 时恒 `null`）。
  final String? chestSeedSpeciesId;

  /// 碎片 / 种子**已发放**标记（幂等键）。
  ///
  /// ## 🔴 为什么需要它（这是「多发一次」而不是「吞掉奖励」的唯一手段）
  /// 碎片与种子走 `BloomRewardRepository`（账户级藏品，**不进阳光账本**），
  /// 而阳光走账本 —— 两者跨仓储、**无事务**。`claim()` 的顺序是
  /// 「先发碎片/种子 → 再写 `guard_win` 账本行」（设计 §5.2 ⑤ 在 ⑥ 之前）：
  ///  · 反过来的话，账本行写成功而碎片发放前崩溃 ⇒ 重进时账本层幂等判定
  ///    「已领取」⇒ **碎片永久丢失**，而结算卡已经承诺「获得碎片」；
  ///  · 本顺序的最坏结果是**多发 1 片**（方向偏向孩子，玄参已接受）。
  /// 本标记只覆盖「⑤ 与 ⑧ 之间进程被杀」这一个窗口，把重复量压到最小。
  final bool chestExtrasGranted;

  const GuardDayState({
    required this.dayKey,
    required this.status,
    this.thiefKind,
    this.energyUsed = 0,
    this.paidSun = 0,
    this.winSun = 0,
    this.dropKind = GuardDropKind.none,
    this.bonusDropKind = GuardDropKind.none,
    this.sunStolen = 0,
    this.growthStolen = const <String, double>{},
    this.buff,
    this.bonusBuff,
    this.tutorialSeen = false,
    this.battleAttempt = 0,
    this.chestTier = GuardChestTier.normal,
    this.chestBonusDropKind = GuardDropKind.none,
    this.chestFragmentQty = 0,
    this.chestSeedKind = GuardSeedKind.none,
    this.chestSeedSpeciesId,
    this.chestExtrasGranted = false,
  });

  /// 一天的空白起点（`dayKey` 变化时用它重置）。
  factory GuardDayState.empty(String dayKey) =>
      GuardDayState(dayKey: dayKey, status: GuardDayStatus.none);

  /// 今天有没有贼（有存活株且已生成）。
  bool get hasThief => thiefKind != null;

  /// 是否已领取（幂等：`claim()` 遇到本值即 no-op）。
  bool get isClaimed => status == GuardDayStatus.claimed;

  /// 是否当天免罚（余额不足档）。
  bool get isFreeRide => status == GuardDayStatus.short;

  /// 不可变副本。
  ///
  /// ⚠️ [thiefKind] / [buff] 两个可空字段用「显式布尔开关」而不是
  /// `x ?? this.x`：本项目的 `Plant.copyWith` 已经踩过「可空字段清不掉」的坑
  /// （见 `Plant.kClear` 的注释）。清空的写法是
  /// `copyWith(clearBuff: true)` / `copyWith(clearThief: true)`。
  GuardDayState copyWith({
    String? dayKey,
    GuardDayStatus? status,
    GuardThiefKind? thiefKind,
    bool clearThief = false,
    int? energyUsed,
    int? paidSun,
    int? winSun,
    GuardDropKind? dropKind,
    GuardDropKind? bonusDropKind,
    int? sunStolen,
    Map<String, double>? growthStolen,
    GuardBuffState? buff,
    bool clearBuff = false,
    GuardBuffState? bonusBuff,
    bool clearBonusBuff = false,
    bool? tutorialSeen,
    int? battleAttempt,
    GuardChestTier? chestTier,
    GuardDropKind? chestBonusDropKind,
    int? chestFragmentQty,
    GuardSeedKind? chestSeedKind,
    String? chestSeedSpeciesId,
    bool clearChestSeedSpeciesId = false,
    bool? chestExtrasGranted,
  }) {
    return GuardDayState(
      dayKey: dayKey ?? this.dayKey,
      status: status ?? this.status,
      thiefKind: clearThief ? null : (thiefKind ?? this.thiefKind),
      energyUsed: energyUsed ?? this.energyUsed,
      paidSun: paidSun ?? this.paidSun,
      winSun: winSun ?? this.winSun,
      dropKind: dropKind ?? this.dropKind,
      bonusDropKind: bonusDropKind ?? this.bonusDropKind,
      sunStolen: sunStolen ?? this.sunStolen,
      growthStolen: growthStolen ?? this.growthStolen,
      buff: clearBuff ? null : (buff ?? this.buff),
      bonusBuff: clearBonusBuff ? null : (bonusBuff ?? this.bonusBuff),
      tutorialSeen: tutorialSeen ?? this.tutorialSeen,
      battleAttempt: battleAttempt ?? this.battleAttempt,
      chestTier: chestTier ?? this.chestTier,
      chestBonusDropKind: chestBonusDropKind ?? this.chestBonusDropKind,
      chestFragmentQty: chestFragmentQty ?? this.chestFragmentQty,
      chestSeedKind: chestSeedKind ?? this.chestSeedKind,
      // `chestSeedSpeciesId` 可空 ⇒ 显式开关清空（同 thiefKind / buff 的口径）。
      chestSeedSpeciesId: clearChestSeedSpeciesId
          ? null
          : (chestSeedSpeciesId ?? this.chestSeedSpeciesId),
      chestExtrasGranted: chestExtrasGranted ?? this.chestExtrasGranted,
    );
  }

  /// 序列化（线名冻结；键名与 PRD §7.2 一致）。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'dayKey': dayKey,
      'status': status.id,
      'thiefKind': thiefKind?.id,
      'energyUsed': energyUsed,
      'paidSun': paidSun,
      'winSun': winSun,
      'dropKind': dropKind.id,
      'bonusDropKind': bonusDropKind.id,
      'sunStolen': sunStolen,
      'growthStolen': Map<String, double>.from(growthStolen),
      'buff': buff?.toJson(),
      'bonusBuff': bonusBuff?.toJson(),
      'tutorialSeen': tutorialSeen,
      'battleAttempt': battleAttempt,
      // 🔴 Guard-B13.11：宝箱六字段（纯追加键；老读者忽略未知键即可）。
      'chestTier': chestTier.id,
      'chestBonusDropKind': chestBonusDropKind.id,
      'chestFragmentQty': chestFragmentQty,
      'chestSeedKind': chestSeedKind.id,
      'chestSeedSpeciesId': chestSeedSpeciesId,
      'chestExtrasGranted': chestExtrasGranted,
    };
  }

  /// 反序列化。
  ///
  /// 容错口径：缺字段取默认值、未知线名兜底（状态 → none / 贼 → null /
  /// 券 → none），**绝不抛异常** —— 一份坏掉的 prefs 不该让孩子打不开今日页。
  /// [dayKey] 缺失 / 非字符串 / 空串时用 [fallbackDayKey] 兜底（调用方传入「今天」）。
  factory GuardDayState.fromJson(
    Map<String, Object?> json, {
    required String fallbackDayKey,
  }) {
    final Object? rawBuff = json['buff'];
    // 🔴 Guard-B13.11：种子档位与物种必须先解出来再判「不变量」（档位 none ⇒
    //    物种强制 null），否则一份「档位 none 但物种非空」的脏存档会让
    //    发放层把一颗不存在的种子发出去。
    final GuardSeedKind seedKind =
        guardSeedKindFromId(json['chestSeedKind'] as String?);
    final Object? rawSpecies = json['chestSeedSpeciesId'];
    return GuardDayState(
      // 🔴 P2-③ 收口（与下面四个旧字段**同一口径**）：`dayKey` 原来写的是
      //    `json['dayKey'] as String?` —— 一份 `{"dayKey": 42}` 的脏存档会抛
      //    `TypeError`，与文件头「绝不抛异常」相悖（`GuardStatePrefsStore.read`
      //    的 `catch(_)` 只是把白屏挡住了，契约仍不一致）。
      //    [_stringOf] 对「非 String」与「空串」都返回 `null` ⇒ 这里继续回落
      //    [fallbackDayKey]（调用方传「今天」）——**空串不算合法 dayKey**，
      //    否则 `dayKey == ''` 会让「同一天 ⇒ 空操作」永远不成立。
      dayKey: _stringOf(json['dayKey']) ?? fallbackDayKey,
      // ⚠️ 这四个**旧**字段用 [_stringOf] 而不是 `as String?`：脏存档里可能是
      //    数字 / 列表 / Map，硬转会抛 `TypeError`（QA 实证 `{"status": 42}` 就炸），
      //    与文件头「绝不抛异常 —— 一份坏掉的 prefs 不该让孩子打不开今日页」相悖。
      //    本批给 chest* 四键定下口径后，旧字段缺的只是这一步对称收口。
      status: guardDayStatusFromId(_stringOf(json['status'])),
      thiefKind: guardThiefKindFromId(_stringOf(json['thiefKind'])),
      energyUsed: _intOf(json['energyUsed']),
      paidSun: _intOf(json['paidSun']),
      winSun: _intOf(json['winSun']),
      dropKind: guardDropKindFromId(_stringOf(json['dropKind'])),
      // 🔴 B13.5：缺字段兜底 none / null —— 老存档（无 bonus 键）向后兼容。
      bonusDropKind: guardDropKindFromId(_stringOf(json['bonusDropKind'])),
      sunStolen: _intOf(json['sunStolen']),
      growthStolen: _doubleMapOf(json['growthStolen']),
      buff: rawBuff is Map
          ? GuardBuffState.fromJson(Map<String, Object?>.from(rawBuff))
          : null,
      bonusBuff: json['bonusBuff'] is Map
          ? GuardBuffState.fromJson(
              Map<String, Object?>.from(json['bonusBuff'] as Map))
          : null,
      // 缺字段兜底 false：老存档（无 tutorialSeen 键）向后兼容。
      tutorialSeen: json['tutorialSeen'] == true,
      // 缺字段兜底 0：老存档（无 battleAttempt 键）= 当天第 1 场，账本 id 无后缀。
      battleAttempt: _intOf(json['battleAttempt']),
      // 🔴 Guard-B13.11：宝箱六字段全部兜底 —— 老存档（无 chest* 键）读成
      //    「普通宝箱、无附加项、未发放」，与改造前的经济口径逐位一致。
      // ⚠️ 用 [_stringOf] 而不是 `as String?`：脏存档里这两个键可能是数字，
      //    硬转会抛 `TypeError`（一个坏 prefs 不该让孩子打不开今日页）。
      chestTier: guardChestTierFromId(_stringOf(json['chestTier'])),
      chestBonusDropKind:
          guardDropKindFromId(_stringOf(json['chestBonusDropKind'])),
      chestFragmentQty: _positiveIntOf(json['chestFragmentQty']),
      chestSeedKind: seedKind,
      chestSeedSpeciesId: seedKind == GuardSeedKind.none
          ? null
          : _stringOf(rawSpecies),
      chestExtrasGranted: json['chestExtrasGranted'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GuardDayState) return false;
    if (other.dayKey != dayKey ||
        other.status != status ||
        other.thiefKind != thiefKind ||
        other.energyUsed != energyUsed ||
        other.paidSun != paidSun ||
        other.winSun != winSun ||
        other.dropKind != dropKind ||
        other.bonusDropKind != bonusDropKind ||
        other.sunStolen != sunStolen ||
        other.buff != buff ||
        other.bonusBuff != bonusBuff ||
        other.tutorialSeen != tutorialSeen ||
        other.battleAttempt != battleAttempt ||
        other.chestTier != chestTier ||
        other.chestBonusDropKind != chestBonusDropKind ||
        other.chestFragmentQty != chestFragmentQty ||
        other.chestSeedKind != chestSeedKind ||
        other.chestSeedSpeciesId != chestSeedSpeciesId ||
        other.chestExtrasGranted != chestExtrasGranted) {
      return false;
    }
    if (other.growthStolen.length != growthStolen.length) return false;
    for (final MapEntry<String, double> e in growthStolen.entries) {
      if (other.growthStolen[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        dayKey,
        status,
        thiefKind,
        energyUsed,
        paidSun,
        winSun,
        dropKind,
        bonusDropKind,
        sunStolen,
        buff,
        bonusBuff,
        tutorialSeen,
        battleAttempt,
        chestTier,
        chestBonusDropKind,
        chestFragmentQty,
        chestSeedKind,
        chestSeedSpeciesId,
        chestExtrasGranted,
        Object.hashAllUnordered(
          growthStolen.entries
              .map((MapEntry<String, double> e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'GuardDayState($dayKey, ${status.id}, '
      'thief=${thiefKind?.id}, energyUsed=$energyUsed, paidSun=$paidSun, '
      'winSun=$winSun, drop=${dropKind.id}, bonusDrop=${bonusDropKind.id}, '
      'sunStolen=$sunStolen, growthStolen=$growthStolen, buff=$buff, '
      'bonusBuff=$bonusBuff, tutorialSeen=$tutorialSeen, '
      'attempt=$battleAttempt, chest=${chestTier.id}, '
      'chestBonus=${chestBonusDropKind.id}, chestFragments=$chestFragmentQty, '
      'chestSeed=${chestSeedKind.id}($chestSeedSpeciesId), '
      'chestExtrasGranted=$chestExtrasGranted)';
}

/// JSON 里的 int 字段（`num` / `String` / 缺失都兜底为 0）。
int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// JSON 里的**非负** int 字段（负数 / 脏值一律收敛成 0）。
///
/// 专用碎片数量：一个坏存档不该让发放层减片（`setPremiumFragmentBalance` 是
/// 覆盖式写，负数会直接把账户余额扣掉）。
int _positiveIntOf(Object? value) {
  final int raw = _intOf(value);
  return raw > 0 ? raw : 0;
}

/// JSON 里的字符串字段（非 `String` / 空串一律 `null`，**不抛类型异常**）。
String? _stringOf(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// JSON 里的 `Map<String, double>`（非 Map / 非数值项一律跳过）。
Map<String, double> _doubleMapOf(Object? value) {
  if (value is! Map) return const <String, double>{};
  final Map<String, double> result = <String, double>{};
  value.forEach((Object? key, Object? raw) {
    if (key is! String) return;
    if (raw is num) {
      result[key] = raw.toDouble();
    }
  });
  return result;
}
