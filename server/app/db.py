"""SQLite schema and connection helpers.

Schema is copied verbatim from 技术方案 §7 (with ``IF NOT EXISTS`` added so that
``init_db`` is safe to call on every boot).
"""

from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from .config import SERVER_ROOT

SCHEMA_SQL: str = """
CREATE TABLE IF NOT EXISTS orders (
  out_trade_no    TEXT PRIMARY KEY,
  claim_token     TEXT NOT NULL,
  device_hash     TEXT,
  app_version     TEXT,
  amount          TEXT NOT NULL,
  status          TEXT NOT NULL,
  alipay_trade_no TEXT,
  gmt_payment     TEXT,
  redeem_code     TEXT,
  serial          INTEGER,
  created_at      TEXT NOT NULL,
  paid_at         TEXT,
  issued_at       TEXT
);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_trade  ON orders(alipay_trade_no);

CREATE TABLE IF NOT EXISTS code_pool (
  serial       INTEGER PRIMARY KEY,
  code         TEXT NOT NULL UNIQUE,
  status       TEXT NOT NULL,
  out_trade_no TEXT,
  issued_at    TEXT
);
CREATE INDEX IF NOT EXISTS idx_pool_status ON code_pool(status);
"""


def default_db_path() -> Path:
    """Resolve the database path from env, relative to the server directory."""
    raw = (os.environ.get("DATABASE_PATH") or "").strip()
    path = Path(raw) if raw else SERVER_ROOT / "data" / "server.db"
    return path if path.is_absolute() else SERVER_ROOT / path


def get_conn(path: str | Path | None = None) -> sqlite3.Connection:
    """Open a connection with WAL + busy timeout.

    ``isolation_level=None`` puts sqlite3 in autocommit mode; write paths that
    need atomicity must wrap their statements in :func:`transaction`.
    """
    target = Path(path) if path is not None else default_db_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(target), timeout=10.0, isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(path: str | Path | None = None) -> None:
    """Create schema if missing. Safe to call repeatedly."""
    with get_conn(path) as conn:
        conn.executescript(SCHEMA_SQL)


@contextmanager
def connection(path: str | Path | None = None) -> Iterator[sqlite3.Connection]:
    """Yield a connection and always close it."""
    conn = get_conn(path)
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """Run a block inside a single write transaction.

    ``BEGIN IMMEDIATE`` takes the write lock up front, so two concurrent redeem
    requests cannot both observe an unissued order and then both claim a code.
    """
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield conn
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")


def utc_now() -> str:
    """Return a sortable UTC timestamp in ISO-8601 ``Z`` form."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
