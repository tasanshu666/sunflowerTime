/// 孩子端外壳的路由回台观察者（F150 家长赠予到账提醒）。
///
/// 为什么独立成文件：`app_router.dart` import 了 `child_shell_page.dart`，
/// 而 shell 需要拿到 observer 实例订阅 `RouteAware` —— 放回 router 会形成
/// 环（Dart 允许但极易演化成加载顺序坑）。单例全局共享：
///
///  · `GoRouter(observers: [childShellRouteObserver])` 注册；
///  · shell 在 `didChangeDependencies` 里 `subscribe(this, ModalRoute.of(context)!)`；
///  · 家长天地（push 覆盖在孩子端之上）pop → shell `didPopNext` → 检查
///    「家长赠予到账」未读标记并弹金色提示卡。
///
/// ⚠️ 只为「回孩子端」这一个信号服务，勿复用到别的页面（按需再加观察者）。
library child_route_observer;

import 'package:flutter/widgets.dart';

/// 全局唯一路由观察者（shell 订阅用）。
final RouteObserver<ModalRoute<dynamic>> childShellRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
