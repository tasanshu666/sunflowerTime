# iOS 支付宝解锁 · 合规评估 v1

> **性质**：单独立项的合规评估，**只调研、不改任何代码、不 commit / push**。
> **触发**：玄参拍板「iOS 是否同步支持支付宝解锁」= 要同步评估，但明确「不在本批代码范围内」。
> **查阅日期**：本文所有联网结论均于 **2026-11-28** 查阅；每条结论后附一手来源 URL。转述类资料只作旁证，凡与 Apple 原文冲突以原文为准。
> **既有硬约束**：`docs/官网自动解锁_技术方案_v1.md` §10.3「iOS 包零 AlipaySDK」（`otool -L` 零命中、`grep -r alipay ios/` 零命中）——玄参**目前未接受**解除该约束，本文任何结论均不得破坏它。

---

## 0. 一句话结论

**不建议在海外 iOS 版做「App 内支付宝解锁（激活码）」。** 数字解锁 + 激活码正好命中 App Review Guidelines 3.1.1 明文禁止的「license keys」自用解锁机制；美国区 2025-05-01 起的外链自由只放宽了「引导去网页买」，**既没有取消 IAP 强制，也没有允许在 App 内用支付宝 SDK 解锁数字权益**；中国大陆区不在任何外链 entitlement 适用地区内。当前双轨结构（海外 iOS StoreKit IAP + 国内 Android 官网直供）已是风险最低解。

**推荐路径**：维持现状（路径①）；把 iOS 支付宝彻底转为「需求冻结 + 触发式重评」，重评条件见 §6.2。

---

## 1. 调研来源清单（全部 2026-11-28 查阅）

| # | 来源 | URL | 性质 |
|---|---|---|---|
| S1 | Apple《App Review Guidelines》现行版（Last Updated 2026-10-16） | https://developer.apple.com/app-store/review/guidelines/ | **官方原文** |
| S2 | Apple Developer News《Updated guidelines now available》（2025-05-01，Epic 判决后修订 3.1.1 / 3.1.1(a) / 3.1.3 / 3.1.3(a)） | https://developer.apple.com/news/?id=9txfddzf | **官方原文** |
| S3 | Apple Developer News《Updated App Review Guidelines are now available》（2026-10-16） | https://developer.apple.com/news?id=92th7e5i | **官方原文** |
| S4 | Apple Developer Documentation《StoreKit external purchase》（地区 entitlement 清单、iOS 版本门槛） | https://developer.apple.com/documentation/storekit/external_purchase | **官方原文** |
| S5 | Apple Support《Offering account deletion in your app》（5.1.1(v) 细则） | https://developer.apple.com/support/offering-account-deletion-in-your-app/ | **官方原文** |
| S6 | Apple Developer News《Updated App Review Guidelines now available》（2024，3.1.3(b) 补链 3.1.1(a)） | https://developer.apple.com/news/?id=flmb6ri3 | **官方原文** |
| S7 | Apple Developer Forums：3.1.1(v) 拒审通知原文引用 | https://developer.apple.com/forums/thread/765160 | 官方论坛 |
| S8 | 支付宝开放平台《APP 支付产品介绍》 | https://docs.open.alipay.com/204/105051 | 官方（支付宝侧） |
| S9 | 苹果审核第三方案例汇编（二进制残留 AlipaySDK 被判 3.1.1） | https://blog.csdn.net/lihao_ios/article/details/162293122 | 旁证，非官方 |
| S10 | 第三方 2026 外链政策汇总（地区、佣金、法院进展） | https://newly.app/how-to/app-store-external-purchase-link ；https://www.appstemple.com/guides/apple-external-payment-links-2026 | 旁证，非官方 |
| S11 | 第三方指南版本时间线（v13 2025-05-02、v22 2026-10-17） | https://appstoreguidelines.com/app-review-guidelines/version/18 | 旁证，非官方 |
| S12 | 中国区审核案例汇编（虚拟商品走微信/支付宝被判 3.1.1） | https://ask.dcloud.net.cn/article/id-42577 ；https://m.sng.cn/sc/app/762142.html | 旁证，非官方 |

