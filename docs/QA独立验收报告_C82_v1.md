# C82 QA 独立验收报告（最终合并权威版）

> 验收人：严过关（Yan）· QA 工程师 ｜ 日期：2026-10-17 ｜ 基线 HEAD `0c898cd` + C82 在制（lib 3 / test 2 / docs 3）
> 准绳：软件工程师-2 交付说明、F116 口径、`docs/项目进度跟踪表.md` §7 文档同步矩阵
>
> ⚠️ **版本裁决**：本轮曾发生「**双 QA 同树变异**」——复核期间同一份工作树被另一路并发「改坏 → 还原」，导致**首版报告**（早期写入 `docs/QA独立验收报告_C82_v1.md` 的那份）的**隔离用例数字与 analyze 计数被污染**。**首版作废，以本版为准。**污染事件留痕见 §八。
>
> 本版所有数字/结论**均在私有隔离副本 `/tmp/qa2_proj` 内独立重跑得出**，不采信任何他方自报。

---

## 一、独立重跑数字（隔离副本，自跑）

| 项 | 命令 | 实测 |
|---|---|---|
| 全量（JSON 逐条解析 `testDone`，排除 hidden） | `flutter test --no-pub --reporter json` | **PASSED=1441 / FAILED=0 / OTHER=0 / ERROR(events)=0**（EXIT=0） |
| 静态分析 | `flutter analyze` | **0 error / 0 warning / 103 info**（EXIT=1 为 flutter 对 info 的固有非零返回，属预期） |

> 1441 = 基线 1435 + 工程师复现用例 5（`garden_care_repro_test.dart`）+ QA 反向护栏 1（`garden_growth_sfx_no_care_test.dart`）。已确认两份新增测试文件均被包含且通过。

---

## 二、变异测试（6 次改坏，定向变红后**字节级还原**）

方法：仅在私有副本内 `Edit` 改坏 → 内置 Grep 回读确认 → 跑对应用例 → **立即还原** → `shasum` 校验字节一致。**全程未用 `git stash` / `checkout` / `restore`**。

### Bug1 · 浮层稳定 Key（逐键细粒度）

| 编号 | 改坏内容 | 目标用例 | 实测 | 还原 |
|---|---|---|---|---|
| **M1** | 删成长 Key（保留养护 Key） | 复现·Bug1 | 🟢 **仍绿（3/3）**——`GrowthFxOverlay initState` 仅 1 次 | ✅ |
| **M1b** | 删养护 Key（保留成长 Key） | 复现·Bug1 | 🟢 **仍绿** | ✅ |
| **M1c** | **两把 Key 全删**（= 修复前） | 复现·Bug1 | 🔴 **红（3/3）**：`Expected: <1> / Actual: <2>`，日志 `initState` **出现两次** | ✅ |

**结论**：Bug1 的 remount **真实存在**（双删必红、`Actual=2` 稳定复现），修法与根因方向正确；但**关键不是「那一把成长 Key」**——**任一把独立 Key 即足以断链**（顶对齐在该 index 因 key 不匹配而提前停止 → 改由**自底向上**按 (类型+key) 匹配 → `GrowthFxOverlay` 元素被保住、不 remount）；**只有两把都缺**才 `canUpdate`（`null==null` 同类型 `Positioned`）**误命中** → 原地复用、仅换 child → 子类型不匹配 → 旧元素卸载 + 新建 State → 动画从第 0 帧重放。⇒ 两把都留作**双保险**（单把已足够）。

### Bug2 · 定向修复（`playGrowthSfx`）

| 编号 | 改坏内容 | 目标用例 | 实测 | 还原 |
|---|---|---|---|---|
| **M2** | `playGrowthSfx: !sameActionCareSound` → 恒 `true` | 复现·浇水/施肥 | 🔴 **红**：care_water / care_fertilize `Expected ≥1 / Actual 0`（load 序列为空）；**care_weed / care_pest / Bug1 仍绿**（3 绿 2 红） | ✅ |
| **M2′** | `playGrowthSfx` → 恒 `false`（反向） | 🆕 自然成长用例 | 🔴 **红**（`Actual: 0`，日志 `SKIP growth SFX`）→ 证明该反向护栏**有牙** | ✅ |

