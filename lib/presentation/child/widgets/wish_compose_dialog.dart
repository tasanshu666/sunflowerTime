/// 许愿弹窗（A-T04 / A22.2）——**孩子端第一个自由文本输入**。
///
/// ## 样式纪律（照 `entry_page.dart:601-630`，`theme.dart` 无 InputDecorationTheme）
///  - `fillColor: Color(0xFFFFFBF0)` / `contentPadding: symmetric(16, 14)` /
///    `OutlineInputBorder(circular(16))` / `enabledBorder` 描边 `Color(0xFFF0E2C8)`；
///  - 字号 `18 / w700`（沿用孩子端字号层级）；`keyboardType: text` /
///    `textInputAction: done`。
///  - 🔴 **字数按 Unicode 码点**（`runes.length`，不用 `String.length`）——
///    emoji 在 UTF-16 里占 2 个 code unit，`String.length` 会让 30 个 emoji 变 60。
///  - 🔴 **软键盘不遮挡**：`showModalBottomSheet(isScrollControlled: true)` +
///    `Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom))`
///    ——只写不变式（输入框始终在键盘之上），不写死像素。
///  - 🔴 **草稿保留**：写失败 / 超长时不关闭，文本留在 controller 里；调用方重开
///    时把 [initialText] 传回即可回填（测试 ⑬）。
///  - 文案全部走 ARB（[AppLocalizations]），builder 上下文在页级 `L10nScope` 之外，
///    故文案由调用方在 scope 内取好经参数槽位传入（与 `showChildConfirmCard` 同构）。
library wish_compose_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/enum_l10n.dart'
    show wishCategoryLabel;
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 把文本按 **Unicode 码点**计长（emoji = 1，不是 2）。判据单点，测试直接调。
int wishTextRuneCount(String text) => text.runes.length;

/// 许愿弹窗的提交结果。
class WishComposeResult {
  const WishComposeResult({required this.text, required this.categoryIndex});

  /// 去首尾空白后的愿望文本。
  final String text;

  /// 选中的愿望分类下标（`WishCategory.index`）。
  final int categoryIndex;
}

/// 弹出许愿输入框。返回 `null` = 取消；返回 [WishComposeResult] = 提交。
///
/// [initialText] 用于草稿回填；[l10n] 由调用方在页级 scope 内取好传入。
Future<WishComposeResult?> showWishComposeDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  String initialText = '',
  int initialCategoryIndex = 0,
}) {
  return showModalBottomSheet<WishComposeResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => WishComposeSheet(
      l10n: l10n,
      initialText: initialText,
      initialCategoryIndex: initialCategoryIndex,
    ),
  );
}

/// 许愿输入浮层本体（独立 widget 便于单独 pump 测试）。
class WishComposeSheet extends StatefulWidget {
  const WishComposeSheet({
    super.key,
    required this.l10n,
    this.initialText = '',
    this.initialCategoryIndex = 0,
  });

  final AppLocalizations l10n;
  final String initialText;
  final int initialCategoryIndex;

  @override
  State<WishComposeSheet> createState() => _WishComposeSheetState();
}

class _WishComposeSheetState extends State<WishComposeSheet> {
  late final TextEditingController _controller;
  late int _categoryIndex;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _categoryIndex = widget.initialCategoryIndex.clamp(0, 5);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前码点数（判据单点：wishTextRuneCount）。
  int get _count => wishTextRuneCount(_controller.text);

  bool get _tooLong => _count > kWishTextMaxLength;

  bool get _tooShort =>
      wishTextRuneCount(_controller.text.trim()) < kWishTextMinLength;

  void _submit() {
    if (_tooLong || _tooShort) {
      // 超长 / 过短：不关闭，草稿自然留在 controller（⑫）。
      setState(() {});
      return;
    }
    Navigator.of(context).pop<WishComposeResult>(
      WishComposeResult(
        text: _controller.text.trim(),
        categoryIndex: _categoryIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 软键盘不遮挡：底部 padding 取 viewInsets（只写不变式，不写死像素）。
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 拖拽把手（纯视觉）。
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6D6B8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.l10n.wishComposeTitle,
                  key: const Key('wish_compose_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B4E12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('wish_compose_field'),
                  controller: _controller,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: widget.l10n.wishComposeHint,
                    helperText: _tooLong ? widget.l10n.wishComposeTooLong : '',
                    helperStyle: const TextStyle(
                      color: Color(0xFFC0392B),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: Color(0xFFF0E2C8)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.l10n.wishComposeCounter(
                      _count,
                      kWishTextMaxLength,
                    ),
                    key: const Key('wish_compose_counter'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _tooLong
                          ? const Color(0xFFC0392B)
                          : const Color(0xFF8A7A66),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 分类单选（6 类，EN 走 ARB；零自由输入）。
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    for (int i = 0; i < 6; i++)
                      _categoryChip(i, widget.l10n),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('wish_compose_submit'),
                  onPressed: _submit,
                  icon: const Icon(Icons.park),
                  label: Text(widget.l10n.wishComposeSubmit),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 分类 chip：选中态高亮。文案经 enum l10n 映射（下一组补 `wishCategoryLabel`）。
  Widget _categoryChip(int index, AppLocalizations t) {
    final bool selected = _categoryIndex == index;
    final String label = wishCategoryLabel(WishCategory.values[index], t);
    return ChoiceChip(
      key: Key('wish_compose_category_$index'),
      label: Text(label),
      selected: selected,
      onSelected: (bool value) {
        if (value) setState(() => _categoryIndex = index);
      },
    );
  }
}
