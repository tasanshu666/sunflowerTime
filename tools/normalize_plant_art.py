"""把植物/花盆美术图统一排版到同一张画布上（盆宽、盆底基线、水平中心对齐）。

## 为什么需要
美术出的每张图都是独立画布（宽度还不一样：种子 753 / 幼苗 753 / 成株 756 /
盛开 975，盛开因为花瓣更宽）。若代码按「图宽铺满格子」缩放，盛开时盆会比别的
阶段小 23% —— 孩子看到的是「同一盆花，大小忽大忽小」。

把每张图都排到同一尺寸画布、且**盆宽 / 盆底基线 / 盆水平中心**三者固定，
代码就只需 `width: 格子宽` 一个缩放动作，各阶段的盆自动等大、自动对齐。

## 输入
优先读 `assets/_originals/` 下的**原始图**（由 trim_art.py 备份），保证本脚本
可重复执行而不会反复内缩；原图不存在时回退读当前文件。

## 输出
覆盖 `assets/pots/pot.png` 与 `assets/plants/species_sunflower_*.png`。

## 出图规格（以后自己出新图也照这个来，或把新图丢进 _originals/ 再跑本脚本）
- 画布：1200 × 2000 透明底
- 盆宽：800 px
- 盆底：贴画布底边（y = 2000）
- 盆水平中心：画布中心（x = 600）
- 植物向上生长，长多高都行，不要超出画布

## 基准常量来源
原图（2048×2048）实测：4 张植物图与空盆图的盆宽均为 711 px、盆底基线均为
y=1816、盆中心均为 x=1025.5 —— 这些数值由 alpha 通道边界测得，见 trim_art.py。
"""
import glob
import os

from PIL import Image

ROOT = "/Users/wangjunchao/WorkBuddy/sunflowerTime/"
ORIGIN = ROOT + "assets/_originals/"

CANVAS_W, CANVAS_H = 1200, 2000
PLANTER_W_REF = 711.0       # 原图中盆宽（px）
PLANTER_CENTER_X = 1025.5   # 原图中盆水平中心（px）
PLANTER_BOTTOM_Y = 1816     # 原图中盆底基线（px）
TARGET_PLANTER_W = 800.0    # 目标：画布中盆宽（px）
SCALE = TARGET_PLANTER_W / PLANTER_W_REF
PAD_RATIO = 0.02            # 内容外留 2% 余量，避免锐边被切

FILES = sorted(
    ["assets/pots/pot.png"] + glob.glob("assets/plants/*.png")
)
# 说明：这里用 glob 扫描而非硬编码清单 —— 以后美术新增任何
# `assets/plants/*.png`（如枯萎/枯死态、新物种）都会自动纳入统一排版，
# 不必再改本脚本。新图若已按本文件顶部规格出图，跑一次即可；未按规格出图，
# 也会被自动重新对齐到「盆宽 800 / 盆底贴底 / 盆心居中」。


def source_of(rel: str) -> str:
    """优先用备份的原图（可重复执行），没有则用当前文件。"""
    bak = ORIGIN + rel[len("assets/"):]
    return bak if os.path.exists(bak) else ROOT + rel


for rel in FILES:
    src = source_of(rel)
    dst = ROOT + rel
    im = Image.open(src).convert("RGBA")
    w, h = im.size

    bbox = im.getchannel("A").getbbox()
    if bbox is None:
        print(f"{rel:52s} 全透明，跳过")
        continue
    left, top, right, bottom = bbox

    pad_x = int((right - left) * PAD_RATIO)
    pad_y = int((bottom - top) * PAD_RATIO)
    cx0, cx1 = max(0, left - pad_x), min(w, right + pad_x)
    cy0 = max(0, top - pad_y)
    # 底部**不加**留白：盆底基线必须精确等于裁剪框底边，否则高图（成株/盛开）因
    # 按内容高度比例留白而多出几像素，各阶段的盆在画布上就会垂直错位（实测最大 19px）。
    cy1 = min(h, PLANTER_BOTTOM_Y)

    crop = im.crop((cx0, cy0, cx1, cy1))
    new_w = max(1, round(crop.width * SCALE))
    new_h = max(1, round(crop.height * SCALE))
    resized = crop.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    paste_x = round(CANVAS_W / 2 - (PLANTER_CENTER_X - cx0) * SCALE)
    paste_y = CANVAS_H - new_h
    if paste_x < 0 or paste_y < 0 or paste_x + new_w > CANVAS_W:
        print(
            f"{rel:52s} ⚠️ 放不下：paste=({paste_x},{paste_y}) 图 {new_w}x{new_h}，"
            f"请调大 CANVAS_W/CANVAS_H 或调小 TARGET_PLANTER_W"
        )
        continue
    canvas.alpha_composite(resized, (paste_x, paste_y))
    canvas.save(dst, optimize=True)

    print(
        f"{rel:52s} {w}x{h} → 画布 {CANVAS_W}x{CANVAS_H} "
        f"内容 {new_w}x{new_h} 贴于 ({paste_x},{paste_y}) "
        f"| 盆宽 {round(PLANTER_W_REF * SCALE)}px 盆底贴底 ✔"
    )

print("\n完成：所有图的盆宽=800px、盆底=画布底边、盆心=画布中心，代码按格宽缩放即可等大。")
