# App Store 上架执行手册 v1（2026-10-28）

> 用途：**上架单一执行源**。逐项打勾推进，不依赖记忆与旧文档。
> 代码基线：`e2cc5ec`（= `origin/main`，含 F163/F164 布局修复 + F165 提示浮层 + F166 关于与反馈/锁定加盆格）· 版本 `1.0.0 (build 2105，**唯一可提审版本**)` · Bundle ID `com.sunflowertime.app` · Team `6NW722K2GN`（付费开发者计划已确认）。
> 状态图例：✅ 已就绪 ｜ ⬜ 待做 ｜ 🔒 需玄参亲手操作 ｜ ⚠️ 需玄参拍板

---

## 0. 一句话现状

**代码与工程侧已经就绪**（测试 3348 全绿、analyze 零 error/warning、图标无 alpha、隐私清单已入包、加密声明已加、双语显示名生效、麦克风用途说明已补、英文长文案挤压/溢出已修、家长端已提供开发者联系方式）。

**剩下的三件事都在你手上**：① Xcode 登录账号让发布证书自动生成 → ② App Store Connect 建档 + 建内购商品 → ③ 上传包并提审。

---

## 1. 已就绪清单（2026-10-28 实测证据）

| 项 | 值 | 证据 |
|---|---|---|
| 全量测试 | **3348 全绿** | `flutter test --no-pub` 实跑（2026-10-29，含 F165/F166） |
| 静态检查 | **77 info / 0 error / 0 warning** | `flutter analyze`，与历史基线持平 |
| Bundle ID | `com.sunflowertime.app`（Android/iOS 统一） | `project.pbxproj` |
| 版本号 | **`1.0.0 (2105)` 已归档并校验通过（唯一可提审版本）** · `~/Library/Developer/Xcode/Archives/2026-10-29/Runner-2105.xcarchive`（`MARKETING_VERSION 1.0` + `FLUTTER_BUILD_NUMBER` 由 `pubspec.yaml` 的 `version:` 推导） | `pubspec.yaml:4` + `project.pbxproj` 三处 `MARKETING_VERSION = 1.0` |
| 设备族 | `1,2`（iPhone + iPad） | `TARGETED_DEVICE_FAMILY` |
| 最低系统 | iOS 15.0 | `IPHONEOS_DEPLOYMENT_TARGET` / `Podfile` |
| App 图标 | 15 档齐全，**1024×1024 无 alpha** | `sips -g hasAlpha` = no |
| 双语显示名 | zh「小小葵番茄钟」/ en「Tiny Sunflower」 | `en.lproj` / `zh-Hans.lproj` 双 strings，构建后 `.app` 内已验证 |
| 隐私清单 | `PrivacyInfo.xcprivacy` 已入包（1136 B） | `Runner.app` 内实测存在 |
| 加密声明 | `ITSAppUsesNonExemptEncryption = false` | 构建后 Info.plist 内实测 |
| 麦克风用途说明 | `NSMicrophoneUsageDescription` 已加（中英双语），**本 App 从不录音、从不请求该权限** | 解 `ITMS-90683` 拒收，详见 §14 |
| 权限声明 | **零隐私用途描述**（无相机/相册/麦克风/定位） | `Info.plist` 全文 |
| CocoaPods | 已安装，`Podfile.lock` 存在 | `ios/Pods` |
| 内购商品 ID | `com.sunflowertime.app.premium.lifetime`（非消耗型） | `lib/core/constants/iap_product_ids.dart:14` |
| 价格 | **代码不硬编码**，一律读商店返回的本地化价格 | `parent_premium_page.dart:4` |
| 商店截图 | `docs/商店截图/` iphone / ipad11 / ipad13 三套 | 目录实测 |

### 本批（F158）新增的工程改动

1. `ios/Runner/PrivacyInfo.xcprivacy`（新建）—— 声明不追踪、不收集数据、UserDefaults 仅自用（CA92.1）
2. `ios/Runner.xcodeproj/project.pbxproj` —— **纯 4 行插入**注册进 Copy Bundle Resources
3. `ios/Runner/Info.plist` —— 加 `ITSAppUsesNonExemptEncryption = false`

> ⚠️ 踩坑记录：用 Ruby `xcodeproj` gem 自动加资源会**拆掉 F149 手工注册的 `InfoPlist.strings` 变体组**（中文名会失效成英文），已回滚改用手工插 4 行。**今后改 pbxproj 一律手工插入，禁止用 xcodeproj gem 重存。**

