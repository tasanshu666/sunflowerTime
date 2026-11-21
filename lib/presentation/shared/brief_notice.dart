/// 一次性**轻提示浮层**（淡入 → 保持约 1s → 淡出自清；不是 SnackBar）。
///
/// 🔴 为什么不用 `showQuotaNotice`：那条是 2.8s 常驻卡片配额提示（带锁图标 /
/// 可选 action）。本条用于「战斗态点战士但没能量」这种**极轻**反馈，玄参原话
/// 「轻轻的弹文字『请专注去获得能量吧』，1 秒后淡出消失」——故单独做一个更短、
/// 更小、带**真淡出**的浮层（沿用 F165 自绘 Overlay 纪律，绝不回退 SnackBar）。
///
/// 纪律同 `quota_notice.dart`：文案在调用方上下文取好传入（浮层 builder 在页级
/// `L10nScope` 之外）；独立 Timer 自清，不依赖当前路由；重复触发只留最新一条；
/// 裸测试宿主（无 Overlay）静默降级，绝不因附加反馈崩掉业务。
library brief_notice;

import 'dart:async';

import 'package:flutter/material.dart';

/// 当前在显示的唯一轻提示（重复触发先撤旧条，避免堆叠）。
OverlayEntry? _briefEntry;

/// 自清定时器（与路由无关）。
Timer? _briefTimer;

/// 淡入 / 淡出时长。
const Duration _kFadeMs = Duration(milliseconds: 180);

/// 弹出轻提示：[message] 已本地化；[hold] = 淡出前的保持时长（默认约 1s）。
void showBriefNotice(
  BuildContext context, {
  required String message,
  Duration hold = const Duration(milliseconds: 1000),
}) {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  hideBriefNotice();

  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext _) => _BriefNoticeLayer(
      message: message,
      hold: hold,
      onDone: hideBriefNotice,
    ),
  );
  _briefEntry = entry;
  overlay.insert(entry);
  // 兜底清理：即使淡出动画因宿主销毁没走到回调，也必须撤掉浮层（防 F165 常驻）。
  _briefTimer = Timer(
    hold + _kFadeMs + const Duration(milliseconds: 400),
    hideBriefNotice,
  );
}

/// 移除当前轻提示（幂等；页面 dispose / 跳转前可主动调用）。
void hideBriefNotice() {
  _briefTimer?.cancel();
  _briefTimer = null;
  final OverlayEntry? entry = _briefEntry;
  _briefEntry = null;
  if (entry == null) return;
  entry.remove();
  entry.dispose();
}

/// 轻提示本体：淡入 → 保持 → 淡出 → [onDone] 自清。
class _BriefNoticeLayer extends StatefulWidget {
  const _BriefNoticeLayer({
    required this.message,
    required this.hold,
    required this.onDone,
  });

  final String message;
  final Duration hold;
  final VoidCallback onDone;

  @override
  State<_BriefNoticeLayer> createState() => _BriefNoticeLayerState();
}

class _BriefNoticeLayerState extends State<_BriefNoticeLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _kFadeMs,
  );
  Timer? _holdTimer;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ctrl.forward());
    _holdTimer = Timer(widget.hold, _beginFadeOut);
  }

  void _beginFadeOut() {
    if (_fadingOut) return;
    _fadingOut = true;
    unawaited(_ctrl.reverse().then((_) {
      if (mounted) widget.onDone();
    }));
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    // Align 只在自己的矩形内命中 → 浮层外点击照常落到页面，不挡操作。
    return Align(
      alignment: const Alignment(0, 0.30),
      child: FadeTransition(
        opacity: _ctrl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: s.surface.withValues(alpha: 0.96),
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: s.onSurface,
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
