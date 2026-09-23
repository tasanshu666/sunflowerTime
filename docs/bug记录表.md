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
- **已提交**：commit `645c89b` 已推 `origin/m2/economy`（不合 main）。

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
- **已提交**：commit `645c89b` 已推 `origin/m2/economy`（不合 main）。

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
| F07 | M3/家长端导航 | 家长端 5 个 tab 在 **AppBar 顶部** `TabBar`，玄参预期在**屏幕底部** | 原实现用 `AppBar.bottom: TabBar` + `TabBarView` | 改屏幕底部 `NavigationBar`（5 tab：**今日 / 奖励 / 成长 / 夸夸台 / 设置**）+ `IndexedStack`（切 tab 保活，替代 `TabBarView`）。死守 B19/B20 三项不得回退：`PopScope(canPop:false)` 拦返回键 + AppBar 返回箭头 + `parentThemeFor` 深色皮肤 | ✅ 已修复（待真机） |
| F08 | M3/孩子端导航 | 孩子端仍是 M0 占位首页（竖排按钮：开始专注 / 家长天地 / 阳光商店 / 我的花园 / DEBUG 加阳光），商店与花园靠 `push` 进入，**无 tab 栏** | 孩子端底部导航在设计里有、工程里没做 | 新建 `child_shell_page.dart`（底部 `NavigationBar` + `IndexedStack`，5 tab：**今日 / 成长 / 花园 / 商店 / 我的**，AppBar 标题随 tab 变、actions 保留「家长天地」）+ `child_today_page.dart` / `child_task_page.dart` / `child_profile_page.dart`；`garden_page` 与 `store_page` 加 `embedded` 复用（商店余额从 `AppBar.actions` 抽为内联 `_BalanceChip`，避免「看不到余额」复现）；`app_router.dart` 的 `/` 改指 `ChildShellPage`；旧 `child_home_page.dart`（含首页「四档反馈预览 / S1」入口）**整文件删除**，`/s1-demo` 路由与 `S1DemoPage` 保留；B4/B5 通知逻辑（`_checkVerifiedNotices` / `_checkRejectedNotices` / `_checkAllNotices` + `economyRevisionProvider` 监听）整段迁入壳页 | ✅ 已修复（待真机） |
| F09 | M3/术语统一 | 「任务」听起来像要干活（玄参） | 用户可见文案与产品术语不一致 | 用户可见「任务」→「成长」，两端一致：底部 tab、家长端配置页（成长配置 / 新增·编辑成长项 / 成长项名称）、孩子端进度（今日成长 x/y）、分区（每日成长 / 每周成长，`weeklyCount==0` 时整段不渲染）、打卡按钮（我做到了 / 已做到）、空态（今天没有成长项，去玩吧 🌻）、成功提示（太棒了！+X 阳光）、领域层异常文案。**刻意不改**：`Task` 实体 / `TaskCheckInService` / `checkIn()` / 文件名 / 路由 `/parent/tasks`（大范围重命名风险高收益低，已在领域层文件头加「术语约定」注释说明）；**刻意不改**：账本字段 `refType='task_checkin'`（是**数据标识不是文案**，改了会对不上历史账本） | ✅ 已修复（待真机） |

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
| F10 | M3/奖励口径 | 完美日 ×1.5 让同一个成长项的奖励是**不确定值**，家长算不清 | 原设计把「完美日系数」叠加在成长项奖励上 | **玄参拍板移除**：完美日仅留徽章语义，不再叠加系数；`task_checkin_service._rewardFor` 移除系数并删 `app_constants` 残留导入 | ✅ 已修复（待真机） |
| F11 | M3/两端口径 | 「阅读 20 分钟」在**孩子端预览显示 12**、结算页 / 家长卡显示的是别的数字 | `_rewardFor` 在**孩子端预览取基础值**、**结算页与家长卡取含 ×1.5 的 `sunlightGross`**，两条口径并存 | ×1.5 移除后三端统一取 `Task.effectiveSunlightReward`（单点收口，禁止各处复写） | ✅ 已修复（待真机） |
| F12 | M3/联动项定价 | 家长可任意调高联动成长项的奖励 → 存在刷分空间 | 联动项奖励读家长设值 `sunlightReward` | **玄参拍板**：联动项（`requiresFocus == true`）奖励**固定 = 最少专注分钟 × 40%**（`kTaskRewardRatio = 0.4`），**家长不再可调**；公式单点收口在 `Task.rewardCapFor(int)` / `Task.rewardCap` / `Task.effectiveSunlightReward`（编辑器与领域结算共用同一口径）。非联动项保持家长原值（`kTaskRewardDefault=8` / `Min=5` / `Max=15`）。影响面：种子联动项「完成学校作业」「练习数学口算」（均 15 分钟 / 设 12）生效值 **12 → 6**（15×0.4）；「阅读 20 分钟」非联动 → 仍 12。编辑器联动项锁死文案「奖励固定=专注N分钟×40%=X☀」，奖励滑杆 min/max 随分钟动态变化、下调时自动夹回（`min == max` 时 `divisions` 必须传 `null`，否则断言崩）。历史超标数据：编辑器打开即显示夹回后的合法值，但**数据库原值不动** | ✅ 已修复（待真机） |
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
| F14 | M4/家长核销 | **[P0]** 家长连点两次「确认发放」→ 阳光**双倍入账** | `verifyCheckIn` 是「读记录 → 改状态 → 写账本」的**读-改-写非原子**序列，第二次读到的是尚未更新的旧状态 | DAO 层 **CAS**：新增 `TaskDao.resolveCheckInIfStatus`（`update ... where id=? and status=?`，**以受影响行数判成败**；状态用 `int` 传，避免数据层 import 领域枚举）；抢占失败即抛异常、放弃入账。`_appendLedger` 再加一层 `countByRefTypeAndRefIdOnDay('task_checkin', checkInId, day)` 兜底去重 | ✅ 已修复（待真机） |
| F15 | M4/联动校验 | **[P1]** 一次专注会话解锁**多个**联动成长项（一鱼三吃） | 校验只看「当日**存在**一次 `actualFocusMin >= minFocusMin` 的专注」，**不区分归属**、也不检查该专注是否已被别的成长项用掉 | 会话复用守卫：当日已存在 `sessionId == session.id && status == verified` 的打卡 → 抛「这次专注已经结算过成长项啦」 | ✅ 已修复（待真机） |
| F16 | M4/跨天 | **[P1]** 用**昨天的**专注结算今天的成长项 | `settleFocusLinked` 未校验专注会话的日期归属 | 跨天守卫：`dayKey(session.start) != dayKey(now)` → 抛异常 | ✅ 已修复（待真机） |
| F17 | M4/完成度口径 | **[P2]** `rejected` 被当成「已做到」，还能凑完美日 | 取当日打卡时未剔除 `rejected` 行 | 统一优先级函数 `_activeCheckIn`（同一 task 当日多行取「最新一条非 rejected」）+ `_allDailySubmitted` 剔除 rejected | ✅ 已修复（待真机） |
| F18 | M4/重做 | **[P2]** 被驳回后当日卡死，无法重做 | `checkIn` 对当日已有任意打卡行一律拦截 | `checkIn` 只拦 `pending` / `verified`，`rejected` 放行（**新增一行**，保留审计痕迹） | ✅ 已修复（待真机） |
| F19 | M4/统计口径 | **[P2]** `totalCheckInCount` 把 pending / rejected 也算进去 → 孩子端「我的」页累计打卡**虚高** | 计数未按状态过滤 | 改 `countCheckInsByStatus(CheckInStatus.verified.index)` | ✅ 已修复（待真机） |
| F20 | M4/并发 | **[P0·补发现]** 两条不同 pending 记录并发核销 / 孩子连点两次「我做到了」→ 顶穿当日软顶、出双份阳光（家长看到两条同名待确认，核销出双份） | F14 的 CAS 只保证**同一条记录**不被重复核销，管不住**两条不同记录互相插队**：`_softCapGrant` 是「读当日累计 → 算差额 → 写账本」的非原子序列，两条各自读到同一份 `grantedSoFar`、各自补满差额；孩子连点两次则各插一行 pending | 服务层**串行闸门** `_serialized`（`Completer` 链），包住 `checkIn` / `settleFocusLinked` / `verifyCheckIn` / `rejectCheckIn` **四个写入口**；只读的 `board()` / `pendingCheckIns()` **不加闸门**（否则写操作会拖住界面）；被串行化的方法内部**不得**再调用另一个公共写入口，只能调私有实现或仓储（防死锁）。**两道锁分工**：闸门管「并发插队」，CAS 管「状态已被别处改过」，两层都要有、不能互相替代 | ✅ 已修复（待真机） |

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
| F21 | 花园/扩容 | 点「扩容 +1」**直接扣 400 阳光**（低年级档 160），无确认、按钮上没价格 | `garden_page.dart` 点「扩容 +1」直接 `_run(() => expandPot(...))`，按钮文案写死「扩容 +1」（无价格），中间**零确认** → 点了才扣 | 新增 `_expandCost` getter（`_tier == AgeTier.low ? kPlantPotExpandCostLow(160) : kPlantPotExpandCostHigh(400)`，无裸字面量）+ `_confirmAndExpand()`：`AlertDialog`「要给花园腾一个花盆吗？」正文三行 = 当前阳光 X ☀ / 本次扩容将扣除 Y ☀ / 花园容量 N → N+1 盆；「取消」`pop(false)` → `if (ok != true) return;` **一分不扣**，「确定，扣除」`pop(true)` → 才 `expandPot`；余额不足先 SnackBar「阳光不足，还差 Z ☀」并 return。`_CapacityBanner` 重写为**三态互斥**：已达上限 →「已达上限」；阳光不足 → 灰字「阳光不足（还差 Z ☀）」且**不给可点按钮**；可扩容 →「扩容 +1 · Y☀」（原 `onExpand==null` 一律显示「已达上限」会误导，已消除）；`busy` 时禁用 | ✅ 已修复（待真机） |
| F22 | 孩子端/我的页 | 「我的」页 1000 多、花园页 900 多，**两端对不上** | `child_profile_page.dart` 的 `_balance` **只在 `initState` 的 `_reload()` 读一次**，而它是底部导航 `IndexedStack` 的**保活页**，切 tab 不重建 → 花园消费后切回仍显示旧值。**账本本身是准的**：`PlantGrowthService.expandPot` 确实走 `_appendSpend(..., refType:'plant_expand')` 写 `net = -cost` —— **不是少扣了款，只是页面没重读，禁止去领域层「补扣」** | `build()` 内加 `ref.listen(economyRevisionProvider, (_, __) { if (mounted) _reload(silent: true); })`；`_reload` 加 `{bool silent = false}`（沿用花园同款静默刷新，避免切回时闪全屏 loading） | ✅ 已修复（待真机） |

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
| F23 | 植物/成长 | 浇水标 +12%，实际本阶段成长**跳到 21%**（真机） | **根因① `_advanceGrowth` 非幂等**：`stageStartedAt` 只在**跨阶段**时更新 → 每次 `tickAll`（每次页面刷新）都把「stageStartedAt → now」整段**重新累加**到已有进度 | 改为按段推进 + 推进 cursor，重复 tick 不再重算已走过的段 | ✅ 已修复（待真机） |
| F24 | 植物/成长 | 「培养太简单，没有陪伴成长的乐趣」——几小时就开花 | ⭐**根因②（真凶）微秒除数少除 1000 倍**：`inMicroseconds / 3600000.0`，而 1 小时 = 3.6e9 微秒，正确除数应为 **`3600000000.0`** → 成长速度整体**快 1000 倍**。表面只表现为「长得快」，极难定位 | `plant_growth_service.dart:295` 改 `/ 3600000000.0`；`kPlantGrowthHoursPerStageDefault` 24 → **240**（普通，每阶段 10 天）；新增 `kPlantGrowthHoursPerStagePremium` = **480**（精品，每阶段 20 天）；`kPlantAutoGrowthScale` 0.2 → **1.0** | ✅ 已修复（待真机） |
| F25 | 植物/成长 | 施肥从 21% 涨到 70%；且「正好 30 天」实际要 **31 天** | **根因③ 浮点卡阶段**：24/240 累加 10 次 = `0.9999999999999999 < 1.0`，严格 `>= 1.0` 判定把「正好 30 天」推成 31 天 | 新增 `kGrowthEpsilon = 1e-9`，阶段判定改 `progress >= 1.0 - kGrowthEpsilon`；浇水 +12% → **+1%**（`kPlantWaterProgressGain = 0.01`）、施肥 +25% → **+5%**（`kPlantFertilizeProgressGain = 0.05`） | ✅ 已修复（待真机） |
| F26 | 结算页 | 「今日累计」显示 **-173** | `settle_page` 用 `dayNet()`（**含支出**）→ 把浇水 / 施肥 / 种植的支出也算进了「今日累计」 | 改用 `SunlightRepository.earnNetOnDay()`（**只统计 `type == earn` 的 net**）并钳 **≥ 0** | ✅ 已修复（待真机） |

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
| F32 | M2/日上限 | **[P0] PRD §4.5「日上限 79」实际未按「日」封顶**：一天多场专注可远超 79 | `lib/domain/services/sunlight_service.dart` 的 `settle()` 里 `net = computeEffective(rawS)`，而 `rawS` 是**本次会话自己的**原始产出 → 软顶是**按会话逐次套**的，不是按当日累计；`todayCumulativeNet()` 只用于展示，没有参与约束。连带影响：成长项打卡按「当日累计差额」发阳光，若某日专注侧已超发（net > 79），打卡会 `grant == 0`，看起来像「打卡不发阳光」 | **玄参 2026-09-23 拍板修法（见 `口径裁定表_v1.md` C11）**：① 取消分段打薄（`computeSoftCap` + 6 个 `kSoftCap*` 常量全删），专注 **1 分钟 = 1 阳光**、年段日上限 **60/90/120** 硬封顶；② 成长奖励改**独立额度 79**，`_dailyRewardGrant` **只读 `task_checkin` 自身账目**（不再读当日全部 earn）→ 两条额度线解耦，连带影响同步消除；③ **三道拦**：选时长页灰超额度档位 → 开始前截断 → **结算硬截断**（`settle` 新增 `required int dailyFocusCap` + `effectiveFocusSunlight`）。详见下文「G02」 | ✅ 已修复（待真机） |
| F33 | M4/植物养成 | 满养护实测 **17 天**，与理论 **18 天**差 1 天 | 种下当天即可养护 → 少 1 天（理论 16.67 进位）。要严格 18 天，需把每天养护从 8% 降到约 6.7%（浇水 0.5%/次 或施肥 4%），会**破坏已拍板的 +1% / +5% 整数口径** | 玄参 2026-09-22 23:49 **拍板：就 17 天，不细调**（差 1 天无感知，凑 18 天要破坏 +1% / +5% 整数口径，不值得） | ✅ 已拍板（不改） |
| F34 | 孩子端/我的 | `child_profile_page.dart` 底部 `DEBUG 加1000阳光` 按钮仍在（源码自标「提交前删除」） | 玄参真机验收兑换链路要用，故暂留 | **提审前必须清理** | 🔧 待清理 |
| F35 | 全仓/文案 | 注释里的「任务」字样约 **26 处**未统一为「成长」 | 均在 `///` / `//` 注释中（**非用户可见**），其中若干处直接指代 tab 名（如 `child_shell_page.dart:3`），对新维护者有误导性 | 工程师按纪律未改（不在本轮范围）并已逐条列出 | 🔧 待清理 |
| F36 | M3/完美日口径 | 完美日按「**已提交**」判定（联动 = 自动结算；非联动 = 已打卡），而非「家长已核销」 | 玄参拍板：保持**即时情绪反馈**（不等家长核销）；完美日本身不发钱，故无经济风险 | **不改**（已拍板） | ✅ 已确认正确 |
| F37 | M2/指标 | **「核销履约率」指标（含 G2 ≥70% 硬门槛）取消** | 玄参：「简单一点，不要什么核销履约率」。该指标① 口径虚设（分母要排除免确认自动通过，但当前兑换一律走待核销、无样本可排除）；② **从未实现**（全库仅 3 处注释提及，`parent_report_page` 无任何计算代码，`autoApproved` 列无人读取）；③ 还要拆小额/大额分层判读，对单机 MVP 属过度设计 | **已删除**：`redemption_service.dart:29`、`enums.dart:22/113` 三处注释中的「履约率」字样已清理。⚠️ 历史文档（`软件设计文档_M2.md`、`MVP执行规划_v2.md`、`验证计划_SunFocus_G0G2.md`、`架构设计_SunFocus_MVP.md`、`软件设计文档_spikes.md`、`sequence-diagram-M2.mermaid`）中仍留有表述，**是否一并清理待玄参发话** | ✅ 已执行（历史文档待定） |
| F38 | M2/周池 | 周池预算区间 **50–1200 只在 UI 校验**（`pool_indicator.dart` 硬编码），常量里没有周池 min/max；1200 过大 | `prd_params.dart` 的 `kMonthlyPoolMin=100 / kMonthlyPoolMax=1200` 是**月池遗留**（名字带 Monthly），与周池无关；`weekly_pool_service.dart` 领域层**零校验** | **玄参 2026-09-23 拍板改掉**：新增 `kWeeklyPoolBudgetMin=50` / `kWeeklyPoolBudgetMax=500`（`prd_params.dart`），`pool_indicator.dart` 校验与提示文案改为引用常量（不再有裸字面量）。区间 50–1200 → **50–500** | ✅ 已修复（待真机） |
| F39 | 家长端/设置 | 每日专注上限下拉 `options: [60, 75, 90]`（`parent_settings_page.dart`）中的 **75 是孤儿**，且三档默认值不合理（低=中=90、高=60，高年段反而更少） | `prd_params.dart` 旧值只有 `kDailyFocusCapLow=90`（低/中都用它）/ `kDailyFocusCapHigh=60`；75 只存在于 UI 字面量 | **玄参 2026-09-23 拍板改掉**：改为**年龄越大上限越高**的阶梯 —— 低 60 / 中 90 / 高 120。新增 `kDailyFocusCapMid=90`，`kDailyFocusCapLow` 90→60、`kDailyFocusCapHigh` 60→120；`age_tier_params.dart` 三档同步；下拉改为引用三个常量（75 消失，不再有裸字面量）。新增 `test/m2/age_tier_params_test.dart` 7 条断言锁死阶梯与区间 | ✅ 已修复（待真机） |

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
| G02 | M2/日上限 + M4/打卡额度 | **[P0]** 日上限只在「点开始专注」时检查一次，**不检查这一场会不会超** → 孩子可选自定义 180 分钟，一场拿下 180 分钟、到账 79 阳光，**一次超掉低年段 60 上限的 32%**。**另一处 [P1]** 当天专注或家长赠予拿满额度 → 成长打卡奖励归 0（打卡「发不出来」） | ① `settle()` 里 `net = computeSoftCap(rawS)`，`rawS` 是**本次会话自己**的原始产出 → 按会话逐次套，非当日累计；`dailyFocusRemaining()` 早已写好却**全仓零调用**（当初就打算这么接，没接上）。② `_dailyRewardGrant` 读的是**当日全部 `earn`**（`earnGrossOnDay` / `earnNetOnDay`），专注 / 赠予一拿满就把成长奖励额度吃干净。③ 分段软顶「第一段即 60 分钟全额」，与「封顶跟随年段」在数学上**不能共存** —— 高年段 120 分钟永远只能拿 79，是摸不到的天花板 | **取消分段软顶**：删 `computeSoftCap()` 与 6 个常量（`kSoftCapDailyMax` / `kSoftCapSeg1..3` / `kSoftCapSeg2Rate` / `kSoftCapSeg3Rate`），改 **1 分钟 = 1 阳光 + 年段硬封顶**。**两条独立额度线**：专注（跟随年段 60/90/120，按 `refType='focus_session'` 聚合）/ 成长奖励（新增 `kTaskCheckinDailyCap = 79`，按 `refType='task_checkin'` 聚合），互不挤占。**额度三道拦**：选时长页灰超额度档位 + 提示「今天还可以专注 N 分钟」→ 开始前按剩余额度截断 → **结算时硬截断**（新增 `effectiveFocusSunlight`，唯一可靠兜底）。**接口与改名**：`settle` 新增 `required int dailyFocusCap`；`sunlight_service` 新增 `focusEarnedToday` / `focusRemainingToday`（额度口径单点收口）；`cappedBySoftCap → cappedByDailyCap`；`_softCapGrant → _dailyRewardGrant`；`FocusSettlement.capped` 改为直接比较 `net < rawS`（不再靠「是否超第一段」推断） | ✅ 已修复（代码 + **348 条测试全绿**；**未出包、待真机复测**） |

