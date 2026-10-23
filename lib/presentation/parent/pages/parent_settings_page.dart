/// 家长端·设置页（M3 T03，第 5 个 tab）。
///
/// 复用现有 Settings 字段（ageTier / 夜间边界 / 每日上限 / App 时长 / 休息 /
/// quietMode / soundOn / bgmOn / themeDark），
/// 0 新增字段。额外能力：
///  · PIN 重设（[SecureStore.resetPin]，非 settings 字段）；
///  · 阳光赠予动作（[SunlightRepository.append] refType='parent_gift'，日/月上限见 U1）；
///  · 夜间边界下拉（M3 修订补齐，字段早存在但 UI 未暴露）；
///  · 删除入口卡 → /parent/delete（**任务配置已升为独立 tab**，玄参大人反馈
///    「奖励独占一个窗口、任务却在设置里」，故两者并排）。
///
/// C85 变更：① 删除「专注报告」入口卡（报告自 C76 起已在「记录」tab 内，双入口冗余）；
/// ② 原「数据入口」分区标题改为「数据与隐私」（只剩删除入口）；
/// ③ 末尾新增 **仅 Debug** 的「会员模式」开关（`if (kDebugMode)` 包裹，release 无）。
library parent_settings_page;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/debug_unlock_switch.dart';
import 'package:sunflower_time/presentation/shared/language_picker.dart';

