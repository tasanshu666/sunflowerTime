# C83 QA 独立验收报告（购买页主按钮吸底）

> 验收人：严过关（Edward）· QA 工程师 ｜ 日期：2026-10-17 ｜ Head：`c72bde1`（main）
> 方式：**独立重跑 + 自证伪**，不采信工程师自报数字。
> 隔离：所有变异/探针一律在副本 `/tmp/qa_c83/`（`rsync` 复制，排除 `build`/`.git`）内做；共享工作树 `lib/`、`test/` **全程只读**，**未执行任何 git 写操作**。

---

## 一、结论与路由

**结论：C83 交付成立，可以合并。**

- 吸底行为在真实视口下**独立复现**：主按钮 / 恢复入口常驻 `Scaffold.bottomNavigationBar`，滚动 y 位移 **0.00pt**，首屏即完整可见；400×800 / 375×667 / 320×568 三档视口底栏均**不越界**、主按钮均**完整可见**、说明卡均**可滚达**。
- 数字全部对得上：`analyze` 0/0/103、全量 **1443 passed / 0 failed / 0 error**（共享树 1 次 + 副本 2 次，三次完全一致）。
- 变异 M1/M2/M3 全部被现有测试**咬红**，守卫有牙；**但 M4 暴露两处「测试敏感度」缺口**（不是生产代码缺陷），见 §三。

**路由判定：`NoOne`**（全绿，生产代码未发现 C83 相关 Bug）。

附带三条**非阻塞**移交项（均不需回炉工程师返工）：
1. **QA 自身测试缺口 2 处**（M1 的 sticky 结构守卫漏检、M4 写死高度逃检）→ **✅ 已修**：经主理人授权后，补丁 A / B 已写入共享 `test/qa/premium_sticky_cta_test.dart`，并复跑 M1 / M4(96) / M4b(60) 三组变异验证咬红（详见 **§八 补丁复验**）。
2. **既存缺陷 1 处**（非 C83 引入，HEAD 基线同样复现）：320pt 宽英雄卡胶囊 Row 横向溢出 18px。
3. **可及性 2 处**（C83 改动带来的样式风险，非功能 Bug）：恢复按钮热区 34pt < 44pt、小字对比度 ≈3.1:1 < 4.5:1。

---

## 二、真实测试数字（自跑，逐条解析 JSON `testDone`）

| 项 | 共享树 `/Users/wangjunchao/WorkBuddy/sunflowerTime` | 副本 `/tmp/qa_c83` |
|---|---|---|
| `flutter analyze` error | **0** | **0** |
| `flutter analyze` warning | **0** | **0** |
| `flutter analyze` info | **103** | **103** |
| `flutter test --no-pub` passed | **1443** | **1443**（跑 2 次：变异前 / 探针删除后，均 1443） |
| failed | **0** | **0** |
| error | **0** | **0** |

- 解析方式：`--reporter json` → 只统计 `testDone` 且 `hidden != true`（排除框架内部用例），并单独统计 `type == "error"` 事件（排查"断言未跑就崩"的假绿）。**两份数字逐项一致，无差异需查因**。
- **用例账目核对**：基线 1441 → `premium_page_viewport_test` 旧 1 例被**整体重写**（−1）→ 新 1 例（+1）→ `premium_sticky_cta_test` 新增 2 例（+2）= **1443** ✅（工程师"−1 +3 = 1443"的算术成立；其表述里的"3 条新增"= 新 viewport 1 + sticky 2）。

---

## 三、变异测试（5 组，每次只改一处，全部还原）

还原证明：每组结束后 `shasum` 与共享树比对一致（`3f9f25df…3586`），且 `diff -r lib/ test/` 对副本与共享树**无任何输出**。

