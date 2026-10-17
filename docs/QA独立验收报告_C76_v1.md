# QA 独立验收报告 · C76 专注报告 v2（T04）

- 验收人：QA 严过关（Edward）
- 仓库：`/Users/wangjunchao/WorkBuddy/sunflowerTime`（main，HEAD `95cf355`，含本批未提交改动）
- 私有副本：`/tmp/qa_c76`（`rsync -a --exclude build --exclude .git`，全部变异只在此副本内做，结束已 `rm -rf`）
- 命令统一摘代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy flutter test --no-pub`
- 交付批次：T01 数据层 / T02 信息架构 / T03 报告段 + 门控
- 玄参拍板口径（C76 裁定 #1）：**免费只能看近 7 天** → 月/年 + 近 4 周稳定性 + 热力图 **三处区域 + 两个周期按钮**归 `deepReport`；护眼统计免费可见

---

## ① 结论 + 路由

**结论：验收通过（独立复现工程师自报数字，并额外取证 6 组变异、4 组边界视口、5 条白名单纪律、3 条取数口径）。**

| 项 | 结论 |
|---|---|
| analyze | **103 info / 0 warning / 0 error** —— 与工程师自报一致（共享树与副本逐行 diff 仅差工程名） |
| 全量测试 | **1479 passed / 0 failed / 0 error**（1658 testStart 中 179 条为 group/loading 隐藏项）—— 一致，无「假绿」 |
| 门控（免费只近 7 天） | 成立。月/年不切换 + 弹「升级解锁」给因；稳定性 / 热力图整卡替换为付费引导卡；护眼免费 |
| 取数纪律 | 成立。免费档**7 次**按日查询（仅本周），买断档才付 35 次稳定性 + 365 天热力图 |
| 白名单纪律 | 成立且**有牙**。`focus_report_section.dart` 白名单恰 1 条，其余 5 个新 widget 零 token |
| 边界视口 | 成立。375×667 / 320×568（1.0× 与 1.3×）/ 834×1194@1.3× 全 **零异常、零横向溢出** |
| 未回归 | 成立。phase4 / free_tier / guard / nav_structure / 记录页 4 例 —— 断言未削弱 |
| 数据层 | 成立。`schemaVersion` 仍 **25**，无新表 / 新列 / 迁移 |

**路由判定：`NoOne`** —— 未发现生产代码 Bug；本轮亦未发现测试代码缺陷（见 ⑧ 的两处「文档级轻微不符」与一处「非我所致的共享树脏改动」）。

---

## ② 数字表（共享树 / 私有副本）

| 指标 | 共享树 `sunflowerTime` | 副本 `/tmp/qa_c76` | 一致 |
|---|---|---|---|
| `analyze` info | 103 | 103 | ✅ |
| `analyze` warning | 0 | 0 | ✅ |
| `analyze` error | 0 | 0 | ✅ |
| `test` 用例总数（含隐藏） | 1658 | 1658 | ✅ |
| `test` 隐藏项（group / loading） | 179 | 179 | ✅ |
| `test` **passed** | **1479** | **1479** | ✅ |
| `test` failed | 0 | 0 | ✅ |
| `test` error | 0 | 0 | ✅ |
| `reporter=json` 的 `done.success` | `true` | `true` | ✅ |
| 测试文件（suite）数 | 158 | 158 | ✅ |

**逐条解析（排除假绿）**：用脚本逐行消费 `--reporter json` 的 `suite / testStart / testDone(hidden) / error / done` 事件，统计口径为「非 hidden 的 `testDone`」。`errors` 事件计数 = 0，`done.success == true`。`analyze` 两份输出做 `diff`（抹掉 `Analyzing <name>` 与耗时行）后**完全一致**。

关键文件用例数（共享树实测，全绿）：

| 测试文件 | 用例数 | 结果 |
|---|---|---|
| `test/qa/focus_report_gating_test.dart`（🆕） | 6 | 6 passed |
| `test/m4/focus_report_period_test.dart`（🆕） | 23 | 23 passed |
| `test/m3/parent_history_page_test.dart` | 7（4 既有 + 3 新增） | 7 passed |
| `test/qa/phase4_gating_test.dart` | 12 | 12 passed |
| `test/qa/free_tier_no_regression_test.dart` | 7 | 7 passed |
| `test/qa/entitlement_gate_guard_test.dart` | 3 | 3 passed |
| `test/nav/nav_structure_test.dart` | 6 | 6 passed |

---

## ③ 变异表 M1–M6（全部在 `/tmp/qa_c76`，每次只改一处，跑完立即还原并校验 shasum）

还原基准（与共享树逐字节一致）：

- `focus_report_section.dart` → `f1aa38d1540982863c38959b7b892084aec2d70310a44e6baf171076877381ea`
- `report_period.dart` → `0d46dcf8f52988affbb9caf71dd1219ef1cc4c9ccf0c4f42633465e8c70388dd`
- `focus_report_gating_test.dart` → `73b0fe3cf4a4c62323644bb48915aaaddde28c04cb8d4b531235b78364a4ffff`
- `report_heatmap.dart` → `36d925a103d855c24be32db6513c774b3121b3349ebc8d469bd79dc489a27404`

| # | 改了什么（文件:行） | 预期红 | 实测 | 红在哪条断言 |
|---|---|---|---|---|
| **M1** 门控失效 | `focus_report_section.dart:99-100` `_isUnlocked(...) => featureAllowedFor(FeatureKey.deepReport, tier)` → `=> true` | 免费档 3 例（锁图标 / 点月不切换 / 引导卡） | **2 红 / 4 绿** | `:154` `find.byIcon(Icons.lock_outline)` `findsNWidgets(2)` → **Found 0**；`:178` `find.text('解锁「深度专注报告」')` `findsNWidgets(2)` → **Found 0** |
| **M2** 点击静默 | `:219` 删掉 `showPremiumUpsell(context, FeatureKey.deepReport)` 只留 `return` | 「弹出升级解锁」变红 | **1 红 / 5 绿** | `:169` `find.text('升级解锁')` `findsOneWidget` → **Found 0**（C62「不可点≠静默」有牙） |
| **M3** 引导卡静默隐藏 | `:326` `const Widget locked = PremiumUpsellCard(...)` → `const SizedBox.shrink()` | 「解锁×2」变红 | **1 红 / 5 绿** | `:178` `find.text('解锁「深度专注报告」')` `findsNWidgets(2)` → **Found 0** |
| **M4** 免费档偷查数据 | `:142-143` 去掉 `unlocked ? … : null` 三元，恒查 365 天 | 热力图零渲染 / 查询跨度变红 | **1 红 / 5 绿** | `:183` `find.byType(ReportHeatmap)` `findsNothing` → **Found 1** |
| **M4b**（M4 补充取证） | 在副本里临时删掉 `:183/:185` 两条渲染断言，只留「查询跨度」守卫 | 守卫自身有牙 | **1 红** | `:189` `rangeSpans.every(span <= 8)` → **false，实收 `[7, 365]`**（免费档真的偷查了 365 天窗口） |
| **M5** 周期口径破坏 | `report_period.dart:54` `month` → `start.add(Duration(days: 30))` | m4 周期测试变红 | **7 红 / 16 绿** | `:218` 月区间终点 `2026-11-01` 期望 / **实得 `2026-10-31`**；`:259` 闰年 `2024-03-01` 期望 / **实得 `2024-03-02`**；另 5 条：月聚合·累计分钟、月聚合·bestDay、平均每日·进行中(dayCount 17)、平均每日·历史(dayCount 31)、趋势桶·月档 |
| **M6**（白名单守卫补证） | 在副本 `report_heatmap.dart` 末尾追加一行 `const Object _m6Probe = FeatureKey.deepReport;` | 守卫红 | **1 红 / 2 绿** | `权益标识符只允许出现在白名单文件内` → `lib/presentation/parent/widgets/report_heatmap.dart:329 出现「\bFeatureKey\b」` |

> 结论：**门控、给因、非静默、取数纪律、周期口径、白名单**六条守卫逐条有牙，不是摆设。
> 每组变更后均以 `cp` 还原并被 `shasum -a 256` 复核为**基线值**（上表 4 个哈希全数命中）。

---

## ④ 边界视口表（不改生产代码；临时用例只存在于副本，跑完已删）

测试形态：`Scaffold(body: ParentHistoryPage(now: 2026-10-17))`（= 生产里 `ParentHomePage` body 的真实承载形态），用 `tester.binding.setSurfaceSize` + `MediaQuery.textScaler` 参数化。

| 视口 | textScaler | ① 异常数 | ② 周期条宽 / 分段控件宽 | ③ 免费档引导卡文本宽 | ④ 热力图卡宽 / 横滑视口宽 | 热力格数 | 能滚到护眼卡 |
|---|---|---|---|---|---|---|---|
| 375×667 | 1.0× | **0** | 343 / 343（屏 375） | 172.5 | 343 / 319 | 365 | ✅ |
| 320×568 | 1.0× | **0** | 288 / 288（屏 320） | 172.5 | 288 / 264 | 365 | ✅ |
| 320×568 | **1.3×** | **0** | 288 / 288（屏 320） | 200.0 | 288 / 264 | 365 | ✅ |
| 834×1194（平板） | **1.3×** | **0** | 802 / 802（屏 834） | 223.5 | 802 / 778 | 365 | ✅ |

- ① `tester.takeException()` 在「首屏 → 稳定性区 → 热力图区 → 护眼卡」四个节点各排空一次，**全为 null**（含 `RenderFlex overflow` 类异常）；
- ② 周期条与 `SegmentedButton<int>` 宽度**全部 ≤ 屏宽**（最紧 320 屏占 288，余量 32pt），`FittedBox` + 外置横向滚动兜住了 1.3× 缩放；
- ③ 免费档在稳定性区与热力图区各见 1 张付费引导卡（`解锁「深度专注报告」`），文本宽 172.5 → 200.0（1.3×）→ 223.5（平板 1.3×），**均 ≤ 屏宽**；
- ④ 热力图卡宽 ≤ 屏宽，卡内横向 `SingleChildScrollView` 视口宽**恒 ≤ 卡宽**（319 ≤ 343、264 ≤ 288、778 ≤ 802）→ 53 列日历格被横滑视口吃掉，**不溢出卡片边界**；买断档实测 365 个 `heatCell_*` 全部渲染。
- **无溢出，故无「具体数值 + 控件」需要上报。**

---

## ⑤ 白名单纪律（5 条结论）

1. **`focus_report_section.dart` 在 `_whitelist` 中恰好 1 条**（`:65`）。全文件共 3 次文本出现：`:61` 说明注释、`:65` 白名单条目、`:116` 存在性清单条目 —— 白名单本体只有 1 条，未重复登记。
2. **其余 5 个新 widget 文件均不在白名单**，且对 10 个禁用 token 逐个 grep（`\bEntitlement` / `\bFeatureKey\b` / `\bFeatureRule\b` / `\bRestoreResult\b` / `\bPremiumGate\b` / `\bkEntitlementMatrix\b` / `\bkUnlimitedQuota\b` / `\bentitlementProvider\b` / `\bentitlementServiceProvider\b` / `\bentitlementRepositoryProvider\b`）**每条均 0 命中**：

   | 文件 | 在白名单 | 10 token 总命中 |
   |---|---|---|
   | `report_palette.dart` | ❌ | **0** |
   | `report_period_bar.dart` | ❌ | **0** |
   | `report_heatmap.dart` | ❌ | **0** |
   | `report_stability_card.dart` | ❌ | **0** |
   | `report_eye_care_card.dart` | ❌ | **0** |

3. **存在性清单（`:96-117`）与白名单条目数一致**：都是 **19 条**，集合完全相同（脚本比对 `set` 相等）。
4. **`parent_report_page.dart` 零改动**：`git diff -- lib/.../parent_report_page.dart` 为空，`git status --porcelain` 该路径为空；文件内 `focusReportServiceProvider` 仍出现 **1 次**（旧页仍是本地聚合的孤儿页，符合设计）。
5. **守卫有牙（双证）**：① M6 变异 → 守卫立刻红并精确报出 `report_heatmap.dart:329`；② 全仓扫描：**非白名单 `lib/**.dart` 文件中 10 个 token 命中数 = 0**（唯一带 token 的新文件就是白名单里的 `focus_report_section.dart`，占 7 行代码 + 2 行文档，白名单登记是**必需而非装饰**）。

---

## ⑥ 未回归（5 条）

1. **三绿**：`phase4_gating_test` **12 passed** / `free_tier_no_regression_test` **7 passed** / `entitlement_gate_guard_test` **3 passed**，0 失败。
2. **`free_tier` 正向断言未被削弱**：该文件 `git status` 为**未改动**（零 diff）。其 3 条关键断言（`parent_report_page.dart` 不含 `PremiumGate`、不含 `Entitlement`、**仍含 `focusReportServiceProvider`**）全部仍在且为真（实测 `focusReportServiceProvider` 计数 = 1）。
3. **记录页 4 例既有断言未被削弱**：`test/m3/parent_history_page_test.dart` 的 diff **只有 4 处插入 `await _switchToActivity(tester);` + 追加 3 个新用例**，既有 `expect` 行**一字未改**（`完成 2 次` / `今天 · 10月10日` / `本期间还没有成长项完成记录` / `完成 3 次 findsNothing` 等全部原样保留）。
4. **`nav_structure_test` 6 passed**：其中 `:407` 例断言「恰好 5 项、顺序 今日/奖励/成长/记录/设置」且 `:426 expect(find.byType(TabBar), findsNothing)` —— 新的 `SegmentedButton` 分段控件**没有**引入 TabBar，底栏结构零回归。
5. **`/parent/report` 重定向 —— 行为级验证（真 router + 真实 redirect 链）**：
   - 用真实 `routerProvider` 装配 `MaterialApp.router`，`SharedPreferences` 注入「已同意首启」后 `router.go('/parent/report')`；
   - `routerDelegate.currentConfiguration.uri` **恰为 `/parent/home?tab=3&seg=0`**（`matchedPath = /parent/home`）；
   - 落屏后 `find.byType(FocusReportSection)` **findsOneWidget**（报告段可见）、`find.byType(HistoryActivitySection)` **findsNothing**（非默认段被 Offstage 跳过）→ `tab=3` 与 `seg=0` 双双生效；
   - 反向对照：`/parent/home?tab=3&seg=1` → `HistoryActivitySection` 可见 / `FocusReportSection` 不可见 → `initialSegment` 确实被透传并生效。
6. **设置页入口卡「不是死点击」**：用 stub router 捕获目标 URI 后 `tap('专注报告')` → 捕获值**恰为 `/parent/home?tab=3&seg=0`**，且副标题已按免费边界收紧为 **`近 7 天专注分布与健康指标`**（原文案为「周/月专注分布…」，与「免费只近 7 天」矛盾，本批已改正，👍）。

---

## ⑦ 口径核查（3 条）

1. **免费档不得发起 365 天窗口查询 —— 成立，双向取证**：
   - 正向：`focus_report_gating_test:191` `rangeSpans.every(span <= 8)`，免费档实测 `[7]`；
   - 反向（M4b）：把 `_load` 里 `heat` 三元去掉后，跨度立刻变成 **`[7, 365]`** 并把注释为「免费档不得发起 365 天热力图范围查询」的断言打红。
2. **`buildReport` 的 35 次按日查询只在买断档发生 —— 成立（计数探针）**：用一个**只实现 `FocusRepository`、不实现 `FocusRangeQuery`** 的计数假仓储（强制走逐日回退路径，使每次查询可见）：

   | 档位 | `sessionsOfDay` 调用次数 | 覆盖日期 | 结论 |
   |---|---|---|---|
   | 免费 | **7** | `2026-10-12` ~ `2026-10-18`（仅本周） | 无 35 次稳定性、无 365 天热力图 |
   | 买断 | **407** = **7**（周档）+ **35**（稳定性 4×7+7）+ **365**（热力图） | 去重 366 天 | 两笔代价只在买断档支付 |

   （去重 366 = 365 天热力图窗口 `2025-10-18~2026-10-17` 并上本周多出的 `2026-10-18` 明天，符合预期。）
3. **`schemaVersion` 仍 25、无新表 / 新列 / 迁移 —— 成立**：`lib/data/local/database/app_database.dart:59` `int get schemaVersion => 25;`；该文件 `git status` **未改动**；`git diff lib/data/` 全量只有 `focus_local_repository.dart` **+23 / -1**（`implements FocusRangeQuery` + `sessionsBetween`，复用既有列 `start`，半开 `[from, to)` + `orderBy start, id`），diff 中 `createTable` / `alterTable` / `migration` / `from:` / `to:` 关键字**零命中共 0 条**。

---

## ⑧ 遗留风险与建议

1. **`parent_history_page.dart` 行数与任务书不符（文档级，非缺陷）**：任务书写「809 → **166** 行」，实测 **144 行**（`history_activity_section.dart` 817 行、`focus_report_section.dart` 843 行均与任务书一致）。功能无影响，建议工程师在交接文档里订正数字。
2. **⚠️ 共享树多出 2 个非本批改动（非 QA 所致，需主理人确认归属）**：开工时我的 `git status --porcelain` 基线快照（`/tmp/qa_baseline_status.txt`，落盘 **11:05:17**）为 **21 条**；收工复检为 23 条，多出 ` M docs/口径裁定表_v1.md`（mtime **11:05:22**）与 ` M docs/项目进度跟踪表.md`（mtime **11:05:28**）。两者 mtime 均晚于我取基线的时刻，且我**从未写过 `docs/`**，判断为**同批其他成员（主理人）在我开工瞬间并行提交的文档更新**（内容为 +29 / +25 行说明性文字，不涉及 `lib/` 与 `test/`）。**`lib/` 与 `test/` 的 21 条基线条目逐字节未变**，4 个关键文件 shasum 与基线完全一致 —— 隔离红线未破。
3. **`ReportPeriodBar` 锁定档位「可点但拦截」的语义依赖上层**：`report_period_bar.dart` 的 `onTap` 恒非空（符合 C62），拦截完全由 `focus_report_section._onPeriodTap` 承担。若未来有人复用 `ReportPeriodBar` 而不传拦截逻辑，会出现「点了月却切不过去且无提示」的静默缺陷。建议在 `ReportPeriodBar` 文档里补一句「调用方必须自行拦截 + 给因」，或加断言型注释（当前已有一处说明，强度尚可）。
4. **热力图列数上限未与数据长度耦合校验**：`report_heatmap` 的 `columns = ((lastIdx - firstIdx) ~/ 7) + 1` 依赖 `days` 已按日连续。当前 365/366 天输入下实测正确；若将来传入非连续序列（如只查有数据的天），会画错列位置。属潜在脆弱点，非本批缺陷。
5. **`flutter analyze` 的 103 条 info 全部落在 `test/**`（`prefer_const_*` 类）**，生产代码零告警。建议后续单独一批「测试代码 lint 清零」，避免长期噪声掩盖真问题。
6. **建议把本轮 3 个临时探针沉淀为正式回归用例**（当前只在副本里跑过、已删除）：①「查询计数」探针（免费 7 / 买断 407，最能防「免费档偷偷跑 35+365 次」的性能回归）；②「重定向 + 入口卡目标 URI」探针；③「4 档边界视口」探针。三者都是**数值型**断言，比现有文案断言更抗文案漂移。

---

## 附：隔离执行记录

- 所有变异 / 探针文件**只存在于** `/tmp/qa_c76`；共享树 `lib/` 与 `test/` **只读**（仅在共享树跑 `analyze` + `test`，未做任何「改坏→还原」）。
- 结束前 `rm -rf /tmp/qa_c76`；本报告为唯一新增文件（`docs/QA独立验收报告_C76_v1.md`）。
- 未做任何 git 写操作（无 `add` / `commit` / `checkout` / `reset` / `stash`）。
