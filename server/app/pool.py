"""Offline pre-signed code pool import and status queries.

Codes are generated on the developer's own machine with
``tool/issue_redeem_code.dart --out <path>``. The signing private key NEVER
appears on this server; only finished codes are imported here.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import db


@dataclass
class ImportResult:
    """Outcome of an idempotent pool import."""

    inserted: int = 0
    skipped: int = 0
    total: int = 0


def load_codes(json_path: str | Path) -> list[tuple[int, str]]:
    """Read and validate ``[{"serial": 1001, "code": "AQAA..."}, ...]``."""
    path = Path(json_path)
    with path.open("r", encoding="utf-8") as handle:
        payload: Any = json.load(handle)
    if not isinstance(payload, list):
        raise ValueError("码池 JSON 顶层必须是数组")

    codes: list[tuple[int, str]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise ValueError(f"码池 JSON 第 {index} 项不是对象")
        serial = item.get("serial")
        code = item.get("code")
        if not isinstance(serial, int) or isinstance(serial, bool) or serial <= 0:
            raise ValueError(f"码池 JSON 第 {index} 项 serial 非法: {serial!r}")
        if not isinstance(code, str) or not code.strip():
            raise ValueError(f"码池 JSON 第 {index} 项 code 非法")
        codes.append((serial, code.strip()))
    return codes


def import_pool(json_path: str | Path, db_path: str | Path | None = None) -> ImportResult:
    """Insert codes with ``INSERT OR IGNORE`` so re-import is a no-op.

    A duplicate serial OR a duplicate code is silently skipped; no available
    code is ever consumed or overwritten by a repeat import.
    """
    codes = load_codes(json_path)
    db.init_db(db_path)
    result = ImportResult()
    with db.connection(db_path) as conn:
        with db.transaction(conn):
            for serial, code in codes:
                cur = conn.execute(
                    "INSERT OR IGNORE INTO code_pool(serial, code, status) VALUES(?, ?, 'available')",
                    (serial, code),
                )
                if cur.rowcount == 1:
                    result.inserted += 1
                else:
                    result.skipped += 1
            result.total = int(conn.execute("SELECT COUNT(*) FROM code_pool").fetchone()[0])
    return result


def available_count(conn: Any) -> int:
    """Return the number of unissued codes on an existing connection."""
    return int(conn.execute("SELECT COUNT(*) FROM code_pool WHERE status='available'").fetchone()[0])


def pool_status(db_path: str | Path | None = None) -> dict[str, int]:
    """Return aggregate counts only — never any code content."""
    db.init_db(db_path)
    with db.connection(db_path) as conn:
        row = conn.execute(
            "SELECT "
            "SUM(CASE WHEN status='available' THEN 1 ELSE 0 END) AS available, "
            "SUM(CASE WHEN status='issued'   THEN 1 ELSE 0 END) AS issued, "
            "COUNT(*) AS total "
            "FROM code_pool"
        ).fetchone()
    return {
        "available": int(row["available"] or 0),
        "issued": int(row["issued"] or 0),
        "total": int(row["total"] or 0),
    }


def _main(argv: list[str]) -> int:
    """Tiny CLI used by operations: ``pool.py import <json>`` / ``pool.py status``."""
    parser = argparse.ArgumentParser(description="离线码池运维工具")
    sub = parser.add_subparsers(dest="command", required=True)
    importer = sub.add_parser("import", help="导入码池 JSON（可重复执行）")
    importer.add_argument("json_path")
    importer.add_argument("--db", default=None)
    status_parser = sub.add_parser("status", help="查询码池余量")
    status_parser.add_argument("--db", default=None)
    args = parser.parse_args(argv)

    if args.command == "import":
        result = import_pool(args.json_path, args.db)
        print(f"imported={result.inserted} skipped={result.skipped} total={result.total}")
    else:
        print(json.dumps(pool_status(args.db), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
