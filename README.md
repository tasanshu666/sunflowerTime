# sunflowerTime

**《向日葵专注 · SunFocus》** —— 一款用「阳光养成植物」帮助 6–12 岁孩子建立专注与学习习惯的陪伴型专注力训练工具（教育工具，非游戏）。

---

## 当前状态（2026-11-24）

| 项 | 值 |
|---|---|
| 版本 | `1.1.0+2107`（`pubspec.yaml` 与 `kAppBuildNumber` 两处同源，有守卫用例） |
| iOS | **1.0.0 在售**；**1.1.0 (2107) 已提审**（2026-11-24） |
| Android | 工程/签名/上架手册就绪，**未提审**（渠道加固待办、IAP 搁置） |
| 质量基线 | 全量测试 **5831 全绿**；`flutter analyze` **0e / 0w / 76i**（全部既有 info） |
| 数据版本 | `schemaVersion = 32`（Drift + SQLCipher，口令运行期拼装） |
| 代码规模 | `lib` 275 文件 / 122.6K 行；`test` 420 文件 / 156.9K 行 |
| Git | 提交 224 笔，tag `appstore-1.0.0-2105` |

**项目全景与交接材料** → [`docs/项目现状总览_2026-11-24.md`](docs/项目现状总览_2026-11-24.md)

---

## 真源优先级（冲突时按此裁决）

| 顺位 | 文件 | 角色 |
|---|---|---|
| 1 | [`docs/项目进度跟踪表.md`](docs/项目进度跟踪表.md) **§0** | **活状态权威快照**（版本/基线/待办） |
| 2 | [`docs/口径裁定表_v1.md`](docs/口径裁定表_v1.md) | **项目宪法**：C1–C145 拍板判例（翻案留痕） |
| 3 | [`docs/bug记录表.md`](docs/bug记录表.md) | B 系列缺陷台账 + 修复证据 |
| 4 | [`docs/待测清单_2106_真机回归.md`](docs/待测清单_2106_真机回归.md) | 当前待测/提审前置清单 |

> 🔴 `docs/MVP执行规划_v2.md`（2026-09-15）与 `docs/历史归档/` 下早期 PRD/开发计划**已降级为历史快照**，不再作施工依据。

---

## 技术栈

Flutter（iOS + Android 单库）· Riverpod · Drift/SQLCipher · just_audio · in_app_purchase · ARB 本地化（zh/en）

分层单向依赖：`domain`（纯业务 84 文件）← `data/local`（Drift 30）← `presentation`（UI 115）；辅助 `core` 28 / `shared` 8 / `platform` 4 / `l10n` 3。

---

## 常用命令

```bash
# 全量测试（必须摘代理，禁并发）
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=127.0.0.1,localhost ~/development/flutter/bin/flutter test --no-pub

# 静态检查
~/development/flutter/bin/flutter analyze --no-pub

# iOS 上架包（混淆 + 符号拆分 + 自动签名 Team 6NW722K2GN）
~/development/flutter/bin/flutter build ipa --release --obfuscate \
  --split-debug-info=build/symbols/ios/1.1.0+2107

# Android 上架包
~/development/flutter/bin/flutter build apk --release --obfuscate \
  --split-debug-info=build/symbols
```

---

## 文档索引

### 进度与审计
`项目进度跟踪表.md`（79K，§0 权威快照）· `口径裁定表_v1.md`（474K，判例）· `bug记录表.md`（375K）· `经验总结记录表.md`（21K）· `待测清单_2106_真机回归.md`

### 设计文档（按模块，历史快照）
- **天气系统**：A2 设计/PRD、A3/A4/A5/A7 增量设计、最终方案、季节权重
- **花园守卫**：增量 PRD v1/v2、守卫战玩法、宝箱与结算演出、守卫大招、素材实体比
- **许愿树**：增量 PRD v0.1–v0.3、架构设计 v0.1–v0.3、成长任务闭环、设计确认稿 + mermaid
- **付费/称号**：付费墙阶段5、称号属性系统设计、购买页改版、F146 对比表
- **其他**：专注等级、专注报告 v2、植物成长动画、软件设计文档 M0–M3M4

### 上架与合规
`上架执行手册_AppStore_v1.md` · `上架执行手册_安卓国内渠道_v1.md`（v1.3）· `上架注意事项_安卓国内渠道_v1.md` · `商店文案_AppStore_v1.md` · `商店文案_国内安卓_v1.md` · `签名密钥与发布.md` · `隐私政策_向日葵专注_v1.md`（+EN +发布版）· 备案四件套 + `备案材料/` · `软著材料/` · `商店截图/`

### 历史归档
`docs/历史归档/`（早期 PRD v2.0 / 开发计划 v1.0）· `项目进度跟踪表_历史归档_20261104.md` · `MVP执行规划_v2.md`（已降级）· 早期 QA 验收报告 / 耗时记录 / 提案 / ASC 沟通材料

---

## 硬约束速查（改动前必读）

- `schemaVersion = 32` 不得擅动；既有表加索引须先 `DROP INDEX IF EXISTS` → `createAll()`
- 孩子端 5 tab：Today / Growth / Garden / Store / Mine（**无 My tab**）
- 无通用 `spend()`；禁止给 `SunlightRepository` 加方法
- 版本号两处同源：`pubspec.yaml` + `app_constants.dart`
- iOS `CODE_SIGN_STYLE = Automatic` + Team `6NW722K2GN`，**勿再手写 `CODE_SIGN_IDENTITY`**（C145 判例）
- release 出包必须带 `--obfuscate --split-debug-info`（防逆向，C142 纪律）
- 历史文档留痕不抹除（设计快照/裁定判例不回改）
