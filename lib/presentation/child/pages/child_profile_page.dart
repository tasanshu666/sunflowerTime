/// 孩子端「我的」tab（M3 导航重构 / §4.4 成就展示）。
///
/// 采用**累计制**成就（累计专注时长 / 次数 / 有效专注天数 / 任务打卡 / 开花植物 /
/// 阳光余额），刻意**不做「连续 N 天」这类断档清零指标**（§4.4：连续断了归零本身是
/// 挫败源）。底部调试区保留原孩子端首页的「DEBUG 加 1000 阳光」入口供真机验收。
library child_profile_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';

/// 孩子端「我的」：累计成就。
class ChildProfilePage extends ConsumerStatefulWidget {
  const ChildProfilePage({super.key});

  @override
  ConsumerState<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends ConsumerState<ChildProfilePage> {
  double _totalFocusMinutes = 0;
  int _totalSessions = 0;
  int _totalValidDays = 0;
  int _totalCheckIns = 0;
  int _bloomedPlants = 0;
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    // 注：经济修订号监听放在 [build] 里（见下方注释），Riverpod 的 ref.listen
    // 有 `debugDoingBuild` 断言，**只能在 build 中调用**，不能放 initState。
  }

  /// [silent] = true 时不整页转圈（经济修订号触发的后台刷新），
  /// 避免每次消费后切回本 tab 都闪一次全屏 loading。
  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final FocusStats stats =
          await ref.read(focusRepositoryProvider).totalStats();
      final int checkIns =
          await ref.read(taskRepositoryProvider).totalCheckInCount();
      final List<Plant> plants =
          await ref.read(plantRepositoryProvider).plants();
      final double balance =
          await ref.read(sunlightRepositoryProvider).balance();
      if (!mounted) return;
      setState(() {
        _totalFocusMinutes = stats.totalFocusMinutes.toDouble();
        _totalSessions = stats.totalSessions;
        _totalValidDays = stats.totalValidDays;
        _totalCheckIns = checkIns;
        _bloomedPlants =
            plants.where((Plant p) => p.status == PlantStatus.bloomed).length;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// DEBUG ONLY — 测试用临时入口，提交前删除。
  /// 追加一条 +1000 阳光账本（net 为正、balanceAfter 累加），便于真机验收兑换链路。
  Future<void> _grantDebugSunlight() async {
    final double balance = await ref.read(sunlightRepositoryProvider).balance();
    final DateTime now = DateTime.now();
    await ref.read(sunlightRepositoryProvider).append(SunlightEntry(
      id: const Uuid().v4(),
      ts: now,
      type: SunlightType.earn,
      gross: 1000,
      net: 1000,
      balanceAfter: balance + 1000,
      refType: 'debug_grant',
      refId: null,
      dayKey: dayKey(now),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DEBUG：已加 1000 阳光，去阳光商店看看'),
        duration: Duration(seconds: 2),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    // 经济修订号变化（浇水 / 扩容 / 施肥 / 兑换 / 成长打卡）→ 静默重拉本页。
    // 「我的」是底部导航 IndexedStack **保活**页，切 tab 不会重建；不监听的话，
    // 花园扣费后切回本页仍显示扣费前的余额（真机实测：我的页 1000+、花园页 900+）。
    // 账本本身是准的，此处只是补上「重新读一次」。
    // 必须写在 build 内：Riverpod 的 ref.listen 有 `debugDoingBuild` 断言；
    // 订阅随 element unmount 自动关闭（无泄漏），回调内判 mounted 防止 dispose 后 setState。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const CircleAvatar(
                      radius: 36,
                      child: Icon(Icons.person, size: 40),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '我的阳光：${_balance.toInt()} ☀',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // 右上角标签：点击进入阳光来源记录（用户 2026-09-21 反馈 ③）。
                    TextButton.icon(
                      onPressed: () =>
                          context.push('/child/sunlight-history'),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('来源'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD98F00),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('累计成就'),
        _AchievementTile(
          icon: Icons.schedule,
          label: '累计专注时长',
          value: '${_totalFocusMinutes.round()} 分钟',
        ),
        _AchievementTile(
          icon: Icons.timer,
          label: '累计专注次数',
          value: '$_totalSessions 次',
        ),
        _AchievementTile(
          icon: Icons.event_available,
          label: '累计有效专注天数',
          value: '$_totalValidDays 天',
        ),
        _AchievementTile(
          icon: Icons.checklist,
          label: '累计成长打卡',
          value: '$_totalCheckIns 次',
        ),
        _AchievementTile(
          icon: Icons.local_florist,
          label: '累计开花植物',
          value: '$_bloomedPlants 株',
        ),
        const SizedBox(height: 24),
        const _SectionTitle('调试区'),
        // DEBUG ONLY — 测试用，提交前删除
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
          onPressed: _grantDebugSunlight,
          child: const Text('DEBUG 加1000阳光'),
        ),
      ],
    );
  }
}

/// 分组标题。
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      );
}

/// 单条成就行。
class _AchievementTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AchievementTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: Colors.teal),
          title: Text(label),
          trailing: Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
}
