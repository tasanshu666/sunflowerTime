/// 结算页（T09）：光回罐动画 + 本次专注时长 + 产出阳光 + 当日累计 + 向日葵庆祝态。
///
/// 依据 PRD §4.1.2（结算动画是全场的视觉高光：那束出远门的光从屏外回来、落进阳光罐，
/// 账同步上涨；本次专注时长、产出阳光数、当日累计、向日葵醒着庆祝）。
///
/// 预留「家长转述表扬」占位区（M2 夸夸台接入，PRD §4.9）：M1 先留空位。
/// （C49 / 玄参 2026-10-10：夸夸台裁撤，占位框改为**随机系统夸奖卡**）
library settle_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/praise_phrases.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/pages/eye_care_page.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

/// 专注时长格式化（B25 修复）：[minutes] 单位为**分钟**。
///
/// 先转成总秒数再拆成「分 + 秒」，避免把分钟当秒拆导致 1 分钟显示成「1 秒」。
String formatFocusMinutes(double minutes) {
  final int totalSeconds = (minutes * 60).round();
  final int m = totalSeconds ~/ 60;
  final int s = totalSeconds % 60;
  if (m == 0) return '$s 秒';
  return s == 0 ? '$m 分钟' : '$m 分 $s 秒';
}

/// `/settle` 路由参数（由专注页经 go extra 传入；深链缺失时为 null）。
///
/// 除专注结算结果外，可选携带**联动成长项**的结算结果（仅从「成长」进入专注时产生）：
///  - [taskOutcome] 非空且 `verified` → 结算页多展示一行「成长项「X」完成 +N ☀」；
///  - `rejected` → 本次专注没到该项要求的时长，成长项未算上（正常业务，温和提示）；
///  - [taskSettleSkipped] 为真 → 成长项结算被跳过（取不到本次落库会话 / 结算异常），
///    结算页给非阻塞提示，不影响本次专注阳光（仅兜底，正常不应触发）。
class SettleArgs {
  /// 本次专注的结算结果（缺失即深链直入，无专注数据）。
  final FocusSettlement? settlement;

  /// 联动成长项的结算结果（无联动项 / 被跳过时为 null）。
  final TaskCheckInOutcome? taskOutcome;

  /// 联动成长项名称（展示用；无则 null）。
  final String? taskName;

  /// 是否跳过了成长项结算（取不到真实落库会话 / 结算异常，兜底标记）。
  final bool taskSettleSkipped;

  /// 进入结算页之前是否**还需要一次护眼休息**（C28 §1 场末插入点）。
  ///
  /// 真值 → 本页会先把 [EyeCarePage] 压在自己之上，等它结束（完成 / 确认跳过）才
  /// 露出下面的奖励数字：**先护眼、后领奖励**，防止孩子为了拿奖励直接跳过护眼。
  ///
  /// 由专注页按「距上次护眼之后的本段注视 ≥ [kEyeCareSessionEndMinutes] 分钟」算出
  /// 后随 [SettleArgs] 传入；深链直入（本参数为默认 false）不插卡，行为与既往一致。
  ///
  /// 2026-10-08 修订：**到时结束**的场末护眼改由专注页在其之上播放（横屏 + 3s 过渡，
  /// 修复「护眼竖屏播放 / 盖住结算动画」），本页插卡路径仅剩手动结束 / 离席打断场景。
  final bool eyeCarePending;

  /// 本场**已完成**的护眼奖励（玄参 2026-10-08）：
  /// 到时结束走专注页内护眼时随 args 传入（护眼卡内部已入账，本页只展示）；
  /// 本页自带插卡路径（eyeCarePending）完成时同样按 [kEyeCareRewardSunlight] 显示。
  final int eyeCareReward;

  const SettleArgs({
    this.settlement,
    this.taskOutcome,
    this.taskName,
    this.taskSettleSkipped = false,
    this.eyeCarePending = false,
    this.eyeCareReward = 0,
  });
}

