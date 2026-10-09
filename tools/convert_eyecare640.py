#!/usr/bin/env python3
"""护眼 640 帧素材 PNG→WebP 转换 + A/B 对比（2026-10-09 C43，玄参新素材查收）。

输入：主工作区 assets/fx/focus/sunflower/eyecare640/（玄参交付，640 张 720×720 PNG）
输出：
  1. q95 有损 → assets/fx/eyecare640/frameNNN.webp（最终库内位置）
  2. 无损   → build/eyecare640_lossless/frameNNN.webp（宠物管线节奏的 A/B 验证用）
  3. 对比拼板 build/eyecare640_ab.png（抽样 8 帧 × 3 列：原 PNG / 无损 / q95）
  4. 终端统计：体积、PSNR（RGBA 合成到白底后按 RGB 计算）

用法：
  python3 tools/convert_eyecare640.py [--src DIR] [--dst DIR]
"""

import argparse
import math
import multiprocessing as mp
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

Q95 = dict(quality=95, method=6)
# 工作树/主工作区两用：默认相对本脚本定位仓库根
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path("/Users/wangjunchao/WorkBuddy/sunflowerTime/assets/fx/focus/sunflower/eyecare640")
DST_Q95 = ROOT / "assets" / "fx" / "eyecare640"  # 由 --dst 覆盖
DST_LOSSLESS = ROOT / "build" / "eyecare640_lossless"


def convert_one(job):
    src, dst_q95, dst_ll = job
    im = Image.open(src)
    name = src.stem + ".webp"
    out = {}
    if dst_ll is not None:
        p = dst_ll / name
        im.save(p, lossless=True, method=6)
        out["ll"] = p.stat().st_size
    im.save(dst_q95 / name, **Q95)
    out["q95"] = (dst_q95 / name).stat().st_size
    out["png"] = src.stat().st_size
    return out


def psnr(a: Image.Image, b: Image.Image) -> float:
    """RGBA 合成白底后按 RGB 计算 PSNR（dB）。"""
    a = a.convert("RGBA")
    b = b.convert("RGBA")
    bg = Image.new("RGB", a.size, (255, 255, 255))
    bg.paste(a, mask=a.split()[-1])
    bg2 = Image.new("RGB", b.size, (255, 255, 255))
    bg2.paste(b, mask=b.split()[-1])
    import numpy as np
    x = np.asarray(bg, dtype=np.float64)
    y = np.asarray(bg2, dtype=np.float64)
    mse = ((x - y) ** 2).mean()
    if mse == 0:
        return float("inf")
    return 10 * math.log10(255 * 255 / mse)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    ap.add_argument("--dst", default=str(ROOT / "assets" / "fx" / "eyecare640"))
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    src = Path(args.src)
    dst_q95 = Path(args.dst)
    dst_ll = DST_LOSSLESS
    frames = sorted(src.glob("frame*.png"))
    if not frames:
        print(f"ERROR: no frames in {src}")
        sys.exit(1)
    dst_q95.mkdir(parents=True, exist_ok=True)
    dst_ll.mkdir(parents=True, exist_ok=True)
    print(f"src={src} frames={len(frames)}")
    print(f"dst(q95)={dst_q95}  dst(lossless)={dst_ll}")

    jobs = [(f, dst_q95, dst_ll) for f in frames]
    totals = {"png": 0, "ll": 0, "q95": 0}
    with mp.Pool(args.workers) as pool:
        for i, r in enumerate(pool.imap_unordered(convert_one, jobs, chunksize=16)):
            for k in totals:
                totals[k] += r[k]
            if (i + 1) % 128 == 0:
                print(f"  {i + 1}/{len(jobs)} done")

    print("\n=== 体积统计 ===")
    print(f"PNG 原始     : {totals['png'] / 1048576:8.1f} M")
    print(f"WebP 无损    : {totals['ll'] / 1048576:8.1f} M  ({totals['ll'] / totals['png'] * 100:.1f}%)")
    print(f"WebP q95     : {totals['q95'] / 1048576:8.1f} M  ({totals['q95'] / totals['png'] * 100:.1f}%)")

    # 抽样 PSNR（均匀 8 帧）+ 拼板
    sample_idx = [round(i * (len(frames) - 1) / 7) for i in range(8)]
    font = None
    for cand in ("/System/Library/Fonts/PingFang.ttc",):
        if Path(cand).exists():
            font = ImageFont.truetype(cand, 18)
    cols = [("原 PNG", lambda p: Image.open(p)),
            ("WebP 无损", lambda p: Image.open(dst_ll / (p.stem + ".webp"))),
            ("WebP q95", lambda p: Image.open(dst_q95 / (p.stem + ".webp")))]
    cw, pad = 300, 10
    with Image.open(frames[0]) as _im0:
        ch = round(cw * _im0.height / _im0.width)
    board = Image.new("RGB", (3 * (cw + pad) + pad,
                              len(sample_idx) * (ch + 34 + pad) + pad), (255, 255, 255))
    d = ImageDraw.Draw(board)
    print("\n=== 抽样质量（PSNR dB，对原 PNG）===")
    for r, fi in enumerate(sample_idx):
        f = frames[fi]
        for c, (label, loader) in enumerate(cols):
            im = loader(f).resize((cw, ch))
            x = pad + c * (cw + pad)
            y = pad + r * (ch + 34 + pad)
            board.paste(im, (x, y), im.convert("RGBA"))
            d.text((x + cw // 2, y + ch + 16), f"{label}", fill=(90, 85, 75),
                   font=font, anchor="mm")
        p_ll = psnr(Image.open(f), Image.open(dst_ll / (f.stem + ".webp")))
        p_q = psnr(Image.open(f), Image.open(dst_q95 / (f.stem + ".webp")))
        print(f"frame{f.stem[5:]}: 无损 {p_ll:6.2f} | q95 {p_q:6.2f}")

    out = ROOT / "build" / "eyecare640_ab.png"
    board.save(out)
    print(f"\n拼板图: {out}")


if __name__ == "__main__":
    main()
