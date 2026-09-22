/// 启动初始化（§5 T01）。DB 为 Lazy 打开，无需在此预建连。
///
/// M2 将在此补跑周池重置（`weekKey` → `releaseQueue()`，§8 风险项）。
library bootstrap;

Future<void> bootstrap() async {
  // M0：无需预初始化动作（Drift 走 LazyDatabase，首访即建连）。
}
