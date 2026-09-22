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

/// 删除入口页：一键删除全部本地数据（合规 §10.4 C5）。
class ParentDeletePage extends ConsumerStatefulWidget {
  const ParentDeletePage({super.key});

  @override
  ConsumerState<ParentDeletePage> createState() => _ParentDeletePageState();
}

class _ParentDeletePageState extends ConsumerState<ParentDeletePage> {
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除全部本地数据？'),
        content: const Text(
          '此操作将永久删除：专注记录、阳光账本、植物、成长项、奖励模板、'
          '家长 PIN 与所有本地设置，且无法恢复。\n\n'
          '建议先「导出成册」留存（导出功能将在 V2 上线）。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认删除'),
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
          const SnackBar(content: Text('已删除全部本地数据')),
        );
        // 清库后回到孩子端首页（设置将在下次读取时重建默认）。
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('删除入口')),
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
                Text('数据删除权（§10.4 C5）',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text(
                  '你拥有删除全部本地数据的权利。删除后所有进度与设置将不可恢复。',
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
                const SnackBar(content: Text('导出成册功能将在 V2 上线，请先截图留存')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('导出成册（V2 上线）'),
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
              label: Text(_busy ? '删除中…' : '删除全部本地数据'),
            ),
          ),
        ],
      ),
    );
  }
}