> **证据等级约定**：S1–S6 为 A 级（Apple 官方原文）；S7 为 B 级；S9–S12 为 C 级（行业经验，仅用于说明审核实践，不作为唯一依据）。

---

## 2. 条款原文摘录与解读（A 级来源 S1，2026-11-28 查阅）

### 2.1 🔴 3.1.1 In-App Purchase —— 本项目的决定性条款

原文（逐字）：

> "If you want to unlock features or functionality within your app, (by way of example: subscriptions, in-game currencies, game levels, access to premium content, or unlocking a full version), you must use in-app purchase. **Apps may not use their own mechanisms to unlock content or functionality, such as license keys, augmented reality markers, QR codes, cryptocurrencies and cryptocurrency wallets, etc.**"

解读（对本项目致命）：

- 本产品 iOS 的 premium 解锁 = "unlocking a full version" / "access to premium content"，**必须走 IAP**。
- 现成的 Android 解锁机制是「92 字符激活码 → Ed25519 离线验签 → 写票据解锁」。这在 3.1.1 原文里被**点名列为禁止项：license keys**。
- 因此**哪怕用户是在网页/官网真金白银买了码**，只要 iOS App 内提供「输码解锁」这个动作，就是"use their own mechanisms to unlock content or functionality, such as license keys"——这条不因外链政策放宽而改变。
- 另一个细节：3.1.1 还规定 "Digital gift cards, certificates, vouchers, and coupons which can be redeemed for digital goods or services can only be sold in your app using in-app purchase." 数字兑换券在 App 内销售也受 IAP 约束。

### 2.2 3.1.1(a) Link to Other Purchase Methods（2025-05-01 修订后）

原文（逐字，节选）：

> "Developers may apply for entitlements to provide a link in their app to a permitted destination in order to purchase digital content or services. **These entitlements are not required for developers to include buttons, external links, or other calls to action in their United States storefront apps.**"
>
> "…In all other storefronts, **except for the United States storefront, where this prohibition does not apply**, apps and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase."

解读：

- **仅美国店面**免除 entitlement 要求；其余店面（含中国大陆）默认禁止 App 内放「去别处买」的按钮/链接/行动号召。
- 2025-05-01 Apple 官方公告（S2）明确「changes affect apps distributed on the **United States storefront**」，修订了 3.1.1 / 3.1.1(a) / 3.1.3 / 3.1.3(a)。
- 2026-10-16 修订（S3）把 Music Streaming Services Entitlement 并入 StoreKit External Purchase Link Entitlement，并澄清「links may be provided to a permitted destination」——**目的地必须是被许可的站点**，不是任意第三方支付页。
- 🔴 **关键边界**：3.1.1(a) 放宽的是「**引导用户去外部网页买**」，**不是**「在 App 内嵌支付宝 SDK 唤起收银台」。App 内支付宝唤起属于 3.1.1 禁止的"own mechanisms"，不因 3.1.1(a) 豁免。
- 🔴 美国区即使可以外链，**3.1.1 主句仍要求解锁走 IAP**，所以主流合规做法是「IAP 与外链并存」，不是「只留外链」。

### 2.3 3.1.3 Other Purchase Methods 及其 (a)(b)(e)

原文（逐字，节选）：

> "The following apps may use purchase methods other than in-app purchase. **Apps in this section cannot, within the app, encourage users to use a purchasing method other than in-app purchase, except for apps on the United States storefront and as set forth in 3.1.1(a) and 3.1.3(a).** Developers can send communications outside of the app to their user base about purchasing methods other than in-app purchase."
>
> **3.1.3(b) Multiplatform Services:** "Apps that operate across multiple platforms may allow users to access content, subscriptions, or features they have acquired in your app on other platforms or your web site, including consumable items in multi-platform games, **provided those items are also available as in-app purchases within the app**."
>
> **3.1.3(e) Goods and Services Outside of the App:** "If your app enables people to purchase physical goods or services that will be consumed outside of the app, you must use purchase methods other than in-app purchase to collect those payments, such as Apple Pay or traditional credit card entry."
>
> **3.1.3(a) "Reader" Apps:** 仅限 magazines / newspapers / books / audio / music / video 的已购内容访问。