| # | 改坏内容（file:line） | 预期红 | 实测 | 还原 |
|---|---|---|---|---|
| **M1** | `parent_premium_page.dart:198` — 在 `_buildBody` 的 `ListView.children` 末尾**再插一份** `_buildMainButton(unlocked)`（底栏照留）= 重复 Key | sticky 的 `findsOneWidget` + `premium_page_test` 相关 | 🔴 **8 红**（39 例中）：`premium_page_viewport_test`（吸底用例）、`premium_page_test` 5 例（加载与价格 / 购买成功 / 用户取消 / 商店不可用 / loadProducts 抛错）、`premium_unlock_table_test` 2 例（T7 两态 `ButtonStyleButton`）→ 均为 `Found 2 widgets with key`。<br>⚠️ **但 `premium_sticky_cta_test` 单独跑 = 全绿（2/2）**，见下方缺陷① | ✅ |
| **M2** | `:171` `bottomNavigationBar: _loading ? null : …` → 恒 `null`；`:185` 把 `_buildStickyBottomBar(...)` 塞回 body 顶部（模拟"没吸底"） | viewport「初始完整可见 / 滚到底仍可见」 | 🔴 **3/3 全红**。viewport 红在 `premium_page_viewport_test.dart:192`：`Found 0 widgets with key [premiumMainButton]`（滚到底后底栏随列表滚出并被回收）；sticky 两例亦红（`bottomNavigationBar` 为 null） | ✅ |
| **M3** | `:490` 恢复按钮文案 `恢复购买` → `恢复` | `premium_page_test`「恢复购买」守卫 + `unlock_table` 源码守卫 | 🔴 **7 红**：sticky 结构守卫（`find.text('恢复购买')`）、`premium_page_test` 5 例（加载与价格、恢复三态 ×3、商店不可用）、`unlock_table`「T9 渲染守卫：恢复购买入口存在」。<br>⚠️ `premium_page_test:397` 的**源码字符串守卫未红**（文件注释与说明卡里仍含「恢复购买」四个字），见缺陷③ | ✅ |
| **M4** | `:236` 底栏 `Column` 外套 `SizedBox(height: 96)`（= 写死高度，违反"禁写死高度"纪律） | 1.3× 缩放假设用例 / overflow 断言 | 🟢 **3 例全绿 —— 逃逸**。原因：实测内容高 88pt（主按钮 48 + 6 + 恢复 34），写死 96 ≥ 88 既不溢出、`h2 >= h1` 两边同时被抬高也恒成立。见缺陷② | ✅ |
| **M4b** | 同上但 `height: 60`（**小于**内容） | overflow 断言 | 🔴 **3/3 全红** → 证明溢出断言本身有牙，盲区只在"写死高度 ≥ 内容" | ✅ |

### 缺陷①（QA 测试缺口 — **✅ 已修：补丁 A**）
**现象**：`premium_sticky_cta_test` 的结构守卫在 M1 下**全绿**，而其 `reason` 明确写着"防「挪进底栏但没从列表删」造成重复 Key"——名不副实。
**根因**：`ListView(children:)` 懒构建。M1 注入的那份在 400×800 下位于视口下方且超出 `cacheExtent`，**从未被 build**，`find.byKey` 自然找不到 → `findsOneWidget` 通过。同理「不在 ListView 子树内」的 `findsNothing` 也形同虚设。（同一变异在默认 800×600 视口下反而被抓到：宽度更大→内容更矮→尾部落在 cacheExtent 内被构建，故 `premium_page_test` 变红——**结论依视口而定，这是不可接受的脆弱性**。）
**已验证补丁**（在副本里实测：加后 M1 → 红）：在 `_pumpUntilLoaded` 之后、② 断言之前插入滚到底循环：
```dart
for (int i = 0; i < 20; i++) {
  final double before = tester
      .state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
  await tester.drag(find.byType(ListView), const Offset(0, -300));
  await tester.pump(const Duration(milliseconds: 30));
  final double after = tester
      .state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
  if ((after - before).abs() < 0.5) break;
}
```
实测：干净代码 2/2 绿；M1 下结构守卫 **变红**（`Found 2 widgets`）。

