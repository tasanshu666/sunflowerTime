/// 结算页（T09）：光回罐动画 + 本次专注时长 + 产出阳光 + 当日累计 + 向日葵庆祝态。
///
/// 依据 PRD §4.1.2（结算动画是全场的视觉高光：那束出远门的光从屏外回来、落进阳光罐，
/// 账同步上涨；本次专注时长、产出阳光数、当日累计、向日葵醒着庆祝）。
///
/// 预留「家长转述表扬」占位区（M2 夸夸台接入，PRD §4.9）：M1 先留空位。
library settle_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
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

class SettlePage extends ConsumerStatefulWidget {
  /// 结算参数（由专注页经 go extra 传入；深链缺失时为 null）。
  final FocusSettlement? settlement;

  const SettlePage({super.key, this.settlement});

  @override
  ConsumerState<SettlePage> createState() => _SettlePageState();
}

class _SettlePageState extends ConsumerState<SettlePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
    // M2：net > 0 光回罐动画启动时播放结算奖励音（受 soundOn 保护，缺素材静默降级）。
    if ((widget.settlement?.net ?? 0) > 0) {
      ref.read(audioServiceProvider).playSfx(AudioCue.taskReward);
    }
    // T-B：结算后注入 sun_earned / valid_focus_day 埋点（settlement 非空时）。
    final FocusSettlement? settlement = widget.settlement;
    if (settlement != null) {
      unawaited(_trackSunEarned(settlement));
      unawaited(_trackValidFocusDay(settlement));
    }
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
          'capped': s.rawS > kSoftCapSeg1,
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

  @override
  Widget build(BuildContext context) {
    final settlement = widget.settlement;
    final double net = settlement?.net ?? 0;
    final double todayNet = settlement?.todayNet ?? 0;
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
        backgroundColor: const Color(0xFF1B1B2F),
        body: SafeArea(
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
                    // net > 0：庆祝态花 + 「光回罐」上涨动画 + 小字；
                    // net == 0（含 shortAborted / settlement 为 null）：静态呼吸花（celebrating=false），
                    // 不显示罐与光点（花与罐已拆分，不再被整体隐藏）。
                    child: net > 0
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '向日葵把光收进罐子里 ☀️',
                                style: TextStyle(
                                  color: Color(0xFFBDBDBD),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _LightBackToJar(progress: t),
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
                        value: '${(todayNet * t).round()} ☀️',
                      ),
                      if (shortAborted) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '这次太短啦，向日葵没来得及收集阳光（≥5 分钟才有产出哦）',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                        ),
                      ],
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
        ),
      ),
      ),
    );
  }
}

/// 「光回罐」动画：那束光从屏外飞回罐子，罐内水位随进度上涨。
class _LightBackToJar extends StatelessWidget {
  final double progress;

  const _LightBackToJar({required this.progress});

  @override
  Widget build(BuildContext context) {
    // 光点行进阶段（前 70%）：从右上屏外飞入罐口；此后停在罐内。
    final double travel = (progress / 0.7).clamp(0.0, 1.0);
    final double fill = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SunflowerCanvas(
            level: FeedbackLevel.lvl1,
            celebrating: true,
          ),
          // 光点：从右上 (dx=120, dy=-120) 飞向罐口 (0, 20)
          Positioned(
            left: 130 + (1 - travel) * 110,
            top: 130 + (1 - travel) * (-110) + 30,
            child: Opacity(
              opacity: travel >= 0.98 ? 0.0 : 1.0,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF59D),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x88FFF59D), blurRadius: 12)
                  ],
                ),
              ),
            ),
          ),
          // 阳光罐（简化：底部圆角罐 + 水位）
          Positioned(
            bottom: 6,
            child: _Jar(fill: fill),
          ),
        ],
      ),
    );
  }
}

class _Jar extends StatelessWidget {
  final double fill;

  const _Jar({required this.fill});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 82,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FractionallySizedBox(
          heightFactor: fill.clamp(0.0, 1.0),
          widthFactor: 1.0,
          alignment: Alignment.bottomCenter,
          child: Container(color: const Color(0xFFFFE082)),
        ),
      ),
    );
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
