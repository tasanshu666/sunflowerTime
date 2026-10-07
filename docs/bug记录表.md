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
| B33 | M2/家长端奖励页 | 家长端「奖励」Tab 键盘弹出后 `BOTTOM OVERFLOWED 47px` | `parent_reward_page` 根布局用 `Column`+`Expanded`，键盘弹出后可用高度被压缩、子内容溢出 | 根 `Column`→`ListView`；内层模板列表 `shrinkWrap:true` + `NeverScrollableScrollPhysics()` | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| B34 | M2/家长端 | 「每周阳光池预算」设定卡 与「周阳光池」展示卡 分立两张 | 设计把"预算设定"与"池展示"拆成两张独立卡 | 删独立预算卡，重写 `pool_indicator.dart` → `WeeklyPoolCard` 合并卡（预算输入+保存按钮+进度条+「已用 X / 池 Y」+「当前档免确认上限 N」）；`parent_reward_page` 改为 `const WeeklyPoolCard()` | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| B35 | M2/周阳光池 | 预算设 600 保存成功，但展示卡仍显示 400 不刷新 | ①`WeeklyPoolService.pool()` 对已存在行直接返回旧快照 budget；②`FutureBuilder` 的 `initState` future 永不重载 | ①新增 `updateBudget(now, budget)`：仅替换当周池 budget，保留 `used/autoReleased/resetAt`；不存在则新建；②保存后 `setState(() => _future = _load())` + 自增 `economyRevisionProvider` | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| B36 | M2/定价 | 家长设价 20，孩子端显示/扣 30 | 消耗侧价 = `baseCost × 分龄系数 K`（高年级 K=1.5）→ 20×1.5=30 | **2026-09-21 玄参大人拍板取消分龄系数 K**：`_priceFor` 与 `store_page` 均直接用 `baseCost`；删 `math_ext.applyAgeTierK`；`k`/`ageTierK()` 保留但生产定价链路不得调用（见 C10） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| B37 | M2/展示口径 | 孩子端兑换后右上角金色阳光不变（应 = 余额 − 兑换值，如 600−50=550） | `store_page` 读账本余额，pending/queued 按 §7.4 不变式**不扣账本** → 仅展示口径未做减法 | 金色改为 `balance - pendingTotal`（pending+queued 均计入，≥0 截断）；并补「待核销 N」灰色小字 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| B38 | M2/导航 | 孩子端经 `go` 进入的栈底页无系统返回键 | 同 M0 B19/B20：`go` 替换路由栈 → 栈底页 `PopScope` 未拦截 Android 返回键 | 孩子端相关栈底页补 `PopScope(canPop:false)` + 显式返回入口 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

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
- **已提交**：commit `645c89b` 已推 `origin/m2/economy`（不合 main）。

---

# M2 真机验收·第 3 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机复测第 2 轮 APK：孩子端卡片仍显示「可兑换次数为 3」（核销 1 次后未变 2）；家长端已能显示限领值，但核销后也未递减。
> **根因**：第 2 轮只接好了「展示口径」，却漏了最底层——**冷却计数从未被写入**。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F03（根因） | M2/冷却计数 | 兑换落单后 `cooldownCount` 恒为 0，导致卡片剩余次数永远 = 限领值、且 `_onCooldown` 闸门失效 | `RewardLocalRepository.createRequest` 只 `insert` 兑换申请，**从不调用** `CooldownCounterDao.bump()`（全仓无任何调用点）；而测试 mock 的 `createRequest` 会自行 +1，掩盖了生产缺失 | `RewardLocalRepository.createRequest` 落单后调用 `cooldownCounterDao.bump(templateId, CooldownPeriod.weekly)`（与 `redemption_orchestration_test` 的 Fake 行为对齐）；`createRequest` 仅被 `submit()` 调用，无其它路径污染 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F04（动态） | M2/家长端奖励页 | 家长端核销 1 次后，模板卡应显示「可兑换次数为 2」而非静态 3 | 第 2 轮家长端用 `weeklyRedeemLabel(limit, 0)`（静态）；未取本周已领次数，也未随核销刷新 | `parent_reward_page._load` 逐模板取 `cooldownCount(weekly)` 存 `_weeklyUsed`；展示改 `weeklyRedeemLabel(limit, _weeklyUsed[t.id] ?? 0)`；`initState` 监听 `economyRevisionProvider` → 孩子兑换 / 家长核销后自动重算 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

## M2 第 3 轮 · 校验

- **新增回归测试**：`test/m2/reward_dao_test.dart`「落单即 bump 本周冷却计数」组（真实内存 Drift 库，验证同模板落单 N 次→cooldownCount=N、不同模板独立）。锁死本根因，避免再次回潮。
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（32 info）；`flutter test` 全绿（168 + 2 新 = 170，含新回归测试）；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（待真机复测）。
- **已提交**：commit `645c89b` 已推 `origin/m2/economy`（不合 main）。

---

# M2 真机验收·第 4 轮（2026-09-21，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机复测第 3 轮 APK，三点反馈：①家长端奖励页面报错（崩溃）；②家长端确认核销 → 孩子端核减为 1（逻辑正确，无需改）；③家长端点「拒绝」后孩子端阳光虽返回，但可兑换次数仍减了 1（错误）。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F05 | M2/家长端奖励页 | 家长端奖励页面打开即报错（崩溃，附截图） | 第 3 轮在 `parent_reward_page` 的 `initState` 中调用 `ref.listen(...)`，违反 riverpod 2.6.1 铁律（`ref.listen` 仅允许在 `build()` 内调用，否则运行时断言崩溃） | 改用 `ref.listenManual(economyRevisionProvider, (_, __) { if (mounted) _load(); })`（返回 `ProviderSubscription`，专用于 `State.initState` 场景） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| — | M2/核销同步 | 家长端确认核销 → 孩子端商城核减为 1（吃冰棍限领 3、核销 1） | 无（第 3 轮已修，本次真机确认正确） | 不改 | ✅ 已确认正确 |
| F06 | M2/拒绝回流 | 家长端点「拒绝」后，孩子端阳光原路返回（正确），但可兑换次数仍减了 1（错误） | 落单时 `createRequest` 已 `bump` 本周冷却计数（D4）；但 `reject()` 只把状态置 `rejected`，**未回退该计数** → 剩余次数被无端占掉一次，孩子后续可兑换次数凭空少 1 | `RewardRepository` 新增 `decrementCooldown(templateId, window)`；`CooldownCounterDao.decrement` 用 `UPDATE ... SET used_count = MAX(0, used_count-1)`（下限 0）；`RewardLocalRepository` 实现；`RedemptionOrchestrationService.reject()` 在定位请求后调用 `decrementCooldown(req.templateId, CooldownPeriod.weekly)`，使「被拒不占次数」 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

## M2 第 4 轮 · 校验

- **新增回归测试**：`test/m2/redemption_orchestration_test.dart` reject 组新增 `(g4) 拒绝回流 → 本周冷却计数回退 1`（限领 3 落单 2 次→cooldown=2，拒绝 1→cooldown 回退为 1 且待处理列表仅剩 1 笔）。锁死 F06 不变式。
- **测试 Fake 同步**：`redemption_orchestration_test` Fake 与 `store_page_test` 两个 Fake 均补齐 `decrementCooldown` 实现（map 计数 `clamp(0,...)`），否则编译不过。
- **收尾校验**：`flutter analyze` **0 error / 0 warning**（33 info，均为既有 lint hint）；`flutter test` **171/171 全绿**（170 基线 + 1 新 g4）；`flutter build apk --debug` 成功；`adb install -r` 推小米 14 Pro（`f05bbc46`）成功（待真机复测）。
- **已提交**：commit `645c89b` 已推 `origin/m2/economy`（不合 main）。

---

# M3 孩子端 / 家长端导航改版（2026-09-22，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机反馈原文：
> 「关于家长页面的 tab 栏，我得说它在顶部，并不是在底部。确实变成了 5 个。任务栏挪在了外面，正确」
> 「家长页改为了 tab 栏了，孩子页是不是也得改为 tab 栏了，而且首页的四档反馈预览也该删除了」
> 「孩子端的导航应该是**今日、任务、花园、商店、我的**」
>
> 本轮为**需求类**（非缺陷）。孩子端 tab 栏不是新增需求、是**补做**：`docs/架构设计_SunFocus_MVP.md:305` 原设计即 `home_page.dart # 今日状态卡+底部导航`。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F07 | M3/家长端导航 | 家长端 5 个 tab 在 **AppBar 顶部** `TabBar`，玄参预期在**屏幕底部** | 原实现用 `AppBar.bottom: TabBar` + `TabBarView` | 改屏幕底部 `NavigationBar`（5 tab：**今日 / 奖励 / 成长 / 夸夸台 / 设置**）+ `IndexedStack`（切 tab 保活，替代 `TabBarView`）。死守 B19/B20 三项不得回退：`PopScope(canPop:false)` 拦返回键 + AppBar 返回箭头 + `parentThemeFor` 深色皮肤 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F08 | M3/孩子端导航 | 孩子端仍是 M0 占位首页（竖排按钮：开始专注 / 家长天地 / 阳光商店 / 我的花园 / DEBUG 加阳光），商店与花园靠 `push` 进入，**无 tab 栏** | 孩子端底部导航在设计里有、工程里没做 | 新建 `child_shell_page.dart`（底部 `NavigationBar` + `IndexedStack`，5 tab：**今日 / 成长 / 花园 / 商店 / 我的**，AppBar 标题随 tab 变、actions 保留「家长天地」）+ `child_today_page.dart` / `child_task_page.dart` / `child_profile_page.dart`；`garden_page` 与 `store_page` 加 `embedded` 复用（商店余额从 `AppBar.actions` 抽为内联 `_BalanceChip`，避免「看不到余额」复现）；`app_router.dart` 的 `/` 改指 `ChildShellPage`；旧 `child_home_page.dart`（含首页「四档反馈预览 / S1」入口）**整文件删除**，`/s1-demo` 路由与 `S1DemoPage` 保留；B4/B5 通知逻辑（`_checkVerifiedNotices` / `_checkRejectedNotices` / `_checkAllNotices` + `economyRevisionProvider` 监听）整段迁入壳页 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F09 | M3/术语统一 | 「任务」听起来像要干活（玄参） | 用户可见文案与产品术语不一致 | 用户可见「任务」→「成长」，两端一致：底部 tab、家长端配置页（成长配置 / 新增·编辑成长项 / 成长项名称）、孩子端进度（今日成长 x/y）、分区（每日成长 / 每周成长，`weeklyCount==0` 时整段不渲染）、打卡按钮（我做到了 / 已做到）、空态（今天没有成长项，去玩吧 🌻）、成功提示（太棒了！+X 阳光）、领域层异常文案。**刻意不改**：`Task` 实体 / `TaskCheckInService` / `checkIn()` / 文件名 / 路由 `/parent/tasks`（大范围重命名风险高收益低，已在领域层文件头加「术语约定」注释说明）；**刻意不改**：账本字段 `refType='task_checkin'`（是**数据标识不是文案**，改了会对不上历史账本） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

## M3 导航改版轮 · 校验

- **新增回归测试**：`test/nav/nav_structure_test.dart` **6 条 widget 测试**（断言两端底部导航项数与文案顺序、初始选中项、`IndexedStack` 存在、`TabBar` 不存在、「四档反馈预览」文字不出现、家长端 `PopScope.canPop==false` + 返回箭头 + `parentThemeFor` 主题；并用注入数据证明「家长核销 / 拒绝」弹窗真的弹出）。
- **收尾校验（本阶段）**：`flutter analyze` **0 error / 0 warning**（55 条 info 级既有 lint）；`flutter test --no-pub` **207 passed 全绿**（M2 第 4 轮 171 之后、M3 导航改版阶段的数字）。
- **口径裁定（本轮新增，玄参拍板）**：完美日只统计 `isDaily`（`repeatRule` 为 null/'daily'）的成长项。「每周」项仍每天列出、仍可打卡，但**不计入完美日**——`repeatRule` 只有 null/'daily'/'weekly' 三值且**无星期信息**（实体注释自写「（占位）」），玄参裁定不改数据模型，避免一个没做的周任务把完美日永远卡死。`TodayTaskBoard.total/doneCount/allDone` 语义 = **「今日必做成长项的进度」，不是列表可见行数**（已写入类注释）；新增 `weeklyCount` 供 UI 分区。
- **已提交**：随 commit **`34e1541`**（`m2/economy`）；同日 `--no-ff` 合回 `main` → 合并提交 **`421df23`**。装包设备小米 14 Pro **`f05bbc46`**。

---

# M3 真机验收·4 类孩子端反馈修复轮（2026-09-22，小米 14 Pro，分支 `m2/economy`）

> 玄参大人真机实测导航改版 APK 后的 4 类反馈（完美日加成去留 / 两端口径不一致 / 联动项奖励家长还能改 / 植物培养没有过程感），经 AskUserQuestion 由玄参逐条拍板。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F10 | M3/奖励口径 | 完美日 ×1.5 让同一个成长项的奖励是**不确定值**，家长算不清 | 原设计把「完美日系数」叠加在成长项奖励上 | **玄参拍板移除**：完美日仅留徽章语义，不再叠加系数；`task_checkin_service._rewardFor` 移除系数并删 `app_constants` 残留导入 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F11 | M3/两端口径 | 「阅读 20 分钟」在**孩子端预览显示 12**、结算页 / 家长卡显示的是别的数字 | `_rewardFor` 在**孩子端预览取基础值**、**结算页与家长卡取含 ×1.5 的 `sunlightGross`**，两条口径并存 | ×1.5 移除后三端统一取 `Task.effectiveSunlightReward`（单点收口，禁止各处复写） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F12 | M3/联动项定价 | 家长可任意调高联动成长项的奖励 → 存在刷分空间 | 联动项奖励读家长设值 `sunlightReward` | **玄参拍板**：联动项（`requiresFocus == true`）奖励**固定 = 最少专注分钟 × 40%**（`kTaskRewardRatio = 0.4`），**家长不再可调**；公式单点收口在 `Task.rewardCapFor(int)` / `Task.rewardCap` / `Task.effectiveSunlightReward`（编辑器与领域结算共用同一口径）。非联动项保持家长原值（`kTaskRewardDefault=8` / `Min=5` / `Max=15`）。影响面：种子联动项「完成学校作业」「练习数学口算」（均 15 分钟 / 设 12）生效值 **12 → 6**（15×0.4）；「阅读 20 分钟」非联动 → 仍 12。编辑器联动项锁死文案「奖励固定=专注N分钟×40%=X☀」，奖励滑杆 min/max 随分钟动态变化、下调时自动夹回（`min == max` 时 `divisions` 必须传 `null`，否则断言崩）。历史超标数据：编辑器打开即显示夹回后的合法值，但**数据库原值不动** | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F13 | M3/植物培养 | 植物培养没有过程感（玄参当日进一步升级为 V2，见 F23–F25） | 原成长参数下浇水 / 施肥增量过大、自动成长偏快 | 本轮先改为**固定增量**：浇水 **+12%**（`kPlantWaterProgressGain=0.12`）、施肥 **+25%**（`kPlantFertilizeProgressGain=0.25`），按钮明示；自动成长乘 `kPlantAutoGrowthScale=0.2` 缓速；卡面显示「距下一阶段还需约 N 次」。**同日被植物成长 V2（F23–F25）覆盖**：+12% / +25% → **+1% / +5%**，`kPlantAutoGrowthScale` 0.2 → **1.0** | ✅ 已修复（待真机，同日已被 V2 覆盖） |

## M3 4 类反馈轮 · 校验

- **测试同步（本轮必然连带）**：`adversarial_v1_v10_test.dart` V7c/V7d 的 ×1.5 断言改固定值（9 → 6）；`task_checkin_test.dart` / `adversarial_task_checkin_test.dart` 旧的 `min(设值, 封顶)` 口径改「固定 = 分钟 × 40%」（如 reward12 @45min → **18**），软顶 / 余额数字同步改；抽象 `SunlightRepository.all()` 拖出 8 个测试 fake 缺实现 → 全部补齐；`daos.dart` 的 `allDesc()` 原用未引入的 `Ordering` 类 → 改 `select().get()` 后 Dart 端 `sort` 降序（ts 为 unix 秒 INTEGER，比较无碍）。
- **收尾校验（本阶段）**：`flutter analyze` **0 error**（58 条 info/warning 为既有 lint，含 2 处 `app_constants` unused_import，未删以免误伤其他常量）；`flutter test` **279 passed 全绿**（含 m4 服务 84 条 + 全仓）；`flutter build apk --debug` **✓ Built**（compileSdk 强制 35）。
- **装包**：本轮 `adb -s f05bbc46 install -r` **失败**（`adb devices` 为空，手机未连；重启 daemon 仍无设备）。APK 就绪于 `build/app/outputs/flutter-apk/app-debug.apk`，后续补装（见「花园扩容『暗扣 400』修复轮」的装包记录）。
- **已提交**：随 commit **`34e1541`**。