class SettlePage extends ConsumerStatefulWidget {
  /// 结算参数（由专注页经 go extra 传入；深链缺失时为 null）。
  final SettleArgs? args;

  const SettlePage({super.key, this.args});

  @override
  ConsumerState<SettlePage> createState() => _SettlePageState();
}

class _SettlePageState extends ConsumerState<SettlePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  /// 今日**获得**的阳光合计（只累加正向获得，不含浇水 / 施肥 / 种植 / 扩容等消耗）。
  ///
  /// [FocusSettlement.todayNet] 是当日账本 net 求和（**含支出**），养护 / 扩容之后会
  /// 变成负数（真机实测 -173）；本栏口径改为「当日 earn 类型的 net 合计」，恒 ≥ 0。
  /// null = 尚未拉到，此时先用 [FocusSettlement.todayNet] 钳到 ≥ 0 顶一帧。
  double? _todayEarned;

  /// 本次结算**前置**的护眼休息是否已经走完（拿到护眼卡结果后翻 true）。
  ///
  /// 这是「先护眼、后领奖励」在**渲染层**的落点：护眼卡压在本页之上、结果未回时
  /// （[_eyeCareBlocking]），本页所有数字以「···」占位，不在卡背后抢先露出
  /// 奖励数字（孩子会以为「先领了再护眼」）。
  bool _eyeCareDone = false;

  /// 本场结算的护眼奖励（玄参 2026-10-04 拍板口径）：完成护眼 = [kEyeCareRewardSunlight]
  /// （账本入账由护眼卡内部完成，本页只收结果显示）；跳过 / 未触发 = 0。
  ///
  /// 2026-10-08：初值改为读 [SettleArgs.eyeCareReward]——到时结束的场末护眼已在
  /// 专注页播完（横屏 + 3s 过渡），奖励随 args 直达，本页不再插卡。
  int _eyeCareReward = 0;

  /// 结算前护眼卡是否仍在展示（带 [SettleArgs.eyeCarePending] 进场且结果未回）。
  bool get _eyeCareBlocking =>
      (widget.args?.eyeCarePending ?? false) && !_eyeCareDone;

  /// 本场随机夸奖语（C49）：进入结算页时抽一次，动画重建不换句。
  late final String _praisePhrase = randomPraisePhrase();

  /// 数字占位：护眼卡未收口时全部以「···」遮住。
  String _mask(String value) => _eyeCareBlocking ? '···' : value;

  @override
  void initState() {
    super.initState();
    // 2026-10-08：到时结束的场末护眼已在专注页播完，奖励随 args 直达（只展示）。
    _eyeCareReward = widget.args?.eyeCareReward ?? 0;
    // 玄参 2026-09-30 拍板：专注结束后**强制竖屏**进入结算页。
    // 专注页锁横屏，结束时手机常仍横持（专注页 dispose 只复位方向 = 跟随传感器，
    // 横持就保持横屏），竖版信息页在横屏下溢出（实测 BOTTOM OVERFLOWED BY 267
    // PIXELS）。主流专注 App（番茄ToDo / Forest）的结算/统计页也均为竖屏信息页。
    unawaited(_lockPortrait());
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
    // 显示口径修正：本栏只统计「获得」，单独读一次账本（不改动任何写入逻辑）。
    unawaited(_loadTodayEarned());
    // 结算页向日葵庆祝序列帧（settle）配音；受 soundOn 保护，缺素材静默降级。
    // F95（玄参 2026-10-08）：口径与 B32 动画对齐——只要带结算数据进场就配音
    // （含短专注 net==0），不再「画面庆祝、声音静音」。静音开关仍由 playSfx
    // 内部 [_soundOn] 统一拦截。
    if (widget.args?.settlement != null) {
      ref.read(audioServiceProvider).playSfx(AudioCue.focusSettle);
    }
    // T-B：结算后注入 sun_earned / valid_focus_day 埋点（settlement 非空时）。
    final FocusSettlement? settlement = widget.args?.settlement;
    if (settlement != null) {
      unawaited(_trackSunEarned(settlement));
      unawaited(_trackValidFocusDay(settlement));
      // P0 · B：结算后判定「本轮新跨过的里程碑」（按 type 去重，一生只写一次）。
      unawaited(_recordMilestones());
    }
    // C28 §1 场末插入点（玄参 2026-10-04 补接线）：带 eyeCarePending 进场时，
    // 先把护眼卡压在本页之上，拿到结果（完成 / 确认跳过）才露出奖励数字。
    if (widget.args?.eyeCarePending ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openEyeCareIfPending());
      });
    }
  }

  /// 压入结算前护眼卡（C28「先护眼、后领奖励」）。
  ///
  /// 完成时的 [kEyeCareRewardSunlight] 由**护眼卡内部**写阳光账本（唯一真源，
  /// `refType='eye_care_break'`），本页只收结果、驱动「护眼奖励」行显示；
  /// 跳过（确认后）→ 无奖励显示 0。设置读取失败按默认「允许跳过」放行（安全侧，
  /// 不让配置异常阻塞结算流程）。
  Future<void> _openEyeCareIfPending() async {
    if (!mounted || _eyeCareDone) return;
    bool skipAllowed = true;
    try {
      final AppSettings s =
          await ref.read(settingsRepositoryProvider).getSettings();
      skipAllowed = EyeCareService.isSkipAllowed(s);
    } catch (_) {
      // 设置读取失败：按默认「允许跳过」放行。
    }
    if (!mounted || _eyeCareDone) return;
    // 护眼卡 pop 出的是 [EyeCareResult] 包装（不是裸枚举）。
    final Object? result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        fullscreenDialog: true,
        builder: (_) => EyeCarePage(
          args: EyeCareArgs(
            skipAllowed: skipAllowed,
            source: EyeCareSource.sessionEnd,
          ),
        ),
      ),
    );
    if (!mounted) return;
    // C44：护眼卡进场时锁了横屏（含本页是竖屏进场的 sessionEnd 路径）→
    // 退场后本页重新锁回竖屏，防止横屏态残留到结算页。
    unawaited(_lockPortrait());
    setState(() {
      _eyeCareDone = true;
      _eyeCareReward =
          result is EyeCareResult && result.completed
              ? kEyeCareRewardSunlight
              : 0;
    });
  }

  /// 强制竖屏（portraitUp/Down；失败静默 —— 方向锁定只是体验优化，不阻塞结算）。
  Future<void> _lockPortrait() async {
    try {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  // ── T-B 埋点（仅新增，不重构既有逻辑）─────────────────────────

  /// sun_earned：本次到账阳光（gross / net / 余额 / 是否触顶）。
  Future<void> _trackSunEarned(FocusSettlement s) async {
    try {
      await ref.read(trackingRepositoryProvider).track(TrackingEvent(
        id: Uuid().v4(),
        name: TrackingEventNames.sunEarned,
        type: TrackingType.metric,
        ts: DateTime.now(),
        payload: {
          'gross': s.rawS,
          'net': s.net,
          'balance_after': s.balanceAfter,
          'capped': s.capped,
        },
      ));
    } catch (_) {}
  }

  /// valid_focus_day：有效专注日判定（≥15min 且完成率≥0.90）。
  Future<void> _trackValidFocusDay(FocusSettlement s) async {
    try {
      final bool met = s.actualFocusMin >= kValidFocusMinutes &&
          (s.plannedMin > 0
              ? s.actualFocusMin / s.plannedMin >= kCompletionRateThreshold
              : false);
      await ref.read(trackingRepositoryProvider).track(TrackingEvent(
        id: Uuid().v4(),
        name: TrackingEventNames.validFocusDay,
        type: TrackingType.metric,
        ts: DateTime.now(),
        payload: {
          'day_key': dayKey(DateTime.now()),
          'actual_min': s.actualFocusMin,
          'met': met,
        },
      ));
    } catch (_) {}
  }

  /// P0 · B：按累计统计判定「本轮新跨过的里程碑」并落库（按 type 去重，幂等）。
  ///
  /// [MemoirService.recordMilestone] 内部按 type 去重（一生只写一次），故此处只需对
  /// 「已达阈值的里程碑」各调一次即可；阈值全部引用 `prd_params.dart` 常量（无裸字面量）。
  Future<void> _recordMilestones() async {
    try {
      final memoir = ref.read(memoirServiceProvider);
      final DateTime now = DateTime.now();
      final FocusStats stats =
          await ref.read(focusRepositoryProvider).totalStats();
      if (stats.totalValidDays >= kMilestoneFirstValidFocusDayDays) {
        await memoir.recordMilestone(kMilestoneFirstValidFocusDayType, now);
      }
      if (stats.totalFocusMinutes >= kMilestoneFocusTotal600MinMinutes) {
        await memoir.recordMilestone(kMilestoneFocusTotal600MinType, now);
      }
      if (stats.totalValidDays >= kMilestoneValidDays30Days) {
        await memoir.recordMilestone(kMilestoneValidDays30Type, now);
      }
      final List<Plant> plants =
          await ref.read(plantRepositoryProvider).plants();
      final int bloomed =
          plants.where((Plant p) => p.status == PlantStatus.bloomed).length;
      if (bloomed >= kMilestoneFirstBloomCount) {
        await memoir.recordMilestone(kMilestoneFirstBloomType, now);
      }
    } catch (_) {
      // 埋点失败容忍：绝不影响结算页既有行为。
    }
  }

  /// 联动成长项结算展示（**非阻塞**）：失败 / 跳过只温和提示，绝不改变
  /// 「本次专注已成功、阳光已入账」这个事实（契约见 [TaskCheckInService.settleFocusLinked]）。
  List<Widget> _taskSettlementLines() {
    final SettleArgs? args = widget.args;
    final TaskCheckInOutcome? o = args?.taskOutcome;
    final String name = args?.taskName ?? '成长项';

    if (args != null && args.taskSettleSkipped) {
      return <Widget>[
        const SizedBox(height: 12),
        const Text(
          '成长项结算没能完成，不影响本次专注阳光',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
        ),
      ];
    }
    if (o == null) return const <Widget>[];

    if (o.status == CheckInStatus.verified) {
      final String capped = o.cappedByDailyCap
          ? '（今日阳光已达上限，本次只到账 ${_fmtSun(o.granted)} ☀）'
          : '';
      return <Widget>[
        const SizedBox(height: 12),
        Text(
          '成长项「$name」完成 +${_fmtSun(o.granted)} ☀$capped',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFE082),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ];
    }
    if (o.status == CheckInStatus.rejected) {
      return <Widget>[
        const SizedBox(height: 12),
        Text(
          '成长项「$name」还差一点，下次专注够时长就算上啦 🌻',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
        ),
      ];
    }
    return const <Widget>[];
  }

  /// 拉取当日「只算获得」的阳光合计（显示口径修正：不含消耗，恒 ≥ 0）。
  ///
  /// 用 [SunlightRepository.earnNetOnDay]（只统计 `type == earn` 的 net），
  /// 而不是 [SunlightRepository.dayNet]（全部类型求和，含支出 → 会变负数）。
  Future<void> _loadTodayEarned() async {
    try {
      final double v = await ref
          .read(sunlightRepositoryProvider)
          .earnNetOnDay(dayKey(DateTime.now()));
      if (!mounted) return;
      setState(() => _todayEarned = v < 0 ? 0.0 : v);
    } catch (_) {
      // 读不到账本就退化为 0：本栏纯展示，绝不把异常抛到页面上。
      if (!mounted) return;
      setState(() => _todayEarned = 0.0);
    }
  }

  /// 阳光数值展示：整数不带小数，否则保留 1 位。
  String _fmtSun(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final settlement = widget.args?.settlement;
    final double net = settlement?.net ?? 0;
    // 今日累计 = 只统计「获得」（earn 口径，恒 ≥ 0）；未拉到时先用 todayNet 钳到 ≥ 0。
    final double todayNet = settlement?.todayNet ?? 0;
    final double todayEarned =
        _todayEarned ?? (todayNet > 0 ? todayNet : 0.0);
    final double actualMin = settlement?.actualFocusMin ?? 0;
    final bool shortAborted = settlement?.status == FocusStatus.shortAborted;
    // 本次产出被**今日专注额度**削过（原始 > 实得）：在结算页做一次温和说明
    // （玄参 2026-09-30：不因此在专注页加额度定时器打扰孩子）。
    final bool capped = settlement?.capped ?? false;
    final double rawS = settlement?.rawS ?? 0;

    // B20 修复：结算页经 go('/settle') 进入 → 路由栈底唯一页。
    // 用 PopScope 拦截系统返回手势（Android 右滑 / iOS 边缘滑动），
    // 把「返回意图」导向孩子首页 '/'（与现有「回首页」按钮行为一致），避免栈空直接退出 App。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF141426),
        // 背景升级（玄参 2026-09-30）：不再纯黑 —— 保持与专注页一致的深色系，
        // 叠深蓝紫渐变（顶部略亮的夜空感；参考潮汐「深色沉浸 + 层次渐变」）。
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF2E2E52),
                Color(0xFF1B1B2F),
                Color(0xFF141426),
              ],
              stops: <double>[0.0, 0.45, 1.0],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  SingleChildScrollView(
                    // 横屏兜底：强制竖屏生效前的瞬间 / 未来内容增高也不再溢出报错。
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_anim.value);
            return Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  '专注结束啦',
                  style: TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    // B32 修复：中央向日葵**始终**渲染，避免 <5 分钟（net==0）结算时花消失。
                    // 方案 A（玄参 2026-09-30）：有结算数据（settlement 非空）就**始终**播 settle
                    // 序列帧（含 <5 分钟短专注 net==0），画面与庆祝态统一，不回退默认矢量花；
                    // F95（玄参 2026-10-08）：音效口径同步对齐——settlement 非空即播
                    // （initState 控制），不再短专注静音。
                    // 仅 settlement 为 null（深链直入、无专注数据）才回退默认静态呼吸花。
                    child: settlement != null
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              // 柔和暖金光晕（庆祝氛围，不与帧特效抢戏）。
                              Container(
                                width: 300,
                                height: 300,
                                decoration: const BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: <Color>[
                                      Color(0x30FFE082),
                                      Color(0x00FFE082),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 260,
                                height: 260,
                                child: FrameSequencePlayer(
                                  frames: fxFrameAssets(
                                      kFocusSettleFxDir, kFocusSettleFrameCount),
                                  durationMs: kFocusSettleDurationMs,
                                  loop: false,
                                  holdLastFrame: true, // 播一次定格末帧（不循环、不渐隐）
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(
                            width: 260,
                            height: 260,
                            child: SunflowerCanvas(
                              level: FeedbackLevel.lvl1,
                              celebrating: false,
                            ),
                          ),
                  ),
                ),
                // 数据行：本次专注时长 / 产出阳光 / 当日累计
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _StatRow(
                        label: '本次专注',
                        value: _mask(formatFocusMinutes(actualMin)),
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '收集阳光',
                        // 数字滚动上涨（按动画进度）。
                        value: _mask('+${(net * t).round()}'),
                        highlight: true,
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '护眼奖励',
                        // 玄参 2026-10-08：本场护眼的结果——完成 +kEyeCareRewardSunlight ☀
                        // （护眼卡内部已入账，到时结束随 args 直达 / 插卡路径完成后回填）；
                        // 跳过 / 未触发显示 0。
                        value: _mask(
                          _eyeCareReward > 0 ? '+$_eyeCareReward ☀️' : '0 ☀️',
                        ),
                      ),
                      // F98（玄参 2026-10-08）：任务奖励升级为正式数据行——此前只是
                      // 「拥有阳光」下方的金色小字，真机反馈「只有专注奖励和护眼奖励，
                      // 没有任务奖励」（+6 实际已入账但展示层级太弱漏看）。
                      // 带联动成长项结算结果进场时与护眼奖励同级展示：
                      // verified → '+N ☀️'（N = 实际入账，含日上限削减后的值）；
                      // rejected → '0 ☀️'（本次没达标，下方灰字解释）。
                      if (widget.args?.taskOutcome != null) ...[
                        const SizedBox(height: 8),
                        _StatRow(
                          label: '任务奖励',
                          value: _mask(
                            widget.args!.taskOutcome!.status ==
                                    CheckInStatus.verified
                                ? '+${_fmtSun(widget.args!.taskOutcome!.granted)} ☀️'
                                : '0 ☀️',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '今日累计',
                        value: _mask('${(todayEarned * t).round()} ☀️'),
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '拥有阳光',
                        // 结算后余额（FocusSettlement.balanceAfter）。
                        value: _mask('${(settlement?.balanceAfter ?? 0).round()} ☀️'),
                      ),
                      if (shortAborted) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '这次太短啦，向日葵没来得及收集阳光（≥5 分钟才有产出哦）',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                        ),
                      ],
                      // 超额说明（玄参 2026-09-30）：额度用完被截断时讲清楚原因，
                      // 让孩子知道「不是向日葵没收，是今天的额度到顶了」。
                      if (capped) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE9B8).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  const Color(0xFFFFE9B8).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                '🌻 今天专注额度用完啦',
                                style: TextStyle(
                                  color: Color(0xFFFFE082),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '超出额度的部分就不再收集阳光了'
                                '${capped && rawS > net ? '（原本 ${_fmtSun(rawS)} ☀️，实到 ${_fmtSun(net)} ☀️）' : ''}。'
                                '今天已经很棒啦，明天再来吧！',
                                style: const TextStyle(
                                  color: Color(0xFFBDBDBD),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // 联动成长项结算（仅从「成长」进入专注才会有）。
                      ..._taskSettlementLines(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 随机系统夸奖卡（C49：原「家长留言区」占位框，夸夸台裁撤后改随机话术）
                _PraiseCard(phrase: _praisePhrase),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // 结算页经 go('/settle') 进入 = 路由栈底；退出必须 go('/')（B20）。
                      onPressed: () => context.go('/'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: const Text('回首页'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          },
                        ), // AnimatedBuilder
                      ), // IntrinsicHeight
                    ), // ConstrainedBox
                  ), // SingleChildScrollView
            ), // LayoutBuilder
          ), // SafeArea
        ), // DecoratedBox
      ), // Scaffold
    ); // PopScope
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 16)),
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFFFFE082) : Colors.white,
            fontSize: highlight ? 22 : 16,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 随机系统夸奖卡（C49 / 玄参 2026-10-10）：原「家长留言区（夸夸台接入后显示）」
/// 占位框改为随机夸奖话术——结算页是孩子的正反馈高光时刻，保留鼓励位；
/// 纯本地话术池（[kPraisePhrases]），无网络无依赖。句子由页面 State 抽定后传入，
/// 动画重建不换句。
class _PraiseCard extends StatelessWidget {
  final String phrase;

  const _PraiseCard({required this.phrase});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFFFE082), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phrase,
              style: const TextStyle(
                color: Color(0xFFFFF3D6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