---

## 2. 🔒 待办 1：生成发布签名（约 5 分钟）

本机目前**只有 `Apple Development` 证书，没有 `Apple Distribution`，也没有 App Store 描述文件** —— 现在 archive 必然失败。

### 做法（推荐，全自动）

1. 打开 `open /Users/wangjunchao/WorkBuddy/sunflowerTime/ios/Runner.xcworkspace`
2. Xcode → 菜单 `Xcode` → `Settings` → `Accounts` → 确认 `1007681634@qq.com` 已在列表中且 Team 显示为**付费团队**（非 Personal Team）
3. 左侧选中 `Runner` 项目 → TARGETS `Runner` → `Signing & Capabilities`
4. 确认勾选 **Automatically manage signing**，Team 选对应团队
5. 此时 Xcode 会自动创建 `Apple Distribution` 证书与 App Store 描述文件

### 验证

```bash
security find-identity -v -p codesigning
# 期望出现：Apple Distribution: ... （而不只是 Apple Development）
```

> 若第 2 步显示 `Personal Team`，说明登录的是免费账号 → 必须换付费账号，否则无法上架。

---

## 3. 🔒 待办 2：App Store Connect 建档

### 3.1 先确认 App ID 是否已注册

`developer.apple.com` → Certificates, Identifiers & Profiles → Identifiers
- 若没有 `com.sunflowertime.app` → 新建 App ID（类型 App，无需任何 capability）
- 若已存在 → 跳过

> 本项目**不需要额外 capability**（无推送、无 Associated Domains、无 Sign in with Apple；Keychain 走默认 group）。

### 3.2 建 App（My Apps → + → New App）

| 字段 | 填什么 | 说明 |
|---|---|---|
| Platforms | iOS | |
| Name | **Tiny Sunflower** | 30 字符内；**已定名（2026-10-28 ASC 查重通过，原 Tiny Bloom 被占用）** |
| Primary Language | **English (U.S.)** | 首发美区；简中作为第二语言本地化后加 |
| Bundle ID | `com.sunflowertime.app` | 下拉选择 |
| SKU | `XIAOXIAOKUI-001` | 内部用，任意唯一串，不可改 |
| User Access | Full Access | |

### 3.3 App 信息（App Information 页）

| 字段 | 填什么 |
|---|---|
| 名称 | Tiny Sunflower（英文）/ 小小葵番茄钟（简体中文，在「可本地化信息」里加） |
| 副标题 | Kids Focus & Grow（英）/ 待定中文副标题 |
| 主分类 | **Education** |
| 次分类 | **Health & Fitness** |
| 内容版权声明 | 不包含第三方内容 → 不勾 |
| 年龄分级 | 见 §5 |
| 价格 | **免费下载**（收入来自内购） |
| App 隐私 | 见 §4 |
| 隐私政策 URL | `https://sunfocused.cn/privacy.html` / 英文 `https://sunfocused.cn/privacy-en.html` |
| 支持 URL | `https://sunfocused.cn`（必填） |

### 3.4 版本信息（Version Information）

| 字段 | 填什么 |
|---|---|
| 版本号 | `1.0.0` |
| 描述 | 见下方草稿，**需你定稿** |
| 关键词 | 见下方草稿，**需你定稿** |
| 技术支持 URL | `https://sunfocused.cn` |
| 版权 | `2026 小小葵` |
| 截图 | 见 §6 |

**描述草稿（英文，≤4000 字符）**

```
Tiny Sunflower is a calm focus timer that turns a child's focused minutes into a
growing garden.

Put the phone down, pick a task, and focus. Every minute you stay focused
earns sunlight. Spend sunlight on plants, watch them grow from seed to bloom,
and keep the garden alive with water and care.

BUILT FOR KIDS, CONTROLLED BY PARENTS
• Child side: a simple timer, a garden, and small daily goals — no feeds,
  no ads, no strangers.
• Parent side: protected by a PIN you set yourself. Approve rewards, set tasks,
  and review focus reports there.
• Anti-addiction: entertainment screens are locked after a daily limit while
  focus and growth stay open.

PRIVATE BY DESIGN
• Everything stays on this device. No account, no cloud, no tracking,
  no third-party analytics.
• We do not collect, upload, or sell any data.

ONE-TIME PURCHASE
• The core experience is free. An optional one-time purchase unlocks the full
  set of features — not a subscription, restore anytime on your other devices.
```

