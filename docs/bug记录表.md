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

---

# M1 批次一（专注闭环 T06–T10）· 缺陷记录

> 本批首次启用「工程师实现 → QA 独立验证」两段流程，下述 3 条**全部由 QA 在编码期发现并定级**，均未流入真机验收。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B22 | M1/专注引擎 | **离席时段被吞入专注时长**（P1）：真机灭屏（OS 挂起 ticker）期间即便一次 tick 都没有，亮屏后首帧仍把整段离席当 running 计入 | `onAbsent()` / `onPresent()` 未推进 `_lastTick`（而 `resume()` 有）→ 两者不对称；后续 `now - _lastTick` 把离席窗口整段按 running 结算。三重后果：① `actualFocusMin` 注水，可误越 5 分钟门槛；② 结算按注水时长发阳光 → **给离席时间发阳光**（违背用户拍板的灭屏口径）；③ 离席满 300s 的**打断被整段跳过** | 抽出**共享推进内核 `_advance(now)`**：tick 与两个事件入口共用同一套"按当前状态切分时段归属"逻辑（`onPresent` 入口先 `_advance`，把整段离席窗口按 absent 归属并触发唤醒/打断，打断则早退）。**未采用**"仅在事件入口补 `_lastTick`"的朴素方案——那会让打断整段丢失 | ✅ 已修复（QA Round 2 复验通过） |
| B23 | M1/阳光记账 | **产出双源**（P2）：引擎 `rawSunlight` 走精确斜坡积分，结算层却用 `actualFocusMin` 重算 S | `SunlightService.computeRawS` 收 `focusMin` 反推，忽略 10s 回满斜坡 → **每次离席恢复系统性多算 5/60 阳光**，引擎的精确积分被白做 | `computeRawS` 参数改为 `focusSunlight`；`settle()` 改为传 `outcome.rawSunlight`（对外签名不变，调用点无需改） | ✅ 已修复（QA 用例 N1） |
| B24 | M1/口径单点 | 本批新代码 2 处裸字面量，且顺带发现既有常量"定义了却没用" | ① `presence_detector.dart:54` 默认 `Duration(seconds: 3)` 与 `kOrientationGraceSeconds` 孪生；② `focus_engine.dart:308,317` 用 `/60.0` 编码速率；③ **既有**：`math_ext.dart` 分段软顶用 60/90/110/0.5/0.2/79 裸值，而同名常量 `kSoftCapSeg1/Seg2/Seg3`、`kSoftCapDailyMax` 早已存在未被引用；`datetime_ext.dart:29` 的 21 同理 | ①③ 全部改为引用常量（**数值不变**，S=162→79、91.8→75.4、47.6→47.6 三锚点保持）；`autoApproveMonthlyCap` 默认参数改 `double?` 可空 + 内部回落常量；新增 `kSoftCapSeg2Rate` / `kSoftCapSeg3Rate` 到 `prd_params.dart` | ✅ 已修复（QA 复核无数值漂移） |

**证据锚点**

| 缺陷 | 修复前 | 修复后 |
|---|---|---|
| B22 | 在场 10s + 离席 60s（0 tick）+ 恢复 → `actualFocusMin = 71/60` | **11/60** |
| B22 | 离席 300s（0 tick）→ 未打断 | 恢复调用内即 `isFinished / interrupted` |
| B23 | `settle` 用 actualFocusMin 反推 S（多算 5/60） | 账本 `gross` == 引擎 `rawSunlight`；且 `rawS < actualFocusMin × rate` |

**QA 独立验证的其它产出**

- **45 条**新用例（edge 29 + P1 缺陷证据 2 + `_advance` 内核 9 + 结算端到端 5）；其中 2 条曾作为"故意保留的红测"作为缺陷证据，修复后转绿。
- **口径巡检**：本批裸字面量清零；`0.5` / `0.2` / `0.90` 全仓仅剩常量定义处与注释。
- **接线审查**（本机跑不了 UI，以代码审查替代）：`focus_page` 真接引擎与检测器（非"只建不用"）；**B18 / B20 两处旧修复未回退**；路由参数与页面构造参数一致；`focusRepositoryProvider` 已由桩换真实实现。

---

# M1 批次一 · 汇总

- **编码期缺陷**：B22–B24（3 项，全部 ✅ 已修复）
- **真机验收缺陷**：⏳ 待玄参大人执行（验收路径见 `docs/产品开发文档_M1.md` §5 的 11 步）
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（11 info）；`dart test` **67/67 通过**；`flutter build apk --debug` 成功；`adb install -r` 成功；启动进程存活、无 FATAL
- **明确未验证**（不含糊通过）：UI 实际渲染 / 动画帧率 / 常亮是否被国内 ROM 杀 / ticker 是否真被 OS 挂起（此四条须真机）
- **M0 遗留台账**（本批未动，待 M2 清）：见 `docs/软件设计文档_M1.md` §11