/// 设置页：家长可控开关集 + PIN 重设 + 阳光赠予 + 删除入口卡（+ Debug 调试区）。
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
  ///
  /// 2026-09-29：顺带把「音效 / 背景音乐」开关**立即**同步给音频服务 —— 否则家长改完
  /// 开关要等孩子端外壳重建（甚至重启 App）才生效（花园 BGM 迟迟不响的次生原因）。
  Future<void> _update(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).saveSettings(next);
    AudioService.instance.applySettings(
      soundOn: next.soundOn,
      bgmOn: next.bgmOn,
    );
    if (mounted) setState(() => _s = next);
    ref.invalidate(settingsProvider);
  }

  Future<void> _resetPin() async {
    // i18n B2 🔴 弹窗纪律：builder 上下文在页级 scope 之外 → 文案在此处（页级
    // scope 内的 context）取好，经参数槽位传入弹窗。
    final AppLocalizations t = l10nOf(context);
    final TextEditingController oldCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_settings_pin_dlg_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: t.parent_settings_pin_dlg_old,
              ),
            ),
            TextField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: t.parent_settings_pin_dlg_new,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_settings_pin_dlg_ok),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String oldPin = oldCtrl.text.trim();
    final String newPin = newCtrl.text.trim();
    if (newPin.length < 4) {
      _snack(t.parent_settings_pin_too_short_snack);
      return;
    }
    final bool verified = await ref.read(secureStoreProvider).verify(oldPin);
    if (!verified) {
      _snack(t.parent_settings_pin_wrong_snack);
      return;
    }
    await ref.read(secureStoreProvider).resetPin(newPin);
    _snack(t.parent_settings_pin_ok_snack);
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
    // i18n B2 🔴 弹窗纪律：文案在页级 scope 内取好，经参数槽位传入弹窗。
    final AppLocalizations t = l10nOf(context);
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

    // 跨 await 后仍要用 context（提示条 / 弹窗）：先确认页面还在。
    if (!mounted) return;

    // 额度耗尽：分因提示，不弹窗空跑（点了才发现赠不了 = 静默失败）。
    if (maxGrant <= 0) {
      _snack(dayRemain <= 0
          ? t.parent_settings_gift_daily_cap_snack(kParentGiftDaily)
          : t.parent_settings_gift_monthly_cap_snack(kParentGiftMonthly));
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
              ? t.parent_settings_gift_err_positive
              : parsed > maxGrant
                  ? t.parent_settings_gift_err_over(
                      maxGrant.toInt(),
                      dayRemain.toInt(),
                      monthRemain.toInt(),
                    )
                  : null;
          return AlertDialog(
            title: Text(t.parent_settings_gift_dlg_title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t.parent_settings_gift_daily_line(
                  dayTotal0.toInt(),
                  kParentGiftDaily,
                  dayRemain.toInt(),
                )),
                const SizedBox(height: 4),
                Text(t.parent_settings_gift_monthly_line(
                  monthTotal0.toInt(),
                  kParentGiftMonthly,
                  monthRemain.toInt(),
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.parent_settings_gift_amount_label,
                  ),
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
                child: Text(t.shared_cancel),
              ),
              FilledButton(
                onPressed: error == null
                    ? () => Navigator.of(ctx).pop(true)
                    : null, // 超额 → 禁用（点不下去，不会静默失败）
                child: Text(t.parent_settings_gift_btn),
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
      _snack(t.parent_settings_gift_over_snack(
        (kParentGiftDaily - dayTotal).toInt(),
      ));
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
    _snack(t.parent_settings_gift_ok_snack(
      amount.toInt(),
      (kParentGiftDaily - dayTotal - amount).toInt(),
    ));
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
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析；Builder 的
    // 上下文在 scope **之内**，故可直调 `AppLocalizations.of`。
    return L10nScope(
      child: Builder(builder: (BuildContext context) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // 🔴 2026-10-14 玄参截图反馈：「解锁全部功能」**上移到最顶部**第一个分区
        // （原话「放在最上面，更显眼」）。其余分区顺序不变。
        _SectionTitle(l10n.premium_gate_unlock_all),
        // C78（V2-4）：唯一**金令牌视觉**入口（仅样式；路由 / PIN 门控 / 副标题不变）。
        _EntryCard(
          icon: Icons.star_rounded,
          title: l10n.premium_gate_unlock_all,
          subtitle: const PremiumStatusText(),
          gold: true,
          onTap: () => context.push('/parent/premium'),
        ),
        const SizedBox(height: 12),
        _SectionTitle(l10n.parent_settings_section_screentime),
        _SwitchTile(
          title: l10n.parent_settings_switch_quiet,
          value: s.quietMode,
          onChanged: (v) => _update(s.copyWith(quietMode: v)),
        ),
        // 🔴 C79（2026-10-15 玄参拍板）：原「在场检测」开关已移除 ——
        //    功能**常开**（专注页无条件启动 PresenceDetector，防挂机核心，
        //    逻辑一行不动），不再有可关的开关。
        _NightBoundaryTile(
          l10n: l10n,
          hour: s.nightBoundaryHour,
          minute: s.nightBoundaryMinute,
          onChanged: (int h, int m) => _update(
            s.copyWith(nightBoundaryHour: h, nightBoundaryMinute: m),
          ),
        ),
        _IntTile(
          title: l10n.parent_settings_daily_focus_cap,
          value: s.dailyFocusCap,
          options: const <int>[
            kDailyFocusCapLow,
            kDailyFocusCapMid,
            kDailyFocusCapHigh,
          ],
          onChanged: (v) => _update(s.copyWith(dailyFocusCap: v)),
        ),
        _IntTile(
          // C48（玄参 2026-10-10）：原「每日 App 使用时长」有歧义（看似整个 App，
          // 实际只限花园/商店等娱乐 tab 的累计时长）→ 文案写准。
          title: l10n.parent_settings_daily_app_cap,
          value: s.dailyAppCapMinutes,
          options: kDailyAppCapOptions,
          onChanged: (v) => _update(s.copyWith(dailyAppCapMinutes: v)),
        ),
        _IntTile(
          title: l10n.parent_settings_rest_after,
          value: s.restAfterSessions,
          options: const <int>[1, 2, 3],
          onChanged: (v) => _update(s.copyWith(restAfterSessions: v)),
        ),
        _IntTile(
          title: l10n.parent_settings_rest_minutes,
          value: s.restMinutes,
          options: const <int>[5, 10, 15],
          onChanged: (v) => _update(s.copyWith(restMinutes: v)),
        ),
        const SizedBox(height: 12),
        // C28 少儿护眼休息（玄参 2026-10-04 拍板，口径裁定表 v1 C28 §4）。
        // 注意：这里只有 **3 项** —— 总开关 / 触发间隔 / 是否允许孩子跳过。
        // ⚠️ 刻意**没有「护眼时长」设置项**：单次护眼固定 60 秒（前 30 秒闭眼 + 口令
        // 转眼球、后 30 秒睁眼远眺），玄参拍板「家长端不设、不可调」；时长常量单点
        // 收口在 `kEyeCareDurationSeconds`。加这个开关等于把已拍板的口径改回去。
        _SectionTitle(l10n.parent_settings_section_eyecare),
        _SwitchTile(
          title: l10n.parent_settings_switch_eyecare,
          subtitle: Text(
            l10n.parent_settings_eyecare_subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          value: s.eyeCareEnabled,
          onChanged: (v) => _update(s.copyWith(eyeCareEnabled: v)),
        ),
        _IntTile(
          title: l10n.parent_settings_eyecare_interval,
          value: s.eyeCareIntervalMin,
          options: kEyeCareIntervalOptions,
          onChanged: (v) => _update(s.copyWith(eyeCareIntervalMin: v)),
        ),
        _SwitchTile(
          title: l10n.parent_settings_switch_eyecare_skip,
          subtitle: Text(
            l10n.parent_settings_eyecare_skip_subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          value: s.eyeCareSkipAllowed,
          onChanged: (v) => _update(s.copyWith(eyeCareSkipAllowed: v)),
        ),
        const SizedBox(height: 12),
        _SectionTitle(l10n.parent_settings_section_sound),
        _SwitchTile(
          title: l10n.parent_settings_switch_sound,
          value: s.soundOn,
          onChanged: (v) => _update(s.copyWith(soundOn: v)),
        ),
        _SwitchTile(
          title: l10n.parent_settings_switch_bgm,
          value: s.bgmOn,
          onChanged: (v) => _update(s.copyWith(bgmOn: v)),
        ),
        _SwitchTile(
          title: l10n.parent_settings_switch_dark,
          value: s.themeDark,
          onChanged: (v) => _update(s.copyWith(themeDark: v)),
        ),
        // i18n（B1）：家长端本批只加「语言」入口（对话框式）；其余家长端文案 B2 迁移。
        const _LanguageEntryTile(),
        // 🔴 C79（2026-10-15 玄参拍板）：原「自主模式（孩子自助核销）」开关已
        //    **彻底删除** —— 全仓排查该字段零业务消费点（自主核销从未实现），
        //    实体字段 + DB 列（schemaVersion 25 DROP COLUMN）一并移除。
        const SizedBox(height: 12),
        _SectionTitle(l10n.parent_settings_section_lock),
        ListTile(
          leading: const Icon(Icons.pin),
          title: Text(l10n.parent_settings_reset_pin),
          trailing: const Icon(Icons.chevron_right),
          onTap: _resetPin,
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium),
          title: Text(l10n.parent_settings_grant_title),
          subtitle: Text(l10n.parent_settings_grant_subtitle(
            kParentGiftDaily,
            kParentGiftMonthly,
          )),
          trailing: const Icon(Icons.chevron_right),
          onTap: _grantGift,
        ),
        const SizedBox(height: 12),
        // 「解锁全部功能」已上移到列表最顶部（玄参 2026-10-14 反馈），此处不再重复。
        // C85：原先此处还有一张「专注报告」入口卡 → **已删除**。报告自 C76 起已并入
        // 「记录」tab 的分段（`FocusReportSection`），「记录」tab 底部即入口，
        // 设置页再放一张属于双入口冗余（玄参 2026-10-17 反馈「设置里那张报告卡点
        // 进去还是记录页，多一层」）。故本节只剩删除入口 → 标题改为「数据与隐私」。
        _SectionTitle(l10n.parent_settings_section_data),
        // 隐私政策应用内全文（首启告知 2.0 / C110）：与首启同意页「查看完整隐私
        // 政策」共用 /privacy-policy；PIN 门内入口，家长随时可查（§10.3）。
        _EntryCard(
          icon: Icons.privacy_tip_outlined,
          title: l10n.privacy_policy_title,
          subtitle: Text(l10n.parent_settings_entry_privacy_sub),
          onTap: () => context.push('/privacy-policy'),
        ),
        // 🔴 保留（隐私合规）：本地数据删除权——§10.4 C5 要求家长随时可清空本机数据。
        _EntryCard(
          icon: Icons.delete_forever,
          title: l10n.parent_settings_entry_delete,
          subtitle: Text(l10n.parent_settings_entry_delete_sub),
          danger: true,
          onTap: () => context.push('/parent/delete'),
        ),
        // 🐞 C85 · Debug 专用区：真机预览付费内容（月 / 年报告、热力图、深度报告）。
        // `kDebugMode` 为编译期常量 → release 构建里整段被 tree-shake，
        // 且本分支内的 widget / 文案在 release 包中**完全不存在**（不可见、不可触达）。
        // 🔴 2026-10-19（C95）：截商店图时调试区会入镜 → 显示条件统一走
        // `shouldShowDebugUi`，截图构建（`--dart-define=HIDE_DEBUG_UI=true`）可隐藏；
        // release 恒不显示（debugMode == false → 判据 false），安全性不变。
        if (shouldShowDebugUi(
          debugMode: kDebugMode,
          hideForScreenshots: kHideDebugUi,
        )) ...<Widget>[
          const SizedBox(height: 12),
          _SectionTitle(l10n.parent_settings_section_debug),
          const DebugUnlockSwitch(),
        ],
      ],
        );
      }),
    );
  }
}

