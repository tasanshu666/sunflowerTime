/// 首株植物守卫说明卡（B13.15，玄参 2026-11-12 第 5 条）。
///
/// ## 入口（玄参原话）
/// 「种下第一个种子之后，回收今日首页，弹出一个卡片，进行花园守卫的简单
/// 说明，大概就是花园里面有了新的植物，会有小动物偷取，但是不要担心，
/// 向日葵战士会帮你守护花园的。」
///
/// ## 判据（`maybeShowGuardFirstPlantIntro`）
/// * prefs [kGuardFirstPlantIntroSeenPrefKey] 未置（一辈子一次，设备级）；
/// * **花园里有存活植物**（`status != dead`）——没种东西不弹（概念无从谈起）；
/// * 两条都满足 ⇒ 弹卡，**关闭后**置位（写失败吞掉 ⇒ 最坏下次再讲一遍，
///   与 B7 教学浮层同一「宁多勿缺」口径）。
///
/// ## 与 [GuardIntroDialog]（玩法全量说明）的关系
/// 本卡是**引导卡**：只讲一句「有战士守护，别担心」，点击后孩子的注意力
/// 应该被引到花园场景卡上；完整规则（怎么打 / 能量点 / 奖励 / 图鉴）仍在
/// 场景卡左侧房子的入口里。两卡互不替代、互不阻断。
library guard_first_plant_dialog;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart' show PlantStatus;
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 判定并弹出首株守卫说明卡（幂等：弹过 / 没植物 / prefs 异常都静默跳过）。
///
/// 调用方（`child_today_page`）在**进入今日页**时触发 —— 弹窗走 root
/// navigator，页面转圈不影响。[l10n] 必须显式传入（弹窗上下文在页级
/// L10nScope 之外，靠默认值会回落中文）。
Future<void> maybeShowGuardFirstPlantIntro({
  required BuildContext context,
  required AppLocalizations l10n,
  required SharedPreferences sp,
  required PlantRepository plants,
}) async {
  bool seen = false;
  try {
    seen = sp.getBool(kGuardFirstPlantIntroSeenPrefKey) ?? false;
  } catch (_) {
    seen = false; // prefs 读不到 ⇒ 当作没看过（宁多勿缺）。
  }
  if (seen) return;

  final List<Plant> all = await plants.plants();
  final bool hasAlive = all.any((Plant p) => p.status != PlantStatus.dead);
  if (!hasAlive) return; // 还没种东西：不弹也不置位（等真种了再讲）。
  if (!context.mounted) return; // 查库的 async gap 里页面可能已卸载。

  await showGuardFirstPlantIntro(context, l10n);

  // 关闭后才置位：中途杀进程 ⇒ 下次进今日页再讲一遍（可接受）。
  try {
    await sp.setBool(kGuardFirstPlantIntroSeenPrefKey, true);
  } catch (_) {
    // 写失败 = 最坏下次再弹一遍，绝不阻断页面。
  }
}

/// 弹出说明卡（居中、点遮罩可关；版式与 `guard_intro_dialog` 同族）。
Future<void> showGuardFirstPlantIntro(
  BuildContext context,
  AppLocalizations l10n,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.guard_first_plant_title,
    barrierColor: const Color(0xB31B1206),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              key: const Key('guardFirstPlantIntro'),
              constraints: const BoxConstraints(maxWidth: 320),
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 战士胜利立绘（B13.14 胜利横幅同款素材，安心感）。
                    Center(
                      child: Image.asset(
                        'assets/guard/soldier_win.webp',
                        height: 96,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox(height: 96),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.guard_first_plant_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6B4A00),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.guard_first_plant_body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFF4A3410),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('guardFirstPlantOk'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE8A600),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        l10n.guard_tutorial_ok,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