---

# M4 经济漏洞修复轮（2026-09-22，玄参报漏洞 + 代码审计，分支 `m2/economy`）

> 玄参大人原话：「成长这个地方的任务，比如数学专注 10 分钟，是不是需要和专注联动？……如果不联动，孩子完成任务，点击我做到了，阳光直接核销，**没有家长监管，是不是孩子容易不做这个事情，也会刷分**？」
>
> 核实属实：玄参报的 4 处 + 代码审计挖出的 4 处 = **7 + 1 个漏洞**（第 7 条为主理人复核时的补发现）。全部修在 `lib/domain` + `lib/data` 内。
>
> 前置事实：本轮之前 `SunlightService.computeRawS/settle` 的 `taskCount` / `perfectDayCoefficient` 参数，**唯一调用点 `focus_page.dart` 从未传值** → 原设计意图（PRD §4.5 `S = 专注分钟×1 + 任务数×12×完美日系数`）自 M2 起一直断着。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F14 | M4/家长核销 | **[P0]** 家长连点两次「确认发放」→ 阳光**双倍入账** | `verifyCheckIn` 是「读记录 → 改状态 → 写账本」的**读-改-写非原子**序列，第二次读到的是尚未更新的旧状态 | DAO 层 **CAS**：新增 `TaskDao.resolveCheckInIfStatus`（`update ... where id=? and status=?`，**以受影响行数判成败**；状态用 `int` 传，避免数据层 import 领域枚举）；抢占失败即抛异常、放弃入账。`_appendLedger` 再加一层 `countByRefTypeAndRefIdOnDay('task_checkin', checkInId, day)` 兜底去重 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F15 | M4/联动校验 | **[P1]** 一次专注会话解锁**多个**联动成长项（一鱼三吃） | 校验只看「当日**存在**一次 `actualFocusMin >= minFocusMin` 的专注」，**不区分归属**、也不检查该专注是否已被别的成长项用掉 | 会话复用守卫：当日已存在 `sessionId == session.id && status == verified` 的打卡 → 抛「这次专注已经结算过成长项啦」 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F16 | M4/跨天 | **[P1]** 用**昨天的**专注结算今天的成长项 | `settleFocusLinked` 未校验专注会话的日期归属 | 跨天守卫：`dayKey(session.start) != dayKey(now)` → 抛异常 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F17 | M4/完成度口径 | **[P2]** `rejected` 被当成「已做到」，还能凑完美日 | 取当日打卡时未剔除 `rejected` 行 | 统一优先级函数 `_activeCheckIn`（同一 task 当日多行取「最新一条非 rejected」）+ `_allDailySubmitted` 剔除 rejected | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F18 | M4/重做 | **[P2]** 被驳回后当日卡死，无法重做 | `checkIn` 对当日已有任意打卡行一律拦截 | `checkIn` 只拦 `pending` / `verified`，`rejected` 放行（**新增一行**，保留审计痕迹） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F19 | M4/统计口径 | **[P2]** `totalCheckInCount` 把 pending / rejected 也算进去 → 孩子端「我的」页累计打卡**虚高** | 计数未按状态过滤 | 改 `countCheckInsByStatus(CheckInStatus.verified.index)` | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F20 | M4/并发 | **[P0·补发现]** 两条不同 pending 记录并发核销 / 孩子连点两次「我做到了」→ 顶穿当日软顶、出双份阳光（家长看到两条同名待确认，核销出双份） | F14 的 CAS 只保证**同一条记录**不被重复核销，管不住**两条不同记录互相插队**：`_softCapGrant` 是「读当日累计 → 算差额 → 写账本」的非原子序列，两条各自读到同一份 `grantedSoFar`、各自补满差额；孩子连点两次则各插一行 pending | 服务层**串行闸门** `_serialized`（`Completer` 链），包住 `checkIn` / `settleFocusLinked` / `verifyCheckIn` / `rejectCheckIn` **四个写入口**；只读的 `board()` / `pendingCheckIns()` **不加闸门**（否则写操作会拖住界面）；被串行化的方法内部**不得**再调用另一个公共写入口，只能调私有实现或仓储（防死锁）。**两道锁分工**：闸门管「并发插队」，CAS 管「状态已被别处改过」，两层都要有、不能互相替代 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

## M4 经济漏洞轮 · 规则变更（玄参拍板，已落地）

- **联动项**（`requiresFocus == true`，UI 改述为「专注联动（自动结算）」）：孩子从该成长项点「开始专注」→ 专注达标 → **自动结算**（`verified` + 直接入账）。孩子**没有**可点的打卡按钮。
- **非联动项**：孩子点「我做到了」→ **当期不发阳光**，落 `CheckInStatus.pending` → **家长核销后才入账**，可驳回并写理由。
- **归属机制**：从成长项进入专注（`/focus?...&task=<id>`），因此**不需要给 `FocusSession` 加科目列**（绕开了「无科目字段」的数据模型限制）。
- **`pending` 不占当日软顶额度**：只有真正入账才计入当日 `earn` 合计。
- **完美日按「已提交」判定**（联动 = 自动结算；非联动 = 已打卡，**不等家长核销**），保持即时情绪反馈；完美日本身不发钱。
- `settleFocusLinked()` 专注**未达标** → 返回 `status == rejected` 且 `checkInId == ''`，**不抛异常、不写记录、不写账本**（让表现层能区分「正常没达标」与「真出错」）。
- **家长核销 / 驳回入口放在家长端「今日」tab**（核销有时效性）；待确认列表为空时整卡不渲染。
- 新增独立能力接口 `CheckInAdminRepository`（`checkInById` / `checkInsByStatus` / `updateCheckIn`），**没有往 `TaskRepository` 加方法** → `TaskRepository` 方法集未变，`test/nav` 里手写 Fake 不受影响，省掉一轮连锁返工。

## M4 经济漏洞轮 · 数据变更（schemaVersion 5 → 6）

- `check_ins` 表补 **5 列**：`status` / `sunlightGross` / `sunlightGranted` / `resolvedAt` / `parentNote`，走既有 `_ensureColumn` 幂等补列；`CheckIn` 实体同步加这 5 个字段。
- **枚举顺序刻意把 `verified` 放在 index 0**（`lib/domain/entities/enums.dart:48`）：老库补列默认值 0 → 历史打卡仍视为「已核销」（v5 及以前本就是「打卡即入账」，历史行为必须保持）。若把 `pending` 放 0，升级后会突然冒出一堆历史遗留待办，把家长淹掉。
- **本轮未加数据库列以外的结构变更**；`schemaVersion` 由 5 升到 **6**（后续植物成长 V2 再升到 7）。
- **连带**：`test/m3/migration_v4_to_v5_test.dart` 硬编码 `schemaVersion == 5` 的护栏断言被合法的 5→6 升级打破，已一并改为 6（升级的必然连带）。

## M4 经济漏洞轮 · 校验

- **新增回归测试**：`test/m4/task_checkin_test.dart` **42/42 通过**（含新增的「两条不同记录并发核销」「连点两次打卡」「闸门不吞异常」）；QA 独立对抗 `test/m4/adversarial_task_checkin_test.dart` **25 用例**；`test/m4/migration_v5_to_v6_test.dart`（v5→v6 迁移护栏）。
- **收尾校验（本阶段）**：`flutter analyze` **0 error / 0 warning**（全仓仅 55 条既有 info）；`flutter test --no-pub` **279 passed 全绿**。
- **主理人复核**：已亲自核对 4 个写入口的**公共签名一字未变**（表现层不受影响）、闸门实现无死锁风险。
- **QA 诚实自我更正**：早前报的「settle 路径并发竞态」是打在**修复前**的旧服务上，40 次并发 **0/40** 未复现 → 降级为契约回归，**当前无残留经济竞态**。
- **[P3-C] 口径裁定**：成长项被删除后，其孤儿 pending **仍可核销** → **保持现状**，非缺陷。家长端 `parent_today_page.dart` 已有 `p.task?.name ?? '（已删除的成长项）'` 兜底文案、按钮照常可点，让家长能把历史遗留清掉。
- **已提交**：随 commit **`34e1541`**。

---

# 花园扩容「暗扣 400」修复轮（2026-09-22，小米 14 Pro，分支 `m2/economy`）

> 玄参大人原话：「点击扩容的时候，它会扣400阳光，但是并没有显示……需要有弹出一个卡片，告诉我需要扣除多少阳光，确定之后才扣除，取消就不扣除」
> 「在我的里面是1000多阳光，在我的花园里面的阳光却是900多阳光，这两个数量就对不上」

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F21 | 花园/扩容 | 点「扩容 +1」**直接扣 400 阳光**（低年级档 160），无确认、按钮上没价格 | `garden_page.dart` 点「扩容 +1」直接 `_run(() => expandPot(...))`，按钮文案写死「扩容 +1」（无价格），中间**零确认** → 点了才扣 | 新增 `_expandCost` getter（`_tier == AgeTier.low ? kPlantPotExpandCostLow(160) : kPlantPotExpandCostHigh(400)`，无裸字面量）+ `_confirmAndExpand()`：`AlertDialog`「要给花园腾一个花盆吗？」正文三行 = 当前阳光 X ☀ / 本次扩容将扣除 Y ☀ / 花园容量 N → N+1 盆；「取消」`pop(false)` → `if (ok != true) return;` **一分不扣**，「确定，扣除」`pop(true)` → 才 `expandPot`；余额不足先 SnackBar「阳光不足，还差 Z ☀」并 return。`_CapacityBanner` 重写为**三态互斥**：已达上限 →「已达上限」；阳光不足 → 灰字「阳光不足（还差 Z ☀）」且**不给可点按钮**；可扩容 →「扩容 +1 · Y☀」（原 `onExpand==null` 一律显示「已达上限」会误导，已消除）；`busy` 时禁用 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F22 | 孩子端/我的页 | 「我的」页 1000 多、花园页 900 多，**两端对不上** | `child_profile_page.dart` 的 `_balance` **只在 `initState` 的 `_reload()` 读一次**，而它是底部导航 `IndexedStack` 的**保活页**，切 tab 不重建 → 花园消费后切回仍显示旧值。**账本本身是准的**：`PlantGrowthService.expandPot` 确实走 `_appendSpend(..., refType:'plant_expand')` 写 `net = -cost` —— **不是少扣了款，只是页面没重读，禁止去领域层「补扣」** | `build()` 内加 `ref.listen(economyRevisionProvider, (_, __) { if (mounted) _reload(silent: true); })`；`_reload` 加 `{bool silent = false}`（沿用花园同款静默刷新，避免切回时闪全屏 loading） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

⚠️ **与 F05 同一类坑（交叉引用）**：主理人最初建议把 `ref.listen` 写在 `initState`，**Riverpod 不允许**——有 `debugDoingBuild` 断言（`ref.listen can only be used within the build method`）。实测写在 `initState` 会让 `test/nav/nav_structure_test.dart` **4 条全红**（`ChildProfilePage` 是 `ChildShellPage` 的 `IndexedStack` 子页，`initState` 立即执行即触发）。改放 `build()` 内、`_loading` 早退之前（与 `child_shell_page` / `child_today_page` 现有一致）→ nav 恢复 6/6、全量 279 绿。
**纪律**：`ref.listen` 只能写在 `build()` 内；`initState` 场景必须用 `ref.listenManual`（见 F05）。

## 花园扩容轮 · 校验

- **收尾校验（本阶段）**：`flutter analyze` **0 error**（3 条 warning 在 QA 早前新增的 test 文件 unused_import / unused_element_parameter，非本轮改动文件，未动 `test/**`）；`flutter test` **279 passed 全绿**；`test/nav/nav_structure_test.dart` 单独 **6/6**。
- **装包（20:49，玄参重连手机）**：小米 14 Pro `f05bbc46` / shennong / 23116PN5BC 重新连上；`adb -s f05bbc46 install -r build/app/outputs/flutter-apk/app-debug.apk` → **Success**（覆盖装，保留数据）；`am start -n com.example.sunflower_time/.MainActivity` → 进程 **PID 6709 存活**，无崩溃。
- **已提交**：随 commit **`34e1541`**。

---

# 植物成长 V2 重规划轮（2026-09-22，玄参真机反馈 + 拍板，分支 `m2/economy`）

> 玄参大人原话：「点击浇水，本阶段成长直接到了21%，并不是浇水的12%。点击施肥，成长阶段直接从21%涨到了70%，并不是施肥的25%」
> 「现在植物的培养还是太简单了……一个植物需要1个月的成长期，精品植物需要2个月的成长期……浇水成长1%，施肥成长5%。植物的成长还需要重新规划」
> 「结算页面，我看到了现在今日累计，显示的是-173，消耗的阳光就不用在这里显示了吧，只需要显示获得的阳光」
>
> 玄参 AskUserQuestion 三选拍板：① 成长期口径 =「**不养护 30 天，养护可加速**」；② 养护强度 =「**浇水 1%×3 次/天 + 施肥 5%×1 次/天**」（每天最多 +8%）；③ 老植物 =「**全部重置清零**」。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F23 | 植物/成长 | 浇水标 +12%，实际本阶段成长**跳到 21%**（真机） | **根因① `_advanceGrowth` 非幂等**：`stageStartedAt` 只在**跨阶段**时更新 → 每次 `tickAll`（每次页面刷新）都把「stageStartedAt → now」整段**重新累加**到已有进度 | 改为按段推进 + 推进 cursor，重复 tick 不再重算已走过的段 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F24 | 植物/成长 | 「培养太简单，没有陪伴成长的乐趣」——几小时就开花 | ⭐**根因②（真凶）微秒除数少除 1000 倍**：`inMicroseconds / 3600000.0`，而 1 小时 = 3.6e9 微秒，正确除数应为 **`3600000000.0`** → 成长速度整体**快 1000 倍**。表面只表现为「长得快」，极难定位 | `plant_growth_service.dart:295` 改 `/ 3600000000.0`；`kPlantGrowthHoursPerStageDefault` 24 → **240**（普通，每阶段 10 天）；新增 `kPlantGrowthHoursPerStagePremium` = **480**（精品，每阶段 20 天）；`kPlantAutoGrowthScale` 0.2 → **1.0** | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F25 | 植物/成长 | 施肥从 21% 涨到 70%；且「正好 30 天」实际要 **31 天** | **根因③ 浮点卡阶段**：24/240 累加 10 次 = `0.9999999999999999 < 1.0`，严格 `>= 1.0` 判定把「正好 30 天」推成 31 天 | 新增 `kGrowthEpsilon = 1e-9`，阶段判定改 `progress >= 1.0 - kGrowthEpsilon`；浇水 +12% → **+1%**（`kPlantWaterProgressGain = 0.01`）、施肥 +25% → **+5%**（`kPlantFertilizeProgressGain = 0.05`） | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F26 | 结算页 | 「今日累计」显示 **-173** | `settle_page` 用 `dayNet()`（**含支出**）→ 把浇水 / 施肥 / 种植的支出也算进了「今日累计」 | 改用 `SunlightRepository.earnNetOnDay()`（**只统计 `type == earn` 的 net**）并钳 **≥ 0** | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |

## 植物成长 V2 轮 · 数值变更表（`lib/core/constants/prd_params.dart`）

| 参数 | 改前 | 改后 |
|---|---|---|
| `kPlantGrowthHoursPerStageDefault` | 24 | **240**（普通，每阶段 10 天） |
| `kPlantGrowthHoursPerStagePremium` | —（本轮新增） | **480**（精品，每阶段 20 天） |
| `kPlantWaterProgressGain` | 0.12 | **0.01** |
| `kPlantFertilizeProgressGain` | 0.25 | **0.05** |
| `kPlantAutoGrowthScale` | 0.2 | **1.0** |
| `kGrowthEpsilon` | —（本轮新增） | **1e-9** |

## 植物成长 V2 轮 · 数据迁移（schemaVersion 6 → 7）

```sql
UPDATE plants SET stage = 0, growth_progress = 0.0, stage_started_at = <unix秒> WHERE status = 0;
```

- **只清 `growing`（status = 0）**；`bloomed` / `wilting` / `dead` **不动**——清掉已开花的植物等于抹掉成就感，非玄参本意。
- ⚠️ **时间必须写秒**（`DateTime.now().millisecondsSinceEpoch ~/ 1000`）：本仓未开 `storeDateTimesAsText`，drift 把 `DateTime` 落库为 **unix 秒 INTEGER**，SQL 里写毫秒会算出 1970 年。
- 旧进度是按 24h/阶段、且**非幂等**累加出来的，**无法与新口径对齐**（真机上已表现为进度虚高），故玄参选「全部重置清零」而非平滑衔接。

## 植物成长 V2 轮 · 校验