### 缺陷②（QA 测试缺口 — **✅ 已修：补丁 B**）
**现象**：写死高度（96pt ≥ 内容 88pt）逃过 `premium_sticky_cta_test` 全部断言，也逃过 viewport。
**根因**：`h2 >= h1` 是**相对比较**，写死高度会把基准 1.0× 一起抬高（109 → 117），两边相等故恒真；且 `takeException` 只在内容超出写死值时才有溢出。
**已验证补丁**（副本实测：干净绿 / 96 红 / 60 红），加一条**内容撑开不变量**（比 `mainAxisSize == min` 强得多，后者只是"声明"，前者是"实测结果"）：
```dart
final double colH = tester.getSize(colFinder).height;
final double mainH = tester.getSize(find.byKey(kPremiumMainButtonKey)).height;
final double restoreH = tester.getSize(find.byKey(kPremiumRestoreButtonKey)).height;
expect(colH, closeTo(mainH + 6 + restoreH, 0.5),
    reason: '底栏高度必须由内容撑开（写死高度会破坏该等式）');
```
实测数据：`column=88.0 main=48.0 restore=34.0` → 等式成立；`SizedBox(height:96)` → `column=96 ≠ 88` 红；`height:60` → 亦红。

### 缺陷③（既存测试弱点，非 C83 引入 — **保留为已知局限**）
`premium_page_test.dart:397`「源码守卫：购买页必须含「恢复购买」入口文案」用 `src.contains('恢复购买')` 断言 —— M3 把**按钮文案**改成「恢复」后该用例**仍绿**，因为同文件注释（`:480`）与说明卡正文（`:506`"点「恢复购买」即可找回"）都含这四个字。**结论：源码字符串守卫对文案变异无鉴别力**。
**按主理人裁定保留不动**：该弱点已由 **`find.text('恢复购买') findsOneWidget` 的行为断言兜底**（`premium_sticky_cta_test:243` 区段、`premium_page_test:202`、`premium_unlock_table_test:553`），M3 变异下这些行为断言全部变红，故 Apple 审核风险实质已被覆盖。

---

## 四、边界视口表（真实视口 / dpr=1，探针在副本内运行，跑完已删除）

| 视口 | 底栏高 | body 高（AppBar 56 之后） | 底栏矩形 | 主按钮完整可见 | 底栏不越界 | 「购买前请知悉」可达 | `takeException` |
|---|---|---|---|---|---|---|---|
| 400×800 | **109.0** | 635.0 | `(0,691)-(400,800)` | ✅ 702→750 | ✅ | ✅ | **0** |
| 375×667 | **109.0** | 502.0 | `(0,558)-(375,667)` | ✅ | ✅ | ✅ | **0** |
| 320×568 | **109.0** | 403.0 | `(0,459)-(320,568)` | ✅ | ✅ | ✅ | **1（既存缺陷，非 C83）** |

- **底栏高 109pt 三档恒定**（`1 border + 10 + 48 + 6 + 34 + 10`），与工程师自报「109pt」以及「主按钮 702→750、恢复 756→790、AppBar 底 56」**逐项吻合**（我独立量得：主按钮高 48.0、恢复高 34.0、Column 高 88.0、bar 顶 691）。
- **320×568 的唯一异常是既存缺陷**：`A RenderFlex overflowed by 18 pixels on the right.`，`The relevant error-causing widget was: Row: parent_premium_page.dart:309:21` —— 即**英雄卡内「未解锁/已解锁」胶囊 + 「一次买断 · 永久」金胶囊那一行**：320pt 宽时该 `Expanded` 内可用宽仅 **177pt**，两胶囊需 **195pt** → 右溢 18px，**首帧（未滚动）即出现**。
- **归属判定（关键）**：把副本里的生产文件换回 `git show HEAD:` 的 C83 前版本再跑同一诊断 → **同样 18px 右溢**，故**确认与 C83 无关**（该 Row 及其父布局 C83 一行未动）。建议（另开工单）：`:309` 的 `Row` 改 `Wrap(spacing: 8, runSpacing: 6)`，或把第二个胶囊包 `Flexible`。影响面：SE1 级 320pt 小屏（iPhone 5s/SE1 及部分安卓）。

---

## 五、未回归核查（5 条逐条）

