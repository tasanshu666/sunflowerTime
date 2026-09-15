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