解读：

- 本产品是**数字解锁**（premium 功能），不是实物/线下服务，3.1.3(e) 不适用。
- 本产品不是 reader app（非书刊音视频），3.1.3(a) 不适用。
- 3.1.3(b) 是**唯一可能相关**的通道，但有两个前提：① 用户"已在其他平台或网站取得"权益；② **同一权益必须在 App 内也以 IAP 形式提供**。本产品 iOS 已有 IAP（满足②），但项目无账号体系、无跨端权益同步（不满足①的工程前提）。
- S6（Apple 官方 2024 公告）补了一句：3.1.3(b) 应用也可使用 3.1.1(a) 的 entitlement——即外链能力可叠加，但仍不解除 3.1.1 的解锁方式限制。
- 注意「App 内不能鼓励用户用非 IAP 方式付款」这条对**所有店面的 App 内文案**都成立（除美国店面的 3.1.1(a) 情形）。

### 2.4 2.3 Accurate Metadata（S1，2026-11-28 查阅）

原文要点：

> "2.3.1(a) All new features, functionality, and product changes must be described with specificity in the Notes for Review section of App Store Connect (generic descriptions will be rejected) and accessible for review."
>
> "2.3.2 If your app includes in-app purchases, make sure your app description, screenshots, and previews clearly indicate whether any featured items… require additional purchases."

解读：若 iOS 增加支付宝入口，必须在 Review Notes 中**逐屏描述支付流程**并提供可测账号；`2.3.1(a)` 明确「藏起来不描述」会被拒。这也堵死了「审核时关闭、过审后打开」的灰色做法（S12 旁证同样指出）。

### 2.5 5.1.1(v) Account Sign-In / 账号删除（S1 + S5，2026-11-28 查阅）

原文（Apple 支持页 S5 引用指南 5.1.1(v)）：

> "If your app supports account creation, you must also offer account deletion within the app."

解读：

- 本产品是**无账号、离线优先**（Plan B 无账号单机版），当前不触发 5.1.1(v)。
- 但如果为了走 3.1.3(b)「跨平台权益同步」而**引入账号系统**，则必须同步实现 App 内账号删除、隐私政策更新、数据清理链路——这是采取路径⑤的隐藏成本，必须计入。

### 2.6 关于任务书提到的 3.1.7

**现行《App Review Guidelines》（2026-10-16 版，S1）中不存在 3.1.7 条款。** 历史上对应「Multiplatform Services」的条目现为 **3.1.3(b)**（本文 §2.3 已按现行原文引用）。以旧编号引用会在评审中造成口径混乱，本评估统一按现行编号。**3.1.3(b) 的实质内容如上，结论不变。**

### 2.7 2025–2026 修订时间线（S2 / S3 / S11，2026-11-28 查阅）

| 日期 | 事件 | 对本项目影响 |
|---|---|---|
| 2025-05-01 | Epic v. Apple 藐视法庭裁定后，Apple 修订 3.1.1 / 3.1.1(a) / 3.1.3 / 3.1.3(a)（S2） | 美国店面可外链且无需 entitlement；**中国区无变化** |
| 2025-12 | 第九巡回上诉法院维持藐视法庭认定，但认为 Apple 可收取「合理成本」费用（S10 旁证） | 外链是否免费仍未定，成本模型不稳 |
| 2026-06-30 | 最高法院同意受理 Apple v. Epic（No. 25-1311），开庭排在 2027-01-11（S10 旁证） | 2027 年前政策仍有变数，不宜此时押注 |
| 2026-10-16 | 指南最新版：新增 2.3.14、2.5.19，3.1.1(a) 并入音乐流媒体 entitlement（S3） | 外链口径进一步明确，但 3.1.1 主句未变 |

---

## 3. 中国区 vs 海外区差异

### 3.1 中国大陆区

