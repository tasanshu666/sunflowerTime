#!/usr/bin/env python3
"""测量 tab 整页底图的「场景 ↔ 留白面板」分界线（C64 对齐常量的唯一来源）。

## 为什么需要
底图是「上半场景 + 下半留白」的整页图，`TabBackground` 用 `BoxFit.cover` 铺满。
平板（更宽）竖直方向要裁掉 35%~45%，必须知道**分界线在图里的归一化 y**，才能算出
「把它裁到屏幕哪个位置」的对齐值 → 常量写进 `lib/shared/tab_bg_layout.dart`。

## 判据
留白面板是**沿宽度方向色差极小**的平坦区（std 很小，仅存 JPEG/WebP 噪点），场景区
颜色变化剧烈（std 大）。故取「扫描区内**最后一个内容行**」的下方为分界线。

## ⚠️ 两个坑（2026-10-13 实测踩到）
1. **不能自下而上找「连续平坦区起点」**：today / growth 的底图**最底边有暖光晕**
   （std 30~55），自下而上第一步就判定为「内容」→ 直接返回 1.0。
2. 故改为**限定扫描区 `[0.15h, 0.80h]`** 并取最后一个 `std ≥ 阈值` 的行：下界避开
   顶部天空/墙面（大片平坦），上界避开底部光晕。

用法：`python3 tools/probe_tab_bg_panel_top.py`
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets' / 'backgrounds'

# (常量名, 文件, 扫描下界) —— 只测量「分界线」常量，源尺寸由 sips 另测。
TARGETS = [
    ('kTodayBgPanelTopFraction', 'today.webp', 0.15),
    ('kGrowthBgPanelTopFraction', 'growth.webp', 0.15),
    ('kStoreBgPanelTopFraction', 'store02.webp', 0.25),
]

# 平坦判定阈值：场景区 std 通常 > 40，留白面板 std ≈ 14~20（噪点）。
FLAT_STD = 30.0

# 扫描上界：避开底图最底边的暖光晕（today / growth 有）。
SCAN_LIMIT = 0.80


def panel_top_fraction(path: Path, scan_from: float) -> tuple[float, int, int]:
    img = Image.open(path).convert('RGB')
    arr = np.asarray(img).astype(np.float32)
    h, w, _ = arr.shape
    row_std = arr.std(axis=(1, 2))

    start = int(scan_from * h)
    limit = int(SCAN_LIMIT * h)
    last_content = start
    for y in range(start, limit):
        if row_std[y] >= FLAT_STD:
            last_content = y
    boundary = last_content + 1
    return boundary / h, boundary, h


def main() -> int:
    print(f'{"常量":32s} {"图":14s} {"尺寸":11s} {"分界 y":>7s} {"归一化":>9s}')
    for name, filename, scan_from in TARGETS:
        path = ASSETS / filename
        if not path.exists():
            print(f'!! 缺文件：{path}', file=sys.stderr)
            return 1
        frac, y, h = panel_top_fraction(path, scan_from)
        with Image.open(path) as im:
            w = im.size[0]
        print(f'{name:32s} {filename:14s} {w}x{h:<7d} {y:7d} {frac:9.4f}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