- **实测结果（工程师实测，非估算）**：普通 不养护 → **30 天**（正好命中）；普通 每天满养护 → **17 天**（理论 16.67 进位，比预期 18 少 1 天，见 F33）；精品 不养护 → **60 天**；幂等性——同一时刻连 tick 4 次增量 **0.0**，浇水后 1 分钟再 tick 增量 **6.944e-5**（= 1min/240h，修前是 **0.06944**）。
- **新增回归测试**：`test/m3/plant_growth_v2_test.dart` **9 条**；`test/m3/migration_v6_to_v7_test.dart` **7 条**（全部**读回断言**，含跨版本 v5→v7 / v3→v7、幂等重开不被二次清零、三种非 growing 状态原样保留）。
- **连带改动（必然连带）**：`test/m3/migration_v4_to_v5_test.dart:209` 与 `test/m4/migration_v5_to_v6_test.dart:247` 硬编码 `expect(schemaVersion, 6)` → 改 **7**（与上次 5→6 同样的跟进）；`plant_card`「还需约 N 次浇水」→ **「每天按时养护，还需约 N 天长成」**（选时间口径，保留延迟满足激励）；`garden_page` 说明卡同步新数值 + 每日次数上限。
- **收尾校验（本阶段）**：`flutter analyze` **0 error**；`flutter test` **295/295 全绿**（279 基线 + 新增 16）。
- **已提交**：随 commit **`34e1541`**。

---

# 植物模块接口化（2026-09-22，需求类 · 非缺陷，分支 `m2/economy`）

> 玄参大人原话：「植物这个地方，你要做一些个接口，因为现在还只是个卡片形式。我以后还要做美术，替换为美术资源，把它做进去」
> 「植物长成到成长阶段之后，它会有一些其他的属性，比如说偶尔可能会往外生产阳光，需要用户去收集。或者说还有其他的比较有意思的方案会接入」
>
> 玄参 AskUserQuestion 拍板：① 本轮范围 = **渲染抽象 + 能力接口骨架**（不做产阳光的具体规则）；② 美术资源接入 = **按命名规范自动匹配**（美术只需丢图，代码零改动）；③ 占位方案 = **自绘简笔植物**。
>
> ⚠️ 本条**不是修 bug**，是**为将来换美术 / 加玩法预留的扩展点**。

| ID | 模块 | 现象 / 需求 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F27 | 植物/扩展点 | 植物外观硬编码为 Material 图标（`CircleAvatar + _stageIcon`），换美术必须改代码；未来「植物产阳光、用户去收集」一类玩法无处挂载 | 渲染与能力都写死在 `plant_card.dart`，没有抽象层 | ①**渲染抽象**：新建 `lib/presentation/child/widgets/plant_artwork.dart`。**三级回退命名规范**（美术按此丢图，代码零改动）：`assets/plants/{speciesId}_{stage}_{status}.png` → `{speciesId}_{stage}.png` → `{speciesId}.png` → 内置自绘 `PlantPlaceholderArt`（例：`species_sunflower_adult_bloomed.png`）。`_PlantArtAssets` 懒加载 `AssetManifest.json`（进程内解析一次）+ 按「物种_阶段_状态」缓存；`PlantArtwork` 用 `FutureBuilder`，命中走 `Image.asset`，未命中 / 解码失败一律回退占位（坏图不至于整页崩）；`PlantPlaceholderArt` Canvas 自绘，按 speciesId 区分形态、stage 区分高矮、status 调色。`plant_card.dart` 改用 `PlantArtwork(plant, species, size:44, tint:_statusColor)`，删 `_stageIcon`。②**能力接口骨架**（领域层，纯 Dart、不 import flutter）：`lib/domain/entities/plant_perk.dart`（`PlantPerkKind { sunlightDrop, custom }` / `PlantPerkState { locked, idle, ready }` / `abstract class PlantPerk`（`isUnlocked` 有默认实现，`evaluate` 由子类实现，**只描述状态、不含任何数值规则**）/ `PlantDrop` 掉落物模型——**不落库、不含规则**）+ `lib/domain/services/plant_perk_registry.dart`（`instance` 单例 + `register` / `unregisterById` / `all` / `unlockedFor` / `readyFor` / `hasAnyReady` / `resetForTest`）。**注册表默认为空** → 当前 UI 不出现任何新玩法（这是本轮预期，也是测试断言）；`plant_card` 挂接线点 `_perkEntries()`，空列表时**零视觉变化**。`pubspec.yaml` 新增 `- assets/plants/`（目录含 `.gitkeep`，空目录不建会导致构建报找不到目录） | ✅ 已实现（待真机） |

## 植物模块接口化 · 架构纪律（本次沉淀）

- 给未来美术 / 玩法留接口时，先抽**「渲染」**和**「能力」**两个方向：渲染靠「命名规范 + 自动回退」（美术零代码介入），能力靠「抽象接口 + 空注册表」（玩法零 UI 改动）。共同点是**调用方代码一行不改**。
- **领域层必须 flutter-free**，否则纯 dart 单测跑不起来（本轮领域层 + 测试全部无 Flutter 依赖，29 条跑在 `package:test`）。
- **单例注册表必须提供 `resetForTest()`**，否则跨测试串味。
- **校验参数用 `StateError` 不用 `assert`**：release 构建会剥离 assert，校验等于没有。

## 植物模块接口化 · 校验

- **新增测试**：`test/m3/plant_perk_skeleton_test.dart` **29 条**（纯 `package:test`）：默认空注册、重复 / 空 id 抛 `StateError`、默认解锁门槛四种组合、子类覆盖生效、ready 才命中、`PlantDrop` 收集 / 过期边界、`resetForTest`。
- **收尾校验（本阶段 = 当日最终基线）**：`flutter analyze` **0 error**；`flutter test --no-pub` **324 passed 全绿**（295 基线 + 新增 29）；`flutter build apk --debug` **✓ Built** `build/app/outputs/flutter-apk/app-debug.apk`。
- **装包（22:50，玄参重连手机）**：`adb devices` 恢复 `f05bbc46` / shennong / 23116PN5BC（**注意：手机断开后即使重插，有时 adb 仍列空，需 `adb kill-server` + `start-server` 才扫到**）；`adb -s f05bbc46 install -r` → **Success**（覆盖装，保留数据）；`am start -n com.example.sunflower_time/.MainActivity` → 进程 **PID 29113 存活**，无崩溃。
- **已提交**：commit **`34e1541`**（`m2/economy`）；同日 `--no-ff` 合回 `main` → 合并提交 **`421df23`**，`origin/HEAD` 指向 `421df23`。

---

# 环境类问题（iOS 模拟器构建，2026-09-22，分支 `m2/economy`）

> 玄参想在 Mac 上用 iOS 模拟器做功能 / 页面自测。授权范围：**只在 `m2/economy` 分支加 `ios/` 工程 + 本地 pod 顶替**，只做 iOS 模拟器，不做 macOS 桌面版。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F28 | 环境/iOS 构建 | `flutter build ios --simulator` 在 `debug_unpack_ios` 的 `thinFramework` 阶段失败 | `~/development/flutter/packages/flutter_tools/lib/src/build_system/targets/darwin.dart` 调用 `lipo <path> -verify_arch arm64 x86_64`（**双架构**），而本机 **Xcode 27 的新 lipo 的 `-verify_arch` 只接受单架构** → 报 `requires exactly one input file`（即便 `lipo -info` 显示 x86_64 / arm64 都在） | 把该校验改为**逐架构循环**单条 `lipo <path> -verify_arch <arch>`（顺带覆盖 macOS 同名函数），并删 `flutter_tools.snapshot` / `stamp` 强制重建。备份：`/tmp/darwin.dart.bak_20260922` | ✅ 已确认正确 |
| F29 | 环境/iOS 构建 | 部署目标 13.0（Runner）/ 12.0 / 9.0（Pods）报 Target Integrity 失败 | 本机 Xcode / iOS 26 SDK 要求模拟器 `IPHONEOS_DEPLOYMENT_TARGET ∈ [15.0, 27.0]` | `ios/Runner.xcodeproj/project.pbxproj` 三处 13.0 → **15.0**；`ios/Podfile` 启用 `platform :ios, '15.0'` 并在 `post_install` 遍历所有 pod target 强制 `config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'`。**副作用**：iOS < 15 的旧设备跑不了（模拟器 iOS 26 无影响） | ✅ 已确认正确 |
| F30 | 环境/iOS 依赖 | `pod install` 必败 | `sqlcipher_flutter_libs` 依赖 CocoaPods 上的 `SQLCipher ~> 4.5.4`，其源码指向 `github.com/sqlcipher/sqlcipher.git`，**本机屏蔽 github** | 新建本地空壳 pod `ios/local_pods/SQLCipher/`（podspec 版本 4.5.7 + 空 `Classes/Empty.m`），在 `ios/Podfile` 用 `pod 'SQLCipher', :path => 'local_pods/SQLCipher'` 顶替；`pod install` 成功（10 pods）。安全性：pubspec 里 sqlite3 native assets 配 `source: system`（iOS 用系统 libsqlite3），且 `sqlcipher_flutter_libs` 的 iOS 原生类是空实现 → **顶替零行为影响**；差异是 **iOS 库不加密**（与既定行为一致） | ✅ 已确认正确 |
| F31 | 环境/包名 | Android `applicationId` = `com.example.sunflower_time`（下划线）与 iOS `PRODUCT_BUNDLE_IDENTIFIER` = `com.example.sunflowerTime`（camelCase）**不一致** | `flutter create` 按项目名 `sunflower_time` 默认生成，**非本轮引入** | **已改（2026-09-23 玄参拍板）**：包名统一为 `com.sunflowertime.app`（Android/iOS 一致）。当前纪律：所有 `adb` 命令改用 `com.sunflowertime.app`（launch / pidof / install -r 均以此为准），iOS 模拟器同用 `com.sunflowertime.app` | ✅ 已改 |

## 环境轮 · 校验

- **`flutter create` 副作用已修**：`.metadata` 被改写为只剩 `platform: ios` → 已恢复 `platform: android` + `platform: ios` 两条；`pubspec.lock` 被重写（丢了 1090 行 dev 依赖）→ `git checkout -- pubspec.lock` 还原；模板 `test/widget_test.dart`（引用不存在的 `MyApp`）已删，避免污染测试套件。
- **构建结果**：`flutter build ios --simulator --debug` ✅ → `✓ Built build/ios/iphonesimulator/Runner.app`（Xcode 编译 14.2s；清快照后首次重建 flutter_tools + 代理 502 重试共约 27 分钟，依赖命中缓存后过关）；`lipo -info` → `x86_64 arm64`（fat，符合 iOS 26 模拟器要求）。
- **启动验证**：`xcrun simctl install` + `launch`（PID 19008）→ 无崩溃诊断报告 → App 在 **iPhone 17 模拟器（iOS 26.5，UDID `DAA7C94F-F995-47CB-A010-2920AC1480F8`，已 Booted）** 正常启动。
- **已知限制（不是缺陷）**：模拟器无 `CMMotionManager` 硬件，`native_device_orientation` 返回 `orientation_not_available` → 「物理竖屏 → 退出确认弹窗」这一个交互在模拟器上**静默不 arm**；其余功能 / 页面照常可测，方向相关仍需小米 14 Pro 真机补测。
- **已提交**：`ios/` 工程随 commit **`34e1541`** 入库；`ios/Pods`（828K）与含本机绝对路径的 `Generated.xcconfig` / `flutter_export_environment.sh` / `ephemeral/` / `xcuserdata/` 已加进 `.gitignore`（新增 7 条规则，`git add -A` 时命中忽略）。

---

# 遗留待玄参拍板 / 已知技术债（2026-09-22 盘点）

> 按玄参大人要求**不掩盖**，此处如实登记本轮**已发现但未修 / 未定夺**的事项。

| ID | 模块 | 现象 | 根因 / 影响 | 处置 | 状态 |
|---|---|---|---|---|---|
| F32 | M2/日上限 | **[P0] PRD §4.5「日上限 79」实际未按「日」封顶**：一天多场专注可远超 79 | `lib/domain/services/sunlight_service.dart` 的 `settle()` 里 `net = computeEffective(rawS)`，而 `rawS` 是**本次会话自己的**原始产出 → 软顶是**按会话逐次套**的，不是按当日累计；`todayCumulativeNet()` 只用于展示，没有参与约束。连带影响：成长项打卡按「当日累计差额」发阳光，若某日专注侧已超发（net > 79），打卡会 `grant == 0`，看起来像「打卡不发阳光」 | **玄参 2026-09-23 拍板修法（见 `口径裁定表_v1.md` C11）**：① 取消分段打薄（`computeSoftCap` + 6 个 `kSoftCap*` 常量全删），专注 **1 分钟 = 1 阳光**、年段日上限 **60/90/120** 硬封顶；② 成长奖励改**独立额度 79**，`_dailyRewardGrant` **只读 `task_checkin` 自身账目**（不再读当日全部 earn）→ 两条额度线解耦，连带影响同步消除；③ **三道拦**：选时长页灰超额度档位 → 开始前截断 → **结算硬截断**（`settle` 新增 `required int dailyFocusCap` + `effectiveFocusSunlight`）。详见下文「G02」 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F33 | M4/植物养成 | 满养护实测 **17 天**，与理论 **18 天**差 1 天 | 种下当天即可养护 → 少 1 天（理论 16.67 进位）。要严格 18 天，需把每天养护从 8% 降到约 6.7%（浇水 0.5%/次 或施肥 4%），会**破坏已拍板的 +1% / +5% 整数口径** | 玄参 2026-09-22 23:49 **拍板：就 17 天，不细调**（差 1 天无感知，凑 18 天要破坏 +1% / +5% 整数口径，不值得） | ✅ 已拍板（不改） |
| F34 | 孩子端/我的 | `child_profile_page.dart` 底部 `DEBUG 加1000阳光` 按钮仍在（源码自标「提交前删除」） | 玄参真机验收兑换链路要用，故暂留 | **提审前必须清理** | 🔧 待清理 |
| F35 | 全仓/文案 | 注释里的「任务」字样约 **26 处**未统一为「成长」 | 均在 `///` / `//` 注释中（**非用户可见**），其中若干处直接指代 tab 名（如 `child_shell_page.dart:3`），对新维护者有误导性 | 工程师按纪律未改（不在本轮范围）并已逐条列出 | 🔧 待清理 |
| F36 | M3/完美日口径 | 完美日按「**已提交**」判定（联动 = 自动结算；非联动 = 已打卡），而非「家长已核销」 | 玄参拍板：保持**即时情绪反馈**（不等家长核销）；完美日本身不发钱，故无经济风险 | **不改**（已拍板） | ✅ 已确认正确 |
| F37 | M2/指标 | **「核销履约率」指标（含 G2 ≥70% 硬门槛）取消** | 玄参：「简单一点，不要什么核销履约率」。该指标① 口径虚设（分母要排除免确认自动通过，但当前兑换一律走待核销、无样本可排除）；② **从未实现**（全库仅 3 处注释提及，`parent_report_page` 无任何计算代码，`autoApproved` 列无人读取）；③ 还要拆小额/大额分层判读，对单机 MVP 属过度设计 | **已删除**：`redemption_service.dart:29`、`enums.dart:22/113` 三处注释中的「履约率」字样已清理。⚠️ 历史文档（`软件设计文档_M2.md`、`MVP执行规划_v2.md`、`验证计划_SunFocus_G0G2.md`、`架构设计_SunFocus_MVP.md`、`软件设计文档_spikes.md`、`sequence-diagram-M2.mermaid`）中仍留有表述，**是否一并清理待玄参发话** | ✅ 已执行（历史文档待定） |
| F38 | M2/周池 | 周池预算区间 **50–1200 只在 UI 校验**（`pool_indicator.dart` 硬编码），常量里没有周池 min/max；1200 过大 | `prd_params.dart` 的 `kMonthlyPoolMin=100 / kMonthlyPoolMax=1200` 是**月池遗留**（名字带 Monthly），与周池无关；`weekly_pool_service.dart` 领域层**零校验** | **玄参 2026-09-23 拍板改掉**：新增 `kWeeklyPoolBudgetMin=50` / `kWeeklyPoolBudgetMax=500`（`prd_params.dart`），`pool_indicator.dart` 校验与提示文案改为引用常量（不再有裸字面量）。区间 50–1200 → **50–500** | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F39 | 家长端/设置 | 每日专注上限下拉 `options: [60, 75, 90]`（`parent_settings_page.dart`）中的 **75 是孤儿**，且三档默认值不合理（低=中=90、高=60，高年段反而更少） | `prd_params.dart` 旧值只有 `kDailyFocusCapLow=90`（低/中都用它）/ `kDailyFocusCapHigh=60`；75 只存在于 UI 字面量 | **玄参 2026-09-23 拍板改掉**：改为**年龄越大上限越高**的阶梯 —— 低 60 / 中 90 / 高 120。新增 `kDailyFocusCapMid=90`，`kDailyFocusCapLow` 90→60、`kDailyFocusCapHigh` 60→120；`age_tier_params.dart` 三档同步；下拉改为引用三个常量（75 消失，不再有裸字面量）。新增 `test/m2/age_tier_params_test.dart` 7 条断言锁死阶梯与区间 | ✅ 已修复（真机已验证，2026-09-23 21:41 装机） |
| F40 | M4/植物养成 | 施肥 **+5%/次** 进度增长偏快（每天满养护 18%/天，长成只要 17 天） | 玄参大人 2026-09-25 拍板：「施肥增长 5% 的进度有点快」；每天满养护推进量 = 自动 10% +浇水 3×1% +施肥 5% = **18%**，节奏过快 | `kPlantFertilizeProgressGain` **0.05 → 0.03**（`prd_params.dart:203-206`，唯一真源，UI 文案从常量派生故自动同步）；每天满养护推进 **18% → 16%**；满养护长成 **17 天 → 约 19 天**（实测 19 天 = 理论 3.0 阶段 ÷ 16% = 18.75 进位，符合预期）；**不养护仍 30 天不变**（未动 `kPlantGrowthHoursPerStageDefault`）。测试 `test/m3/plant_growth_v2_test.dart` 常量钉死断言同步为 `0.03` / 每天养护上限 `0.06`、长成天数区间改为 `19..20` | ✅ 已修复（2026-09-25 玄参拍板） |

