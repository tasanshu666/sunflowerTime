# SunFocus S1/S2/S3 Bug 记录表

> 本批 spike 全量 bug / 编译阻塞修复记录。分支：`spike/s1-s2-s3`（本地，未提交）。
> 状态：✅ 已修复 / ⏳ 待真机 / ⚠️ 待裁定

---

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B01 | domain/entities | `reward_template.dart`：`Type 'RewardCategory' not found` | 漏 `import 'enums.dart'` | 补 import | ✅ |
| B02 | domain/entities | `redemption_request.dart`：`RequestStatus undefined` | 漏 `import 'enums.dart'` | 补 import | ✅ |
| B03 | 测试 | `flutter test`：`WebSocketException: Invalid WebSocket upgrade request` | 沙箱 `flutter_tester` 无法连接 | 改用 `dart test`（加 dev dep `test ^1.24.0`，import 改 `package:test/test.dart`） | ✅ 已绕开 |
| B04 | S2 逻辑/单测 | 单测预期错：原以为单笔 130/50 直接自动放行 | 误把"候选阈值"当放行边界；且漏整体池余量校验 | 修正 `decide()` 补 `withinPool`；单测改为以 `min(100/40, 池×25%)` 为实际边界（130/50→pending、100/40→verified） | ✅ |
| B05 | S3 | `onOrientationChanged`：`undefined_method` | 本机 `native_device_orientation 2.1.3` 中它是**方法** | 改为 `.onOrientationChanged().listen(...)`（加 `()`） | ✅ |
| B06 | S3 | `portraitUpDown`：`undefined_enum_constant` | 2.1.3 枚举无此值 | 删除该判断分支，仅判 portraitUp/Down | ✅ |
| B07 | S1 | `Path.addEllipse`：`undefined_method` | 本 Flutter 版本 Path 无该方法 | 改用 `addOval(Rect.fromLTWH(...))` | ✅ |
| B08 | S1/S3 | `withOpacity`：deprecation 警告 | 新版 Flutter 弃用 | 改用 `withValues(alpha: 0.x)` | ✅ |
| B09 | core/constants | `prd_params.dart`：`dangling_library_doc_comments` | 文件级注释缺 `library` 指令 | 首行补 `library prd_params;` | ✅ |
| B10 | S2 口径 | C5 低年段池=200：正文"20" vs 公式"40" 冲突 | 正文疑似笔误 | 实现按**公式 40**。2026-09-15 玄参大人已裁定＝40，无需改码 | ✅ 已裁定 |
| B11 | S1/S3 | 真机渲染 / 常亮 / 帧率 无法本地验证 | ~~本机无 JDK~~（误判：JDK=Android Studio 自带 JBR，可正常打包） | `flutter build apk --debug` → `adb install` 推小米 14 Pro 真机验收 | ✅ 已真机 |
| B12 | S3 | **竖屏保护失灵**：物理转竖屏不弹"确定结束吗？"确认框（真机实测，手机未锁方向） | `onOrientationChanged()` 默认 `useSensor:false`，插件走 OrientationListener：读 `getDisplay().getRotation()` + `configuration.orientation`（均为被 `SystemChrome.setPreferredOrientations` 锁死的 **UI 方向**），且监听的 `ACTION_CONFIGURATION_CHANGED` 广播在 UI 锁定后永不触发 → 流只发 1 次初始横屏值即静默 | `.onOrientationChanged(useSensor: true)`：改用 OrientationEventListener（纯物理传感器，与 UI 锁无关），正确上报 PortraitUp/Down；并删除 `flutter create` 残留的 `test/widget_test.dart` 脚手架计数器测试（`MyApp` 不存在，污染 analyze） | 🔧 已修复待复测 |

---

## 真机验收结果（2026-09-15，小米 14 Pro，debug 包）
| 项 | 结果 |
|---|---|
| S1 四档切换/向日葵渲染/气泡 | ✅ 通过（lvl1 常态 / lvl2 气泡"我去把它放好。" / lvl3 光晕 / lvl4 睁眼+气泡 均正常） |
| S3 常亮稳定性 | ✅ 通过（横屏放置连跑 20 分钟未被省电策略杀） |
| S3 计时 | ✅ 灭屏期间仍在后台计时（墙钟差设计使然：打盹语义=睡着也计入专注）；无漂移 |
| S3 结束回退 | ✅ 20 分钟到点自动返回演示页 |
| S3 竖屏保护 | ❌ 失灵 → B12（根因已定位，修复方案待批准） |

## 汇总
- 已修复：B01–B09（9 项，均编译/单测通过）
- 已裁定/已真机：B10、B11
- 待复测：B12（S3 竖屏保护，已改 `useSensor:true`，等真机复测）
- `flutter analyze`：无 error/warning（仅 12 info）；`dart test`：13/13 通过。

---

# M0 骨架阶段（分支 `m0/skeleton`，2026-09-15）

