/// 专注入口页（T09，竖屏）：选时长 + 音效/背景音乐开关 + 横屏引导。
///
/// 依据 PRD §4.1.2（进入前选时长）/ §4.1.6（音效、背景音乐前移至进入前设置页）/ §4.2。
/// 点「开始专注」→ 先经防沉迷服务（T11）评估：夜间锁定跳 /lock、达每日上限提示、需休息跳
/// /rest，否则 → `/focus?minutes=N&dnd=1|0`（横屏打盹屏，独占屏，经 go 进入）。
///
/// ## 每日专注上限的「三处收口」（2026-09-23 P0 修复）
///
/// 修复前的漏洞：上限**只在点「开始专注」那一刻**判一次「是否已经用完」，
/// **不判「这一场会不会超」**。低年段孩子今日未专注（0 < 60，判定通过）→ 选
/// 「自定义 180 分钟」→ 直接开一场 180 分钟，一次冲过 60 分钟上限拿到 79 阳光。
/// 半途也会超：先做 20+20（剩 20）→ 再选 45 分钟 → 放行 → 到手 85 分钟。
///
/// 现在三处一起收口：
///  1. **选时长时**：超过今日剩余的档位置灰不可选，自定义输入上限跟着收（本页）；
///  2. **开始前**：剩余不足 1 分钟直接拦；否则把本次时长截到剩余（本页）；
///  3. **结算时**：`SunlightService.settle` 按剩余额度硬截断（UI 拦不住计时器
///     因「离席恢复」多算，所以这一层才是真正的兜底）。
///
/// 额度口径的**单点真源**是账本 `refType='focus_session'` 的当日净额
/// （`SunlightService.focusEarnedToday`），不是当日会话 `actualFocusMin` 之和 ——
/// 后者在本场被额度截断时仍记真实时长，会把已用额度算多。
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

  /// 今日专注上限（分钟，设置项）与今日剩余额度（分钟，1:1 于阳光）。
  ///
  /// null = 尚未读到（读取失败或加载中）：此时**不灰档位**、不写提示，
  /// 由「开始前截断」与「结算截断」两层兜住正确性，绝不用假数据拦孩子。
  int? _cap;
  double? _remaining;

  @override
  void initState() {
    super.initState();
    _loadRemaining();
  }

  /// 读「今日剩余专注额度」：走账本口径（见文件头），保证与结算同源。
  Future<void> _loadRemaining() async {
    try {
      final AppSettings s =
          await ref.read(settingsRepositoryProvider).getSettings();
      final double remaining = await ref
          .read(sunlightServiceProvider)
          .focusRemainingToday(s.dailyFocusCap, DateTime.now());
      if (!mounted) return;
      setState(() {
        _cap = s.dailyFocusCap;
        _remaining = remaining;
        // 默认档/已选档超了剩余额度 → 收到剩余上限，避免开局就选了个会被截断的时长。
        if (remaining >= 1 && _minutes > remaining) {
          _minutes = remaining.floor();
          _custom = false;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _remaining = null);
    }
  }

  /// 自定义输入与档位共同的上限：`min(硬上限, 今日剩余)`。
  int get _maxSelectableMinutes {
    const int hard = kFocusDurationMaxMinutes;
    final double? remaining = _remaining;
    if (remaining == null) return hard;
    final int byRemaining = remaining.floor();
    return byRemaining < hard ? byRemaining : hard;
  }

  /// 今日额度是否已耗尽（含不足 1 分钟的零头）。
  bool get _roundedOut => _remaining != null && _remaining! < 1;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 开始专注前经防沉迷服务（T11）评估；按决策跳转或拦截。
  ///
  /// 见文件头「三处收口」：本方法负责第 ① ② 处，第 ③ 处在结算侧。
  Future<void> _start() async {
    final AppSettings settings =
        await ref.read(settingsRepositoryProvider).getSettings();
    if (!mounted) return;

    final String day = dayKey(DateTime.now());
    final sessions = await ref.read(focusRepositoryProvider).sessionsOfDay(day);
    if (!mounted) return;

    // 已用额度取**账本**口径（不再对会话 actualFocusMin 求和，见文件头）。
    final double usedToday = await ref
        .read(sunlightServiceProvider)
        .focusEarnedToday(DateTime.now());
    if (!mounted) return;

    final int todayValid =
        sessions.where((s) => s.status == FocusStatus.completed).length;
    final int cap = settings.dailyFocusCap;

    final AntiAddictionService antiAddiction = AntiAddictionService();
    final double remaining = antiAddiction.dailyFocusRemaining(settings, usedToday);

    final AntiAddictionDecision decision = antiAddiction.evaluate(
      s: settings,
      now: DateTime.now(),
      todayFocusMin: usedToday,
      todayValidSessions: todayValid,
      restSatisfied: ref.read(restSatisfiedProvider),
    );

    switch (decision) {
      case AntiAddictionDecision.nightLocked:
        context.go('/lock');
      case AntiAddictionDecision.dailyCapReached:
        _snack('今日专注已达上限（$cap 分钟），明天再来哦');
        return; // 不启动专注
      case AntiAddictionDecision.restRequired:
        context.go('/rest');
        return;
      case AntiAddictionDecision.allowed:
        // 剩余不足 1 分钟（额度只剩零头）→ 当作已用完拦下，避免开一场 1 分钟
        // 却仍超出剩余额度。
        if (remaining < 1) {
          _snack('今天的专注时间用完啦（上限 $cap 分钟），明天再来哦');
          return;
        }
        // 开始前按剩余额度截断（第 ② 处收口）：孩子可能选了比剩余更长的档，
        // 不截就会一次冲过日上限。
        final int minutes =
            _minutes > remaining ? remaining.floor() : _minutes;
        if (minutes < _minutes) {
          _snack('今天只剩 ${remaining.floor()} 分钟额度了，这次就专注 $minutes 分钟吧');
        }
        if (ref.read(restSatisfiedProvider)) {
          // 用完清零，避免下次免休息时间窗。
          ref.read(restSatisfiedProvider.notifier).state = false;
        }
        context.go('/focus?minutes=$minutes&dnd=${_dndOn ? 1 : 0}');
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
    final int maxSelectable = _maxSelectableMinutes;
    final bool roundedOut = _roundedOut;
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
            if (_remaining != null) ...<Widget>[
              const SizedBox(height: 6),
              // 剩余额度提示：让孩子在选时长前就知道今天还剩多少（第 ① 处收口）。
              Text(
                roundedOut
                    ? '今天的专注时间已经用完啦（每日上限 ${_cap ?? 0} 分钟），明天再来'
                    : '今天还可以专注 ${_remaining!.floor()} 分钟'
                        '（每日上限 ${_cap ?? 0} 分钟）',
                style: TextStyle(
                  fontSize: 13,
                  color: roundedOut
                      ? Colors.orange.shade800
                      : Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ...kFocusDurationOptions.map((int m) {
                  // 超过今日剩余额度的档位直接不可选（而不是选了到结算才少拿）。
                  final bool overLimit = _remaining != null && m > _remaining!;
                  final bool selected = !_custom && m == _minutes;
                  return ChoiceChip(
                    label: Text('$m 分钟'),
                    selected: selected,
                    onSelected:
                        overLimit ? null : (_) => setState(() {
                              _minutes = m;
                              _custom = false;
                            }),
                  );
                }),
                // 「自定义」档：选中后在其下显示数字输入（见下方）。
                ChoiceChip(
                  label: const Text('自定义'),
                  selected: _custom,
                  onSelected:
                      roundedOut ? null : (_) => setState(() => _custom = true),
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
                decoration: InputDecoration(
                  labelText: '自定义时长（分钟）',
                  hintText: maxSelectable >= 1 ? '1 – $maxSelectable' : '今日额度已用完',
                  helperText: _remaining == null
                      ? '可选 $kFocusDurationMaxMinutes 分钟以内'
                      : '可选 $maxSelectable 分钟以内（受今日剩余额度限制）',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (String value) {
                  final int? parsed = int.tryParse(value);
                  // 仅在校验范围 [1, _maxSelectableMinutes] 内更新 _minutes，
                  // 超出或空时保留最近一次合法值，避免开始专注时透传非法时长。
                  if (parsed != null &&
                      parsed >= 1 &&
                      parsed <= maxSelectable) {
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