## 遗留项 · 校验

- **本轮最终基线（commit `34e1541`）**：`flutter analyze` **0 error**；`flutter test` **324 passed 全绿**；`flutter build apk --debug` 成功；小米 14 Pro **`f05bbc46`** 覆盖装成功、进程存活无崩溃。
- **真机复测状态**：上列 F07–F27 中标注「待真机」的条目，截至 2026-09-22 22:50 装包后**结论待玄参回**；本文档在收到回执后再行订正状态列。
- **提交纪律**：先 `flutter analyze` 0 error + `flutter test` 324 绿，再经玄参明确允许（22:54 授权）才 commit / push / merge。

---

# 花园改造轮 + 日上限口径重构轮（2026-09-23）

> 玄参口径原话：「每日上限**仅作用于专注时长**，防刷阳光，成长奖励不算在内；低 60 / 中 90 / 高 120 分别对应 1–2 / 3–4 / 5–6 年级；其他年级无限制。」
> 该口径的**技术裁定**落在 `口径裁定表_v1.md` **C11**（项目宪法，优先级最高）；PRD §4.5 的旧软顶公式被本条覆盖。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| G01 | 孩子端/花园 | 花园是「卡片列表 + 容量横幅」，一屏看得全但**没有花园感**；点植物只能在一排按钮里挑动作 | 原 `garden_page.dart` 用卡片列表渲染，缺乏空间感；容量入口是独立横幅，与花盆不在一处 | 重写为**草地 + 3 列花盆网格**：新建 `garden_pot.dart`（`GardenGrid` / `GardenPot` / `EmptyPot` / `ExpandPotSlot` / `_PotPainter` 自绘陶盆）；点植物弹**底部养护面板**（新建 `plant_care_sheet.dart`，复用 `PlantCard` 的展示与按钮，**不复制第二套按钮逻辑**）；空盆即种植入口；加盆收进网格**末尾一格**（三态：带价可点 / 差多少不可点 / busy 不可点）；植物按进度**略微变大**（`plant_artwork.dart` 新增 `growthScale`，靠内边距收缩实现，**不会顶破圆形裁切**）。新增 `test/m3/garden_pot_layout_test.dart` **11 条**布局断言（320/360/390 三档屏宽不抛 overflow；同行 x 递增且同高、第 4 格换行；标签不越界；盆沿压在盆口上） | ✅ 已修复（真机复测通过，commit `c0f8298`） |
| G02 | M2/日上限 + M4/打卡额度 | **[P0]** 日上限只在「点开始专注」时检查一次，**不检查这一场会不会超** → 孩子可选自定义 180 分钟，一场拿下 180 分钟、到账 79 阳光，**一次超掉低年段 60 上限的 32%**。**另一处 [P1]** 当天专注或家长赠予拿满额度 → 成长打卡奖励归 0（打卡「发不出来」） | ① `settle()` 里 `net = computeSoftCap(rawS)`，`rawS` 是**本次会话自己**的原始产出 → 按会话逐次套，非当日累计；`dailyFocusRemaining()` 早已写好却**全仓零调用**（当初就打算这么接，没接上）。② `_dailyRewardGrant` 读的是**当日全部 `earn`**（`earnGrossOnDay` / `earnNetOnDay`），专注 / 赠予一拿满就把成长奖励额度吃干净。③ 分段软顶「第一段即 60 分钟全额」，与「封顶跟随年段」在数学上**不能共存** —— 高年段 120 分钟永远只能拿 79，是摸不到的天花板 | **取消分段软顶**：删 `computeSoftCap()` 与 6 个常量（`kSoftCapDailyMax` / `kSoftCapSeg1..3` / `kSoftCapSeg2Rate` / `kSoftCapSeg3Rate`），改 **1 分钟 = 1 阳光 + 年段硬封顶**。**两条独立额度线**：专注（跟随年段 60/90/120，按 `refType='focus_session'` 聚合）/ 成长奖励（新增 `kTaskCheckinDailyCap = 79`，按 `refType='task_checkin'` 聚合），互不挤占。**额度三道拦**：选时长页灰超额度档位 + 提示「今天还可以专注 N 分钟」→ 开始前按剩余额度截断 → **结算时硬截断**（新增 `effectiveFocusSunlight`，唯一可靠兜底）。**接口与改名**：`settle` 新增 `required int dailyFocusCap`；`sunlight_service` 新增 `focusEarnedToday` / `focusRemainingToday`（额度口径单点收口）；`cappedBySoftCap → cappedByDailyCap`；`_softCapGrant → _dailyRewardGrant`；`FocusSettlement.capped` 改为直接比较 `net < rawS`（不再靠「是否超第一段」推断） | ✅ 已修复（代码 + **348 条测试全绿**；**2026-09-23 21:41 已装机，三点均真机验证通过**） |

## 花园/日上限轮 · 校验

- **`flutter analyze lib test`** → **0 error**。4 条 warning（`adversarial_task_checkin_test.dart` 与 `adversarial_v1_v10_test.dart` 的 `unused_import`、`unused_element_parameter`）已用 `git stash` 对比 HEAD 确认**改动前既有**，非本轮引入，按最小改动纪律**未清理**。
- **`flutter test --no-pub`** → **348 条全绿**。计数演进：该轮起点 **331** → 花园 +11 = **342** → 日上限 +6 = **348**。
  - 新增 O1–O6（`test/sunlight_settle_p2_test.dart`）：`effectiveFocusSunlight` 边界 / 单场截断 / 多场累计 / 成长奖励不占专注额度 / 任务奖励单独记账 / `rawS` 语义。
  - 新增回归（`test/m4/task_checkin_test.dart`）：「**专注拿满 + 家长赠予 → 成长奖励仍发得出来**」。
- **⚠️ 测试自身的缺陷（本轮一并修，这才是 bug 长期潜伏的真因）**：4 个测试文件里 `netByRefTypeOnDay` 的手写 fake **忽略 `refType` 参数、一律返回当日全部 earn 合计** → 「额度互相挤占」这类缺陷在测试里**永远是绿的**。已全部改为**真按 refType 过滤**（`test/sunlight_settle_p2_test.dart`、`test/m4/task_checkin_test.dart`、`test/m4/adversarial_task_checkin_test.dart`、`test/qa/adversarial_v1_v10_test.dart`）。**纪律：后续新增 fake 必须真过滤 refType。**
- **装包**：花园轮 `adb -s f05bbc46 install -r` → **Success**；`monkey` 启动后进程存活（PID 3924），logcat 无 `FATAL` / `E/flutter`。**日上限轮按玄参指示暂不出包**（先提交推送，装包另择时间）→ 上表 G02 状态为「待真机复测」。
- **文档同步（本轮一并做）**：`口径裁定表_v1.md` 新增 **C11**；同步 `产品开发文档_M2M3M4.md`（§1.3 / §3.5 / §3.6 / §6）、`软件设计文档_M1.md`（§7 / §8）、`软件设计文档_M2.md`（结算时序图）、`软件设计文档_M3M4.md`（§3.2 / §3.3 / §9 / §10）、`软件设计文档_M0.md`、`软件设计文档_spikes.md`、`架构设计_SunFocus_MVP.md`（§3.2 / §4.3 / §5 目录 / §6 任务表）、`验证计划_SunFocus_G0G2.md`（§4.3 DoD / 埋点字段名 `softcap_hit → capped`）。**PRD v2.0 正文按玄参自维护处理，保留为历史版本，不在回写范围。**
- **已知技术债留存**：`child_profile_page.dart` 的 `DEBUG 加1000阳光` 按钮（F34）**提审前必须删**。

---

# 植物状态规则 + 花园美术接入 + 花园页 v2/v3 轮（2026-09-23 下午–晚）

> 玄参当天多轮真机截图反馈驱动的连续改造。**本节所有条目已装机验证**（`adb -s f05bbc46 install -r` → Success，21:41）。
> 口径落在 `口径裁定表_v1.md` **C12**（植物枯萎 / 恢复 / 花谢循环）与 **C13**（花园表现层与美术规格）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| G03 | M3/植物养成 | 枯萎 7 天太久；付费救回（20/8 阳光）与「靠养护把花救活」的自然直觉不符 | 原为 PRD §4.6 设计 | **玄参拍板**（宪法 **C12**）：枯萎 **7 → 3 天**；**取消付费救回**（删 `revive()` + `kPlantReviveCostLow/High`）→ 改**养护恢复**（未满 3 天浇水 1 次；满 3 天需浇水 3 次 + 施肥 1 次）。恢复次数**以账本为唯一事实源**（新增 `countByRefTypeAndRefIdSince`，**不给 Plants 加计数列**）。枯萎期间放开养护（actionable = `growing \|\| wilting`）。⚠️ 踩坑：恢复需清空 `wiltedAt`，而 `Plant.copyWith` 的 `?? this.x` **清不掉可空字段** → 改用 `Plant(...)` 构造器显式重建 | ✅ 已修复（真机已验） |
| G04 | M3/植物养成 | 成株盛开后**永久停留**，不符合自然规律 | 原设计把「开花」当终点，无任何回退 | **玄参拍板**：**花谢循环** —— 盛开保持 `kBloomDurationDays = 3` 天 → 花谢（`status → growing`、进度回落 `kBloomWiltProgressFloor = 0.5`，**体型保持成株不缩回幼苗**）→ 由时间/养护重新养满后**自动再盛开**。新增 `Plant.bloomedAt`（**v8 迁移**，`_ensureColumn` 幂等）；老库升级来的已开花植物首次 tick 补计时起点，**不立即花谢** | ✅ 已修复（真机已验） |
| G05 | M3/花园美术 | 「花盆怎么调都太小」；一格画**两个盆**、边缘错位不干净 | **两层根因**（都不是「调比例参数」能解决的）：① 原图为 2048×2048 画布但**内容只占 35%×30%**，`BoxFit.contain` 按整张画布缩放 → 花盆只显示约 **29px**；② **植物图自带花盆**，而 `GardenPot` 又叠了一层 `pot.png` | ① 美术侧新增 `tools/normalize_plant_art.py`（幂等；glob 扫 `assets/plants/*.png` + `assets/pots/*.png`，新增图自动纳入）→ 全部重排为统一画布 **1200×2000**（盆宽 800、盆底贴底、盆心 x=600），原图备份 `assets/_originals/`（**不在 pubspec 声明内，不入包**）；② **玄参拍板「代码不要自动叠花盆，只要植物自带的花盆」** → `GardenPot` 只渲染一张植物图；③ `growthScale` 0.18 → **0**（所有盆必须等大，进度反馈交给盆下细进度条） | ✅ 已修复（真机已验） |
| G06 | M3/花园页 | 「我的阳光」通栏大卡**挡住草地**；空花盆「这么大点儿下面还有一条横线，看不出种没种」 | 通栏卡横在草地上方；空盆与有植物的盆**两套尺寸不一致** | 「我的阳光」→ **顶部栏左上角胶囊**（新建 `sunlight_pill.dart` + `sunlightBalanceProvider`，**仅花园 tab 显示**；加载/出错显示 `— ☀`，**绝不显示 0**）；空花盆只显示陶盆（去掉「+ 点击种植」） | ✅ 已修复（真机已验） |
| G07 | M3/花园页 | 第三排花盆**挡住背景植物**；加号格**飘在花盆上方**；「还差 400 阳光」**看不清**；底部半透明白块难看 | ① 网格按容量自然填行、不设可视上限；② 加号按**整张画布**正中（50%）居中，而 `pot.png` 的盆心在 **82.95%** → 必然高出一截；③ 11px 彩字**直接压在草地上**（不可点态尤其几乎看不清）；④ 通栏白块占草地 | ① 网格**锁 2 行**（超出部分**区域内纵向滚动**，滚动条**仅在溢出时**可见），滚动区底界按背景图映射到**菜地上沿之上**，永不遮挡背景植物；② 加号圆心对齐**盆心**（360 屏实测误差 **0.0px**）；③ 三类格子文案统一**半透明白胶囊底** `0xE6FFFFFF` + 加深字色（枯萎态对比度 **3.50 → 5.18**，五态全部 ≥4.5:1）；④ 白块**整块删除**，容量/养护信息收进**木牌弹窗**（背景图左下角木牌做成可点击 + 呼吸高亮 → 「花园说明」） | ✅ 已修复（真机已验） |
| G08 | 测试质量 | 花园 v3 有 **2 个用例形同虚设**（改坏生产代码仍全绿）；1 处文字对比度不达标 | ① 该组测试**自建 `SingleChildScrollView` 复刻了布局**，根本没渲染真实 `GardenPage`（且 `gridWidth` 用 `360-44`，生产是 `360-24`）；② 木牌用例只断言「≥44px 且在容器内」→ **右移 248 源像素**仍全绿；③ 加号断言**引用被测常量本身**（自指 = 永不红） | QA 严过关用**变异测试**（故意改坏实现看测试会不会红）戳穿 → ① 「锁 2 行」抽成公共纯函数 `gardenGridVisibleHeight()` + 补**真实 `GardenPage` 渲染用例**（假仓储 + `ProviderScope` overrides）；② 木牌坐标改为**从源图像素独立推导 + 硬钉实测值**；③ 加号期望值改为**从 `pot.png` bbox 独立推导**；④ 加严变异又挖出 `firstRowTop` 窄覆盖洞 → 补**矮屏 360×380 真实页用例**；⑤ 枯萎态 `orange.shade900` → `deepOrange.shade900` | ✅ 已修复（真机已验） |

## 花园 v2/v3 轮 · 校验

- **`flutter analyze`** → **0 error**；3 条 warning 全在**既有**测试文件（`test/m4`、`test/qa` 的 `unused_import`），非本轮引入。
- **`flutter test --no-pub`**（摘四个代理变量）→ **412 条全绿**。计数演进：360 → 370（花谢循环）→ 385（植物状态规则）→ 387（花园根因修复）→ 404（花园 v3）→ **412**（v3 缺陷修复 + 矮屏用例）。
- **变异测试（本轮最有价值的方法论，已写进 `软件设计文档_M3M4.md` §8.4）**：
  - M1 `kPotBodyCenterYFraction` 0.8295 → 0.5 → **变红** ✓
  - M2 木牌归一化矩形右移 +0.05 → **3 个用例变红** ✓
  - M3 `visibleRows` 2 → 3 → **3 个用例变红**（含真实 `GardenPage`）✓
  - M4（加严）改 `gardenGridVisibleHeight` **内部逻辑**（两行高度算错 / 去掉 `min` 约束）→ 变红 ✓
  - M5（加严）`firstRowTop` 传 `0` → **修前全绿（残洞）** → 补矮屏用例后**变红**（偏差恰 +12px）✓
  - 所有变异均 `shasum -c` **byte-identical 还原**，工作区无残留。
- **滚动条机制逐帧实测**（QA 用真实 `GardenPage`）：首帧 `maxScrollExtent` 即 >0 → **第 2 帧滚动条出现** → 60 帧内**只翻转 1 次**（无自激排帧）→ 容量 12 降回 4 时**正确消失**。
- **像素级验证（AI 不截图，靠度量）**：11 张图画布统一 1200×2000、内容底边全 = 2000、口沿宽 795~803、盆心 599~601；木牌归一化矩形反推源像素 = **x 47.95~285.03 / y 1655.04~1825.02**（与标定吻合），并**裁图目视确认是木牌**；`assets/_originals` **未入包**（解包 APK 抽图 md5 与磁盘一致）。
- **装包**：`flutter build apk --debug` → ✓ Built；`adb -s f05bbc46 install -r` → **Success**（21:41）；`dumpsys` 确认 `com.sunflowertime.app` / `versionName 0.1.0`。
- **文档同步（本轮一并做）**：`口径裁定表_v1.md` 新增 **C12 / C13**；`项目进度跟踪表.md` 重写；`美术资源清单_花园植物.md` 升 **v2**；`产品开发文档_M2M3M4.md`；`软件设计文档_M3M4.md`；`交接总结_下一阶段.md`。

