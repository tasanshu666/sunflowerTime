/// 守卫战玩法说明弹窗 + 怪物图鉴解锁（B13，玄参第七/八轮）。
///
/// ## 入口（玄参原话）
/// 「我觉得这个玩法应该有一个说明介绍，点击左侧的花园在中间弹出来玩法说明
/// 介绍，包括小动物的卡片啊什么的，如何攻击啊，相关的写清楚；当然，小怪物
/// 需要遇到才能解锁。」
///
/// ## 结构
/// * 点场景卡左侧房子（`GuardSceneCard` 的 `_HouseSlot` 上加 GestureDetector）
///   ⇒ 居中弹出本弹窗；
/// * 三张**怪物图鉴卡**（馋光鼠 / 食叶虫 / 贪婪鼬）：已遇到 = 图 + 名 + 描述；
///   未遇到 = 剪影（低透明度）+ 锁 + 「还没遇到过」；
/// * 解锁判定 = prefs 字符串列表 [kGuardMetMonstersPrefKey]（存 `m1/m2/m3`），
///   **开战即解锁**（`child_today_page._onGuardCardTap` 落盘战斗态后写入 ——
///   与上屏战局同源：调试剧本覆盖也计入）；
/// * 「怎么打 / 能量点是什么 / 打赢有什么 / 今天不打会怎样」四节正文全走
///   ARB（零 CJK 字面量进 Dart；B13.3 加后两节：能量点来源 + 不打的后果）。
///
/// ## 占位说明
/// 图鉴卡直接用怪物进攻序列的**首帧**（`frame001.webp`，已是正式素材）；
/// 卡片版式等玄参后补美术素材后整卡替换。
library guard_intro_dialog;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart'
    show sharedPreferencesProvider;
import 'package:sunflower_time/core/i18n/enum_l10n.dart' show guardThiefName;
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleMonsterKind;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

/// 「已遇到的怪」prefs 键（字符串列表，值为 `m1` / `m2` / `m3`）。
///
/// 🔴 永久累积（一辈子解锁，不跨天重置）——与 B7 教学浮层的「设备级一次」
/// 同一 prefs 宿主，`DataManagementService.clearAll` 会一并清掉（可接受）。
const String kGuardMetMonstersPrefKey = 'guard.met_monsters.v1';

/// 战斗里出现的怪种 ⇒ 写入「已遇到」（开战即解锁；失败吞掉，绝不阻断开战）。
Future<void> recordMetMonsterKinds(
  Iterable<GuardBattleMonsterKind> kinds,
  SharedPreferences sp,
) async {
  try {
    final Set<String> met =
        (sp.getStringList(kGuardMetMonstersPrefKey) ?? <String>[]).toSet();
    met.addAll(kinds.map((GuardBattleMonsterKind k) => k.id));
    final List<String> sorted = met.toList()..sort();
    await sp.setStringList(kGuardMetMonstersPrefKey, sorted);
  } catch (_) {
    // 解锁写失败 = 图鉴少一格，不影响任何玩法。
  }
}

/// 读「已遇到的怪」（键缺失 / prefs 异常 ⇒ 空集 = 全部未解锁）。
Set<String> _readMetMonsterIds(SharedPreferences sp) {
  try {
    return (sp.getStringList(kGuardMetMonstersPrefKey) ?? <String>[]).toSet();
  } catch (_) {
    return const <String>{};
  }
}

/// 弹出玩法说明（居中卡片；点击遮罩可关）。
///
/// [context] 必须在 `MaterialApp` 内（showGeneralDialog 走 navigator）；
/// l10n 由调用方传入（与 `showGuardResultCard` 同因：弹窗上下文在页级
/// L10nScope 之外，靠默认值会回落中文）。
///
/// [isPremium]（B13.8 能量档位制）：能量点小节正文按权益档位取词 ——
/// 免费「一天最多 1 个」（[AppLocalizations.guard_intro_energy_body_free]）、
/// 付费「一天最多 2 个」（[AppLocalizations.guard_intro_energy_body_premium]）。
/// 缺省 false（免费档），旧调用方零改动。
Future<void> showGuardIntroDialog(
  BuildContext context,
  AppLocalizations l10n, {
  bool isPremium = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.guard_intro_open,
    barrierColor: const Color(0xB31B1206),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder:
        (BuildContext dialogCtx, Animation<double> __, Animation<double> ___) {
      // 🔴 B13.18（玄参 2026-11-12 iPad 反馈「玩法说明卡片没有适应屏幕」）：
      //    卡宽上限 360 / 卡高上限 640 原是手机常量 ⇒ iPad 上一条窄长条。
      //    与守卫链路其余弹层（结算卡 B13.16）同口径：几何 × uiScaleOf，
      //    文字不乘（走系统 textScaler，防双乘）。
      final double ui = uiScaleOf(dialogCtx);
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              key: const Key('guardIntroDialog'),
              constraints: BoxConstraints(
                maxWidth: 360 * ui,
                maxHeight: 640 * ui,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF1),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: _IntroBody(l10n, isPremium: isPremium, uiScale: ui),
            ),
          ),
        ),
      );
    },
  );
}

/// 弹窗正文（Consumer 读 prefs 决定图鉴解锁态）。
class _IntroBody extends ConsumerStatefulWidget {
  final AppLocalizations l10n;

