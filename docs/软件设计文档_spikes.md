# SunFocus S1/S2/S3 软件设计文档（spike 阶段）

> 配套真源：`docs/MVP执行规划_v2.md`（唯一施工真源）＞ `docs/口径裁定表_v1.md` ＞ 开发计划 v1.0 ＞ 验证计划 ＞ PRD v2.0。
> 分支：`spike/s1-s2-s3`（全部文件仅落本地，**未 commit / 未 push**，待审核 + 真机测试通过后按指令提交）。
> 范围：仅 `MVP执行规划_v2.md` §4 三个 spike，**未开 M0**。

---

## 0. 工程形态（用户裁定：最小可运行工程）

不开 M0 全骨架，仅保留：
- `pubspec.yaml`：新增依赖 `wakelock_plus: ^1.2.0`、`native_device_orientation: ^2.0.0`；dev 依赖补 `test: ^1.24.0`（为 `dart test` 纯逻辑单测）。
- `analysis_options.yaml`：`include: flutter_lints.yaml`，`avoid_print: false`。
- `lib/main.dart`：极薄 app 壳 `SunFocusApp` + `HomePage`（ListView 路由到 S1 / S3 demo 入口）。
- `lib/core/constants/prd_params.dart`：PRD 参数单点（总纪律 #2），所有可调数值集中此处。

技术栈：Flutter 3.44.7 + Dart 3.12.2（本机已装，`flutter analyze` / `pub get` / `dart test` 可跑；**本机无 JDK / 无 Android SDK**，无法打 APK、无法跑模拟器渲染）。

---

## 1. 文件结构与职责

```
lib/
  core/constants/prd_params.dart          # C3 / C5 / 软顶 / 成长系数 / 夜间边界 全部常量单点
  domain/
    entities/
      enums.dart                         # AgeTier / RewardCategory / RequestStatus
      reward_template.dart               # 奖励模板（含 category、分龄 baseCost）
      monthly_pool.dart                  # 月度池（budget/used/autoReleased）
      redemption_request.dart            # 兑换申请（status / autoApproved / queuePosition）
    services/
      redemption_service.dart            # S2 核心：兑换判定纯函数 decide()
  presentation/child/
    widgets/
      sunflower_canvas.dart              # S1：向日葵 CustomPainter + 呼吸动画 + 四档绘制
      feedback_overlay.dart              # S1：二档/四档气泡文案层
    pages/
      s1_demo_page.dart                  # S1：一屏四档切换 demo（仅预览，非产品页）
      focus_page.dart                    # S3：打盹屏专注页（横屏+计时+常亮+方向锁）
  main.dart                              # 入口 + HomePage 路由
test/
  redemption_service_test.dart           # S2 纯逻辑单测（13 用例，dart test 全过）
```

依赖方向（单向，无环）：
`presentation → domain ← core/constants`；`domain/services` 依赖 `domain/entities` 与 `core/constants`。
UI 层不持有业务判定，S2 判定为纯函数（无 `BuildContext`、无 `I/O`），便于单测。

---

## 2. S1 · 四档反馈 + 向日葵画布

### 2.1 设计
- `FeedbackLevel { lvl1 常态产光, lvl2 随光报信, lvl3 欢迎回来, lvl4 唤醒提醒 }`，外加 `kFeedbackLevelLabel` 演示标签。
- `SunflowerCanvas`（StatefulWidget + `AnimationController` 4s 往复呼吸）：通过 `AnimatedBuilder` 把相位 `t` 传给 `_SunflowerPainter`，驱动 `scale∈[0.96,1.02]`、`opacity∈[0.82,1.0]`、花瓣极慢微旋（`0.04*(t-0.5)`）。
- 绘制分层（按档位条件绘制）：
  - 三档光晕（`lvl3`）：纯视觉 `drawCircle` 外圈光晕，无声。
  - 12 片花瓣（`addOval`）、花心 + 三层种子纹理（`drawCircle`）。
  - 四档睁眼（`lvl4`）：白底黑瞳双眼。
  - 二档送光粒子（`emitParticle`）：向上送出一粒光，alpha 随相位淡出。
- `FeedbackOverlay`：仅 `lvl2`（"我去把它放好。"）与 `lvl4`（"向日葵想你了，回来看看吧～"）出气泡；一档/三档返回 `SizedBox.shrink()`。台词遵循 PRD §4.1.3 三原则（随光只报信不夸奖；夸奖只留结算动画与家长转述；任何一档不得比结算动画更诱人）。
- `S1DemoPage`：一屏 demo，四个按钮切换档位（`lvl2` 自动触发送光），仅 spike 预览用，非产品最终页。

### 2.2 关键决策
- 全部用 `withValues(alpha:)` 替代已弃用的 `withOpacity`；`Path.addEllipse` 在本 Flutter 版本不存在，改用 `addOval(Rect.fromLTWH(...))`。
- 动画低亮慢频，不抢注意力（打盹屏"零突事件"原则）。

