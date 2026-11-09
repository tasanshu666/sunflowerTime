/// 「守卫赶小偷」战斗界面（第三批，占位 emoji demo，PRD §3.9 / §8.2）。
///
/// ## 为什么用 `showGeneralDialog` 而不是新路由
/// 新路由（`context.push`）会进 `GoRouter` 的路由栈：孩子的返回键 / 侧滑手势可以
/// **只退出战斗、留在今日页**，而 UI 上「已进战斗」的状态还在 —— 路由栈与
/// 状态机不同步。`showGeneralDialog` 是**独立的 overlay route**，返回键只会关掉
/// 它（= 跳过战斗），语义单一。同理结算卡也走 dialog，不开新路由。
///
/// ## 🔴 奖励与观看时长零相关（PRD §7.3 第一条红线）
/// 落骰（来哪只贼 / 偷多少 / 掉什么 / 保底几 ☀）在 `GuardService.resolve()` 时
/// **已经定死并落盘**；本文件只是**回放**。所以：
///  · 「跳过」与「看完」拿到逐位相同的结果；
///  · 本文件**不写账本、不发奖励、不调 `claim()`** —— 发放推迟到结算卡的「收下」
///    （见 `guard_result_card.dart`）。
///
/// ## 文案从页面传进来（i18n 铁律）
/// `showGeneralDialog` 的 builder 上下文挂在根 Navigator 上，**不在页级
/// `L10nScope` 之下** → 浮层内部严禁直调 `AppLocalizations`（见
/// `core/i18n/l10n_scope.dart` 铁律）。故 [AppLocalizations] 由调用方在页级
/// scope 内解析好后经构造参数传入。
///
/// ## 时长
/// 总时长 [kGuardBattleMs] = 10000ms（玄参要求 ~10 秒，不是 3 秒）；
/// 「跳过」按钮延迟 [kGuardBattleSkipDelayMs] = 600ms 出现（防「一进来就点掉」）。
library guard_battle_overlay;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 弹出战斗界面并等待它结束。
///
/// 返回 `true` = 孩子点了「跳过」；`false` = 动画播完（或返回键关掉）。
/// 返回值**只用于埋点**（`kGuardTrackSkip`），不影响任何奖励口径。
Future<bool> showGuardBattle(
  BuildContext context, {
  required GuardThiefKind thief,
  required AppLocalizations l10n,
}) async {
  final bool? skipped = await showGeneralDialog<bool>(
    context: context,
    // 孩子不能点遮罩跳过（遮罩点击 = 隐式跳过，会绕开「跳过」按钮的埋点；
    // 返回键仍然可用，那条路径走 `false`）。
    barrierDismissible: false,
    barrierLabel: l10n.guard_pill_fighting,
    barrierColor: const Color(0xB31B1206),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) =>
        GuardBattleOverlay(thief: thief, l10n: l10n),
  );
  return skipped ?? false;
}

/// 战斗动画本体（10 秒，可跳过）。
class GuardBattleOverlay extends StatefulWidget {
  /// 浮层根 Key（测试用于断言「战斗界面已上屏」）。
  static const Key overlayKey = Key('guardBattleOverlay');

  /// 「跳过」按钮 Key（测试用于断言「600ms 前不存在、之后出现」）。
  static const Key skipButtonKey = Key('guardBattleSkip');

  /// 小偷 emoji Key（度量「从右往左」用）。
  static const Key thiefKey = Key('guardBattleThief');

  /// 今天来的贼（emoji 取自 [GuardThiefKind.emoji]，符号非文案）。
  final GuardThiefKind thief;

  /// 页级 scope 内解析好的文案（见文件头「文案从页面传进来」）。
  final AppLocalizations l10n;

  const GuardBattleOverlay({
    super.key,
    required this.thief,
    required this.l10n,
  });

  @override
  State<GuardBattleOverlay> createState() => _GuardBattleOverlayState();
}

class _GuardBattleOverlayState extends State<GuardBattleOverlay>
    with SingleTickerProviderStateMixin {
  /// 战斗进度（0 → 1，线性，[kGuardBattleMs] 走完）。
  late final AnimationController _battle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kGuardBattleMs),
  );

  /// 收尾闸门：跳过与「播完」可能同帧先后到，只允许 pop 一次。
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _battle.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) _finish(skipped: false);
    });
    _battle.forward();
  }

  @override
  void dispose() {
    _battle.dispose();
    super.dispose();
  }

  /// 结束战斗：`true` = 跳过。
  ///
  /// 幂等：`_closed` 之后一律忽略（跳过按钮与 `completed` 回调竞争时的护栏）。
  void _finish({required bool skipped}) {
    if (_closed || !mounted) return;
    _closed = true;
    _battle.stop();
    Navigator.of(context).pop(skipped);
  }

  /// 归一化进度（线性；缓动只作用于小偷位移，不作用于进度条 —— 进度条要「诚实」）。
  double get _progress {
    final double v = _battle.value;
    if (!v.isFinite) return 0;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  @override
  Widget build(BuildContext context) {
    // 文案只由 textScaler 放大；图形尺寸固定（浮层不跟平板 uiScale 放大，
    // 否则 iPad 上一个 emoji 会占掉小半屏）。
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedBuilder(
            animation: _battle,
            builder: (BuildContext context, Widget? _) {
              final double t = _progress;
              final bool skipReady =
                  _battle.value * kGuardBattleMs >= kGuardBattleSkipDelayMs;
              return Container(
                key: GuardBattleOverlay.overlayKey,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                constraints: const BoxConstraints(maxWidth: 340),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF1),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 战况文案：复用胶囊的「守卫正在赶走它…」，全 App 一套说法。
                    Text(
                      widget.l10n.guard_pill_fighting,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A5A00),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 进度 / 血条：中间一条，小偷越近走得越满。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: t,
                        minHeight: 8,
                        backgroundColor: const Color(0x1FE8A600),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFE8A600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 对战场：守卫在左，小偷**从右往左**逼近。
                    SizedBox(
                      height: 84,
                      width: double.infinity,
                      child: LayoutBuilder(
                        builder: (BuildContext _, BoxConstraints c) {
                          const double slot = 56;
                          final double w =
                              c.maxWidth.isFinite ? c.maxWidth : 260;
                          // 位移区间 = 右端 → 守卫右侧；宽度不够时退化到 8pt（绝不反向往右）。
                          final double travel = math.max(8, w - slot * 2);
                          final double eased =
                              Curves.easeInOut.transform(t.clamp(0.0, 1.0));
                          final double left = (w - slot) - travel * eased;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              // 守卫 🌻：固定在最左。
                              const Positioned(
                                left: 0,
                                bottom: 0,
                                child: Text('🌻',
                                    style: TextStyle(fontSize: 40)),
                              ),
                              Positioned(
                                left: left < slot ? slot : left,
                                bottom: 2,
                                child: Text(
                                  widget.thief.emoji,
                                  key: GuardBattleOverlay.thiefKey,
                                  style: const TextStyle(fontSize: 34),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 跳过：600ms 前**不插进树**（不是透明化 —— 透明化会被测试与
                    // 无障碍读屏当成「可以点」，也会让孩子一进来就误触）。
                    if (skipReady)
                      TextButton(
                        key: GuardBattleOverlay.skipButtonKey,
                        onPressed: () => _finish(skipped: true),
                        child: Text(widget.l10n.guard_battle_skip),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
