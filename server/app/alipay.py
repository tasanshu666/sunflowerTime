"""Alipay order-string signing and notify signature verification (RSA2).

Only the *Alipay application private key* lives here. The Ed25519 redeem-code
signing key never does — these are two unrelated key domains (技术方案 §8.2).
"""

from __future__ import annotations

import base64
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping
from urllib.parse import quote, urlencode

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from .config import Settings

SIGN_TYPE: str = "RSA2"
_CN_TZ = timezone(timedelta(hours=8))


def _to_pem(key: str, label: str) -> bytes:
    """Accept either a full PEM block or Alipay's bare base64 body."""
    stripped = key.strip()
    if "-----BEGIN" in stripped:
        return stripped.encode("utf-8")
    lines = [stripped[i : i + 64] for i in range(0, len(stripped), 64)]
    return ("-----BEGIN " + label + "-----\n" + "\n".join(lines) + "\n-----END " + label + "-----\n").encode("utf-8")


def _private_key(pem: str) -> rsa.RSAPrivateKey:
    """Load an RSA private key from PEM or bare base64."""
    key = serialization.load_pem_private_key(_to_pem(pem, "PRIVATE KEY"), password=None)
    if not isinstance(key, rsa.RSAPrivateKey):
        raise TypeError("ALIPAY_APP_PRIVATE_KEY 不是 RSA 私钥")
    return key


def _public_key(pem: str) -> rsa.RSAPublicKey:
    """Load an RSA public key from PEM or bare base64."""
    key = serialization.load_pem_public_key(_to_pem(pem, "PUBLIC KEY"))
    if not isinstance(key, rsa.RSAPublicKey):
        raise TypeError("支付宝公钥不是 RSA 公钥")
    return key


def canonical_string(params: Mapping[str, str], *, exclude_sign_type: bool = False) -> str:
    """Build Alipay's sign source: sorted ``key=value`` pairs, raw values.

    ``sign`` is always excluded. Whether ``sign_type`` is excluded depends on
    the direction, and the two rules are deliberately opposite:

    * Order signing (us -> Alipay gateway): ``sign_type`` stays IN. The gateway
      verifies against ``...&sign_type=RSA2``, so the default (``False``) keeps
      it. This is the path used by ``sign_rsa2`` / ``build_order_string``.
    * Notify verification (Alipay -> us): ``sign_type`` is OUT. The sandbox
      callback signature is computed over a source string that omits
      ``sign_type``; passing ``exclude_sign_type=True`` reproduces it.

    Default ``False`` preserves the historical order-signing behaviour exactly.
    """
    parts: list[str] = []
    for key in sorted(params):
        if key == "sign" or (exclude_sign_type and key == "sign_type"):
            continue
        value = params[key]
        if value is None or value == "":
            continue
        parts.append(f"{key}={value}")
    return "&".join(parts)


def sign_rsa2(
    params: Mapping[str, str], private_key_pem: str, *, exclude_sign_type: bool = False
) -> str:
    """RSA2 (SHA256withRSA) sign a parameter mapping, return base64 signature.

    ``exclude_sign_type`` is only needed to emulate Alipay's own callback
    signing in tests; real order signing keeps the default (``sign_type`` in).
    """
    if not private_key_pem:
        raise RuntimeError("ALIPAY_APP_PRIVATE_KEY 未配置，无法签发订单")
    signature = _private_key(private_key_pem).sign(
        canonical_string(params, exclude_sign_type=exclude_sign_type).encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    return base64.b64encode(signature).decode("ascii")


def verify_rsa2(
    params: Mapping[str, str],
    public_key_pem: str,
    signature: str,
    *,
    exclude_sign_type: bool = False,
) -> bool:
    """Verify an RSA2 signature via ``canonical_string`` (see its docstring).

    For Alipay callbacks the sign source excludes ``sign_type``; callers should
    pass ``exclude_sign_type=True``. Order signing is the opposite and keeps
    ``sign_type`` in the source.
    """
    if not public_key_pem or not signature:
        return False
    try:
        _public_key(public_key_pem).verify(
            base64.b64decode(signature),
            canonical_string(params, exclude_sign_type=exclude_sign_type).encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        return True
    except (InvalidSignature, ValueError, TypeError):
        return False


def build_order_string(
    settings: Settings,
    out_trade_no: str,
    amount: str,
    subject: str = "小小葵番茄钟-永久解锁",
) -> str:
    """Build the signed ``order_string`` fed directly to the Alipay SDK.

    ``amount`` is a string and is never converted to float.
    """
    if not settings.app_id:
        raise RuntimeError("ALIPAY_APP_ID 未配置，无法签发订单")
    if not settings.notify_url:
        raise RuntimeError("NOTIFY_URL 未配置，无法签发订单")
    if not isinstance(amount, str) or not amount:
        raise ValueError("amount 必须是非空字符串")

    biz_content: dict[str, Any] = {
        "out_trade_no": out_trade_no,
        "total_amount": amount,
        "subject": subject,
        "product_code": "QUICK_MSECURITY_PAY",
    }
    params: dict[str, str] = {
        "app_id": settings.app_id,
        "method": "alipay.trade.app.pay",
        "format": "JSON",
        "charset": "utf-8",
        "sign_type": SIGN_TYPE,
        "timestamp": datetime.now(_CN_TZ).strftime("%Y-%m-%d %H:%M:%S"),
        "version": "1.0",
        "notify_url": settings.notify_url,
        "biz_content": json.dumps(biz_content, ensure_ascii=False, separators=(",", ":")),
    }
    signature = sign_rsa2(params, settings.app_private_key)
    ordered = "&".join(f"{quote(k)}={quote(v)}" for k, v in sorted(params.items()))
    return f"{ordered}&sign={quote(signature)}"


def verify_notify(params: Mapping[str, str], settings: Settings) -> bool:
    """Step 1 of notify validation: RSA2 signature with the Alipay public key.

    Business checks (app_id / amount / trade_status / seller_id) are performed
    by the endpoint, not here.
    """
    if params.get("sign_type", SIGN_TYPE) != SIGN_TYPE:
        return False
    # 回调验签的源串排除 sign_type（与下单签名相反，见 canonical_string docstring）。
    return verify_rsa2(
        params, settings.alipay_public_key, params.get("sign", ""), exclude_sign_type=True
    )
