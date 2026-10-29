/// 配额达上限「轻提示浮层」（App 风格卡片，**不是 SnackBar**）。
///
/// 🔴 为什么弃用 SnackBar（2026-10-29 玄参实测缺陷 F165「黑条常驻」）：
///
///  ① **带 action 的 SnackBar 在「无障碍导航」开启时永不自动关闭**。
///     Flutter `ScaffoldMessengerState.build` 的计时逻辑里有：
///     `if (snackBar.action != null && mediaQuery.accessibleNavigation) return;`
///     —— 本提示恰好带「Unlock All」action，一旦设备开了旁白/朗读屏幕之类，
///     `duration: 1000ms` 直接失效，提示条**永久驻留**，只能点 action 或杀 App。
///  ② **计时器还额外依赖「当前路由命中」**：同一处 `build` 里
///     `if (route == null || route.isCurrent)` 才建 Timer —— 用户点了
///     「解锁全部功能」跳会员页、或切 tab 之后，定时器干脆不启动。
///  ③ **`ScaffoldMessenger` 挂在 MaterialApp 层** → 提示**跨路由存活**
///     （玄参实测「回到孩子端那条黑的还在」「进会员页也不消失」）。
///  ④ M3 亮色主题的 SnackBar 用 `inverseSurface`（深色底）→ 与暖米白 App 风格
///     冲突（玄参「这种黑色的弹窗也太丑了，不符合我这个 APP 的风格」）。
///
/// 本组件改用**居中偏下的卡片浮层**（与花园页 `_RisingHint` 同一套视觉语言）：
///  · 颜色全部由 `ColorScheme` 派生 → 明暗主题、两套皮肤自动适配，无硬编码色；
///  · **独立 `Timer` 自清**（不依赖路由状态）→ 到时必消失，另有 300ms 兜底；
///  · 点「解锁全部功能」→ 先移除浮层再跳转（不留残影）；
///  · 重复触发**只保留最新一条**（不堆叠，玄参连点也不会糊满屏）；
///  · 浮层不拦截浮层外的点击（`Align` 只在自己的矩形内命中）→ 不挡用户操作。
///
/// 纪律：文案在**调用方上下文**取好再传入（弹窗纪律：浮层 builder 在页级
/// `L10nScope` 之外，不得在里面直调 `AppLocalizations.of`）。
library quota_notice;

import 'dart:async';

import 'package:flutter/material.dart';

/// 当前在显示的唯一浮层（重复触发先清旧的，避免堆叠）。
OverlayEntry? _entry;

/// 自清定时器（**与路由无关**，这是修复「常驻」的关键）。
Timer? _timer;

/// 从 [hold] 起算的兜底清理时长（淡出动画走完之后再清一次，幂等）。
const int _kFallbackSweepMs = 400;

/// 弹出配额达上限轻提示。
///
/// [message] 已经本地化的正文；[actionLabel] 为空 → 不渲染按钮（孩子端场景）；
/// [onAction] 在浮层移除**之后**执行（跳转不会留下残影）。
void showQuotaNotice(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration hold = const Duration(milliseconds: 2800),
}) {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  // 裸测试宿主（无 Overlay）静默降级：提示是**附加**反馈，不得因为它崩掉业务。
  if (overlay == null) return;
  hideQuotaNotice();

  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext _) => _QuotaNoticeLayer(
      message: message,
      actionLabel: actionLabel,
      onAction: () {
        // 先撤浮层再跳：跳页后浮层若还在，会跨页残留（正是 F165 的老毛病）。
        hideQuotaNotice();
        onAction?.call();
      },
    ),
  );
  _entry = entry;
  overlay.insert(entry);
  _timer = Timer(
    hold + const Duration(milliseconds: _kFallbackSweepMs),
    hideQuotaNotice,
  );
}

/// 移除当前浮层（幂等；页面 dispose / 跳转前可主动调用）。
void hideQuotaNotice() {
  _timer?.cancel();
  _timer = null;
  final OverlayEntry? entry = _entry;
  _entry = null;
  if (entry == null) return;
  entry.remove();
  entry.dispose();
}

/// 浮层本体：淡入 + 轻微上浮，居中偏下（避让底部导航）。
class _QuotaNoticeLayer extends StatefulWidget {
  const _QuotaNoticeLayer({
    required this.message,
    required this.onAction,
    this.actionLabel,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  State<_QuotaNoticeLayer> createState() => _QuotaNoticeLayerState();
}

class _QuotaNoticeLayerState extends State<_QuotaNoticeLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.14),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    // `Align` 只在自己的矩形内命中测试 → 浮层外的点击照常落到页面，不挡操作。
    return Align(
      alignment: const Alignment(0, 0.62),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: s.surface,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    13,
                    widget.actionLabel == null ? 16 : 8,
                    13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    // 描边保证在暖米白/浅青底上也能看出卡片边界。
                    border: Border.all(
                      color: s.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: s.primary,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: s.onSurface,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null)
                        TextButton(
                          onPressed: widget.onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: s.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