**关键词草稿（≤100 字符，逗号分隔，不加空格）**

```
focus timer,kids,pomodoro,ADHD,study,homework,habit,garden,timer,parental control
```

> ⚠️ 关键词禁堆砌竞品名；`pomodoro` 属通用词可用。

---

## 4. App 隐私标签（App Privacy）

**结论：Data Not Collected（不收集数据）**

| 提问 | 答案 |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |
| 追踪（Tracking） | **No** |

依据：纯本地单机，无登录、无服务器、无广告/分析 SDK；内购由 Apple 处理，不计入 App 收集。与隐私政策 §3 一致。

> Flutter 引擎与插件自带隐私清单已随包提交，`PrivacyInfo.xcprivacy` 已声明 UserDefaults 仅自用 —— 上传时不应再收到 `ITMS-91053`。

---

## 5. 年龄分级问卷

全部按「无」回答，预期结论 **4+**：

| 问卷项 | 答案 |
|---|---|
| 卡通/幻想暴力、写实暴力、血腥 | 无 |
| 性内容/裸露 | 无 |
| 粗俗幽默、脏话 | 无 |
| 恐怖/惊悚主题 | 无 |
| 酒精/烟草/毒品 | 无 |
| 赌博（含模拟赌博） | 无 |
| 医疗/健康信息 | 无 |
| 无限制网页访问 | 否 |
| 用户生成内容 / 社交互动 | 否 |
| 广告 | 否 |
| App 内购买 | **是**（有买断内购） |

### ⚠️ 需拍板：是否加入 Kids Category

| 选项 | 影响 |
|---|---|
| **不勾 Kids Category（建议）** | 分类放 Education + Health & Fitness，年龄 4+。审核负担小；内购已在家长 PIN 门后，符合 1.3 精神 |
| 勾 Kids Category | 必须满足 5.1.4 全套：无第三方分析、无外链跳转、内购必须在家长门后、无行为广告。当前实现**基本满足**，但今后每次改动都要复查，且审核更严 |

**建议：不勾。** 如你要争「儿童类」曝光位，再勾。

---

## 6. 截图

已有三套（`docs/商店截图/`）：iphone 15 张 / ipad13 16 张 / ipad11 14 张。

**必须补的两张**：C110 批改过「首启同意页」与「隐私政策页」，若那两页在截图集内 → **需重截**（需你操作，AI 不截图）。

App Store 要求：6.9"/6.5" iPhone 至少 1 组，13" iPad 至少 1 组（支持 iPad 时为强制）。三套已覆盖。

---

## 7. 🔒 待办 3：内购商品配置

路径：App Store Connect → 你的 App → 「App 内购买项目」→ +

| 字段 | 填什么 |
|---|---|
| 类型 | **非消耗型（Non-Consumable）** |
| 参考名称 | `Premium Lifetime`（内部用） |
| 产品 ID | **`com.sunflowertime.app.premium.lifetime`** ← 必须逐字一致，代码写死这个串 |
| 价格 | **US$14.99**（口径 C69 拍板价；代码读商店返回价，选完自动本地化 ¥/HK$ 等） |
| 显示名称（英） | `Tiny Sunflower Premium`（≤30 字符） |
| 显示名称（简中） | `小小葵番茄钟 · 完整版` |
| 描述（英） | `Unlock the full feature set. One-time purchase, not a subscription. Restorable on your other devices.` |
| 描述（简中） | `一次性解锁全部功能，非订阅，可在其他设备恢复。` |
| **Family Sharing** | 🔴 **必须关闭**（口径 C92-1，隐私政策已明示不启用） |
| 审核信息 | 截图可选；备注写清「家长 PIN 门内的买断入口」 |

> ⚠️ 商品 ID 若拼错，App 内购买页会拿不到商品 → 按钮降级不可点，审核会以 2.1 拒。

### 沙盒自测（建议在提审前做）

1. App Store Connect → Users and Access → Sandbox → Testers → 建一个沙盒账号（用非真实 Apple ID 邮箱）
2. 真机（iPad mini 4 或 iPhone）设置 → App Store → 沙盒账户 登录
3. 进 App → 家长天地（右上角）→ 设 PIN → 会员购买页 → 完成一次沙盒购买 → 确认解锁态生效、重装后可「恢复购买」

---

## 8. 审核备注（App Review Notes，直接复制）