1. **`PremiumUnlockTable` 与 5 枚权益徽标未被改动 —— 成立。** `git status` 显示 `lib/presentation/parent/widgets/` 零改动；`unlockRowsFor()` 仍构造 5 行（`premium_gate.dart:337/345/355/363/373`：一键操作 / 花盆上限 / 成长项模板 / 奖励模板 / 称号属性）；`_buildPreviewBadges` 仍以 `emojis`（5 枚）× `rows`（5 行）双上限取 5 枚；现有守卫 `premium_unlock_table_test:268/393/401`（`rows.length == 5` + emojis 5 枚）全绿。
2. **价格仍只来自商店 —— 成立。** 生产文件中价格唯一来源为 `_product?.price`（`:399`、`:406`），全文件无任何硬编码金额/`$` 字面量（grep 仅命中文档注释）；`立即解锁 · HK$88.00` 用例（价格串来自假商店）绿。
3. **`git diff` 逐块复核：无与吸底无关的逻辑改动 —— 成立（5 块，全部与吸底相关）。** ① `build()` 抽 `final ThemeData theme` + 加 `bottomNavigationBar` 槽位；② `_buildBody` 的 `padding` 底 32→16 且从列表移除两个按钮；③ 新增 `_buildStickyBottomBar`；④ `_buildMainButton` 仅加文档注释（返回树/Key 未动）；⑤ `_buildRestoreButton` 由 `OutlinedButton.icon` 改 `TextButton.icon`。
   **可疑行（如实列出，非 Bug）**：
   - `:496 tapTargetSize: MaterialTapTargetSize.shrinkWrap` + `:495 minimumSize: Size(0, 34)` → 恢复入口**点击热区仅 34pt**，低于 Apple HIG 建议的 44×44pt（该按钮正是 Apple 审核关注项，建议至少 44 或改用 `MaterialTapTargetSize.padded` 保留外扩热区）。
   - `:494 foregroundColor: _kInkSoft`（`#9C917E`）配 13pt 小字 → 对近白底 `colorScheme.surface` 的对比度约 **3.1:1**，低于 WCAG AA 正文 4.5:1（原 `OutlinedButton` 默认字号更大且带描边，弱化程度没这么高）。
   - `:184` 列表底部留白 32→16 合理（底栏不再覆盖 body，`body.bottom == bar.top`，已由边界探针断言 `barH + bodyH <= 视口高`）。
   - `:195` 注释「权益预览 **4** 徽标」与实际 5 枚不符 —— **既存陈旧注释**（diff 未触碰该行），建议顺手改为 5。
4. **状态机 `_loading/_storeUnavailable/_buying/_restoring` 未被改动 —— 成立。** diff 中 `_loadProduct` / `_buy` / `_restore` / `_snack` **零改动**；`_loading` 仅被 `build()` 读取用于决定槽位是否为 null（加载中不渲染底栏，避免闪「暂不可购买」—— 该行为已由 sticky 结构守卫第①段实测验证：加载中 `bottomNavigationBar == null` 且两 Key 均 `findsNothing`）。
5. **两态 Key 运行期唯一 —— 成立。** 源码 `kPremiumMainButtonKey` 确有 **2 处 `key:`**（`:391` 已解锁态 / `:410` 未解锁态，互斥分支），`kPremiumRestoreButtonKey` 1 处（`:486`）。运行期实测：**未解锁态** `findsOneWidget` + 文案「立即解锁 · HK$88.00」+ `onPressed != null`；**已解锁态** `findsOneWidget` + 「已解锁 · 感谢支持」+ `onPressed == null` + 恢复入口仍存在。两态各 1 实例 → "源码 2 处"是互斥分支，合法。

---

## 六、遗留风险与建议（按优先级）

