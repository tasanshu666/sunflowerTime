/// 结算页（T09）：光回罐动画 + 本次专注时长 + 产出阳光 + 当日累计 + 向日葵庆祝态。
///
/// 依据 PRD §4.1.2（结算动画是全场的视觉高光：那束出远门的光从屏外回来、落进阳光罐，
/// 账同步上涨；本次专注时长、产出阳光数、当日累计、向日葵醒着庆祝）。
///
/// 预留「家长转述表扬」占位区（M2 夸夸台接入，PRD §4.9）：M1 先留空位。
library settle_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
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

  const SettleArgs({
    this.settlement,
    this.taskOutcome,
    this.taskName,
    this.taskSettleSkipped = false,
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

  @override
  void initState() {
    super.initState();
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
    if ((widget.args?.settlement?.net ?? 0) > 0) {
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
                    // 音效仍只在 net>0 时播（initState 控制），短专注静音。
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
                        value: formatFocusMinutes(actualMin),
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '收到阳光',
                        // 数字滚动上涨（按动画进度）。
                        value: '+${(net * t).round()}',
                        highlight: true,
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '今日累计',
                        value: '${(todayEarned * t).round()} ☀️',
                      ),
                      const SizedBox(height: 8),
                      _StatRow(
                        label: '拥有阳光',
                        // 结算后余额（FocusSettlement.balanceAfter）。
                        value: '${(settlement?.balanceAfter ?? 0).round()} ☀️',
                      ),
                      if (shortAborted) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '这次太短啦，向日葵没来得及收集阳光（≥5 分钟才有产出哦）',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                        ),
                      ],
                      // 联动成长项结算（仅从「成长」进入专注才会有）。
                      ..._taskSettlementLines(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 预留：家长转述表扬占位区（M2 夸夸台接入，PRD §4.9）
                _PraisePlaceholder(),
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

/// 家长转述表扬占位区（M2 夸夸台接入，PRD §4.9）。
class _PraisePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: const Row(
        children: [
          Icon(Icons.forum_outlined, color: Color(0xFF757575), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '家长留言区（夸夸台接入后显示）',
              style: TextStyle(color: Color(0xFF757575), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
