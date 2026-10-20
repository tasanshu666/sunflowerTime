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

> **2026-10-08 批次**（玄参小米 14 三轮真机反馈，当日 1–4 项与改名后口径已复测通过；本批 F89–F94 除注明外均待玄参复测确认）：

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F89** | 护眼·帧播放 | 护眼卡 5 组素材 7 槽位播放中，**每次槽位切换瞬间闪黑屏**（玄参 2026-10-08 反馈；原计划玄参自行合成单帧+单音频，后改为代码侧先试） | 护眼页给播放器挂 `key: ValueKey(_slot)` → 槽位切换 = 播放器**整体销毁重建**，新组首帧异步解码期间画面空白；且下一组帧从未预热，切换瞬间必现解码 | 三层保险（代码注释标记 **B34**）：① `FrameSequencePlayer` 支持 `didUpdateWidget` 换帧组重启（不再销毁重建，旧组末帧经 `gaplessPlayback` 挂到新组首帧就绪）；② 新增 `playToken` 播放令牌——段④⑤⑥是同一组 look 帧同时长，纯内容判重会漏掉重开导致卡死（widget 测试当场抓出），令牌变化即强制重播；③ 护眼页滚动预热：播第 N 组时预解码第 N+1 组 | ✅ 已修复，**玄参 2026-10-08 真机复测通过**（原话「护眼帧不闪黑屏了，可以」），素材合成免做 |
| **F90** | 专注·音频 | 专注中有收集阳光动画、**无收集音效**（勿扰开着；玄参 2026-10-08 反馈） | **勿扰档位用错**：`setInterruptionFilter(INTERRUPTION_FILTER_NONE)`（完全静音）在 Android 会把**媒体音量一起静音**；收集/结算音效都播在勿扰生效期间 → 有画面没声音 | 档位改 `INTERRUPTION_FILTER_PRIORITY`（仅屏蔽通知/铃声，媒体照常出声），「专注期屏蔽通知」原目标不变；Dart 侧注释同步（`dnd_controller.dart` / `MainActivity.kt`） | ✅ 已修复，**玄参 2026-10-08 真机复测通过**（原话「收集阳光有音效了」） |
| **F91** | 专注·方向判定 | 首次进专注需授权勿扰 → 跳设置授权返回后，**横屏条件下一直弹「结束」提示框**，杀 App 重进才恢复 | 退后台期间方向传感器残留竖屏值 → 回前台恢复监听后，残留值触发横→竖→横循环判定，反复弹框 | `PresenceDetector` 修（代码注释标记 **B33**）：`didChangeAppLifecycleState` 回前台时**忽略后台期间的方向事件**并清挂起状态；加 **2s 再同步宽限**（`kResumeResyncGraceSeconds`）+ 宽限期后主动重探一次物理方向再武装 | ✅ 已修复，**玄参 2026-10-08 真机复测通过**（不再循环弹框） |
| **F92** | 结算·演出 | 专注到时 → 护眼 → **直接进结算页**：看不到向日葵结算动画帧、听不到结算音效 | 两个根因叠加：① 结算动画/音效在护眼卡**背后播完**（被全屏护眼卡覆盖）；② 专注页 `dispose` 里释放音频服务，把刚起播的结算音效杀掉 | ① 到时结束新流程：**3s 过渡（横屏）→ 护眼卡（横屏）→ 护眼结束才转竖屏**进结算，结算演出不再被遮挡；② 移除专注页 dispose 中的 `audioServiceProvider.dispose()`（结算音效不被杀）；③ `SettleArgs` 新增 `eyeCareReward` 直达展示，护眼奖励数字不再依赖时序 | ✅ 已修复，**玄参 2026-10-08 真机复测通过**（原话「护眼结束后，有结算动画和结算音效」） |
| **F93** | 花园经济 | 第一株向日葵（pot 0）**一次蹦出 33 个产物图标**（早上 8 点自然晨露刷新触发，非调试直接产生） | **拉真机加密数据库实锤**：该株调试催熟 33 次开花（`bloom_count=33`），C30 晨露登记对「同株 + 同 8 点槽位」**无去重** → 每次催熟把未来 3 个槽位各登记一遍，10/8、10/9、10/10 各 33 条共 **99 条未领取**；今早 8 点 33 条同时到期 → 头顶堆 33 个图标。对照组 pot 1（自然开 1 次花）完全正常 | 双修：① **登记去重护栏**——`_enqueueBloomRewards` 对同株 + 同槽位 + 同档位的未领取行只登记一次（催熟多少次都不翻倍）；② **v16→v17 数据迁移**——首次启动自动清理存量重复（每槽位保留 1 条、金额不合并；已领取历史账与阳光账本一律不动），真机 99 条自动收敛回 3 条；配迁移测试 + 去重回归测试，既有 14 个迁移测试版本断言 16→17 | ✅ 已修复（代码侧 105 例迁移链测试全绿）；**✅ 玄参 2026-10-09 复测通过**（原话「花园也的bug现在看是暂时修复了」） |
| **F94** | 护眼·出口口径 | **没走完护眼流程手点「完成休息」直接发 +3 奖励**（玄参 2026-10-08 第三轮反馈：需二次确认、确认跳过无奖励、卡上明示 + 爱护眼睛提示） | 主按钮 `onPressed` 无条件按 completed 处理——未走完也发奖励，孩子可绕过护眼白拿阳光 | 新口径（玄参拍板）：① 主按钮**定名「跳过护眼休息」**（自然走完时系统自动收口，主按钮实际语义 = 提前结束 = 跳过）；② 未走完手点 = **视同跳过**：弹二次确认卡（`kEyeCareEarlyFinishTitle/ConfirmText`，明示无奖励 + 爱护眼睛提示），确认后按 skipped 退场（无奖励、不写账本）；③ 家长禁跳时点击无效弹「不可跳过，请爱护眼睛」；④ 只有末槽播放回调 / 兜底保险丝的自然收口才是 completed 发奖励；新文案常量 4 个单点 `prd_params`，eye_care_page_test 完成休息组重写 2 例 + 家长禁跳组补断言，settle_eye_care_test 3 处写死文案改常量引用 | ✅ 已修复（analyze 基线一致；**896 全绿**）；⚠️ 真机复测待玄参下班后确认 |
| **F95** | 结算·音频 | **短专注（如专注 7 秒手动退出）结算页只有动画帧、没有结算音效**（玄参 2026-10-08 反馈） | 历史口径残留：B32 让 settle 序列帧在有结算数据时**始终**播放（含 net==0 短专注），但 `initState` 的音效播放仍被旧条件 `settlement.net > 0` 门控 → 画面庆祝、声音静音，视听不一致 | 音效条件与动画对齐：`settlement != null` 即播 `focusSettle`（`_soundOn` 静音开关仍由 `playSfx` 内部统一拦截）；同步修正 B32 处注释口径 | ✅ 已修复（analyze 基线 110 一致）；⚠️ 待玄参真机复测 |
| **F96** | 专注·护眼触发 | **20 分钟专注走到「19 分多」向日葵就进入护眼休息**（玄参 2026-10-08 反馈，怀疑跨场计时累计） | **非缺陷（拉真机加密数据库实证）**：① 护眼场内触发＝本场独立计时（引擎每场 initState 新建、`_eyeCareBaselineFocusSeconds` 归零），且触发值（`actualFocusMin`）恒 ≤ 显示值（`elapsed`），「显示 19 分多就触发 20 分钟间隔」在代码层不可能；② 当日 19:13 场墙钟仅 5 分 29 秒、实际专注累计 20.01 分钟 = **中途按了 3 次 debug 快进（+5 分钟/次）**，显示从 ~19:32 爬到 20:00 约 28 秒 → 到时结束 → 3s 过渡 → 护眼，玄参在「19 分多」瞥了一眼、28 秒后护眼出现，感觉像提前；③ 19:30:00 `eye_care_break +3` 挂在 19:28 场（3s+63s 与 87s 墙钟分秒吻合）。**真解释：debug 快进让墙钟 ≪ 专注钟** | 无需改代码；向玄参还原时间线说明（快进跳变 + 场末护眼按 20:00 整点触发） | ✅ 关闭（非缺陷，数据实证） |
| **F97** | 专注·离席暂停 | **娃点「再坐一会」后抱着竖屏手机走开 → 确认卡不再弹、专注计时一直走**（玄参 2026-10-08 反馈；娃离座习惯把手机竖起来） | B31 旧口径「resume 后需先回横屏才能再次触发」的洞：点「再坐一会」→ `_resume()` 只 resume 引擎，`_portraitFired` 仍为 true → 手机一直竖着（无 landscape 事件）永不重武装；专注页常亮（Wakelock）连灭屏离席都不触发 → 引擎一直 running 计时。弹卡时暂停（`_engine.pause()`）/ 结束 / 再坐会恢复三个动作本身 9 月起就已实现 | `PresenceDetector` 新增 `rearmPortrait()`（仅复位 `_portraitFired`，不起定时器）：`_resume()` 时调用。点完「再坐一会」后：放回横放 → 无感；**抱着竖屏手机走开 → 移动产生 portrait 事件 → 1.5s 去抖后重新弹卡 + 暂停**；静止竖持（拿着看）不产生事件 → 不连环弹卡。测试 presence_detector_test 新增 C1（重武装后竖屏重触）/C2（未重武装维持 B31 不重触对照） | ✅ 已修复（analyze 基线 110 一致）；⚠️ 待玄参真机复测 |
| **F98** | 成长·任务奖励 | **成长页任务「去专注」完成后，结算页只有专注奖励和护眼奖励，没有任务奖励**（玄参 2026-10-08 晚反馈） | **拉真机库实证：后端链路完整走通**——19:28 场（session 253a0450）check_in 已创建且 `status=0(verified)`、账本 `task_checkin +6`、余额含此笔；联动项奖励按 2026-09-21 冻结口径 = 最少专注分钟 × 40%（15×0.4=**6**，非家长配置的 12）。**真问题 = 展示层级太弱**：任务奖励只是「拥有阳光」下方一行金色小字（需滚动且易漏看），被当成「没发」 | 「任务奖励」升级为与「护眼奖励」同级的正式数据行：verified → `+6 ☀️`（实发 granted）、rejected → `0 ☀️`；金色说明行（带任务名）保留。新增 settle_task_row_test 3 例（verified / rejected / 无联动项不渲染） | ✅ 已修复；⚠️ 待玄参真机复测（另请裁定：联动项 40% 口径是否改为足额发家长配置值） |
| **F99** | 防沉迷·单次限时 | **花园等娱乐页只有每日 30 分钟总时长，孩子单次可以连玩 30 分钟**（玄参 2026-10-08 晚拍板：加 10 分钟单次限时，玩 10 锁 10，每日总量仍 30） | 原设计只有日累计口径（`AppUsageService.isCapReached` 唯一判定），无单次连续使用约束 | 三层实现：① **纯函数** `AppUsageService.isSingleLimitReached`（唯一判定入口，防判定孪生）；② **控制器** `AppUsageController` 增 `singleSeconds` / `lockedUntilMs`——单次秒数仅在锁定触发时归零（离开 tab / 切后台**不**重置，防切一下 tab 绕过），到点即锁定：停表 + 弹卡 + `lockedUntil` 持久化 SharedPreferences（**杀 App 重启绕不过**）；到期惰性解锁；测试缝 = 构造注入 limit/lock 分钟数；③ **外壳** `child_shell_page`：点娱乐 tab 时锁定中拦截并弹 `AppCapDialog.sessionLock()`（「已经连续玩 10 分钟啦 / 10 分钟后解锁」）；`ref.listen` 状态变化——人**还停在**娱乐 tab 时到点即自动踢回「今日」+ 弹卡（日上限到顶中途命中的旧缺口一并补上）。debug 期沿用既有 bypass 口径。测试 app_usage_single_limit_test 4 例 | ✅ 已修复；⚠️ 待玄参真机复测（测试期记得开/关家长端调试限时开关） |
| **F100** | 专注·结束过渡 | **结束过渡倒计时 3s 太短 + 系统叮声太小声**（玄参 2026-10-08 晚拍板：改 5s 并交付正式音效） | `kFocusEndBufferSeconds=3` 为临时值，提示音用 ToneGenerator 系统音（`SystemTone.playDing`）占位 | ① `kFocusEndBufferSeconds` 3 → **5**；② 新增 `AudioCue.focusEndCountdown`（`assets/audio/sfx/5s_countdown.mp3`，玄参交付，实测 4.99s 过 ≥3s 红线），`_runEndingBuffer` 改走 SFX 通道（受 soundOn 保护、ducking 统一），`SystemTone` 调用与导入移除；音频资产护栏测试补该 cue | ✅ 已修复；⚠️ 待玄参真机复测 |
| **F101** | 专注·任务联动 | **荣耀平板 Release 包：任务行「去专注」完成计划时长后，任务不打勾、阳光获取记录无任务奖励**（玄参 2026-10-08 晚反馈；小米 debug 包同场景正常） | **离席窗口吞专注进度的口径缺陷**：引擎到时判定用墙钟（`_sessionElapsed`，含离席窗口），而 `actualFocusMin` 只累计 running 秒数；任务行跳转 `planned = task.minFocusMin`（15 分钟任务 = 计划 15 分钟），孩子中途任何一次短离席（灭屏/离开 < 300s 不打断）→ 到时结束时 `actualFocusMin < minFocusMin` → 联动任务静默 rejected（不打卡、不入账、不打勾）。小米 debug 包因快进按钮注水时长（+5min/次）掩盖；release 包自然使用必现 | **到时判定切「专注时长」口径**：`_advance` 到时条件改 `_focusSeconds >= _planned`（坐够 N 分钟才到时，离席时间顺延）；`remaining` / 正计时显示 / 额度轻提示同步切 `focusElapsed`（离席时停走，孩子直观看到「离席不算、回来坐满」）。离席产出停止（§4.1.5）、离席 300s 打断、手动提前结束 < 门槛 rejected 等既有口径不变。新增 focus_engine_f101_focus_time_test 4 例 | ✅ 已修复（analyze 110 一致）；⚠️ 待玄参真机/平板复测 |