**结论**：`playGrowthSfx: !sameActionCareSound` 是 Bug2「浇水/施肥无声」的**真实修复点**；且回退后**除草/除虫仍绿** → 二者不依赖此修复（无成长跃迁 → 无 cue 竞争）。

### Bug2 第二道防线 · token 去重（`_lastPlayedGrowthToken`）

| 编号 | 改坏内容 | 观察 | 结论 | 还原 |
|---|---|---|---|---|
| **M3** | token 去重短路 → 恒 `false` | **全量 1440 条用例仍全绿** | ⚠️ **零测试覆盖**——无任何用例变红（有效验收发现） | ✅ |

⇒ 已作为整改项 R2 上报，工程师据此**删除该死代码**（字段 / 短路 / 赋值三处 + `Plant? plant` 参数 + 调用点），保留 `_growthFxInFlight` 不动。

---

## 三、整改项 R1/R2/R3 落实情况核实（逐条独立核对）

| 项 | 落实 | 核实证据 |
|---|---|---|
| **R1** 归因注释修正 | ✅ **已落实且准确** | `garden_page.dart:90-107`（常量 doc）+ `:1967-1978`（Stack 内联）已改为**实测机制**并写入 **M1/M1b/M1c 结论**（「任一把 Key 在位即可断链…两把都缺才 remount…两把都留作双保险」）——与本报告 §二 完全一致 |
| **R2** 删除 token 死代码 | ✅ **已落实** | Grep 全 `lib/`：`_lastPlayedGrowthToken` **0 命中**；`_playGrowthFx` 定义已无 `plant` 参数（`garden_page.dart:1011-1015`），调用点（`:838` 预览 / `:980` 检测）一致；`:1007-1010` doc 注明「v1 曾加…零覆盖死代码已移除」。`analyze` **0 warning** 佐证无残留未用变量/参数 |
| **R3** C82 文档登记 | ✅ **已落实且无虚报** | 见 §四 |

**① `sameActionCareSound` 计算式完整性**：`:976-977` = `recoveryReEntry || (_activeEffect?.plant?.id == p.id)`（完整、未被删 token 波及）；`:983` = `playGrowthSfx: !sameActionCareSound`（在位）。✅

---

## 四、文档登记准确性核查（R3 细核）

### ① 真机验收状态（**不得虚报**）
- `口径裁定表_v1.md:1077`（C82 抬头）：**「状态：代码已改、未提交；真机验收 = 待玄参复测」** ✅
- `项目进度跟踪表.md:900-902`（§1.17）：**「⚠️ 未提交…真机验收 = 待玄参复测」** ✅
- `bug记录表.md:893`（F119）/ `:894`（F120）：**「🚧 代码已改（未提交）｜真机验收状态 = 待玄参复测」** ✅
- 三处正文**均无**「已修复 / 已验证」这类未验表述（对 F119/F120 行逐行核对「已修复|已验证」零命中）。✅

### ② Bug 编号接续
`F118`（今日页徽章）→ **`F119`**（花园·成长演出 remount）→ **`F120`**（花园·音频养护音效）——**连续、无跳号、无重号**。✅

### ③ 口径表 C82 正文与代码事实一致性
- 「**任一把 Key 即断链**」：与 §二 M1/M1b/M1c 实测一致 ✅
- 「**串行两首都播被否决 = 音画错位 ~3s**」：与代码事实一致——养护动效时长 `kCareWaterDurationMs=2900ms` / `kCareFertilizeDurationMs=3056ms`（`prd_params.dart:570/573`），「让养护音效先占满 ≈3s → 成长音效迟到 ~3s」成立 ✅
- 「**token 去重 = 删除**」：与代码一致（§三 R2）✅
- 「除草/除虫无声 = 未定论」：与 §六 一致 ✅

> **核查结论：R3 三项文档登记内容准确、状态无误导性表述，未发现虚报。无新增整改项。**

