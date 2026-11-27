#!/usr/bin/env python3
"""雪方位图（3 张）+ 家长天地入口图标 PNG → WebP q95（2026-11-27 玄参交付）。

## 管线口径（复用 tools/convert_assets_webp.py，不自创规则）

* `quality=95, method=6`，**RGBA 编码**：libwebp 有损档的 alpha 子块无损，
  透明边缘不会出现白边 / 黑边；逐张校验输出仍有透明区（alpha min == 0）。
* **等比缩放 + 透明方形画布居中**：源图非正方（1295×1334 等），
  直接拉成正方会让雪花变形 ~3%；按最长边缩到目标边长再居中贴透明画布。
  目标尺寸按「显示尺寸 × 3 倍屏」留余量：雪花最大 20pt → 256px、
  入口图标 28dp → 128px。
* **雪花漂白（2026-11-27 玄参一轮反馈）**：源图 RGB 均值 189~238 偏灰蓝，
  在黄绿草地上看着像灰片。转 WebP 前把 RGB 向纯白插值 70%（alpha 原样保留
  ⇒ 形状、层次、透明边缘逐位不变）。家长图标不漂白（保留原配色）。
* **原 PNG 不删除**：复制到 `assets/_originals/ui_snow_batch_2026_11/`
  （该目录被 .gitignore 忽略且不在 pubspec 声明里 ⇒ 不进包），
  外置盘素材归档保持原样。

## 用法

```bash
python3 tools/convert_snow_parent_ui.py
```
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = Path("/Volumes/DataHD-2TB/素材归档/专注素材/花园/雪花UI")
BACKUP = ROOT / "assets/_originals/ui_snow_batch_2026_11"

# (源文件名, 相对 assets 的目标 WebP 路径, 正方形边长, 向白色插值比例)
# 🔴 雪花 0.72：源图偏灰蓝（RGB 均值 189~238），插值后接近纯白且保留形状层次。
#    家长图标 0.0：配色原样保留（反馈要去掉的是代码里的白胶囊，不是素材配色）。
JOBS = (
    ("雪花01(1)_1.png", "assets/fx/snow/snow_01.webp", 256, 0.72),
    ("雪花02(1)_1.png", "assets/fx/snow/snow_02.webp", 256, 0.72),
    ("雪花03(1)_1.png", "assets/fx/snow/snow_03.webp", 256, 0.72),
    ("家长天地UI(1)_1.png", "assets/ui/parent_hub.webp", 128, 0.0),
)


def whiten_rgba(im: Image.Image, ratio: float) -> Image.Image:
    """把 RGB 向纯白插值 ``ratio``，alpha 通道逐字节不动。

    只改颜色不改形状：雪花源图偏灰蓝（玄参 11-27「不够白」反馈），
    插值后接近纯白但明暗层次仍在；透明边缘的 alpha 保持原样，
    不会出现白边 / 灰边。
    """
    if ratio <= 0.0:
        return im
    r, g, b, a = im.split()
    lut = [round(v + (255 - v) * ratio) for v in range(256)]
    return Image.merge(
        "RGBA", (r.point(lut), g.point(lut), b.point(lut), a)
    )


def convert_one(name: str, rel: str, side: int, whiten: float) -> None:
    src = SRC / name
    if not src.exists():
        raise FileNotFoundError(f"源素材不存在：{src}")

    out = ROOT / rel
    out.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(src) as opened:
        im = opened.convert("RGBA")
        im.thumbnail((side, side), Image.LANCZOS)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        canvas = whiten_rgba(canvas, whiten)
        canvas.save(out, format="WEBP", quality=95, method=6)

    with Image.open(out) as check:
        assert check.size == (side, side), f"尺寸不符：{out}"
        alpha_min, alpha_max = check.getchannel("A").getextrema()
        assert alpha_min == 0, f"透明区丢失：{out}"

    backup = BACKUP / name
    if not backup.exists() or backup.read_bytes() != src.read_bytes():
        BACKUP.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, backup)

    print(
        f"{name}: {Image.open(src).size} -> {side}x{side} "
        f"{out.stat().st_size / 1024:.1f} KiB  {rel}"
    )


def main() -> None:
    for name, rel, side, whiten in JOBS:
        convert_one(name, rel, side, whiten)
    total = sum((ROOT / rel).stat().st_size for _, rel, _, _ in JOBS)
    print(f"4 张合计 {total / 1024:.1f} KiB；原 PNG 已归档到 {BACKUP}")


if __name__ == "__main__":
    main()
