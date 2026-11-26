"""Contract tests for the five public endpoints (技术方案 §6 + §12).

The Alipay signature verifier and order-string signer are replaced with stubs
via ``app.dependency_overrides``, so the suite needs neither real keys nor
network access.
"""

from __future__ import annotations

import dataclasses
import json
import os
import re
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

# Configure a harmless environment BEFORE importing the app.
_TEMP_ROOT = Path(tempfile.mkdtemp(prefix="unlock-server-tests-"))
os.environ.update(
    {
        "APP_ENV": "sandbox",
        "ALIPAY_APP_ID": "app-id-test",
        "ALIPAY_SELLER_ID": "seller-id-test",
        "ALIPAY_SANDBOX_PUBLIC_KEY": "test-alipay-public-key",
        "ALIPAY_PRODUCTION_PUBLIC_KEY": "test-prod-alipay-public-key",
        "NOTIFY_URL": "https://api.example.test/v1/alipay/notify",
        "ADMIN_TOKEN": "admin-token-test",
        "DATABASE_PATH": str(_TEMP_ROOT / "import.db"),
    }
)

from fastapi.testclient import TestClient  # noqa: E402

import app.db as db  # noqa: E402
import app.main as main  # noqa: E402
import app.pool as pool  # noqa: E402

BASE_SETTINGS = main.settings


class FakeOrderBuilder:
    """Records calls and returns a deterministic, obviously-fake order string."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []

    def __call__(self, out_trade_no: str, amount: str) -> str:
        self.calls.append((out_trade_no, amount))
        return f"app_id=stub&out_trade_no={out_trade_no}&sign=stub"


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Fresh isolated DB, 6 fake codes, and stubbed Alipay dependencies."""
    main.app.dependency_overrides.clear()
    monkeypatch.setattr(main, "rate_limiter", main.RateLimiter())

    test_settings = dataclasses.replace(BASE_SETTINGS, database_path=tmp_path / "test.db")
    monkeypatch.setattr(main, "settings", test_settings)
    db.init_db(test_settings.database_path)

    codes = [{"serial": 1001 + i, "code": f"TESTCODE{i:03d}"} for i in range(6)]
    codes_file = tmp_path / "codes.json"
    codes_file.write_text(json.dumps(codes), encoding="utf-8")
    pool.import_pool(codes_file, test_settings.database_path)

    builder = FakeOrderBuilder()
    monkeypatch.setitem(main.app.dependency_overrides, main.get_order_string_builder, lambda: builder)
    # 验签桩：业务校验仍在 endpoint 里真实执行
    monkeypatch.setitem(main.app.dependency_overrides, main.verify_notify, lambda: True)

    with TestClient(main.app, raise_server_exceptions=False) as test_client:
        yield test_client, builder, test_settings, codes_file

    main.app.dependency_overrides.clear()


def create_order(test_client: TestClient, device_hash: str = "device-1", **overrides):
    """POST /v1/order/create with defaults that satisfy the contract."""
    body = {
        "platform": "android",
        "app_version": "1.1.0+2107",
        "device_hash": device_hash,
    }
    body.update(overrides)
    return test_client.post("/v1/order/create", json=body)


def notify(test_client: TestClient, out_trade_no: str, **overrides):
    """POST /v1/alipay/notify with a well-formed payload."""
    payload = {
        "app_id": "app-id-test",
        "out_trade_no": out_trade_no,
        "trade_no": f"ALIPAY-{out_trade_no}",
        "trade_status": "TRADE_SUCCESS",
        "total_amount": "29.90",
        "seller_id": "seller-id-test",
        "gmt_payment": "2026-11-25 10:00:00",
        "sign_type": "RSA2",
        "sign": "stub-signature",
    }
    payload.update(overrides)
    return test_client.post("/v1/alipay/notify", data=payload)


def redeem(test_client: TestClient, out_trade_no: str, claim_token: str):
    """GET /v1/order/redeem with the given credentials."""
    return test_client.get(
        "/v1/order/redeem",
        params={"out_trade_no": out_trade_no, "claim_token": claim_token},
    )


