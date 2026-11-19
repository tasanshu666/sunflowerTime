/// 家长端「贴标签 + 温柔回复」动作弹层（A21.4 / A24 / A-T05 组3）。
///
/// 对外三动作入口（PRD W20）：设定目标 + 布置任务 / 直接实现 / 贴标签 + 温柔回复。
/// 选中第三项时展示：
///  · 标签单选（6 选 1，可跳过）；
///  · 预设回复下拉（按所选标签过滤并重排，推荐词首位）—— 真源
///    [wishPresetsForTag]；
///  · 始终可见的回信输入框（预填所选预设词，可改）；
///  · 时机下拉（仅 `onOccasion` 预设时出现，5 选 1，不可自由输入）。
///
/// ## v0.3.0 新增（R3-P0-10②③ / D4）
/// 选中「无法实现」（[WishTag.notPossible]）时，回信框**预填**安慰话
/// （复用既有键 `shared_wish_reply_hard_but_love`，零新增键）：
///  · **可编辑、可清空**（预填只是初值，不是锁定）；
///  · **不自动写库** —— 直到家长点「发送回复」才经 `onTagReply` 上抛；
///  · 只在「回信框为空」时预填，不覆盖家长已写的内容。
///
/// 🔴 `parent_reply` 是唯一回信通道；不落 `reply_source`（PRD W21 无此列）。
/// 写操作经回调上抛（页面接领域调用），本 widget 自含 [L10nScope]，纯展示可测。
library parent_wish_action_sheet;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/i18n/wish_l10n.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 贴标签表单的提交结果（纯值对象）。
class WishTagReplyResult {
  const WishTagReplyResult({
    this.tag,
    this.reply,
    this.occasion,
  });

  final WishTag? tag;
  final String? reply;
  final WishOccasion? occasion;
}

/// 「三动作 + 标签/回复」弹层。
class ParentWishActionSheet extends StatefulWidget {
  const ParentWishActionSheet({
    super.key,
    required this.wish,
    this.initialTag,
    this.initialReply,
    required this.onSetup,
    required this.onFulfill,
    required this.onTagReply,
  });

  final Wish wish;
  final WishTag? initialTag;
  final String? initialReply;

  final VoidCallback onSetup;
  final VoidCallback onFulfill;
  final void Function(WishTagReplyResult result) onTagReply;

  @override
  State<ParentWishActionSheet> createState() => _ParentWishActionSheetState();
}

class _ParentWishActionSheetState extends State<ParentWishActionSheet> {
  WishTag? _tag;
  WishReplyPreset? _preset;
  WishOccasion _occasion = WishOccasion.birthday;
  late TextEditingController _replyCtrl;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    _replyCtrl = TextEditingController(text: widget.initialReply ?? '');
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  /// 选标签后：预设词按标签过滤重排（推荐词首位），默认选中第一个（通用词
  /// `weSawIt` 恒在，保证非空）。若当前 preset 已不在新集合则重置为首位。
  List<WishReplyPreset> get _presets => wishPresetsForTag(_tag);

  void _selectTag(WishTag? tag, AppLocalizations t) {
    setState(() {
      _tag = tag;
      final List<WishReplyPreset> next = wishPresetsForTag(tag);
      if (_preset == null || !next.contains(_preset)) {
        _preset = next.first;
      }
      // v0.3.0（R3-P0-10② / D4）：「无法实现」⇒ 预填安慰话（既有 ARB 键）。
      // 仅当回信框为空时预填 —— 绝不覆盖家长已经写下的内容；预填后仍可清空。
      if (tag == WishTag.notPossible && _replyCtrl.text.trim().isEmpty) {
        final String comfort = t.shared_wish_reply_hard_but_love;
        _replyCtrl.text = comfort;
        _replyCtrl.selection = TextSelection.collapsed(offset: comfort.length);
      }
    });
  }

