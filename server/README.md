# 官网自动解锁方案 B · 服务端

Python + FastAPI + SQLite 的最小可用实现，对应
[`docs/官网自动解锁_技术方案_v1.md`](../docs/官网自动解锁_技术方案_v1.md) 的 §6–§9、§12。

服务端只做三件事：**签发订单号 → 验证支付宝回调 → 从离线预签码池取一枚码**。
它不做任何激活码密码学运算。

---

## 🔴 最重要的一条：服务器上没有发码私钥

> **Ed25519 发码私钥永远只在开发者本机。** 本目录、这台服务器、这份代码里
> **不允许出现**任何发码私钥 / 种子（禁止 `BEGIN PRIVATE KEY` 形式的 Ed25519 种子）。
>
> 服务器上出现的 `ALIPAY_APP_PRIVATE_KEY` 是**支付宝应用私钥**（RSA2），用途是给
> 下单串签名和调退款接口，**与发码私钥毫无关系**。两者风险域完全独立：
> - 支付宝应用私钥泄露 → 可伪造下单 / 调退款；
> - 发码私钥泄露 → 可无限伪造激活码，且离线验签**无法吊销**。
>
> 补货流程：在本机运行 `dart tool/issue_redeem_code.dart --serial <起始> --count <数量> --out codes.json`
> （🔴 用 `dart` 直调而非 `dart run`，否则 SDK 会多打一句 `Running build hooks...`）
> 生成机器可读 JSON → `scp` 到服务器 `/tmp`（权限 600）→ 用下面的命令导入 →
> **立即删除**本机与服务器上的临时 JSON → 把 serial 区间记入发放台账，防止区间重叠。
> 对外正式发码从 **serial 1001** 起。
>
> 验收方式：`grep -r "BEGIN PRIVATE" /srv` 应零命中发码密钥（支付宝应用私钥除外，须单独存放并授权）。

---

## 目录结构

```
server/
  README.md           本文件
  requirements.txt    依赖
  .env.example        配置样例（无真实密钥；不要改造成 .env 提交）
  app/
    __init__.py
    config.py         环境变量配置；金额常量 49.90；沙箱/生产网关与公钥分开
    db.py             SQLite schema（§7 DDL）+ 连接/事务工具
    pool.py           离线码池 JSON 导入（INSERT OR IGNORE）+ 余量查询
    alipay.py         RSA2 下单串签名 + notify 验签
    main.py           5 个接口 + 内部补发后台页
  tests/test_api.py   TestClient 契约测试
```

## 沙箱启动步骤

需要 Python ≥ 3.10。

```bash
cd server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

cp .env.example .env          # 然后填入沙箱值；.env 已在 server/.gitignore 中
set -a; source .env; set +a

# 1) 准备一个测试码池 JSON（本机签发，服务器上只有成品码）
cat > /tmp/codes.json <<'JSON'
[{"serial":1001,"code":"TESTCODE001"},{"serial":1002,"code":"TESTCODE002"}]
JSON
.venv/bin/python -m app.pool import /tmp/codes.json

# 2) 启动（默认只监听 127.0.0.1；公网请用 Nginx 反代 + HTTPS）
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# 3) 冒烟
curl http://127.0.0.1:8000/v1/pool/status
curl http://127.0.0.1:8000/admin
```

沙箱参数从支付宝开放平台「沙箱应用」页面取：`APPID`、应用私钥、支付宝公钥、
沙箱 PID。 notify 地址在沙箱里通常要能公网可达；本地联调可用内网穿透。

## 配置项

| 变量 | 默认 | 说明 |
|---|---|---|
| `APP_ENV` | `sandbox` | `sandbox` / `production` |
| `ALIPAY_GATEWAY` | 按环境自动选 | 沙箱 `https://openapi-sandbox.dl.alipaydev.com/gateway.do`；生产 `https://openapi.alipay.com/gateway.do` |
| `ALIPAY_APP_ID` | 空 | 支付宝应用 ID |
| `ALIPAY_SELLER_ID` | 空 | 商户 PID，校验 notify 的 `seller_id` |
| `ALIPAY_APP_PRIVATE_KEY` / `_PATH` | 空 | 支付宝**应用**私钥（RSA2），二选一 |
| `ALIPAY_SANDBOX_PUBLIC_KEY` | 空 | **沙箱**支付宝公钥 |
| `ALIPAY_PRODUCTION_PUBLIC_KEY` | 空 | **生产**支付宝公钥（与沙箱不同，绝不共用） |
| `NOTIFY_URL` | 空 | 公网 HTTPS 回调地址 |
| `DATABASE_PATH` | `./data/server.db` | SQLite 文件 |
| `ADMIN_TOKEN` | 空 | 后台 token；留空时仅允许 127.0.0.1 访问 |
| `HOST` / `PORT` | `127.0.0.1` / `8000` | uvicorn 绑定 |
| `ORDER_TTL_SECONDS` | `900` | 订单有效期 |
| `CREATE_RATE_*` / `REDEEM_RATE_*` | 见 `.env.example` | 内存限流阈值 |