# ---------------------------------------------------------------------------
# 1. happy path
# ---------------------------------------------------------------------------
def test_full_happy_path(client):
    test_client, builder, settings, _ = client
    created = create_order(test_client)
    assert created.status_code == 200, created.text
    data = created.json()["data"]

    assert data["amount"] == "29.90"
    assert data["expires_in"] == 900
    assert re.fullmatch(r"SF\d{6}[A-Z2-7]{8}", data["out_trade_no"])
    assert re.fullmatch(r"[0-9a-f]{32}", data["claim_token"])
    assert builder.calls == [(data["out_trade_no"], "29.90")]

    callback = notify(test_client, data["out_trade_no"])
    assert callback.status_code == 200
    assert callback.text == "success"  # pure text, no JSON quotes / BOM

    claimed = redeem(test_client, data["out_trade_no"], data["claim_token"])
    assert claimed.status_code == 200, claimed.text
    result = claimed.json()["data"]
    assert result["status"] == "issued"

    with db.connection(settings.database_path) as conn:
        row = conn.execute(
            "SELECT code, status FROM code_pool WHERE serial=?", (result["serial"],)
        ).fetchone()
    assert row is not None
    assert row["code"] == result["redeem_code"]
    assert row["status"] == "issued"


# ---------------------------------------------------------------------------
# 2. idempotency: 10 redeem calls consume exactly one code
# ---------------------------------------------------------------------------
def test_redeem_ten_times_returns_same_code(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]
    assert notify(test_client, created["out_trade_no"]).text == "success"

    responses = [
        redeem(test_client, created["out_trade_no"], created["claim_token"]) for _ in range(10)
    ]
    assert all(response.status_code == 200 for response in responses)
    bodies = [response.json()["data"] for response in responses]
    assert all(body == bodies[0] for body in bodies)
    assert bodies[0]["status"] == "issued"

    counts = pool.pool_status(settings.database_path)
    assert counts["issued"] == 1
    assert counts["available"] == 5


# ---------------------------------------------------------------------------
# 3. unpaid order -> 200 unpaid
# ---------------------------------------------------------------------------
def test_unpaid_order_returns_unpaid(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]

    # An order past its TTL is definitively unpaid (no callback can still be
    # in flight), so it maps to 200 unpaid rather than 202 pending.
    with db.connection(settings.database_path) as conn:
        conn.execute(
            "UPDATE orders SET created_at='2020-01-01T00:00:00Z' WHERE out_trade_no=?",
            (created["out_trade_no"],),
        )
    response = redeem(test_client, created["out_trade_no"], created["claim_token"])
    assert response.status_code == 200
    assert response.json()["data"] == {"status": "unpaid"}
    assert pool.pool_status(settings.database_path)["issued"] == 0


# ---------------------------------------------------------------------------
# 4. delayed notify -> 202 pending, then issued
# ---------------------------------------------------------------------------
def test_delayed_callback_returns_202_then_issued(client):
    test_client, _, _, _ = client
    created = create_order(test_client).json()["data"]

    pending = redeem(test_client, created["out_trade_no"], created["claim_token"])
    assert pending.status_code == 202
    assert pending.json()["data"] == {"status": "pending"}

    assert notify(test_client, created["out_trade_no"]).text == "success"
    issued = redeem(test_client, created["out_trade_no"], created["claim_token"])
    assert issued.status_code == 200
    assert issued.json()["data"]["status"] == "issued"


# ---------------------------------------------------------------------------
# 5. wrong claim token -> 403
# ---------------------------------------------------------------------------
def test_wrong_claim_token_forbidden(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]
    assert notify(test_client, created["out_trade_no"]).text == "success"

    response = redeem(test_client, created["out_trade_no"], "f" * 32)
    assert response.status_code == 403
    assert response.json()["error"] == "CLAIM_TOKEN_MISMATCH"
    assert pool.pool_status(settings.database_path)["issued"] == 0