> **2026-10-09 批次**（C44~C47 孩子端三 tab 视觉迭代 + F104 / F105 两项修复，玄参 iOS 模拟器逐轮验收；F93 当日复测通过已回写）：

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F93（补）** | 花园 UI | F93 数据去重后花园图标**仍可能挤爆**：晨露 1 条/天 + 开花瞬间奖励 = 单株 5~6 条 × 1~3 列 ≈ 18 个图标同屏排不下（玄参 2026-10-09 截图） | F93 只治了「历史重复脏行」这层数据根因；**合法场景**（多条独立奖励同时到期）展示层没有任何聚合 | 双层：① 展示聚合 `aggregateRewardIcons()`——按列合并（阳光 fold 求和「+N」/ 碎片「×N」/ 种子按物种去重 / 哨兵行合并礼包），点击=收下覆盖全部条目、批量结算单条失败跳过；② `BloomRewardIconsBar.onCollect` 签名升级为批量 `(List<PendingBloomReward>, spec)`；qa_b3 / garden_reward_icons_ui / p0_ui 测试同步 | ✅ 已修复；**✅ 玄参 2026-10-09 复测通过** |
| **F102** | 成长/商店 UI | 卡片左侧图标**显小**，图标下方还叠着一个马卡龙色块；改大占位后「左边距变大 + 挤压中间文字」（玄参 2026-10-09 三轮反馈） | 素材 v1 四周有 **~15% 透明留边**（内容 ~70%），56px 色块内图标实际只 ≈39px；90px 占位放大后留边叠在 14px 卡内边距上 → 视觉左距 ≈27px 且挤压文字 | 双管齐下：① **素材 v2**——玄参重交紧裁圆角卡 PNG（growth 9 + store 7），方形化 512² → WebP q90（母版归档 `assets/_originals/`）；② 代码 64px 满幅直出（无缩放补偿、无色块底），失败仍回退色块+状态图标 | ✅ 已修复；**✅ 玄参 2026-10-09 复测通过** |
| **F103** | 今日·气泡 | 「我的阳光」悬浮气泡**飘着飘着突然跳变**；再反馈「速度太快、幅度太小」（玄参 2026-10-09） | Lissajous 轨迹用了 **2.7×/1.3×/0.7× 非整数倍频**——t=2π 归零瞬间各分量不回原点（实测 dy 跳 ~12pt）；振幅名义 ±13 实际谐波互抵只剩 ±12.7 | 频率全改**整数倍谐波**（dx 1/3/5、dy 2/4/6 次，位置/速度边界差精确为 0，循环永无跳变）；系数数值反推达真实振幅 dx ±20 / dy ±16；周期 12s；Python 数值扫描验证轨迹不越界不碰花头 | ✅ 已修复；**✅ 玄参 2026-10-09 复测通过**（原话「可以了，就这样吧」） |
| **F104** | 花园经济 | 修复 F93 后花园**一次多给 165 阳光**（玄参 2026-10-09 反馈「上次修复后向日葵的阳光一下子给了 165 个，太不合理了」） | **直读模拟器库实锤**：向日葵 23 条遗留「旧口径 48h 第二段」未领取行（`due = 开花 + 48h`、时间非整点）合计 165 阳光 + 月光兰 18；因 F78 的「同轮」判定（`dueAt >= bloomedAt`）被误判为本轮可收集 → 头顶聚合 +165 | **v18→v19 数据迁移**：删除「盛开植物的未领取 normal/premium 行且 due 非本地 08:00:00 整」；growing 植物 / claimed / instant 一律不动（兼容旧库迁移测试的 growing 种子）。真库验证：165 / 18 全清、历史账分毫未动。防复发：新口径单株同屏 ≤ ~24 阳光 | ✅ 已修复（+6 例迁移测试）；**✅ 玄参 2026-10-10 复测通过**（C48 验收未再报） |
| **F105** | 商店·余额口径 | **同一余额两个数**：商店页显示 **390**，今日 / 花园 / 我的显示 **389**（玄参 2026-10-09 反馈「你核对下是咋回事」） | **取整方向不一致**。账本 `sum(net) = 389.913261`（专注按分钟计酬，净额天然带小数）；商店页 `(b - pendingTotal).round()` → **390**，其余三处 `.toInt()` → **389** | 新增 `core/utils/sunlight_display.dart` 的 `sunlightDisplayInt()`（**向下取整**、非正数钳 0）作为全端**唯一展示口径**，4 处调用（商店 / 花园胶囊 / 今日气泡 / 我的）统一；新增 `test/m4/sunlight_display_test.dart` 6 例回归（含「与 `.round()` 差异」锚点，改回 round 必红）。口径理由：孩子看到的可用阳光永不虚高；**只影响展示，不参与任何记账 / 比较 / 扣费**（§3.2 账本铁律） | ✅ 已修复（+6 例，全量 942 绿）；**✅ 玄参 2026-10-10 复测通过**（C48 验收未再报） |

> **2026-10-10 批次（C50~C54）**：同日多轮迭代 —— C50 护眼卡布局改版（方案 A：左右双栏）+ 按钮合并（主按钮为唯一出口）；C51 护眼触发与结算展示口径统一（场内 / 场末同口径累计，剩余 < 60s 不触发场末那次）；C52 成长 / 奖励内容分类追加（`habit` / `toys` / `books`）+ 编辑器下拉「图标 + 文字」+ 默认种子集合重写（成长任务 **9** 条 / 奖励 **6** 条）+ v21 迁移补播 9 条默认成长任务；C53 v21→v22 迁移按固定 id 清理换种子残留的重复内置条目；C54 见下表。**本批代码仍未提交，待玄参验收。**

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F106** | 家长端·成长页 UI | 家长天地「成长」页**右下角悬浮加号压住最后一张卡的「删除」按钮**，点不到删除（玄参 2026-10-10 截图反馈） | `Scaffold.floatingActionButton` 固定在右下角，与 `ListView` 末尾卡片必然重叠（列表越长越容易撞上末卡右侧操作区） | 移除 `floatingActionButton`；新增列表顶部工具条 `_headerBar()`（标题「成长任务」+ N 项 + `OutlinedButton.icon`「新增成长项」），版式与「奖励」页的「新增奖励」完全一致 → **任何卡片都不再被遮挡**；独立路由形态（`embedded=false`）改把「新增」放 AppBar 右上角。空态文案同步为「点右上角「新增成长项」创建一个吧」 | ✅ 已修复（analyze 基线 109 不变）；⚠️ 待玄参真机复测 |
| **F107** | 家长端·成长/奖励条目 | 家长天地「成长任务」出现**重复条目**（同一名称两条，其中一条无法删除或删除后仍留）（玄参 2026-10-10 截图反馈） | **换种子集合的历史残留**：C52 重写默认种子后，旧库里「旧种子 id 的行」与「新种子 id 的行」并存；C53（v21→v22）只按**固定 id 白名单**识别内置种子，**`is_custom = 1` 的同名行漏网**（旧种子的 `is_custom` 值不确定），得同名不同 id 的重复条目 | **双层收口**：① **外观收口**——内置集合强制定死为「成长任务 9 条 + 奖励 6 条」，`id` 前缀 `seed_` = 内置种子、UUID = 用户自建；② **v22→v23 迁移**（`schemaVersion` 22→23）三步清理：㈠ 成长任务**同名**重复行 → 先把 `check_ins.task_id` 重定向到内置 id，再删重复行；㈡ 奖励模板**同名**重复行 → 先把 `redemption_requests.template_id` 重定向到内置 id，再删重复行；㈢ 兜底删 `is_custom = 0` 且 id 不在 9 条白名单内的脏行。**只删不补**（家长主动删掉的内置项不复活）；迁移天然幂等（删除后不再匹配、UPDATE 命中 0 行无副作用）。SQL 字面量经 `String q(String s) => "'${s.replaceAll("'", "''")}'"` 转义，仅用编译期常量 | ✅ 已修复（新增 `test/m3/migration_v23_test.dart` **6/6**；19+1 个测试文件版本锚点 22→23 已同步；全量 **976 绿**）；⚠️ 真机复测待玄参确认 |
| **F108** | 家长端·今日页（debug 专用卡） | 调试包渲染「今日」页时报 Flutter 断言 **「ListTile background color or ink splashes may be invisible」**（C54 加测试时暴露；此前测试里该页一直走错误分支、从未渲染到） | `_DebugCapSwitchCard` 把 `SwitchListTile`（内部含 `ListTile`）直接挂在 `creamCardDecoration()`（**带白底的 `DecoratedBox`**）下；`ListTile` 要求**最近的 `Material` 祖先**承载背景与水波纹，Flutter 在满足 `onTap != null \|\| onLongPress != null \|\| 不透明底色` 时断言 | 在该卡内垫一层 `Material(type: MaterialType.transparency)`，让水波纹正确落在卡片内（**视觉零变化**）；仅 debug 可见卡受影响，release 不受影响 | ✅ 已修复（`nav_structure_test` 的假任务仓储改为同时实现 `CheckInAdminRepository`，测试得以渲染真实内容后不再报错）；⚠️ 无需真机验证（debug-only，且为断言级） |

**C54 附带新增功能（非缺陷）：家长端「记录」页**

- 需求（玄参 2026-10-10）：「孩子完成的任务和兑换的内容，需要有一个历史记录，**相同的内容可以统计次数**，方便家长查看。」
- 口径（AskUserQuestion 澄清确认）：**只做家长端**；入口为**新增底部「记录」tab**（家长端底部导航 4 → **5**：今日 / 奖励 / 成长 / 记录 / 设置）。
- 实现：
  - 新增 `lib/presentation/parent/pages/parent_history_page.dart` —— 顶部汇总卡（累计完成成长项 / 累计兑换奖励 / 累计消耗阳光）+ 两块历史（**成长任务完成记录** 按 `taskId` 聚合、**奖励兑换记录** 按 `templateId` 聚合），每行显示「次数徽章 + 首次 ～ 最近时间」（奖励行另附累计消耗阳光），支持下拉刷新与分区空态。
  - 数据源**只取已核销事实**：`TaskCheckInService.verifiedCheckIns()`（新增，走 `CheckInAdminRepository.checkInsByStatus(verified)`，联动项自动结算 + 家长核销通过都落 verified）+ `RewardRepository.verifiedRequests()`；**pending（待确认）与 rejected（已驳回）不计入**。
  - **不新增 DAO、不改表结构、不动既有仓储接口**（分组聚合在页内做，数据量为单孩子单机量级），避免牵动 v23 之后已收敛的 schema 与大批测试。
  - 缺口说明：已被家长删除的成长项 / 奖励，历史行只保留 `taskId` / `templateId`，名称回落占位「（已删除的成长项）/（已删除的奖励）」（与「今日」页同款口径）。
- 测试：新增 `test/m3/parent_history_page_test.dart` **3 例**（相同内容聚合计数 + 汇总；空态；只统计已核销——pending / rejected 不计入）；`test/nav/nav_structure_test.dart` 家长端断言 `4 项` → **`5 项`，顺序 今日/奖励/成长/记录/设置**。

