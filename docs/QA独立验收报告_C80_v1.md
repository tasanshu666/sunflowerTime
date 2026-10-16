# C80 QA 独立验收报告（称号属性付费解锁 + 详情卡改版）

> 验收人：严过关（Yan）· QA 工程师 ｜ 日期：2026-10-16 ｜ Head：`145f9ad`（main，工作区 97 文件在制）
> 权威准绳：`docs/称号属性_v1_系统设计.md` §0.3（V3-1..V3-8 / T01–T05 / TC-V3-01..19）+ PRD §五。
> 方式：**独立重跑 + 自证伪**，不采信工程师自报数字。变异测试一律 **Edit 改坏 → 手动还原**（未用任何 git 恢复命令）。

---

## 一、真实测试数字（自跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 全量（compact） | `flutter test --no-pub` | **`All tests passed!`** · EXIT=0 |
| 全量（JSON 解析 `testDone`） | `flutter test --no-pub --reporter json` | **非隐藏 testDone = 1434 · success = 1434 · failure = 0 · error = 0**（hidden 169 = 框架内部）；EXIT=0 |

✅ 数字与工程师自报一致（1434 全绿 / 0 fail），且经 JSON 事件流**逐条核对**，排除 compact reporter「... and N more」隐藏失败的可能。

## 二、静态分析数字（自跑）

`flutter analyze --no-pub` → **103 issues = 103 info / 0 warning / 0 error**（与基线 103/0/0 持平）。severity 直方图：`103 info •`，无 `error`/`warning`。

## 三、变异测试（证明非假绿 · 4 组，全部还原）

| # | 改坏内容（file:line） | 期望红用例 | 实测 | 还原 |
|---|---|---|---|---|
| (a) | `providers.dart:195` 短路条件前置 `false &&`（= 门控反转恒真） | TC-V3-02（free 老号仍 none） | 🔴 红：TC-V3-02 + TC-V3-04 均 fail（free 返回 `perkOfLevel(40)`） | ✅ 已手动还原 |
| (b) | `plant_growth_service.dart:243` `can(titlePerks)` 门控前置 `false &&`（= 删域防线） | 域防线（free 扣 5）+ currentPerk 直调 | 🔴 红：`注入 free 档假件 → 浇水扣 5` + `currentPerk() 直调 free→none` 均 fail | ✅ 已手动还原 |
| (c) | `entitlement_matrix.dart:174` `titlePerks.freeEnabled` false→true | TC-V3-01（矩阵目标值守卫） | 🔴 红：`C80 称号属性：free 关闭/premium 放开` fail | ✅ 已手动还原 |
| (d) | `premium_unlock_table.dart:86` 遍历 `derived` → `derived.take(4)`（模拟回退写死前 4 行） | T2（B 组 5 行齐全） | 🔴 红：`两栏胶囊 + 两个分组带 + B 组 5 行项目名齐全` fail（「称号属性」缺行） | ✅ 已手动还原 |

**还原校验**：还原后 `grep` 无任何变异标记（`false &&`/`derived.take(4)`）；`git status --porcelain | wc -l` = **97**（未增删）；HEAD = `145f9ad` 不变；4 组目标测试文件复跑全绿（21 用例）。

## 四、门控 / 域层 / 矩阵 逐条判定

| 判据 | 实现（file:line） | 判定 |
|---|---|---|
| 矩阵 `titlePerks`：free=false / premium=true / 双向 unlimited | `entitlement_matrix.dart:172-177` `freeEnabled:false` + free/premium 均 `kUnlimitedQuota` | ✅ PASS |
| 单点 `featureAllowedFor(titlePerks, free\|premium)` | `:184-192` → free=**false** / premium=**true** | ✅ PASS |
| provider：free 短路 none（含 level≥1 老号） | `providers.dart:192-210` watch entitlementProvider + 短路 `PlantPerk.none` | ✅ PASS（TC-V3-02，变异 a 证明） |
| provider：premium 累积 | Lv.1 仅 `eyeCareBonus=1`；Lv.40 9 字段全生效 | ✅ PASS（TC-V3-03a/b） |
| P1-1 购买即时生效（零回调） | watch entitlementProvider 自动重算 | ✅ PASS（TC-V3-04，变异 a 触红） |
| bounded 2s 异常回退 none | try/catch → none（free/premium 同路） | ✅ PASS（TC-V3-05） |
| **域层防线** `currentPerk()` | `plant_growth_service.dart:241-248`：`_entitlement.can(titlePerks)` 门控 | ✅ PASS（变异 b 证明） |
| 域防线：free 假件浇水扣 **5** | 基础值（即便累计 Lv.40） | ✅ PASS |
| 域防线：premium 假件浇水扣 **4** | C78 减免 | ✅ PASS |
| 域防线：`_entitlement==null` 保 C77 旧行为 | 不门控 | ✅ PASS |