# ---------------------------------------------------------------------------
# 6. empty pool -> 503 and NO Alipay call
# ---------------------------------------------------------------------------
def test_empty_pool_rejects_create_without_alipay_call(client, tmp_path, monkeypatch):
    test_client, builder, settings, _ = client
    calls_before = len(builder.calls)

    empty_settings = dataclasses.replace(settings, database_path=tmp_path / "empty.db")
    monkeypatch.setattr(main, "settings", empty_settings)
    db.init_db(empty_settings.database_path)

    response = create_order(test_client, device_hash="device-empty")
    assert response.status_code == 503
    assert response.json()["error"] == "POOL_EXHAUSTED"
    assert len(builder.calls) == calls_before

    with db.connection(empty_settings.database_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 0


# ---------------------------------------------------------------------------
# 7. notify replay is idempotent
# ---------------------------------------------------------------------------
def test_notify_replay_is_idempotent(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]
    no = created["out_trade_no"]

    first = notify(test_client, no, trade_no="TRADE-FIRST")
    second = notify(test_client, no, trade_no="TRADE-SECOND")
    assert first.text == second.text == "success"

    with db.connection(settings.database_path) as conn:
        row = conn.execute("SELECT * FROM orders WHERE out_trade_no=?", (no,)).fetchone()
    assert row["status"] == "paid"
    assert row["alipay_trade_no"] == "TRADE-FIRST"  # first write wins
    assert row["redeem_code"] is None

    a = redeem(test_client, no, created["claim_token"]).json()["data"]
    b = redeem(test_client, no, created["claim_token"]).json()["data"]
    assert a == b
    assert pool.pool_status(settings.database_path)["issued"] == 1


# ---------------------------------------------------------------------------
# 8. tampered amount -> rejected even when signature stub passes
# ---------------------------------------------------------------------------
def test_notify_wrong_amount_rejected(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]
    no = created["out_trade_no"]

    rejected = notify(test_client, no, total_amount="0.01")
    assert rejected.status_code == 200
    assert rejected.text == "failure"

    with db.connection(settings.database_path) as conn:
        row = conn.execute("SELECT status FROM orders WHERE out_trade_no=?", (no,)).fetchone()
    assert row["status"] == "pending"

    pending = redeem(test_client, no, created["claim_token"])
    assert pending.status_code == 202
    assert pending.json()["data"]["status"] == "pending"


# ---------------------------------------------------------------------------
# 9. pool import is repeatable
# ---------------------------------------------------------------------------
def test_pool_import_twice_has_no_duplicates(client):
    test_client, _, settings, codes_file = client
    before = pool.pool_status(settings.database_path)
    result = pool.import_pool(codes_file, settings.database_path)
    after = pool.pool_status(settings.database_path)

    assert result.inserted == 0
    assert result.skipped == 6
    assert result.total == before["total"] == after["total"] == 6


# ---------------------------------------------------------------------------
# Additional contract guarantees
# ---------------------------------------------------------------------------
def test_non_android_platform_rejected(client):
    test_client, builder, _, _ = client
    calls_before = len(builder.calls)
    response = create_order(test_client, platform="ios")
    assert response.status_code == 400
    assert response.json()["error"] == "BAD_REQUEST"
    assert len(builder.calls) == calls_before


def test_order_not_found(client):
    test_client, _, _, _ = client
    response = redeem(test_client, "SF261125AAAAAAAAA", "a" * 32)
    assert response.status_code == 404
    assert response.json()["error"] == "ORDER_NOT_FOUND"


def test_request_id_on_every_response(client):
    test_client, _, _, _ = client
    for response in (
        create_order(test_client),
        test_client.get("/v1/pool/status"),
        redeem(test_client, "SF261125AAAAAAAAA", "a" * 32),
    ):
        value = response.headers.get("X-Request-Id", "")
        assert re.fullmatch(r"[0-9a-f-]{36}", value)


def test_create_rate_limit(client):
    test_client, _, _, _ = client
    responses = [create_order(test_client, device_hash=f"device-{i}") for i in range(6)]
    assert [response.status_code for response in responses] == [200] * 5 + [429]
    assert responses[-1].json()["error"] == "RATE_LIMITED"


def test_bad_signature_is_discarded(client, monkeypatch):
    test_client, _, settings, _ = client
    monkeypatch.setitem(main.app.dependency_overrides, main.verify_notify, lambda: False)
    created = create_order(test_client).json()["data"]

    response = notify(test_client, created["out_trade_no"])
    assert response.text == "failure"
    with db.connection(settings.database_path) as conn:
        row = conn.execute("SELECT status FROM orders WHERE out_trade_no=?", (created["out_trade_no"],)).fetchone()
    assert row["status"] == "pending"


def test_concurrent_redeem_consumes_one_code(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]
    assert notify(test_client, created["out_trade_no"]).text == "success"

    args = (created["out_trade_no"], created["claim_token"])
    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(lambda _: redeem(test_client, *args), range(10)))

    assert all(response.status_code == 200 for response in results)
    bodies = [response.json()["data"] for response in results]
    assert all(body == bodies[0] for body in bodies)
    assert pool.pool_status(settings.database_path)["issued"] == 1