## 花园/日上限轮 · 校验

- **`flutter analyze lib test`** → **0 error**。4 条 warning（`adversarial_task_checkin_test.dart` 与 `adversarial_v1_v10_test.dart` 的 `unused_import`、`unused_element_parameter`）已用 `git stash` 对比 HEAD 确认**改动前既有**，非本轮引入，按最小改动纪律**未清理**。
- **`flutter test --no-pub`** → **348 条全绿**。计数演进：该轮起点 **331** → 花园 +11 = **342** → 日上限 +6 = **348**。
  - 新增 O1–O6（`test/sunlight_settle_p2_test.dart`）：`effectiveFocusSunlight` 边界 / 单场截断 / 多场累计 / 成长奖励不占专注额度 / 任务奖励单独记账 / `rawS` 语义。
  - 新增回归（`test/m4/task_checkin_test.dart`）：「**专注拿满 + 家长赠予 → 成长奖励仍发得出来**」。
- **⚠️ 测试自身的缺陷（本轮一并修，这才是 bug 长期潜伏的真因）**：4 个测试文件里 `netByRefTypeOnDay` 的手写 fake **忽略 `refType` 参数、一律返回当日全部 earn 合计** → 「额度互相挤占」这类缺陷在测试里**永远是绿的**。已全部改为**真按 refType 过滤**（`test/sunlight_settle_p2_test.dart`、`test/m4/task_checkin_test.dart`、`test/m4/adversarial_task_checkin_test.dart`、`test/qa/adversarial_v1_v10_test.dart`）。**纪律：后续新增 fake 必须真过滤 refType。**
- **装包**：花园轮 `adb -s f05bbc46 install -r` → **Success**；`monkey` 启动后进程存活（PID 3924），logcat 无 `FATAL` / `E/flutter`。**日上限轮按玄参指示暂不出包**（先提交推送，装包另择时间）→ 上表 G02 状态为「待真机复测」。
- **文档同步（本轮一并做）**：`口径裁定表_v1.md` 新增 **C11**；同步 `产品开发文档_M2M3M4.md`（§1.3 / §3.5 / §3.6 / §6）、`软件设计文档_M1.md`（§7 / §8）、`软件设计文档_M2.md`（结算时序图）、`软件设计文档_M3M4.md`（§3.2 / §3.3 / §9 / §10）、`软件设计文档_M0.md`、`软件设计文档_spikes.md`、`架构设计_SunFocus_MVP.md`（§3.2 / §4.3 / §5 目录 / §6 任务表）、`验证计划_SunFocus_G0G2.md`（§4.3 DoD / 埋点字段名 `softcap_hit → capped`）。**PRD v2.0 正文按玄参自维护处理，保留为历史版本，不在回写范围。**
- **已知技术债留存**：`child_profile_page.dart` 的 `DEBUG 加1000阳光` 按钮（F34）**提审前必须删**。
