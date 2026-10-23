# App Store 商店文案 v1（美区首发 · 2026-10-23 玄参拍板）

> 应用更名批（2026-10-23）：中文名「小小葵番茄钟」/ 英文名「Tiny Bloom」（**暂定**，App Store Connect 查重冲突再改）/ 副标题「Kids Focus & Grow」/ 开发者「小小葵」。Bundle ID `com.sunflowertime.app` 不变。

## 一、确认过的字段

| 字段 | 内容 | 备注 |
|---|---|---|
| App Name（英区） | Tiny Bloom | 暂定；30 字符内 |
| App Name（中区/简中） | 小小葵番茄钟 | |
| Subtitle（副标题） | Kids Focus & Grow | 30 字符内 |
| Developer Name | 小小葵 | 个人开发者；含中文的名称仅中区显示，美区建议 `Xiaoxiaokui`（待 App Store Connect 实测） |
| Bundle ID | com.sunflowertime.app | 不变 |
| Privacy Policy URL | https://sunfocused.cn/privacy.html | 英文页 /privacy-en.html，均已 v2.0 就绪 |
| 价格 | 一次性买断（非消耗型 IAP），非订阅 | |

## 二、待补字段（建 App 后填）

- [ ] Description（描述文案，4000 字符内）——待玄参定稿
- [ ] Keywords（100 字符）——待玄参定稿
- [ ] What's New（版本更新说明）
- [ ] 年龄分级问卷（儿童类别）
- [ ] 截图：复用 `docs/商店截图/` 三套（⚠️ 其中同意页/政策页两张因 C110 批已改版需重截）
- [ ] App Privacy（隐私营养标签）：申报为「不收集数据」，依据政策 §3
- [ ] IAP 买断项配置 + 沙盒自测

## 三、改名落点清单（本批已改）

- iOS `Info.plist` CFBundleDisplayName = Tiny Bloom + `en.lproj`/`zh-Hans.lproj` InfoPlist.strings（桌面名按系统语言切换）
- Android `values/strings.xml`（Tiny Bloom）+ `values-zh/strings.xml`（小小葵番茄钟），Manifest `@string/app_name`
- ARB `app_title` / `consent_welcome_title` / `consent_decline_body`（zh/en）
- 隐私政策底稿 zh/en + 发布稿 + App 内资产
- 官网 privacy.html（站点仓库已推）
- ⏳ 待办：官网首页（sunfocused.cn）品牌名与宣传语仍为「向日葵专注 SunFocus」，待与玄参确认官网改版范围后统一更换