---

# M1 批次二（T06–T10 真机验收修复）· 分支 `m1/focus-loop`

> 玄参大人真机实测 M1 批次一 APK，分两轮反馈：首轮 **7 条** → B25–B29 + F01（新功能）；
> 次轮 **3 通过 / 3 失败** → 失败项 B30/B31/B32，第三轮复测全部通过。

## 首轮（7 条反馈）

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B25 | M1/结算 | 横屏1min+竖屏退出后结算「本次专注 1 秒」 | `settle_page.dart` 旧 `_fmtMinutes` 把 `actualFocusMin`（单位=分钟）当**秒**拆 → 1.0 分钟显示"1 秒"。引擎其实正常累计了 60s | 新增顶层纯函数 `formatFocusMinutes(minutes)`：先 `×60` 转总秒再拆「分+秒」；调用点换用，删旧私有方法。**结论：纯显示 bug，引擎无需重构** | ✅ 已修复（次轮复测：6分56秒 显示正确） |
| B26 | M1/在场检测 | 竖屏检测太灵敏，稍晃即弹「再坐一会」 | 原判定 `isPortrait && !_paused` 无「持续时长」门槛 | `presence_detector.dart` 新增 `_portraitSince` + 常量 `kPortraitExitDebounceSeconds=1.5`：竖屏需**连续保持 ≥1.5s** 才触发；横屏清计时、非横非竖忽略 | ✅ 已修复（次轮复测：轻晃不误弹） |
| B27 | M1/亮屏补判 | 灭屏30–60s 亮屏未见欢迎光晕；灭屏2min+ 无唤醒文案 | 灭屏=离席语义（OS 挂起 ticker，无法实时提醒，合理取舍）；亮屏补判偏弱 | `focus_page.dart` lvl3 欢迎时长 2s→3s + 新增「欢迎回来」文字；`sunflower_canvas.dart` 光晕 alpha 0.35→0.5、半径 135→145 | ✅ 已修复（次轮复测：灭屏30s亮屏有「欢迎回来」约3s） |
| B28 | M1/结算 | 结算「从下往上增长进度条」语义不清 | 罐动画语义未对齐「光回罐」叙事 | 仅 `net>0` 显示「光回罐」上涨动画 + "向日葵把光收进罐子里 ☀️" 小字；`net==0/null` 只留「这次太短啦」文案、不显示上涨罐 | ✅ 已修复（次轮复测：手动返回结算+7阳光+阳光特效） |
| B29 | M1/入口 | 入口开音效/BGM 开关但无声 | 音频功能属 M2（T18），本批未接 | 开关 `onChanged:null` 禁用 + 副标题「音频功能即将上线（M2）」，不接 just_audio | ✅ 诚实化（不实现） |
| F01 | M1/新功能 | 入口新增「屏蔽通知（勿扰）」开关（默认开） | 专注期需屏蔽微信等打扰 | 新增 `dnd_controller.dart`(`MethodChannel('sunfocus/dnd')`，`Platform.isAndroid` 守卫) + `MainActivity.kt`(`isDndPolicyGranted/openDndSettings/setDnd` NONE/ALL, try/catch) + `AndroidManifest.xml`(`ACCESS_NOTIFICATION_POLICY`)；入口开关 → `/focus?dnd=1`；进专注启用、结束/dispose 恢复 | ✅ 已实现（B30 初版失效，见下） |

