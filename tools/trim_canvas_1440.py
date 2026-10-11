"""把植物成品画布 1720×2000 收窄到 1440×2000（玄参 2026-10-11 拍板 B 档）。

## 背景
2026-10-09 画布加宽到 1720 的唯一瓶颈是月光兰枯死/枯萎态垂叶（半跨 855）。
玄参 2026-10-11 口径：「不常用素材不能影响整个画面」——花盆显示占比
800/1720=0.465 偏小。实测半跨排位：moon 855 > coral 793 > sunflower盛开 784
（legacy 不可动）> jade 720 > 其余 ≤652。取画布 1440（= 2×720）：

  · 盆占比 800/1440 ≈ 0.556（+19.4%），花园 3 列布局不变；
  · **需真裁**：moon 成株/枯萎/枯死（左半跨 855→720，裁 135px 垂叶）、
    coral 枯死/枯萎/成株（793/792/742→720，裁 73/72/22px）——共 6 张；
  · jade 半跨 720 恰好贴边不裁（≤1px 的 alpha≤30 微弱光晕被切，不可见）；
  · sunflower/shared/pot.png 本就是 1200×2000 legacy 画布，**不碰**。

## 做法
对 1720×2000 成品**逐图裁掉左右各 140 列**（内容居中平移，不缩放不重排，
盆宽 800 / 盆心 / 盆底三约束全部自动保持），并对新画布左右边缘做 10px
alpha 线性羽化——被裁的垂叶以渐隐收尾，避免「刀切直边」。

## 可回退性
`assets/_originals/` 原图未动；如需回到 1720，把
`tools/normalize_plant_art.py` 的 CANVAS_W 改回 1720 重跑即可重排，
再由本脚本裁回 1440。归一化主脚本 CANVAS_W 已同步改为 1440。
"""
import glob
import os

import numpy as np
from PIL import Image

ROOT = "/Users/wangjunchao/WorkBuddy/sunflowerTime/"
OLD_W, NEW_W, CANVAS_H = 1720, 1440, 2000
TRIM = (OLD_W - NEW_W) // 2  # 140，左右各裁
FEATHER = 10                 # 左右边缘 alpha 线性羽化宽度（px）
SKIP_PREFIXES = ("assets/pots/", "assets/plants/sunflower/", "assets/plants/shared/")

CUT = []   # 内容被真实裁切的文件（用于汇报）
KEPT = []  # 只是换画布、内容无损的文件


def run_at(mask_row: np.ndarray, x: int):
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


def verify_pot(a60: np.ndarray, path: str) -> bool:
    """防呆：盆基座中心 ≈ 新画布中心 720、盆底贴底。"""
    for y in range(CANVAS_H - 1, CANVAS_H - 30, -1):
        seg = run_at(a60[y], NEW_W // 2)
        if seg and 30 <= seg[1] - seg[0] + 1 <= 400:
            cx = (seg[0] + seg[1]) / 2
            if abs(cx - NEW_W / 2) > 6:
                print(f"{path:56s} ⚠️ 盆心 {cx:.0f} ≠ {NEW_W // 2}，已跳过")
                return False
            return True
    print(f"{path:56s} ⚠️ 未找到盆基座，已跳过")
    return False


for rel in sorted(glob.glob("assets/plants/**/*.png", recursive=True)):
    if rel.startswith(SKIP_PREFIXES):
        continue
    path = ROOT + rel
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if (w, h) != (OLD_W, CANVAS_H):
        print(f"{rel:56s} 非 {OLD_W}×{CANVAS_H}（{w}×{h}），跳过")
        continue
    a = np.array(im)

    # 记录是否真有内容被裁（alpha>30 的内容越出保留窗）
    a30 = a[:, :, 3] > 30
    xs = np.nonzero(a30.any(axis=0))[0]
    real_cut = len(xs) > 0 and (xs[0] < TRIM or xs[-1] >= TRIM + NEW_W)

    trimmed = a[:, TRIM:TRIM + NEW_W, :].copy()
    # 左右边缘 alpha 线性羽化（只影响贴边内容；透明区乘 0 无变化）
    ramp = np.linspace(0.0, 1.0, FEATHER, endpoint=False)
    alpha = trimmed[:, :, 3].astype(np.float32)
    alpha[:, :FEATHER] *= ramp[None, :]
    alpha[:, -FEATHER:] *= ramp[::-1][None, :]
    trimmed[:, :, 3] = alpha.astype(np.uint8)

    out = Image.fromarray(trimmed)
    a60 = np.array(out)[:, :, 3] > 60
    if not verify_pot(a60, rel):
        continue
    out.save(path, optimize=True)
    (CUT if real_cut else KEPT).append(rel)
    tag = "✂️ 真裁垂叶" if real_cut else "仅收画布（内容无损）"
    print(f"{rel:56s} {OLD_W}→{NEW_W}  {tag}")

print(f"\n完成：{len(CUT)} 张真裁 + {len(KEPT)} 张无损收框，画布统一 1440×2000"
      f"（盆占比 800/1440≈0.556，盆心/盆底/盆宽三约束不变）。")
