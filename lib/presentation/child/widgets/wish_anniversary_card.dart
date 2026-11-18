/// 「历史上的今天」回顾卡（A-T04 / A26.10 / A36.1~A36.3，v0.6.0 定稿批补）。
///
/// ## 落点（A26.10.5）
/// 许愿树页**最上方**、树上段之上，**页内卡**（不是模态）；打开即见，不打断许愿。
/// 每天最多 1 次（频次由页面读/写 `SettingsStore`，本卡只负责展示与回调）。
///
/// ## 四态判据（A26.10.5 ③ · K26 恰 4 分支穷举，无 else 兜底）
/// [anniversaryStateOf] 按 `status` + `releasedAt` 判：**穷举 4 态**
/// `fulfilled / onTree / boxed / changed`，禁「没做到 / 失败 / 快点」等否定词（T-V250-05）。
/// 文案全部参数化年份（[anniversaryYearLabel]：去年 / 两年前 / N 年前，T-V250-09）。
///
/// ## v0.7.0 三增强
/// - ① A36.1：本卡即"去年今天许的"回顾，日期信息区相邻，无频次另计；
/// - ② A36.2：🔴 [extraCount] > 0 时「还有 N 条」可**就地展开**成小列表
///   （[extraWishes] 按 `createdAt` 倒序，名单行只读不可点，带 ▶/▼）；
/// - ③ A36.3：「看看它」→ [onLook] 由页面切段 + 滚动 + 高亮；点后本卡收起。
///
/// 纯展示 widget：不读 provider、不写任何列（A26.10.1 ③ 只读）；文案经 [t] 传入。
library wish_anniversary_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 回顾卡四态（K26：判据函数恰 4 个可达分支）。
enum WishAnniversaryState {
  /// `status == fulfilled` —— 后来它实现了。
  fulfilled,

  /// `releasedAt == null && status != fulfilled` —— 它还在树上等你。
  onTree,

  /// `releasedAt != null` —— 它被收进了愿望收藏箱。
  boxed,

  /// `status == abandoned` —— 你后来换成了别的愿望。
  changed,
}

/// 四态判据（唯一实现，K26 恰 4 分支、无 else 兜底）。
///
/// 判据顺序即规格顺序，`status == abandoned` 单列（换愿望），其余按
/// `fulfilled → boxed → onTree` 穷举。导出为顶层纯函数便于测试直接断言。
WishAnniversaryState anniversaryStateOf(Wish wish) {
  if (wish.status == WishStatus.abandoned) return WishAnniversaryState.changed;
  if (wish.status == WishStatus.fulfilled) return WishAnniversaryState.fulfilled;
  if (wish.releasedAt != null) return WishAnniversaryState.boxed;
  return WishAnniversaryState.onTree;
}

/// 四态 → ARB 文案（switch 穷举，无 CJK 硬编码）。
String anniversaryStateTextOf(WishAnniversaryState state, AppLocalizations t) =>
    switch (state) {
      WishAnniversaryState.fulfilled => t.wishAnnivFulfilled,
      WishAnniversaryState.onTree => t.wishAnnivOnTree,
      WishAnniversaryState.boxed => t.wishAnnivBoxed,
      WishAnniversaryState.changed => t.wishAnnivChanged,
    };

/// 年份文案（T-V250-09：参数化，不硬编码数字）。
///
/// [years] = 今年 − 许愿年（≥1）；1 → 「去年今天」，2 → 「两年前的今天」，
/// N ≥ 3 → 「N 年前的今天」，分别走不同 ARB key / 占位符。
String anniversaryYearLabel(int years, AppLocalizations t) {
  if (years <= 1) return t.wishAnnivLastYear;
  if (years == 2) return t.wishAnnivYearsAgo(years);
  return t.wishAnnivYearsAgo(years);
}

/// 「历史上的今天」回顾卡。
class WishAnniversaryCard extends StatefulWidget {
  const WishAnniversaryCard({
    super.key,
    required this.wish,
    required this.years,
    required this.t,
    required this.onLook,
    required this.onDismiss,
    this.extraWishes = const <Wish>[],
    this.extraCount = 0,
  });

  /// 主卡（命中集合中 `createdAt` 最大的一条）。
  final Wish wish;

  /// 年份差 = 今年 − 许愿年（≥1，由页面算好）。
  final int years;

  final AppLocalizations t;

  /// 「看看它」：页面切段 + 滚动 + 高亮，随后收起本卡（A36.3）。
  final VoidCallback onLook;

  /// 「收起」：页面写今日日期到 `SettingsStore`（当天不再弹）。
  final VoidCallback onDismiss;

  /// 其余命中（按 `createdAt` 倒序，A36.2）。
  final List<Wish> extraWishes;

  /// 折叠计数 = 命中总数 − 1（`wishAnnivMore` 占位参数）。
  final int extraCount;

  @override
  State<WishAnniversaryCard> createState() => _WishAnniversaryCardState();
}

class _WishAnniversaryCardState extends State<WishAnniversaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final WishAnniversaryState state = anniversaryStateOf(widget.wish);
    return Container(
      key: const Key('wish_anniversary_card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFF6DC), Color(0xFFFFE9B8)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x4DE8A600)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('📅', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                widget.t.wishAnnivTitle,
                key: const Key('wish_anniversary_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B4E12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            anniversaryYearLabel(widget.years, widget.t),
            key: const Key('wish_anniversary_year'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8D6E00),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.wish.text,
            key: const Key('wish_anniversary_text'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Color(0xFF4E3B12)),
          ),
          const SizedBox(height: 6),
          Text(
            anniversaryStateTextOf(state, widget.t),
            key: Key('wish_anniversary_state_${state.name}'),
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B4E12)),
          ),
          // ② A36.2：折叠小列表（就地展开，带 ▶/▼，行只读不可点）。
          if (widget.extraCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            _buildFoldToggle(),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 6),
              for (final Wish extra in widget.extraWishes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_shortName(extra.text)} · ${anniversaryYearLabel(widget.years, widget.t)} · '
                    '${anniversaryStateTextOf(anniversaryStateOf(extra), widget.t)}',
                    key: Key('wish_anniversary_extra_${extra.id}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B4E12),
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('wish_anniversary_look'),
                  onPressed: widget.onLook,
                  child: Text(widget.t.wishAnnivLook),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  key: const Key('wish_anniversary_dismiss'),
                  onPressed: widget.onDismiss,
                  child: Text(widget.t.wishAnnivDismiss),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 折叠行开关（▶/▼ + 「还有 N 条」）。
  Widget _buildFoldToggle() => InkWell(
        key: const Key('wish_anniversary_more'),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Row(
          children: <Widget>[
            Text(
              _expanded ? '▼' : '▶',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8D6E00)),
            ),
            const SizedBox(width: 6),
            Text(
              widget.t.wishAnnivMore(widget.extraCount),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8D6E00),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  /// 愿望短名 = 前 8 码点 + 省略号（emoji 不被截半）。
  String _shortName(String text) {
    final int count = text.runes.length;
    if (count <= 8) return text;
    return '${String.fromCharCodes(text.runes.take(8))}…';
  }
}
