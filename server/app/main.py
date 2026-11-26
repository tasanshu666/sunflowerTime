"""FastAPI application for 官网自动解锁方案 B.

Five public endpoints (技术方案 §6) plus a minimal local-only customer-service
page (§9.2). The server never performs redeem-code cryptography: it only
hands out codes that were pre-signed offline.
"""

from __future__ import annotations

import base64
import hmac
import html
import logging
import secrets
import threading
import time
import uuid
from collections import deque
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict

from fastapi import Depends, FastAPI, Form, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse
from pydantic import BaseModel, ConfigDict, Field

from . import alipay, config, db, pool

logging.basicConfig(
    level=getattr(logging, config.Settings.from_env().log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("unlock_server")

# Settings are read once at import. Tests swap this object (dataclasses.replace)
# to point at an isolated database; all helpers below look it up dynamically.
settings: config.Settings = config.Settings.from_env()

# Create the schema at import time as well as in the lifespan hook. This makes
# `TestClient(app)` work whether or not the caller enters its context manager.
db.init_db(settings.database_path)

SUCCESS_STATUSES = frozenset({"TRADE_SUCCESS", "TRADE_FINISHED"})
PAYABLE_STATUSES = frozenset({"paid", "issued"})
_B32_ALPHABET_DIGITS = 5  # 5 bytes -> exactly 8 base32 chars (no padding)
_CN_TZ = timezone(timedelta(hours=8))


# ---------------------------------------------------------------------------
# Response helpers and errors
# ---------------------------------------------------------------------------
class ApiError(Exception):
    """A business error mapped to the contract's unified JSON envelope."""

    def __init__(self, status_code: int, error: str, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.error = error
        self.message = message


def _ok(data: dict[str, Any], status_code: int = 200) -> JSONResponse:
    """Wrap a successful payload in ``{ok: true, data: ...}``."""
    return JSONResponse({"ok": True, "data": data}, status_code=status_code)


def _fail(status_code: int, error: str, message: str) -> JSONResponse:
    """Wrap an error in ``{ok: false, error, message}``."""
    return JSONResponse({"ok": False, "error": error, "message": message}, status_code=status_code)


def mask(value: str | None) -> str:
    """Mask a secret for logs: keep only the first and last four characters."""
    if not value:
        return "<empty>"
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}****{value[-4:]}"


@asynccontextmanager
async def lifespan(application: FastAPI) -> Any:
    """Initialise the schema and log the active gateway on every boot."""
    db.init_db(settings.database_path)
    log.info("unlock-server started env=%s gateway=%s db=%s", settings.app_env, settings.gateway, settings.database_path)
    yield
    log.info("unlock-server stopped")


app = FastAPI(title="官网自动解锁服务端", version="1.0.0", lifespan=lifespan)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next: Callable[..., Any]) -> Any:
    """Attach a UUID to every response so users can report it to support."""
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-Id"] = request_id
    return response


@app.exception_handler(ApiError)
async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    """Map :class:`ApiError` onto the documented error envelope."""
    return _fail(exc.status_code, exc.error, exc.message)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Contract says bad parameters are 400 BAD_REQUEST (not FastAPI's 422)."""
    log.warning("bad request validation: %s", exc.errors())
    return _fail(400, "BAD_REQUEST", "参数缺失或格式错误")


@app.exception_handler(Exception)
async def unexpected_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """Never leak a stack trace to the client."""
    log.exception("unhandled exception request_id=%s", getattr(request.state, "request_id", "-"))
    return _fail(500, "SERVER_ERROR", "服务端内部错误")


# ---------------------------------------------------------------------------
# In-memory rate limiting
# ---------------------------------------------------------------------------
class RateLimiter:
    """Sliding-window limiter backed by a dict of deques (per-process only)."""

    def __init__(self) -> None:
        self._events: Dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str, window_seconds: int, max_calls: int) -> bool:
        """Return True and record an event if the caller is under the limit."""
        now = time.monotonic()
        with self._lock:
            events = self._events.setdefault(key, deque())
            while events and now - events[0] > window_seconds:
                events.popleft()
            if len(events) >= max_calls:
                return False
            events.append(now)
            return True


rate_limiter = RateLimiter()


def _client_ip(request: Request) -> str:
    """Client address for rate limiting only — never persisted to a business table."""
    return request.client.host if request.client else "unknown"


# ---------------------------------------------------------------------------
# Injectable dependencies (unit tests override these)
# ---------------------------------------------------------------------------
async def _notify_form(request: Request) -> dict[str, str]:
    """Parse the x-www-form-urlencoded Alipay notification body."""
    form = await request.form()
    return {str(key): str(value) for key, value in form.items()}


def verify_notify(payload: dict[str, str] = Depends(_notify_form)) -> bool:
    """Dependency: verify the notify signature with the Alipay public key.

    Tests replace this via ``app.dependency_overrides[verify_notify]`` so no
    real Alipay keys or network calls are needed.
    """
    if not settings.alipay_public_key:
        log.warning("notify rejected: alipay public key not configured")
        return False
    try:
        return alipay.verify_notify(payload, settings)
    except Exception:
        log.exception("notify signature verification raised an exception")
        return False


def build_order_string(out_trade_no: str, amount: str) -> str:
    """Default order-string builder; tests override the dependency below."""
    return alipay.build_order_string(settings, out_trade_no, amount)


def get_order_string_builder() -> Callable[[str, str], str]:
    """FastAPI dependency returning the order-string builder."""
    return build_order_string


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
def _new_out_trade_no() -> str:
    """``SF + yyMMdd + 8 uppercase base32 chars`` (16 chars total, §6.1.1)."""
    stamp = datetime.now(_CN_TZ).strftime("%y%m%d")
    random_part = base64.b32encode(secrets.token_bytes(_B32_ALPHABET_DIGITS)).decode("ascii")[:8]
    return f"SF{stamp}{random_part}"


def _is_expired(order: Any) -> bool:
    """A fresh unpaid order means 'callback may still arrive'; an old one is unpaid."""
    try:
        created = datetime.strptime(str(order["created_at"]), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return True
    age = (datetime.now(timezone.utc) - created).total_seconds()
    return age >= settings.order_ttl_seconds


def _claim_and_bind(conn: Any, out_trade_no: str) -> tuple[str, int]:
    """Atomically take one available code and bind it to the order.

    Must be called inside :func:`db.transaction`. The SELECT-then-UPDATE uses
    ``WHERE serial=? AND status='available'`` and checks ``rowcount``; a zero
    rowcount means another writer won the race and we retry. There is no
    unconditional write anywhere in this path.
    """
    now = db.utc_now()
    serial: int = -1
    code: str = ""

    for _ in range(5):
        candidate = conn.execute(
            "SELECT serial, code FROM code_pool WHERE status='available' ORDER BY serial LIMIT 1"
        ).fetchone()
        if candidate is None:
            raise ApiError(
                503,
                "POOL_EXHAUSTED",
                f"码池已耗尽，订单 {out_trade_no} 需人工补发",
            )
        cur = conn.execute(
            "UPDATE code_pool SET status='issued', out_trade_no=?, issued_at=? "
            "WHERE serial=? AND status='available'",
            (out_trade_no, now, int(candidate["serial"])),
        )
        if cur.rowcount == 1:
            serial = int(candidate["serial"])
            code = str(candidate["code"])
            break
    else:
        raise ApiError(503, "POOL_EXHAUSTED", f"码池并发耗尽，订单 {out_trade_no} 需人工补发")

    bound = conn.execute(
        "UPDATE orders SET redeem_code=?, serial=?, status='issued', issued_at=?, "
        "paid_at=COALESCE(paid_at, ?) WHERE out_trade_no=? AND redeem_code IS NULL",
        (code, serial, now, now, out_trade_no),
    )
    if bound.rowcount == 0:
        # Another request bound the order first (defensive: BEGIN IMMEDIATE
        # normally prevents this). Return the code that is actually bound and
        # release our speculative reservation so no code is wasted.
        conn.execute(
            "UPDATE code_pool SET status='available', out_trade_no=NULL, issued_at=NULL "
            "WHERE serial=? AND status='issued' AND out_trade_no=?",
            (serial, out_trade_no),
        )
        existing = conn.execute(
            "SELECT redeem_code, serial FROM orders WHERE out_trade_no=?", (out_trade_no,)
        ).fetchone()
        if existing is not None and existing["redeem_code"]:
            return str(existing["redeem_code"]), int(existing["serial"])
        raise ApiError(500, "SERVER_ERROR", "发码状态不一致，请联系客服")

    log.info("code issued order=%s serial=%s", out_trade_no, serial)
    return code, serial


# ---------------------------------------------------------------------------
# §6.1 POST /v1/order/create
# ---------------------------------------------------------------------------
class CreateOrderRequest(BaseModel):
    """Client request body; ``amount`` is deliberately not accepted."""

    model_config = ConfigDict(extra="ignore")

    platform: str = Field(..., min_length=1, max_length=16)
    app_version: str = Field(..., min_length=1, max_length=64)
    device_hash: str = Field(..., min_length=1, max_length=128)


@app.post("/v1/order/create")
async def create_order(
    request: Request,
    body: CreateOrderRequest,
    builder: Callable[[str, str], str] = Depends(get_order_string_builder),
) -> JSONResponse:
    """Create an order, check pool stock first, and sign an Alipay order string."""
    if body.platform != "android":
        raise ApiError(400, "BAD_REQUEST", "本链路仅支持 Android")

    ip = _client_ip(request)
    if not rate_limiter.check(
        f"create:{ip}", settings.create_rate_window_seconds, settings.create_rate_max
    ):
        raise ApiError(429, "RATE_LIMITED", "下单过于频繁，请稍后再试")

    with db.connection(settings.database_path) as conn:
        # 🔴 池空直接拒绝，绝不调起支付宝（不能让用户付了钱没码发）。
        if pool.available_count(conn) <= 0:
            log.warning("order create rejected: pool exhausted ip=%s", mask(ip))
            raise ApiError(503, "POOL_EXHAUSTED", "暂时无法购买，请联系客服")

        out_trade_no = ""
        for _ in range(3):
            candidate = _new_out_trade_no()
            if conn.execute(
                "SELECT 1 FROM orders WHERE out_trade_no=?", (candidate,)
            ).fetchone() is None:
                out_trade_no = candidate
                break
        if not out_trade_no:
            raise ApiError(500, "SERVER_ERROR", "订单号生成失败")

        claim_token = secrets.token_hex(16)
        try:
            order_string = builder(out_trade_no, settings.amount)
        except Exception:
            log.exception("build order string failed")
            raise ApiError(500, "SERVER_ERROR", "下单签名失败，请稍后再试")

        conn.execute(
            "INSERT INTO orders (out_trade_no, claim_token, device_hash, app_version, amount, "
            "status, created_at) VALUES (?, ?, ?, ?, ?, 'pending', ?)",
            (
                out_trade_no,
                claim_token,
                body.device_hash,
                body.app_version,
                settings.amount,
                db.utc_now(),
            ),
        )

    log.info("order created order=%s token=%s", out_trade_no, mask(claim_token))
    return _ok(
        {
            "out_trade_no": out_trade_no,
            "claim_token": claim_token,
            "order_string": order_string,
            "amount": settings.amount,
            "expires_in": settings.order_ttl_seconds,
        }
    )


# ---------------------------------------------------------------------------
# §6.2 GET /v1/order/redeem
# ---------------------------------------------------------------------------
@app.get("/v1/order/redeem")
async def redeem(
    request: Request,
    out_trade_no: str = Query(..., min_length=1, max_length=64),
    claim_token: str = Query(..., min_length=1, max_length=128),
) -> JSONResponse:
    """Idempotently return the one code bound to a paid order."""
    if not rate_limiter.check(
        f"redeem:{claim_token}", settings.redeem_rate_window_seconds, settings.redeem_rate_max
    ):
        log.warning("redeem rate limited order=%s token=%s", out_trade_no, mask(claim_token))
        raise ApiError(429, "RATE_LIMITED", "领取过于频繁，请稍后再试")

    with db.connection(settings.database_path) as conn:
        with db.transaction(conn):
            order = conn.execute(
                "SELECT * FROM orders WHERE out_trade_no=?", (out_trade_no,)
            ).fetchone()
            if order is None:
                raise ApiError(404, "ORDER_NOT_FOUND", "订单不存在")

            if not hmac.compare_digest(str(order["claim_token"]), claim_token):
                log.warning("claim token mismatch order=%s token=%s", out_trade_no, mask(claim_token))
                raise ApiError(403, "CLAIM_TOKEN_MISMATCH", "领取凭据不匹配")

            # Idempotency: an already-bound order is read back, never re-issued.
            if order["redeem_code"]:
                return _ok(
                    {
                        "status": "issued",
                        "redeem_code": str(order["redeem_code"]),
                        "serial": int(order["serial"]),
                    }
                )

            status = str(order["status"])
            if status in PAYABLE_STATUSES:
                code, serial = _claim_and_bind(conn, out_trade_no)
                return _ok({"status": "issued", "redeem_code": code, "serial": serial})

            # Fresh unpaid order: the Alipay callback may still be in flight
            # (§5.2 race) -> 202 so the App retries. Expired/void -> 200 unpaid.
            if status == "pending" and not _is_expired(order):
                return _ok({"status": "pending"}, status_code=202)
            return _ok({"status": "unpaid"})


# ---------------------------------------------------------------------------
# §6.3 POST /v1/alipay/notify
# ---------------------------------------------------------------------------
def _reject_notify(payload: dict[str, str], reason: str) -> PlainTextResponse:
    """Discard an invalid notification and log a redacted diagnostic."""
    log.warning(
        "notify rejected reason=%s order=%s trade=%s amount=%s",
        reason,
        mask(payload.get("out_trade_no")),
        mask(payload.get("trade_no")),
        mask(payload.get("total_amount")),
    )
    return PlainTextResponse("failure")


@app.post("/v1/alipay/notify")
async def alipay_notify(
    payload: dict[str, str] = Depends(_notify_form),
    verified: bool = Depends(verify_notify),
) -> PlainTextResponse:
    """Verify and record a payment notification. Response is plain text only."""
    if not verified:
        return _reject_notify(payload, "bad_signature")

    if payload.get("app_id") != settings.app_id:
        return _reject_notify(payload, "bad_app_id")
    if payload.get("total_amount") != settings.amount:
        # String comparison — never float. Wrong amount is an attack signal.
        log.error(
            "ALERT notify amount mismatch order=%s got=%s expected=%s",
            mask(payload.get("out_trade_no")),
            payload.get("total_amount"),
            settings.amount,
        )
        return _reject_notify(payload, "bad_amount")
    if payload.get("trade_status") not in SUCCESS_STATUSES:
        return _reject_notify(payload, "bad_trade_status")
    if payload.get("seller_id") != settings.seller_id:
        return _reject_notify(payload, "bad_seller_id")

    out_trade_no = payload.get("out_trade_no", "")
    trade_no = payload.get("trade_no", "")
    if not out_trade_no or not trade_no:
        return _reject_notify(payload, "missing_trade_identity")

    with db.connection(settings.database_path) as conn:
        with db.transaction(conn):
            # Idempotent: never touches redeem_code / serial. COALESCE keeps the
            # first trade_no on replay, and CASE never downgrades issued orders.
            cur = conn.execute(
                "UPDATE orders SET "
                "status = CASE WHEN status='pending' THEN 'paid' ELSE status END, "
                "alipay_trade_no = COALESCE(alipay_trade_no, ?), "
                "gmt_payment = COALESCE(gmt_payment, ?), "
                "paid_at = COALESCE(paid_at, ?) "
                "WHERE out_trade_no=?",
                (
                    trade_no,
                    payload.get("gmt_payment", ""),
                    db.utc_now(),
                    out_trade_no,
                ),
            )
            if cur.rowcount == 0:
                log.error("notify for unknown order=%s trade=%s", mask(out_trade_no), mask(trade_no))

    log.info("notify accepted order=%s trade=%s", out_trade_no, mask(trade_no))
    return PlainTextResponse("success")


# ---------------------------------------------------------------------------
# §6.4 GET /v1/pool/status
# ---------------------------------------------------------------------------
@app.get("/v1/pool/status")
async def pool_status() -> JSONResponse:
    """Return stock counts only, never code contents."""
    return _ok(pool.pool_status(settings.database_path))


# ---------------------------------------------------------------------------
# §9.2 Internal back-office page (localhost or token protected)
# ---------------------------------------------------------------------------
def _admin_authorized(request: Request, supplied_token: str) -> bool:
    """Require the admin token when configured, otherwise loopback only."""
    if settings.admin_token:
        candidate = supplied_token or request.query_params.get("token", "")
        return hmac.compare_digest(candidate, settings.admin_token)
    host = request.client.host if request.client else ""
    return host in ("127.0.0.1", "::1", "testclient")


def _admin_page(title: str, message: str, show_token: bool) -> HTMLResponse:
    """Render the tiny support form with a status message."""
    token_field = (
        '<label>Token <input name="token" autocomplete="off" /></label><br />' if show_token else ""
    )
    safe_title = html.escape(title)
    safe_message = html.escape(message)
    body = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>{safe_title}</title>
<style>body{{font-family:system-ui,sans-serif;max-width:680px;margin:40px auto;line-height:1.6}}
input{{padding:6px;width:320px}} button{{padding:6px 16px}} .msg{{background:#f4f4f4;padding:12px}}</style>
</head><body>
<h1>内部补发后台（客服专用）</h1>
<p class="msg">{safe_message}</p>
<form method="post" action="/admin/issue">
  <label>支付宝账单里的商户订单号<br /><input name="out_trade_no" required /></label><br /><br />
  {token_field}
  <label><input type="checkbox" name="force" value="1" /> 强制发码（仅在确认已付款且 notify 丢失时勾选）</label><br /><br />
  <button type="submit">一键发码</button>
</form>
<p><a href="/admin">刷新</a></p>
</body></html>"""
    return HTMLResponse(body)


@app.get("/admin", response_class=HTMLResponse)
async def admin_page(request: Request) -> HTMLResponse:
    """Render the manual-issue form."""
    if not _admin_authorized(request, ""):
        return HTMLResponse("FORBIDDEN", status_code=403)
    return _admin_page("内部补发后台", "输入用户在支付宝账单里看到的商户订单号。", bool(settings.admin_token))


@app.post("/admin/issue", response_class=HTMLResponse)
async def admin_issue(
    request: Request,
    out_trade_no: str = Form(...),
    token: str = Form(""),
    force: str = Form(""),
) -> HTMLResponse:
    """Manually bind a code to an order whose claim_token was lost (§9.2)."""
    if not _admin_authorized(request, token):
        return HTMLResponse("FORBIDDEN", status_code=403)

    out_trade_no = out_trade_no.strip()
    if not out_trade_no:
        return _admin_page("补发失败", "订单号不能为空。", bool(settings.admin_token))

    try:
        with db.connection(settings.database_path) as conn:
            with db.transaction(conn):
                order = conn.execute(
                    "SELECT * FROM orders WHERE out_trade_no=?", (out_trade_no,)
                ).fetchone()
                if order is None:
                    return _admin_page("补发失败", "订单不存在，请核对商户订单号。", bool(settings.admin_token))

                if order["redeem_code"]:
                    detail = (
                        f"该订单已于 {html.escape(str(order['issued_at'] or '-'))} 发码，"
                        f"serial={int(order['serial'])}, code={html.escape(str(order['redeem_code']))}"
                    )
                    return _admin_page("已有激活码", detail, bool(settings.admin_token))

                status = str(order["status"])
                if status not in PAYABLE_STATUSES:
                    if force == "1" and status == "pending":
                        conn.execute(
                            "UPDATE orders SET status='paid', paid_at=COALESCE(paid_at, ?) WHERE out_trade_no=?",
                            (db.utc_now(), out_trade_no),
                        )
                        log.warning("admin force-issued unpaid order=%s", out_trade_no)
                    else:
                        return _admin_page(
                            "补发失败",
                            "订单尚未确认付款。请先核对支付宝账单；确认已付款且回调丢失时勾选「强制发码」。",
                            bool(settings.admin_token),
                        )

                code, serial = _claim_and_bind(conn, out_trade_no)
                detail = (
                    f"发码成功：serial={serial}；激活码（仅本页可见，请勿外传）："
                    f"<code>{html.escape(code)}</code>"
                )
                return _admin_page("补发成功", detail, bool(settings.admin_token))
    except ApiError as exc:
        return _admin_page("补发失败", exc.message, bool(settings.admin_token))