## 五、文档落档真实性核查（防「空壳落档」）

| 文档 | 落点 | 结论 |
|---|---|---|
| `docs/口径裁定表_v1.md` | C80 条目 `L1046-1054` | ✅ **含 PRD §四裁决全文**（①门控分层 ②红线反转 ③矩阵 ④免费展示口径 ⑤详情卡改版 五点全文），非空壳；并含同批技术裁定 V3-Q1..Q3 + 收尾修正说明 |
| `docs/项目进度跟踪表.md` | `§1.15` `L854-875` | ✅ 存在 §1.15 C80；**T01–T05 状态如实**（均 ✅ 完成），附 6 文件测试改写清单与零 DB 声明 |
| PRD `docs/产品开发文档_详情卡改版与称号属性付费解锁_v1.md` | §五 A–E | ✅ 勾选状态与「真机待验 3 项未勾」一致：仅 `L93`（手机/平板目检+ellipsis）、`L103`（金额抽验 2 处）、`L110`（真机抽验两口径）为 `[ ]`，其余 `[x]` |

## 六、付费墙红线 C69 + 工程师修正复核

- **零 DB / 零迁移 / schemaVersion 不变**：`app_database.dart:59` `schemaVersion => 25`；`grep titlePerks lib/data/` 无命中 → C80 纯逻辑门控，未动表/列/迁移；账本/植株/等级数据不动（perk 锁定只拦「生效」，不删已存数据）✅
- **工程师自报修正复核（premium_unlock_table.dart）**：现为 `for (final PremiumUnlockRow r in derived)` 全量遍历（L86），**第 5 行「称号属性」真渲染**（变异 d 证明 T2 可捕获缺行）；取值 `freeText='✗'`(派生自 `featureAllowedFor(titlePerks,free)`)、`premiumText='✓ ${kFocusLevelTitleLevels.length} 条'`=**9 条**（派生防漂移）。核实：`kFocusLevelTitleLevels.length == 9`（`prd_params.dart:1236`）✅
- **UI 三态**：`FocusLevelDetailDialog → ConsumerWidget`（`focus_level_badge.dart:271`）；`_PerkPill` 三态（橙实心 / 锁标=置灰+🔒+可点 pop→push `/parent/premium` L719 / 灰字无锁）；演出卡 `_LevelUpContent → ConsumerWidget`（`level_up_fx_overlay.dart:287`）+ `kLevelUpFxPerkLockedSuffix` 尾缀（L418）✅
- **守卫**：`plant_perk_bypass_guard_test.dart` 白名单**恰好 4 文件**（L39-48）+ `kLevelPerkLegendText` 零残留；`entitlement_gate_guard_test.dart` 白名单 **+2**（L58-59 / L108-109）✅

## 七、路由判定与遗留风险

**路由判定：NoOne ✅**（全通过——源码无 Bug、测试代码无 Bug，无需回派 Engineer 或自行修复）。

遗留风险 / 建议（均非本批代码缺陷，不阻塞）：
1. **V3-Q1**：`/parent/premium` **无家长 PIN 守卫**（`app_router.dart:114-117`），与 PRD「PIN 照旧生效」假设不符 → 已如实落档裁定表 C80；**建议玄参拍板**是否另立路由守卫任务（本批不新增）。
2. **R-V3-2**：守卫白名单扩大（旁路 4 文件 + entitlement +2）削弱守卫强度 → 注释即契约，可接受。
3. **PRD §五 3 项真机待验**未勾（L93/103/110）→ 属玄参真机事项，代码侧已由 `level_detail_perk_layout_test`（textScaler 1.6 零溢出）与 provider 单点自动回落兜底。

---

**一句话结论**：C80 全量 1434/1434 绿、analyze 103/0/0，4 组变异均被守卫捕获且已还原，门控/域层/矩阵/文档落档与设计逐条吻合 —— **独立验收通过，路由 NoOne**。