- **⚠️ 本轮修正了一个旧结论**：v1 美术清单称「`seed_dead` **三物种全不可达**」。枯萎改 3 天后重新推导：**普通植物（240h/阶段）仍不可达**（死亡与阶段推进同日，tick 内先推进、后判死）；但**精品仙人掌（480h/阶段）现在可达** —— 第 3 天枯萎（进度 15%）、第 10 天死亡时进度仅 50%，**仍在 seed 阶段**。故仙人掌需**多出 1 张 `species_cactus_seed_dead.png`**；可达槽位总数 **27 → 28**（详见 `docs/美术资源清单_花园植物.md` §3.2）。
> ⚠️ **此「28」已被下一节 G12 的「种子通用」重算为 24**，以最新口径为准。

---

# P0 缺口补全 + 真机两个 Bug + 背景换图轮（2026-09-23 深夜）

> 玄参 22:44 自行更换 `assets/garden/background.png`（**1056×2336**，原 1161×2560），
> 22:5x 反馈花园两个真机 Bug（附图）。本轮同时收口 P0 三项缺口。
> ⚠️ **本轮代码改动尚未装机复验**（最后一次装机是 21:41）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| G09 | M3/花园页 | **左上角阳光余额溢出**：余额到 4 位以上，AppBar 左上角出现**竖排数字** | `SunlightPill` 的 `Container` 直接包 `Row`，AppBar `leading` 宽度有限（原 `leadingWidth` 96，扣左边距实际 ≈84px），位数一多 `Row` 放不下 → RenderFlex overflow | ① 胶囊内容包 `FittedBox(fit: BoxFit.scaleDown)`（等比缩小，任意位数都不溢出）；② `leadingWidth` 96 → **112**（注释写明「容纳 ☀ + 6 位数余额」）；③ 新增 `test/m3/sunlight_pill_test.dart` 两条（**6 位余额** `123456` 在 112 窄约束下 `takeException()` 必须为 null；4 位以内布局不变） | ✅ 已修复（**待装机复验**） |
| G10 | M3/花园页 | **点「+」加号无法添加花盆**（点了没反应，也没任何提示） | 花园页 v3 重写时**弄丢了 `economyRevisionProvider` 监听** → 别处（如扩容扣 400）改了余额后，`IndexedStack` 保活的花园页 `_balance` **仍是旧值** → `shortfall = _expandCost - _balance` 误算为正 → `affordable = false` → `InkWell.onTap` 传 **null**（连「阳光不足」提示都不弹，表现为纯「点不动」） | 在 `GardenPage.build()` 内补 `ref.listen(economyRevisionProvider, …)` → `_reload(silent: true)` 静默重载（**必须写在 `build()` 内**，`initState` 会触发 `debugDoingBuild` 断言崩溃；`silent` 避免闪全屏 loading）。**账本是准的，未改领域层** | ✅ 已修复（**待装机复验**） |
| G11 | M4/孩子端外壳 | **定时器泄漏**（测试抓出，非玄参反馈）：离开外壳后 App 时长 ticker 仍在跑 | `ChildShellPage.dispose()` 里用 `ref.read(appUsageControllerProvider.notifier)` 停表 —— 但 Riverpod 的 `ConsumerStatefulElement.unmount()` **先把 ref 标为 disposed 再调 `state.dispose()`**，所以 `ref.read` 必抛 `Bad state: Cannot use "ref" after the widget was disposed.`；而外层 `catch (_) {}` **静默吞掉** → ticker 从未取消 | ① `initState` 抓 notifier 引用存字段 `_usageCtrl`（加注释说明为什么不能走 ref）；② `_stopAppUsageCounting()` 改用该引用；③ 新增 dispose 停表用例（`UncontrolledProviderScope` + 手动 `ProviderContainer`，**排除 `ref.onDispose` 兜底**，只剩 `dispose` 自身路径）→ 修复前红、修复后绿 | ✅ 已修复（测试已锁） |
| G12 | M3/美术契约 | 出图账目与命名契约不匹配「种子通用」的新规划 | 玄参拍板「**种子通用**，幼苗/成株按物种各自出图」，原 3 级候选回退无通用层 | ① `plant_artwork.dart` 候选 **3 级 → 5 级**：`{id}_{stage}_{status}` → `{id}_{stage}` → `{id}` → `shared_{stage}_{status}` → `shared_{stage}`（**物种图恒优先于通用图**）；② 命名契约抽成公开纯类 `PlantArtCandidates`，**护栏测试与实现共用同一份**；③ 出图账目重算：总槽位 **28 → 24**（通用种子 2 + 向日葵 7 + 雏菊 7 + 仙人掌 8），**待出 18 → 17**；④ 美术清单 / 进度表数字全部对齐 | ✅ 已结案 |
| G13 | M3/花园背景 | 玄参换新背景图后，木牌热区与背景尺寸常量仍是旧值 | 背景由 1161×2560 换为 **1056×2336**（构图完全不同） | `kGardenBackgroundSize` → `Size(1056, 2336)`；木牌归一化矩形重新标定为 `Rect.fromLTRB(0.082, 0.642, 0.258, 0.722)`（源像素 x≈86.6~272.4 / y≈1499.7~1686.6）；新增**背景图资产守卫测试**（直读 PNG IHDR 比对常量，改回旧值立刻变红）；木牌弹窗按玄参拍板改名「**玩法说明**」（原「花园说明」），文案扩为完整玩法说明 | ✅ 已修复（**待装机复验**） |

## P0 缺口补全轮（同一批次）

| ID | 项 | 内容 | 状态 |
|---|---|---|---|
| G14 | 调试代码清理 | 删 `child_profile_page.dart` 的 `DEBUG 加1000阳光` 段与「调试区」标题；删 `app_router.dart` `/s1-demo` 路由 + import；删 `s1_demo_page.dart`（grep 证实 `lib/` 内 0 引用，`SunflowerCanvas`/`FeedbackOverlay` 仍被 `focus_page`/`settle_page` 使用不受影响）。新增回归用例「孩子端『我的』页不得再出现 DEBUG 入口」 | ✅ 已结案 |
| G15 | App 总时长防沉迷 | 新增 `lib/domain/services/app_usage_service.dart`（`AppUsageTick` + `advance` + `isCapReached` **唯一判定入口**）与 `lib/presentation/child/state/app_usage_controller.dart`（`Timer.periodic` 计时、切后台暂停、跨自然日清零）；`anti_addiction_service.isAppCapReached` 改为**一行委托**（**判定孪生已消除**）；外壳拦**花园/商店/我的**三个娱乐 tab，**今日/成长永远放行**（有变异测试锁住） | ✅ 已结案 |
| G16 | 纪念册埋点 | 新增 `lib/domain/services/memoir_service.dart`（`ensureWeeklySnapshot` / `recordMilestone` / `recordPraiseSent`）+ 事件名常量。口径按玄参拍板：① 计时**只算**花园/商店/我的（不含今日/成长）；② `praise_sent` 以**「家长写就记」**为 emit 点；③ 里程碑 **4 类** | ✅ 已结案 |

## 本轮校验

- **`flutter analyze`** → **0 error**（3 warning 均为既有测试文件遗留，已 git 对比确认非本轮引入）。
- **`flutter test --no-pub`** → **450 条全绿**。计数演进：412 → 435（QA 补强 +11 等）→ 447 → **450**（+阳光胶囊 2 条 +dispose 停表 1 条）。
- **QA 变异测试（本轮 17 个变异点）**：**15 个有效打红、0 严重假绿**；其中「含今日(0)/成长(1)」两个变异**都打红** = 「专注入口不可被挡」已被测试锁住。
- **G11 的用例有效性已实证**：修复前该用例红（报 `A Timer is still pending`）、修复后绿 —— **不是空转断言**。
- ⚠️ **未装机**：本轮所有改动最后一次真机验证停留在 21:41，需玄参安排 `flutter build apk --debug` + `adb -s f05bbc46 install -r` 复验 G09 / G10 / G13。

---

# iOS 模拟器反馈轮（2026-09-24 深夜）

> 玄参不在真机旁，改为 **iPhone 17 / iOS 27.0 模拟器**验收（逻辑 402×874 @3x）。
> 玄参反馈两条：① 点「+」加盆**仍无响应**（G10 的修复没治到根）；② 点已种植物弹出
> 的养护面板**溢出**（黄黑警示条贯穿全屏，附截图）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| G17 | M3/花园页 | 点「+」加盆**仍然没反应**（G10 修复了数据陈旧，但没治静默点击） | `ExpandPotSlot` 里 `onTap: (affordable && !busy) ? onTap : null` —— **阳光不足时点击被拦成 null**，而页面层 `_confirmAndExpand` 早已写好兜底提示（SnackBar「阳光不足，还差 N ☀」），永远调不到；且 `garden_pot_layout_test.dart` 还把「点了没反应」**锁成了预期行为**。模拟器是新数据（余额 0）→ 必然走这条路径 | `onTap: busy ? null : onTap` —— 阳光不足**仍回调**，分因提示由页面层兜底（文案升级为「阳光不足，还差 N ☀ —— 去专注赚阳光吧」）；busy 防连点保持拦截；测试断言同步改为「点击仍回调」 | ✅ 已修复（模拟器待玄参复验） |
| G18 | M3/养护面板 | 点已种植物 → 养护面板**右侧黄黑溢出条贯穿全屏**（附截图） | `PlantArtwork` 命中美术资源时 `Image.asset` **无显式宽高** → 按**原图逻辑尺寸**布局（画布 1200×2000 @3x → 400×667pt）。草地格子外层有 tight `SizedBox` 兜住所以没事；`PlantCard(size: 44)` 头部 Row 是 **loose 约束** → 必炸。**探针实测：`A RenderFlex overflowed by 870 pixels on the right`，Row size `342×2000`（高度=画布原高）**。真机此前没炸只因美术图接入后没人点开过养护面板 | ① `PlantArtwork` 内 `Image.asset` 包 `SizedBox(width: size, height: size)`（tight 约束下被外层覆盖、草地行为不变；loose 约束下提供安全上限）；② 顺手修养护按钮 label 加 `maxLines: 1` + 「5 ☀」→「5☀」（iOS 字体略宽，emoji 单独换行掉底） | ✅ 已修复（探针复跑实证 0 overflow） |
| G19 | M2/家长端 | 家长赠予 **30 阳光，孩子端「没收到」** | ⚠️ **不是同步 bug**：`kParentGiftDaily = 20`（PRD §4.5 当日赠予 ≤20）→ 赠 30 被 `dayTotal + amount > 20` 直接 return，旧实现只弹一条**一闪而过的 SnackBar** → 家长以为赠成功了，实际一分没入账（**静默失败**，与 G17 同款教训）。同步链路（append + `economyRevision++` + 孩子端 listen）本身完整 | 弹窗**先显示**今日/本月已赠与剩余额度；`StatefulBuilder` 实时校验 → 超额即红字「最多可赠 N ☀」+ **「赠予」按钮禁用**（点不下去）；额度耗尽直接分因 SnackBar 不弹窗；成功后提示含剩余额度；二次校验保留防绕过。⚠️ **日上限 20 是 PRD 口径，未擅改**（属产品决策，待玄参拍板） | ✅ 已修复（模拟器待复验） |
| G20 | 调试设施 | 玄参要求把「DEBUG 加1000阳光」**加回来**（昨晚 P0 清理时删掉的） | 删除后调试不便（刷余额只能靠赠予，而赠予有日上限 20） | 加回至「我的」页底部，但**升级为受 `kDebugMode` 约束**（release 自动不渲染，不必再担心「提审前忘了删」）；且加完后**自增 `economyRevisionProvider`**（旧版只 `_reload()` 本页 → 花园胶囊/商店仍显示旧值）。测试：`child_shell_app_cap_test` 的「不得出现 DEBUG」改为**源码守卫**（正则断言 `if (kDebugMode) … DEBUG 加1000阳光`；widget 测试恒 debug 无法直接断言 release 行为）+ 新增「点按钮真的入账 1000」（spy 账本记录 append 金额） | ✅ 已完成（452 全绿） |

## 本轮校验

- **探针法（本轮最重要的调试手段）**：无模拟器点击能力（`simctl` 无 tap、osascript 无辅助功能权限）
  → 写**临时探针入口** `lib/garden_probe_main.dart`（复用主 App DI 读模拟器里玄参种的真实植物，
  启动后自动弹 `PlantCareSheet`），`flutter run` 的 stdout 直接吐出溢出报告（含 widget 链）。
  **修复前：overflow 870px；修复后：0 异常 + 截图确认面板正常渲染。探针已删。**
- **⚠️ widget 测试抓不到 G18**：`flutter test` 环境 `AssetManifest.loadFromAssetBundle` 读取失败 →
  `PlantArtwork` 静默走自绘占位 → 「命中美术图才溢出」在测试里 `takeException()` 恒为 null（假绿）。
  已新增 `test/m3/plant_care_sheet_iphone_test.dart`（iPhone 17 402×874 渲染真实 GardenPage + 弹面板）
  作为占位路径回归；**真验证靠探针实跑**。
- **`flutter analyze`** → **0 error**；**`flutter test --no-pub`** → **451 全绿**（450 → +1）。
- 正式构建（main 入口）已装 iPhone 17 模拟器并启动，玄参可继续验收。

### 深夜追加：G19 赠予静默失败 / G20 调试入口加回

- **`flutter analyze`** → **0 error**；**`flutter test --no-pub`** → **452 全绿**（451 → +1 调试入口入账用例）。
- G19 的关键结论：**「孩子端没收到」≠ 同步坏了**。排查时先确认**动作到底有没有成功入账**
  （本例是日上限 20 直接 return，只留一条一闪而过的 SnackBar）。
  → 通用纪律：**任何「被规则拒绝」的操作，都必须可见地拒绝**（禁用按钮 / 弹窗内实时报错），
  不能只靠一次性 SnackBar。
- G20 的关键决定：调试入口**不再靠人工记得删**，用 `kDebugMode` 让它 release 自动消失；
  测试改用源码守卫锁住这条约束。

---

# 成株后循环玩法 Batch 1 轮（2026-09-27，分支 `main`，✅ **已提交**：`4ae7a58`）

> 落地「成株后循环玩法 Batch 1」：复开花双档节奏（普通 7/14、精品 ×1.5）+ 花期双阶段奖励（48h 气泡手动收集）+ 物种表改版（8 物种 / 稀有度两档 / 死亡全损 / 月光兰首购）+ 奖励物图标化 & 掉落即定奖（C16）。口径见宪法 **C15 / C16** 与 `docs/成株后玩法_Batch1_PRD.md`。
> 本轮修掉的两个缺陷：

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| B-NEW-1 | M3/花园页 | 点击「48h 奖励气泡」**崩溃**：`SqliteException(1555): UNIQUE constraint failed: pending_bloom_rewards.id` | DAO 对 `PendingBloomRewards` 用**裸 `insert`**，而内存 Fake 实现走 **upsert** 语义 → 真机重复写入同一 pending（同 id）时主键冲突崩溃；**两侧语义不一致**（测试环境的 Fake 掩盖了真机 SQLite 行为） | DAO 改为 **`insertOnConflictUpdate`**（与 Fake 的 upsert 语义对齐）；补回归用例覆盖「同 id 重复写入」 | ✅ 已修复（待真机/QA 复验） |
| DEF-1 | M3/植物成长 | **盛开次数被静默清零**：`bloom_count` 意外归零，复开花档位 / 节奏判定随之不稳 | `_maybeRecover`（枯萎恢复路径）重建 `Plant` 时**漏传 `bloomCount`** → 恢复后 `bloomCount` 回到默认 0（重建时漏参比 `copyWith` 清空更隐蔽） | `_maybeRecover` 重建 `Plant` 时**显式带上 `bloomCount`**；新增回归测试断言「枯萎 → 恢复后 `bloomCount` 不变」 | ✅ 已修复（+ 回归测试） |

**本轮口径关联**：死亡全损（废止 `kPlantDeathRefundRate`）/ 月光兰首购 400 阳光・其后碎片 / 满 8 片手动解锁废止（改花园页按物种直接兑换）——详见 `口径裁定表_v1.md` **C15**；**奖励物图标化 + 掉落即定奖**（`pending_bloom_rewards` +3 列 `reward_sunlight`/`reward_fragments`/`reward_species_id`、schemaVersion **11→12**、花谢自动到账提示、碎片对外改名「植物碎片」）——详见 **C16**。

---

# 养护动效序列帧 + 花园背景音轮（2026-09-28 ~ 09-29，分支 `main`，✅ **已提交推送**：`5b1cf49`）