> **2026-10-10 批次（C55）**：修 F107 的**数据丢失回归** —— v23「同名去重」在「同名内置行实际不存在」的设备上把用户条目清空（真机只剩 3 任务 + 4 奖励），v24 迁移补齐内置种子；同时「记录」页升级为**按天 / 按周 / 按月**统计。**本批代码仍未提交，待玄参验收。**

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F109** | 家长端·成长/奖励条目（**数据丢失**） | 更新后家长天地「成长」页**只剩 3 条**、「奖励」页**只剩 4 条**（玄参 2026-10-10 真机反馈） | **两条缺陷叠加**：① **C52 的 9+6 种子在该设备从未落库**（用硬编码口令 `sunfocus-planb-dev-passphrase-2026` **离线解密真机 `sunfocus.sqlite` 实证**：`tasks` 仅 3 行 = 早期 3 任务种子、`reward_templates` 仅 4 行，字段值（阳光 8/8/6、专注 20/15/15；单价 30/100/20/200）与新默认**一字不差、只是缺行**；`check_ins` 4 行只引用仍存在的任务、无断链）；② 玄参为凑齐**手动补了同名条目**（即 F107 的「重复」），而 **F107 的 v23 同名去重假设「同名内置行一定存在」** → 先把用户条目的历史重定向到内置 id、再删用户条目，而内置行根本不存在 → 净剩 3 + 4 | **v23→v24 迁移（`schemaVersion` 23→24）**：对 9 条成长任务 + 6 条奖励逐条 `INSERT OR IGNORE`（**只补不删、不覆盖、不复活**）——id 缺失才补一条默认行，已存在则整行跳过（家长对内置项改过的价 / 名 / 删一律尊重）；`from < 24` 单次触发、天然幂等（二次执行 0 行写入）。真机预期：3 → **9**、4 → **6**。**遗留口径（需玄参知悉）**：家长此前主动删除的内置项会被**一次性补回**（本次为「补种内置目录」语义）；补回之后再删不再复活（v24 不会重跑） | ✅ 已修复（新增 `test/m3/migration_v24_test.dart` **6/6**：真机态 3+4→9+6 / 既有行不被覆盖 / 自建项不动 / 幂等 / v20 端到端 / 版本号；全项目 56 处 `schemaVersion, 23` → **24** 同步；`flutter analyze` 基线 **109** 不变）；⚠️ 待玄参真机复测 |
| **F109（附）** | 家长端·「记录」页统计 | 记录页只有「累计」一种口径，内容一多就不便查看（玄参 2026-10-10 反馈：成长记录与奖励兑换都要**按天 / 按周 / 按月**统计） | 页面仅做全量聚合，**无期间概念** | 记录页升级：顶部 **`日 / 周 / 月` 切换**（周以**周一**为始、月为自然月，均取半开区间 `[start, end)`）+ **`◀ 期间 ▶` 导航**（下一期间起点晚于现在时禁用 ▶，不能翻到未来）；两块历史**同时**按所选期间过滤聚合；汇总卡改「本期」口径（本期完成成长项 / 本期兑换奖励 / 本期消耗阳光）；原始已核销数据**一次拉取、页内重聚合**（切粒度不重复查库）。页面新增可注入 `now`（仅测试用） | ✅ 已修复（`test/m3/parent_history_page_test.dart` 重写为 **4 例**：三粒度切换与期间标题 / 期间导航（◀ 回看、▶ 未来禁用）/ 空态 / 只统计已核销）；⚠️ 待玄参真机复测 |
| **F110** | 花园·干扰物浮标 | 画布加宽后（10-09 批）真机发现**杂草跑到花盆外左上角、且比盆还大**（玄参 2026-10-11 反馈「花盆大小改变之后杂草的位置就变了」） | 根因 = 2026-10-09 画布 1200→1720 加宽后盆在画布内占比 0.667→0.465，而杂草仍是**旧画布比例锚点（left 0.17）+ 定长 60px**——盆变小了、杂草没跟着变 | 尺寸与横向锚点全部改**盆身相对**表达（`kWeedSizeToPotRatio` 0.83 / `kPestSizeToPotRatio` 0.72 / 杂草左缘=盆左缘 / 害虫探出盆右缘 164px 语义不变），常量收口 `prd_params.dart`；纵向 0.47/0.53 沿用（新旧画布同高）；新增回归测试 `garden_interference_anchor_test` 锁「随盆等比 + 盆相对锚点」；此后画布 1720→1440（C56）公式自动跟随 | ✅ 已修复（2026-10-11 真机验收通过） |
| **F111** | 花园·开花植物 | 已开花植物显示「有点口渴，该浇水啦」，但浇水 / 施肥按钮是灰的（提示「仅成长中/枯萎植物可养护」）——玄参 2026-10-12 真机反馈 | ① 心情判定（`_deriveMood`）对 bloomed 照常走「>1 天未浇 → thirsty」；② 养护准入（`careQuota.actionable`）却只认 `growing / wilting` → 两口径打架；③ **更严重**：枯萎状态机（`_applyWiltAndDeath`）对 `growing / bloomed` 一视同仁（≥ `kPlantWiltDays`=3 天不浇水同样枯萎），禁养护 = 「看着它枯却救不了」的玩法死锁 | 盛开态**放行养护**（不加成长进度：进度已 1.0），意义 = 重置枯萎计时 + 保住次日晨露满额；**不延长花期**（玄参：延长=多给奖励，花园是消耗阳光的场景）；未养护 → 次日晨露阳光 × 0.5 向上取整、保底 1（**变少不归零**）；只折阳光不折碎片/种子，开花瞬间奖励不折；账本即事实源不加列；展示与发放同源。常量 `kBloomDewCarePerDayRequired` / `kBloomDewNeglectFactor` / `kBloomDewMinSunlight`；回归 `bloom_care_dew_test`（8 条）；文案与产品文档同步（C58） | ✅ 已修复（2026-10-12，待真机验收） |
| **F112** | 平板（iPad）·**全页面空白** | iPad 上**所有页面主体全部空白**，只见底部导航（且导航浮在屏幕**中间**而非贴底），整屏呈米色 —— 玄参 2026-10-13 iPad Pro 11″ 模拟器实测（截图：仅底部 5 tab 可见） | `AdaptiveNavBarHost`（C61 平板限宽外壳）用 `ColoredBox > Center`，而 `Scaffold` 的 `bottomNavigationBar` 槽位给的是「宽有界、**高也有界**（max = 屏高）」的 loose 约束 —— `Center` **只在高度无界时**才 shrink-wrap，高度有界时它会**撑满 maxHeight = 整屏高** → ① 底栏外壳占满全屏高、`Scaffold.body` 被挤成 **0 高** → 页面全空白；② `Center` 把导航**垂直居中** → 浮在 53% 处；③ `ColoredBox` 用 `surfaceContainer`（米色）铺满全屏。原测试只断言**宽度**、从未断言高度（且注释里写错了前提「槽位高度无界」）→ 漏网 | 给 `Center` 显式 **`heightFactor: 1`** 强制纵向 shrink-wrap（宽度仍撑满槽位）；订正注释与设计文档 §5.16 里「高无界」的错误表述；`tablet_adaptation_test` 补**外壳高度 = 导航高度**断言 + 新增「**底栏不得挤掉 body**」（`body + 底栏 = 屏高`）回归用例（6 → **7 条**） | ✅ 已修复（analyze 0 error / 全量 **1056** 全绿；已装入 iPad Pro 11″(M5)，待玄参目视） |
| **F113** | 花园·铲除返还 | 铲除植物**不返还阳光**（弹窗写「本次铲除不返还阳光」），但番茄 / 草莓（普通档，应返还 **150**）也如此 —— 玄参 2026-10-13 实测 | `PlantGrowthService._maybeRecover`（枯萎靠养护复活）为清空 `wiltedAt` 而**用构造器重建** `Plant`，却**漏列 4 个字段** → `plants.shovel_refund` 被静默重置为 **0**（另 `weedAt` / `pestAt` / `weedPestRollDay` 一并被清）。同处已有前科（DEF-1 曾漏 `bloomCount`）→ 属「构造器重建漏字段」的高复发点。**注**：另有两条**设计性 0**（向日葵免费首株、v16 迁移前的历史行）属既有 C29 口径，非本缺陷 | 重建时补全 4 个字段（`shovelRefund` / `weedAt` / `pestAt` / `weedPestRollDay`），并加醒目警告注释「**新增 Plant 字段必须同步此处**」；回归 `plant_wilt_recover_boundary_test` 新增 **G1/G2**（浇活后字段全保留 + 浇活后铲除仍返还 150 并写 `plant_shovel_refund` 账本行） | ✅ 已修复（待真机复测） |
| **F115** | 专注·结算页 | 手动结束且本段注视 ≥ 10 min 时：**结算庆祝动画不播，只看到一张静态图**（玄参 2026-10-13 真机反馈：设定 15 min，专注到 14 min 把平板竖过来 → 弹「确定结束吗？」→ 点「结束」→ 护眼流程播完 → 进结算页无动画） | 手动结束走 `eyeCarePending: true` 路径：结算页先 build，**护眼卡随后压在其上**（`addPostFrameCallback` 内 push）。而**被覆盖路由的 Ticker 仍在跑** → 结算页 `initState` 即起的三样东西——`_anim.forward()`（2.4s 数字上涨）、`FrameSequencePlayer`（6.087s 庆祝序列帧，`holdLastFrame` 定格末帧）、`focus_settle` 音效——**在护眼卡背后全部播完**；孩子等 60s 护眼结束回来只剩**定格末帧**（静态图）+ 已滚完的数字。⚠️ **同缺陷 2026-10-08 已被记录并修复过**，但当时**只改了「到时结束」路径**（改由专注页横屏先播护眼），本页插卡路径（手动结束 / 离席打断）**漏修** | 结算页庆祝改为**可延后启动**：新增 `_celebrationStarted` 幂等闸门 + `_startCelebration()`（数字上涨动画 + 音效）。`eyeCarePending: false` → `initState` 立即起（**行为与既往逐位一致**）；`eyeCarePending: true` → 由 `_openEyeCareIfPending` 在**护眼卡收口后**调用，**此刻才起**庆祝。build 侧条件由 `settlement != null` 收紧为 `settlement != null && !_eyeCareBlocking`（护眼未收口时回退静态呼吸花）→ 卡收口后本处重建为播放器，**新 State 从第 1 帧起播**。回归 `settle_eye_care_test` 新增 **2 条**（护眼期间不得挂庆祝序列帧 + 反向护栏「无卡时立即挂」） | ✅ 已修复（analyze **105/0/0**；全量 **1069** 全绿；待真机验收） |
| **F114** | 花园·成长演出 | 珊瑚岭兰「成株→开花」时，**开花动画帧播放了两次**（玄参 2026-10-13 实测；事后尝试复现未成功） | 演出**无 in-flight 去重闸门**：`_playGrowthFx` 不检查是否已有演出在飞/在屏；而同一阶段跃迁可能被**多条刷新路径各观测一次**（一次养护动作会触发 ≥2 次 `_reload`）。且 `_suppressReload` 原为**单个 bool** —— 两次清除动画（先除虫、未等淡出完就除草）的计时器重叠时，**前一次的收尾会把闸门提前打开**，放行本应被抑制的 `_reload` → 多余结算。已自证：检测层 `_lastPhases` 快照去重（同步读写）与演出层 `FrameSequencePlayer`（`frames` 内容不变则不重启）**均不会自播两次**，故根因在**上游重复触发** | ① `_playGrowthFx` 加去重闸门 `_growthFxInFlight`（入口**同步**置位、演出 `onComplete` 复位、异常路径也复位），口径「一帧只播一场演出」；② `_suppressReload` 由 `bool` 改**票据制**（`Set<int> _suppressTickets` + `_suppressTicketSeq`，每个清除动作持自己的票据、收尾按**自己的**票据释放），消除「重叠计时器提前开闸」 | ✅ 已修复（防御性收口；因难以确定性复现，待玄参复核） |
| **F116** | 专注·手动结束 → 护眼卡（**F115 同源**） | 专注中**手动结束** → 点确认卡「结束」→ 护眼卡**只有动画、没有声音**（孩子真机反馈，**出现 3 次**） | SFX 全局只有**一个**共享播放器（`_sfxPlayer`），而 `_playSfxPaths` 起播前先 `await player.stop()` —— **既无并发闸门、也无代际校验**。手动结束路径上两路 SFX 相距极近发起：「结算页 `focus_settle`」**先**发起但**卡在首次 `_sfx` 初始化**（配音频会话 / 建播放器 / 清资产缓存，数百 ms 级），「护眼卡 `eyecare`」**后**发起却因 `_audioSessionConfigured` **布尔守卫已置位**而**绕过慢路径、抢先起播**；前者醒来后照旧 `stop()` → **掐断护眼配音**。护眼动画由 `FrameSequencePlayer` 的 Ticker 独立驱动（另一条链路）→ 孩子看到「**有动画、没声音**」。**只在手动结束路径**：到时结束走 `eyeCareFirst`（`focus_page.dart` `_handleOutcome`），护眼卡由**专注页** push、结算页**不插卡** → 两路不同时存在。胜负取决于 A 的首次初始化耗时 vs B 的起步耗时（两者都是首次平台操作）→ **概率性偶发（约一半）**。⚠️ 与 **F115 同源**：F115 把 `focus_settle` 推迟到护眼卡收口后**无意中绕开了本竞态，但根因未除** | 玄参拍板 **A + C**（见口径裁定表 **C66**、软件设计文档 §5.20）：**A · 代际闸门** `_sfxGeneration`（`playSfxPaths` 起手同步 `++`；每个 `await` 间隙比对，过期即让位、**绝不回头 stop 别人**）→ 口径「**后发起者赢**」；**C① · 会话配置** 改「成功置位 + 在途共享 / 失败可重试」；**C② · 资产缓存清理** 同款幂等；**C③ · SFX 起播** 改「`unawaited(play())` + 有限轮询确认起播」（复用 `_pollPlaybackStarted`）。**同批修掉一个既有「假绿」**（本轮实测发现，属改动前既存）：`one_click_care_sfx_choice_test` / `qa_independent_p0_care_sfx_behavior_test` 的第 2+ 用例经单例跨 FakeAsync Zone 复用 `AudioPlayer` → `setAsset` 永等 `ready`（`play` 从未发生），但 `load:` 已**同步**记录 → 断言侥幸通过；修法 = 新增 `AudioService.@visibleForTesting resetForTest()`（同步、不 await 旧 Zone）+ 两文件每用例调用，并把收尾判据由「等到 `load:`」改为「`load:` **且** `play`」+ 新增「真的起播恰好一次」断言（已做先红后绿） | ✅ 已修复（`flutter analyze` **103 info / 0 error / 0 warning**；全量 **1084** 全绿（1081 → +3）；新增护栏 `test/m3/sfx_concurrency_guard_test.dart` **3 条** 并已做「**先红后绿**」实证；无 schemaVersion 变更）；⚠️ 待玄参真机复测 |
| **F117** | 孩子端 5 个 tab（花园 / 今日 / 成长 / 商店 / 我的） | 花园里盛开的「珊瑚岭兰」**没有产生阳光**；随手点开一个花盆 → 弹出卡片 → 退出卡片后**才看到**阳光（玄参 2026-10-14 iPad 模拟器实测） | 孩子端 5 个 tab 由外壳 `IndexedStack` **保活**（`_tabs` 预先构建 → 各页 `initState` 只在**外壳首次构建**时跑一次），刷新只有三类触发：① 首次挂载（**切 tab 不重跑**）② `economyRevisionProvider` 自增（**副作用**）③ 页面内动作（如养护卡片关闭）→ **缺**「切回本 tab」「App 回前台」「停在页面上跨过 08:00 / 跨天」三类**时间性**触发。⚠️ **08:00 不是刷新时刻、只是「晨露行到期」的数据时刻**（行在开花那一刻就预登记好，见 `_enqueueBloomRewards`），而「可收集集合」只在页面 `_reload` 里重算 → **页面不重读，到期了也看不见头顶气泡**。**奖励一直没丢，只是界面不知道要更新**（正好解释玄参观察：点开花盆再关掉触发了「页面内动作」这条） | **方案 A + B（玄参拍板；范围 = 5 个孩子端 tab 一起修）**：新增 `lib/presentation/child/state/child_tab_refresh.dart` —— 纯函数 `shouldRefreshForTimeBoundary(last, now)`（跨天 / 同一天内跨过 08:00 → true；时钟回拨 false）+ mixin `ChildTabAutoRefresh`（`ref.listenManual(childShellTabIndexProvider)` 判可见 → **切回本 tab 即刷**；自带 `WidgetsBindingObserver` → **回前台且可见即刷**；可见期间每 `kChildTabBoundaryCheckSeconds`=60s 兜底检查，**跨边界才真刷**、不跨不碰库；在途去重；不可见即停定时器）。5 页各 `with ChildTabAutoRefresh<X>` + 两个成员（今日/成长 `_reload` 补 `silent` 防闪加载圈；商店页 = `ref.invalidate` 两个 `FutureProvider`）；花园页仅 `embedded` 时按下标，路由直推传 `null`。新增护栏 `test/m3/child_tab_refresh_test.dart` **15 条** + `test/m2/store_page_test.dart` 端到端 **1 条** | ✅ 已修复（`flutter analyze` **103 info / 0 error / 0 warning**；全量 **1102** 全绿（1086 → +16）；已做「**先红后绿**」实证：临时掐死刷新入口 → **7 条精确报红**（含商店页「仍显示旧快照：待核销 60」），`cp` 完整恢复、`diff` 无差异；无 schemaVersion 变更）；⚠️ 待玄参真机复测 |

