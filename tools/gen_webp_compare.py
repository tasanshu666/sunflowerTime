#!/usr/bin/env python3
"""素材瘦身（PNG→WebP q95）**前后对比图**生成器（2026-11-25 装包体积治理批）。

给负责人目视验收画质用：每组一张拼板，左「原 PNG」右「WebP q95」，含

* 全图缩略对照（看整体色调 / 构图有无漂移）；
* **1:1 像素局部放大**（默认 2~3 倍近邻放大，压在棋盘格上看透明边缘有无
  白边 / 黑边 / 色晕）；
* 顶部信息条：画布尺寸、前后体积、压缩比、alpha 加权 PSNR。

数据来源（都是仓库内已存在的文件，本脚本**只读**）：

* 原图：`assets/_originals/png_webp_batch_2026_11/<相对 assets 的路径>.png`
* 转后：`assets/<相对 assets 的路径>.webp`

用法：

```bash
python3 tools/gen_webp_compare.py          # 生成 docs/素材瘦身对比/*.png
```
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
BACKUP = ASSETS / "_originals" / "png_webp_batch_2026_11"
OUT_DIR = ROOT / "docs" / "素材瘦身对比"

# ── 版面常量 ────────────────────────────────────────────────────────────────
CANVAS_W = 1440          # 画布宽
PAD = 24                 # 外边距 / 元素间距
HEADER_H = 128           # 顶部信息条高（标题 + 两行元信息）
COL_W = (CANVAS_W - PAD * 3) // 2   # 单列内容宽
LABEL_H = 34             # 每块图下方标签行高
BG = (250, 249, 246)     # 米白底（与项目 UI 暖调一致）
INK = (74, 62, 52)       # 深棕正文
SUB = (140, 126, 112)    # 次级文字
CHECK_A = (255, 255, 255)
CHECK_B = (214, 211, 206)
TITLE = "sunflowerTime 素材瘦身 · PNG → WebP q95 画质对照"


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """挑一个**有中文字形**的系统字体。

    ⚠️ 本机没有 `/System/Library/Fonts/PingFang.ttc`（实测 `OSError: cannot open
    resource`）。若回退到 `ImageFont.load_default()`（Aileron），中文会全渲染成
    方框 □ —— 首版拼板就踩了这个坑。故按 Hiragino Sans GB（本机实测可用）→
    Songti SC → PingFang → Helvetica 顺序探测，**只在全部失败时**才用默认字体。
    """
    candidates = (
        ["/System/Library/Fonts/Hiragino Sans GB.ttc",
         "/System/Library/Fonts/Supplemental/Songti.ttc",
         "/System/Library/Fonts/PingFang.ttc",
         "/System/Library/Fonts/Helvetica.ttc"]
        if not bold else
        ["/System/Library/Fonts/Hiragino Sans GB.ttc",
         "/System/Library/Fonts/Supplemental/Songti.ttc",
         "/System/Library/Fonts/PingFang.ttc",
         "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
         "/System/Library/Fonts/Helvetica.ttc"]
    )
    for cand in candidates:
        if Path(cand).exists():
            try:
                return ImageFont.truetype(cand, size)
            except OSError:
                continue
    print("⚠️ 未找到可用的中文字体，拼板中文可能显示为方框")
    return ImageFont.load_default()


def checker(w: int, h: int, cell: int = 10) -> Image.Image:
    """棋盘格底（看 alpha 边缘用）。"""
    im = Image.new("RGB", (w, h), CHECK_A)
    d = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=CHECK_B)
    return im


def alpha_weighted_psnr(ref: Image.Image, out: Image.Image) -> float:
    """按 alpha 加权的 RGB PSNR（dB）；与 tools/convert_assets_webp.py 同式。"""
    a = np.asarray(ref.convert("RGBA"))
    b = np.asarray(out.convert("RGBA"))
    w = a[:, :, 3].astype(np.float64) / 255.0
    total_w = float(w.sum()) * 3.0
    if total_w <= 0:
        return float("inf")
    diff = a[:, :, :3].astype(np.float64) - b[:, :, :3].astype(np.float64)
    mse = float((diff * diff * w[:, :, None]).sum() / total_w)
    if mse == 0:
        return float("inf")
    return 10.0 * math.log10(255.0 * 255.0 / mse)


def fit(im: Image.Image, box_w: int, box_h: int) -> Image.Image:
    """等比缩到框内（LANCZOS），不放大。"""
    scale = min(box_w / im.width, box_h / im.height, 1.0)
    if scale >= 1.0:
        return im
    return im.resize(
        (max(1, round(im.width * scale)), max(1, round(im.height * scale))),
        Image.LANCZOS,
    )


def paste_alpha(canvas: Image.Image, im: Image.Image, xy: tuple[int, int]) -> None:
    """把带 alpha 的图合成到 RGB 画布（用自身 alpha 作蒙版）。"""
    rgba = im.convert("RGBA")
    canvas.paste(rgba, xy, rgba)


def row_h_for(im: Image.Image, col_w: int) -> int:
    """全图缩略行高度（由较高的一列决定）。"""
    return round(col_w * im.height / im.width)


def build_board(
    rel: str,
    title_note: str,
    zoom_box: tuple[int, int, int, int],
    zoom: int,
) -> Path:
    """生成一张「原 PNG × WebP q95」对照拼板。"""
    png_path = BACKUP / f"{rel}.png"
    webp_path = ASSETS / f"{rel}.webp"
    for p in (png_path, webp_path):
        if not p.exists():
            raise FileNotFoundError(f"缺文件：{p}")

    src = Image.open(png_path).convert("RGBA")
    out = Image.open(webp_path).convert("RGBA")
    if src.size != out.size:
        raise ValueError(f"{rel}: 尺寸不一致 {src.size} vs {out.size}")

    png_b = png_path.stat().st_size
    webp_b = webp_path.stat().st_size
    psnr = alpha_weighted_psnr(src, out)

    # ── 全图缩略行 ──
    thumb = fit(src, COL_W, 10 ** 6)
    full_h = thumb.height

    # ── 1:1 局部放大行 ──
    z = src.crop(zoom_box)
    zw, zh = round(z.width * zoom), round(z.height * zoom)
    z_scale = min(1.0, COL_W / zw)
    zw, zh = max(1, round(zw * z_scale)), max(1, round(zh * z_scale))

    total_h = HEADER_H + PAD + (full_h + LABEL_H) + PAD + (zh + LABEL_H) + PAD
    canvas = Image.new("RGB", (CANVAS_W, total_h), BG)
    d = ImageDraw.Draw(canvas)
    f_title = load_font(26, bold=True)
    f_meta = load_font(19)
    f_label = load_font(20, bold=True)
    f_small = load_font(17)

    # ── 顶部信息条 ──
    d.text((PAD, 18), TITLE, fill=INK, font=f_title)
    keep = webp_b / png_b * 100.0
    # ⚠️ 一律用 ASCII `-` 而不是 U+2212 `−`：Hiragino Sans GB 缺该码位，
    # 会渲染成方框（首版实测）。同理避免 →、×以外的冷门符号。
    meta1 = (f"{rel}   ·   画布 {src.width}×{src.height}"
             f"   ·   alpha 加权 PSNR = {psnr:.2f} dB")
    meta2 = (f"{png_b / 1024:.0f} KB -> {webp_b / 1024:.0f} KB"
             f"   ·   省 {(1 - webp_b / png_b) * 100:.1f}%"
             f"（保留 {keep:.1f}%）")
    d.text((PAD, 52), meta1, fill=SUB, font=f_meta)
    d.text((PAD, 78), meta2, fill=SUB, font=f_meta)
    d.line([(PAD, HEADER_H - 8), (CANVAS_W - PAD, HEADER_H - 8)], fill=(228, 224, 217))

    cols = (
        (f"原 PNG   {png_b / 1024:.0f} KB", src),
        (f"WebP q95   {webp_b / 1024:.0f} KB   (省 {(1 - webp_b / png_b) * 100:.1f}%)", out),
    )

    y = HEADER_H + PAD - 8

    # ── 第 1 行：全图 ──
    for i, (label, im) in enumerate(cols):
        x = PAD + i * (COL_W + PAD)
        box = Image.new("RGB", (COL_W, full_h), (243, 241, 236))
        t = fit(im, COL_W, full_h)
        ox = (COL_W - t.width) // 2
        oy = (full_h - t.height) // 2
        paste_alpha(box, t, (ox, oy))
        canvas.paste(box, (x, y))
        d.text((x + COL_W // 2, y + full_h + 8), label, fill=INK,
               font=f_label, anchor="ma")
    y += full_h + LABEL_H + PAD

    # ── 第 2 行：1:1 局部放大（棋盘格底，看透明边缘）──
    d.text((PAD, y - 6), f"局部 {zoom}× 近邻放大（看边缘 / 噪点 / 色晕）",
           fill=SUB, font=f_small)
    y += 24
    for i, (label, im) in enumerate(cols):
        x = PAD + i * (COL_W + PAD)
        crop = im.crop(zoom_box)
        crop = crop.resize(
            (round(crop.width * zoom * z_scale), round(crop.height * zoom * z_scale)),
            Image.NEAREST,
        )
        bg = checker(COL_W, zh)
        paste_alpha(bg, crop, ((COL_W - crop.width) // 2, (zh - crop.height) // 2))
        canvas.paste(bg, (x, y))
        d.text((x + COL_W // 2, y + zh + 8), label, fill=INK,
               font=f_label, anchor="ma")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{rel.replace('/', '_')}_before_after.png"
    canvas.save(out_path)
    print(f"{out_path.relative_to(ROOT)}  {canvas.width}×{canvas.height}  "
          f"PNG {png_b / 1024:.0f}K → WebP {webp_b / 1024:.0f}K  PSNR {psnr:.2f} dB"
          f"  // {title_note}")
    return out_path


# (相对 assets 的路径, 说明, 1:1 放大取景框, 放大倍数)
CASES = (
    # ① 植物大图（1200×2000 legacy 画布，本批最大的一块：plants 共 106 MB）
    #    取景：花头眼睛 + 嘴角 + 花瓣描边（描边最邻近色差最容易被看出来）
    ("plants/sunflower/species_sunflower_adult_bloomed", "植物大图",
     (480, 600, 780, 840), 3),
    # ② 特效帧（升级演出 720²，柔光晕 + 花瓣渐变最容易暴露色带）
    #    取景：眼睛 / 花瓣阴影 / 右侧柔光边缘
    ("fx/levelUp/defaultLevelUp/frame002", "特效帧",
     (230, 120, 530, 370), 3),
    # ③ 许愿树循环帧（720×960，本批压缩比最低的一组 50.8% = 最需要目检）
    #    取景：枝干 + 叶片 + 两条半透明飘带（半透明区最考验 alpha 保真）
    ("wish_tree/tree_frames/frame001", "许愿树帧",
     (280, 300, 460, 470), 3),
)


def main() -> int:
    for rel, note, box, zoom in CASES:
        build_board(rel, note, box, zoom)
    print(f"\n输出目录：{OUT_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
