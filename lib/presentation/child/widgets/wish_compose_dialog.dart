/// 许愿弹窗（A-T04 / A22.2）——**孩子端第一个自由文本输入**。
///
/// ## v0.3.0 改造（R3-P0-02 / R3-P0-03 / R3-P0-04，玄参反馈 2/3）
///  - **居中 `Dialog`**：玄参反馈 2「点击开始许愿，弹出来的卡片在中间显示，不要在下面
///    显示」⇒ `showModalBottomSheet` → `showDialog`（`barrierDismissible: false`，
///    与贴标签弹层同纪律：只走显式按钮）。
///  - 最大高度 **≤ 屏高 85%**，内容超高时**弹层内部滚动**（`SingleChildScrollView`），
///    键盘弹起走 `viewInsets` 避让。
///  - **删掉 6 个分类 chip**（反馈 3：孩子不可能自己给愿望分类）⇒ 提交一律
///    `category = 0`（`WishCategory.other`，DB 列保留供历史数据）。
///  - **字数双阈值**：输入框 3→5 行；counter 与本地校验**同源于**
///    [wishMaxTextLength]（域层 `createWish(maxTextLength:)` 由调用方传同一值）。
///
/// ## 样式纪律（照 `entry_page.dart:601-630`，`theme.dart` 无 InputDecorationTheme）
///  - `fillColor: Colors.white` / `contentPadding: symmetric(16, 14)` /
///    `OutlineInputBorder(circular(16))` / `enabledBorder` 描边 `Color(0xFFF0E2C8)`；
///  - 字号 `18 / w700`（沿用孩子端字号层级）；`keyboardType: text` /
///    `textInputAction: done`。
///  - 🔴 **字数按 Unicode 码点**（`runes.length`，不用 `String.length`）——
///    emoji 在 UTF-16 里占 2 个 code unit，`String.length` 会让 1 个 emoji 变 2。
///  - 🔴 **草稿保留**：写失败 / 超长时不关闭，文本留在 controller 里；调用方重开
///    时把 [initialText] 传回即可回填。
///  - 文案全部走 ARB（[AppLocalizations]），builder 上下文在页级 `L10nScope` 之外，
///    故文案由调用方在 scope 内取好经参数槽位传入（与 `showChildConfirmCard` 同构）。
library wish_compose_dialog;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 弹层容器 Key（测试用 `tester.getRect` 量居中偏差 / 底边距 / 最大高度）。
const Key kWishComposeDialogKey = Key('wish_compose_dialog');

/// 把文本按 **Unicode 码点**计长（emoji = 1，不是 2）。判据单点，测试直接调。
int wishTextRuneCount(String text) => text.runes.length;

/// 许愿弹窗的提交结果。
///
/// 🔴 v0.3.0：分类选择 UI 已删除，结果**只带文本**；提交时固定写
/// `WishCategory.other`（`category = 0`，列保留供历史数据）。
class WishComposeResult {
  const WishComposeResult({required this.text});

  /// 去首尾空白后的愿望文本。
  final String text;
}

/// 弹出许愿输入框（**居中 Dialog**）。返回 `null` = 取消；返回
/// [WishComposeResult] = 提交。
///
/// [initialText] 用于草稿回填；[l10n] 由调用方在页级 scope 内取好传入；
/// [maxTextLength] 由调用方传 `wishMaxTextLength(locale.languageCode)` ——
/// 与后续 `createWish(maxTextLength:)` 用**同一个值**（单一真源 S2）。
Future<WishComposeResult?> showWishComposeDialog({
  required BuildContext context,
  required AppLocalizations l10n,
  String initialText = '',
  int maxTextLength = kWishTextMaxLengthZh,
}) {
  return showDialog<WishComposeResult>(
    context: context,
    // 与贴标签弹层同纪律：点遮罩不关闭，只走显式按钮（防误触丢失草稿）。
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      final Size screen = MediaQuery.sizeOf(ctx);
      return Dialog(
        // 🔴 可见卡片由内层 Container 承担（**它才是被测几何的载体**）：
        // `Dialog` 自身经 `Align` 铺满整屏，`getRect(Dialog)` 拿不到卡片矩形。
        backgroundColor: Colors.transparent,
        elevation: 0,
        // 键盘避让交给 `Dialog` 自身的 `viewInsets` 合并逻辑（effectivePadding =
        // viewInsets + insetPadding），不在此处手写 bottom padding —— 手写会和
        // 居中约束打架（容器仍被居中，内容却被顶高）。
        // 水平 24 / 垂直 40：配合内容自然高度 ⇒ 底边距屏幕底 ≥80dp（排除贴底）。
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          key: kWishComposeDialogKey,
          // ≤ 屏高 85%（R3-P0-02⑤）；超高由内部 SingleChildScrollView 承接。
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: screen.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF0),
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: WishComposeSheet(
              l10n: l10n,
              initialText: initialText,
              maxTextLength: maxTextLength,
            ),
          ),
        ),
      );
    },
  );
}

/// 许愿输入浮层本体（独立 widget 便于单独 pump 测试）。
class WishComposeSheet extends StatefulWidget {
  const WishComposeSheet({
    super.key,
    required this.l10n,
    this.initialText = '',
    this.maxTextLength = kWishTextMaxLengthZh,
  });

  final AppLocalizations l10n;
  final String initialText;

  /// 字数上限（= 调用方 `wishMaxTextLength(locale)` 的返回值）。
  final int maxTextLength;

  @override
  State<WishComposeSheet> createState() => _WishComposeSheetState();
}

class _WishComposeSheetState extends State<WishComposeSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前码点数（判据单点：wishTextRuneCount）。
  int get _count => wishTextRuneCount(_controller.text);

  /// 超上限（上限来自 [WishComposeSheet.maxTextLength]，与 counter 同源）。
  bool get _tooLong => _count > widget.maxTextLength;

  bool get _tooShort =>
      wishTextRuneCount(_controller.text.trim()) < kWishTextMinLength;

  void _submit() {
    if (_tooLong || _tooShort) {
      // 超长 / 过短：不关闭，草稿自然留在 controller（R3-P0-04③）。
      setState(() {});
      return;
    }
    Navigator.of(context).pop<WishComposeResult>(
      WishComposeResult(text: _controller.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
            // v0.3.0（R3-P0-04⑤）：可见行数 3 → 5，超出内部滚动。
            maxLines: 5,
            minLines: 3,
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
                borderSide: const BorderSide(color: Color(0xFFF0E2C8)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              // counter 的上限 == [WishComposeSheet.maxTextLength] ==
              // 调用方传给 createWish 的 maxTextLength（单一真源 S2）。
              widget.l10n.wishComposeCounter(_count, widget.maxTextLength),
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
          const SizedBox(height: 8),
          // 🔴 barrierDismissible:false ⇒ 必须给显式取消出口，否则无路可退。
          TextButton(
            key: const Key('wish_compose_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.l10n.shared_cancel),
          ),
        ],
      ),
    );
  }
}
