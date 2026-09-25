/// 应用路由（go_router，§1.1 / §5）。
///
/// 孩子端（默认竖屏）与 家长端（本地 PIN 进入）分离；首启未同意 → /consent。
library app_router;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';
import 'package:sunflower_time/presentation/child/pages/entry_page.dart';
import 'package:sunflower_time/presentation/child/pages/lock_page.dart';
import 'package:sunflower_time/presentation/child/pages/rest_page.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/settle_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_home_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_login_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_report_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_delete_page.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ChildShellPage(),
      ),
      GoRoute(
        path: '/entry',
        builder: (context, state) => const EntryPage(),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const LockPage(),
      ),
      GoRoute(
        path: '/rest',
        builder: (context, state) => const RestPage(),
      ),
      GoRoute(
        path: '/focus',
        builder: (context, state) {
          final minutes = int.tryParse(
                state.uri.queryParameters['minutes'] ?? '',
              ) ??
              kFocusDurationDefaultMinutes;
          // dnd 默认开：仅当显式传 '0' 才关闭（F01）。
          final dnd = state.uri.queryParameters['dnd'] != '0';
          // task 可空：从「成长」联动项进入时携带成长项 id（M4 达标后自动结算）。
          final taskId = state.uri.queryParameters['task'];
          return FocusPage(
            plannedMinutes: minutes,
            dnd: dnd,
            taskId: taskId,
          );
        },
      ),
      GoRoute(
        path: '/settle',
        // 结算参数经 go extra 传入（当前会话内即时导航；不做深链持久化）。
        builder: (context, state) =>
            SettlePage(args: state.extra as SettleArgs?),
      ),
      GoRoute(
        path: '/consent',
        builder: (context, state) => const ConsentPage(),
      ),
      GoRoute(
        path: '/parent',
        builder: (context, state) => const ParentLoginPage(),
      ),
      GoRoute(
        path: '/parent/home',
        builder: (context, state) => const ParentHomePage(),
      ),
      GoRoute(
        path: '/store',
        builder: (context, state) => const StorePage(),
      ),
      GoRoute(
        path: '/child/sunlight-history',
        builder: (context, state) => const ChildSunlightHistoryPage(),
      ),
      GoRoute(
        path: '/garden',
        builder: (context, state) => const GardenPage(),
      ),
      GoRoute(
        path: '/parent/report',
        builder: (context, state) => const ParentReportPage(),
      ),
      GoRoute(
        path: '/parent/tasks',
        builder: (context, state) => const ParentTaskConfigPage(),
      ),
      GoRoute(
        path: '/parent/delete',
        builder: (context, state) => const ParentDeletePage(),
      ),
    ],
    // 首启同意流守卫：未同意 → /consent；已同意访问 /consent → /
    redirect: (BuildContext context, GoRouterState state) async {
      final consent =
          await ref.read(settingsStoreProvider).isFirstLaunchConsented();
      final loc = state.matchedLocation;
      if (!consent && loc != '/consent') return '/consent';
      if (consent && loc == '/consent') return '/';
      return null;
    },
  );
});