---

## 五、回归红线（不许改坏 F116）

| 检查 | 结果 |
|---|---|
| `test/m3/sfx_concurrency_guard_test.dart` | 🟢 绿（F116「后发起者赢」3 条守卫全过） |
| `test/m3/growth_fx_overlay_test.dart` | 🟢 绿 |
| `test/m3/ambient_d1d2_guard_test.dart` | 🟢 绿（三文件合计 **14 passed**） |
| **F116 语义是否被改** | ✅ **未改**：逐行核对 `git diff lib/platform/audio_service.dart`，**新增行全部**为注释 / `_adbg(...)` / `abandon(...)`；`stale()` 布尔条件**逐字一致**，`if (stale()) return;` 仅被包成 `if (stale()) { <日志> return; }`，控制流不变 |
| **成长音效未被误杀**（自然成长仍发声） | ✅ 由 🆕 `garden_growth_sfx_no_care_test.dart` 守护（接记录型假 just_audio：无养护动作、`_activeEffect==null` 的 `sprout→adult` 自然跃迁 → `playSfx=true` → 真实 load `grow_sprout_to_adult.mp3`）；M2′ 已反向证其有牙 |
| 全量 | **1441/0/0** → 无回归 |

---

## 六、日志门控核查（release 零噪声）

逐处读源码确认门控：
- `garden_page.dart:84-88` `_gfxDbg`（tag `GARDENFX`）：`if (!kDebugMode) return;` ✅
- `growth_fx_overlay.dart:79-83 / :89-92` 两处 `debugPrint`：均在 `if (kDebugMode) { … }` 内 ✅
- `audio_service.dart:38-42` `_adbg`（tag `AMBDIAG`）及本轮新增全部 `_adbg` / `abandon`：`if (!kDebugMode) return;` ✅
- 三处均走 `debugPrint`（`flutter test` 下指向 `debugPrintSynchronously`，**不留 pending timer**）✅

---

## 七、未定论项（如实登记，非结论）

1. **除草 / 除虫真机无声 —— 仍未定论**。harness 修复前即绿（无成长跃迁 → 无 cue 竞争，见 `garden_care_repro_test.dart` 用例③/⑤ 修复前后均绿）；变异 M2 亦佐证二者不受本修复影响；**真机未能复现、未能定位第三作废源**。**待玄参真机复测**。
2. `_playCareEffect` 三处早退分支真机是否触发（harness 命中 0）。
3. `_activeEffect` 与 `_detectGrowthTransitions` 的先后时序在真机是否成立。

---

## 八、路由判定与遗留

### 路由判定：**NoOne ✅**（全通过，无需回派 Engineer、无需 QA 自修）

C82 两 Bug 经独立重跑（**1441/0/0**）+ **6 次变异实验**（M1/M1b/M1c/M2/M2′/M3）+ 回归红线全核验，功能正确、无回归；三条整改（R1/R2/R3）**均已落实且经独立核实准确**。⇒ **NoOne**。

**遗留（非阻塞，待真机）**：§七 三项真机待验（除草/除虫无声、早退分支、时序）；诊断日志建议真机复测收口后按需清理（P2）。

---

## 附：并发变异污染事件（过程留痕）

本轮复核期间检测到**共享工作树被并发「改坏 → 还原」**：本 QA 在共享树跑隔离用例时 Bug1 一度变红（`Actual=2`）、`analyze` 一度报出 2 条 `unused_element` warning（`_kCareEffectOverlayKey` / `_kGrowthFxOverlayKey` 未引用）；而 `shasum` 取证显示——我 `cp` 的备份恰为**缺这两把 Key** 的状态，随后文件又恢复为含 Key 的版本。⇒ 系**另一路（并行 QA / 工程师）在同一工作树做变异**所致，非真实缺陷。

**处置**：全部变异与重测改在私有副本 `/tmp/qa2_proj` 内进行；**共享工作树 `lib/` 全程只读**（本报告仅写/删 `docs/` 两个文件，未改任何 `lib/`、`test/`）。
