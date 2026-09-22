/// 孩子端「阳光来源记录」页（用户 2026-09-21 反馈 ③）。
///
/// 「我的」页阳光卡右上角标签点击进入。按时间倒序列出阳光账本每一笔：
/// 来源（refType → 中文文案）/ 增减（net 正负着色）/ 当时余额 / 时间。
/// 数据来自 [SunlightRepository.all]（append-only 账本，可追溯）。
library child_sunlight_history_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';

/// refType → 中文来源文案（单点收口，避免 UI 层散落字面量）。
const Map<String, String> _refLabels = <String, String>{
  'focus': '专注产出',
  'task_checkin': '成长项奖励',
  'plant_plant': '种植植物',
  'plant_water': '浇水',
  'plant_fertilize': '施肥',
  'plant_revive': '救回植物',
  'plant_expand': '花园扩容',
  'plant_death_refund': '植物死亡返还',
  'redeem': '兑换奖励',
  'queueRelease': '阳光池释放',
  'parent_gift': '家长赠予',
  'debug_grant': '调试发放',
};

/// 孩子端阳光来源记录页。
class ChildSunlightHistoryPage extends ConsumerStatefulWidget {
  const ChildSunlightHistoryPage({super.key});

  @override
  ConsumerState<ChildSunlightHistoryPage> createState() =>
      _ChildSunlightHistoryPageState();
}

class _ChildSunlightHistoryPageState
    extends ConsumerState<ChildSunlightHistoryPage> {
  List<SunlightEntry> _entries = <SunlightEntry>[];
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final List<SunlightEntry> entries =
          await ref.read(sunlightRepositoryProvider).all();
      final double balance =
          await ref.read(sunlightRepositoryProvider).balance();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阳光来源记录'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Text('还没有阳光记录哦 🌻',
                      style: TextStyle(fontSize: 16)),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    _BalanceBanner(balance: _balance),
                    const SizedBox(height: 12),
                    ..._entries.map(_EntryTile.new),
                  ],
                ),
    );
  }
}

/// 余额横幅（与「我的」页阳光卡一致）。
class _BalanceBanner extends StatelessWidget {
  final double balance;
  const _BalanceBanner({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6DC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.wb_sunny, color: Color(0xFFE8A600)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('当前拥有阳光',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              '${balance.toInt()} ☀',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD98F00)),
            ),
          ],
        ),
      );
}

/// 单条账本记录。
class _EntryTile extends StatelessWidget {
  final SunlightEntry entry;
  const _EntryTile(this.entry);

  @override
  Widget build(BuildContext context) {
    final String label =
        _refLabels[entry.refType ?? ''] ?? '其他';
    final bool earned = entry.net >= 0;
    final String amountText = '${entry.net > 0 ? '+' : ''}${entry.net.toInt()} ☀';
    final String time =
        DateFormat('MM-dd HH:mm').format(entry.ts);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(
          earned ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: earned ? Colors.green : Colors.red,
        ),
        title: Text(label),
        subtitle: Text('$time · 余额 ${entry.balanceAfter.toInt()} ☀'),
        trailing: Text(
          amountText,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: earned ? Colors.green.shade700 : Colors.red.shade700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
