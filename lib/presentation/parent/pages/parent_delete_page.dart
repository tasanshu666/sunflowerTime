/// 家长端·删除入口页（M3 T03，§10.4 C5 合规删除权）。
///
/// 纪律：① 仅放删除入口，不放其他配置；② 「先导后清」——先提示导出成册
/// （导出 UI 留 V2，此处仅提示），确认后调 [DataManagementService.clearAll] 清空
/// Drift 全表 + 安全区 PIN + SharedPreferences；③ 清库后回到孩子端首页。
library parent_delete_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 删除入口页：一键删除全部本地数据（合规 §10.4 C5）。
class ParentDeletePage extends ConsumerStatefulWidget {
  const ParentDeletePage({super.key});

  @override
  ConsumerState<ParentDeletePage> createState() => _ParentDeletePageState();
}

class _ParentDeletePageState extends ConsumerState<ParentDeletePage> {
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    // 弹窗纪律：文案在页级 scope 内取好再传入（builder 上下文在 scope 之外）。
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_delete_dlg_title),
        content: Text(t.parent_delete_dlg_body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_delete_btn_ok),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(dataManagementServiceProvider).clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.parent_delete_done_snack)),
        );
        // 清库后回到孩子端首页（设置将在下次读取时重建默认）。
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nOf(context).parent_delete_fail_snack(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(l10n.parent_delete_title)),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.parent_delete_right_title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        l10n.parent_delete_right_body,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    // 导出成册留 V2：此处仅提示。
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l10n.parent_delete_export_snack)),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: Text(l10n.parent_delete_btn_export),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _busy ? null : _confirmAndDelete,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_forever),
                    label: Text(_busy
                        ? l10n.parent_delete_btn_deleting
                        : l10n.parent_delete_btn_all),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
