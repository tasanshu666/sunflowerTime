/// 专注入口页（T09，竖屏）：选时长 + 音效/背景音乐开关。
///
/// 依据 PRD §4.1.2（进入前选时长）/ §4.1.6（音效、背景音乐前移至进入前设置页）/ §4.2。
/// 点「开始专注」→ 先经防沉迷服务（T11）评估：夜间锁定跳 /lock、达每日上限提示、需休息跳
/// /rest，否则 → `/focus?minutes=N&dnd=1|0`（横屏打盹屏，独占屏，经 go 进入）。
/// 选「自由」档 → `/focus?minutes=0&dnd=..&free=1`（不预设时长，孩子自己点结束）。
///
/// ## 视觉改版（玄参 2026-09-30「少儿不友好」反馈）
/// 按卡片样式统一专项的马卡龙/奶油风重排：奶油底 + 大圆角白卡（柔和阴影）+
/// 吉祥物圆 + 大号粉彩时长胶囊 + 彩色圆底大图标开关行 + 大号圆角主按钮。
/// **仅视觉层重排，交互逻辑（额度三处收口 / 自定义校验 / 开关持久化）原样保留**。
///
/// ## 时长档位固定三排（玄参 2026-09-30）
/// 旧实现用 `Wrap` 流式排布，选中态会插入打勾图标 → 胶囊变宽 → 触发重排，
/// 表现为「点一下胶囊就跳位/来回变动」。现改为**固定三排等宽 Row**：
/// 15-20-25 / 30-45-60 / 自由-自定义，胶囊宽度由 `Expanded` 等分固定，
/// 选中不再引起任何重排。原底部「把手机横过来…」引导贴士已按玄参要求删除
/// （直接点「开始专注」即可，不再口头引导转横屏）。
///
/// 「自由」档口径：不预设时长、不自动结算，孩子自己决定何时结束；计时照走、
/// 每日额度与防沉迷约束仍在（结算侧硬截断兜底）。
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
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/anti_addiction_service.dart';

/// 页面底色（奶油暖调，与成长页 `_kCream` 同源）。
const Color _kCream = Color(0xFFFBF4E4);

/// 深棕正文（儿童可读主文字色）。
const Color _kBrown = Color(0xFF5D4037);

/// 主琥珀（选中态 / 开关激活 / 主按钮）。
const Color _kAmber = Color(0xFFF9A825);

/// 大圆角白卡：柔和阴影 + 22 圆角（与成长/商店页卡片同款）。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// 卡片小节标题行：粉彩圆底吉祥物 emoji + 标题。
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.emoji,
    required this.bgColor,
    required this.title,
  });

  /// 吉祥物 emoji（占位，后续换豆包立绘）。
  final String emoji;

  /// 圆底粉彩色。
  final Color bgColor;

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kBrown,
            ),
          ),
        ),
      ],
    );
  }
}

/// 大号时长胶囊（儿童友好：大字、大热区、选中打勾）。
///
/// 宽度由外层 `Expanded` 等分固定，选中态插入的打勾图标**不会**改变胶囊宽度，
/// 因此不会像旧 `Wrap` 那样触发重排跳动（玄参 2026-09-30）。
class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final bool selected;

  /// false = 超出今日剩余额度 / 额度用完，置灰不可选。
  final bool enabled;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (!enabled) {
      bg = const Color(0xFFEFEAE0);
      fg = const Color(0xFFB9B1A4);
    } else if (selected) {
      bg = _kAmber;
      fg = Colors.white;
    } else {
      bg = const Color(0xFFFFF6E3);
      fg = const Color(0xFF8D6E00);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 54,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (selected) ...<Widget>[
                  const Icon(Icons.check_circle, size: 18, color: Colors.white),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: fg,
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
}

/// 固定一排胶囊（玄参 2026-09-30）：行内等分、排数固定，杜绝 Wrap 的跳动重排。
class _DurationRow extends StatelessWidget {
  const _DurationRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// 开关行：56×56 粉彩圆底大图标 + 标题/副标题 + Switch。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(icon, size: 28, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kBrown,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _kAmber,
          activeTrackColor: const Color(0xFFFFE0A3),
        ),
      ],
    );
  }
}

class EntryPage extends ConsumerStatefulWidget {
  const EntryPage({super.key});