> 玄参交付 7 物种开花图 + 向日葵三段成长序列帧 + 浇水/施肥帧 + 音频，要求接入并按相机/中央卡演出。三轮模拟器/真机反馈后修复 7 处。口径见宪法 **C18** 与 `docs/美术资源_序列帧与音频命名规范_v1.md`。

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F41 | iOS 构建 | 调试按钮报 `OSStatus -34018`（keychain 解锁失败，App 起不来） | 构建误加 `--no-codesign` → 产物无签名 → keychain 不可访问 | 去掉 `--no-codesign`，走默认 adhoc 自签 | ✅ 已修复 |
| F42 | 美术接入 | 只听到水/肥音效、看不到帧，仍是旧粒子；花盆随帧上下移动 | ① `pubspec.yaml` 的 `flutter.assets` **目录声明不递归** → `grow/sunflower/*`、`care/*` 子目录帧未进包；② 旧 overlay 自绘带盆植物副本且错位 → 花盆跳动 | ① 改登 **5 个叶子目录**（`assets/fx/grow/sunflower/{seed_to_sprout,sprout_to_adult,adult_to_bloomed}` + `assets/fx/care/{water,fertilize}`），新增 `fx_frame_assets_guard_test` 护栏；② **整体删除 overlay 的 plant 层** | ✅ 已修复 |
| F43 | 动效 | 浇水/施肥「一闪一闪」、落点掉到花盆底部而非根部 | ① 720 PNG 逐帧重解码白屏 → 闪烁；② 旧「底边对齐格底」定位 → 帧掉到盆底 | ① `precacheFxFrames` 预载 + `gaplessPlayback`；② 几何重定位：盆口 = 画布 0.659 高，水柱末端 x=0.21、肥 x=0.31，帧宽 1.15×格宽（允许越界），根 Stack 改 `Clip.none` | ✅ 已修复 |
| F44 | 动效 | 进化（开花/成长过渡）动画**没播** | 旧设计在目标花盆格上放大 1.4×，格子太小看不清、与底层花盆重叠显乱，且实际未触发 | 改为**屏幕中央焦点卡**（`GrowthFxOverlay`）：奶油渐变底 + 金色径向柔光 + 阳光黄胶囊标题，弹入 → 播放 → 300ms 整卡淡出 | ✅ 已修复（玄参 2026-09-29 验收「可以」） |
| F45 | 音频 | 花园背景音**从没响过** | `AudioService.applySettings({soundOn,bgmOn})` 全项目**零调用** → `bgm_on` 默认 false 永远不播；且存量库 `bgm_on=false` | ① 接线：外壳 `initState` 读设置后调 `applySettings`；设置页改完即时调；② `bgm_on` 默认 **false → true**；③ v12→v13 迁移把存量 `bgm_on` 翻 true；④ 新增 `startGardenAmbient` 每 30s 循环 `background.mp3` | ✅ 已修复（真 bug） |
| F46 | 美术 | `tools/normalize_plant_art.py` 误把向日葵萎/死 6 图二次缩放（已归一化图被误伤） | 脚本无「防重跑」保护 | 加防重跑：无 `_originals` 备份且已是 1200×2000 则跳过；6 图已从 git 恢复 | ✅ 已修复 |
| F47 | UI | 成长卡片**纯白底不好看** | 旧 `growth_fx_overlay` 用纯白卡 | 重做为「奶油阳光风」中央焦点卡（#FFFDF7→#FFF2D9 渐变 + 暖黄描边 #FFE0A3 + 暖棕阴影），与 App 马卡龙/奶油语言一致 | ✅ 已修复（玄参验收通过） |

**本轮校验**

- `flutter analyze` → **0 error**
- `flutter test --no-pub`（摘四个代理变量）→ **663 全绿**（645 基线 + 新增：`fx_frame_assets_guard`（叶子目录/帧计数/命名/音频/8 图尺寸）/ `growth_fx_overlay` 3 / `migration_v12_to_v13` 4 / `care_effect_overlay` 更新）
- 资产落位：`assets/audio/bgm/background.mp3`、`assets/audio/sfx/{grow_*,care_water,care_fertilize}.mp3`、`assets/fx/grow/sunflower/{seed_to_sprout,sprout_to_adult,adult_to_bloomed}/frame001..025.png`、`assets/fx/care/{water,fertilize}/frame001..025.png`、`assets/plants/species_*_adult_bloomed.png` ×8
- iOS 模拟器（iPhone 17，无 GUI，用 `xcrun simctl` 装启）已装最新奶油卡版；Android APK 仍为旧包、真机未连

---

# 专注/结算页体验修订（2026-09-30，分支 `main`，✅ **已提交推送**：`fb104b1` + `0af3c17` + `fa441e3`（C24/F56）+ `e8ee466` + `7710ed4`（C25/F57））

> 玄参真机验收专注页序列帧（C21）的 4 条反馈：专注静音拍板、构图优化、结算页三问题、欢迎音无声。口径见宪法 **C22**。

| ID | 模块 | 现象 / 报错 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| F48 | 音频 | 离席回来 welcome 动画正常但**无声**（settle 音正常，排除 soundOn/素材问题） | app 刚从后台恢复时音频会话尚未就绪，首次 `play()` 被系统静默吞掉（catch 吞掉无感知） | `AudioService._playSfx` 首败后延迟 600ms 重试一次（仍静默降级） | ✅ 已修复 |
| F49 | 结算页 | settle 动画帧**无限循环**但音效只播一次（6.09s 音 vs 36 帧同速循环 → 失同步感） | C21 按旧口径把 settle 接成 `loop:true` | 玄参拍板「播放一次就可以」：`loop:false + holdLastFrame:true`（新参数：播完停末帧常驻，与音效同起同止） | ✅ 已修复 |
| F50 | 结算页 | 横屏进入结算页 `BOTTOM OVERFLOWED BY 267 PIXELS`（截图实证） | 专注页锁横屏，结束时只「复位方向」（=跟随传感器），手机横持则保持横屏；竖版结算页 Column 超高 | `settle_page.initState` 强制 portraitUp/Down；另加 `LayoutBuilder+SingleChildScrollView+IntrinsicHeight` 滚动兜底 | ✅ 已修复 |
| F51 | 结算页 | 结算页纯黑背景生硬；自制「光回罐+阳光罐」卡与帧内特效重复 | C21 保留了旧矢量时代的特效卡 | 删 `_LightBackToJar`/`_Jar` 及说明小字；背景升级为与专注页一致的深蓝紫渐变 + 暖金光晕（参考潮汐「深色沉浸+层次渐变」） | ✅ 已修复 |
| F52 | 结算页 | <5 分钟短专注（net==0）结算中央回到系统默认矢量向日葵，与正式庆祝帧视觉割裂（孩子困惑「换图了」） | `settle_page.build` 原判定 `net > 0` 才播 settle 序列帧，net==0 走默认花 | 方案A：改为 `settlement != null` 才播 settle 帧——短专注也播（画面统一）；音效仍只在 net>0 播（短专注静音）；仅深链 `settlement==null` 才回退默认花 | ✅ 已修复 |
| F53 | 专注页 | 1/3 收集阳光时文案「我去把它放好。」以底部白色横条压在向日葵身上、遮挡角色 | 旧 `FeedbackOverlay` 为屏幕底部横向白底圆角条 | 重写为「向日葵说话气泡」：暖黄奶油底+深棕字+左下小尾巴指向花心，锚定花头右上，不遮挡；lvl2 文案后修订为「太好了，又收集到阳光了。」 | ✅ 已修复 |
| F54 | 专注页 | 离席≥30s 回来的「欢迎回来」用独立顶部金色大字，与向日葵重叠/压住角色 | 欢迎回来走独立 `Text` 块而非气泡层 | lvl3 现也出气泡（`_bubbleText` 增 `lvl3⇒'欢迎回来'`）；`focus_page` 删独立金色大字块，统一走 `FeedbackOverlay` 右上角气泡，3 秒消失逻辑不变 | ✅ 已修复 |
| F55 | 专注页 | 说话气泡初版被 `Align.topRight` 推到屏幕最右缘，离居中向日葵太远，不像向日葵说的话 | 气泡定位在屏幕边缘而非角色旁 | `feedback_overlay` 去内部 Align/Padding（只渲染本体）；`focus_page` 中部 `Center+SizedBox(s×s)+Stack`，气泡 `Positioned(top:s*0.04, left:s*0.92)` 锚花头右上外沿（随缩放联动），尾巴指向花心 | ✅ 已修复 |
| F56 | 专注入口页 | 预设时长胶囊「点击的时候来回变动」——选中某档后胶囊位置跳动、整排排列不稳（玄参 2026-09-30） | 旧用 `Wrap` 流式排布：选中态会插入打勾图标 → 胶囊变宽 → **触发重新换行（重排）** | 改为**固定三排等宽**布局 `_DurationRow` + `Expanded`（15-20-25 / 30-45-60 / 自由-自定义），胶囊宽度由 `Expanded` 锁定，选中不再引起任何重排 | ✅ 已修复 |
| F57 | 专注页 / 结算页 | 自由专注下**今日额度用完后全程零提示**：孩子不知道已不再产阳光，只有结算才发现「时长够却没阳光」（C24 遗留边界） | 额度收口只在入口（灰档 / 开始前截断）与结算（硬截断）两处，**专注进行中没有任何反馈** | 玄参拍板「轻提示、不打扰、**不加定时器**」：判定**复用专注页既有每秒 `_ticker`**（`_maybeShowQuotaHint()`），命中即在**屏幕左上角**淡入暖黄小卡（不遮挡居中向日葵），驻留 `kFocusQuotaHintSeconds=8` 秒后淡出、**整场仅一次**；判定抽为公开纯函数 `focusQuotaExhausted`；超额的完整说明放**结算页**（取 `settlement.capped` + `rawS` 显示「原本 X ☀️，实到 Y ☀️」） | ✅ 已修复（✅ **已提交**：`e8ee466` + `7710ed4`） |

**同轮非 Bug 拍板（玄参）**：专注中**不放 BGM**（`focus_loop.mp3` 资产保留不使用）；专注页构图优化（elapsed 放大 46 号主视觉、向日葵 320→`kFocusStageSize=220`、底部提示半透明胶囊、双页深色渐变）。

**本轮校验**：`flutter analyze` 0 error（92 info 基线）；`flutter test --no-pub`（摘四代理）**679 全绿**（678 + `holdLastFrame` 行为用例 1）。

---

## 2026-09-30 深夜轮：入口页档位三排 / 删横屏贴士 / 自由专注

**同轮非 Bug 拍板（玄参）**：

1. **删除底部「把手机横过来…」引导贴士**——直接点「开始专注」即可，不再口头引导转横屏。
2. **时长档位固定三排**：15-20-25 / 30-45-60 / 自由-自定义；`kFocusDurationOptions` 由 `[15,20,25,30,45]` 增至 `[15,20,25,30,45,60]`（补 60 档）。
3. **新增「自由」档（自由专注）**：不预设时长、**不自动结算**，孩子自己决定何时结束；计时照走、每日额度与防沉迷约束仍在。落库 `plannedMin=0`（`plannedMin==0` 在结算 / 成长项 / 完美日各处既有守卫天然兼容）。
4. **「提示音效」开关保留不动**——该开关实际控制收集阳光 / 欢迎回来 / 结算庆祝音效；删除会导致这些音效**默认常响**（仅家长端可关），故维持现状。

**实现落点**：`app_constants.dart`（档位 +60）、`focus_engine.dart`（构造增 `freeMode=false`；`_advance` 到时判定加 `!_freeMode` 守卫 → 越过 planned 不自动结算，离席打断 / 产光 / 额度照旧）、`focus_page.dart`（增 `freeMode`；自由模式引擎 `planned` 改用 `kFocusDurationDefaultMinutes`(20) **仅推导 1/3 报信节奏**；计时标签「自由专注」、隐藏「/ 计划时长」）、`app_router.dart`（`free=1` → `plannedMinutes:0` + `freeMode:true`）、`entry_page.dart`（删横屏贴士、`Wrap` → 三排等宽、增 `_free` 状态、`_start()` 自由分支跳 `free=1`）。

**护栏**：`focus_engine_advance_test` 新增 **N 组 4 条**——N1 越过 planned 不结算仍 running 且产光照旧 / N2 手动 `stop()` 出 manual 结算 / **N3 对照组：非自由模式仍自动 `timedOut`**（防改坏定时专注）/ N4 自由模式离席 320s「打断」照旧生效。

**本轮校验**：`flutter analyze` 0 error；`flutter test --no-pub`（摘四代理）**684 全绿**（680 + 自由模式 4）。

**已知边界（已于同日定夺，见 F57 / 口径 C25）**：自由模式仍是「孩子点结束才结算」+ 结算侧额度硬截断；额度用完后**不自动弹结算**（违背「孩子自己决定何时结束」），改为**专注页左上角轻提示卡 + 结算页超额说明**。

---

## 2026-09-30 额度提示轮：自由专注额度用完的告知方式

**玄参拍板（2026-09-30）**：

1. **否决「在专注页加额度看护定时器」**——自由专注的精神是孩子自己决定何时结束，软件不应替他结束，也不该常驻一个轮询定时器。
2. **只在专注页轻弹一次提示卡**（左上角、8 秒后淡出、不遮挡向日葵、不可点击、不暂停专注），**不新增定时器**（复用既有每秒 tick 判定）。
3. **超额的完整说明放在结算页**：显示「原本 X ☀️，实到 Y ☀️」，让孩子理解「不是向日葵没收，是今天的额度到顶了」。
4. **额度三处收口（入口灰档 / 开始前截断 / 结算硬截断）一个不动**——本轮只新增「告知」，不改任何扣费或截断结果。

**实现落点**：`prd_params.dart`（`kFocusQuotaHintSeconds = 8`）、`focus_page.dart`（`_maybeShowQuotaHint()` + `_FocusQuotaHintCard` + 顶层纯函数 `focusQuotaExhausted`）、`settle_page.dart`（`capped` / `rawS` 超额说明卡）。

**护栏**：新增 `test/m3/focus_quota_hint_test.dart` **6 条**纯函数用例（充足 / 差一点 / 刚好 / 超出 / 零头 <1min / 为 0）。

**本轮校验**：`flutter analyze` 0 error；`flutter test --no-pub`（摘四代理）**690 全绿**（684 + 6）。

**纪律说明**：本轮代码先于文档提交（commit `e8ee466`），文档（口径 C25 / bug F57 及本段）随后补齐 —— 玄参已明确：**「同步到 GitHub」＝先同步相关文档、再提交推送，两者同批完成**，后续不得再拆分。


---

## 2026-10-03 全项目盘点轮（资源缺口发现，**未改码**，待玄参定夺）

> 玄参 2026-10-03 要求「同步文档、保持台账与代码一致」。本次盘点用 `ls assets/{plants,rewards,fx,audio}` + 代码 grep 实证，
> 查出 **两条 690 测试全绿也测不出来的资源缺口**（不崩、不报错、静默回退）。**AI 不改码，只登记 + 出方案。**

| ID | 模块 | 现象 | 根因 / 实况 | 建议 | 状态 |
|---|---|---|---|---|---|
| **F58** | 奖励图标（头顶/掉落物） | 奖励物图标位**显示成内置矢量 `Icons`**，而非美术图标 | `lib/presentation/child/widgets/bloom_reward_icons.dart:151/154/158` **只认** `assets/rewards/sunlight.png` / `fragment.png` / `seed.png` 三张；实测 `assets/rewards/` 目录里**只有一个 `README.txt`**，清单为空集 → 回退链直接落到内置 `Icons`，**不抛异常、无日志** | 补三张 PNG 到 `assets/rewards/` 并在 `pubspec.yaml` 逐个登记叶子目录（**目录声明不递归，登父目录 = 静默不进包**，同 F42 坑）；等价于 C16「奖励物图标化」美术侧此前**并未真正落地** | ⬜ **待玄参确认图标位是否为空 → 我接手补图 + 登记**（链路已贯通） |
| **F59** | 植物美术（非向日葵 6 物种） | 非向日葵物种（番茄/草莓/月光兰/星辰花/虹影蕨/珊瑚岭兰/翡翠绣球）**只有 `*_adult_bloomed.png` 一张**，`sprout` / `adult` 各状态（growing / wilting / dead）**全无图** → 回退到⑥自绘占位 `[PlantPlaceholderArt]`（简笔绿块 + emoji） | 出图只覆盖了「开花态」；种子期靠 C20 三张通用图兜住，**因此整条主链路看起来是通的**，掩盖了中后期缺口 | 属**出图量决策**：建议「幼苗先通用（`shared_sprout`）、成株按物种差异化」混合方案，先补向日葵以外 6 物种的成株三态 + 通用幼苗；**口径待玄参拍板**（项目决策点） | ⬜ **待玄参拍板出图范围** |

**本轮校验**：`flutter analyze` 0 error（92 info 基线）；`flutter test --no-pub`（摘四代理）**690 全绿**。
**本轮其他**：校准 `项目进度跟踪表.md`（提交数 38→**45**、测试 663→**690**、HEAD `58ce640`→`7710ed4`、补记 §1.7 五个提交、§4 美术线重盘）；
新立**「提交前文档同步纪律」**（见 `项目进度跟踪表.md` §7）——每次 push 前必须同步本表 + 进度表 + 口径裁定表 + 产品开发/软件设计文档，文档未齐不得 commit/push。

