/// 专注入口页（T09，竖屏）：选时长 + 音效/背景音乐开关 + 横屏引导。
///
/// 依据 PRD §4.1.2（进入前选时长）/ §4.1.6（音效、背景音乐前移至进入前设置页）/ §4.2。
/// 点「开始专注」→ 先经防沉迷服务（T11）评估：夜间锁定跳 /lock、达每日上限提示、需休息跳
/// /rest，否则 → `/focus?minutes=N&dnd=1|0`（横屏打盹屏，独占屏，经 go 进入）。
library entry_page;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';

class EntryPage extends ConsumerStatefulWidget {
  const EntryPage({super.key});

  @override
  ConsumerState<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends ConsumerState<EntryPage> {
  int _minutes = kFocusDurationDefaultMinutes;
  bool _dndOn = true; // 屏蔽通知（勿扰），默认开（F01）

  /// 是否选中「自定义」时长档（与预设档互斥；默认保持某个预设选中）。
  bool _custom = false;

  /// 开始专注前经防沉迷服务（T11）评估；按决策跳转或拦截。
  Future<void> _start() async {
    final AppSettings settings =
        await ref.read(settingsRepositoryProvider).getSettings();
    if (!mounted) return;

    final String day = dayKey(DateTime.now());
    final sessions = await ref.read(focusRepositoryProvider).sessionsOfDay(day);
    if (!mounted) return;

    final double todayFocusMin = sessions
        .where((s) => s.status == FocusStatus.completed)
        .fold(0.0, (a, s) => a + s.actualFocusMin);
    final int todayValid =
        sessions.where((s) => s.status == FocusStatus.completed).length;

    final AntiAddictionDecision decision = AntiAddictionService().evaluate(
      s: settings,
      now: DateTime.now(),
      todayFocusMin: todayFocusMin,
      todayValidSessions: todayValid,
      restSatisfied: ref.read(restSatisfiedProvider),
    );

    switch (decision) {
      case AntiAddictionDecision.nightLocked:
        context.go('/lock');
      case AntiAddictionDecision.dailyCapReached:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '今日专注已达上限（${settings.dailyFocusCap} 分钟），明天再来哦',
            ),
          ),
        );
        return; // 不启动专注
      case AntiAddictionDecision.restRequired:
        context.go('/rest');
        return;
      case AntiAddictionDecision.allowed:
        if (ref.read(restSatisfiedProvider)) {
          // 用完清零，避免下次免休息时间窗。
          ref.read(restSatisfiedProvider.notifier).state = false;
        }
        context.go('/focus?minutes=$_minutes&dnd=${_dndOn ? 1 : 0}');
    }
  }

  /// M2：将音效 / 背景音乐开关持久化写入设置仓储，并刷新 [settingsProvider] 内存值。
  Future<void> _persistSettings({bool? soundOn, bool? bgmOn}) async {
    final AppSettings s = await ref.read(settingsRepositoryProvider).getSettings();
    await ref.read(settingsRepositoryProvider).saveSettings(
          s.copyWith(soundOn: soundOn, bgmOn: bgmOn),
        );
    ref.invalidate(settingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppSettings> settingsAsync = ref.watch(settingsProvider);
    final bool soundOn = settingsAsync.valueOrNull?.soundOn ?? true;
    final bool bgmOn = settingsAsync.valueOrNull?.bgmOn ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/'); // 系统返回键/边缘手势 → 回孩子端，而非退 App（B19）。
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('开始专注'),
          // 本页经 go('/entry') 进入 = 路由栈底；系统返回键经 PopScope 拦截，
          // 显式箭头作可见返回入口（B19 约定）。
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: () => context.go('/'),
          ),
        ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '这次想专注多久？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ...kFocusDurationOptions.map((int m) {
                  final bool selected = !_custom && m == _minutes;
                  return ChoiceChip(
                    label: Text('$m 分钟'),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _minutes = m;
                      _custom = false;
                    }),
                  );
                }),
                // 「自定义」档：选中后在其下显示数字输入（见下方）。
                ChoiceChip(
                  label: const Text('自定义'),
                  selected: _custom,
                  onSelected: (_) => setState(() => _custom = true),
                ),
              ],
            ),
            if (_custom) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const Key('customMinutesField'),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                decoration: const InputDecoration(
                  labelText: '自定义时长（分钟）',
                  hintText: '1 – $kFocusDurationMaxMinutes',
                  helperText: '可选 $kFocusDurationMaxMinutes 分钟以内',
                  border: OutlineInputBorder(),
                ),
                onChanged: (String value) {
                  final int? parsed = int.tryParse(value);
                  // 仅在校验范围 [1, kFocusDurationMaxMinutes] 内更新 _minutes，
                  // 超出或空时保留最近一次合法值，避免开始专注时透传非法时长。
                  if (parsed != null &&
                      parsed >= 1 &&
                      parsed <= kFocusDurationMaxMinutes) {
                    setState(() => _minutes = parsed);
                  }
                },
              ),
            ],
            const SizedBox(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('屏蔽通知（勿扰）'),
              subtitle: const Text('专注时屏蔽短信/来电等打扰'),
              value: _dndOn,
              onChanged: (v) => setState(() => _dndOn = v),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('音效'),
              subtitle: const Text('专注时播放轻提示音'),
              value: soundOn,
              onChanged: (v) {
                _persistSettings(soundOn: v);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('背景音乐'),
              subtitle: const Text('专注时循环轻柔背景乐'),
              value: bgmOn,
              onChanged: (v) {
                _persistSettings(bgmOn: v);
              },
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.screen_rotation, color: Color(0xFFF9A825)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '把手机横过来放好，向日葵就开工啦。',
                      style: TextStyle(fontSize: 16, color: Color(0xFF5D4037)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => _start(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('开始专注'),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
