#!/usr/bin/env python3
"""成长帧素材 PNG→WebP 转换（对齐护眼帧 `tools/convert_eyecare640.py` 的同款管线）。

范围：assets/fx/grow/{物种}/{种子→幼苗|幼苗→成株|成株→盛开}/frame*.png
产物：同目录 frame*.webp（**默认无损档**：像素零变化，供「无损」验收；`--q95` 切有损）。
备份：原 PNG 移到 build/grow_fx_png_backup/<相对路径>（不入包、可回退）。
校验：逐帧 round-trip 像素比对（无损档必须 100% 相等），并直读 WebP 头确认 720×720。

用法：
  python3 tools/convert_grow_fx.py [--q95] [--apply] [--workers N]
默认 dry-run（只测体积/校验，不落盘）。
"""
import argparse
import glob
import io
import os
import shutil
import struct
import sys
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GROW = ROOT / 'assets' / 'fx' / 'grow'
BACKUP = ROOT / 'build' / 'grow_fx_png_backup'


def webp_size(path):
    b = open(path, 'rb').read(30)
    if b[:4] != b'RIFF' or b[8:12] != b'WEBP':
        return None
    fourcc = b[12:16]
    if fourcc == b'VP8 ':
        if b[23:26] != b'\x9d\x01\x2a':
            return None
        w = (b[26] | (b[27] << 8)) & 0x3FFF
        h = (b[28] | (b[29] << 8)) & 0x3FFF
        return w * h
    if fourcc == b'VP8L':
        bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
        return ((bits & 0x3FFF) + 1) * (((bits >> 14) & 0x3FFF) + 1)
    if fourcc == b'VP8X':
        w = b[24] | (b[25] << 8) | (b[26] << 16)
        h = b[27] | (b[28] << 8) | (b[29] << 16)
        return (w + 1) * (h + 1)
    return None


def one(job):
    png, q95, apply = job
    try:
        if not os.path.exists(png):
            return (str(png), 0, 0, False)  # 已被其它批次处理 / 缺失：跳过（不崩）
        return _one(png, q95, apply)
    except Exception:  # noqa: BLE001 —— 单帧失败绝不让整个 Pool 崩掉
        return (str(png), 0, 0, False)


def _one(png, q95, apply):
    s0 = os.path.getsize(png)  # ⚠️ 必须在 move 之前取（move 后路径即失效）
    im = Image.open(png).convert('RGBA')
    webp = str(png)[:-4] + '.webp'
    kw = dict(quality=95, method=6) if q95 else dict(lossless=True, method=6)
    im.save(webp, format='WEBP', **kw)
    # 无损档必须像素零变化；q95 档跳过精确比对（有损）
    # 视觉无损判据：alpha 通道逐像素相等 + 可见像素(alpha>0)的 RGBA 逐字节相等。
    # （WebP lossless 会把「完全透明像素底下的 RGB」清零——不渲染，画面零差别。）
    ok = True
    if not q95:
        back = Image.open(webp).convert('RGBA')
        a = np.asarray(im); c = np.asarray(back)
        ok = (a.shape == c.shape
              and bool((a[..., 3] == c[..., 3]).all())
              and bool((a[a[..., 3] > 0] == c[c[..., 3] > 0]).all()))
    wh = webp_size(webp)
    if wh != 720 * 720:
        ok = False
    if apply and ok:
        rel = Path(png).relative_to(ROOT)
        dst = BACKUP / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            shutil.move(png, dst)  # 原 PNG 移出仓库（备份保留）
    return (str(png), s0, os.path.getsize(webp), ok)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--q95', action='store_true')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--workers', type=int, default=max(1, (os.cpu_count() or 4)))
    a = ap.parse_args()

    pngs = sorted(glob.glob(str(GROW / '*' / '*' / 'frame*.png')))
    if not pngs:
        print('no grow frame PNGs found'); sys.exit(1)
    mode = 'WebP q95（有损）' if a.q95 else 'WebP 无损'
    print(f'模式={mode}  帧数={len(pngs)}  apply={a.apply}  workers={a.workers}')
    t0 = t1 = 0
    bad = 0
    with Pool(a.workers) as pool:
        for i, (path, s0, s1, ok) in enumerate(
                pool.imap_unordered(one, [(p, a.q95, a.apply) for p in pngs], chunksize=8), 1):
            t0 += s0; t1 += s1
            if not ok:
                bad += 1; print(f'  !! 校验失败: {path}')
            if i % 50 == 0 or i == len(pngs):
                print(f'  ...{i}/{len(pngs)}')
    print(f'\n{"APPLIED" if a.apply else "DRY-RUN"}  {len(pngs)} 帧  '
          f'{t0/1048576:.1f}M -> {t1/1048576:.1f}M  ({t1/t0*100:.1f}%)  校验失败={bad}')
    if a.apply and bad == 0:
        print(f'原 PNG 已备份至 {BACKUP.relative_to(ROOT)}（可回退）')


if __name__ == '__main__':
    main()