  @override
  ConsumerState<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends ConsumerState<EntryPage> {
  int _minutes = kFocusDurationDefaultMinutes;
  bool _dndOn = true; // 屏蔽通知（勿扰），默认开（F01）

  /// 是否选中「自定义」时长档（与预设档、自由档互斥）。
  bool _custom = false;

  /// 是否选中「自由」档（玄参 2026-09-30）：不预设时长、不自动结算，
  /// 孩子自己决定何时结束；计时照走、额度与防沉迷约束仍在。
  bool _free = false;

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

    // F66：完成会话列表同时供场数统计与「休息义务起始基准」推导。
    final List<FocusSession> completed =
        sessions.where((s) => s.status == FocusStatus.completed).toList();
    final int todayValid = completed.length;
    final int cap = settings.dailyFocusCap;

    final AntiAddictionService antiAddiction = AntiAddictionService();
    final double remaining =
        antiAddiction.dailyFocusRemaining(settings, usedToday);

    // F66：休息满足 = 休息页走完倒计时（内存标记）**或** 触发场结束至今已自然
    // 流逝 ≥ restMinutes（墙上时钟）。锁屏/离开 App 期间同样是休息，回来不该
    // 重新计满 10 分钟。基准从会话库推导，幂等、杀进程不丢。
    final bool restSatisfied = ref.read(restSatisfiedProvider) ||
        antiAddiction.restNaturallySatisfied(
          restMinutes: settings.restMinutes,
          now: DateTime.now(),
          lastSessionEnd: antiAddiction.lastCompletedSessionEnd(completed),
        );

    final AntiAddictionDecision decision = antiAddiction.evaluate(
      s: settings,
      now: DateTime.now(),
      todayFocusMin: usedToday,
      todayValidSessions: todayValid,
      restSatisfied: restSatisfied,
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
        if (ref.read(restSatisfiedProvider)) {
          // 用完清零，避免下次免休息时间窗。
          ref.read(restSatisfiedProvider.notifier).state = false;
        }
        // 自由专注：不预设时长，透传 free=1（minutes=0 仅作落库口径标记）；
        // 没有「时长」可按剩余额度截断，额度由结算侧硬截断兜底。
        if (_free) {
          context.go('/focus?minutes=0&dnd=${_dndOn ? 1 : 0}&free=1');
          return;
        }
        // 开始前按剩余额度截断（第 ② 处收口）：孩子可能选了比剩余更长的档，
        // 不截就会一次冲过日上限。
        final int minutes =
            _minutes > remaining ? remaining.floor() : _minutes;
        if (minutes < _minutes) {
          _snack('今天只剩 ${remaining.floor()} 分钟额度了，这次就专注 $minutes 分钟吧');
        }
        context.go('/focus?minutes=$minutes&dnd=${_dndOn ? 1 : 0}');
    }
  }