| # | 级别 | 内容 | 建议动作 | 归属 |
|---|---|---|---|---|
| 1 | ~~中~~ 已修 | **缺陷①**：sticky 结构守卫因 ListView 懒构建，对"列表尾部重复 Key"无感（M1 下全绿），与其 `reason` 承诺不符 | **补丁 A 已写入**（`test/qa/premium_sticky_cta_test.dart:227` 前置 `_scrollToBottom`）；M1 复跑已咬红 | ✅ 已修 |
| 2 | ~~中~~ 已修 | **缺陷②**：写死高度 ≥ 内容（96pt）逃过全部断言 | **补丁 B 已写入**（`:178 _expectContentDrivenBar`，调用点 `:314` / `:329`）；96pt 复跑已咬红 | ✅ 已修 |
| 3 | 中 | **既存缺陷（非 C83）**：320pt 宽英雄卡胶囊 `Row` 右溢 18px（`:309`），首帧即现 | `Row` → `Wrap`，或金胶囊包 `Flexible`；补 320×568 视口回归 | 工程师（另开工单） |
| 4 | 低 | **既存弱点**：`premium_page_test:397` 源码字符串守卫对文案变异无鉴别力（缺陷③） | 改精确 `RegExp` 匹配按钮文案行 | QA（后续） |
| 5 | 低 | 可及性：恢复按钮热区 34pt < 44pt；`_kInkSoft` 13pt 对比度 ≈3.1:1 | 热区 ≥44（或 `padded`）；文字色加深至 ≥4.5:1 | 工程师（可与 C83 合并修） |
| 6 | 提示 | `:195` 注释仍写「4 徽标」（实际 5 枚，C80 起） | 顺手改 5 | 工程师 |

> 关于「吸底」断言强度的一点提醒：viewport 用例里**「初始完整可见」单独不足以证明吸底** —— M2（底栏塞回 body 顶部）时该断言仍绿，真正起效的是「滚到底仍可见 + 全局 y 差 < 1.0pt」（M2 红在 `:192`）。当前两者并存，强度足够，**请勿删后者**。

---

## 七、隔离合规自证

- 变异全部在 `/tmp/qa_c83/` 内进行；副本与共享树 `diff -r lib/ test/` **无差异**（探针文件已删）。
- 共享树 `git status --porcelain` 全程仅工程师的 3 项：`M parent_premium_page.dart` / `M premium_page_viewport_test.dart` / `?? premium_sticky_cta_test.dart`；`HEAD` 仍为 `c72bde1`。
- 未执行任何 git 写命令（仅 `git show HEAD:` 读旧版做基线比对）。

---

## 八、补丁复验（指令 §9 · 补丁 A / B，已写入共享 `test/`）

> 授权范围：**仅** `test/qa/premium_sticky_cta_test.dart`；生产代码 `lib/` 仍全程只读（`shasum` 与变异前一致：`3f9f25df…3586`）。
> 文件：264 → **338 行**，用例数 **仍为 2**（只增断言，不增用例）→ 全量 passed 数不变。

### 8.1 改动行

| 补丁 | 位置（`test/qa/premium_sticky_cta_test.dart`） | 内容 |
|---|---|---|
| **A** | `:150-169` 新增 `_scrollToBottom(tester)` 辅助；**`:227-238`** 在「② 两 Key 各唯一」断言**之前**调用 | 触底即停（最多 20 次拖拽，位移 < 0.5pt 判定触底）；并新增断言「滚到底过程中零异常」+「`scrolledOffset > 0`」（证明补丁本身有检验力，不是空转） |
| **B** | `:172-201` 新增 `_expectContentDrivenBar(tester, scale:)`；调用点 **`:314`（1.0×）/ `:329`（1.3×）** | 断言底栏内唯一 `Column` 高度 **== 主按钮高 + 6 + 恢复按钮高**，`closeTo(..., 0.5)` |
| 附 | `:14-22` 文件头文档 | 记录两处曾实测漏检的加固动机 |

### 8.2 三次变异复跑（补丁后在 `/tmp/qa_c83` 内复跑，改法与本报告 §三 完全相同）

