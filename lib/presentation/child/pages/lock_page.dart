/// 夜间锁定页（T11，§6.1 不变式）。
///
/// 向日葵「睡觉中」：夜间边界后不允许开始专注，引导用户明天再来。
/// 夜间边界以 [AppSettings.nightBoundaryHour/Minute] 为**唯一值**（§6.1 不变式），
/// 文案同样跟随该值，不写死（避免家长改边界后文案与真实锁定时刻不一致）。
/// 配色与专注页一致（深色背景）。
library lock_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

class LockPage extends ConsumerWidget {
  const LockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // i18n（B1）：页级 L10nScope + Builder —— 文案取用统一走 scope 内上下文；
    // 闭包参数 `context` 遮蔽外层（下方 `context.go` 行为不变）。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          // 夜间边界唯一值来自 settings（§6.1）；未就绪时回退默认 21:00。
          final int boundary = ref.watch(settingsProvider).value
                  ?.nightBoundaryHour ??
              kNightBoundaryDefaultHour;
          final AppLocalizations l10n = AppLocalizations.of(context);

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              context.go('/'); // 系统返回键/边缘手势 → 回孩子端，而非退 App（B19）。
            },
            child: Scaffold(
              // 显式返回箭头回孩子端（B19 约定）。
              appBar: AppBar(
                title: Text(l10n.child_lock_title),
                backgroundColor: const Color(0xFF1B1B2F),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l10n.shared_back,
                  onPressed: () => context.go('/'),
                ),
              ),
              body: Container(
                color: const Color(0xFF1B1B2F),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.child_lock_sleeping,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFE082),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.child_lock_body(boundary),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFFBDBDBD),
                            ),
                          ),
                          const SizedBox(height: 32),
                          FilledButton(
                            onPressed: () => context.go('/entry'),
                            child: Text(l10n.shared_back),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
