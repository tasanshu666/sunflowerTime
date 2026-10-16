# C81 QA 独立验收报告（详情卡体验修复 · C80 续批）

> 验收人：严过关（Yan）· QA 工程师 ｜ 日期：2026-10-16 ｜ HEAD：`145f9ad`（main）
> 权威准绳：`docs/口径裁定表_v1.md` **C81**（L1058-1071，玄参真机验收拍板 6 条）+ `docs/项目进度跟踪表.md` §1.16。
> 方式：**独立重跑 + 自证伪**；变异测试一律 **Edit 改坏 → 手动还原**（未用任何 git 恢复命令）。

---

## 一、真实测试数字（自跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 全量（JSON 解析 `testDone`） | `flutter test --no-pub --reporter json` | **非隐藏 1435 · success 1435 · failure 0 · error 0**（hidden 169）；EXIT=0 |
| C81 目标 4 文件复跑 | `flutter test test/m3/plant_perk_test.dart test/m3/level_detail_perk_layout_test.dart test/m3/focus_level_detail_dialog_test.dart test/qa/premium_unlock_table_test.dart` | **66/66 All tests passed!** |

✅ 与工程师自报 1435 全绿一致，且经 JSON 事件流逐条核对，排除隐藏失败。

## 二、静态分析数字（自跑）

`flutter analyze --no-pub` → **103 issues = 103 info / 0 warning / 0 error**（与基线持平）。

## 三、变异测试（4 组，全部捕获并手动还原）

| # | 改坏内容（file:line） | 期望红用例 | 实测 | 还原 |
|---|---|---|---|---|
| M1 | `plant_perk.dart` `perkShortTextOf` 浇水分支加回「消耗」前缀 | `plant_perk_test` ③ 纯数值 | 🔴 红：`perkShortTextOf：C81 纯数值带符号（9 节点逐条）` fail | ✅ 已还原 |
| M2 | `focus_level_badge.dart` 卡宽 `kLevelDetailCardMaxWidth * s` → 去掉 `* s` | `level_detail_perk_layout_test` TC-32 平板卡宽 ≈403 | 🔴 红：`TC-32 平板 uiScaleOf=1.3 …卡宽 ×1.3` fail | ✅ 已还原 |
| M3 | `focus_level_badge.dart` `_PerkPill` 锁标 `if (locked)` → `if (false)`（去点按） | `focus_level_detail_dialog_test` ⑧ 弹提示卡 | 🔴 红：`⑧ 锁标态点按 → 弹提示卡` fail | ✅ 已还原 |
| M4 | `focus_level_badge.dart` 阳光图标加回 `if (unlocked)` 条件（模拟原 `if(!plain)`） | `level_detail_perk_layout_test` TC-31 9 行统一☀ | 🔴 红：`TC-31 …9 行统一带阳光图标` fail | ✅ 已还原 |

**还原校验**：`grep` 无任何变异标记残留；C81 目标 4 文件复跑 **66/66 全绿**；HEAD 不变、`git status` 未增删源码文件。

## 四、C81 六条逐条判定（file:line 证据）

| # | 裁定 | 实现证据 | 判定 |
|---|---|---|---|
| ① | 锁标点按**只弹提示卡**（不 pop/不跳转） | `focus_level_badge.dart:676-690` `_showLockedHint`→`AlertDialog`（`perkLockedHintKey`，文案 `kPremiumUpsellHintText`）；`:743-751` 仅锁标态 `GestureDetector.onTap`；`lib/presentation/child/**` 内 `/parent/premium` **零出现** ⇒ **V3-Q1 结案** | ✅ PASS |
| ② | 9 行末尾**统一**带 ☀ | `:724-736` 阳光 `Image.asset` **无** `if(!plain)` 条件；TC-31 断言 9 行各 1 枚 `Image`（变异 M4 触红） | ✅ PASS |
| ③ | 删「额外/消耗/返还」→ **纯数值** | `plant_perk.dart:264-275` 返回 `−1 / +1 / −20 / +20`（变异 M1 触红） | ✅ PASS |
| ④ | 顺序 `[🔒] emoji 属性名 数值 ☀` + 新增属性名 | `focus_level_badge.dart:713-736` 顺序核对；`prd_params.dart:1648` `kPerkNames`（9 名）+ `plant_perk.dart:189-192` `perkNameOfTitleNode` 单点派生 | ✅ PASS |
| ⑤ | 当前行右列对齐 → **删 ✨** | `kLevelDetailCurrentMark` 在 `lib/**` **零出现**；当前行改 `高亮底 + w800`（`:416 / :432-434`），详情卡无 ✨ 渲染 | ✅ PASS |
| ⑥ | 平板详情卡加宽 | `:315/:324` `maxWidth: kLevelDetailCardMaxWidth * uiScaleOf`（平板 1.3 → 403）；TC-32（变异 M2 触红） | ✅ PASS |

## 五、文档落档核查

| 文档 | 落点 | 结论 |
|---|---|---|
| 口径裁定表 C81 | `L1058-1071` | ✅ 含**裁定全文 6 条**（非空壳）+ 影响面清单 |
| 进度跟踪表 §1.16 | `L879-896` | ✅ 6 条修复表 + ②核实根因 + 测试改写 4 文件 + 文件清单 |
| PRD | `L89` C81 修订说明 + §五 `L93/94/108` 勾选同步 | ✅ 与实现一致 |

## 六、零 DB / 红线

- **零 DB 变更**：`app_database.dart:59` `schemaVersion => 25`（不变），零迁移。
- **孩子端零购买入口**：`lib/presentation/child/**` 无 `/parent/premium`；`premium_unlock_table_test` T12 源码守卫（已改写断言）✅。

## 七、路由判定与遗留

**路由判定：NoOne ✅**（全通过，无需回派 Engineer / 自行修复）。

遗留（均非阻塞，仅上报）：
1. **陈旧注释**（P2 文案）：`lib/domain/entities/focus_level.dart:87` 注释仍写「详情卡据此高亮 **+ ✨**」——C81 ⑤ 已删 ✨，注释未同步（无功能影响、无测试断言；建议下批顺手改）。
2. **PRD §五 3 项真机待验**未勾（L95 手机/平板目检、L105 金额抽验、L112 真机抽验）——属玄参真机事项，代码侧已由 TC-31/32/34 与 provider 单点回落兜底。

---

**一句话结论**：C81 全量 1435/1435 绿、analyze 103/0/0，4 组变异全部被守卫捕获且已还原，六条裁定与实现逐条吻合、文档落档真实、零 DB —— **独立验收通过，路由 NoOne**。
