/// 家长端·设置页（M3 T03，第 5 个 tab）。
///
/// 复用现有 Settings 字段（ageTier / 夜间边界 / 每日上限 / App 时长 / 休息 /
/// quietMode / detectionOn / soundOn / bgmOn / themeDark / autonomousMode），
/// 0 新增字段。额外能力：
///  · PIN 重设（[SecureStore.resetPin]，非 settings 字段）；
///  · 阳光赠予动作（[SunlightRepository.append] refType='parent_gift'，日/月上限见 U1）；
///  · 夜间边界下拉（M3 修订补齐，字段早存在但 UI 未暴露）；
///  · 两个入口卡 → /parent/report、/parent/delete（**任务配置已升为独立 tab**，
///    玄参大人反馈「奖励独占一个窗口、任务却在设置里」，故两者并排）。
library parent_settings_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';

/// 设置页：家长可控开关集 + PIN 重设 + 阳光赠予 + 三个入口卡。
class ParentSettingsPage extends ConsumerStatefulWidget {
  const ParentSettingsPage({super.key});

  @override
  ConsumerState<ParentSettingsPage> createState() => _ParentSettingsPageState();
}

class _ParentSettingsPageState extends ConsumerState<ParentSettingsPage> {
  AppSettings? _s;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final AppSettings s =
        await ref.read(settingsRepositoryProvider).getSettings();
    if (mounted) setState(() => _s = s..copyWith());
    if (mounted) setState(() => _loading = false);
  }

  /// 落库并刷新本地副本 + 全局 settingsProvider。
  Future<void> _update(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).saveSettings(next);
    if (mounted) setState(() => _s = next);
    ref.invalidate(settingsProvider);
  }

  Future<void> _resetPin() async {
    final TextEditingController oldCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('重设家长 PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '当前 PIN'),
            ),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '新 PIN（≥4 位）'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重设'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String oldPin = oldCtrl.text.trim();
    final String newPin = newCtrl.text.trim();
    if (newPin.length < 4) {
      _snack('新 PIN 至少 4 位');
      return;
    }
    final bool verified = await ref.read(secureStoreProvider).verify(oldPin);
    if (!verified) {
      _snack('当前 PIN 不正确');
      return;
    }
    await ref.read(secureStoreProvider).resetPin(newPin);
    _snack('PIN 已重设');
  }

  /// 家长赠予阳光。
  ///
  /// ⚠️ 2026-09-24 修订（玄参反馈「赠了 30 阳光孩子端没收到」）：
  /// 根因是 **日上限 20**（PRD §4.5：当日赠予 ≤ 20），超额时旧实现只弹一条
  /// 一闪而过的 SnackBar → 家长以为赠成功了、实际一分没入账（**静默失败**）。
  /// 新口径沿用「分因提示 + 不可点即禁用」的既有纪律：
  ///  · 弹窗**先显示**今日/本月已赠与剩余额度；
  ///  · 输入超过剩余额度 → **实时报错 + 「赠予」按钮禁用**，根本点不下去；
  ///  · 额度已耗尽 → 直接分因 SnackBar，不弹窗空跑。
  Future<void> _grantGift() async {
    final DateTime now0 = DateTime.now();
    final SunlightRepository ledger0 = ref.read(sunlightRepositoryProvider);
    final double dayTotal0 =
        await ledger0.netByRefTypeOnDay('parent_gift', dayKey(now0));
    final double monthTotal0 =
        await ledger0.netByRefTypeInMonth('parent_gift', monthKey(now0));
    final double dayRemain =
        (kParentGiftDaily - dayTotal0).clamp(0.0, kParentGiftDaily.toDouble());
    final double monthRemain = (kParentGiftMonthly - monthTotal0)
        .clamp(0.0, kParentGiftMonthly.toDouble());
    final double maxGrant =
        dayRemain < monthRemain ? dayRemain : monthRemain;

    // 额度耗尽：分因提示，不弹窗空跑（点了才发现赠不了 = 静默失败）。
    if (maxGrant <= 0) {
      _snack(dayRemain <= 0
          ? '今日赠予已达上限（$kParentGiftDaily ☀/天），明天再来'
          : '本月赠予已达上限（$kParentGiftMonthly ☀/月）');
      return;
    }

    final TextEditingController amountCtrl = TextEditingController(
      text: maxGrant >= 10 ? '10' : maxGrant.toInt().toString(),
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setState) {
          final double? parsed = double.tryParse(amountCtrl.text.trim());
          // 分因：空/非正数 vs 超额 —— 文案点明「最多可赠多少」，可执行。
          final String? error = parsed == null || parsed <= 0
              ? '请输入正数'
              : parsed > maxGrant
                  ? '最多可赠 ${maxGrant.toInt()} ☀（今日剩 ${dayRemain.toInt()} / 本月剩 ${monthRemain.toInt()}）'
                  : null;
          return AlertDialog(
            title: const Text('赠予阳光'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('今日已赠 ${dayTotal0.toInt()} / $kParentGiftDaily ☀'
                    '，还可赠 ${dayRemain.toInt()} ☀'),
                const SizedBox(height: 4),
                Text('本月已赠 ${monthTotal0.toInt()} / $kParentGiftMonthly ☀'
                    '，还可赠 ${monthRemain.toInt()} ☀'),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '赠予数量'),
                  onChanged: (_) => setState(() {}),
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    error,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: error == null
                    ? () => Navigator.of(ctx).pop(true)
                    : null, // 超额 → 禁用（点不下去，不会静默失败）
                child: const Text('赠予'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final double? amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;
    final DateTime now = DateTime.now();
    final SunlightRepository ledger = ref.read(sunlightRepositoryProvider);
    final double dayTotal =
        await ledger.netByRefTypeOnDay('parent_gift', dayKey(now));
    final double monthTotal =
        await ledger.netByRefTypeInMonth('parent_gift', monthKey(now));
    // 二次校验（弹窗可能被绕过）：仍然拒绝超额，绝不静默入账。
    if (dayTotal + amount > kParentGiftDaily ||
        monthTotal + amount > kParentGiftMonthly) {
      _snack('超出赠予上限，未赠予（今日剩 '
          '${(kParentGiftDaily - dayTotal).toInt()} ☀）');
      return;
    }
    final double balance = await ledger.balance();
    await ledger.append(SunlightEntry(
      id: const Uuid().v4(),
      ts: now,
      type: SunlightType.earn,
      gross: amount,
      net: amount,
      balanceAfter: balance + amount,
      refType: 'parent_gift',
      refId: null,
      dayKey: dayKey(now),
    ));
    // 关键：自增经济修订号 → 孩子端（花园胶囊 / 商店 / 我的）立即重算。
    ref.read(economyRevisionProvider.notifier).state++;
    _snack('已赠予 ${amount.toInt()} ☀，孩子端已到账'
        '（今日剩 ${(kParentGiftDaily - dayTotal - amount).toInt()} ☀）');
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final AppSettings s = _s!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SectionTitle('防沉迷与作息'),
        _SwitchTile(
          title: '免打扰模式',
          value: s.quietMode,
          onChanged: (v) => _update(s.copyWith(quietMode: v)),
        ),
        _SwitchTile(
          title: '在场检测',
          value: s.detectionOn,
          onChanged: (v) => _update(s.copyWith(detectionOn: v)),
        ),
        _NightBoundaryTile(
          hour: s.nightBoundaryHour,
          minute: s.nightBoundaryMinute,
          onChanged: (int h, int m) => _update(
            s.copyWith(nightBoundaryHour: h, nightBoundaryMinute: m),
          ),
        ),
        _IntTile(
          title: '每日专注上限（分钟）',
          value: s.dailyFocusCap,
          options: const <int>[
            kDailyFocusCapLow,
            kDailyFocusCapMid,
            kDailyFocusCapHigh,
          ],
          onChanged: (v) => _update(s.copyWith(dailyFocusCap: v)),
        ),
        _IntTile(
          title: '每日 App 使用时长（分钟）',
          value: s.dailyAppCapMinutes,
          options: kDailyAppCapOptions,
          onChanged: (v) => _update(s.copyWith(dailyAppCapMinutes: v)),
        ),
        _IntTile(
          title: '每 N 次专注后休息',
          value: s.restAfterSessions,
          options: const <int>[1, 2, 3],
          onChanged: (v) => _update(s.copyWith(restAfterSessions: v)),
        ),
        _IntTile(
          title: '休息时长（分钟）',
          value: s.restMinutes,
          options: const <int>[5, 10, 15],
          onChanged: (v) => _update(s.copyWith(restMinutes: v)),
        ),
        const SizedBox(height: 12),
        _SectionTitle('环境与音效'),
        _SwitchTile(
          title: '音效',
          value: s.soundOn,
          onChanged: (v) => _update(s.copyWith(soundOn: v)),
        ),
        _SwitchTile(
          title: '背景音乐',
          value: s.bgmOn,
          onChanged: (v) => _update(s.copyWith(bgmOn: v)),
        ),
        _SwitchTile(
          title: '深色主题',
          value: s.themeDark,
          onChanged: (v) => _update(s.copyWith(themeDark: v)),
        ),
        _SwitchTile(
          title: '自主模式（孩子自助核销）',
          value: s.autonomousMode,
          onChanged: (v) => _update(s.copyWith(autonomousMode: v)),
        ),
        const SizedBox(height: 12),
        _SectionTitle('家长锁与赠予'),
        ListTile(
          leading: const Icon(Icons.pin),
          title: const Text('重设家长 PIN'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _resetPin,
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium),
          title: const Text('赠予阳光'),
          subtitle: Text('日上限 $kParentGiftDaily / 月上限 $kParentGiftMonthly'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _grantGift,
        ),
        const SizedBox(height: 12),
        _SectionTitle('数据入口'),
        _EntryCard(
          icon: Icons.bar_chart,
          title: '专注报告',
          subtitle: '周/月专注分布与健康指标',
          onTap: () => context.push('/parent/report'),
        ),
        _EntryCard(
          icon: Icons.delete_forever,
          title: '删除入口',
          subtitle: '删除全部本地数据（§10.4 C5）',
          danger: true,
          onTap: () => context.push('/parent/delete'),
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
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      );
}

/// 开关行。
class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(
      {required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      );
}

/// 整数选项行（下拉选择）。
class _IntTile extends StatelessWidget {
  final String title;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;
  const _IntTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: DropdownButton<int>(
          value: value,
          items: options
              .map((int o) =>
                  DropdownMenuItem<int>(value: o, child: Text('$o')))
              .toList(),
          onChanged: (int? v) => v == null ? null : onChanged(v),
        ),
      );
}

/// 夜间边界行（时:分 下拉）。
///
/// M3 修订：字段 `nightBoundaryHour/Minute` 早就在 `AppSettings` 里、也是孩子端
/// 夜间锁的**唯一取值来源**（§6.1 不变式），但设置页从未暴露 → 真机反馈「没看到
/// 夜间边界开关」。此处补上，取值档位见 [kNightBoundaryOptions]。
class _NightBoundaryTile extends StatelessWidget {
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  const _NightBoundaryTile({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  static String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // 当前值若不在预设档位（旧库遗留 / 手工改过），补进下拉项，
    // 否则 DropdownButton 会因 value 不在 items 中而断言失败。
    final List<List<int>> options = <List<int>>[...kNightBoundaryOptions];
    if (!options.any((List<int> o) => o[0] == hour && o[1] == minute)) {
      options.add(<int>[hour, minute]);
    }
    return ListTile(
      title: const Text('夜间边界'),
      subtitle: Text('${_fmt(hour, minute)} 起进入夜间（夜锁生效时间）'),
      trailing: DropdownButton<int>(
        value: hour * 60 + minute,
        items: options
            .map((List<int> o) => DropdownMenuItem<int>(
                  value: o[0] * 60 + o[1],
                  child: Text(_fmt(o[0], o[1])),
                ))
            .toList(),
        onChanged: (int? v) {
          if (v == null) return;
          onChanged(v ~/ 60, v % 60);
        },
      ),
    );
  }
}

/// 入口卡（跳转）。
class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: danger ? Colors.red : null),
          title: Text(title,
              style: danger
                  ? const TextStyle(color: Colors.red)
                  : null),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
