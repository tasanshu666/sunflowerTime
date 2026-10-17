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
// ⚠️ C76 / C87：`parent_report_page.dart` 曾在此被 import；C76 起 `/parent/report`
// 改为重定向，C87 已把该孤儿页**整个删除**（报告内容唯一实现 = FocusReportSection）。
// 此处保持无 import，切勿再把老页捞回来。
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_delete_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';
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
          // free=1：自由专注（玄参 2026-09-30）——不预设时长、无到时提醒，
          // 孩子自定结束；minutes 透传 0（仅落库 plannedMin=0 的口径标记）。
          final bool free = state.uri.queryParameters['free'] == '1';
          return FocusPage(
            plannedMinutes: free ? 0 : minutes,
            dnd: dnd,
            freeMode: free,
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
        // C76（专注报告 v2）：支持 `?tab=<0..4>&seg=<0|1>` 带参直达。
        //
        // 为什么用 `pageBuilder` 而不是 `builder`：go_router 的 `RouteMatch.pageKey`
        // **只由路由路径生成**（`ValueKey<String>(matchedPath)`，query 不参与）。
        // 家长端内部（设置页「专注报告」入口卡）用
        // `context.go('/parent/home?tab=3&seg=0')` 跳转时 matchedLocation 仍是
        // 同一路径 → Navigator 视为「同一个 page」，只做 `_updateSettings`，
        // **不会**重建页面子树，新参数被丢弃 → 表现为「点了没反应」。
        // 把 `tab`/`seg` 放进 pageKey 后，参数变化 = 新 page，必定按新参数重建
        // （含 `initState`），入口卡一次点击即可落到「记录」tab 的报告段。
        pageBuilder: (BuildContext context, GoRouterState state) {
          final int tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          final int seg =
              int.tryParse(state.uri.queryParameters['seg'] ?? '') ?? 0;
          return MaterialPage<void>(
            key: ValueKey<String>('/parent/home?tab=$tab&seg=$seg'),
            child: ParentHomePage(initialTab: tab, initialSegment: seg),
          );
        },
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
        // C76（专注报告 v2）：报告不再是独立页面，改为「记录」tab 的专注报告段。
        // 路由本身**保留**并重定向，兼容历史深链 / 旧版本文档里的入口。
        redirect: (BuildContext context, GoRouterState state) =>
            '/parent/home?tab=3&seg=0',
      ),
      GoRoute(
        path: '/parent/tasks',
        builder: (context, state) => const ParentTaskConfigPage(),
      ),
      GoRoute(
        path: '/parent/delete',
        builder: (context, state) => const ParentDeletePage(),
      ),
      // 付费墙 · 阶段 3 第二批：一次性买断购买页（从家长端设置页 push 进入）。
      GoRoute(
        path: '/parent/premium',
        builder: (context, state) => const ParentPremiumPage(),
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