```
No account or login is required. The app is fully offline; nothing is uploaded.

PARENT AREA ACCESS
The child-facing screen has a "Parent Hub" button at the TOP-RIGHT corner.
Tapping it asks for a parent PIN. On first entry the app lets you SET any PIN
(minimum 4 digits) — there is no preset PIN. Please set your own, e.g. 1234.

IN-APP PURCHASE
The only purchase is a one-time non-consumable ("Tiny Sunflower Premium",
product id com.sunflowertime.app.premium.lifetime). Its entry point lives
INSIDE the parent area, behind the PIN, so a child cannot reach it.
For review you can use a sandbox tester account.

WHAT THE APP DOES
A focus timer for children. Focused minutes earn an in-app currency
("sunlight"), which is spent on growing plants in a garden. All progress is
stored locally on the device.
```

---

## 9. ⚠️ 提审前需你拍板的 4 件事

| # | 事项 | 选项 |
|---|---|---|
| 1 | App 名称 | **已定名 `Tiny Sunflower`**（2026-10-28 ASC 查重通过，原 `Tiny Bloom` 被占用；不得再改） |
| 2 | 买断价格档 | **US$14.99 已拍板**（C69，2026-10-14；不做早鸟价，后续调价不影响老用户）。后台档位选 **Tier 14.99**，中国区建议 ¥99（C69 记录）。~~4.99 是我手误写错，已作废~~ |
| 3 | 是否加入 Kids Category | 建议不勾（见 §5） |
| 4 | 商店描述 / 关键词是否采用上面草稿 | 需你逐句定稿，尤其「无广告、无陌生人」这类承诺必须与实际一致（2.3.1） |

---

## 10. 提审前自检 12 项
- [ ] `security find-identity` 能看到 **Apple Distribution** 证书
- [ ] App Store Connect 里 App 记录已建，Bundle ID 匹配
- [ ] 内购商品 `com.sunflowertime.app.premium.lifetime` 状态为「准备提交」且 **Family Sharing 关闭**
- [ ] App 隐私填「不收集数据」
- [ ] 年龄分级问卷完成
- [ ] 截图齐全（含重截的同意页/政策页）
- [ ] 描述/关键词定稿，**无与实际不符的表述**
- [ ] 隐私政策 URL 可访问，且是 **v2.0 发布稿**（⚠️ 线上仍是 v1 旧版，见下）
- [ ] 支持 URL 可访问
- [ ] 审核备注已粘贴（含家长入口与 PIN 说明）
- [ ] Archive 成功，包已上传并处理完成（无 ITMS 警告邮件）
- [ ] 沙盒购买自测通过

---

## 11. ✅ 上架前必须同步的线上口径（2026-10-28 已核实：无需改动）

| # | 事项 | 核实结果 |
|---|---|---|
| A | 线上 `privacy.html` 版本 | **已是 v2.0**，与 `docs/隐私政策_发布版/privacy.html` md5 完全一致，含「五、购买与退款」 |
| B | 官网首页 3 处过期宣传 | **已全部改好**（无内购 / 无网络权限 / iPad 不支持 均无残留） |

> ⚠️ 教训：这轮曾用 bash `grep` 搜中文得出「缺失」的假结论，实际是假 0。中文检索一律用内置 Grep。

---

## 12. 提审流程（顺序执行）

1. Xcode → `Product` → `Archive` → Organizer → `Distribute App` → `App Store Connect` → `Upload`
2. 等 15–30 分钟，App Store Connect 里版本页出现可选的构建版本
3. 选构建、填版本信息、关联内购（首次提审时 IAP 会随 App 一起送审）
4. `Add for Review` → `Submit`
5. 通常 24–72 小时出结果；被拒按 Resolution Center 逐条回复（本手册 §8 已备审核备注）

---

## 13. 🔴 出包实操：为什么 `flutter build ipa` 必然失败（2026-10-28 实测）

### 现象
```
Xcode archive done.  (68.9s)  ✓ Built Runner.xcarchive (525MB)
error: exportArchive No signing certificate "iOS Distribution" found
error: exportArchive No Accounts
```

### 根因（两条，都实测取证）

| # | 事实 | 命令取证 |
|---|---|---|
| 1 | Xcode 已登录付费团队（Individual / `6NW722K2GN` / **isFreeProvisioningTeam = 0**） | `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` |
| 2 | 但 **xcodebuild 的账号列表是空的** → 命令行永远报 `No Accounts` | `defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists` → `{ "IDE.Identifiers.Prod" = ( ); }` |
| 3 | 本机只有 `Apple Development` 证书，无 `Apple Distribution` | `security find-identity -v -p codesigning` |
| 4 | 唯一描述文件是旧的开发档（`get-task-allow=true`，**2026-10-30 到期**） | `security cms -D -i <profile>` |