`amount` **不接受环境变量或客户端传值**，在 `app/config.py` 里固定为字符串
`"49.90"`（玄参 2026-11-26 拍板，原为 29.90），全程不做 float 转换。

## 接口速查

| 方法 | 路径 | 成功 | 说明 |
|---|---|---|---|
| POST | `/v1/order/create` | 200 | 先查码池余量，空则 503 `POOL_EXHAUSTED` 且不签名下单 |
| GET | `/v1/order/redeem` | 200 / 202 | `issued`(200) / `pending`(202) / `unpaid`(200) |
| POST | `/v1/alipay/notify` | 200 | 纯文本 `success`（拒绝时纯文本 `failure`） |
| GET | `/v1/pool/status` | 200 | 只返回数量，不返回码 |
| GET/POST | `/admin`, `/admin/issue` | HTML | 内部人工补发 |

所有响应带 `X-Request-Id`。错误体统一为 `{"ok": false, "error": "...", "message": "..."}`。

### 关于 `pending` 与 `unpaid` 的判定（文档未明示，此处的实现口径）

数据库只有 `pending | paid | issued | void` 四态，而接口要返回三种 status。实现口径：

- 已绑定码 → 200 `issued`；
- 已付款（`paid` / `issued`）未绑定 → 原子取码并绑定 → 200 `issued`；
- 刚创建、未收到回调、**未过期**的 `pending` → **202 `pending`**，对应 §5.2 的回调竞态，App 应重试；
- 已过期（`created_at` 超过 `ORDER_TTL_SECONDS`）的 `pending` 或 `void` → 200 `unpaid`。

### 关于 notify 拒绝时的响应

签名 / `app_id` / 金额 / `trade_status` / `seller_id` 任一校验失败：不写库、记录脱敏日志，
返回**纯文本** `failure`（不是 JSON）。成功入库才返回纯文本 `success`。
金额错误会额外打 `ALERT` 日志。

## 测试

```bash
.venv/bin/python -m pytest server/tests/test_api.py -q
# 若沙箱环境拦截系统 /tmp（pytest 报 FileExistsError），改用工作区内的临时目录：
.venv/bin/python -m pytest server/tests/test_api.py -q --basetemp=server/.pytest_tmp
# 或最低要求：仅语法校验
python3 -m py_compile server/app/*.py server/tests/*.py
```

测试用 `app.dependency_overrides` 替换 `verify_notify` 与 `get_order_string_builder`，
无需真实支付宝密钥或网络。覆盖：全链路、redeem 幂等 ×10、unpaid、202 延迟回调、
错误凭据、池空拒绝且不下单、notify 重放、金额篡改、重复导入、限流、并发领取、后台补发。

## 生产切换清单

1. 备案 / APPID / APP 支付签约全部下来后，设置 `APP_ENV=production`。
2. 用**生产**支付宝公钥填 `ALIPAY_PRODUCTION_PUBLIC_KEY`；确认沙箱公钥不再被读取
   （`settings.alipay_public_key` 按 `APP_ENV` 严格择一）。
3. 换用生产 `APPID` / PID / 应用私钥；确认网关是 `https://openapi.alipay.com/gateway.do`。
4. `NOTIFY_URL` 改为 `https://api.sunfocused.top/v1/alipay/notify`，支付宝后台回跳地址同步。
5. 设置强随机 `ADMIN_TOKEN`；确认 uvicorn 只绑定内网 / Nginx 仅放行 443，
   `/admin` 不对外裸奔。Nginx 反代时透传真实 IP 供限流使用（`proxy_set_header X-Forwarded-For`），
   uvicorn 加 `--proxy-headers --forwarded-allow-ips=<Nginx IP>`。
6. 只在 App 内发起支付；网站仍然**只展示价格与下载，不承载交易**（§3.1）。
7. 升级为破坏性变更时走 `/v2`，`/v1` 至少保留 12 个月。

## 运维命令

```bash
# 导入码池（可重复执行，INSERT OR IGNORE）
.venv/bin/python -m app.pool import /tmp/codes.json

# 查余量（available < 总数 10% 时告警；< 20% 时安排补货）
.venv/bin/python -m app.pool status

# 每日备份（保留 30 天，本地 + 异地各一份）
cp data/server.db /backup/server-$(date +%F).db
scp /backup/server-$(date +%F).db <异地主机>:/backup/

# systemd 常驻（示例）
# ExecStart=/srv/sunflowerTime/server/.venv/bin/uvicorn app.main:app \
#   --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1
```

安全约定：业务表**不存用户 IP**（只在 Nginx access log 保留 7 天）；
日志中 `claim_token` / `redeem_code` / `trade_no` 一律只留前 4 后 4；
码池 JSON 用完立即删除（权限 600）；服务器只开 80/443，SSH 改端口且禁用密码登录。