- **外链 entitlement 不适用**：Apple 官方 StoreKit external purchase 文档（S4，2026-11-28 查阅）列出的适用地区为 EU / EEA / Russia / South Korea / Japan / Brazil 等，**没有中国大陆**。美国区豁免明确只写"United States storefront"（S2）。
- **3.1.1 完整适用**：数字解锁必须 IAP；license keys 明确禁止。
- **是否有真实过审案例**：在 A 级来源中**未找到任何官方口径表示「中国区 iOS 可用支付宝解锁数字权益且过审」**；相反，S12（C 级，2026-11-28 查阅）汇总了多起「教育/内容类 App 用微信/支付宝解锁会员被判 3.1.1 驳回」的案例；S9（C 级）指出更严格的情形——**IPA 包里残留 AlipaySDK 文件/目录即使未调用也会被静态扫描判 3.1.1**。
- **结论**：中国区 iOS 做支付宝数字解锁，合规风险 **高**，且没有可引用的官方许可路径。注意这与「国内 Android 官网直供」不矛盾——Apple 规则只管 iOS 分发渠道，Android APK 走官网分发不受 3.1.1 约束。

### 3.2 海外区（本产品主战场：美国区 App Store，$6.99）

- 美国区可**无 entitlement** 放置外链按钮（S1 / S2），可告知用户外部价格更低；但：
  1. 3.1.1 主句仍要求数字解锁走 IAP；
  2. 外链目的地必须是"permitted destination"（通常自有网站），不是任意支付页；
  3. 主流合规形态是 IAP + 外链**并存**，而非替代（S10，C 级）。
- 若目标还包含 EU / JP / BR / KR，需各区 entitlement、不同 iOS 最低版本、不同佣金规则（S4），工程与法务成本显著上升；其中巴西要求「每个数字商品陈列页必须把 IAP 与替代支付同等显著并列」（S10，C 级）。
- 外链佣金仍处诉讼中（S10），2027 年前成本不可预测。

### 3.3 对本产品结构的综合判断

| 结构 | 受 3.1.1 约束？ | 现状 |
|---|---|---|
| 海外 iOS（App Store） | ✅ 是 | 已走 StoreKit IAP，1.1.0 已上架，**零风险** |
| 国内 Android（官网直供 APK） | ❌ 否（不经 App Store） | 官网付款 + 激活码离线验签，本批正在做 |
| 提议中的 iOS 支付宝 | ✅ 是 | 同时踩「license keys」与「own payment mechanism」两条 |

---

## 4. 可行路径对比

| 路径 | 做法 | 合规风险 | 是否需改隐私政策第三方清单 | 对用户影响 | 实施成本 | §10.3 红线 |
|---|---|---|---|---|---|---|
| **① 保持现状（推荐）** | iOS 只走 StoreKit IAP；支付宝只在 Android 官网直供 | **低** | 否 | 无变化；iOS 用户仍用 Apple ID 付款、可恢复购买 | 0 | ✅ 不破坏 |
| **② 支付宝仅用于实物/服务** | 把 premium 包装成"实物/线下服务" | **不适用 / 实质高** | — | — | — | — |
| | 说明：本 App 卖的是**数字功能解锁**（3.1.1 明确列举 "unlocking a full version"），3.1.3(e) 的实物/服务例外**不成立**。强行包装属于误导性元数据（2.3.1(a)）。 | | | | | |
| **③ 中国区单独提交含支付宝的 iOS 包** | 用一个专门的 CN storefront 包，内嵌支付宝 SDK + 激活码入口 | **高** | 是（且需第三方 SDK 数据采集披露） | 中国区 iOS 用户可支付宝付款；但无官方许可案例，随时被下架 | 高（双包维护 + 审核拉锯） | ❌ **直接破坏**（iOS 包链入 AlipaySDK） |
| **④ 外部网页购买（App 内引导去官网付款）** | iOS 内保留 IAP，另加「去官网购买（可能更便宜）」按钮，网页收支付宝，回来后用码解锁 | **美国区：中**；**中国区/其他区：高** | 美国区若仅跳转浏览器、无 SDK：**通常不需要**；若加 SDK 则需要 | 需要账号/码回填，流程变长；退款与客服改为开发者承担（S10） | 中高（地区门控 + Review Notes + 双支付并对账） | ⚠️ 纯外链可不破坏；**一旦为"回来解锁"加激活码输入框，就踩 3.1.1 license keys** |
| **⑤ 3.1.3(b) 多平台权益同步** | iOS 不新增支付方式；已有账号的用户在 Android/网页购买后，iOS 凭账号读取同一权益；IAP 仍在 App 内提供 | **中** | 是（引入账号 + 数据处理） | 用户需登录；换机/跨平台权益自动同步，体验最好 | **高**（引入账号体系、5.1.1(v) 账号删除、服务端权益库、跨端退款对账） | ✅ 可不破坏（无需 AlipaySDK） |

