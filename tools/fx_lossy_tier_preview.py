#!/usr/bin/env python3
"""fx 帧序列「WebP 有损档位」样张对比图生成器（2026-11-25 决策用，**只出图不落地**）。

## 为什么有这个脚本

上一轮素材瘦身把 fx 帧统一转成 **WebP q95**（近无损档）—— 容器换了，体积几乎没降。
现在要评估「要不要降到 q75 / q75+半分辨率」，「降多少包、掉多少画质」必须让用户
**看得见**再拍板。本脚本只读 `assets/`、只往 `build/asset_compare/` 写图，
**绝不修改 `assets/`、绝不改代码**。

## 三档口径

| 档位 | 来源 | 说明 |
|---|---|---|
| 现状 q95 | **直接取现网资产字节**（不重编码） | 内存里解码，作为 PSNR 基准 |
| q75 | 由 q95 解码后按 `quality=75, method=6` 重编码，**原分辨率 720²** | |
| q75@360 | 同上但先把画布 LANCZOS 缩到 **360×360** 再 q75 | 半分辨率（显示侧本来就 ≤470px） |

`method=6` 与既有管线（`tools/convert_assets_webp.py` / `convert_eyecare640.py`）同档。

## 每张拼板的结构

* 上排「设备显示尺寸」：三档都按**同一个显示尺寸**画（q95/q75 先 720→显示尺寸
  缩小，q75@360 反过来 360→显示尺寸放大）—— 这才是用户眼睛看到的差别；
* 下排「原像素 2× 近邻放大」：同一块细节区域按**原生像素**放大（q75@360 用一半
  坐标、4× 放大对齐），把 q75 的块效应 / 色带 / 边缘振铃摊开来看；
* 棋盘格底是**中灰**（150/110），不用白色 —— 白色会把透明边缘的劣化掩盖掉；
* 每格下方标注：该档**实际字节数**、占 q95 的百分比、alpha 加权 PSNR。

## 用法

```bash
python3 tools/fx_lossy_tier_preview.py            # 出 4 组对比图 + 1 张总览图
python3 tools/fx_lossy_tier_preview.py --survey 80 # 只做 N 帧全量抽样统计（不出图）
```
"""

from __future__ import annotations

import argparse
import glob
import io
import math
import os
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
FX = ASSETS / "fx"
OUT_DIR = ROOT / "build" / "asset_compare"

# ── 三档规格 ────────────────────────────────────────────────────────────────
Q_BASE = "现状 q95"
Q_MID = "q75"
Q_SMALL = "q75@360"
TIERS = (Q_BASE, Q_MID, Q_SMALL)
MID_QUALITY = 75
SMALL_EDGE = 360
METHOD = 6

# ── 版面 ────────────────────────────────────────────────────────────────────
CELL = 440              # 单格显示边长
GAP = 26                # 格间距
PAD = 28                # 外边距
CANVAS_W = CELL * 3 + GAP * 2 + PAD * 2
LABEL_H = 58            # 每格下方两行标注
ROW_TITLE_H = 30
BG = (247, 246, 243)
INK = (68, 58, 50)
SUB = (132, 120, 108)
CHECK_A = (150, 150, 150)   # 中灰棋盘（不是白：要能看出透明边缘劣化）
CHECK_B = (110, 110, 110)
DETAIL_BOX = 220            # 「原像素放大」取景边长（720² 空间）

# 待出图的 4 组样本：覆盖「最容易被有损压缩看出来」的四类内容。
# 帧号是按「半透明像素占比 / 边缘能量 / q75 降幅」扫描后挑的最坏样本（见 --survey）。
CASES = (
    ("fx/eyecare640/frame561.webp", "护眼640",
     "整幅满画面：渐变天空 + 米色文字卡（大面积平滑渐变，色带最易现形）"),
    ("fx/grow/moon_orchid/adult_to_bloomed/frame019.webp", "成长帧(月光兰)",
     "成长帧：细描边花瓣 + 柔光晕（本库 q75 降幅最小的一组之一，边缘能量最高）"),
    ("fx/levelUp/defaultLevelUp/frame025.webp", "升级演出",
     "升级演出：41% 画布是半透明柔光（大面积半透明渐变）"),
    ("fx/focus/sunflower/settle/frame001.webp", "专注结算",
     "结算庆祝：细线条描边 + 小星点粒子（高频细节 + 半透明光斑）"),
)


