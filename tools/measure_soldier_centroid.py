#!/usr/bin/env python3
"""守卫战 · 战士三态素材的 **alpha 加权质心 x** 量测（B11/C4）。

## 为什么需要它
战士三态（待机 19 帧 / 攻击 / 胜利）是**各自裁到自己的实体框**的：
攻击帧的实体框里除了身体还有**挥出去的兵器**（512 宽，比待机 362 宽 41%），
`BoxFit.fitHeight` 再**居中**放进绘制框时，身体就被推离中轴约 10~15pt ⇒
玄参第六轮报的「攻击时人往左挪了一点」。

居中永远对不齐 —— 因为待机身体中心与攻击身体中心在各自画布里的**位置本来就不同**
（配准差在素材里，不在定位公式里）。修法 = 按**身体质心**对齐（而不是按实体框居中）：
量每个状态的 alpha 加权质心 x，落成常量表，绘制时按「质心 → 绘制框中轴」位移。

## 量法（可复算）
* 判实体：`alpha > 128`（与 `tools/convert_guard_b5b.py` / 素材记录 §1 同口径）；
* 权重 = `alpha`（不是二值掩码 —— 半透明描边按比例计入，避免边缘噪声主导）；
* `cx_px = Σ(x · alpha) / Σ(alpha)`（x 取像素中心 `i + 0.5`）；
* 归一化 `fx = cx_px / W`（0 = 素材左缘、1 = 右缘）；再换到 **512 参考画布**
  `cx_512 = fx × 512`（三种状态画布宽不同，只有归一化/512 参考才可比）；
* 待机 = **19 帧 cx 的算术平均**（玄参口径「idle 19 帧取平均」）。

## 用法
```bash
python3 tools/measure_soldier_centroid.py            # 打印表格
python3 tools/measure_soldier_centroid.py --json     # 机器可读（贴常量表用）
```

🔴 **换素材（改名 / 重导 / 重裁）必须重跑本脚本 + 更新
`kGuardSoldierStateCentroidX` + 重跑 `test/guard/guard_soldier_state_align_test.dart`。**
该测试会独立重算质心（Dart 侧）并与常量表比对，常量过期即红。
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("需要 Pillow：pip install pillow", file=sys.stderr)
    raise

ALPHA_THRESHOLD = 128
CANVAS_REF = 512.0
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD_DIR = os.path.join(ROOT, "assets", "guard")


def centroid_x(path: str) -> tuple[float, int, int, int]:
    """返回 (cx_px, W, H, mass)。mass = Σalpha（用来发现空图）。"""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    alpha = im.split()[3].load()
    total = 0
    weighted = 0.0
    for y in range(h):
        for x in range(w):
            a = alpha[x, y]
            if a <= ALPHA_THRESHOLD:
                continue
            total += a
            weighted += (x + 0.5) * a
    if total == 0:
        raise SystemExit(f"空图（alpha 全 <= {ALPHA_THRESHOLD}）：{path}")
    return weighted / total, w, h, total


def measure() -> dict:
    out: dict = {}

    idle_files = sorted(glob.glob(os.path.join(GUARD_DIR, "soldier_idle", "frame*.webp")))
    if not idle_files:
        raise SystemExit("找不到 assets/guard/soldier_idle/frame*.webp")
    cxs = []
    sizes = set()
    for path in idle_files:
        cx, w, h, _ = centroid_x(path)
        # 归一化后再平均：19 帧画布尺寸相同，等价于 px 平均，但口径更稳。
        cxs.append(cx / w)
        sizes.add((w, h))
    if len(sizes) != 1:
        raise SystemExit(f"待机帧画布尺寸不一致：{sizes}")
    w, h = sizes.pop()
    out["idle"] = {
        "frames": len(idle_files),
        "w": w,
        "h": h,
        "fx": sum(cxs) / len(cxs),
        "aspect": w / h,
    }

    for key, name in (("stand", "soldier_stand.webp"), ("attack", "soldier_attack.webp"), ("win", "soldier_win.webp")):
        path = os.path.join(GUARD_DIR, name)
        if not os.path.exists(path):
            raise SystemExit(f"找不到 {path}")
        cx, w, h, _ = centroid_x(path)
        out[key] = {"frames": 1, "w": w, "h": h, "fx": cx / w, "aspect": w / h}

    for key, item in out.items():
        item["cx_px"] = item["fx"] * item["w"]
        item["cx_512"] = item["fx"] * CANVAS_REF
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="机器可读输出")
    args = ap.parse_args()

    data = measure()
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    print(f"{'状态':<8}{'画布':<12}{'质心 px':>10}{'归一化 fx':>12}{'512 参考':>10}{'宽高比':>9}")
    print("-" * 64)
    for key in ("idle", "stand", "attack", "win"):
        it = data[key]
        print(
            f"{key:<8}{f'{it[chr(119)]}x{it[chr(104)]}':<12}"
            f"{it['cx_px']:>10.2f}{it['fx']:>12.4f}{it['cx_512']:>10.2f}{it['aspect']:>9.4f}"
        )
    print("-" * 64)
    idle = data["idle"]
    for key in ("stand", "attack", "win"):
        d = data[key]
        print(
            f"质心差 {key} − idle = {(d['fx'] - idle['fx']) * 100:+.2f}% 画布宽"
            f"（= {(d['fx'] * d['w']) - (idle['fx'] * idle['w']):+.2f}px 不归一）"
        )
    print(
        "\n→ 常量表（`kGuardSoldierStateCentroidX`）：\n"
        + "\n".join(
            f"  '{key}': {data[key]['fx']:.4f}," for key in ("idle", "attack", "win")
        )
    )


if __name__ == "__main__":
    main()