/// 「语言」入口行（i18n B1）。
///
/// 家长端本批只加语言入口（对话框式，样式与设置页其它行一致）；其余家长端
/// 文案 B2 迁移。自带页级 [L10nScope]：本页其余部分未迁移，行内文案经内部
/// 上下文取 ARB；弹窗文案在页级 scope 内取好后传参（弹窗纪律）。
class _LanguageEntryTile extends ConsumerWidget {
  const _LanguageEntryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return L10nScope(
      child: Builder(builder: (BuildContext innerContext) {
        final AppLocalizations l10n = AppLocalizations.of(innerContext);
        final AppLanguage current = ref.watch(appLanguageProvider);
        return ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.parent_settings_lang_entry),
          subtitle: Text(LanguagePicker.labelOf(l10n, current)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLanguageDialog(innerContext, ref),
        );
      }),
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
///
/// [subtitle] 为可选补充说明（C28 护眼三项都带一句「这样是什么效果」的说明，
/// 否则家长只看「护眼提醒 / 允许跳过」不知道能管什么）。
class _SwitchTile extends StatelessWidget {
  final String title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title),
        subtitle: subtitle,
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
  final AppLocalizations l10n;
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  const _NightBoundaryTile({
    required this.l10n,
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
      title: Text(l10n.parent_settings_night_title),
      subtitle: Text(l10n.parent_settings_night_subtitle(_fmt(hour, minute))),
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

/// 入口卡（跳转）。[subtitle] 为 Widget，可直接嵌入随状态刷新的组件
/// （如解锁状态 [`PremiumStatusText`]）。
///
/// C78（V2-4）：可选 [gold] 令牌视觉 —— **仅「解锁全部功能」入口传 true**，
/// 复用购买页金系色值（底渐变 `0xFFFFFDF7→0xFFFFF0C9` / 描边 `0xFFE8C56A`
/// 1.5px / 图标金 `0xFFE8A600` / 字 `0xFF6B6252`）；其余入口卡白底逐像素不变。
class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool gold;
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    if (gold) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFFDF7), Color(0xFFFFF0C9)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8C56A), width: 1.5),
        ),
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFFE8A600)),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6B6252),
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: subtitle,
          trailing: const Icon(Icons.chevron_right, color: Color(0xFFE8A600)),
          onTap: onTap,
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: Icon(icon, color: danger ? Colors.red : null),
        title: Text(title,
            style: danger
                ? const TextStyle(color: Colors.red)
                : null),
        subtitle: subtitle,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
