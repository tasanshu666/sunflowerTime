/// 隐私政策应用内全文页（首启告知 2.0 / C110）。
///
/// 两个入口共用：
///  · 首启同意页「查看完整隐私政策 ›」（未同意状态也可进入 —— 路由守卫对
///    `/privacy-policy` 双向放行）；
///  · 家长端（PIN 保护）设置页「隐私政策」行。
///
/// ## 数据来源（单一事实源）
/// 正文从打包资产 `assets/docs/privacy_policy_{zh,en}.md` 读取，该资产由
/// `tools/gen_privacy_assets.py` 从 `docs/隐私政策_向日葵专注_v1.md`（底稿，
/// 版本三要素在头部）派生 —— **勿手改资产**；底稿改口径后重跑脚本即可。
/// locale 选文件用 `AppLocalizations.localeName`（zh → zh，其余 → en），
/// 随界面语言切换即时换文（watch [appLanguageProvider] 同帧重建）。
///
/// ## 渲染策略（零新依赖）
/// 不引入 markdown 包（`flutter_markdown` 已停止维护），内置轻量渲染器：
/// 标题（#/##/###）· 引用块（>）· 列表（-）· 表格行（|…|，两列渲染为「**项**：值」、
/// 表头行自动跳过）· 分隔线（---）· 行内 `**加粗**` 与 `` `代码` ``。够用即可，政策底稿
/// 的结构变化须回看本渲染器（新增语法不会自动生效）。
library privacy_policy_page;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 中文政策资产路径（`tools/gen_privacy_assets.py` 产物）。
const String kPrivacyPolicyAssetZh = 'assets/docs/privacy_policy_zh.md';

/// 英文政策资产路径。
const String kPrivacyPolicyAssetEn = 'assets/docs/privacy_policy_en.md';

/// 正文滚动视图的公开 Key（供测试定位 / 滚动断言）。
const Key kPrivacyPolicyScrollKey = Key('privacyPolicyScroll');