  /// 选预设词：回信框预填该词全文（可改）；onOccasion 时填入时机占位文案。
  void _selectPreset(WishReplyPreset preset, AppLocalizations t) {
    setState(() {
      _preset = preset;
      final String text = wishReplyPresetText(
        preset,
        t,
        occasion: wishOccasionText(_occasion, t),
      );
      _replyCtrl.text = text;
      _replyCtrl.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  void _submitTagReply() {
    final String reply = _replyCtrl.text.trim();
    widget.onTagReply(WishTagReplyResult(
      tag: _tag,
      // 回信为空也允许提交（孩子端显示占位）。
      reply: reply.isEmpty ? null : reply,
      occasion: _preset == WishReplyPreset.onOccasion ? _occasion : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations t = AppLocalizations.of(context);
          return AlertDialog(
            key: const Key('parent_wish_action_sheet'),
            title: Text(t.parent_wish_action_tag),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 三动作入口（恰好 3 个，对外口径）。
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        OutlinedButton(
                          key: const Key('sheet_action_setup'),
                          onPressed: widget.onSetup,
                          child: Text(t.parent_wish_action_setup),
                        ),
                        OutlinedButton(
                          key: const Key('sheet_action_fulfill'),
                          onPressed: widget.onFulfill,
                          child: Text(t.parent_wish_action_fulfill),
                        ),
                        OutlinedButton(
                          key: const Key('sheet_action_tag'),
                          onPressed: null,
                          child: Text(t.parent_wish_action_tag),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // 标签 6 选 1（可跳过）——标题只由 InputDecoration.labelText
                    // 承载（v0.2.0：删除原独立 Text 标题，消除双标题）。
                    DropdownButtonFormField<WishTag?>(
                      key: const Key('parent_wish_tag_picker'),
                      isExpanded: true,
                      initialValue: _tag,
                      decoration: InputDecoration(labelText: t.parent_wish_tag_hint),
                      items: <DropdownMenuItem<WishTag?>>[
                        // v0.2.0：删除 value:null 的「取消」项 —— items 恰好 6 项
                        //（可跳过语义由 label「（可以跳过）」+ 不选直接提交承载）。
                        for (final WishTag tag in WishTag.values)
                          DropdownMenuItem<WishTag?>(
                            value: tag,
                            child: Text(wishTagText(tag, t)),
                          ),
                      ],
                      onChanged: (WishTag? v) => _selectTag(v, t),
                    ),
                    const SizedBox(height: 12),
                    // 预设回复下拉（按标签过滤重排，推荐词首位）——同样只用
                    // InputDecoration.labelText 做单一标题（v0.2.0）。
                    DropdownButtonFormField<WishReplyPreset>(
                      key: const Key('parent_wish_reply_preset_picker'),
                      isExpanded: true,
                      initialValue: _preset ?? _presets.first,
                      decoration: InputDecoration(labelText: t.parent_wish_reply_preset),
                      items: <DropdownMenuItem<WishReplyPreset>>[
                        for (final WishReplyPreset p in _presets)
                          DropdownMenuItem<WishReplyPreset>(
                            value: p,
                            child: Text(_presetLabel(p, t)),
                          ),
                      ],
                      onChanged: (WishReplyPreset? v) =>
                          v == null ? null : _selectPreset(v, t),
                    ),
                    if (_preset == WishReplyPreset.onOccasion) ...<Widget>[
                      const SizedBox(height: 12),
                      // 时机下拉（5 选 1，不可自由输入）。
                      DropdownButtonFormField<WishOccasion>(
                        key: const Key('parent_wish_occasion_picker'),
                        isExpanded: true,
                        initialValue: _occasion,
                        decoration:
                            InputDecoration(labelText: t.parent_wish_occasion_hint),
                        items: <DropdownMenuItem<WishOccasion>>[
                          for (final WishOccasion o in WishOccasion.values)
                            DropdownMenuItem<WishOccasion>(
                              value: o,
                              child: Text(wishOccasionText(o, t)),
                            ),
                        ],
                        onChanged: (WishOccasion? v) =>
                            v == null ? null : setState(() => _occasion = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 始终可见的回信输入框（预填可改）。
                    TextField(
                      key: const Key('parent_wish_reply_input'),
                      controller: _replyCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: t.parent_wish_reply_input),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                // v0.2.0：弹 null（不再弹 false）——调用方有 is-cast 守卫。
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.shared_cancel),
              ),
              FilledButton(
                key: const Key('parent_wish_tag_submit'),
                onPressed: () {
                  _submitTagReply();
                  Navigator.of(context).pop(true);
                },
                child: Text(t.parent_wish_tag_apply),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 预设词在下拉里的短标签：onOccasion 用「回复 + 时机」拼出可读短名，
  /// 其余用全文（列表项可换行，不受宽度硬约）。
  String _presetLabel(WishReplyPreset p, AppLocalizations t) {
    final String full = wishReplyPresetText(
      p,
      t,
      occasion: wishOccasionText(_occasion, t),
    );
    return full.length > 24 ? '${full.substring(0, 24)}…' : full;
  }
}