> 结论：**别跟 CLI 死磕**。Xcode 27.1 的 GUI 账号态与 xcodebuild 读的旧 plist 不同步，这条链路走不通；archive 本身是成功的，只差导出。

### 正确路径（GUI，一次点完，证书+描述文件+上传全自动）

1. **先建发布证书**：Xcode → Settings → Apple Accounts → 选中团队 → `Manage Certificates…` → 左下 `+` → **Apple Distribution** → 自动生成后 `Done`
   - 验证：`security find-identity -v -p codesigning` 出现 `Apple Distribution: junchao wang (6NW722K2GN)`
2. **导出并上传**：`open build/ios/archive/Runner.xcarchive` → Organizer → 右侧 `Distribute App` → `App Store Connect` → `Upload` → 签名选 **Automatically manage signing** → 一路 Next
3. 上传成功后 15–30 分钟，ASC 版本页出现构建版本

### 「Signing & Capabilities」在哪（不是设置窗口）
它是 **target 的属性**，不在 Xcode Settings 里：

```
⌘1 打开左侧导航 → 点最上方蓝色工程图标 Runner
→ 编辑区左栏 TARGETS 下点 Runner
→ 编辑区顶部标签栏第 2 个 = Signing & Capabilities
```

若顶部看不到标签栏 → 说明只开了空窗口，工程没真正打开，执行 `open ios/Runner.xcworkspace`。

---

## 14. 🔴 ITMS-90683 拒收（缺失 NSMicrophoneUsageDescription）· 2026-10-28 实战

### 苹果邮件原文要点
> Build **2100** 被拒收：`ITMS-90683: Missing purpose string in Info.plist` —— `Runner.app` 应包含 `NSMicrophoneUsageDescription`。
> 「**While your app might not use these APIs, a purpose string is still required.**」

### 我们的 App 根本不录音，为什么会被要求
不是我们写的代码，是传递依赖：

| 链路 | 说明 |
|---|---|
| `just_audio`（BGM/SFX 播放） | 依赖 `audio_session` |
| `audio_session` iOS 源码 | `Sources/audio_session/DarwinAudioSession.m` 里实现了 `recordPermission` / `requestRecordPermission:`（用于录音场景） |
| Apple 静态检查器 | 只要二进制里出现这些符号，就要求对应的 purpose string，**与运行时是否真的调用无关** |

**取证命令（复现方式）**
```bash
cd build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
grep -rl "requestRecordPermission" Frameworks/*/* Runner
# → 仅 Frameworks/audio_session.framework/audio_session 命中
```

### 已做的修复（3 处 + 版本号）
| # | 文件 | 改动 |
|---|---|---|
| 1 | `ios/Runner/Info.plist` | 新增 `NSMicrophoneUsageDescription`（英文基串） |
| 2 | `ios/Runner/en.lproj/InfoPlist.strings` | 同键英文串（用户可见） |
| 3 | `ios/Runner/zh-Hans.lproj/InfoPlist.strings` | 同键简体中文串 |
| 4 | `pubspec.yaml` | `1.0.0+2101` → **`1.0.0+2102`**（2101 归档带同一缺陷，作废重编；换号便于在 Organizer 里区分，防止误传旧包） |

**文案口径（已按「诚实说明」写，不编造用途）**
> 中文：小小葵番茄钟只播放音乐和音效，不录音，也不会请求麦克风权限。此说明为系统音频播放组件所要求。
> 英文：Tiny Sunflower only plays music and sound effects. It does not record audio and never requests microphone access; this entry is required because the system audio playback component references microphone APIs.

> 因为**从不调用** `requestRecordPermission`，系统**永远不会弹出麦克风授权框**，App 隐私标签仍为「不收集数据」，用户侧零感知。

### 为什么不用「编译期剔除」这个更干净的方案
`audio_session` 源码里有 `#if AUDIO_SESSION_MICROPHONE` 开关（默认 1），理论上可在 `Podfile` 的 `post_install` 里给该 pod 加 `GCC_PREPROCESSOR_DEFINITIONS = '$(inherited) AUDIO_SESSION_MICROPHONE=0'`，把符号从二进制里编译掉、连串都不需要。