> **2026-10-15 批次（C78 前置）**：今日页专注等级徽章「Lv.40」显示截断 Bug（**纯显示缺陷**，数值 / 经济 / 称号逻辑零改动）；随后同日落地 C78 称号奖励改版（见口径裁定表 C78）。

| ID | 模块 | 现象 | 根因 | 修复 | 状态 |
|---|---|---|---|---|---|
| **F118** | 今日页·专注等级徽章 | 满级玩家今日页徽章显示 **「Lv.4」而非「Lv.40」**——摘要态胶囊与详情卡大圆徽**两处均截断**（玄参 2026-10-15 真机反馈；C75 上线后首位满级玩家暴露） | `Lv.40` 是**无空格单词**：`Text('Lv.$level')` 在固定直径圆内按 `maxLines:1` 布局时，水平方向**不换行、直接被裁掉超出圆内宽度的部分**——末位「0」被裁 → 视觉上变「Lv.4」。一位数（Lv.1~9）宽内装得下从不触发，两位数才暴露；iPhone 宽度档位与 `textScaler` 放大只是改变触发概率，根因是**缺自适应缩放** | 两处 `Lv.N` 文本各包一层 **`FittedBox(fit: BoxFit.scaleDown)`**（`focus_level_badge.dart` 摘要胶囊 + 详情卡大圆徽；C75 iPad 红线遵守：文字只走 `textScaler`，装饰性素材才乘 `uiScaleOf`，FittedBox 只在**内容超宽时**等比缩小、不放大）；数值 / 经济 / 称号逻辑零改动。新增护栏 `test/m3/level_badge_two_digit_fit_test.dart` **5 例**（真实字体度量：两位数不溢出圆内、一位数不被无故缩小、两档徽章一致性等） | ✅ 已修复（`flutter analyze` 基线 **103 info / 0 error / 0 warning** 保持；相关 **109** 测试全绿；待玄参真机复测） |
| **F119** | 花园·成长演出 | 枯萎的「已盛开成株」浇水救活后**盛开演出帧播了两次**（玄参 2026-10-16 小米真机反馈） | 根 Stack 两处条件浮层（`CareEffectOverlay` / `GrowthFxOverlay`）**均无 Key**：养护动效结束把 `CareEffectOverlay` 从 children 移除 → `GrowthFxOverlay` 落到前一 index → 两个 `Positioned` 同 `runtimeType` + key 均 `null` → `Widget.canUpdate` 误命中 → 原地复用该元素、仅换 child → child 类型 `CareEffectOverlay → GrowthFxOverlay` 不匹配 → 旧 `GrowthFxOverlay` 元素被卸载、**新建 State** → 动画**从第 0 帧重放**。日志实证 `initState` ×2 / `play requested` ×1 ⇒ **remount**（**非**「同一跃迁被发起两次」） | 两处浮层各加**稳定 Key**（`_kCareEffectOverlayKey` / `_kGrowthFxOverlayKey`）；实测**任一把 Key 即断链**（QA 复核 B：**M1** 只删成长 Key / **M1b** 只删养护 Key 均仍绿，**M1c** 两把全删才红）→ 两把都留作**双保险**；注释归因同步修订。回归 `test/m3/garden_care_repro_test.dart` 用例①（`Set` 收集 State 实例数 == 1） | 🚧 代码已改（**未提交**）｜**真机验收状态 = 待玄参复测** |
| **F120** | 花园·音频 | 浇水 / 施肥 / 除草 / 除虫**四种养护动作全部没有音效**（切 tab 回来仍无效）（玄参 2026-10-16 小米真机反馈） | SFX 全局只有**一个**共享播放器 + F116「**后发起者赢**」代际闸门：浇水 / 施肥把枯萎的盛开成株**救活**时会顺带触发 `adultToBloomed` 演出（域层 `wilting → growing → bloomed` 两跳）→ **后发起的成长音效**把**先发起的养护音效**静默作废（日志 `[sfx] abandon gen=1` 实测）。↳ 除草 / 除虫真机无声**未能复现**（无成长跃迁 → 无 cue 竞争）→ 如实登记为**未定论** | 同一动作**不发起成长 cue**、保留该动作本来的养护音效：命中判据 = `recoveryReEntry || _activeEffect?.plant?.id == p.id` → `_playGrowthFx(..., playGrowthSfx: false)`，跳过成长音效；**真正的成长升级照常发声**（种子→幼苗 / 幼苗→成株 / 首次开花 / 自然复开花）。被否决备选「串行两首都播」= 音画错位 ~3s。回归 `test/m3/garden_care_repro_test.dart` 用例②~⑤ + QA `test/m3/garden_growth_sfx_no_care_test.dart`（反向护栏，防误杀自然成长音效） | 🚧 代码已改（**未提交**）｜**真机验收状态 = 待玄参复测** |
| **F121** | 购买页·布局（英雄卡） | `320×568` 真实视口下英雄卡出现 **1 个 18px 横向溢出**（`A RenderFlex overflowed by 18 pixels on the right.`），**首帧（未滚动）即现**（C83 吸底独立验收时发现，玄参 2026-10-17 批次） | `parent_premium_page.dart:309` 英雄卡内「未解锁 / 已解锁」胶囊 `pillLabel` + 「一次买断 · 永久」`_GoldPill` 那一行 `Row`（两枚胶囊均为**不换行**的 `Container + Text`）：320pt 宽时英雄卡 `Expanded` 内可用宽仅 **177pt**、两胶囊需要 **195pt** → **右溢 18px**。窄于此的设备（SE1 级 320pt）必现 | **C84 已修**：`parent_premium_page.dart` 英雄卡两胶囊 `Row` → `Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center)` —— 宽屏仍同行（视觉不变），窄屏自动折行；否决 `Flexible`（压字）与「窄屏只留一枚」（丢信息）。新增回归 `test/qa/premium_a11y_narrow_test.dart`（**4 条**：320×568 / 375×667 / 320×568@1.3× 三视口零 `takeException` + 可滚到说明卡 + ≥44pt 可点范围） | ✅ 已修复（C84，2026-10-17；`flutter analyze` 103 info / 0 / 0 保持，全量 **1447 passed / 0 failed**；变异 M1 `Wrap`→`Row` 三视口双红取证）｜真机验收 = 待玄参复测。**既存缺陷、非 C83 回归**（QA 用 `git show HEAD` 复现，该 `Row` 及父布局 C83 一行未动） |

| **F122** | 专注·护眼转场 | 专注完成后进入护眼模式，护眼那一分钟**整页竖屏**（玄参 2026-10-18 荣耀平板真机反馈）；口径 = **仅结算页竖屏，专注 / 护眼横屏** | 转场链上**两条方向指令竞速**（Android 平台通道「后发覆盖先发」）：① `focus_page` `go('/settle')` 替换路由后，旧页 **dispose 迟到**（等路由退场过渡结束才销毁），其无条件兜底 `_restoreSystemChrome()` 的 portrait 落在**结算页插的护眼卡 initState landscape 之后** → 护眼整整 1 分钟被压回竖屏；② 护眼卡自身横屏指令 `unawaited` 裸奔（无 await、无串行化保障），与任何后到 portrait 均可竞速。模拟器时序凑巧不触发 → 仅真机复现 | ① `focus_page` `_handleOutcome` 复位后置 `_chromeRestoreHandled`，dispose 仅在未复位（直接 pop / 异常 / 进程被杀）时才兜底——**同一转场链只留一条竖屏指令且在插卡之前**；② 护眼卡横屏改 `OrientationBridge.lockLandscape()` 并在 `_finish` 退场前 **await**（200ms 有界等待兜底，沿 Q-E `kChildProfileReadTimeout` 先例；方向锁失败静默不阻塞流程）；③ 守卫 `test/m3/eye_care_orientation_guard_test.dart`：TestDefaultBinaryMessenger 录 `setPreferredOrientations` 实参序列**行为级**断言——②③④ 序列契约（专注横屏 → 复位竖屏 → 结算竖屏 → 护眼横屏，其后不得再有任何指令）+ 护眼卡自身纪律 + **全链路 dispose 用例**（真实 focus→settle→插卡→退场过渡→dispose，迟到 portrait 即红；变异实证：803 行改回无条件 dispose 后新用例**必红** +2 −1） | ✅ 已修复（主理人独立验收：全量 **1549 / 0**、analyze **89 / 0 / 0** 均亲跑；变异两轮亲验：竞速重现 → 守卫红、预算/过滤无涉）；荣耀平板 release 包已出（FORCE_UNLOCK_ALL），待玄参真机复测 |
| **F123** | 兑换·多孩子隔离（**数据串孩子**） | 孩子 A 申请 3 笔兑换 → 家长把当前孩子切到 B → 家长端「今日」tab **待核销列表出现 A 的申请**；核销后 A、B 视图**同时变已核销**（同一行被两个视图重复展示）；兑换记录 / 「我的申请」同理跨孩子可见（玄参平板真机反馈，2026-10-19） | `redemption_requests` 的**全部读路径**（DAO `pendingAndQueued` / `verified` / `rejected` / `queuedOfWeek`）**均无 childId 过滤** —— v26 加列后只写了 childId、没管读；C90-C-1 又只在「记录」段内做了页面层裁剪（C91 已下线），家长今日 tab / 孩子端商店「我的申请」/ 拒绝对称通知全走无过滤读路径 | **双层收口（接口签名零改动）**：① **仓储级单点过滤**——`RewardLocalRepository` 四个读路径一律传 `_childId`（沿 C90 `_childId` 单点可选注入模式，`AccountService` 可选、null → 恒按 `kChildIdDefault`，既有单测零改动）；DAO 四方法加可选 `childId` 参数（null = 不过滤，兼容迁移/老调用点）；② **编排层双保险**——`RedemptionOrchestrationService.verify / reject / forceRelease` 加 `_guardCurrentChild`：目标申请 childId ≠ 当前孩子 → 抛 `StateError`，不写账本 / 不扣池 / 不改状态 / 不回退冷却计数。回归 `test/c91/` 新增 2 文件 **6 用例**（A 申请 → B 待核销空；B 视图核销 A 的 id 被拒且状态账本零改动；核销记录各归各；无 account 仓储兼容语义）+ 记录页全局跟随 2 用例。**变异实证**（/tmp 私有副本）：仓储过滤钉死放行（`childId: _childId` → `null`）→ 隔离用例 **+1 −3 必红**（② 因编排层防护仍拦 = 双保险生效）；共享树零污染 | ✅ 已修复（待玄参真机复测） |

