/// App 总时长到顶的**儿童风提示卡**（玄参 2026-09-29 美化重做）。
///
/// 设计语言（借鉴儿童 App 通用做法：大圆角 + 吉祥物大表情 + 多色柔和模块 +
/// 大号可点按钮，信息三行以内）：
///  · 主调换**天空蓝**（告别满屏绿），配暖黄向日葵吉祥物 —— 蓝黄互补不冲突；
///  · 关键信息拆成**两枚彩色小模块**：琥珀色「今日上限」/ 绿色「去专注」；
///  · 主按钮橙黄渐变大按钮「去今日开始专注」（点了直接切到今日 tab），
///    次按钮「知道啦」纯文字（既有测试依赖该文案，保留）。
library app_cap_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 到顶提示卡。`pop(AppCapDialog.goFocus)` 表示用户点了「去今日开始专注」。
class AppCapDialog extends StatelessWidget {
  /// 日上限到顶（默认变体，文案与既有测试兼容）。
  const AppCapDialog({super.key, required this.capMinutes})
      : _sessionLock = false,
        _lockMinutes = null;

  /// F99（玄参 2026-10-08）：**单次使用到点**变体——「连续玩了 10 分钟 →
  /// 休息 10 分钟再来」，与日上限到顶区分开。
  const AppCapDialog.sessionLock({super.key})
      : capMinutes = kSingleUseLockMinutes,
        _sessionLock = true,
        _lockMinutes = kSingleUseLockMinutes;

  /// 主按钮返回值：引导切到「今日」tab。
  static const String goFocus = 'go_focus';

  /// 当日上限（分钟），展示在琥珀色模块里（日上限变体用）。
  final int capMinutes;

  final bool _sessionLock;
  final int? _lockMinutes;

  @override
  Widget build(BuildContext context) {
    // i18n（B1）：本卡即弹窗内容（builder 上下文在页级 scope 之外）→ 自带
    // L10nScope，页内文案经内部上下文取用（裸测试宿主也不崩）。
    return L10nScope(
      child: Builder(
        builder: (BuildContext ctx) {
          final AppLocalizations l10n = AppLocalizations.of(ctx);
          return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x2E64B5F6),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildHeader(l10n),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              child: _buildBody(ctx, l10n),
            ),
          ],
        ),
      ),
    );
        },
      ),
    );
  }

  /// 天空蓝渐变头部：向日葵吉祥物 + 标题。
  Widget _buildHeader(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFB3D9FF), Color(0xFFE3F2FD)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(child: Text('🌻', style: TextStyle(fontSize: 40))),
          ),
          const SizedBox(height: 12),
          Text(
            _sessionLock ? l10n.child_cap_single_title : l10n.child_cap_daily_title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1D4E89),
            ),
          ),
        ],
      ),
    );
  }

  /// 正文：一句话 + 两枚彩色信息模块 + 主/次按钮。
  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: <Widget>[
        Text(
          _sessionLock
              ? l10n.child_cap_single_body(_lockMinutes ?? 0)
              : l10n.child_cap_daily_body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFF5B6B7A),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _InfoChip(
              emoji: '⏰',
              label: _sessionLock ? l10n.child_cap_chip_rest : l10n.child_cap_chip_daily,
              value: _sessionLock
                  ? l10n.child_cap_unlock_in(_lockMinutes ?? 0)
                  : l10n.child_cap_minutes(capMinutes),
              bg: const Color(0xFFFFF3D6),
              fg: const Color(0xFFB25E00),
            ),
            _InfoChip(
              emoji: '🎯',
              label: l10n.child_cap_chip_go_today,
              value: l10n.child_cap_chip_earn,
              bg: const Color(0xFFE3F3E4),
              fg: const Color(0xFF2E7D32),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GoFocusButton(
          label: l10n.child_cap_btn_go_focus,
          onTap: () => Navigator.of(context).pop(goFocus),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A97A5)),
          child: Text(l10n.child_cap_ok, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}

/// 彩色信息小模块（emoji 圆片 + 两行文字）。
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.emoji,
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
  });

  final String emoji;
  final String label;
  final String value;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: fg.withValues(alpha: 0.75))),
              Text(value,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主按钮：橙黄渐变大按钮（白字，圆角 18，高度 50）。
class _GoFocusButton extends StatelessWidget {
  const _GoFocusButton({required this.label, required this.onTap});

  /// 按钮文案（i18n B1：由调用方经 l10n 解析后传入）。
  final String label;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFFFC155), Color(0xFFFF9D42)],
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x38FF9D42),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