### 2.3 验收（需真机）
真机四档切换无卡顿；向日葵绘制帧率达标。（本机无 JDK/模拟器，渲染须由玄参大人在小米 14 Pro 等真机自测。）

---

## 3. S2 · 兑换服务纯逻辑

### 3.1 状态机
`RequestStatus { pending, queued, verified }`
- 满足免确认双条件 → `verified`（`autoApproved = true`）
- 不满足 且 整体池未满 → `pending`（待家长显式核销，分母计入核销履约率）
- 不满足 且 整体池已满 → `queued`（下月 1 日按申请先后自动放行，不拒绝、不失效）

### 3.2 `RedemptionService.decide()` 判定逻辑（C5）
入参：`RewardTemplate template`、`int cost`（已乘分龄系数 K 的消耗侧价，本服务不乘 K）、`AgeTier ageTier`、`MonthlyPool pool`。
```
maxCost   = 高 130 / 低 50                  // ① 单笔候选阈值
ceiling   = 高 100 / 低 40                  // ② 固定天花板（天窗）
capFromPool = (pool.budget × 0.25).floor()  // ② 月池 25%
autoCap   = min(capFromPool, ceiling)       // ② 实际月度自动放行上限（天花板上限 + 池 25% 下限）

cond1 = cost ≤ maxCost
cond2 = (pool.autoReleased + cost ≤ autoCap)            // ②-a 月度自动子限额
     && (pool.used + pool.autoReleased + cost ≤ budget) // ②-b 整体池余量（防超额）
cond3 = !isSelfService                              // ③ 自服务类一律不自动放行

满足 cond1&&cond2&&cond3 → verified
否则 projected = used + autoReleased + cost
      projected ≤ budget → pending
      else                → queued
```

### 3.3 关键口径裁定落地
- **天花板 vs 候选阈值**：单笔候选 `130/50` 不是放行边界；实际边界是 `min(100/40, 池×25%)`。默认池 400/160 → 上限 100/40；池降到 200 → 上限 50（高）/ **40（低，见 §5 待裁定）**。
- **双闸防超额**：`cond2` 同时含"月度自动子限额"与"整体池余量"两道闸。早期漏第二闸会导致家长已核销占满池后仍自动放行——已补 `withinPool` 校验。
- **参数单点**：所有数字来自 `prd_params.dart`，业务代码零裸字面量。

### 3.4 验收（已本地验证）
`dart test` 13/13 通过，覆盖：单笔 131/130/100/101、自服务类、月池 400/200 上限、低年段边界、整体池余量防超额、排队。

---

## 4. S3 · 打盹屏专注页

### 4.1 设计
`FocusPage(plannedMinutes=20)`：
- **常亮保持**：`WakelockPlus.enable()`（P6 风险：国产 ROM 省电可能杀常亮，待真机多机验证）。
- **方向锁 + 沉浸**：`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])` + `setEnabledSystemUIMode(immersiveSticky)`。
- **方向监听**：`NativeDeviceOrientationCommunicator().onOrientationChanged().listen(...)`（注意 2.1.3 中 `onOrientationChanged` 是**方法**，需加 `()`；枚举无 `portraitUpDown`）。物理竖屏（portraitUp/Down）→ 视为中途退出意图 → 暂停 + 确认对话框。
- **计时**：墙钟差 `DateTime.now().difference(_startTime)`，灭屏恢复不漂移（非 tick 计数）。竖屏暂停时把 `_startTime` 回拨 `_elapsed`，避免暂停期被计入。
- **退出**：倒计时到 `_planned` → `_finish()`（取消计时/监听、复位系统 UI、pop 回上一页，结算动画占位待 M1）。
- **dispose**：强制复位常亮/方向/系统 UI，避免泄漏到其他页面。

### 4.2 关键决策
- 只显示"本次已专注 / 计划"与"剩余"，**不显示阳光池数字**（PRD §4.2 低打扰）。
- 顶部"剩余"小字为调试用，产品页将移除。

### 4.3 验收（需真机）
在 3–5 台真机（华为/小米/OPPO/vivo 各尽量一台）连续跑 30–60min，记录常亮是否被系统杀掉；验证灭屏恢复后计时不漂移。（本机无 JDK，须玄参大人真机自测。）

---

## 5. 待裁定 / 风险

| # | 项 | 状态 | 说明 |
|---|---|---|---|
| 1 | C5 低年段池=200 上限 | **待玄参大人裁定** | 正文写"20"，公式 `min(40, 200×25%)=40` 给 40。实现按**公式 40**，已标记待确认。 |
| 2 | S1/S3 真机渲染与常亮 | 待真机 | 本机无 JDK/模拟器，无法渲染打包。 |
| 3 | 常亮国产 ROM 杀进程 | 待真机多机 | 单测无法覆盖，需 3–5 台连跑验证。 |
| 4 | `flutter test` 沙箱不可用 | 已绕开 | 改用 `dart test` 跑纯逻辑单测（见经验表）。 |
