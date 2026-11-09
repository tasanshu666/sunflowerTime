/// 今日页「向日葵守卫」胶囊（第三批，PRD §8.1）。
///
/// ## 插在哪
/// `ChildTodayPage` 的 `ListView` **第 0 项**（三张 `_StatCard` 之前），
/// 见 `child_today_page.dart` 的 `_buildLayout`：
/// ```dart
/// children: <Widget>[
///   if (guard.isVisible) ...<Widget>[GuardPill(...), const SizedBox(height: kGuardPillGap)],
///   _StatCard(...  // 原有第一张卡
/// ```
/// `GuardPillMode.absent` 时**整个 widget 都不进树**（调用方负责不插），
/// 所以这里不存在「空占位」分支 —— 零占位是调用方的契约，不是本 widget 的分支。
///
/// ## 🔴 布局必须抗溢出（F127 教训，320 屏可用宽度只有 288pt）
/// ```
/// [emoji 24] [gap 8] [Expanded(Text maxLines:1, ellipsis)] [gap 8] [尾标]
/// ```
/// · 文案**必须**是 `Expanded` 的子项 —— 早期版本把两个 `Text` 直接放进 `Row`
///   （不可压缩子项），320×568 + `textScaler: 1.3` 下父级装不下就整体溢出
///   （`RenderFlex overflowed`，见 `_StatCard` 的 F127 注释）。这里提前按同一
///   结构收敛，并用 `fitted` 尾标（可空）而不是「文字 + 单位」两个不可压缩块。
/// · 🔴 **绝不**用 `FittedBox` / 压 `fontSize`：大字号是用户的无障碍设置，
///   结构性收敛（`Expanded` + 省略号）才是正解。
///
/// ## 高度
/// `minHeight = [kGuardPillHeight]`（44 = 触控下限），**不写死** `height`
/// —— 常态单行时实测就是 44pt（Padding 6×2 + 行高 ≈ 20 或 emoji 24 → 36 < 44），
/// 而 `textScaler: 2.0` 时胶囊会跟着长高，不会把字裁掉。
library guard_pill;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_thief.dart' show GuardThiefKindX;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';

/// 守卫胶囊（纯展示 + 一个点击回调，**不碰任何服务 / 账本**）。
class GuardPill extends StatelessWidget {
  /// 度量护栏用的固定 Key（测试据此断言「存在 / 不存在 / 高度 44」）。
  static const Key pillKey = Key('guardPill');

  /// 尾标 Key（`−5 ☀` / `✓`）。
  static const Key trailingKey = Key('guardPillTrailing');

  /// 当前守卫快照（由页面 `ref.watch(guardTodayProvider)` 传入）。
  final GuardTodayView view;

  /// 点击回调；为 null 或 [GuardTodayView.isActionable] 为 false 时不可点。
  final VoidCallback? onTap;

  const GuardPill({super.key, required this.view, this.onTap});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final bool enabled = view.isActionable && onTap != null;
    final _GuardPillTone tone = _toneOf(view.mode);
    final String label = _labelOf(view, t);
    final String? trailing = _trailingOf(view);

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        // 整条胶囊都是命中区（含内边距），避免「点在胶囊里却没反应」。
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          key: pillKey,
          // 不写死 height：见文件头「高度」。常态实测 = 44。
          constraints: const BoxConstraints(minHeight: kGuardPillHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(kGuardPillRadius),
            border: Border.all(color: tone.border),
          ),
          child: Row(
            children: <Widget>[
              // emoji 固定 24 宽的盒子：三种贼的 emoji 宽度不同，不夹住会让
              // 文案起点在「今天换了个贼」时左右跳（视觉回归）。
              SizedBox(
                width: 24,
                child: Center(
                  child: Text(
                    _emojiOf(view),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tone.foreground,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  trailing,
                  key: trailingKey,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tone.foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 五种上屏态各自的文案（`absent` 不会进树，返回空串兜底）。
  ///
  /// 🔴 「有能量」用的是 [AppLocalizations.guard_pill_pending_free]
  /// （……（免费））：免费/付费是**孩子最关心**的信息，必须让他在点之前就知道
  /// 「这一下不花钱」。
  static String _labelOf(GuardTodayView view, AppLocalizations t) {
    switch (view.mode) {
      case GuardPillMode.absent:
        return '';
      case GuardPillMode.pendingFree:
        return t.guard_pill_pending_free;
      case GuardPillMode.pendingPaid:
        return t.guard_pill_pending;
      case GuardPillMode.freeRide:
        return t.guard_pill_free_ride;
      case GuardPillMode.fighting:
        return t.guard_pill_fighting;
      case GuardPillMode.claimed:
        return t.guard_pill_claimed;
    }
  }

  /// 左侧占位图形：贼在的时候用贼的 emoji（`GuardThiefSpec.emoji`，符号非文案），
  /// 其余（守住 / 阿葵顶班）用守卫自己 🌻。
  static String _emojiOf(GuardTodayView view) {
    switch (view.mode) {
      case GuardPillMode.absent:
        return '';
      case GuardPillMode.pendingFree:
      case GuardPillMode.pendingPaid:
      case GuardPillMode.fighting:
        return view.thief?.emoji ?? '🌻';
      case GuardPillMode.freeRide:
      case GuardPillMode.claimed:
        return '🌻';
    }
  }

  /// 右侧尾标（可空）：只有「要花钱」和「已守住」两种需要额外符号。
  static String? _trailingOf(GuardTodayView view) {
    switch (view.mode) {
      case GuardPillMode.pendingPaid:
        // 数字来自常量，不写死 5（PRD 改价时只改 prd_params）。
        return '−$kGuardPayCost ☀';
      case GuardPillMode.claimed:
        return '✓';
      case GuardPillMode.pendingFree:
      case GuardPillMode.freeRide:
      case GuardPillMode.fighting:
      case GuardPillMode.absent:
        return null;
    }
  }

  static _GuardPillTone _toneOf(GuardPillMode mode) {
    switch (mode) {
      case GuardPillMode.pendingFree:
      case GuardPillMode.pendingPaid:
      case GuardPillMode.fighting:
        return const _GuardPillTone(
          background: Color(0xFFFFF6E0),
          border: Color(0x66E8A600),
          foreground: Color(0xFF8A5A00),
        );
      case GuardPillMode.claimed:
        return const _GuardPillTone(
          background: Color(0xFFF1F7EE),
          border: Color(0x5573A45C),
          foreground: Color(0xFF4C6B3C),
        );
      case GuardPillMode.freeRide:
      case GuardPillMode.absent:
        return const _GuardPillTone(
          background: Color(0xFFF3F0EA),
          border: Color(0x338A7A66),
          foreground: Color(0xFF8A7A66),
        );
    }
  }
}

/// 胶囊配色（三档语气：要动手 / 已守住 / 不用管）。
@immutable
class _GuardPillTone {
  final Color background;
  final Color border;
  final Color foreground;

  const _GuardPillTone({
    required this.background,
    required this.border,
    required this.foreground,
  });
}