| **F124** | 商店·周池卡 | 高年级「不限」下方的**进度横条持续闪烁**（玄参 2026-10-19 iOS 模拟器实测截图） | C91 预算改即时派生后，不限额分支渲染 `LinearProgressIndicator(value: null)` —— value=null = **不确定态无限循环动画**（AnimationController.repeat 逐帧重绘永不收敛）。无重建风暴 / 无 NaN / 无自激循环 | 不限额时进度条**整块不渲染**（无分母无进度可言）；限额时保持确定性进度条（value=used/budget）。守卫 `test/c91/pool_card_unlimited_static_test.dart` 2 条（不渲染 + 连续 pump 后 hasScheduledFrame==false 行为级断言；限额对照组无排帧）。变异 M2：恢复不确定态 → 必红 ✅ | ✅ 已修复（主理人独立变异亲验红；待玄参复测） |
| **F125** | 孩子端·核销确认卡 | 家长核销孩子 A 的兑换 → 切当前孩子到 B → 返回 B 端，**B 也弹「家长已确认你的兑换」确认卡**；且 B 点「知道啦」会把 A 的通知 id 写进 B 的已读键（**双向泄漏**：A 的通知被吃）（玄参 2026-10-19 iOS 模拟器实测） | `_checkVerifiedNotices` 的 diff 链「repo.verifiedRequests() ✕ childId 快照键」两边的孩子归属**只靠数据源单一保证**：SP 快照键已分键（C90-B）、F123 仓储过滤完好、净数据流下不复现——泄漏条件 = 任何未过滤源（旧版本库 / 未过滤调用点 / 切孩子瞬间旧快照）把 A 的行 diff 进 B 的空快照键 | `child_shell_page.dart` 两类通知检查各加**第二层防线**：拉到的列表按本次检查捕获的 childId 再过滤一次（`mine = verified.where((r) => r.childId == childId)`），待展示列表与快照键强制同属一个孩子。守卫 `test/c91/verify_notice_child_isolation_test.dart` 3 条（未过滤源回归模拟 / 拒绝对称 / 真仓储端到端口径自洽）。变异 M3：拆第二层过滤 → 必红 ✅ | ✅ 已修复（主理人独立变异亲验红；待玄参复测） |

| **F126** | 孩子端·通知（成长任务审批） | 家长端「今日」核销孩子的**成长任务打卡**后，返回孩子端**没有任何确认提示**，只有家长端自己一条黑色 SnackBar；而核销**商店兑换**后孩子端会弹金色确认卡 —— 同一台设备、两种核销，孩子端只对兑换有感知（玄参 2026-10-19 截图反馈：「缺少了一个感知环节」） | 孩子端「进入即检查未读通知」的机制只注册了**两条**：兑换 `verified`（金色卡）与兑换 `rejected`（对称卡）。打卡审批**根本没有孩子端通知链路** —— 家长端 `_PendingCheckInTile._confirm()` 只调 `_snack('已确认发放，+N 阳光')`（**家长自己屏幕**）+ `economyRevisionProvider.state++`，孩子端只看到阳光数字变了，不知道「任务被确认」这件事 | 新增**第三条** `_checkTaskVerifiedNotices()`（排在兑换核销 → 兑换拒绝之后）：① 数据源 `checkInsByStatus(verified)` **必须再按 `resolvedAt != null` 过滤** —— 联动项自动结算同样是 verified 但绝不该弹（否则专注自动打卡也弹卡）；② 只取 `resolvedAt` 最近 **24h** 内、倒序最多 **3 条**（打卡量远大于兑换，不加窗首次打开会一次弹几十条历史）；③ 已读键按孩子分键 `acked_task_checkin_ids_read_$childId`，且**先剔已读再 take(3)**（反之「最新 3 条已读」会永久挡住后面未读）；④ 金额**一律取实发 `sunlightGranted`**、删除「granted 为 0 就退回 gross」的回退 —— capped 时落库是 `granted=0 + gross=12`，回退会让卡片**虚报 +12 阳光**；⑤ **封顶判据与显示取整解耦**：`isCapped(c) => c.sunlightGranted <= 0`（原始 double），显示才用 `sunlightDisplayInt`，否则 `granted=0.4` 会被误判成「额度已满」；⑥ 合计三档：全实发 → `共获得 N 阳光` / 部分封顶 → `共获得 N 阳光（X 项今日额度已满，未发放）` / 全封顶 → `今日成长奖励已达上限，本次没有新增阳光`；⑦ 金色卡抽为**共享组件** `gold_notice_dialog.dart`（既有兑换卡 136 行内联改为调用，46 项颜色/尺寸/文案逐值等价，`nav_structure_test` 钉死字面量不动）；⑧ 顺手修小屏大字号溢出：卡片内容套 `ConstrainedBox(maxHeight: 屏高×0.7) + SingleChildScrollView`（内容不超高时高度逐像素不变，实测 3 组 rect 与改前完全相同） | ✅ 已实现（主理人亲跑 `flutter analyze` **88 issues / 0 error / 0 warning**、全量 **1571 全绿**；QA 两轮复核，8 个变异全部实测变红：去 resolvedAt 过滤 / 窗口放宽 / 先 take 再剔已读 / 条数改 10 / 判据改回取整 / 已读写到弹窗前 / 任务名回退改空 / 去掉高度约束）｜⚠️ **待玄参真机复测**（视觉：深金 w500「今日额度已满」观感 + 最长合计文案在 1.3× 下折行） |

| **F127** | 孩子端·外壳布局（小屏 + 大字号） | `320×568` 逻辑像素 + `textScaler 1.3` 下，孩子端外壳**横向溢出 14px**（`A RenderFlex overflowed by 14 pixels on the right.`）—— **不放任何卡片也复现**（库中 0 条打卡时依然报错）（F126 排查中意外发现） | **已定位**：`lib/presentation/child/pages/child_today_page.dart:640` —— `_StatCard.build` 里「主数值 + 次要单位」的基线 Row。可用宽 198（320 − 页 padding 32 − 卡内 padding 32 − 头像 42 − 间距 14 − 描边 2），子项 `0 分钟`(119.6) + 间距 6 + `· 0 次`(84.5) = 210.1 → 溢出 14。三张卡中只有「今日专注」带非空 unit 且最宽，全树仅此 1 处 | 两个 `Text` 各自套 `Flexible`（默认 flex 1 / loose）+ `maxLines: 1` + `ellipsis`：空间不够时收缩而非撑破父级。**刻意不用** `FittedBox` / `AutoSizeText` / 压 `fontSize`（大字号是无障碍设置，压字＝对抗用户选择）。等分 1:1 而非按比例倾斜，是为了宽屏/常规字号下两者都拿到自然宽度 → **零像素回归** | ✅ 已修复（`test/child/shell_narrow_large_text_test.dart` 3 例：修复前真红 14px / 修复后 5 个 tab overflows=0；全量 1574 全绿；待玄参模拟器复测） |

| **F129** | 平板·响应式缩放 | 同一份代码在 **iPad Pro 11″ 正常、iPad Pro 13″ 字体与内容明显偏小**（玄参 2026-10-19 模拟器实测，商店页/我的页截图对比）；换更大平板会更小，「换一台平板就得重新配一次」 | 平板 UI 放大倍率是**固定常量** `kTabletUiScale = 1.3`，而「是否平板」只二分（`shortestSide ≥ 600`），**与设备实际尺寸无关**。iPad 11″(834pt) 与 13″(1032pt) 拿到**相同绝对字号**，13″ 物理屏更大 → 相对更小 | 新增纯函数 `tabletUiScaleFor(shortestSide)`：以 **834（iPad 11″）为锚点**线性外推 `1.3 × s/834`，`max(1.3, …)` **只放不缩**（mini 744 不会反变小）、`min(…, 1.6)` 封顶；`uiScaleOf` 与 `tabletTextScaler` 都改走该函数（文字与素材**同源同一值**，防双重缩放）。`app.dart` 注入方式不变 | ✅ 已修复（真值表实测 390→1.0 / 600→1.3 / 744→1.3 / **834→1.3 零回归** / 1024→1.596 / **1032→1.6** / 1200→1.6；iPad 13 视口 `1032×1376` + `textScaler 1.6` 下孩子端 5 tab + 家长端 5 tab + 结算页**逐页 overflows=0**，未压字号/未用 FittedBox；全量 **1589 全绿**；待玄参实机确认 1.6 观感是否过冲） |

