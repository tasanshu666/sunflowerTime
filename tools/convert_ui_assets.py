#!/usr/bin/env python3
"""C44 素材入库：tab 背景 + UI 图标 → WebP（2026-10-09 玄参交付）。

输入（主工作区）：/Users/wangjunchao/WorkBuddy/sunflowerTime/assets/{backgrounds,ui}/
输出（工作树）  ：assets/backgrounds/*.webp（q88，原尺寸，整页底图）
                  assets/ui/**/*.webp（512×512 q90 透明，显示 56px @3x=168px，512 留足余量）

命名归一：snake_case（cleanUp→clean_up / defaultUI→default_ui / readBook→read_book）。
store01/store03 同步转换入库但**不登记 pubspec**（玄参拍板先用 store02，
换背景 = 改一行常量 + pubspec 登记，见 assets/backgrounds/README.txt）。
"""

from __future__ import annotations

import os
import re
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image

SRC = Path("/Users/wangjunchao/WorkBuddy/sunflowerTime/assets")
DST = Path("assets")

BG_QUALITY = 88
ICON_QUALITY = 90
ICON_SIZE = 512


def snake(name: str) -> str:
    """camelCase/PascalCase → snake_case（含 store_book 等已合规名原样通过）。"""
    if name in _SNAKE_OVERRIDES:
        return _SNAKE_OVERRIDES[name]
    s = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
    return s


# 连续大写缩写词手工修正（defaultUI 的 U/I 会被逐字母拆开）。
_SNAKE_OVERRIDES = {"defaultUI": "default_ui"}


def convert_background(path: Path) -> str:
    out = DST / "backgrounds" / (snake(path.stem) + ".webp")
    out.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(path).convert("RGB")
    im.save(out, "WEBP", quality=BG_QUALITY, method=6)
    return f"{out.name}: {im.size} {path.stat().st_size//1024}KB -> {out.stat().st_size//1024}KB"


def convert_icon(path: Path) -> str:
    rel = path.relative_to(SRC / "ui")
    out = DST / "ui" / rel.parent / (snake(path.stem) + ".webp")
    out.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(path).convert("RGBA")
    im.thumbnail((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    im.save(out, "WEBP", quality=ICON_QUALITY, method=6)
    return f"{out}: {im.size} {path.stat().st_size//1024}KB -> {out.stat().st_size//1024}KB"


def main() -> None:
    bgs = sorted((SRC / "backgrounds").glob("*.png"))
    icons = sorted((SRC / "ui").rglob("*.png"))
    with ProcessPoolExecutor() as ex:
        for line in ex.map(convert_background, bgs):
            print("BG ", line)
        for line in ex.map(convert_icon, icons):
            print("ICO", line)
    total = sum(f.stat().st_size for f in DST.rglob("*.webp"))
    print(f"\n工作树 backgrounds+ui WebP 总体积: {total/1024/1024:.1f}M")


if __name__ == "__main__":
    main()