### 4.1 补充说明

- 路径④在**美国区**技术上是合法形态（S1/S2），但对本产品仍有两道坎：① 3.1.1 的 "license keys" 禁止——用户付完回来输码解锁仍属违规；② 产品定位是无账号离线单机，加账号/码回填与现有架构冲突。
- 路径⑤是唯一「不碰 AlipaySDK、且引用得到 Apple 明文章节」的路径，但它解决的是「**已在别处买过的用户能在 iOS 用**」，**不是**「在 iOS App 内用支付宝付款」。若玄参的真实需求是后者，⑤不满足。
- 路径③的额外硬伤：即使突破 §10.3，S9（C 级）显示 Apple 静态扫描会因**二进制残留**判 3.1.1——"不含支付宝代码但包里有空 AlipaySDK.bundle 也被拒"。这使「只在审核时隐藏入口」的常规规避手段失效。

---

## 5. 结论与建议

### 5.1 明确结论

**在当前「海外 iOS 已上架（1.1.0）+ 国内 Android 官网直供」的双轨结构下，不建议做 iOS 支付宝解锁。**

核心理由（三条，按权重）：

1. **规则硬伤**：3.1.1 原文同时禁止「own mechanisms to unlock」并点名「license keys」（S1）。本产品的解锁载体恰好是 92 字符激活码，机制层面直接冲突，不是文案修饰能绕过的。
2. **外链自由被误读**：美国区 2025-05-01 放宽的是「引导去外部网页购买」（S1/S2），**没有取消 IAP 强制，也没有允许 App 内嵌支付宝 SDK 收数字商品款**；中国大陆区根本不在任何外链 entitlement 地区清单内（S4）。
3. **既有红线未解除**：§10.3「iOS 包零 AlipaySDK」是玄参已生效的拍板，且 S9 表明连二进制残留都会触发拒审。为 Android 转化率污染已上架的海外 iOS，是净亏。

### 5.2 建议的最小动作（本批不做代码）

- **保持路径①**：iOS 分支、6 个 iOS 付费页守卫文件、`iap_service.dart`、`IapClient` 契约继续零改动。
- **把本评估冻结为需求档案**：在 `docs/` 留存本文，待 §6.2 触发条件出现时重评。
- **不做任何 iOS 侧预埋**：不加 AlipaySDK、不加 scheme、不加 URL Types、不加权限，避免 S9 所述「残留即拒审」。

### 5.3 与 §10.3 红线的关系（明确表态）

- 本文所有推荐路径均**不破坏** §10.3：`ios/` 零改动、`grep -r alipay ios/` 零命中、`otool -L Runner.app/Runner | grep -i alipay` 零命中。
- 路径③明确标为 ❌ 破坏红线；路径④仅当「纯外链 + 无 SDK + 无 App 内输码解锁」时才可能不破坏，而那对本产品不成立。
- **若玄参未来明确接受解除 §10.3**，仍需先解决 3.1.1 的 license keys 问题（引入账号 + 服务端权益同步，走路径⑤形态），而不是直接把 Android 支付宝代码搬到 iOS。

### 5.4 什么条件下才值得重评（触发式清单）

同时满足以下**至少 4 项**（其中 ①②为必需）才启动重评：