| **F130** | 平板·卡片（iPad 13 / 1.6×） | F129 放大后暴露：① 家长端「奖励」页价格胶囊里**阳光图标明显偏小**；② 孩子端「商店」卡片右侧 `RIGHT OVERFLOWED BY 2.5 PIXELS` / `4.5 PIXELS`，且按钮内「20 ☀」**图标偏小**（玄参 2026-10-19 iPad 13 截图实测） | F129 只放大了**文字**（`textScaler`），卡片内的图标/按钮尺寸仍是写死常量：胶囊图标 16pt、商店图标 17pt、**兑换按钮 `SizedBox(64×64)` 死宽** → 文字放大到 22–24pt 后装不下就横向溢出 | 卡片内所有定尺寸元素乘 `uiScaleOf(context)`（圆角 / padding / 横向间距 / 图标块 / 阳光图标）；🔴 兑换按钮 `SizedBox` → **`ConstrainedBox(minWidth/minHeight: 64*s)`**，宽度随内容自然增长（实测 1.6 倍下「200 ☀」内容需 **104.3pt > 旧死宽 64**，四位数价格也容得下）；标题**仅平板**限 `maxLines: 2 + ellipsis`、手机保持 `maxLines: null`（🔴 二轮修正：一轮一刀切 `maxLines: 2` 在手机把长名字截断了）；emoji 回退字号**不乘 s**（文字已走 textScaler，乘了会双重放大）；顺带修同款「家长·成长项」卡 | ✅ 已修复（`test/m3/tablet_card_scale_ipad13_test.dart` **10 例**，三档视口实测：1032→图标 **27.2/25.6**、834→**22.1**、390→**17.0/16.0**，均零溢出；变异回退 `tightFor(64,64)` **必红**（溢出 40px / 5.2px）；全量 **1599 全绿**、analyze **88/0/0**。🔴 附带发现：**手机端三位数「200 ☀」在旧 64 死宽下本已隐性溢出 1.3px**，本次一并消除）。**二轮收口**（QA 三轮独立复核 PASS，7 个变异全红）：① 一轮加的 `maxLines: 2` 在手机**截断长名字**（23 字夹具实测 `exceeded=true / 高 48pt`，修前无 maxLines 可折 3 行 72pt）→ 改 `maxLines: tablet ? 2 : null`，手机恢复修前口径（`git show HEAD` 已验证修前确无 `maxLines`，属**恢复**非新改）；② 两处同款图标补乘倍率：阳光来源记录页 24→`24*s`（**38.4**）、专注报告 hero 卡 18→`18*s`（**28.8**，含 `errorBuilder` 的 size），四档视口（390/834/1032/1366）实测严格 `基准×s`、零异常；③ 家长「任务」页补测（上轮**零覆盖**，变异改回全常量必红）：胶囊 **20.8** / 图标块 **89.6**；④ 补卡片内层几何守卫 `12*s + 1` —— **那 1pt 是 `Border.all` 描边内缩**，经「删描边→19.2 / 描边加粗 2pt→21.2 / padding 回退→13.0」三重证伪确认，非把 bug 写进期望值。**已知取舍**：① 手机恢复自由折行后，超长奖励名会让卡高破 C47 的「≈88pt」（**修前既有行为**，本轮只是恢复，C47 的 88pt 本就是典型值非硬约束）；② `child_task_page.dart` 的 `SizedBox(width: 12/10)` 及整卡 padding/圆角仍未乘 s（1032 实测间距停在 12/10，应 19.2/16；因**整卡间距一致偏紧**故是「密度略高」而非布局错乱，零溢出零异常，本轮不扩大范围，后续票据一次性收口） |
| **F131** | 平板·护眼休息（横屏） | 荣耀平板进护眼模式**已横屏**，但画面**只占上半屏**：左上角一张向日葵方图 + 右侧文案/进度条/「跳过护眼休息」按钮挤在上半部分，下方大片空白；同一功能在手机上「看着是满的」（玄参 2026-10-19 荣耀平板拍照反馈） | `eye_care_page.dart` 横屏边长 `min(360.0, max(160.0, maxHeight*0.85))` —— **360 是绝对值上限且只读高度**：手机横屏 844×390 算 331.5 未触顶（所以满），平板 1280×800 算 680 被截到 360 → 内容块高 384 = **屏高 48%**。第二处：`Scaffold.body` 宽松约束 + 顶对齐，横屏内容块没包 `Center` → 即使图卡变大也贴顶。第三处：`:439-443` 的 `mainAxisAlignment.center` 配 `mainAxisSize.min` 是**无效居中**（Row 的 Expanded 只对主轴 tight、交叉轴 loose → free space = 0），且注释「交叉轴是 tight、Column 占满全高」与 SDK 行为相反 | 边长改**双约束派生** `max(200, min(maxHeight*0.85, maxWidth*0.58))`（去掉 360 硬顶）；横屏内容块外包 `Center` 做真正垂直居中（并删掉无效 `center` + 订正错注释）；竖屏兜底同步改 `max(200, min(maxWidth*0.86, maxHeight*0.45))`（旧写死 340 → 平板竖屏只占屏宽 42%）；圆角按 `28 * (frameSide/360)` 等比派生 | ✅ 已修复（`test/m3/eye_care_landscape_tablet_test.dart` 8 例。实测：1280×800 → 图卡 **680**、占屏高 85%、上下边距 60/60（差 0）；1366×1024 → **792.3**；844×390 → **331.5 零回归**（红线，与改前逐位一致）；800×1280 竖屏 → **576**（派生公式钉死）。变异：恢复 `min(360,…)` **4 例红**、去掉 `Center` **1 例红**、竖屏改回 340 **必红**（QA 曾发现该档无守卫，已补）。⚠️ **已知取舍**：图卡从 360 放大到 680，720×720 素材被上采样 ≈1.89 倍，可能略软（用户明确要求铺满）；解码尺寸不受影响，仍是源图 720×720） |
| **F132** | 孩子端·花园成长演出 | 专注约 25 分钟，专注前最后看到的是**种子**，专注结束回到花园**直接是幼芽**，中间成长过渡序列帧**一次都没播**（玄参 2026-10-19 荣耀平板实测：「到了过渡期的时候，如果孩子没有看到，应该播放一次才对」） | 「上次看到哪个阶段」只有**内存快照** `_GardenPageState._lastPhases`。专注结束 `context.go('/')` 会**销毁整个外壳**（go_router 替换路由栈）→ 旧 State 连同快照消失 → 新外壳 `IndexedStack` 立刻构建 5 个 tab（孩子还在「今日」）→ 花园页 `initState._reload()` 正是补结算那一次 `tickAll`（seed→sprout）→ 快照为空 → 旧代码 `if (prev.isEmpty) return` **把唯一一次升级吞掉**（且先写了快照再 return）。孩子点花园时快照已是 sprout，永远无 diff。放大器：新外壳在「今日」tab 就建好花园页，演出即便触发也播在**隐藏页**（`TickerMode(false)`）上 | ① 「上次看到的阶段」**持久化到 SP**（`last_seen_plant_phases_$childId`，C90 多孩子分键，脏数据/非 JSON 一律返回空表不抛）；② 删掉 `prev.isEmpty` 早退，改逐株判定：**prev 无该 plantId → 不播**（首次安装/新种植物保住「进花园不该满屏动画」）；③ **不可见时不播、只入队且不推进快照**（保持「孩子还没看过」，App 被杀下次仍能补播），可见时才消费；④ 队列存**基线**而非算好的段落，消费时用 `_transitionOf` 现算 → 隐藏期继续跨级也能播「最新那一段」；⑤ 跨级只播**最接近当前状态的最后一段**（避免连等 2~3 段 4s+ 演出）；⑥ 枯萎/死亡不播（与检测口径一致）；⑦ 演出在飞时**保留队列 + 不推进快照**等下次重试（`_playGrowthFx` 改返回 bool 表示是否真起播） | ✅ 已修复（`test/child/garden_growth_backfill_test.dart` **8 例**（含枚举顺序守卫 1 例）。核心用例改前必红已双向验证：把数据源改回内存快照 → 6 例全红、还原 → 全绿。另实测「隐藏期跨级 → 播长大啦！🌿 而非发芽啦」、多孩子隔离、不可见不播/切到花园播一次、重复 reload 不重播。QC 变异：数据源回退必红。⚠️ **已知取舍**：多株同时升级只播第一株；SP 读写异常静默降级为内存快照（等价修复前行为，无日志） |

| **F133** | 音频·花园页（iPad 13） | iPad Pro 13″ 模拟器上花园页**所有声音全哑**——背景音、浇水、施肥、除草、收集阳光产物全都没有；同版本 iPad Pro 11″ 与 iPhone 17 **完全正常**，杀 App 重开短暂恢复（玄参 2026-10-19 反馈）。日志里 `[sfx] loaded` 全部成功，说明音效素材加载没问题 | 🔴 just_audio 的 `setAsset` 返回的 Future **只在拿到 `ready` 时完成**；「加载途中被 `stop()` 打断」时平台侧的等待被**丢弃**——既不完成也不抛错，`await` **永不返回**。而 `_playGardenAmbientGuarded` 把 `setAsset` 裸 await 在 `try` 内 → 协程永久挂起 → `finally` 永不执行 → 重入闸门 `_ambientStarting` **永久 true**（`stopGardenAmbient` 只清 `_ambientPlaying`、**不清闸门**）→ 此后每次补播都被自己的闸门挡掉，只能杀 App。触发窗口 = 加载中（平板 0.5~1s）退出花园/切 tab。放大器：卡在 `loading` 的播放器一直占着**共享音频会话** → SFX 也一并被堵（= 「所有操作都没声音」）。真机日志铁证：`19:06:58.333 attempt #1: stop→setAsset→seek…` → `19:06:58.344 processingState=loading`（此后 90 分钟再未离开 loading）→ `19:06:59.320 reason=leave`（加载未完即退出）→ `19:07:00` 起每 30s 一条 `skip: _ambientStarting` | ① `setAsset` 改走 `loadAssetBounded` **有界加载**（`kAmbientSetAssetTimeoutMs=5000`）：超时即当本次失败，并**丢弃该播放器**（解引用 + 取消状态订阅 + fire-and-forget 释放），下一轮 `await _ambient` 重建——卡住的实例不再占着音频会话；② 起播闸门加**僵尸兜底**（`_ambientStartingSince` + `kAmbientStartGateStuckMs=20000`）：持有越界即强制复位并**递增代际**作废僵死在途流程（绝不与新流程抢播放器），把「只能杀 App」降级为「等一轮」；③ `start()` 每次尝试**重新取**播放器、`onAbort` 取**当前**实例（原实现闭包捕获首个实例，重建后会去 stop 一个已释放的播放器）；④ SFX 侧同款有界加载（超时试下一候选）——同一缺陷、同一个共享播放器；⑤ 常量余量守卫：单次起播最坏耗时 3×5s+2×400ms=**15.8s** < 僵尸门 20s，调参越界测试即红 | ✅ 已修复（`test/m3/audio_ambient_zombie_gate_test.dart` **6 例**：永不完成的加载→有界返回 false / 正常加载→true / 抛错原样上抛 / 僵尸门越界→强制复位且代际+1 且不清「应播」意图 / 未越界→仍 skip 且代际不变 / 常量余量守卫。🔴 变异 **6 个全红**：去掉 `.timeout`（挂死 30s 判红）、阈值抬到 365 天、无条件复位、复位不递增代际、超时当成功、超时调到 20s。全量 **1621 全绿**、analyze 零新增。⚠️ **已知取舍**：若平台**持续**卡死，每次起播最坏耗 15.8s 才放弃（期间 `_ambientPlaying` 加载窗口开着，后续补播被挡）；根治靠系统侧恢复，本轮只保证「不再永久哑」。⚠️ **第二轮实测（2026-10-19 21:25，玄参「杀 App 重进、等 1 分钟仍无声」）把两件事彻底分开了**：该次日志显示氛围音**每次都在 300~600ms 内正常起播**（`ready` → `playing=true` → `poll→started=true`，**全程无 `skip: _ambientStarting`**），即 App 侧音频管线健康；同一瞬间平台上打出 **3 轮 `Failed to allocate AVSystemController`**（起播时刻 21:25:05.256 → 报错 21:25:05.371，逐次对齐）。30 分钟计数：**iPad 13 = 82 行 / iPad 11 = 1 行 / iPhone 17 = 1 行** → **该模拟器实例的 CoreMedia 音量路由已楔死**（每次起播都在重试分配音量控制单例，全部失败 → 无可用的输出路由）。处理：`simctl shutdown` + `boot` 重启该实例后复测（重启整机模拟器而非只杀 App —— 玄参已试过杀 App，无效）。🔴 **验收判据 = 日志**（`zombie gate` / `丢弃卡死的氛围音播放器` / `poll→started`），**不是「有没有声音」**；模拟器听不到声时先数 `AVSystemController` 报错行数，不要回头怀疑代码） |

| **F134** | 孩子端·花园·种植确认卡（体验优化） | 种植二次确认卡直接用了 `AlertDialog` 默认样式（白底 Material 卡 + 两行纯文字 + 右下角系统按钮），与 App 通篇「奶油底 + 阳光金 + 圆角卡」脱节，且看不出「种下后还剩多少」（玄参 2026-10-19 截图反馈：「可以帮我优化的漂亮一些吗？」） | 不是 bug，是**样式欠账**：M3 阶段为了「防误操作」临时用默认弹窗，后续没跟 App 视觉体系对齐；两张相邻卡片（金色确认卡 vs 种植确认卡）风格不一致 | 抽出 `lib/presentation/child/widgets/plant_confirm_dialog.dart`：复用 [GoldNoticeStyle] **同一套配色常量**（米色卡底 / 阳光金 / 深金文字 / 投影，不新造色值）；结构 = 物种预览图（`SpeciesPreviewArt`，96 圆角浅金底）→ 标题 → 明细面板（图标 + 名称 + 金额，本次动作用金色加粗、当前值为弱化灰）→ 「种下后剩余 x」高亮小结 → 取消 / 确定种植。四种支付方式（免费 / 种子 / 阳光 / 碎片）各自两行明细；小屏限高 0.7 + 卡内滚动 | ✅ 已完成（`test/m3/plant_confirm_dialog_test.dart` **3 例**：文案红线逐字一致 / 确认→true 取消→false / `320×568 + 1.3×` 零 overflow。⚠️ 标题 `要种下{物种}吗？` 与按钮 `取消`/`确定种植` 是**回归红线**——`plant_species_pricing_test`、`qa_independent_p0_care_sfx_behavior_test` 用 `find.text` 钉死；返回语义不变，取消仍分毫不扣） |