def test_admin_force_issue_for_lost_claim_token(client):
    test_client, _, settings, _ = client
    created = create_order(test_client).json()["data"]

    form = {
        "out_trade_no": created["out_trade_no"],
        "token": "admin-token-test",
        "force": "1",
    }
    response = test_client.post("/admin/issue", data=form)
    assert response.status_code == 200
    assert "serial=" in response.text

    claimed = redeem(test_client, created["out_trade_no"], created["claim_token"]).json()["data"]
    assert claimed["status"] == "issued"
    assert pool.pool_status(settings.database_path)["issued"] == 1


def test_real_rsa2_signing_and_notify_verification():
    """Exercise alipay.py with a freshly generated keypair (no stubs)."""
    from urllib.parse import parse_qs

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    from app import alipay

    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    public_pem = private.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("ascii")
    crypto_settings = dataclasses.replace(
        BASE_SETTINGS, app_private_key=private_pem, sandbox_public_key=public_pem
    )

    order_string = alipay.build_order_string(crypto_settings, "SF2611257K3M9QXA", "29.90")
    parsed = {key: values[0] for key, values in parse_qs(order_string).items()}
    assert parsed["app_id"] == "app-id-test"
    assert parsed["sign_type"] == "RSA2"
    assert '"total_amount":"29.90"' in parsed["biz_content"]
    assert alipay.verify_rsa2(parsed, public_pem, parsed["sign"])

    notify_params = {
        "app_id": "app-id-test",
        "out_trade_no": "SF2611257K3M9QXA",
        "total_amount": "29.90",
        "trade_status": "TRADE_SUCCESS",
        "sign_type": "RSA2",
    }
    # 回调验签排除 sign_type，故模拟支付宝时必须同样排除，否则规则相反验不过。
    notify_params["sign"] = alipay.sign_rsa2(notify_params, private_pem, exclude_sign_type=True)
    assert alipay.verify_notify(notify_params, crypto_settings)
    tampered = dict(notify_params, total_amount="0.01")
    assert not alipay.verify_notify(tampered, crypto_settings)

    production_settings = dataclasses.replace(
        crypto_settings, app_env="production", production_public_key="different-prod-key"
    )
    assert production_settings.alipay_public_key == "different-prod-key"
    assert crypto_settings.alipay_public_key == public_pem


