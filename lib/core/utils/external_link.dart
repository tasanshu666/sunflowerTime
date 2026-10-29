/// 外部链接跳转的**唯一入口**（F166，玄参 2026-10-29）。
///
/// 为什么单点 + 可覆写变量，而不是页面里直接 `launchUrl(...)`：
///  1. **可测**：单测把 [externalLinkOpener] 换成记录器，就能断言「点了哪个
///     URL」，无需 mock url_launcher 的 platform interface（不引额外依赖、
///     不给 analyze 添 `depend_on_referenced_packages` info）；
///  2. **有兜底**：`launchUrl` 在「设备没有邮件 App / 没有浏览器」时可能抛
///     平台异常，也可能返回 false 而不抛。两条路径都收敛到「返回 `false` →
///     调用方给可手动操作的分因提示」，避免孩子/家长点了毫无反应
///     （本仓 UX 纪律：不可用状态必须给分因提示）；
///  3. **口径统一**：一律 `LaunchMode.externalApplication`（在我们的 App 之
///     外打开），绝不用 in-app browser —— 苹果审核对「应用内打开外部网页却
///     不做内嵌浏览器声明」有 5.x 风险，走系统浏览器最干净。
library external_link;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开外部链接的函数签名（测试替换用）。
typedef ExternalLinkOpener = Future<bool> Function(Uri uri);

/// 当前生效的打开方式。生产恒为 [_launchExternal]；**测试可整体替换**。
///
/// ⚠️ 替换后务必在 `addTearDown` 里还原成 [defaultExternalLinkOpener]，
/// 否则同文件后续用例共享脏状态（本仓已因「全局单例残留」翻过车，见 F155）。
ExternalLinkOpener externalLinkOpener = _launchExternal;

/// 生产实现（测试还原时引用它，禁止再新写一份 `launchUrl` 调用）。
Future<bool> defaultExternalLinkOpener(Uri uri) => _launchExternal(uri);

Future<bool> _launchExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 没有可处理的 App（如未配置邮件账户的 iPad）/ 系统拒绝 → 交由调用方提示。
    return false;
  }
}

/// 组装「联系开发者」的 mailto URI（**纯函数**，无 IO，可直接单测）。
///
/// 🔴 空格必须编码成 `%20` 而不是 `+`：
/// [`Uri`] 的 `queryParameters` 构造器走 `encodeQueryComponent`，会把空格编成
/// `+`；而 RFC 6068 规定 mailto 的 header 值用 percent-encoding，部分邮件客户端
/// 会把 `+` 当**字面加号**显示 —— 正文会变成「请在这行下面+写下你…」。
/// 故此处手工拼接并用 [`Uri.encodeComponent`]。
Uri buildSupportMailUri({required String subject, required String body}) {
  final String query = 'subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}';
  return Uri.parse('mailto:$kSupportEmail?$query');
}

/// 反馈邮件里报告的运行平台（家长排查 bug 时最需要的那一列）。
///
/// 纯函数取参而非内部读 `defaultTargetPlatform`：三条分支都能在单测里直接断言，
/// 不会出现「只测到 macOS 那一条」的假绿。
String supportMailPlatformLabel(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
      return 'iOS';
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}