| **F135** | 孩子端·花园·干扰物 | 「种下新的植物的时候，杂草和虫子总会一起跟着出现」（玄参 2026-10-19），且新株当天直接不成长 | `plant()` 建株时**没写** `weed_pest_roll_day` → 留空。种下后页面立刻 `_reload → tickAll`，新株被当成「今天还没掷过」的普通株**当场掷一次**：**55%** 至少中一个（`1 − 0.60×0.70`）、10% 草+虫齐出；中招当天 `_advanceGrowth` 因 `hasPestOrWeed` 直接返回 → 新株当天零成长。本质是「每天一次」被误用在「建株那一刻」 | `plant()` 建株时写入 `weedPestRollDay = DateTime(now.year, now.month, now.day)` → **新株种下当天免疫**，次日才参与掷骰（口径 C100-1）。同时按玄参拍板把害虫概率 25% → **30%**（杂草保持 40%，C100-2；不放大素材、不加待机动画） | ✅ 已修复（`test/m3/garden_weed_pest_test.dart` 新增 1 例：`weedPestRollDay` 已写 / 同日 tick 不长草不长虫 / 次日恢复掷骰；常量护栏 0.25→0.30。变异 **2 个全红**：去掉 `weedPestRollDay`、概率改回 0.25。全量 **1625 全绿**。⚠️ 已知取舍：**老株**当天已掷过骰的不会追溯（不回填历史），仅对**新种下**的生效） |
| **F136** | 孩子端·确认卡（三张统一改版 + 宽度收敛） | ① 「添加新的花盆」二次确认卡（`要给花园腾一个花盆吗？`）与 ② 「铲除植物」二次确认卡（`要铲除「草莓」吗？`）仍是 `AlertDialog` 默认样式，与 F134 已改版的种植卡风格不统一；③ 种植卡改版后**在 iPad 13 上太宽**——实测卡宽 **968pt**（屏宽 1032 的 94%），横向拉满、两侧几乎没有留白（玄参 2026-10-19 iPad 13 截图反馈：「优化的挺好，但是也太宽了……变窄一些」） | 不是 bug，是**视觉体系收口欠账 + 宽度缺约束**：三张卡各写一份样式（种植卡一份、扩容卡/一键卡各一份内联 `AlertDialog`），改版只能一张张改；且改版后只有**高度**兜底（限高 0.7），**没有宽度上限** → `Dialog` 在平板上随屏宽铺开 | 抽出共享卡壳 `lib/presentation/child/widgets/child_confirm_card.dart`：`ChildConfirmCard` + `ChildConfirmStyle` + `ConfirmCardTone{gold, danger}` + `ConfirmCardRow` + `showChildConfirmCard`。六槽位：`hero`（徽标）/ 标题 / `warning`（红字讲后果）/ `rows`（明细）/ `note`（强调色小结讲数字）/ 按钮对。🔴 **宽度收敛单点**：`maxWidth: ChildConfirmStyle.maxWidth(340) × uiScaleOf(context)` → 手机 390 实测 **326**（=390−insetPadding 64，**零回归**）、iPad 13 实测 **544**（收窄 44%）。四张卡（扩容 / 种植 / 铲除 / 一键浇水）全部接卡壳；`plant_confirm_dialog.dart` 改为**薄适配层**（`typedef PlantConfirmRow = ConfirmCardRow`，保留 `_SpeciesHero` 96×s）。铲除卡用 `danger` 红档（`0xFFE5544B` 底 + 白字 + 深红标题 `0xFFB3261E`），仅此一例。🔴 **标题 / 按钮字面量逐字未变**（回归红线：`要给花园腾一个花盆吗？` / `确定，扣除` / `花园容量：N 盆 → N+1 盆` / `要铲除「X」吗？` / `确定铲除` / `确定种植` / `取消`），`note` 与 `warning` 语义分离（note 讲数字、warning 讲后果） | ✅ 已完成（`test/m3/child_confirm_card_test.dart` **6 例**：手机 326 / iPad13 **544 且 <968** / `320×568+1.3×` 零 overflow / 红档按钮底色 + 白字（含金档对照）/ 返回 true-false / 六槽位齐全；`test/m3/plant_confirm_dialog_test.dart` 3 例、`test/m3/garden_layout_v3_test.dart` +1 例扩容卡文案红线、`test/m3/plant_care_sheet_perk_test.dart` 改为 `contains` 分段断言。🔴 **变异 4 个全红**：M1 删 `maxWidth` → 实测 `Actual: 968.0`（反证「改前 = 968」为真）/ M2 `repeat` → `value = 0` / M3 铲除卡 `danger` → `gold`（**工程师用例逃逸，QA 补 1 例接线守后变红**）/ M4 文案改 1 字符 / M4b `→` 改 `->`。全量 **1636 全绿**、analyze **88/0/0**） |
| **F137** | 孩子端·花园·害虫待机动画 | 花园里的害虫（蝗虫）是**完全静止**的一张贴图，与木牌的呼吸动画对比明显「像个贴纸」（玄参 2026-10-19：「你说的给蝗虫做一个动画，你做一下，我看看效果」） | 不是 bug，是**演出缺失**：害虫分支只渲染静态浮标 + 清除按钮，没有待机态动态 | `garden_pot.dart` 新增 `_PestIdleWobble`（StatefulWidget + `SingleTickerProviderStateMixin`）：`AnimationController(1400ms)..repeat(reverse: true)` + `Curves.easeInOut`；浮动总行程 = span × **5%**（span = max(命中区 48, 视觉高)；实测真实浮标外接高 54.46 → 实测最大浮动 **1.362 = 2.5% 单侧**）、摆动 **±4°**；`Transform.translate`（外）+ `Transform.rotate`（内）叠加；`const Key kPestIdleAnimKey` 供测试取矩阵。**只包 `plant.hasPest` 分支，杂草不加**（草保持静态，避免满屏乱动） | ✅ 已完成（`test/m3/garden_pest_idle_animation_test.dart` 3 例：700ms 矩阵变化 + 2800ms 回起点 / `TickerMode(false)` 完全不动 / 只有杂草不挂动画。QA 独立探针复核：15 帧不同姿态 / 最大浮动 1.362 = 54.46×2.5% / 最大摆动 4.000° / 半周期回中 / 极值位置 `tap` 仍命中 `onClearPest`（Transform 反变换有效，孩子点得掉虫子）/ 布局矩形 `Rect(398.0, 409.9, 492.4, 464.4)` 全程逐像素不变（`Transform` 只改绘制与命中变换，不改 layout，与 `garden_interference_anchor_test` 零回归一致）。变异 M2（`repeat` → `value=0`）**双红**。🔴 **新坑位**：花园页现有**第二个无限动画**（原只有木牌呼吸）→ 任何挂载含害虫花盆的用例**禁用 `pumpAndSettle`**（已写入 `garden_pot.dart` 文件头禁令，C101-3） |

| **F138** | 孩子端·外壳 tab / 花园氛围音 | ① 在**花园** tab 进「家长天地」→ 设置完 → 退出家长天地 → 孩子端**直接落到「今日」tab**（不是回花园）；② 人停在今日 tab 不动，**能一直听见花园背景音乐**，且循环不停（玄参 2026-10-19 实测反馈，并追问「是故意这样设计的吗？可以回到花园页面吗？」） | **同一根因的两面**：家长天地入口是 `context.go('/parent')`（`parent_entry_action.dart:34`）—— `go` **替换整条路由栈** → 整个 `ChildShellPage` 连同局部状态 `_index` 被销毁；而全局 `childShellTabIndexProvider`（`shell_tab.dart`）**外壳销毁时无人清理**，残留 2（花园）。① 新外壳 `_index` 初值 0 → 回今日；② `IndexedStack` 会把 5 个子页全部 build，重建出来的花园页读 provider 判自己「可见」（`garden_page.dart:2182`）→ `_syncAmbientTimer()` 起播 + 每 `kGardenAmbientIntervalSeconds` 秒补播 → **今日 tab 上无限循环**。根因是**语义混用**：一个变量同时承担「记忆（上次/当前选中 tab）」与「可见性判据（这一刻有没有人在看）」—— 前者要跨外壳卸载存活（口径 A 要回原 tab），后者必须随外壳上下台变化。⚠️ 外壳销毁那一刻 `dispose` 确实调了 `stopGardenAmbient`，音乐是**新外壳里的花园页重新起播**的 —— 别修错方向 | **拆成两个 provider（语义各司其职）**：① `childShellTabIndexProvider` 改为**记忆**（跨卸载存活，`initState` 用它恢复上次 tab，越界回落今日）；② 新增 `childShellOnStageProvider`（bool，初值 false）= 外壳是否在台前；③ **可见性统一判据 = `onStage && tabIndex == 本页下标`**，三处消费者全改（花园氛围音 / 今日页升级演出 / `ChildTabAutoRefresh._isVisibleNow`，后者同时 `listenManual` 两个 provider 并由 `_recomputeVisibility()` 单点重算）；④ `_publishOnStage(true/false)` **延后一微任务**（Riverpod 的 `debugCanModifyProviders` 在 `initState`/`dispose` 直接改 provider 会抛「while the widget tree was building」），`dispose` 用 `initState` 抓的 notifier 字段（`ref` 已不可用），并加 **`_mountSeq` 挂载序号守卫**（路由转场时旧外壳 dispose 可能晚于新外壳 initState，无条件写下台会把新外壳打回「不在台前」→ 音乐永远不响）；⑤ 结算页两条返回合并 `_backToToday()`：**先写记忆 0 再 `go('/')`**（口径 B：专注结束仍回今日）；⑥ 🔴 **P1 防沉迷漏洞**：恢复 tab 等于绕过 `_onSelectTab` 的三道拦截（单次锁定 / 日总量到顶 / debug 绕过）→ 抽出 `_guardEntertainmentTab(int)` **与点 tab 共用**，恢复路径改为 `_index` 恒从今日起步 → await `_debugCapBypass` + await usage hydrate → 过闸门才切；被拦则**记忆同步归 0**（否则又是「看今日、听花园」的翻版）；⑦ **P2-a 竞态**：异步恢复窗口内孩子自己点了别的 tab → `ref.read(childShellTabIndexProvider) != target` 即**放弃恢复**（记忆是「最后一次主动选择」的真源） | ✅ 已修复（主理人亲跑全量 **1661 全绿**、`flutter analyze` **88 / 0 / 0**）。QA 独立复核：原始 bug 用**真实入口**独立探针复现（真实外壳 → 点花园 → 真销毁 → 重挂今日 → 推进 3×30s **起播 0 次**）；口径 A/B 均成立；P1 闸门与改前 `_onSelectTab` **逐字等价**、全仓排查**无新增绕过口**；变异 **M1~M7 + M6a/b/c/d 共 11 个全红**。🔴 本次最有价值的发现：三条**防御性代码**（`_mountSeq` 守卫 / 记忆越界回落 / await hydrate 探针）删掉后**全量 1646 仍全绿**（零覆盖）→ 已由 QA 探针 Q9/Q7/Q10 收编为正式护栏，现在删任一条必红。**观感实测**：正常设备恢复只有**首帧 1 帧（≈16ms，肉眼不可见，且该帧内不播音乐）**停在今日；刻意拖慢 SP 读到 200ms 才 13 帧（≈208ms）—— 属安全侧等待，**不**改成同步快路径（那会把 P1 漏洞开回来）。⚠️ 已知取舍：`/garden`、`/store` 独立路由是**死路由**（lib 内无调用点，仅深链可达），`embedded:false` → 可见性恒 true → 不过防沉迷闸门，已在代码注释登记，将来加入口必须补闸门 |
| **F139** | 孩子端·商店兑换确认卡 / 截图版调试 UI | ① 商店页点「兑换」弹出的二次确认卡仍是**裸 `AlertDialog`**（白底 Material 默认样式），与花园四张确认卡（种植/扩容/铲除/一键护理）的奶油金卡壳完全不同 —— 同一个 App 里点不同按钮弹出两种截然不同的卡片（玄参 2026-10-20 截图反馈「商店页面兑换确认卡片也需要美化一下」）；② 截商店图时两处调试入口会入镜：**花园页右上角「花期调试」入口**、**专注页右上角护眼调试角标**（`--dart-define=HIDE_DEBUG_UI=true` 的截图开关 `kHideDebugUi` 此前只接了「我的」页 / 家长今日页 / 家长设置页三处，漏了这两处） | ① 商店兑换卡直接 `showDialog` + `AlertDialog`，未接入 F136 的统一卡壳 `ChildConfirmCard`；② 截图开关是「逐个调用点接入」的枚举式设计，**新增页面不会自动继承** —— `kDebugMode` 全仓 16 处命中里，5 处是 UI 入口、其余是日志/诊断/业务闸门，前一批 C95 只接了其中 3 处 | **① 兑换卡接卡壳**（六槽位）：`hero=ConfirmCardBadge(Icons.redeem)` 金徽 / `title='确认兑换？'` / `rows=[兑换物品「小零食」、消耗阳光 −30 ☀、可用阳光 742 ☀(muted)]` / `warning='提交后需家长核销，核销通过才会扣除阳光。'` / `confirmLabel='确认兑换'` / `cancelLabel='再想想'`；`_onRedeem` 新增第 4 参数 `availableSunlight`（直接取 `_StoreLoad.availableSunlight`，与外壳金色数字 `StoreBalancePill` 同源 = `sunlightDisplayInt(余额 − 待核销)`，**不二次格式化**）。原正文首句「确定要用 30 阳光兑换「X」吗？」拆成三行明细（物品/消耗/可用），疑问语气由标题承担，**净增「换完还剩多少」这一信息**。<br>**② 两处调试入口接单点判据** `shouldShowDebugUi(debugMode: kDebugMode, hideForScreenshots: kHideDebugUi)`（花园页 / 专注页）。🔴 **只藏按钮不藏函数**：`focus_page.dart:481` 的 `if (!kDebugMode \|\| _finished) return;`（快进处理函数的领域闸门）**保留不动**；`child_shell_page.dart` 的防沉迷 bypass（366/394）**必须保持裸 `kDebugMode`** —— 截图开关是「UI 显示」语义，绝不能顺手拿来放开限时（已加反向红线用例钉死） | ✅ 已修复（主理人亲跑全量 **1694 全绿**、`flutter analyze` **88 / 0 / 0**）。测试：新增 `store_redeem_confirm_card_test.dart` 8 例（**全部从真实入口走**：挂真实 `StorePage` → 点 `RewardCard` 的「兑换」→ 才量弹窗）+ `screenshot_debug_ui_test.dart` 11 例（源码守卫 + 5 条守卫自检）+ QA 独立探针 `f139_qa_probe_test.dart` 14 例（宽度三档独立推导 / 同源双断言 / `warning`·`note` 槽位 / 320 系列按钮真实命中矩阵 / **改前 AlertDialog 对照** / 既有扩容卡对照）。宽度实测 390→**326** / 320→**256** / 1032@1.6→**544**（期望值由 `min(屏宽−64, 340×uiScaleOf)` 独立推导，未引用被测常量）。变异 **8 个全红**：M1a 删消耗阳光 / M1b 删可用阳光 / M2 「确认兑换」改一字 / M3 花园页改回裸 kDebugMode / M4 专注页改回裸 kDebugMode / M5 可用阳光换成不含待核销的裸余额 / M6a 删 cancelLabel / **M6b warning→note（C101 混用）**。🔴 **两处「改完仍全绿」的危险信号**（与 F136 的 M3 逃逸同型，已全部补守）：<br>· **M6b**：把「提交后需家长核销…」从 `warning` 挪到 `note`（文字一模一样只有槽位变）→ 交付用例 **8/8 全绿**，只有 QA 探针抓住 → 已补 3 条精确断言（`note` 必须 isNull / `warning` 逐字等值 / 三行 `muted` 分布 `[false,false,true]`）。<br>· **M8**：在同一文件**追加**第二个纯裸 `if (kDebugMode)` 入口 → 守卫 **11 例全绿**（根因：`indexOf` 只看第一处 + 反查正则要求必须有 `&&`）→ 已改 `_allIndexOf` 逐处过审 + 反查放宽为 `if \(\s*kDebugMode\b`（不误伤 `!kDebugMode` 形态），并自查出第三个假阴（第二处连 `if` 都没有时 `lastIndexOf` 会跨段拿到上一条合法守卫冒充 → 加片段长度上限 400 + 片段内不得再出现 anchor）。<br>⚠️ 已知取舍：守卫**禁止「谓词抽取」重构**（抽成 `bool get _x => shouldShowDebugUi(...)` 会判红）—— 静态文本守卫无法判定任意谓词等价，宁可误红让人来解释，已在文件头登记。⚠️ **小屏 + 特大字号**（320×568 @1.3）下卡内容超高限高（0.7×屏高）→ 按钮初始在视口外，走卡内滚动（属 F136 卡壳设计内行为，既有扩容卡同样如此；390@1.3 与 320@1.0 均正常，不影响截图）。下批若修：把 action 行移出滚动区（`Column(min, [Flexible(SingleChildScrollView), Padding(actions)])`），代价是改卡壳 ~15 行 + 回归 5 张卡 |

