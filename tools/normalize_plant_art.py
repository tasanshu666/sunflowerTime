"""把植物美术图统一排版到同一张画布上（盆底基线、盆心居中、**全局等盆宽 800**）。

## 为什么需要
美术出的每张图都是独立画布，尺寸不一（2048 / 1536 / 1024 混杂）。若代码按
「图宽铺满格子」缩放，各阶段/各物种的盆会忽大忽小。把每张图都排到同一尺寸
画布、且**盆底基线 / 盆水平中心 / 盆宽**三者固定，代码就只需
`width: 格子宽` 一个缩放动作，盆自动等大、自动对齐。

## 盆宽口径（2026-10-09 终版：**全局 800**，玄参拍板）
玄参 2026-10-09 口径：「种植时所有植物可能都会种一遍，花盆大小必须保持一致」
—— 上一版「物种内一致（561~784）」跨物种仍会跳变，废弃。回到全局 800：

  · 画布从 1200×2000 **等高加宽到 1720×2000**（唯一瓶颈：moon 枯死/枯萎态
    垂叶横跨 2×855=1710px@盆800；其余物种 ≤2×793 全覆盖）。
  · 盆心居中约束下画布宽 = 2×最大悬挂 = 1710 → 取整 1720。
  · **等高加宽对渲染零冲击**：正方形盒（结算页/预览等）contain 按高度绑定缩放，
    盆显示大小恒 = 800/2000 × size，与画布宽无关；花园格图片框宽高比由
    `kGardenArtAspect` 单点跟随（2000/1720）。
  · 旧资产（sunflower 7 张 / shared 3 张 / pot.png）**不重排**：它们的 contain
    缩放系数与新图完全相同（同为 artW/画布宽 × 800 盆宽），盆自动等大
    （pot.png 1200×2000 在新比例框内按高度绑定缩放，盆身 801px 与 800 差 0.1%，
    不可见）。sunflower 成株缺 wilted/dead 原图备份，更不能动。

## 输入
优先读 `assets/_originals/` 下的**原始图**（新图入库前先备份），保证本脚本
可重复执行；原图不存在时回退读当前文件。

## 模板常数（2026-10-08 新物种批次实测）
- 2048 画布：盆沿宽 706、盆轴 x=1028.5、盆底 y=1818.5
- moon 三张 1536 图 = 2048 模板 × 0.75；strawberry 两张 1024 图 = ×0.5
  （盆沿 530/354、盆轴 769.5/512.7、盆底 1363/909 实测全部吻合）
任意方形画布按 f = 画布宽/2048 折算。发光晕/垂地落叶会干扰逐图测盆，
故用模板常数而非逐图测量；处理前做盆基座防呆校验（见 verify_pot）。

## SKIP 清单（已按各自口径定稿，重跑会破坏一致性）
- assets/pots/pot.png、assets/plants/sunflower/、assets/plants/shared/
"""
import glob
import os
import re

import numpy as np
from PIL import Image

ROOT = "/Users/wangjunchao/WorkBuddy/sunflowerTime/"
ORIGIN = ROOT + "assets/_originals/"

CANVAS_W, CANVAS_H = 1720, 2000
TARGET_POT = 800.0        # 全局统一盆沿宽（画布像素）
REF_W = 2048.0             # 模板基准画布
PLANTER_W_REF = 706.0      # 模板盆沿宽（2048 基准 px）
PLANTER_CENTER_X = 1028.5  # 模板盆水平中心（2048 基准 px）
PLANTER_BOTTOM_Y = 1818.5  # 模板盆底基线（2048 基准 px）
PAD_RATIO = 0.02           # 内容外留 2% 余量，避免锐边被切（放不下时退 0）

SKIP_PREFIXES = ("assets/pots/", "assets/plants/sunflower/", "assets/plants/shared/")


def source_of(rel: str) -> str:
    """优先用备份的原图（可重复执行），没有则用当前文件。"""
    bak = ORIGIN + rel[len("assets/"):]
    return bak if os.path.exists(bak) else ROOT + rel


def run_at(mask_row: np.ndarray, x: int):
    """返回 mask_row 中包含 x 的连续不透明行程 (l, r)，不含则 None。"""
    h = mask_row.shape[0]
    if x < 0 or x >= h or not mask_row[x]:
        return None
    l = x
    while l > 0 and mask_row[l - 1]:
        l -= 1
    r = x
    while r < h - 1 and mask_row[r + 1]:
        r += 1
    return l, r


def verify_pot(im: Image.Image, axis: float, bottom: float, f: float) -> str | None:
    """防呆：在 (axis, bottom) 附近应能找到盆基座（宽 30~0.3w 的行程）。

    返回 None 表示通过，否则返回告警文案。
    """
    a = np.array(im)[:, :, 3] > 60  # 高阈值避开发光晕/半透明阴影
    w = a.shape[1]
    ax = int(round(axis))
    tol_y = max(8, int(8 * f))
    tol_x = max(12, int(12 * f))
    for y in range(int(bottom) + int(40 * f), int(bottom) - tol_y, -1):
        if y < 0 or y >= a.shape[0]:
            continue
        seg = run_at(a[y], ax)
        if seg is None:
            continue
        width = seg[1] - seg[0] + 1
        if 30 <= width <= 0.3 * w:
            cx = (seg[0] + seg[1]) / 2
            if abs(cx - axis) > tol_x:
                return f"盆轴偏移 {cx:.0f} ≠ {axis:.1f}"
            if abs(y - bottom) > tol_y:
                return f"盆底 y={y} ≠ {bottom:.1f}"
            return None
        if width > 0.3 * w:
            break  # 落到过大行程（叶/地面物），视为未找到基座
    return "未找到盆基座行程"