> M0 = T01–T05（工程脚手架 / 导航 / 加密本地库 / PIN 锁 / 首启同意流）。
> 本批**全部为构建与环境阻塞类问题**，且大多由本机网络隔离引发。

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B13 | 依赖安装 | `flutter pub get` 跑 20 分钟无任何输出，最终 SIGTERM(137) | 本机 **pub 归档下载被限速**（pub.dev API 正常返回 200，但 tar.gz 下载 20s 未完成）；缓存中仅缺 `drift` 本体 | curl 拉 `drift-2.34.0.tar.gz`(16.9MB/3m14s) → 解包进 `~/.pub-cache/hosted/pub.dev/drift-2.34.0/` → `flutter pub get --offline` → Changed 132 dependencies | ✅ |
| B14 | 安卓构建 | `:sqlcipher_flutter_libs:compileDebugJavaWithJavac` → `In order to compile Java 9+ source, please set compileSdkVersion to 30 or above` | 插件自身 `android/build.gradle` **硬编码 `compileSdkVersion 28`**（<30），AGP 拒绝编译 | 根 `android/build.gradle.kts` 对全部 Android 模块统一覆盖为 35。**注意：必须用 `afterEvaluate` 且放在 `evaluationDependsOn(":app")` 之前**——放后面报 `Cannot run Project.afterEvaluate(Action) when the project is already evaluated`；改用 `plugins.withId("com.android.library")` 则因扩展尚未创建而静默失效 | ✅ |
| B15 | 安卓构建 | `Target dart_build failed: Building native assets failed`；hook 尝试下载 `libsqlite3.arm.android.so` 失败：`Proxy failed to establish tunnel (502)` | `sqlite3` 3.x 的原生资产 hook **默认从 GitHub Releases 下载预编译库**，而本机代理封 github.com | `pubspec.yaml` 增加 `hooks.user_defines.sqlite3: { source: system, name_android: sqlcipher }`：不下载不编译，Android 直接加载 `sqlcipher_flutter_libs` 经 Maven 提供的 `libsqlcipher.so`。**副产品：`dart test` 也一并恢复**（macOS 走系统 libsqlite3） | ✅ |
| B16 | 安卓构建 | `Namespace 'eu.simonbinder.sqlite3_flutter_libs' is used in multiple modules and/or libraries: :sqlcipher_flutter_libs, :sqlite3_flutter_libs` → Manifest merger failed | `sqlcipher_flutter_libs` 的 build.gradle **复制粘贴了 `sqlite3_flutter_libs` 的 namespace**，两者同时引入即冲突 | 移除 `sqlite3_flutter_libs` 依赖（本工程走 SQLCipher，普通版冗余） | ✅ |
| B17 | 安卓构建 | `GeneratedPluginRegistrant.java:39: 找不到符号 类 PackageInfoPlugin` | 多次失败构建（编译中途改 compileSdk/hook 配置）留下的**脏产物**，插件类未进入classpath | `flutter clean` + 重新 `pub get --offline` + 重建 | ✅ |

## M0 构建结果
- `flutter analyze`：**无 error / 无 warning**（12 info）。
- `dart test`：**13/13 通过**（S2 用例未受影响）。
- `flutter build apk --debug`：**成功**，产物 167MB。
- APK 内含 `lib/arm64-v8a/libsqlcipher.so`（3.6MB）→ 加密库确实打包进包。
- 小米 14 Pro 安装 **Success**，启动后**进程存活、无 FATAL 异常**。

## M0 已知取舍（非缺陷，需知悉）
1. **实体用 plain class 而非 freezed**：规避 codegen 风险，M1 可切 freezed（架构 §1.1 目标）。
2. **7 个 Repository 中 5 个为 stub**（Focus/Task/Plant/Reward/Tracking 返回空值），真实实现随 M1/M2 落地。
3. **加密库尚未被任何 UI 路径触发**：当前页面只用到 shared_preferences（同意流）与 secure_storage（PIN），
   Drift/SQLCipher 目前仅完成装配与打包，端到端读写待在 M1 首个数据页接入时验证。

---

# M0 真机验收 · 第 1 轮（2026-09-15 晚，小米 14 Pro）

> 玄参大人真机实测反馈（附截图）：整体测试正常，发现 2 处缺陷。