  /// M2：将音效 / 背景音乐开关持久化写入设置仓储，并刷新 [settingsProvider] 内存值。
  Future<void> _persistSettings({bool? soundOn, bool? bgmOn}) async {
    final AppSettings s =
        await ref.read(settingsRepositoryProvider).getSettings();
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
        backgroundColor: _kCream,
        appBar: AppBar(
          backgroundColor: _kCream,
          title: const Text(
            '开始专注',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kBrown,
            ),
          ),
          iconTheme: const IconThemeData(color: _kBrown),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: <Widget>[
              // ── 卡 1：选时长 ──────────────────────────────────────────
              _SectionCard(
                children: <Widget>[
                  const _CardHeader(
                    emoji: '⏰',
                    bgColor: Color(0xFFFFF1C2),
                    title: '这次想专注多久？',
                  ),
                  if (_remaining != null) ...<Widget>[
                    const SizedBox(height: 12),
                    // 剩余额度提示：让孩子在选时长前就知道今天还剩多少（第 ① 处收口）。
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: roundedOut
                            ? const Color(0xFFFFE0B2)
                            : const Color(0xFFFFF6DE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        roundedOut
                            ? '今天的专注时间已经用完啦（每日上限 ${_cap ?? 0} 分钟），明天再来'
                            : '今天还可以专注 ${_remaining!.floor()} 分钟'
                                '（每日上限 ${_cap ?? 0} 分钟）',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: roundedOut
                              ? const Color(0xFFE65100)
                              : const Color(0xFF8D6E00),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 固定三排（玄参 2026-09-30）：15-20-25 / 30-45-60 / 自由-自定义。
                  // 等宽 Row 排版，选中不打乱布局、胶囊不跳位。
                  _DurationRow(
                    children: <Widget>[
                      ...kFocusDurationOptions
                          .where((int m) => m <= 25)
                          .map(_chipFor),
                    ],
                  ),
                  _DurationRow(
                    children: <Widget>[
                      ...kFocusDurationOptions
                          .where((int m) => m > 25)
                          .map(_chipFor),
                    ],
                  ),
                  _DurationRow(
                    children: <Widget>[
                      // 「自由」档：不预设时长，孩子自己决定何时结束（见文件头）。
                      _DurationChip(
                        label: '自由',
                        selected: _free,
                        enabled: !roundedOut,
                        onSelected: roundedOut
                            ? null
                            : () => setState(() {
                                  _free = true;
                                  _custom = false;
                                }),
                      ),
                      // 「自定义」档：选中后在其下显示数字输入（见下方）。
                      _DurationChip(
                        label: '自定义',
                        selected: _custom,
                        enabled: !roundedOut,
                        onSelected: roundedOut
                            ? null
                            : () => setState(() {
                                  _custom = true;
                                  _free = false;
                                }),
                      ),
                    ],
                  ),
                  if (_custom) ...<Widget>[
                    const SizedBox(height: 4),
                    TextField(
                      key: const Key('customMinutesField'),
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: '自定义时长（分钟）',
                        hintText: maxSelectable >= 1
                            ? '1 – $maxSelectable'
                            : '今日额度已用完',
                        helperText: _remaining == null
                            ? '可选 $kFocusDurationMaxMinutes 分钟以内'
                            : '可选 $maxSelectable 分钟以内（受今日剩余额度限制）',
                        filled: true,
                        fillColor: const Color(0xFFFFFBF0),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: Color(0xFFF0E2C8)),
                        ),
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
                ],
              ),
              const SizedBox(height: 16),
              // ── 卡 2：专注时的小设置 ────────────────────────────────────
              _SectionCard(
                children: <Widget>[
                  const _CardHeader(
                    emoji: '🎧',
                    bgColor: Color(0xFFD9E8FF),
                    title: '专注时的小设置',
                  ),
                  const SizedBox(height: 6),
                  _ToggleRow(
                    icon: Icons.notifications_off,
                    iconColor: const Color(0xFF1565C0),
                    iconBg: const Color(0xFFD9E8FF),
                    title: '屏蔽通知（勿扰）',
                    subtitle: '专注时屏蔽短信/来电等打扰',
                    value: _dndOn,
                    onChanged: (bool v) => setState(() => _dndOn = v),
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    icon: Icons.volume_up,
                    iconColor: const Color(0xFFE65100),
                    iconBg: const Color(0xFFFFE0B2),
                    title: '提示音效',
                    subtitle: '专注时播放轻提示音',
                    value: soundOn,
                    onChanged: (bool v) {
                      _persistSettings(soundOn: v);
                    },
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    icon: Icons.headphones,
                    iconColor: const Color(0xFF2E7D32),
                    iconBg: const Color(0xFFD9F2DD),
                    title: '背景音乐',
                    subtitle: '专注时循环轻柔背景乐',
                    value: bgmOn,
                    onChanged: (bool v) {
                      _persistSettings(bgmOn: v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // ── 主按钮：大号圆角 + 吉祥物 ──────────────────────────────
              // 原底部「把手机横过来…」引导贴士已按玄参要求删除：
              // 直接点「开始专注」即可，不再口头引导转横屏。
              FilledButton(
                onPressed: () => _start(),
                style: FilledButton.styleFrom(
                  backgroundColor: _kAmber,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('🌻', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text('开始专注'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个预设分钟档胶囊：超过今日剩余额度置灰；选中即取消「自由 / 自定义」。
  Widget _chipFor(int m) {
    final bool overLimit = _remaining != null && m > _remaining!;
    final bool selected = !_custom && !_free && m == _minutes;
    return _DurationChip(
      label: '$m 分钟',
      selected: selected,
      enabled: !overLimit,
      onSelected: overLimit
          ? null
          : () => setState(() {
                _minutes = m;
                _custom = false;
                _free = false;
              }),
    );
  }
}