# ── 基础工具 ────────────────────────────────────────────────────────────────


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """挑一个**有中文字形**的系统字体（本机无 PingFang.ttc，中文会变方框）。"""
    cands = [
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/System/Library/Fonts/PingFang.ttc",
    ]
    if bold:
        cands.append("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    cands.append("/System/Library/Fonts/Helvetica.ttc")
    for c in cands:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size)
            except OSError:
                continue
    print("⚠️ 未找到中文字体，标注可能显示为方框")
    return ImageFont.load_default()


def checker(w: int, h: int, cell: int = 10) -> Image.Image:
    """中灰棋盘格（透明区要看得出边缘劣化，不能用白底）。"""
    im = Image.new("RGB", (w, h), CHECK_A)
    d = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=CHECK_B)
    return im


def paste_alpha(canvas: Image.Image, im: Image.Image, xy: tuple[int, int]) -> None:
    rgba = im.convert("RGBA")
    canvas.paste(rgba, xy, rgba)


def alpha_weighted_psnr(ref: np.ndarray, out: np.ndarray) -> float:
    """按 alpha 加权的 RGB PSNR（dB）。

    与 `tools/convert_assets_webp.py` / `tools/gen_webp_compare.py` 同式：透明像素
    不渲染，若一并计入会把误差稀释掉（实测裸 PSNR 在不同质量档间只差 0.1 dB）。
    """
    alpha = ref[:, :, 3].astype(np.float64) / 255.0
    total = float(alpha.sum()) * 3.0
    if total <= 0:
        return float("inf")
    diff = ref[:, :, :3].astype(np.float64) - out[:, :, :3].astype(np.float64)
    mse = float((diff * diff * alpha[:, :, None]).sum() / total)
    if mse == 0:
        return float("inf")
    return 10.0 * math.log10(255.0 * 255.0 / mse)


def pick_detail_box(ref: np.ndarray, mid: np.ndarray,
                    box: int = DETAIL_BOX) -> tuple[tuple[int, int, int, int], str]:
    """自动挑「q75 劣化最严重」的一块区域放大；返回 (取景框, 取景理由)。

    🔴 判据不是「梯度最密」也不是「半透明最多」，而是**实测误差本身**：
    逐像素 `|ref − q75|`（RGB 三通道均值）× alpha 权重，积分图滑窗求和，取误差最大的
    窗口（步长 20，要求窗口内 alpha>32 的像素 ≥ 25%）。

    这样拼板自己就说明了「看哪里」—— 之前用「梯度能量」挑，实测在升级演出帧上会
    挑到花盆沿、在柔光区反而漏掉，看着像没问题；改成按误差挑之后，取景框一定落在
    压缩真正吃亏的地方（同时也不带主观挑选偏差）。
    """
    alpha = ref[:, :, 3].astype(np.float64) / 255.0
    diff = np.abs(ref[:, :, :3].astype(np.float64) - mid[:, :, :3].astype(np.float64))
    err = diff.mean(axis=2) * alpha
    coverage = (ref[:, :, 3] > 32).astype(np.float64)

    ii_e = err.cumsum(0).cumsum(1)
    ii_c = coverage.cumsum(0).cumsum(1)

    def box_sum(ii: np.ndarray, x: int, y: int) -> float:
        x2, y2 = x + box, y + box
        total = ii[y2 - 1, x2 - 1]
        if y > 0:
            total -= ii[y - 1, x2 - 1]
        if x > 0:
            total -= ii[y2 - 1, x - 1]
        if x > 0 and y > 0:
            total += ii[y - 1, x - 1]
        return float(total)

    h, w = err.shape
    best = (-1.0, 0, 0)
    for y in range(0, h - box + 1, 20):
        for x in range(0, w - box + 1, 20):
            if box_sum(ii_c, x, y) / (box * box) < 0.25:
                continue
            e = box_sum(ii_e, x, y)
            if e > best[0]:
                best = (e, x, y)
    _, bx, by = best
    return (bx, by, bx + box, by + box), "q75 实测误差最大处"


