/// 应用路由（go_router，§1.1 / §5）。
///
/// 孩子端（默认竖屏）与 家长端（本地 PIN 进入）分离；首启未同意 → /consent。
library app_router;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/presentation/child/pages/child_home_page.dart';
import 'package:sunflower_time/presentation/child/pages/focus_page.dart';
import 'package:sunflower_time/presentation/child/pages/s1_demo_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_home_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_login_page.dart';
import 'package:sunflower_time/presentation/shared/consent_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ChildHomePage(),
      ),
      GoRoute(
        path: '/focus',
        builder: (context, state) => const FocusPage(),
      ),
      GoRoute(
        path: '/s1-demo',
        builder: (context, state) => const S1DemoPage(),
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