## 次轮（3 失败 → B30/B31/B32，第三轮复测全部通过）

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B30 | M1/DND | 开启勿扰仍收微信弹窗+声音（语音也一样） | 进专注时若未授权，`requestAccess()` 跳设置后即 `setEnabled(true)` 抛 `SecurityException` 被 Kotlin 静默吞 → DND 从未真开；用户从设置返回也**不重查授权** | 三处联动：①`focus_page.dart` 加 `WidgetsBindingObserver`，`resumed` 重查 `isGranted()` 自动 `setEnabled(true)`、未授权显顶部常驻条幅+「去开启」；②`MainActivity.kt` `setDnd` 执行后读 `currentInterruptionFilter` 返回 Dart 自证（`-1`=未生效）+ `Log.d`；③`dnd_controller.dart` `setEnabled` 返回 `int` 并 `debugPrint`，try/catch 不再抛异常只回 -1 | ✅ 第三轮复测通过（微信消息/语音均被屏蔽） |
| B31 | M1/在场检测 | 横→竖静止放 >5s 不弹结束卡片（测3次失败） | 真机证实 `native_device_orientation` **手机静止后不再回调** orientation 事件 → 旧 `_portraitSince` 时长判定依赖连续事件，永远达不成 | `presence_detector.dart` 改 **Timer 到期判定**：arm 后首见竖屏起 `Timer(1.5s)`，到点必触发 `onPortraitIntent`；重复竖屏不重置；landscape/非横非竖取消 timer；加 `_portraitFired` 防一次持有重复弹；`stop()` 取消防泄漏 | ✅ 第三轮复测通过（静止竖放>1.5s 弹框） |
| B32 | M1/结算 | <5 分钟结算向日葵消失（截图中央全黑） | `net==0` 分支把含 `SunflowerCanvas` 的整块换成 `SizedBox.shrink()`，花罐一起藏 | `settle_page.dart` 中央**始终**渲染 `SunflowerCanvas`；`net>0`→celebrating:true+光点+罐涨+小字；`net==0/null`→celebrating:false 静态呼吸花（罐/光点不显示，仅保留「这次太短啦」文案） | ✅ 第三轮复测通过（结算有向日葵） |

## M1 批次二 · 汇总与校验

- **首轮**：B25–B29（5 缺陷）+ F01（1 新功能）全部 ✅
- **次轮**：B30/B31/B32（P1/P1/P2）第三轮复测全部 ✅
- **收尾校验**（次轮修复后）：`flutter analyze` **0 error / 0 warning**（11 info 为 M0 既有 lint）；`flutter test` **73/73 全绿**；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro 第三轮验收全通过
- **5 项口径已裁定**（均保持现状，详见口径裁定表 v1 · C9）：送光基准 / 离席不冻结 / 时长档位 15·20·25·30·45 / 无触摸关闭 / 唤醒恢复瞬间补判。仅文档钉死，M1 无代码改动。
- **仍后置**：T11 防沉迷骨架（分两批）、M2 音频（点3）

---

# M2 真机验收·第 1 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机实测 M2 APK，分两批反馈：首批 **5 条**（B33–B37）+ 导航同步（B38）；
> 次批 **1 条新功能**（F02）。本轮同时锁定两项口径决策：① **定价取消分龄系数 K**；
> ② **孩子端金色阳光 = 余额 −（待核销+排队中）**。均详见口径裁定表 v1 变更记录与 C10。

## 首批（5 条缺陷 + 导航同步）

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B33 | M2/家长端奖励页 | 家长端「奖励」Tab 键盘弹出后 `BOTTOM OVERFLOWED 47px` | `parent_reward_page` 根布局用 `Column`+`Expanded`，键盘弹出后可用高度被压缩、子内容溢出 | 根 `Column`→`ListView`；内层模板列表 `shrinkWrap:true` + `NeverScrollableScrollPhysics()` | ✅ 已修复（待真机） |
| B34 | M2/家长端 | 「每周阳光池预算」设定卡 与「周阳光池」展示卡 分立两张 | 设计把"预算设定"与"池展示"拆成两张独立卡 | 删独立预算卡，重写 `pool_indicator.dart` → `WeeklyPoolCard` 合并卡（预算输入+保存按钮+进度条+「已用 X / 池 Y」+「当前档免确认上限 N」）；`parent_reward_page` 改为 `const WeeklyPoolCard()` | ✅ 已修复（待真机） |
| B35 | M2/周阳光池 | 预算设 600 保存成功，但展示卡仍显示 400 不刷新 | ①`WeeklyPoolService.pool()` 对已存在行直接返回旧快照 budget；②`FutureBuilder` 的 `initState` future 永不重载 | ①新增 `updateBudget(now, budget)`：仅替换当周池 budget，保留 `used/autoReleased/resetAt`；不存在则新建；②保存后 `setState(() => _future = _load())` + 自增 `economyRevisionProvider` | ✅ 已修复（待真机） |
| B36 | M2/定价 | 家长设价 20，孩子端显示/扣 30 | 消耗侧价 = `baseCost × 分龄系数 K`（高年级 K=1.5）→ 20×1.5=30 | **2026-09-21 玄参大人拍板取消分龄系数 K**：`_priceFor` 与 `store_page` 均直接用 `baseCost`；删 `math_ext.applyAgeTierK`；`k`/`ageTierK()` 保留但生产定价链路不得调用（见 C10） | ✅ 已修复（待真机） |
| B37 | M2/展示口径 | 孩子端兑换后右上角金色阳光不变（应 = 余额 − 兑换值，如 600−50=550） | `store_page` 读账本余额，pending/queued 按 §7.4 不变式**不扣账本** → 仅展示口径未做减法 | 金色改为 `balance - pendingTotal`（pending+queued 均计入，≥0 截断）；并补「待核销 N」灰色小字 | ✅ 已修复（待真机） |
| B38 | M2/导航 | 孩子端经 `go` 进入的栈底页无系统返回键 | 同 M0 B19/B20：`go` 替换路由栈 → 栈底页 `PopScope` 未拦截 Android 返回键 | 孩子端相关栈底页补 `PopScope(canPop:false)` + 显式返回入口 | ✅ 已修复（待真机） |