# ── 三档编码 ────────────────────────────────────────────────────────────────


def build_tiers(src: Path) -> dict:
    """解现网资产，产出三档（q95 直接复用现网字节，不重编码）。"""
    q95_bytes = src.stat().st_size
    with Image.open(src) as raw:
        base = raw.convert("RGBA")
    ref = np.asarray(base)

    variants: dict[str, dict] = {
        Q_BASE: {"bytes": q95_bytes, "size": base.size, "psnr": float("inf"),
                 "alpha_ok": True, "img": base},
    }

    buf = io.BytesIO()
    base.save(buf, "WEBP", quality=MID_QUALITY, method=METHOD)
    mid = Image.open(io.BytesIO(buf.getvalue())).convert("RGBA")
    variants[Q_MID] = {
        "bytes": buf.getbuffer().nbytes, "size": mid.size,
        "psnr": alpha_weighted_psnr(ref, np.asarray(mid)),
        "alpha_ok": bool(np.array_equal(ref[:, :, 3], np.asarray(mid)[:, :, 3])),
        "img": mid,
    }

    small_src = base.resize((SMALL_EDGE, SMALL_EDGE), Image.LANCZOS)
    buf2 = io.BytesIO()
    small_src.save(buf2, "WEBP", quality=MID_QUALITY, method=METHOD)
    small = Image.open(io.BytesIO(buf2.getvalue())).convert("RGBA")
    # PSNR 口径：360 版按设备放大后与原图比（LANCZOS 回 720²），含重采样损失。
    upscaled = small.resize(base.size, Image.LANCZOS)
    variants[Q_SMALL] = {
        "bytes": buf2.getbuffer().nbytes, "size": small.size,
        "psnr": alpha_weighted_psnr(ref, np.asarray(upscaled)),
        "alpha_ok": True,  # 尺寸不同，alpha 逐像素比对无意义；看合成图目检
        "img": small,
    }
    return variants


# ── 单组拼板 ────────────────────────────────────────────────────────────────