## 2026-10-03 C26 花园干扰物轮

> 实现 C26（杂草/害虫）过程中，新功能与存量测试互相作用的**三条实现级坑**，全部有测试钉死。
> 本轮校验：`flutter analyze` 0 error（97 info 基线）；`flutter test --no-pub`（摘四代理）**706 全绿**（修复前 31 条红）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F60** | `Plant.copyWith` | 测试 ③「拔草后成长恢复」失败：`copyWith(weedAt: Plant.kClear)` 清不掉字段，杂草永远在 | 「未传」与「清空」用**同一个哨兵实例**，`_resolve` 把显式清空判成「没传」→ 静默保持原值（即 `copyWith ?? this.x` 老坑的变体） | 改**哨兵三态**：`_unset`（未传，默认）/ 传入值 / `Plant.kClear`（清空）三个不同实例；`garden_weed_pest_test` 哨兵三态用例钉死 | ✅ 已修复 |
| **F61** | `GardenPot` 布局 | 干扰物浮标接入后，「空盆与有植物盆图片框等大」测试红（83.7 vs 139.5，恰为 5:3 倒置） | 植物图从「紧约束 SizedBox 直包」改成 `Stack(fit: StackFit.loose)` 子级后失去紧约束，占位图按**自身逻辑尺寸**布局（测试环境无真图，回退占位） | 植物图改 `Positioned.fill` 钉满紧约束框，浮标仍走 `Positioned` 叠加（不占布局高度）；几何契约与改造前完全一致 | ✅ 已修复 |
| **F62** | 存量测试回归 | C26 接入后全量 **31 条红**：GardenPot 新 required 回调 2 文件编译失败；成长/奖励类测试的精确天数与「结算零消耗」断言被打红 | ① 干扰物 roll 走主随机源，消耗随机数且可能 roll 出杂草 → 成长暂停、盛开分支被跳过（seed=2 实证）；② 固定种子治标不治本（序列跑久了必命中 40%/25%） | 服务构造器加独立 `Random? weedRandom` 注入点（默认与 `random` 同源，生产行为不变）；存量测试注入 `NoHitRandom`（`test/helpers/no_hit_random.dart`，`nextDouble()` 恒 0.999…，永不命中、不耗主序列） | ✅ 已修复 |
| **F63** | iOS 模拟器钥匙串 | 点击家长空间 → `PlatformException(-34018, "A required entitlement isn't present")` | ① 项目从无 `.entitlements`，`flutter_secure_storage`（PIN 哈希）在 iOS 缺 **Keychain Sharing** 权限；② 首次修复后又失效：给模拟器装的包是 **`--no-codesign` 构建**（禁签 → entitlements 根本不进 App）；③ `$(AppIdentifierPrefix)` 在模拟器 ad-hoc 签名下展开为空 → 条目被打包工具剥离 | 新建 `ios/Runner/Runner.entitlements`（keychain-access-groups **硬编码** `6NW722K2GN.com.sunflowertime.app`）+ `pbxproj` 三个 Runner 配置加 `CODE_SIGN_ENTITLEMENTS`；模拟器构建**禁止 `--no-codesign`**。验证：`otool -s __TEXT __entitlements`（新 Xcode 由链接器嵌 entitlements 进该段，签名 blob 空属正常）。⚠️ 手动重签 .app 会 launch 失败，勿做 | ✅ 已修复（玄参 2026-10-03 真机确认） |

## 2026-10-03 除草 / 除虫动效轮（C27）

> 玄参真机验收除草/除虫动效过程中发现的两条缺陷，全部修复并复验通过。
> 本轮校验：`flutter analyze` 0 error（info 基线）；`flutter test --no-pub`（摘四代理）**718 全绿**（+2 条帧契约护栏）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F64** | 花园清除演出 | 点杂草后**草瞬间消失**，除草动画播在空盆上（玄参：「应该动画播完了之后再消失」） | 「写库 + 延迟 UI 刷新」的草地刷新有**两条独立触发路径**：`_run` finally 内部静默刷新 + `economyRevisionProvider` 的 `ref.listen` 监听。第一版只挡了内部刷新，监听路径仍把草在动画开播前移除 | 加 `_suppressReload` 抑制闸门**同时压制两条路径**：写库阶段置 true → 动画播完 → 浮标淡出 300ms → 解锁并 `_reload(silent)`。⚠️ 凡「写库 + 延迟 UI 刷新」的动效流程，必须同时挡两条路径，只挡一条必然漏 | ✅ 已修复（玄参复验通过） |
| **F65** | 清除成功飘字 | 「除草成功，阳光+1」**显示不全**（窄格截断成省略号）；且玄参要求「阳光」用图标不是文字 | 飘字是单行 `Text` + `TextOverflow.ellipsis`，花盆格窄时被截断；纯文字无图标 | ① 内容改富排版「文字 + 阳光美术图标（`assets/rewards/sunlight.png`，缺失回退内置图标）+ 数字」；② 胶囊外套 `FittedBox` 等比缩放，超宽整体缩小不再截断；③ 起始位置上移到花盆格垂直中心（玄参「出现位置在花盆口上方一点」） | ✅ 已修复（玄参复验通过） |

## 2026-10-03 休息节奏计时轮（F66）

> 玄参真机反馈：完成 2 场专注后锁屏离开 20 分钟，回来点专注仍被要求「休息满 10 分钟」。
> 本轮校验：`flutter analyze` 0 error（info 基线）；`flutter test --no-pub`（摘四代理）**726 全绿**（+8 条 F66 单测）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F66** | 防沉迷·休息节奏 | 第 2 场结束后锁屏离开 ≥10 分钟，回来点「开始专注」仍弹**满 10 分钟**休息倒计时；杀进程后同样复发 | ① `restRequired` 按「今日完成场数 % 2 == 0」判定无误；② `restSatisfied` 是**内存 StateProvider**，唯一置 true 途径 = 休息页本地 `Timer.periodic` 走完；③ **Timer 只在休息页打开且 App 前台时走**——锁屏/切走期间计时冻结，真实休息时长不被计入；④ 标记不落库，杀进程即丢 | **墙上时钟推导，零 schema 变更**：休息义务起始基准 = 今日最后一场完成会话的 `end`（触发场结算时刻）。`AntiAddictionService` 新增 `lastCompletedSessionEnd` / `restNaturallySatisfied`（结束至今 ≥ restMinutes → 自动放行）/ `restRemaining`（剩余 = restMinutes − 已流逝，基准缺失回退完整时长安全侧）三个纯函数；`entry_page._start` 传入「内存标记 OR 自然满足」；`rest_page` 打开时按墙上时钟校正剩余秒数。休息的本质是眼睛离开屏幕——待在休息页、锁屏、切走都算休息；幂等、杀进程不丢 | ✅ 已修复（8 条单测钉死；待玄参真机复验） |
| **F67** | 音频·花园氛围音 | 花园背景音（ambient `background.mp3`）播放中，浇水/施肥/除草音效一响，**背景音被打断**且养护结束后**不再恢复**（静默直到离开花园） | ambient 与 SFX 在 `AudioService` 内虽是**独立 just_audio 播放器**，但共享同一 iOS 音频会话：SFX 播放器启动触发会话激活/重配 → just_audio 默认打断处理把 ambient **暂停**，而原逻辑**无任何续播机制**（`_ambientPlaying` 翻 false 后只剩花园页 30s 定时器兜底，会话激活混乱时甚至一直静默） | **自愈监听**：`_playGardenAmbient` 首次拿到播放器时挂 `playerStateStream` 监听——花园 tab 可见（新闸门 `_ambientShouldPlay`）且设置开启期间，凡「应播而未播」的**非自然暂停**（paused/idle，非 completed）→ 1s 节流后从头续播；配套 `_ambientReloading` 主动重载窗口守卫（防止把自己的主动 stop 误判为打断）、`stopGardenAmbient` 先翻闸门再停、`dispose` 取消订阅复位。判定逻辑收口纯函数 `ambientNeedsHeal`（4 条单测）。口径不变：ambient 仍 30s 一次、不循环 | ✅ 已修复（4 条单测钉死；待玄参模拟器复验） |
| **F68** | 花园·养护文案 | 玄参儿子给开过花的成株（复开花期 59%）施肥，预期 +3% 实际 59%→60%（实为 +1.2% 截断显示），被当计算 bug 上报 | **数值链路无误**：复开花增量走 Batch 1 拍板的 `kRebloomFertilizeProgressGain=0.012`（复开花放缓口径）；真 bug 是按钮/帮助文案**写死首花增量**（「施肥 +3%」「浇水 +1%」），复开花（普通/精品）植物显示的承诺与实际涨幅不符 | 玄参拍板**方案 A（修文案不动数值）**：`PlantGrowthService` 新增**公开单点口径** `careProgressGain({bloomCount, isPremium, firstGain, rebloomGain})`（私有 `_careProgressGain` 改为委托它）；`plant_card` 按钮、帮助浮层改走单点——首花标 +1%/+3%，复开花标 +0.8%/+1.2%（精品再 ÷1.5），与落库增量恒等；帮助浮层加「花谢后重新养时增量会小一些，看按钮上的实际数字」括注；3 条单测钉口径 | ✅ 已修复（文案随单点口径；待玄参模拟器复验） |
| **F69** | 护眼·结算页接线（C28 交付缺口） | 专注页已传 `SettleArgs.eyeCarePending`，但**结算页从未消费**——场末「先护眼、后领奖励」实际未生效；`_eyeCareDone` 声明后从未赋值 | 工程交付遗漏（工程师多轮 429 中断后手工收尾，漏接此环节）：C28 §1 场末插入点只完成了一半（专注页判定 + 参数传递有，结算页消费无）；widget 测试未覆盖该接线故未红 | 本轮随「结算页显示护眼奖励」需求一并补线：① `settle_page` initState postFrame 按 `eyeCarePending` 压入 `EyeCarePage`（skipAllowed 读设置，失败安全侧放行）；② 收 `EyeCareResult` 后翻 `_eyeCareDone`、记 `_eyeCareReward`（完成 = `kEyeCareRewardSunlight`，账本由护眼卡内部写入）；③ 护眼未收口时结算数字以「···」占位（先护眼后领奖励渲染闸门）；④ 新增「护眼奖励」行（完成 `+2 ☀️` / 跳过或未触发 `0 ☀️`，玄参拍板）；⑤ 文案「收到阳光」→「收集阳光」；3 条 widget 测试钉（含 offstage finder 坑：全屏路由下结算页被标 offstage，`find.text` 需 `skipOffstage:false`） | ✅ 已修复（待玄参模拟器复验） |