class PrivacyPolicyPage extends ConsumerWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // i18n（B1）：watch 界面语言 → 切换语言时本页同帧换文（仿 consent_page）。
    ref.watch(appLanguageProvider);
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          // localeName：gen-l10n 生成（zh / en）；非 zh 一律用英文资产。
          final String asset =
              l10n.localeName == 'zh' ? kPrivacyPolicyAssetZh : kPrivacyPolicyAssetEn;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.privacy_policy_title)),
            body: FutureBuilder<String>(
              // ValueKey(asset)：切语言时换 Future 重新加载对应资产。
              key: ValueKey<String>(asset),
              future: rootBundle.loadString(asset),
              builder: (BuildContext context, AsyncSnapshot<String> snap) {
                if (snap.hasError) {
                  return _CenteredHint(text: l10n.privacy_policy_load_failed);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  key: kPrivacyPolicyScrollKey,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderMarkdown(snap.data!),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── 轻量 Markdown 渲染 ─────────────────────────────────────────────────────

/// 行内样式解析：`**加粗**` + `` `代码` ``（后者只剥反引号不加底色，够用）。
List<InlineSpan> _inlineSpans(String raw, TextStyle base) {
  final List<InlineSpan> spans = <InlineSpan>[];
  // 先按 ** 分段：奇数段为加粗。
  final List<String> boldParts = raw.split('**');
  for (int i = 0; i < boldParts.length; i++) {
    final String part = boldParts[i].replaceAll('`', '');
    if (part.isEmpty) continue;
    final bool bold = i.isOdd;
    spans.add(TextSpan(
      text: part,
      style: bold
          ? base.copyWith(fontWeight: FontWeight.bold)
          : base,
    ));
  }
  if (spans.isEmpty) {
    spans.add(const TextSpan(text: ' '));
  }
  return spans;
}

/// 把政策 Markdown 源文本渲染成 widget 列表（结构见文件头注释）。
List<Widget> _renderMarkdown(String source) {
  final List<Widget> out = <Widget>[];
  final List<String> lines = source.split('\n');
  bool h1Skipped = false;

  for (int idx = 0; idx < lines.length; idx++) {
    final String rawLine = lines[idx];
    final String line = rawLine.trimRight();
    final String t = line.trim();

    if (t.isEmpty) {
      out.add(const SizedBox(height: 10));
      continue;
    }
    if (t == '---') {
      out.add(const SizedBox(height: 6));
      continue;
    }
    // 一级标题：首个跳过（标题在 AppBar），防御性兜底后续 h1 也按节标题渲染。
    if (t.startsWith('# ')) {
      if (!h1Skipped) {
        h1Skipped = true;
        continue;
      }
      out.add(_Heading(text: t.substring(2).trim(), level: 2));
      continue;
    }
    if (t.startsWith('## ')) {
      out.add(_Heading(text: t.substring(3).trim(), level: 2));
      continue;
    }
    if (t.startsWith('### ')) {
      out.add(_Heading(text: t.substring(4).trim(), level: 3));
      continue;
    }
    if (t.startsWith('> ')) {
      out.add(_Quote(text: t.substring(2).trim()));
      continue;
    }
    if (t.startsWith('- ')) {
      out.add(_Bullet(text: t.substring(2).trim()));
      continue;
    }
    if (t.startsWith('|')) {
      // 表头行（下一非空行是 |---| 分隔行）→ 跳过：「项 | 内容」表头对读者无意义。
      bool nextIsSeparator = false;
      for (int j = idx + 1; j < lines.length; j++) {
        final String nt = lines[j].trim();
        if (nt.isEmpty) continue;
        nextIsSeparator = RegExp(r'^\|[\s:\-|]+$').hasMatch(nt);
        break;
      }
      if (nextIsSeparator) continue;
      // 数据行 → 渲染为「项：值」；分隔行被空 cells 过滤自然跳过。
      final List<String> cells = t
          .split('|')
          .map((String c) => c.trim())
          .where((String c) => c.isNotEmpty && !c.startsWith('-'))
          .toList();
      if (cells.isEmpty) continue;
      out.add(_TableRowLine(cells: cells));
      continue;
    }
    // 普通段落。
    out.add(_Paragraph(text: t));
  }
  return out;
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.level});

  final String text;
  final int level; // 2 = 节标题（##），3 = 小节标题（###）

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style;
    return Padding(
      padding: EdgeInsets.only(top: level == 2 ? 18 : 12, bottom: 6),
      child: Text(
        text,
        style: base.copyWith(
          fontSize: level == 2 ? 17 : 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(children: _inlineSpans(text, base)),
        style: base.copyWith(fontSize: 13.5, color: base.color?.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('· '),
          Expanded(
            child: Text.rich(TextSpan(children: _inlineSpans(text, base))),
          ),
        ],
      ),
    );
  }
}

class _TableRowLine extends StatelessWidget {
  const _TableRowLine({required this.cells});

  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style;
    // 「项 | 内容」两列表为主 → 「项：值」，项加粗；多列 → 「 · 」连接。
    // 行内 `**加粗**` 全程走 _inlineSpans（曾只剥首格 `**` 导致值格星号裸露，F149）。
    final TextStyle style = base.copyWith(fontSize: 13.5);
    final List<InlineSpan> spans = <InlineSpan>[];
    if (cells.length == 2) {
      spans.addAll(_inlineSpans(cells.first, style.copyWith(fontWeight: FontWeight.bold)));
      spans.add(TextSpan(text: '：', style: style));
      spans.addAll(_inlineSpans(cells.last, style));
    } else {
      for (int i = 0; i < cells.length; i++) {
        if (i > 0) spans.add(TextSpan(text: ' · ', style: style));
        spans.addAll(_inlineSpans(cells[i], style));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = DefaultTextStyle.of(context).style;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: _inlineSpans(text, base))),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