def build_board(rel: str, short: str, note: str) -> dict:
    src = ASSETS / rel
    if not src.exists():
        raise FileNotFoundError(f"缺样本：{src}")
    v = build_tiers(src)

    detail, detail_why = pick_detail_box(
        np.asarray(v[Q_BASE]["img"]), np.asarray(v[Q_MID]["img"]))
    row_h = CELL
    header_h = 128
    total_h = (header_h + PAD + ROW_TITLE_H + row_h + LABEL_H
               + GAP + ROW_TITLE_H + row_h + LABEL_H + PAD)
    canvas = Image.new("RGB", (CANVAS_W, total_h), BG)
    d = ImageDraw.Draw(canvas)

    f_title = load_font(25, bold=True)
    f_meta = load_font(18)
    f_row = load_font(19, bold=True)
    f_lab = load_font(18, bold=True)
    f_sub = load_font(16)

    base_bytes = v[Q_BASE]["bytes"]
    d.text((PAD, 16), "fx 帧序列 · WebP 档位样张对比", fill=INK, font=f_title)
    d.text((PAD, 50), rel, fill=SUB, font=f_meta)
    d.text((PAD, 74), note, fill=SUB, font=f_meta)
    d.text((PAD, 98),
           f"画布 {v[Q_BASE]['size'][0]}×{v[Q_BASE]['size'][1]}"
           f"   ·   三档同屏显示尺寸 {CELL}px   ·   PSNR 为 alpha 加权（相对现状 q95）",
           fill=SUB, font=f_meta)
    d.line([(PAD, header_h - 10), (CANVAS_W - PAD, header_h - 10)],
           fill=(226, 222, 215))

    # ── 上排：设备显示尺寸 ──
    y = header_h + PAD - 6
    d.text((PAD, y - 4), f"① 设备显示尺寸（三档都缩放到 {CELL}px 再看）",
           fill=SUB, font=f_row)
    y += ROW_TITLE_H
    for i, tier in enumerate(TIERS):
        info = v[tier]
        x = PAD + i * (CELL + GAP)
        box = Image.new("RGB", (CELL, CELL), (238, 236, 231))
        shown = info["img"].resize((CELL, CELL), Image.LANCZOS)
        paste_alpha(box, shown, (0, 0))
        canvas.paste(box, (x, y))
        d.text((x, y + CELL + 6),
               f"{tier}   {info['bytes'] / 1024:.1f} KB"
               f"   ({info['bytes'] / base_bytes * 100:.0f}%)",
               fill=INK, font=f_lab)
        ps = "基准" if tier == Q_BASE else f"PSNR {info['psnr']:.2f} dB"
        d.text((x, y + CELL + 30), f"{info['size'][0]}px   {ps}", fill=SUB, font=f_sub)

    # ── 下排：原像素放大 ──
    y += CELL + LABEL_H + GAP
    bx0, by0, bx1, by1 = detail
    d.text((PAD, y - 4),
           f"② 原像素 2× 近邻放大 · {detail_why}（取景 x{bx0} y{by0} 起 "
           f"{DETAIL_BOX}px；{Q_SMALL} 按一半坐标取景、4× 放大对齐）",
           fill=SUB, font=f_row)
    y += ROW_TITLE_H
    for i, tier in enumerate(TIERS):
        info = v[tier]
        x = PAD + i * (CELL + GAP)
        if tier == Q_SMALL:
            half = DETAIL_BOX // 2
            sx, sy = bx0 // 2, by0 // 2
            crop = info["img"].crop((sx, sy, sx + half, sy + half))
            zoom = CELL // half
        else:
            crop = info["img"].crop(detail)
            zoom = 2
        crop = crop.resize((crop.width * zoom, crop.height * zoom), Image.NEAREST)
        bg = checker(CELL, CELL)
        paste_alpha(bg, crop, ((CELL - crop.width) // 2, (CELL - crop.height) // 2))
        canvas.paste(bg, (x, y))
        d.text((x, y + CELL + 6),
               f"{tier}   {info['bytes'] / 1024:.1f} KB"
               f"   ({info['bytes'] / base_bytes * 100:.0f}%)",
               fill=INK, font=f_lab)
        ps = "基准" if tier == Q_BASE else f"PSNR {info['psnr']:.2f} dB"
        d.text((x, y + CELL + 30), f"{info['size'][0]}px   {ps}", fill=SUB, font=f_sub)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = rel.replace("assets/", "").replace("/", "_").replace(".webp", "")
    out = OUT_DIR / f"{stem}_q95_vs_q75_vs_q75at360.png"
    canvas.save(out)
    print(f"  ✓ {out.relative_to(ROOT)}  {canvas.width}×{canvas.height}")
    print(f"    q95 {v[Q_BASE]['bytes'] / 1024:6.1f}K  →  "
          f"q75 {v[Q_MID]['bytes'] / 1024:6.1f}K ({v[Q_MID]['bytes'] / base_bytes * 100:4.0f}%, "
          f"PSNR {v[Q_MID]['psnr']:.2f} dB)  →  "
          f"q75@360 {v[Q_SMALL]['bytes'] / 1024:5.1f}K "
          f"({v[Q_SMALL]['bytes'] / base_bytes * 100:3.0f}%, "
          f"PSNR {v[Q_SMALL]['psnr']:.2f} dB)")
    return {
        "rel": rel, "short": short, "bytes": {t: v[t]["bytes"] for t in TIERS},
        "psnr": {t: v[t]["psnr"] for t in TIERS},
        "out": str(out),
    }


# ── 全量抽样统计 ────────────────────────────────────────────────────────────


def survey(n: int) -> list[dict]:
    """在全部 fx 帧里均匀抽 n 帧，量三档体积（用于推算总包，不出图）。"""
    files = sorted(glob.glob(str(FX / "**" / "*.webp"), recursive=True))
    if not files:
        raise SystemExit("assets/fx 下没有 webp 帧")
    rng = random.Random(20261125)  # 固定种子，可复现
    picks = sorted(rng.sample(files, min(n, len(files))))
    rows = []
    for p in picks:
        with Image.open(p) as raw:
            base = raw.convert("RGBA")
        q95 = os.path.getsize(p)
        buf = io.BytesIO()
        base.save(buf, "WEBP", quality=MID_QUALITY, method=METHOD)
        mid = buf.getbuffer().nbytes
        small = base.resize((SMALL_EDGE, SMALL_EDGE), Image.LANCZOS)
        buf2 = io.BytesIO()
        small.save(buf2, "WEBP", quality=MID_QUALITY, method=METHOD)
        extra = {}
        for q in (90, 85, 80):
            bq = io.BytesIO()
            base.save(bq, "WEBP", quality=q, method=METHOD)
            extra[q] = bq.getbuffer().nbytes
        rows.append({
            "path": p, "q95": q95, "q75": mid,
            "q75at360": buf2.getbuffer().nbytes, "extra": extra,
        })
    return rows


def draw_wrapped(d: ImageDraw.ImageDraw, xy: tuple[int, int], text: str,
                 font: ImageFont.FreeTypeFont, fill: tuple[int, int, int],
                 max_w: int, line_h: int) -> int:
    """按像素宽度折行（中文无空格，只能逐字累加量宽）。返回结束后的 y。"""
    x, y = xy
    line = ""
    for ch in text:
        probe = line + ch
        prev = line[-1] if line else ""
        if (d.textlength(probe, font=font) > max_w and line
                and not (prev.isascii() and prev.isalnum()
                         and ch.isascii() and ch.isalnum())):
            d.text((x, y), line, fill=fill, font=font)
            y += line_h
            line = ch
        else:
            line = probe
    if line:
        d.text((x, y), line, fill=fill, font=font)
        y += line_h
    return y


def build_overview(stats: dict) -> Path:
    """总览图：三档推算总包（堆叠柱：fx 帧 / 其他 assets / 非 assets）。

    ⚠️ 口径：**q95 柱用实测真值锚定**（fx 实测 162.03 MB、总包实测 285.42 MB），
    q75 / q75@360 用「抽样帧均值之比」等比折算 fx 部分（不是把抽样均值乘帧数 ——
    那样基准柱会跟实测对不上）。其他 assets / 非 assets 视为不变。
    """
    frames = stats["frames"]
    fx_actual = stats["fx_actual_mb"]
    other_assets_mb = stats["other_assets_mb"]
    non_assets_mb = stats["non_assets_mb"]
    base_total = stats["base_total_mb"]
    avg = stats["avg_kb"]
    fx_of = {t: fx_actual * avg[t] / avg[Q_BASE] for t in TIERS}

    W, H = 1180, 960
    canvas = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    f_title = load_font(28, bold=True)
    f_note = load_font(18)
    f_val = load_font(22, bold=True)
    f_leg = load_font(17)

    d.text((44, 28), "三档口径 · 推算 release arm64 APK 总包", fill=INK, font=f_title)
    draw_wrapped(d, (44, 70),
                 f"fx 共 {frames} 帧（实测 {fx_actual:.1f} MB，均值 {fx_actual * 1e6 / frames / 1024:.1f} KB/帧）；"
                 f"按 {stats['sample']} 帧随机抽样均值等比折算。"
                 f"其他 assets {other_assets_mb:.1f} MB、非 assets {non_assets_mb:.1f} MB 视为不变。",
                 f_note, SUB, W - 88, 24)

    plot_x, plot_y, plot_w, plot_h = 130, 150, W - 220, 390
    ymax = math.ceil((base_total + 30) / 50) * 50

    for i in range(0, ymax + 1, 50):
        y = plot_y + plot_h - int(plot_h * i / ymax)
        d.line([(plot_x, y), (plot_x + plot_w, y)], fill=(226, 222, 215))
        d.text((plot_x - 14, y), f"{i}", fill=SUB, font=f_note, anchor="rm")
    d.text((plot_x - 96, plot_y - 16), "MB", fill=SUB, font=f_note)

    seg_colors = ((196, 132, 74), (128, 170, 132), (150, 158, 176))
    seg_names = ("fx 序列帧", "其他 assets", "非 assets（引擎 / dex / so）")
    bar_w = 170
    totals = {}
    for i, tier in enumerate(TIERS):
        fx_mb = fx_of[tier]
        total = fx_mb + other_assets_mb + non_assets_mb
        totals[tier] = (fx_mb, total)
        x = plot_x + int(plot_w * (i + 0.5) / 3) - bar_w // 2
        bottom = plot_y + plot_h
        for mb, color in zip((fx_mb, other_assets_mb, non_assets_mb), seg_colors):
            h = int(plot_h * mb / ymax)
            d.rectangle([x, bottom - h, x + bar_w, bottom], fill=color)
            if h > 26:
                d.text((x + bar_w // 2, bottom - h // 2),
                       f"{mb:.1f}", fill=(255, 255, 255), font=f_leg, anchor="mm")
            bottom -= h
        d.text((x + bar_w // 2, bottom - 30), f"合计 {total:.1f} MB",
               fill=INK, font=f_val, anchor="mm")
        d.text((x + bar_w // 2, plot_y + plot_h + 26), tier,
               fill=INK, font=f_val, anchor="ma")
        d.text((x + bar_w // 2, plot_y + plot_h + 58),
               f"{avg[tier]:.1f} KB/帧", fill=SUB, font=f_leg, anchor="ma")

    # 图例（独占一行，避免与柱下的 KB/帧 标注打架）
    lx, ly = 130, plot_y + plot_h + 96
    for name, color in zip(seg_names, seg_colors):
        d.rectangle([lx, ly, lx + 22, ly + 22], fill=color)
        d.text((lx + 30, ly + 11), name, fill=INK, font=f_leg, anchor="lm")
        lx += 40 + int(d.textlength(name, font=f_leg)) + 34

    d_mid = base_total - totals[Q_MID][1]
    d_small = base_total - totals[Q_SMALL][1]
    y = ly + 58
    d.text((130, y), f"相对现状 q95（实测 {base_total:.2f} MB）：", fill=INK, font=f_note)
    y += 30
    d.text((130, y),
           f"· {Q_MID}：总包 ≈{totals[Q_MID][1]:.1f} MB，省 ≈{d_mid:.1f} MB"
           f"（-{d_mid / base_total * 100:.0f}%）",
           fill=INK, font=f_note)
    y += 28
    d.text((130, y),
           f"· {Q_SMALL}：总包 ≈{totals[Q_SMALL][1]:.1f} MB，省 ≈{d_small:.1f} MB"
           f"（-{d_small / base_total * 100:.0f}%）",
           fill=INK, font=f_note)
    y += 34

    if stats.get("spread"):
        y = draw_wrapped(
            d, (130, y),
            "※ 降幅因内容而异（本页 4 组样本实测 q75 保留率：" +
            "、".join(stats["spread"]) +
            "）—— 越是大面积半透明柔光，q75 越压不动；平滑渐变 + 整幅画面（如护眼帧）降幅最大。",
            f_note, SUB, W - 200, 24)
        y += 6
    if stats.get("extra_tiers"):
        txt = "、".join(
            f"{name} ≈{fx_mb + other_assets_mb + non_assets_mb:.1f} MB"
            for name, fx_mb in stats["extra_tiers"])
        d.text((130, y), f"其他可选档位（同口径推算，保留 720 分辨率）：{txt}",
               fill=INK, font=f_note)
        y += 28
    draw_wrapped(
        d, (130, y),
        "※ 全部为推算值（抽样均值之比 × 实测 fx 总量 + 不变项），不是重新打包实测；"
        "落地后必须 rm -rf build/app 再打包才会得到真实数字（Gradle 增量打包会留空洞）。",
        f_note, SUB, W - 200, 24)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "overview_tier_estimate.png"
    canvas.save(out)
    print(f"  ✓ {out.relative_to(ROOT)}  {W}×{H}")
    return out


# ── 入口 ────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description="fx 帧 WebP 档位样张对比（只出图）")
    ap.add_argument("--survey", type=int, default=80,
                    help="全量抽样帧数（默认 80，用于推算总包）")
    ap.add_argument("--skip-survey", action="store_true")
    args = ap.parse_args()

    print("[boards] 4 组样本对比图 …")
    results = []
    for rel, short, note in CASES:
        results.append(build_board(rel, short, note))

    if not args.skip_survey:
        print(f"\n[survey] 在 assets/fx 均匀抽 {args.survey} 帧量三档体积 …")
        rows = survey(args.survey)
        frames = len(glob.glob(str(FX / "**" / "*.webp"), recursive=True))
        avg = {t: sum(r[{"现状 q95": "q95", "q75": "q75",
                         "q75@360": "q75at360"}[t]] for r in rows) / len(rows) / 1024
               for t in TIERS}
        # 实测真值（本仓库当前状态）：fx 帧总体积、assets 总体积、release arm64 APK。
        fx_actual = sum(os.path.getsize(p) for p in
                        glob.glob(str(FX / "**" / "*.webp"), recursive=True)) / 1e6
        assets_total_mb = 257.43
        base_total_mb = 285.42
        stats = {
            "frames": frames,
            "sample": len(rows),
            "avg_kb": avg,
            "fx_actual_mb": fx_actual,
            "other_assets_mb": assets_total_mb - fx_actual,
            "non_assets_mb": base_total_mb - assets_total_mb,
            "base_total_mb": base_total_mb,
        }
        print(f"  实测 fx 总量 {fx_actual:.2f} MB / {frames} 帧"
              f"（均值 {fx_actual * 1e6 / frames / 1024:.1f} KB/帧）")
        print(f"  抽样 {len(rows)} 帧：" +
              "  ".join(f"{t} {avg[t]:.2f} KB/帧" for t in TIERS))
        for t in TIERS:
            fx_mb = fx_actual * avg[t] / avg[Q_BASE]
            print(f"  推算 {t:<9} fx {fx_mb:6.1f} MB → 总包 "
                  f"{fx_mb + stats['other_assets_mb'] + stats['non_assets_mb']:6.1f} MB")
        stats["extra_tiers"] = [
            (f"q{q}", fx_actual * (sum(r["extra"][q] for r in rows) / len(rows)) / (avg[Q_BASE] * 1024))
            for q in (90, 85, 80)
        ]
        stats["spread"] = [
            f"{r['short']} {r['bytes'][Q_MID] / r['bytes'][Q_BASE] * 100:.0f}%"
            for r in results
        ]
        build_overview(stats)

    print("\n=== 每组三档字节数（可直接抄进决策表）===")
    print(f"{'样本':<56}{'q95':>10}{'q75':>10}{'q75@360':>10}")
    for r in results:
        n = r["rel"].replace("assets/fx/", "")
        print(f"{n:<56}{r['bytes'][Q_BASE]:>9}B{r['bytes'][Q_MID]:>9}B"
              f"{r['bytes'][Q_SMALL]:>9}B")
    print(f"\n输出目录：{OUT_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