| 变异 | 干净态（对照） | 补丁后实测 | 红在哪条断言 |
|---|---|---|---|
| **M1**（列表内再插一份主按钮） | 2/2 🟢 | **红 1 例**（结构守卫） | `:243` `expect(find.byKey(kPremiumMainButtonKey), findsOneWidget)` → `Found 2 widgets with key [<'premiumMainButton'>]`（**补丁前此变异在本文件全绿**） |
| **M4**（底栏 `SizedBox(height: 96)`） | 2/2 🟢 | **红 1 例**（缩放纪律） | `_expectContentDrivenBar:191`：`Expected: within <0.5> of <88.0>`，`Actual: <96.0>`（调用自 `:314`，1.0× 基准；**补丁前 3 例全绿＝逃逸**） |
| **M4b**（`SizedBox(height: 60)`） | 2/2 🟢 | **红 2 例**（结构守卫 + 缩放纪律） | ① `:231` `takeException() isNull` → `A RenderFlex overflowed by 28 pixels on the bottom.`；② `:191` 不变量 `60.0 ≠ 88.0` |
| 干净态终验 | — | **3/3 🟢**（sticky 2 + viewport 1） | — |

### 8.3 共享树最终数字（补丁写入后重跑）

| 项 | 结果 |
|---|---|
| `flutter analyze` | **0 error / 0 warning / 103 info**（与补丁前完全一致，未引入新 lint） |
| 全量 `flutter test --no-pub --reporter json` | **1443 passed / 0 failed / 0 error**（EXIT=0；用例数不变，因补丁只加断言） |

### 8.4 最终改动清单

`git status --porcelain`（补丁完成后实测）：

```
 M docs/bug记录表.md                      ← 主理人台账（F121 等），非 QA 所写
 M docs/口径裁定表_v1.md                   ← 主理人台账（C83 裁定），非 QA 所写
 M docs/项目进度跟踪表.md                   ← 主理人台账，非 QA 所写
 M lib/presentation/parent/pages/parent_premium_page.dart   ← 工程师
 M test/qa/premium_page_viewport_test.dart                  ← 工程师
?? test/qa/premium_sticky_cta_test.dart                      ← 工程师新建（本次含补丁 A/B）
?? docs/QA独立验收报告_C83_v1.md                              ← 本报告（QA）
```

**归属说明（重要）**：上面 3 个 `docs/*.md` 的 `M` **不是 QA 的改动** —— 其 mtime 为 `09:51:11 / 09:51:27 / 09:51:53`，出现在 QA 执行全量测试期间（QA 最后一次「仅 3 项」的状态快照在 09:47 之前），且 diff 全为**纯新增行**（`+1 / +24 / +30`），内容为主理人维护的台账（F121 既存缺陷记录、C83 口径裁定、进度跟踪）。QA 只写了 `docs/QA独立验收报告_C83_v1.md` 这 1 个 `??` 文件。

`HEAD` 仍为 `c72bde1`；**全程无任何 git 写操作**（commit / push / reset / checkout 均未执行）。
**路由维持 `NoOne`。**

---

## 九、后续（C84，2026-10-17，玄参「都改」拍板后补记）

本报告 §五.3 的两条可及性建议中，**①恢复入口热区 34pt < 44pt 已落地（C84）**：`minimumSize: Size(0, 44)` + 横向 `padding` 8→16（保留 `tapTargetSize: shrinkWrap`，否则 Material 再垫到 48pt，会破坏 §三 补丁 B 的「Column 高 = 内容之和」不变量）。**②`_kInkSoft` 13pt 对比度 ≈3.1:1 仍未改**，留待玄参裁定。

§五.1 的 **F121（320×568 英雄卡 18px 横向溢出，既存缺陷）已在 C84 修掉**：英雄卡两胶囊 `Row` → `Wrap(spacing: 8, runSpacing: 6)`。新增行为级回归 `test/qa/premium_a11y_narrow_test.dart`（4 条，含 320×568 / 375×667 / 320×568@1.3×）。变异取证：`Wrap`→`Row` 后 320×568 在 1.0× 与 1.3× **双红**。

**C84 验收数字**：`flutter analyze` **103 info / 0 error / 0 warning**（= 基线）；全量 **1447 passed / 0 failed**（C83 的 1443 + 新增 4）。