1. ① **玄参书面明确接受**解除 §10.3「iOS 包零 AlipaySDK」红线，或确认走「无 SDK 的纯外链 + 账号权益同步」路线。
2. ② **取得 Apple 官方书面口径**（App Review 或 entitlement 批准），确认拟采用的解锁形态不违反 3.1.1；或最高法院 / 第九巡回对 IAP 强制作出实质变更后重新评估（S10，2027-01 开庭后）。
3. ③ 产品**引入账号体系**并接受 5.1.1(v) 的账号删除义务与隐私政策改造，从而能用 3.1.3(b) 替代 license keys。
4. ④ 目标店面限定为美国区（或取得 EU/JP/BR/KR 对应 entitlement），并接受外链佣金不确定性。
5. ⑤ 中国区单独提交方案通过 Apple 预评审，且有可引用的过审先例。
6. ⑥ 商业测算显示 iOS 支付宝带来的增量收入 > 账号体系改造 + 双支付对账 + 审核风险的综合成本。

> 反之，只要 iOS 仍维持「无账号、离线优先、已上架」三要素，就不应重评。

---

## 6. 待玄参确认

| # | 问题 | 建议默认 |
|---|---|---|
| 1 | 「iOS 同步支持支付宝」的真实诉求是「**在 iOS App 内用支付宝付款**」还是「**已在 Android/网页买过的用户在 iOS 上能用**」？ | 若是后者，走路径⑤（账号权益同步），仍不做支付宝 SDK |
| 2 | 是否接受为 iOS 引入账号体系（5.1.1(v) 连带成本）？ | 不接受，维持无账号 |
| 3 | 是否接受在 2027-01 最高法院开庭后再看政策变化？ | 接受，届时重评 |
| 4 | 中国区 iOS 是否真的要单独上架？ | 不做，维持海外区单一 iOS 包 |

---

## 7. 来源逐条对应（查阅日期均为 2026-11-28）

| 结论 | 来源 URL |
|---|---|
| 3.1.1 IAP 强制 + license keys 禁止 | https://developer.apple.com/app-store/review/guidelines/ （S1） |
| 3.1.1(a) 美国店面外链免 entitlement | https://developer.apple.com/app-store/review/guidelines/ ；https://developer.apple.com/news/?id=9txfddzf （S1/S2） |
| 2026-10-16 指南修订内容 | https://developer.apple.com/news?id=92th7e5i （S3） |
| 外链 entitlement 地区清单（无中国大陆） | https://developer.apple.com/documentation/storekit/external_purchase （S4） |
| 5.1.1(v) 账号删除 | https://developer.apple.com/support/offering-account-deletion-in-your-app/ ；https://developer.apple.com/forums/thread/765160 （S5/S7） |
| 3.1.3(b) 多平台服务 + 与 3.1.1(a) 叠加 | https://developer.apple.com/app-store/review/guidelines/ ；https://developer.apple.com/news/?id=flmb6ri3 （S1/S6） |
| 3.1.3(e) 实物/服务例外 | https://developer.apple.com/app-store/review/guidelines/ （S1） |
| 2.3.1(a) Review Notes specificity | https://developer.apple.com/app-store/review/guidelines/ （S1） |
| 外链佣金诉讼 / 最高法院排期 | https://newly.app/how-to/app-store-external-purchase-link ；https://www.appstemple.com/guides/apple-external-payment-links-2026 （S10，C 级） |
| AlipaySDK 二进制残留触发 3.1.1 拒审 | https://blog.csdn.net/lihao_ios/article/details/162293122 （S9，C 级） |
| 中国区虚拟商品第三方支付拒审案例 | https://ask.dcloud.net.cn/article/id-42577 ；https://m.sng.cn/sc/app/762142.html （S12，C 级） |
| 指南版本时间线 | https://appstoreguidelines.com/app-review-guidelines/version/18 （S11，C 级） |

> **免责声明**：本文是工程侧合规风险研判，不构成法律意见。若最终决定推进路径③/④/⑤，应由法务/合规顾问出具正式意见并以 Apple 官方书面答复为准。