**本次没这么做**，理由：改第三方 pod 的编译设置一旦有偏差会直接导致构建失败，而每次上传失败都要重新走一遍「编译→上传→等苹果处理 15–30 分钟→收邮件」的循环。苹果自己在邮件里写了「即使不用也必须声明」，加串是确定能过的路径。**留作后续可选优化**（若审核对麦克风声明有疑问，再改用剔除方案）。

### 附带体检：其余敏感 API 全部为 0
同一个包里扫了另外 10 类需要 purpose string 的 API，全部无命中，**不会再有第二次同类拒收**：

```
AVCaptureDevice / PHPhotoLibrary / CLLocationManager / CNContactStore
CBCentralManager / ASIdentifierManager / CMMotionActivityManager
SFSpeechRecognizer / MPMediaLibrary / HKHealthStore   → 全部 0
```

### 提审注意
ASC 里现在会有多个构建版本：

| build | 内容 | 状态 |
|---|---|---|
| 2100 | 改名前的旧包 | **被拒**（ITMS-90683 缺麦克风用途串） |
| 2101 | 本地归档，与 2100 同一缺陷 | 作废，未上传 |
| 2102 | 修完 ITMS-90683（含麦克风串 + PrivacyInfo + 加密声明 + Tiny Sunflower 新名） | 已上传 ASC |
| 2103 | 加 F161/F162（成长页任务卡 + 商店确认卡英文挤压） | 本地归档，未上传 |
| 2104 | 加 F163/F164（花园养护卡按钮折行/截断 + 全仓英文溢出排查批） | 本地归档，**作废**（缺 F165/F166） |
| **2105** | **再加 F165（免费档提示条常驻黑条 → 居中浮层）+ F166（家长端「关于与反馈」+ 花园锁定加盆格）** | ✅ **已归档并校验通过（唯一可提审版本）** |

提审时**只能选 2105**（2104 已作废，勿传）。

> 为什么跳过 2103/2104：F163/F164 是玄参在小米 14 Pro 与 iOS 模拟器上实测发现的英文长文案问题（花园养护卡 `Remove` 折成 `Remov/e`、`Fertilize +0.8%` 的增幅被省略号吃掉、花盆标签静默截断吞掉价格、成长页进度头行与家长端任务页标题行溢出），代码 `897d0f3`。此后又补两批：**F165** 修免费用户「新增」达上限时那条**永久驻留的黑色提示条**（改居中浮层）、**F166** 加开发者联系方式与花园可扩展性提示（新增 `url_launcher` 依赖）。`bug记录表.md` F163–F166 有完整根因与测试记录。

> ✅ **2105 归档后已完成二进制敏感符号复核（2026-10-29，本仓上架铁律，F160 就是这么漏的）**：
> 扫 13 类符号（`AVCaptureDevice` / `requestRecordPermission` / `AVCaptureSession` / `PHPhotoLibrary` / `CLLocationManager` / `CNContactStore` / `CBPeripheralManager` / `ATTrackingManager` / `CMMotionManager` / `SFSpeechRecognizer` / `MPMediaLibrary` / `HKHealthStore` / `ASIdentifierManager`），**结果 2 命中、均无害**：
> ① `requestRecordPermission`（`audio_session.framework`）—— 已知，`NSMicrophoneUsageDescription` 已声明（F160 修复项）；
> ② `CMMotionManager`（`native_device_orientation.framework`）—— **只引用 `CMMotionManager` 类读设备朝向**，无 `CMMotionActivityManager` / `CMPedometer` / `CMSensorRecorder` → 不触碰「运动与健身」健康数据，**无需 `NSMotionUsageDescription`**，也不会弹权限框；且 2102（已上传并处理完成）/2104 包内同样存在，审核侧从未提异议。
> 其余 11 类全部 0 命中。`url_launcher` 只走 `UIApplication openURL`，不申请任何权限；**代码未使用 `canLaunchUrl`** → 无需 `LSApplicationQueriesSchemes` 白名单（若将来改用 `canLaunchUrl`，必须补 `mailto`/`https` 白名单，否则永远返回 false）。
> 包内实测：`1.0.0 / 2105` · `Tiny Sunflower`(en) / `小小葵番茄钟`(zh) · 麦克风串 ✓ · `ITSAppUsesNonExemptEncryption=false` ✓ · `PrivacyInfo.xcprivacy` 1140B ✓ · `url_launcher_ios.framework` 已入包 · 344MB。
