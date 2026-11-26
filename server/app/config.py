"""Configuration loaded from environment variables.

所有密钥只从环境变量或 600 权限的密钥文件读取，源码中没有任何硬编码密钥。
金额固定为字符串 ``"29.90"``，全程不做浮点转换（技术方案 §7）。
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

# 服务端定死的金额。必须是字符串：float("29.90") 会变成 29.899999...，
# 与支付宝回传的 "29.90" 字符串比较必然不等（技术方案 §6.3 / §7）。
AMOUNT: str = "29.90"

SANDBOX_GATEWAY: str = "https://openapi-sandbox.dl.alipaydev.com/gateway.do"
PRODUCTION_GATEWAY: str = "https://openapi.alipay.com/gateway.do"

SERVER_ROOT: Path = Path(__file__).resolve().parent.parent


def _clean(value: str | None) -> str:
    """Strip a raw environment value, treating ``None`` as an empty string."""
    return (value or "").strip()


def _as_pem(value: str) -> str:
    """Allow PEM with real newlines or with literal ``\\n`` separators in env."""
    return value.replace("\\n", "\n")


def _as_int(value: str | None, default: int) -> int:
    """Parse an integer environment value, falling back on a default."""
    raw = _clean(value)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ValueError(f"配置项需要整数，实际收到 {raw!r}") from exc


@dataclass
class Settings:
    """Immutable-by-convention runtime settings.

    Attributes mirror the keys documented in ``server/.env.example``. Kept as a
    plain dataclass (rather than pydantic-settings) to avoid an extra dependency
    and to let tests swap in an isolated database path via ``dataclasses.replace``.
    """

    app_env: str = "sandbox"
    gateway: str = SANDBOX_GATEWAY
    app_id: str = ""
    seller_id: str = ""
    app_private_key: str = ""
    sandbox_public_key: str = ""
    production_public_key: str = ""
    notify_url: str = ""
    database_path: Path = SERVER_ROOT / "data" / "server.db"
    admin_token: str = ""
    host: str = "127.0.0.1"
    port: int = 8000
    log_level: str = "info"
    order_ttl_seconds: int = 900
    create_rate_window_seconds: int = 600
    create_rate_max: int = 5
    redeem_rate_window_seconds: int = 60
    redeem_rate_max: int = 10
    amount: str = AMOUNT

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        """Build settings from ``os.environ`` or an explicit mapping."""
        source: Mapping[str, str] = os.environ if env is None else env
        app_env = _clean(source.get("APP_ENV")) or "sandbox"
        if app_env not in ("sandbox", "production"):
            raise ValueError(f"APP_ENV 只能是 sandbox 或 production，收到 {app_env!r}")

        default_gateway = SANDBOX_GATEWAY if app_env == "sandbox" else PRODUCTION_GATEWAY

        private_key = _as_pem(_clean(source.get("ALIPAY_APP_PRIVATE_KEY")))
        key_path = _clean(source.get("ALIPAY_APP_PRIVATE_KEY_PATH"))
        if key_path and not private_key:
            private_key = Path(key_path).read_text(encoding="utf-8").strip()

        db_path = Path(_clean(source.get("DATABASE_PATH")) or str(SERVER_ROOT / "data" / "server.db"))
        if not db_path.is_absolute():
            db_path = SERVER_ROOT / db_path

        return cls(
            app_env=app_env,
            gateway=_clean(source.get("ALIPAY_GATEWAY")) or default_gateway,
            app_id=_clean(source.get("ALIPAY_APP_ID")),
            seller_id=_clean(source.get("ALIPAY_SELLER_ID")),
            app_private_key=private_key,
            sandbox_public_key=_as_pem(_clean(source.get("ALIPAY_SANDBOX_PUBLIC_KEY"))),
            production_public_key=_as_pem(_clean(source.get("ALIPAY_PRODUCTION_PUBLIC_KEY"))),
            notify_url=_clean(source.get("NOTIFY_URL")),
            database_path=db_path,
            admin_token=_clean(source.get("ADMIN_TOKEN")),
            host=_clean(source.get("HOST")) or "127.0.0.1",
            port=_as_int(source.get("PORT"), 8000),
            log_level=_clean(source.get("LOG_LEVEL")) or "info",
            order_ttl_seconds=_as_int(source.get("ORDER_TTL_SECONDS"), 900),
            create_rate_window_seconds=_as_int(source.get("CREATE_RATE_WINDOW_SECONDS"), 600),
            create_rate_max=_as_int(source.get("CREATE_RATE_MAX"), 5),
            redeem_rate_window_seconds=_as_int(source.get("REDEEM_RATE_WINDOW_SECONDS"), 60),
            redeem_rate_max=_as_int(source.get("REDEEM_RATE_MAX"), 10),
            amount=AMOUNT,
        )

    @property
    def is_sandbox(self) -> bool:
        """Return True when running against the Alipay sandbox gateway."""
        return self.app_env == "sandbox"

    @property
    def alipay_public_key(self) -> str:
        """The Alipay public key for the *current* environment only.

        沙箱与生产的支付宝公钥不同，这里按 APP_ENV 严格择一，杜绝串用。
        """
        return self.sandbox_public_key if self.is_sandbox else self.production_public_key