| **F70** | 花园音频 | 花园页**锁屏 / 退后台**后背景音乐继续响 | 花园页 30s 氛围音定时器在后台仍触发，且退后台只 stop 不拦新请求 → 定时器把音乐重新拉起 | AudioService 加**后台挂起闸门**（`pauseAllForBackground`/`resumeFromBackground` + `_suspendedForBackground`，挂起期间 `startBgm`/`playGardenAmbient` 直接短路），child_shell_page `didChangeAppLifecycleState` 接线；新增 `audio_background_suspend_test.dart` 2 用例。**v2（玄参 2026-10-05 复测仍响）**：闸门只在播放请求入口查一次，`setAsset/seek` 几百 ms 异步间隙内退后台会在途加载把音乐拉起 → `startBgm`/`_playGardenAmbient` 改 `play()` 前**二次复查**闸门（挂起态 stop 不发声、不置「应播」标记） | ✅ 待真机（v2 后需复测） |
| **F71** | 花园音频 | 花园页**切到其他 tab**后背景音乐继续播完整曲 | 花园页靠 `TickerMode` 依赖重建判「自己可见性」并启停氛围音，但 IndexedStack 更新隐藏子树的时机不保证本页立即重建 → stop 迟到或缺失 | 外壳 `_onSelectTab` 同步写入新增 `childShellTabIndexProvider`；花园页 build 改 **watch provider 确定性推导可见性**（不再依赖 TickerMode 重建时机） | ✅ 待真机（**2026-10-07 v3 见 F81**：stop 后在途 play 竞态 → 代际 guard） |
| **F72** | 花园 UI | 点奖励**阳光图标**直接消失、无「向上飘动淡出」动效（碎片图标正常） | 格内 `CollectGhost` 挂在花盆格 Stack 里，收集成功后 `_reload` 重建格子子树（奖励条移除 → 无 key 子节点整体重挂）→ 动画元素被销毁重建、动效被打断 | 幽灵改**根 Overlay 浮层**（脱离页面重建树 + 不受格内裁剪）：点击时经 `_potKey` RenderBox 取全局矩形插入 `OverlayEntry`，0.9s 动画 + 950ms 定时器兜底双保险，dispose 显式移除 。**v2（玄参 2026-10-05 复测：点阳光图标仍直接消失，碎片正常）**：真根因是**素材缺失**——`assets/rewards/` 只有 `fragment.png` 与两个种子图，**无 `sunlight.png`**；幽灵规则「解析不到素材的图标项不渲染」→ 纯阳光奖励的幽灵整个为空。修法：`CollectGhost` 改「清单可用（非空集）但个别素材缺失 → 内置 Icon 兜底照样飘」，测试环境空集维持不渲染；真素材 `sunlight.png` 落包后自动替换（F73） | ✅ 待真机（兜底已修 + F73 素材待交付） |
| **F73** | 花园美术 | `assets/rewards/` **缺 `sunlight.png`**：头顶奖励图标/幽灵的阳光项全部走内置 Icon 兜底（F72 v2 根因） | 素材交付缺口（2026-09-27 奖励物图标化时仅交付 fragment + 分档种子） | ✅ **2026-10-06 玄参已交付落包**；pubspec 目录注册本就在，重建即全量生效（头顶图标/幽灵/价签/飘字自动换素材）。同日玄参要求「所有用到阳光图标的地方都替换」→ 今日页阳光卡、阳光来源页余额横幅、家长报告本周专注卡、玩法说明「怎么挣阳光」行四处**写死内置图标**的点也改为素材优先 + 内置回退 | ✅ 已闭环（待玄参复测） |
| **F76** | 花园动效 | 一键浇水/施肥的每盆脉冲小图标（`_PotPulse`）**显示 1s 就消失，比同播养护音效（浇水 2.90s / 施肥 3.06s）短**（玄参 2026-10-06 真机反馈） | 脉冲总时长写死 1000ms、清场定时器写死 1100ms，未与音效时长联动 | `_PotPulse` 时长改按类型取 `kCareWaterDurationMs`(2900)/`kCareFertilizeDurationMs`(3056)（与效果帧常量同源单点）；清场定时器 = 脉冲时长 + 150ms；除草/除虫（逐株另有完整效果帧）维持 1s | ✅ 待玄参复测 |
| **F77** | 花园音频 | **收集音效无声**（玄参 2026-10-06 反馈，首轮修复「填静音」后复测仍无声） | **两层根因叠加**：① 素材层——iOS CoreAudio 无法解析过短 MP3，初版 1.04s 的 `collect_reward.mp3` 报 `-11849 NotOptimized`；② **框架层（主因）——just_audio 0.9.46 `setAsset` 把 bundle 资产拷贝到 `tmp/just_audio_cache/` 并只按路径判缓存、不校验内容**，旧 1.04s 拷贝在 App 数据容器 tmp 里长期存活（simctl/应用更新不清 tmp）→ 新素材永不生效，探针实证：同字节改名 `probe_pad.mp3` 能播、原名必挂 | ① ffmpeg `apad` 填静音至 3.58s（听感不变，红线「sfx mp3 ≥3s」已入命名规范 §4.1）；② `AudioService` 冷启动首次用播放器前调 `AudioPlayer.clearAssetCache()`（官方 API，一次性清 `just_audio_cache`），保证素材永远取自当前包；探针实测清缓存后 `setAsset OK dur=3.544s → play() OK`。诊断日志（SFXDBG）已摘除，探针文件已删，原件备份 /tmp | ✅ **已修复并复测通过（玄参 2026-10-06）** |
| **F74** | 花园 UI | 左下角木牌**热区框比牌面大出不少且错位**（玄参 2026-10-06 截图反馈） | 2026-09-23 标定与实际牌面不符：旧归一化矩形底边下探 ~35px 压到栅栏、顶边高 ~13px 在草上、左边缩进牌内 ~28px | PIL 逐像素扫「浅木色」边界 + 网格目视复核：牌面实测 x 58~268 / y 1513~1652 → 重标 `kGardenSignNormalizedRect = (0.0511, 0.6451, 0.2576, 0.7102)`（含 ~5px 点按余量，320 宽屏热区高仍 ≥44）；`garden_layout_v3_test` 独立推导常量与两处硬钉值同步 | ✅ 待玄参复测 |
| **F75** | 花园动效 | 头顶奖励图标**浮动不均匀**（有时高有时低、有时快有时慢，玄参 2026-10-06 反馈） | ① `_ctrl.repeat(reverse: true)` + `sin(2πv)`：往返边界（v=0/1）处于静止点、**最大速度瞬间反向**（快/慢感）；② 各漂浮条独立控制器从 0 起步，**相位不同步**（高/低感） | 改单向 `repeat()`（v 回绕处 sin 值与导数均连续，全程匀滑）+ 所有 `_Bobbing` 按纪元时钟推导同一初相（`millisecondsSinceEpoch % 1400`），duration 恒定 → 同涨同落、重建不跳相 | ✅ 待玄参复测 |
| **F78** | 花园经济 | 点一次「催熟到成株」后**一次蹦出好几个奖励**（第一株向日葵头顶一排 7 个奖励图标，玄参 2026-10-07 截图反馈） | **旧轮 pending 永久滞留累积**：`tickAll` 先 `_advanceGrowth`（花谢回落→重新开花→**插新轮 pending**）后跑 `_autoSettleUncollectibleRewards`；旧豁免条件只看「此刻 status==bloomed」→ 重新开花后旧轮未领取 pending 被豁免（植物看起来在盛开）、滞留不结算，每轮花谢再累积一排 | 判定单点 `_isRewardCollectible(Plant?, PendingBloomReward)`：**盛开 且 `!r.dueAt.isBefore(p.bloomedAt!)`（同轮花期）** 两个条件缺一不可；顺带开花奖励改每日 8 点晨露（C30）后 pending 条数变多，此修复成为前置必要 | ✅ 代码侧多场景复验通过；⚠️ 用户真机复测待确认（疑似其测试包为修复前构建） |
| **F78（补）** | 花园经济 | 同上（催熟到成株后头顶奖励图标显示） | —（二次修订，非新根因） | **2026-10-07 二次修订**：同轮花期判定加 **1s 时钟容差**（新常量 `kBloomSameRoundToleranceSeconds`），吸收同一 tick 内的时钟抖动——`_isRewardCollectible` 的「同轮」下界由 `p.bloomedAt` 放宽为 `p.bloomedAt - 1s`，`dueAt` 落在该窗口内即视为本轮；防御性硬化，不改 C30 晨露口径 | ✅ 代码侧多场景复验通过；⚠️ 用户真机复测待确认（疑似其测试包为修复前构建） |
| **F79** | 品牌/构建 | **Android 桌面图标还是原始默认图**（玄参 2026-10-07 反馈；APP 名称中文已生效） | C27 只生成了 iOS 15 档 + 声明了 `@mipmap/ic_launcher`，**Android mipmap 5 档从未替换**（`mipmap-*/ic_launcher.png` 全是 2026-09-15 默认 544B 占位），且无 anydpi-v26 自适应图标 | sips 从 `assets/appicon/icon_1024.png` 重新生成 48/72/96/144/192 覆盖 mdpi~xxxhdpi；Manifest 引用不变（无 round/adaptive），换图重跑 `tools/` 流程即可 | ✅ 已修复，待玄参真机看桌面图标 |
| **F80** | 花园 UI | 点植物后**种植卡弹出前明显卡顿**（支付按钮要等 DB 查券，玄参 2026-10-07 反馈「同步到种植卡慢」） | `_openPlantSheet` 每次打开现场 `await` 查 `plantPaymentOptions`（含券表查询），主线程等 DB 往返 | `_reload` 末尾**预取** `_paymentButtonsCache`（speciesId→buttons，数据变化时随 `_reload` 刷新）；`_openPlantSheet` 读缓存零等待，未命中（如刚改动券）现场查兜底 | ✅ 待玄参复测 |
| **F81** | 花园音频 | **切 tab 后背景音「停一下又继续直到播完」**（F71 v2 修复后玄参 2026-10-07 复测仍挂） | **stop 后在途 `play()` 竞态**：`_playGardenAmbient` 内有多个 await 间隙（取播放器/setAsset/play），stop 发生在间隙中时，旧代码继续执行 `play()` 并**重置 `_ambientShouldPlay=true`** → 已停的氛围音被重新拉起 | **代际 guard**：`_ambientGeneration` 计数，`stopGardenAmbient`/`dispose` 递增；`_playGardenAmbient` 开头捕获 gen，**每个 await 间隙后校验**，被 stop 过一律 stop+作废、不置「应播」标记；新增 `audio_background_suspend_test` ⑥ 代际用例 | ✅ 待玄参复测（v3） |
| **F82** | 花园音频 | **首次安装后第一次进花园背景音乐不响**，切几次 tab 才响（玄参 2026-10-07 真机反馈） | **冷启动首次启动被丢弃**：首次进花园时 iOS 音频会话尚未激活 / `AudioPlayer.clearAssetCache()` 清缓存后 `setAsset` 首次异步加载未就绪，此时 `play()` 在会话未就绪时被静默吞掉；原 `_playGardenAmbient` **只尝试一次**、失败即放弃置「应播」标记 → 只能等 30s 定时器或切 tab 重建子页才补播 | `AudioService` 新增静态 `startAmbientWithRetries({start, isPlaying, shouldAbort, onAbort, maxAttempts, retryDelay})`——最多 **3 次**、间隔 **400ms** 重试启动，**每次 await 间隙校验** `shouldAbort`（后台挂起 / 花园不可见 / 代际被 stop）避免误播；`_playGardenAmbient` 改走它，且**仅在真正 `started` 后**置 `_ambientShouldPlay = true`；常量落 `prd_params.dart`（`kAmbientStartAttempts = 3` / `kAmbientRetryDelayMs = 400`）；`audio_background_suspend_test` 新增 **F82** 用例组（首次进入重试直至成功 / 不可见期间不重试） | ✅ 待玄参真机复测（F70/F71/F81 口径不破） |
| **F82（补）** | 花园音频 | **首次进花园仍不响**（玄参 2026-10-07 真机复测反馈；F82 首修后仍挂） | **设置迟到竞态 + 未记录「想播」意图**：冷启动时 `playGardenAmbient()` 在 `_bgmOn`（默认 false）判定**之后**才 return → 连「想播」意图都没记，设置随后变 true 也**无人补触发**（只能等 30s 定时器 / 切 tab 重建子页） | `playGardenAmbient()` 改为**先记 `_ambientShouldPlay = true` 再判 `_bgmOn`**（意图与开关解耦）；`applySettings` 在「`bgmOn` 转 true 且意图仍在且未在播且未挂起」时**补播一次**（`_playGardenAmbient()`）；`stopGardenAmbient()` 清意图并 ++代际。代码侧用例已覆盖（`test/m3/garden_ambient_settings_late_test.dart`，3 条） | ⚠️ **待玄参真机复测** |
| **F83** | 花园音频 | **养护 / 种植音效一响，花园背景音就被打断、然后重头开始**（玄参 2026-10-07 真机反馈） | just_audio 0.9.46 `AudioPlayer` 默认 `handleInterruptions: true`，同 App 内 SFX 启动即被视作音频会话打断 → 氛围音被 `pause()`，只靠 `_attachAmbientHeal`「1s 后从头续播」兜底，听感＝断掉重来 | 背景类播放器（BGM / 花园氛围音）改 `AudioPlayer(handleInterruptions: false)`（`_defaultBackgroundPlayerFactory` / `_createBackground()`）；SFX 保留默认（尊重真实系统打断）；叠加 **ducking**（`kSfxDuckAmbientVolume`=0.35，SFX 播完或 `kSfxDuckMaxMs`=5000 兜底恢复）——「背景音正常播放，或降低音量」 | ⚠️ **待玄参真机复测** |
| **F84** | 花园 UI / 提示 | **一键操作空计划提示仍走底部 SnackBar 且停留久**（玄参 2026-10-07 截图实证） | 该分支走 `_snack()` 而非常驻居中浮层——C32 只改了「一键成功汇总」路径，「计划为空 / 阳光不足」两条**仍是底部 SnackBar**（「两条提示路径」又一次） | 空计划 / 阳光不足分支统一改走 `_showBatchHint(...)`（根 Overlay 居中浮层，节奏同 C32：120/1000/300ms）；`_RisingHint` 增 `showSunlight`（`sunlight=0` 不渲染 ☀ 段）；其它流程 SnackBar 不动。行为级用例 `test/m3/one_click_empty_hint_center_test.dart` | ✅ 待真机复测 |
| **F85** | 花园音频 | **ducking 低压从未生效**（A 项只兑现「背景音正常播放」那一半）；**关 BGM 停不掉**在播氛围音；**每次设置同步会把在播氛围音从头重启**（QA/Edward 独立反证用例实测复现） | `_ambientPlaying` 是 `_playGardenAmbient()` 的**加载窗口**标记（起播前置 true → finally false，**稳态恒 false**），却被当作「正在发声」用于**三处**前置判断：① ducking（`_duckAmbientForSfx` 恒判 false → 死代码）；② `applySettings` 关 BGM 分支（`!_bgmOn && _ambientPlaying` 稳态永假 → 停不掉）；③ `applySettings` 迟到补播分支（`!_ambientPlaying` 稳态恒真 → 每次同步重启）。正确稳态信号 = `player.playing` | 拆成两个语义判据：`_ambientAudible`（= `player.playing && _ambientShouldPlay && _bgmOn`，用于 **duck/恢复**）+ `_ambientRunning`（= `_ambientPlaying \|\| player.playing`，用于 **applySettings**）；新增幂等位 `_ambientDucked`（防堆叠压低）；**恢复侧与 duck 侧同判据**（防压低后永久卡 0.35）。⚠️ 判据成立**依赖 just_audio 保证**：`play()` 后 `playing` 保持 true 直到 `pause`/`stop`，曲目自然播完**不翻 false**（`just_audio-0.9.46/lib/just_audio.dart` `play()` 文档 ≈:927-933）；护栏 = QA 的 `A-核心` 用例（稳态播 SFX 必须见 `volume:0.35`），premise 一旦被破坏即红。文档禁令：`_ambientPlaying` **仅表示加载窗口、禁止用作稳态判据** | ✅ 已修复（QA 独立反证 8/8 + 恢复①/恢复②/同源①/同源②；`analyze` 0 error；待玄参真机复测） |
| **F86** | 花园音频 | **冷启动首次进花园完全没声音**，要等约 30s 后才响（玄参 2026-10-07 真机反馈） | **项目从未调用 `AudioSession.instance.configure(...)`**（全仓库 grep 该调用为空）→ Android 音频会话未声明 → 冷启动**首次** `play()` 的渲染管道不启动。真机日志铁证（`/tmp/amb_r5.log`）：卡死轮 `22:52:36.620 playing=true processingState=ready` → 之后 **29.5 秒零事件、永远无 completed**；正常轮 `22:53:06.219` → `22:53:16.536` completed（实播 10.32s）→ 症状正是「不响，等 30s 定时器才响」。之所以「之后会响」：一旦有 SFX 播过（SFX 播放器用 just_audio 默认 `handleInterruptions:true` 会自行激活会话），后续氛围音即正常 | `AudioService` 新增 `_ensureAudioSessionConfigured()`（幂等守卫 `_audioSessionConfigured`，**先置位再配置**，并发只真正配置一次、失败静默不反复重试），在 `_sfx` / `_bgm` / `_ambient` 三个 getter 的**任何播放器首次使用前**调用 `session.configure(const AudioSessionConfiguration.music())`。选 `music()` 的理由：iOS 用 `AVAudioSessionCategory.playback`，BGM 应在静音模式下仍可听见 | ✅ 已修复并**玄参 2026-10-07 真机复测通过**（第 6 轮反馈原文「直接进花园，直接响了，不用等了」） |
| **F87** | 花园音频 | **并发补播自我打断**：修复 F86 后真机仍偶发不响；护栏测试 `qa_independent_round2_shell_d_test.dart`「D 关键：设置迟到补播」报 `PlatformException(abort, Loading interrupted, null, null)` | **两个 `_playGardenAmbient()` 并发操作同一个 `_ambientPlayer`**。日志实证（`/tmp/shelld.log`）：`…380460` `applySettings` 第 1 次调用判定 `lateRepay=true` → 起播#1；`…380464` **仅隔 4ms** 第 2 次调用（外壳 `child_shell_page` initState 首调 + provider 变更监听）**又**判定 `lateRepay=true` → 起播#2；`…380713` 起播#2 的 `player.stop()`（`_setPlatformActive(false)`）**打断**起播#1 正在进行的 `setAsset`（`_setPlatformActive(true)`）→ just_audio 检测到 activation 序列被覆盖，`checkInterruption` 抛 `PlatformException(abort, Loading interrupted)`（`just_audio-0.9.46/lib/just_audio.dart:1331`）→ 首播彻底失败，只能等 30s 定时器。两次都判 `lateRepay=true` 的原因：第一次是 `unawaited`，`_ambientRunning` 尚未来得及翻 true。为什么此前没暴露：既有闸门 `_ambientPlaying` **只在拿到播放器之后才置位**（`_playGardenAmbient` 内），两个并发流程都能穿过 `playGardenAmbientAndWait` 的 `skip: _ambientPlaying` 检查；F86 新增的 `await _ensureAudioSessionConfigured()` 多插入一个异步间隙，把这个既有竞态从偶发变成必现 | 新增**重入闸门** `_ambientStarting`，在 `_playGardenAmbient()` 入口**同步**置位（不能等第一个 await 之后）、`finally` 复位、`dispose()` 也复位（防残留态卡死后续起播）；真正实现拆到新函数 `_playGardenAmbientGuarded()`。该竞态路径有 **5 个调用点**（30s 定时器 / 自愈监听 `_attachAmbientHeal` / `applySettings` 迟到补播 / `resumeFromBackground` 恢复 / 花园页首次进入），全部一并被守住 | ✅ 已修复（护栏 `test/m3/ambient_d1d2_guard_test.dart` D1-v3-①/② 各 1 条，**RED→GREEN 实证**：拆掉闸门 → `Expected: <1> Actual: <3>`；恢复 → 8/8 绿）+ 玄参真机复测通过 |
| **F88** | 花园音频 | **音频素材响度全线失控（背景音被音效完全盖死）**：① 种植音效一响背景音「消失」、等 30s 才回来；② 玄参指出除草/除虫**不**打断背景音，与种植/铲除听感不同（这个观察是对的）；③ 玄参最终要求「背景音有点大，需要调小」 | **素材层响度失控，不是播放逻辑**。ffmpeg EBU R128 实测（归一化前）跨度达 **19 dB**：`shovel.mp3`（铲除）**−14.8 LUFS**/peak −0.3；`cultivate.mp3`（种植）−16.8/−6.4；`care_pest.mp3`（除虫）−18.8/−10.2；`care_weed.mp3`（除草）−21.7/−3.3；`focus_loop.mp3`（专注 BGM）−25.5/−14.7；`care_fertilize.mp3` −31.0；`care_water.mp3` −32.1；`grow_*.mp3` ×3 约 −35~−40；**`background.mp3`（花园氛围音）仅 −38.6 LUFS / peak −24.1** → **背景音比铲除音效低 23.8 dB（峰值差 peak −0.3 −(−24.1)；综合响度差 LUFS −14.8 −(−38.6) 恰为同值 23.8）** → SFX 一响就把背景音完全盖死 → 听成「打断」；除草/除虫比铲除轻 3.6~7 dB → 盖不住那么彻底 → 听成「不打断」。**这精确解释了两次听感差异。** ⚠️ 另据第五轮真机日志：D3「种植/铲除真的 pause/stop 了背景音」这个旧结论**被推翻** —— 5 次 duck 全部正常（duck → `setVolume(0.8)` → 约 4s 后 restore → `setVolume(1.0)`），**无任何一次 pause/stop**。玄参听到的「打断」实际发生在首进那 30 秒哑起播窗口内（背景音本来就是哑的） | ① **纯增益归一化**（`volume=XdB`，非动态压缩，保持波形与时长）——BGM → −26 LUFS、SFX → −20 LUFS（6 dB 层级），受峰值上限 ≤ −1.0 dBFS 约束（4 个文件封顶未达目标）；② 玄参反馈「背景音有点大」后再降 **4.7 dB** → `background.mp3` 最终 **−31.3 LUFS**（mean −37.5 / peak −16.7），比 SFX 低 11 dB（垫底但可闻），时长 10.083s **分毫未变**；③ **duck 深度 0.35 → 0.80**（−9.1 dB → −1.9 dB）：氛围音已提到 −26 LUFS，若仍按 0.35 压等于把它**重新按回听不见** → 仍被听成打断。玄参原话「背景音正常播放，**或者**降低音量」→ 保留 duck 但改为轻微让位。QA 音频测试 14 处硬编码 `0.35` 改为引用常量（单点收口）。全部 20 个 mp3 重编码为 44.1kHz / 立体声 / 192kbps，**时长全部未变**（`sfx ≥3s` 红线安全）；原件全量备份 `/tmp/audio_backup_20261007/` | ✅ 已修复（玄参 2026-10-07 第 6 轮真机复测原文：「音量就先这样吧」「种植和铲除的音量和音效也正常了，修复好了」） |