## 次批（F02 新功能）

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F02 | M2/新功能 | 多次兑换的奖励卡片显示「本周可兑换次数」：N=3→「可兑换次数为3」、N=1→「仅兑换一次」；且按钮应**真正按次数放行**（而非兑1次就灰） | 原冷却用全局阈值 `kCooldownWeeklyDefault=1`，**不认每个模板的 `frequencyLimitPerWeek`** → 设"每周3次"实际只能兑1次就灰 | ①`RedemptionOrchestrationService._onCooldown` 改用 `t.frequencyLimitPerWeek`（≤0 视为不限次数，永不冷却）；②`store_page` 冷却循环按各模板 `frequencyLimitPerWeek` 放行；③`reward_card` 新增 `weeklyLimit` 字段 + 卡片文案（N≥2「可兑换次数为 N」/ N==1「仅兑换一次」/ N≤0「不限次数」） | ✅ 已实现（待真机） |

## M2 第 1 轮 · 汇总与校验

- **首批**：B33–B37（5 缺陷）+ B38（导航同步）全部 ✅
- **次批**：F02（1 新功能）✅
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（31 info 为既有 lint）；`flutter test` **163/163 全绿**；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（验收路径由玄参大人真机执行）
- **两项口径决策（已落地代码）**：
  1. 定价不再叠加分龄系数 K（显示价 = 扣费价 = 家长设定价 `baseCost`）；
  2. 金色阳光 = 账本余额 −（待核销 + 排队中），pending/queued 不真扣账本/池（守 §7.4 不变式）。
- **明确未验证**（不含糊通过）：UI 实际渲染 / 卡片次数文案真机观感 / 键盘溢出复测 / 周池预算刷新复测（此四条须真机，由玄参大人执行）

---

# M2 真机验收·第 2 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机复测第 1 轮 APK 后新增两条反馈：孩子端卡片次数未随消耗递减；家长端模板卡不显示可兑换次数。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F03 | M2/孩子端商店 | 设「吃冰棍」限领 3 次，兑换 1 次并核销后，卡片仍显示「可兑换次数为 3」（应递减为 2） | 卡片用**静态** `frequencyLimitPerWeek` 展示，未扣本周已领次数 | `reward_card` 新增 `weeklyUsed` 字段；展示文案改用共享函数 `weeklyRedeemLabel(limit, used)`（`lib/domain/entities/reward_template.dart`）：按「剩余 = limit − cooldownCount」渲染（N≥2「可兑换次数为 N」/ N==1「仅可兑换 1 次」/ N≤0 隐藏）；`store_page` 把 `cooldownCount` 作为 `weeklyUsed` 传入 | ✅ 已实现（待真机） |
| F04 | M2/家长端奖励页 | 家长端模板卡片不显示可兑换次数，时间长忘了设了几条 | 家长 `ListTile` 副标题只显示分类，未含 `frequencyLimitPerWeek` | `parent_reward_page` 模板 `ListTile` 副标题追加 `weeklyRedeemLabel(limit, 0)`（用配置值，即 used=0），与 child 端共用同一函数，口径一致 | ✅ 已实现（待真机） |

## M2 第 2 轮 · 校验

- **新增单测**：`test/domain/reward_template_test.dart`（纯函数 `weeklyRedeemLabel` 9 断言，覆盖不限/限1/限≥2/领完隐藏/边界）。
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（31 info）；`flutter test` **168/168 全绿**（163 基线 + 5 新）；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（待真机复测）。
- **未提交**（等玄参大人真机复测通过后授权再 push `m2/economy`，不合 main）。

---