def test_sign_type_is_part_of_signed_string():
    """sign_type stays in the sign source; only sign itself is excluded."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    from app import alipay

    assert alipay.canonical_string(
        {"b": "2", "sign_type": "RSA2", "a": "1", "sign": "xxx"}
    ) == "a=1&b=2&sign_type=RSA2"

    # 把两套相反规则都钉死：默认（下单）含 sign_type；回调排除 sign_type。
    assert alipay.canonical_string(
        {"a": "1", "sign_type": "RSA2", "sign": "x"}
    ) == "a=1&sign_type=RSA2"
    assert alipay.canonical_string(
        {"a": "1", "sign_type": "RSA2", "sign": "x"}, exclude_sign_type=True
    ) == "a=1"

    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    public_pem = private.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("ascii")
    params = {
        "app_id": "app-id-test",
        "out_trade_no": "SF261126SIGTYPE",
        "total_amount": "29.90",
        "sign_type": "RSA2",
    }
    params["sign"] = alipay.sign_rsa2(params, private_pem)
    assert alipay.verify_rsa2(params, public_pem, params["sign"])
    tampered = dict(params, sign_type="HMAC-SHA256")
    assert not alipay.verify_rsa2(tampered, public_pem, tampered["sign"])


# ---------------------------------------------------------------------------
# 真实沙箱回调端到端验签（内联原文，不联网）
# ---------------------------------------------------------------------------
def test_real_sandbox_notify_signature_excludes_sign_type():
    """内联的真实回调 body：排除 sign_type + 原始 UTF-8 值才能验签通过。

    pytest 内不能引用 .env 的真实支付宝公钥（那把公钥为真签名配），所以用
    临时生成的 RSA 密钥对自签自验；参数结构与取值则完全来自真实回调原文。
    """
    from urllib.parse import parse_qs

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    from app import alipay

    body = (
        "gmt_create=2026-11-26+17%3A30%3A11&charset=GBK"
        "&seller_email=vejpwe6892%40sandbox.com"
        "&subject=%E5%B0%8F%E5%B0%8F%E8%91%B5%E7%95%AA%E8%8C%84%E9%92%9F-%E6%B0%B8%E4%B9%85%E8%A7%A3%E9%94%81"
        "&sign=QGBhmKe9QbrWZ%2Fyo57jivCLXnVv5fwCIhvvZR8LAT7y7GlEtILnY36Uvsamn8V%2Bto9Qie28VeDAXIgt1LVObyeeXi3yEkptIFDWKGYGymhdie1HqkfV5kraXTFnyvYchVTTJLGmp1mWCHur25tQ589gbU3ljJsLI5P1j1dA5XPMpzFiMYsxpDS2cUY2dLtAeGLAhfTmaYxzJdJ"
        "sFknRXUIkNCc9xahjcuAC8lF7vItF5sphthhi4FLniWuGosX%2BHXJ5zDjnhI0B7TDPvpqXMrEFMpIxC2gfNdI%2B%2FvVslQ5NhprcitOasHPj68j8REmjtvXc1jh23VyuYqEasvtXvHQ%3D%3D"
        "&buyer_id=2088722121438732&invoice_amount=29.90"
        "&notify_id=2026112601222173106138730509208175"
        "&fund_bill_list=%5B%7B%22amount%22%3A%2229.90%22%2C%22fundChannel%22%3A%22ALIPAYACCOUNT%22%7D%5D"
        "&notify_type=trade_status_sync&trade_status=TRADE_SUCCESS&receipt_amount=29.90"
        "&buyer_pay_amount=29.90&app_id=9021000172667979&sign_type=RSA2"
        "&seller_id=2088721121403223&gmt_payment=2026-11-26+17%3A31%3A05"
        "&notify_time=2026-11-26+17%3A31%3A07&version=1.0&out_trade_no=SF261126WH00101"
        "&total_amount=29.90&trade_no=2026112622001438730510724041"
        "&auth_app_id=9021000172667979&buyer_logon_id=fxogcb7223%40sandbox.com"
        "&point_amount=0.00"
    )
    # charset=GBK 但 subject 的百分编码字节是 UTF-8：必须按 utf-8 解码。
    params = {key: values[0] for key, values in parse_qs(body, encoding="utf-8").items()}
    assert params["subject"] == "小小葵番茄钟-永久解锁"
    assert params["out_trade_no"] == "SF261126WH00101"
    assert params["sign_type"] == "RSA2"
    assert params["total_amount"] == "29.90"

    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("ascii")
    public_pem = private.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("ascii")
    settings = dataclasses.replace(BASE_SETTINGS, sandbox_public_key=public_pem)
    assert settings.alipay_public_key == public_pem

    # 模拟支付宝：按“排除 sign_type”规则用临时私钥重签真实参数。
    params["sign"] = alipay.sign_rsa2(params, private_pem, exclude_sign_type=True)
    assert alipay.verify_notify(params, settings) is True

    # 篡改 sign_type（业务校验）与 total_amount（验签）都应被拒绝。
    assert alipay.verify_notify(dict(params, sign_type="HMAC-SHA256"), settings) is False
    assert alipay.verify_notify(dict(params, total_amount="0.01"), settings) is False