  /// 权益档位（B13.8：能量正文免费 / 付费两套 key，见 [showGuardIntroDialog]）。
  final bool isPremium;

  /// 平板放大倍率（B13.18；手机 = 1.0）。只乘图鉴卡美术几何，文字不乘。
  final double uiScale;

  const _IntroBody(this.l10n, {this.isPremium = false, this.uiScale = 1.0});

  @override
  ConsumerState<_IntroBody> createState() => _IntroBodyState();
}

class _IntroBodyState extends ConsumerState<_IntroBody> {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = widget.l10n;
    final SharedPreferences sp = ref.read(sharedPreferencesProvider);
    final Set<String> met = _readMetMonsterIds(sp);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ① 标题
          Text(
            t.guard_intro_title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B4A00),
            ),
          ),
          const SizedBox(height: 14),
          // ② 怎么打
          _sectionTitle(t.guard_intro_howto_title),
          const SizedBox(height: 6),
          Text(
            t.guard_intro_howto_body,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4A3410)),
          ),
          const SizedBox(height: 14),
          // ③ 能量点是什么（B13.3：来源 + 没有能量点怎么办；🔴 B13.8 档位
          //    感知 —— 免费「一天最多 1 个」/ 付费「一天最多 2 个」两套 key）。
          _sectionTitle(t.guard_intro_energy_title),
          const SizedBox(height: 6),
          Text(
            widget.isPremium
                ? t.guard_intro_energy_body_premium
                : t.guard_intro_energy_body_free,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4A3410)),
          ),
          const SizedBox(height: 14),
          // ④ 打赢有什么
          _sectionTitle(t.guard_intro_reward_title),
          const SizedBox(height: 6),
          Text(
            t.guard_intro_reward_body,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4A3410)),
          ),
          const SizedBox(height: 14),
          // ⑤ 今天不打会怎样（B13.3：次日结算真的扣）
          _sectionTitle(t.guard_intro_risk_title),
          const SizedBox(height: 6),
          Text(
            t.guard_intro_risk_body,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4A3410)),
          ),
          const SizedBox(height: 14),
          // ⑥ 怪物图鉴（三张卡；未遇到 = 剪影 + 锁）
          // 🔴 B13.2：`stretch` 在 SingleChildScrollView 的**无界高度**里会
          // 「BoxConstraints forces an infinite height」硬崩（真机：遮罩变暗、
          // 内容不渲染、无法交互 —— 与结算卡奖励卡区同款坑的第二处）。
          // 套 `IntrinsicHeight` 把高度钉到三卡的 intrinsic 高，等高且永不崩。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final GuardThiefKind kind in GuardThiefKind.values) ...<Widget>[
                  if (kind != GuardThiefKind.values.first) const SizedBox(width: 8),
                  Expanded(child: _monsterCard(kind, met)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ⑦ 关闭
          FilledButton(
            key: const Key('guardIntroOk'),
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE8A600),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              t.guard_tutorial_ok,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF6B4A00),
      ),
    );
  }

  /// 单张图鉴卡（🟡 占位版式：素材 = 怪物进攻序列首帧，等玄参美术）。
  Widget _monsterCard(GuardThiefKind kind, Set<String> met) {
    final AppLocalizations t = widget.l10n;
    final double ui = widget.uiScale; // B13.18：美术几何随平板放大，文字不乘
    final String monsterId = _monsterIdOf(kind);
    final bool unlocked = met.contains(monsterId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0xFFFFF6DE) : const Color(0xFFF2EEE6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked ? const Color(0xFFE8A600) : const Color(0xFFB9AE96),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 52 * ui,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Opacity(
                  opacity: unlocked ? 1.0 : 0.25,
                  child: Image.asset(
                    'assets/guard/monster_${_monsterDirOf(kind)}/frame001.webp',
                    height: 52 * ui,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        SizedBox(height: 52 * ui, width: 52 * ui),
                  ),
                ),
                if (!unlocked)
                  Icon(Icons.lock_rounded,
                      size: 22 * ui, color: const Color(0xFF8A7A66)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            unlocked ? guardThiefName(kind, t) : t.guard_intro_locked,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: unlocked ? const Color(0xFF6B4A00) : const Color(0xFF8A7A66),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            unlocked ? _descOf(kind, t) : ' ',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              height: 1.3,
              color: Color(0xFF8A7A66),
            ),
          ),
        ],
      ),
    );
  }

  /// 贼种 → 怪物编号 id（与 `_kindOfThief` 的映射一致；prefs 里存的就是它）。
  String _monsterIdOf(GuardThiefKind kind) {
    switch (kind) {
      case GuardThiefKind.sunRat:
        return 'm1';
      case GuardThiefKind.leafBug:
        return 'm2';
      case GuardThiefKind.sneakThief:
        return 'm3';
    }
  }

  String _monsterDirOf(GuardThiefKind kind) => _monsterIdOf(kind);

  String _descOf(GuardThiefKind kind, AppLocalizations t) {
    switch (kind) {
      case GuardThiefKind.sunRat:
        return t.guard_intro_desc_sunrat;
      case GuardThiefKind.leafBug:
        return t.guard_intro_desc_leafbug;
      case GuardThiefKind.sneakThief:
        return t.guard_intro_desc_sneakthief;
    }
  }
}