| 项 | 结果 |
|---|---|
| 首启同意流 → 同意 → 孩子端首页 | ✅ 通过 |
| PIN 首次设置 → 进入家长端 | ✅ 通过（首进为「设置并进入」，非校验） |
| 家长端返回孩子端 / 二次进入校验 PIN | ❌ 无返回入口，退不回 → **B19** |
| 打盹屏（S3）进入 | ✅ 可正常进入 |
| 打盹屏进入瞬间行为 | ❌ 竖握手机点入即弹「确定结束吗？再坐一会」卡片 → **B18** |

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B18 | M0/S3 | 竖握手机点进打盹屏，**首帧即弹**「确定结束吗？再坐一会」卡片，不符合「竖屏=中途退出意图」的语义 | B12 改用 `useSensor: true`（物理传感器）后，`OrientationEventListener` 在**订阅瞬间会立刻回调一次当前物理方向**；孩子竖握进入时首帧即 `portraitUp`，而原判定仅有 `isPortrait && !_paused` 一道门控，无任何「进入时机」保护 → 必然误弹 | ① 加「宽限期」3 秒（新常量 `kOrientationGraceSeconds`）抑制订阅首帧与进入瞬间抖动；② 加「武装(arm)」条件：**必须先观察到一次横屏**（`landscapeLeft/Right`）才把竖屏视为退出意图。口径经玄参大人裁定：**采用「见过横屏才触发」，不加长竖屏兜底** | ✅ 已修复待复测 |
| B19 | M0/家长端 | PIN 登录后进入家长端，**无返回按钮、系统返回键也退不回**，导致「退回再进应要求校验 PIN」这条路径无法验证 | `parent_login_page.dart` 登录成功用 `context.go('/parent/home')`。go_router 的 `go` 是**替换路由栈**而非入栈：`/parent` 被替换掉、`/` 也不在栈中 → 家长端首页成为栈底 → AppBar 不渲染返回箭头，系统返回键在此直接退出 App | ① 家长端首页 AppBar 增加显式 `leading` 返回箭头 → `context.go('/')`（回孩子端并清栈，避免回退看到 PIN 页）；② 外层包 `PopScope(canPop: false)` 拦截 Android 返回键 → 同样 `go('/')`，与箭头行为一致 | ✅ 已修复待复测 |

## M0 修复后校验（本轮）
- `flutter analyze`：**无 error / 无 warning**（12 info，回到基线）。
- `dart test`：**13/13 通过**。
- `flutter build apk --debug`：**成功**，已 `adb install -r` 推小米 14 Pro。

---

# M0 真机验收 · 第 2 轮（2026-09-15 深夜，小米 14 Pro）

> 复测反馈：打盹屏竖屏确认框已正常弹出（**B18 修复生效**）；但点「结束」后**黑屏，回不到首页**。

| 项 | 结果 |
|---|---|
| B18 打盹屏不再误弹（竖握进入） | ✅ 通过 |
| 竖屏 → 弹「确定结束吗？」 | ✅ 通过 |
| 选「结束」→ 回首页 | ❌ **黑屏** → **B20** |
| B19 家长端返回 + PIN 二次校验 | ✅ 通过 |

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B20 | M0/导航 | 打盹屏选「结束」后**黑屏**，停在空白页而非回孩子端首页 | 与 **B19 同源**：打盹屏经 `context.go('/focus')` 进入，`go` 是替换路由栈 → `/` 不在栈中，`_finish()` 里的 `Navigator.of(context).pop()` 把**最后一个页面**弹掉 → 黑屏 | ① `_finish()` 改用 `context.go('/')` 回孩子端首页（M1 在此接结算动画）；② 打盹屏外层包 `PopScope(canPop:false)`：栈底按 Android 返回键会直接退出 App，按架构 §1.3「手动退出」与物理竖屏**同路处理** → 抽出 `_requestExit()`（暂停+确认框）供两者共用 | ✅ 已修复待复测 |
| B21 | M0/导航 | S1 预览页 `go('/s1-demo')` 进入同样是栈底，AppBar 无返回入口（**B19 同类，本轮一并预防**） | 同 B19 | AppBar 加显式 `leading` 返回箭头 → `context.go('/')` | ✅ 已修复待复测 |

---

# M0 真机验收 · 第 3 轮（收尾）

> 复测反馈：**全部测试通过**（玄参大人确认），M0 验收关闭。

| 项 | 结果 |
|---|---|
| 打盹屏「结束」→ 回孩子端首页（B20） | ✅ 通过 |
| 打盹屏「再坐一会」→ 续时 | ✅ 通过 |
| 家长端返回箭头 / 系统返回键 / PIN 二次校验（B19） | ✅ 通过 |
| 打盹屏竖握进入不误弹、竖屏才弹确认（B18） | ✅ 通过 |
| S1 预览页返回（B21） | ✅ 通过 |

**状态收口**：B18 / B19 / B20 / B21 全部置为 **✅ 已修复并真机复测通过**。

---

## M0 阶段汇总

- **构建与环境阻塞**：B13–B17（5 项，全部✅）
- **真机验收缺陷**：B18–B21（4 项，全部✅，经两轮真机暴露 → 修复 → 复测通过）
- **总计**：9 项全部关闭，无遗留缺陷
- 收尾校验：`flutter analyze` **无 error / 无 warning**（12 info）；`dart test` **13/13 通过**；`flutter build apk --debug` 成功；小米 14 Pro 全路径验收通过
- 复用沉淀：技能 `flutter-gorouter-orientation-pitfalls`、`flutter-android-apk-build`、`flutter-offline-pub-cache`；经验表 E2 已纠正（本机**可以**打 APK）