# M2 真机验收·第 3 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机复测第 2 轮 APK：孩子端卡片仍显示「可兑换次数为 3」（核销 1 次后未变 2）；家长端已能显示限领值，但核销后也未递减。
> **根因**：第 2 轮只接好了「展示口径」，却漏了最底层——**冷却计数从未被写入**。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F03（根因） | M2/冷却计数 | 兑换落单后 `cooldownCount` 恒为 0，导致卡片剩余次数永远 = 限领值、且 `_onCooldown` 闸门失效 | `RewardLocalRepository.createRequest` 只 `insert` 兑换申请，**从不调用** `CooldownCounterDao.bump()`（全仓无任何调用点）；而测试 mock 的 `createRequest` 会自行 +1，掩盖了生产缺失 | `RewardLocalRepository.createRequest` 落单后调用 `cooldownCounterDao.bump(templateId, CooldownPeriod.weekly)`（与 `redemption_orchestration_test` 的 Fake 行为对齐）；`createRequest` 仅被 `submit()` 调用，无其它路径污染 | ✅ 已修复（待真机） |
| F04（动态） | M2/家长端奖励页 | 家长端核销 1 次后，模板卡应显示「可兑换次数为 2」而非静态 3 | 第 2 轮家长端用 `weeklyRedeemLabel(limit, 0)`（静态）；未取本周已领次数，也未随核销刷新 | `parent_reward_page._load` 逐模板取 `cooldownCount(weekly)` 存 `_weeklyUsed`；展示改 `weeklyRedeemLabel(limit, _weeklyUsed[t.id] ?? 0)`；`initState` 监听 `economyRevisionProvider` → 孩子兑换 / 家长核销后自动重算 | ✅ 已修复（待真机） |

## M2 第 3 轮 · 校验

- **新增回归测试**：`test/m2/reward_dao_test.dart`「落单即 bump 本周冷却计数」组（真实内存 Drift 库，验证同模板落单 N 次→cooldownCount=N、不同模板独立）。锁死本根因，避免再次回潮。
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（32 info）；`flutter test` 全绿（168 + 2 新 = 170，含新回归测试）；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（待真机复测）。
- **未提交**（等玄参大人真机复测通过后授权再 push `m2/economy`，不合 main）。

---

# M2 真机验收·第 4 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机复测第 3 轮 APK，三点反馈：①家长端奖励页面报错（崩溃）；②家长端确认核销 → 孩子端核减为 1（逻辑正确，无需改）；③家长端点「拒绝」后孩子端阳光虽返回，但可兑换次数仍减了 1（错误）。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F05 | M2/家长端奖励页 | 家长端奖励页面打开即报错（崩溃，附截图） | 第 3 轮在 `parent_reward_page` 的 `initState` 中调用 `ref.listen(...)`，违反 riverpod 2.6.1 铁律（`ref.listen` 仅允许在 `build()` 内调用，否则运行时断言崩溃） | 改用 `ref.listenManual(economyRevisionProvider, (_, __) { if (mounted) _load(); })`（返回 `ProviderSubscription`，专用于 `State.initState` 场景） | ✅ 已修复（待真机） |
| — | M2/核销同步 | 家长端确认核销 → 孩子端商城核减为 1（吃冰棍限领 3、核销 1） | 无（第 3 轮已修，本次真机确认正确） | 不改 | ✅ 已确认正确 |
| F06 | M2/拒绝回流 | 家长端点「拒绝」后，孩子端阳光原路返回（正确），但可兑换次数仍减了 1（错误） | 落单时 `createRequest` 已 `bump` 本周冷却计数（D4）；但 `reject()` 只把状态置 `rejected`，**未回退该计数** → 剩余次数被无端占掉一次，孩子后续可兑换次数凭空少 1 | `RewardRepository` 新增 `decrementCooldown(templateId, window)`；`CooldownCounterDao.decrement` 用 `UPDATE ... SET used_count = MAX(0, used_count-1)`（下限 0）；`RewardLocalRepository` 实现；`RedemptionOrchestrationService.reject()` 在定位请求后调用 `decrementCooldown(req.templateId, CooldownPeriod.weekly)`，使「被拒不占次数」 | ✅ 已修复（待真机） |

## M2 第 4 轮 · 校验

- **新增回归测试**：`test/m2/redemption_orchestration_test.dart` reject 组新增 `(g4) 拒绝回流 → 本周冷却计数回退 1`（限领 3 落单 2 次→cooldown=2，拒绝 1→cooldown 回退为 1 且待处理列表仅剩 1 笔）。锁死 F06 不变式。
- **测试 Fake 同步**：`redemption_orchestration_test` Fake 与 `store_page_test` 两个 Fake 均补齐 `decrementCooldown` 实现（map 计数 `clamp(0,...)`），否则编译不过。
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（33 info，均为既有 lint hint）；`flutter test` **171/171 全绿**（170 基线 + 1 新 g4）；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（`f05bbc46`）成功（待真机复测）。
- **未提交**（等玄参大人真机复测通过后授权再 push `m2/economy`，不合 main）。