| **F140** | 平板·中央插图（结算页 / 专注页） | iPad Pro 13″ 上**结算页中央向日葵明显偏小**：文字很大、花很小，整页像「小图贴在大屏中央」（玄参 2026-10-20 截图反馈：「这个向日葵你看看是不是有点偏小了，是不是应该跟随平板等比例放大一些呢？」）。截图实测：花可见区 **170.6 × 215.7 pt**，只占屏宽 **16.5%**；同一朵花在手机 390 上占 **43.7%** —— 平板上只剩手机的 **38%** | 与 F129/F130 同源的**定尺寸元素漏乘倍率**，但这两处比卡片更难发现，因为「容器尺寸写死在代码里、看起来像素材本身就这么大」：<br>① `settle_page.dart` 中央向日葵容器 `260×260`、柔光晕 `300×300`、夸奖卡图标 `20`，**全页一次没调 `uiScaleOf`**；而文字走 `textScaler`（iPad 13″ 已放大到 1.6×）→ 文字放大 1.6 倍、花纹丝不动，视觉占比直接失衡；<br>② `focus_page.dart`（打盹屏）的花按可用高度自适应 `clamp(110, 230)`，**上限死写 230** → 平板 Expanded 再高也撑不过 230，与手机**同尺寸**（相对占比同样坍缩）。<br>两处都是「F129 把倍率从固定 1.3 改成随屏短边派生（iPad 13 = 1.6）」之后被放大的欠账 —— 分母变大、分子没变 | ① 结算页：`final double uiS = uiScaleOf(context)`，容器 `260 * uiS`、光晕 `300 * uiS`、图标 `20 * uiScaleOf(context)`；外层包 `FittedBox(fit: scaleDown)` —— **放得下时恒等变换（手机零像素变化）**，放不下时（手机横屏瞬间 / 未来更高倍率）等比收缩而非 `RenderFlex overflow` 报错；② 专注页：`clamp(110.0, 230.0 * uiScaleOf(ctx))` —— **上限随平板放开、下限 110 不乘**（下限是「极小屏地板」，平板永远触不到；手机倍率 1.0 → 行为逐位不变）；③ 两处承载容器各加稳定 `ValueKey`（`settle-sunflower` / `settle-sunflower-fx` / `focus-sunflower-stage`）供测试直接量真实渲染矩形。**手机侧全部 `× 1.0`，逐位等于改前值** | ✅ 已修复（新增 `test/m3/f140_tablet_sunflower_scale_test.dart` **9 例**，全部**从真实页面入口**量 `getRect()`，不自己传尺寸 —— C101-5 接线守）：结算静态花 手机 **260** / iPad 11″ **338** / iPad 13″ **416**（占屏宽 25.2% → **40.3%**）；庆祝帧容器与静态花**同值**（防两条分支只改一条）；夸奖卡图标 手机 **20** → iPad 13″ **32**；专注页打盹花 手机 **230** / iPad 13″ **368**；两页 iPad 13″ `takeException() == null` 零溢出。主理人亲跑全量 **1703 全绿**、`flutter analyze` **88 / 0 / 0**。🔴 **变异 5 个全红**（/tmp 私有副本，做完已删）：M1 静态花去掉倍率（+7 −2）/ M2 庆祝帧去掉倍率（+8 −1）/ M3 夸奖卡图标去掉倍率（+8 −1）/ M4 专注页上限退回死值 230（+8 −1）/ M5 专注页倍率退回死常量 1.3（+8 −1，验证的是「随屏派生」而非死倍率）。⚠️ **已知取舍**：按 C97 口径严格 `× uiScaleOf` 后，平板花占屏宽 40.3% vs 手机 43.7%（≈ 手机的 92%）—— 之所以能接近，是因为光晕 + 容器同乘；若玄参仍觉偏小，可给「结算页中央插图」单开一档专属加权（需新增口径条目，不在本批范围） |

| **F141** | 孩子端·弹窗体系（6 处裸系统弹窗 + 金色卡宽度） | 玄参 2026-10-20 反馈两件事：①「6 处同类裸系统弹窗没统一，其中专注页「确定结束吗？」最值得改，把这 6 个一起修改了」；② 截图「家长已确认你的成长任务」这张金色卡**太宽**——iPad 13 上几乎铺满整屏。**6 处清单**：专注页退出确认「确定结束吗？」/ 兑换被拒通知「🚫 兑换未被通过」/ 完美日「🌻 今日成长项全部完成！」/ 护眼提前结束「还没休息完就结束吗？」/ 等级锁标「请升级到完整版本功能」/ 付费引导「升级解锁」—— 全是 `AlertDialog` 默认白底 Material 卡，与 F134/F136/F139 已收口的奶油金卡壳**两套视觉并存** | **① 收口不彻底**：F136 抽 `child_confirm_card.dart` 时只接了三张「确认卡」，其余 6 处仍裸 `AlertDialog`（同一 App 点不同按钮弹两种卡）；**② 金色卡缺宽度约束**：`gold_notice_dialog.dart` 只有 `insetPadding`（左右 40）、**没有 maxWidth** → 卡片宽度 = 屏宽 − 80，iPad 13（1032）实测 **952**，而 `ChildConfirmStyle` 早在 F136 就收到了 544。**③ 顺带发现一个既有边界缺陷**：专注页退出确认原实现是 `showDialog<void>` + 两按钮各自 `pop()`，`barrierDismissible: false` 只挡「点卡外」**挡不住系统返回键** → 返回键 pop 出 `null` 时两个 onPressed 都不执行，专注永久停在 `_paused = true`（全屏黑遮罩「已暂停」，且 `_requestExit` 首行 `if (_paused) return` → 再也弹不出卡也退不出去）= **只能杀进程** | **① 两个卡壳各司其职**：确认类（①④⑥）走 `ChildConfirmCard`，通知类（②③⑤）走 `GoldNoticeDialog`。**② 给 `GoldNoticeDialog` 扩 5 项能力**：`title`/`footerText` 改可选（⑤ 原文案无标题）、新增 `confirmLabel`（③ 用「太棒啦」）、新增 `NoticeTone{gold,warn}`（②「被拒绝」用红色系，金色奖杯庆祝「被拒」是反语义；色值与 `ChildConfirmStyle.danger/dangerDeep` 同值、注释互指防漂移）、新增 `surfaceKey` 供测试量真实卡宽、`showGoldNoticeDialog` 加 `dialogKey` 让 ⑤ 的 `perkLockedHintKey` 仍可 `find.byKey`（🔴 `super.key` **只挂一层**，下传到内部 `Dialog` 会变 findsNWidgets(2)）。**③ 宽度收敛**：`ConstrainedBox(maxWidth: 340 × uiScaleOf)` 包在 `insetPadding` **外层**（手机 390 → 上限不生效仍 310 **逐像素零回归**；iPad 11 → 442；iPad 13 → **544**，收窄 43%）。**④ `ChildConfirmCard` 新增 `message`**（中性正文，插在 title 与 warning 之间——原文案是陈述句，塞 `warning` 会变红字警告、塞 `note` 违反 C103「warning 讲后果 / note 讲数字」）+ `showChildConfirmCard` 加 `barrierDismissible`（①④ 保留 false 原语义）。**⑤ ① 的 null 死锁顺带修掉**：判定改为「只有 `ok == false` 才算结束」，`true`/`null` 一律 `_resume()`。🔴 **⑥ 按钮权重由主理人拍板反转**：原两枚 `TextButton` 同权重，接卡壳后「结束」一度成为金色实心主按钮 → 孩子手滑即中断专注；改为 `confirmLabel: '再坐一会'`（主）/ `cancelLabel: '结束'`（次），文案逐字不变 | ✅ 已实现（主理人亲跑全量 **1748 全绿**、`flutter analyze` **88 / 0 / 0**）。**六处文案逐字零变更**由 QA 用「渲染层 `Text.data` 集合」逐处比对 `git show HEAD` 的删除行确认（6/6 通过）。新增 `test/m3/f141_confirm_card_unified_test.dart` **20 例** + QA 独立探针 `test/m3/f141_qa_probe_test.dart` **25 例**（转正护栏）。**两轮 QA**：一轮判 `Engineer` 打回——抓出 ② 的明细行回归（`amountText` 是 `Row` 非 flex 子节点 → 拿无界主轴约束，320×568@1.0 溢出 **6.5px** / @1.3 **55px** / 390+24字备注 **213px** / 3条+320@1.3 **328px**）；修法 = 名称 `Expanded(flex:3)` + 金额 `Expanded(flex:2)` 两列皆 flex（结构上不可能再溢出）+ 新增 `GoldNoticeItem.subtitle` 让「说明」不再借位金额槽。二轮判 `NoOne` 通过，并翻出 **NEW-F141-01**：「今日额度已满」6 汉字 = 96px ＞ 金额列 87.2px → 断成「今日额度已」/「满」，改走 `subtitle` 后 390 与 320@1.3 两档实测均 **1 行**。变异：QA 6 个全红（M1 ③退回裸弹窗 / M2 maxWidth 失效 / M3 去掉 barrierDismissible / M4 null 分支退回 / M5 去掉 dialogKey / **M6 ② 去掉 tone → 只有 QA 探针抓到，工程师 13 例全绿 = 覆盖漏洞已补**）。⚠️ **已知取舍（QA 定量登记，均不阻断）**：① 60/40 分割让名称列真机收窄 32~41px（−19%~−24%），长任务名「1分钟跳绳170个以上」由 1 行 → 2 行、单条卡高 +23px（这是「永不再溢出」的代价，玄参未抱怨前不调 `flex`）；② `GoldNoticeStyle.maxWidth/warnBadge/warnDeep` 与 `ChildConfirmStyle` **同值双份**（避免 import 环，注释互指，改一边会漂移）；③ `premium_gate.dart` 跨层 import `child/widgets/`（Dart 无环、analyze 干净，文件头已注理由）；④ 家长端仍有 ~10 处裸 `AlertDialog`（本批口径只覆盖孩子端 + premium_gate）。🔴 **方法论坑（新增）**：`flutter test` 默认字体是**等宽**，会把数字/空格算得比真机宽 ≈33px → **名称列收窄、行数变化在测试里量不出来**，判卡内行数须按中文字宽（汉字恒 1em）换算；要真机口径需在 `flutter_test_config.dart` 用 `FontLoader` 载入比例字体。⚠️ 环境坑：本机 `HTTP_PROXY/HTTPS_PROXY` 会把 `flutter_tester` 的 WebSocket 握手也代理走（报 `Invalid WebSocket upgrade request`、194 例全 load 失败）→ 跑测试**必须摘代理**；且**不要并发跑两个 `flutter test`**（残留 `flutter_tester` 进程会让后续 run 全红） |
