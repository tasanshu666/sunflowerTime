#!/usr/bin/env python3
"""花园守护 · L1 横幅背景素材转换管线（源只读，目标可重复生成）。

源（玄参 2026-11 交付，目录里唯一对应的横幅风景图）：
  /Volumes/DataHD-2TB/素材归档/专注素材/花园守护/背景图片.png
  3712×640 RGB，2.43 MB，md5 974b99795e82c7ddccc596b0263f0fec

落位：assets/guard/background.webp

口径（与 `tools/convert_guard_b5b.py` / `tools/convert_eyecare640.py` 完全一致）：
  * WebP q95、method=6 —— 项目统一「视觉无损级」压缩；
  * **不裁边、不缩放、不做 gamma**：3712×640 是完整横向风景（不是透明抠图、
    不是角色帧），实体 bbox = 整张画布；渲染端用 BoxFit.cover 按高度铺满卡，
    由卡片裁左右两侧，素材本身必须保持完整 5.8:1 比例；
  * 不透明 RGB 输入，无需保留 alpha。

实测（本机 Pillow）：q95 → 291,876 B（源 2,438,559 B 的 12.0%，PSNR 44.19dB）；
无损 WebP → 1,765,136 B（72.4%）但体积收益不足，故采用 q95。
"""

from __future__ import annotations

import hashlib
import math
import os
import sys

from PIL import Image, ImageChops

SRC = "/Volumes/DataHD-2TB/素材归档/专注素材/花园守护/背景图片.png"
DST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "guard",
    "background.webp",
)
QUALITY = 95
METHOD = 6
EXPECTED_SIZE = (3712, 640)


def md5(path: str) -> str:
    """返回文件的 MD5（用于素材验收记录）。"""
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def psnr(a: Image.Image, b: Image.Image) -> float:
    """两张同尺寸 RGB 图的峰值信噪比（dB）；完全一致返回 inf。"""
    diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    histogram = diff.histogram()
    pixel_count = a.size[0] * a.size[1] * 3
    mse = sum((index % 256) ** 2 * count for index, count in enumerate(histogram))
    mse /= pixel_count
    return math.inf if mse == 0 else 10.0 * math.log10(255.0 * 255.0 / mse)


def main() -> int:
    """转换源 PNG → WebP q95，并打印验收数据。"""
    if not os.path.isfile(SRC):
        print(f"MISS 源文件不存在：{SRC}")
        return 1

    source = Image.open(SRC)
    if source.size != EXPECTED_SIZE:
        print(f"FAIL 源尺寸 {source.size} != 预期 {EXPECTED_SIZE}")
        return 1
    source_rgb = source.convert("RGB")

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    source_rgb.save(DST, "WEBP", quality=QUALITY, method=METHOD)

    encoded = Image.open(DST).convert("RGB")
    src_bytes = os.path.getsize(SRC)
    dst_bytes = os.path.getsize(DST)
    print(f"源  {source.size[0]}×{source.size[1]}  {src_bytes:,} B  md5 {md5(SRC)}")
    print(f"出  {encoded.size[0]}×{encoded.size[1]}  {dst_bytes:,} B  md5 {md5(DST)}")
    print(f"压缩  {100.0 * dst_bytes / src_bytes:.1f}%  PSNR {psnr(source_rgb, encoded):.2f} dB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