FILES = sorted(glob.glob("assets/plants/**/*.png", recursive=True))
WORK = [r for r in FILES if not r.startswith(SKIP_PREFIXES)]

# ── 统一排版：全局盆宽 800、盆心 = 画布中心、盆底 = 画布底边 ──────────────
for rel in FILES:
    if rel.startswith(SKIP_PREFIXES):
        print(f"{rel:56s} SKIP（已定稿 / 不在本批范围）")
        continue
    src = source_of(rel)
    dst = ROOT + rel
    im = Image.open(src).convert("RGBA")
    w, h = im.size

    # 防重跑保护：没有 _originals 原图备份、且当前文件已是本脚本的成品画布
    # → 只能整图读回，绝不能当「原图」再缩放（2026-09-28 盆 800→517 事故）。
    if src == ROOT + rel and (w, h) == (CANVAS_W, CANVAS_H):
        print(f"{rel:56s} 无原图备份且已是成品画布，跳过（请先把原图放进 _originals/）")
        continue

    f = w / REF_W
    axis = PLANTER_CENTER_X * f
    bottom_const = PLANTER_BOTTOM_Y * f
    s = TARGET_POT / (PLANTER_W_REF * f)  # 该图源像素 → 画布像素

    msg = verify_pot(im, axis, bottom_const, f)
    if msg:
        print(f"{rel:56s} ⚠️ 盆校验失败：{msg}，跳过（请人工检查模板）")
        continue

    # bbox 用 alpha>30 口径：微弱光晕（alpha<30）不参与约束，超出画布窗口的
    # 部分被裁 —— 光晕本身渐隐到 0，裁切不可见。
    # ⚠️ 不能用 getbbox()（alpha>0）：moon 盛开图的光晕被源画布边缘截断，
    # 会让 bbox 虚宽、误触发「放不下」（2026-10-08 实测教训）。
    a30 = np.array(im)[:, :, 3] > 30
    ys30 = np.nonzero(a30.any(axis=1))[0]
    xs30 = np.nonzero(a30.any(axis=0))[0]
    if len(xs30) == 0:
        print(f"{rel:56s} 全透明，跳过")
        continue
    left, right = int(xs30[0]), int(xs30[-1]) + 1
    top, bottom = int(ys30[0]), int(ys30[-1]) + 1
    if bottom > bottom_const + 2 * f:
        print(f"{rel:56s} 注：盆底以下有内容 {bottom - bottom_const:.0f}px（垂地叶尖等），将按盆底线裁齐")

    def plan(pad_ratio: float) -> tuple:
        """按给定 pad 比例计算 (cx0, cx1, cy0)。盆宽固定 800，不做 fit 回退：
        画布 1720 已按实测最大悬挂（2×855）留足余量；仅当 2% pad 放不下时退 0 pad。"""
        pad_x = int((right - left) * pad_ratio)
        pad_y = int((bottom - top) * pad_ratio)
        cx0, cx1 = max(0, left - pad_x), min(w, right + pad_x)
        cy0 = max(0, top - pad_y)
        return cx0, cx1, cy0

    cx0, cx1, cy0 = plan(PAD_RATIO)
    used_pad = PAD_RATIO
    if (CANVAS_W / 2 - (axis - cx0) * s) < 0 or (cx1 - axis) * s > CANVAS_W / 2:
        cx0, cx1, cy0 = plan(0.0)
        used_pad = 0.0

    crop = im.crop((cx0, cy0, cx1, int(bottom_const)))
    new_w = max(1, round(crop.width * s))
    new_h = max(1, round(crop.height * s))
    resized = crop.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    paste_x = round(CANVAS_W / 2 - (axis - cx0) * s)
    paste_y = CANVAS_H - new_h
    if paste_x < 0 or paste_y < 0 or paste_x + new_w > CANVAS_W:
        print(
            f"{rel:56s} ⚠️ 放不下：paste=({paste_x},{paste_y}) 图 {new_w}x{new_h}，"
            f"请调大 CANVAS_W 或人工核查"
        )
        continue
    canvas.alpha_composite(resized, (paste_x, paste_y))
    canvas.save(dst, optimize=True)

    # 成品自检：盆基座中心 ≈ 画布中心、盆底贴底
    out = Image.open(dst).convert("RGBA")
    oa = np.array(out)[:, :, 3] > 60
    ok = "✔"
    for y in range(CANVAS_H - 1, CANVAS_H - 30, -1):
        seg = run_at(oa[y], CANVAS_W // 2)
        if seg and 30 <= seg[1] - seg[0] + 1 <= 400:
            cx = (seg[0] + seg[1]) / 2
            ok = "✔" if abs(cx - CANVAS_W / 2) <= 6 else f"⚠️ 盆心 {cx:.0f}"
            break
    tag = ok if used_pad == PAD_RATIO else f"✔（pad 退 0，叶缘贴框）"
    print(
        f"{rel:56s} {w}x{h} → 画布 {CANVAS_W}x{CANVAS_H} "
        f"内容 {new_w}x{new_h} 贴于 ({paste_x},{paste_y}) "
        f"| 盆宽 {TARGET_POT:.0f}px 盆底贴底 {tag}"
    )

print("\n完成：全局盆宽 800 一致、盆底=画布底边、盆心=画布中心（画布 1720×2000）。")
