#!/usr/bin/env python3
"""守卫战素材管线（B5b 建立 → B8 加色彩归一 → **B9 加实体裁边**）。

源目录（只读，绝不改动源文件）：
  /Volumes/DataHD-2TB/素材归档/专注素材/花园守护/

落位（`assets/guard/`，命名对齐 docs/美术资源_序列帧与音频命名规范_v1）：

  向日葵战士/待机动画/frame001..019.png (720) → soldier_idle/frame001..019.webp
  馋光鼠/馋光鼠进攻/frame001..007.png   (720) → monster_m1/frame001..007.webp
  食叶虫/食叶虫/frame001..007.png       (720) → monster_m2/frame001..007.webp   ← B9 新增
  顺手贼/顺手贼/frame001..007.png       (720) → monster_m3/frame001..007.webp   ← B9 新增
  向日葵战士/向日葵战士攻击.png (2048)        → soldier_attack.webp
  向日葵战士/向日葵战士胜利.png (2048)        → soldier_win.webp
  房屋/房屋(1).png (1984×1118)                → house.webp（原尺寸，不裁：实体占 94.6%）

## 🔴 B9 的根本改动：按**实体并集 bbox** 裁边（alpha > 128）

玄参第四轮真机说「战士太小、离房子太远」，量化后根因不在常量，而在素材：
交付的美术画布是 512×512，但战士实体只占中间 ~50% ⇒ **标称 72pt 的战士，
肉眼只有 36pt**；同样「栅栏间隙 6pt」因为左边 23% 的透明边，肉眼成了 23pt。

按「alpha > 128」（不是 > 8：> 8 会把半透明阴影算进实体，等于没裁）算出的
**并集** bbox（同一组帧共用一个裁切窗口 ⇒ 动画不抖，与逐帧裁切的口径不同）：

| 组 | 画布 | 并集 bbox | 裁后 | 实体/画布（裁前） |
|---|---|---|---|---|
| soldier_idle(19) | 720×720 | (169,157,531,529) | 362×372 | 26.0% |
| monster_m1(7) | 720×720 | (128,157,720,626) | 592×469 | 53.6% |
| monster_m2(7) | 720×720 | (0,0,720,720) | 720×720 | **100%**（素材出框，无可裁，见下） |
| monster_m3(7) | 720×720 | (96,256,700,571) | 604×315 | 36.7% |
| soldier_attack | 2048×2048 | (298,479,1832,1525) | 1534×1046 | 38.3% |
| soldier_win | 2048×2048 | (417,392,1764,1520) | 1347×1128 | 36.2% |

⚠️ **m2（食叶虫）是唯一例外**：它的画面内容真的顶到画布左边和上边（7 帧里
frame002 甚至铺满整张 720×720），裁边会切掉实体 ⇒ 保原画布不裁。它在游戏里
因此看起来比 m1/m3 略高，这是**素材出框**，不是布局问题（已记进报告与素材比文档）。

裁完若长边 > 512 再等比缩到 512（口径同 convert_grow_fx.py：WebP q95，视觉无损级）。
**三种战士状态各裁各的窗口**（不统一窗口：攻击帧有长兵器，统一窗口会把待机挤成 0.94 倍）。

## B8 色彩归一（玄参第三轮：「待机图偏暗」）

只动**待机帧**（攻击/胜利帧是参照系，一个像素不改），统一 gamma（不做 per-channel
gain：per-channel 要把蓝通道拉 1.71×，花瓣会从暖黄跑成灰紫）：

  γ=1.0 → 135.25  γ=0.7365 → 153.87  γ=0.70 → 156.84
  γ=0.66 → 160.26 ← 采用（与攻击帧 159.38 差 +0.32%）
  γ=0.65 → 161.10  γ=0.62 → 163.75

alpha 通道原样保留（只对 RGB 建 LUT）。

排他：*.zip / *.mp4 / .DS_Store / 房屋浇水(1).png（浇水变体不接）。
重复执行安全：`--force` 强制重导，否则目标比源新就跳过。
"""

from __future__ import annotations

import os
import sys

from PIL import Image

SRC = "/Volumes/DataHD-2TB/素材归档/专注素材/花园守护"
DST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "guard")

LONG_SIDE = 512       # 裁边后长边上限（战内渲染 ≤78pt，×3dpr×2 ≈ 470px，余量充足）
QUALITY = 95          # WebP q95（项目压缩管线统一口径）
ALPHA_THRESHOLD = 128 # 🔴 实体判据：> 128 才算实体（> 8 会把半透明阴影算进来）

# B8 色彩归一（只对待机帧）。
IDLE_GAMMA = 0.615       # soldier_idle 19 帧（均值对齐攻击帧 158.5，实测 −1.02%）
STAND_GAMMA = 0.806      # soldier_stand 单张（原始均值偏暗，0.806 后对齐攻击帧）


class Group:
    """一组素材的转换规格。"""

    def __init__(self, name: str, src: str, dst: str, frames: int | None,
                 crop: bool = True, resize: bool = True, gamma: float | None = None):
        self.name = name
        self.src = src            # 源相对路径模板（帧组带 {i:03d}）
        self.dst = dst            # 目标相对路径模板
        self.frames = frames      # None = 单张
        self.crop = crop          # False = 不裁（房屋）
        self.resize = resize      # False = 不缩（房屋）
        # B12：per-group gamma（None = 不调；亮度以攻击帧 158.5 为基准，量法见
        # docs/花园守卫_素材实体比记录_v1.md §6。待机帧 0.615 / 站立静态 0.806）
        self.gamma = gamma

    def srcs(self) -> list[str]:
        if self.frames is None:
            return [self.src]
        return [self.src.format(i=n) for n in range(1, self.frames + 1)]

    def dsts(self) -> list[str]:
        if self.frames is None:
            return [self.dst]
        return [self.dst.format(i=n) for n in range(1, self.frames + 1)]


GROUPS: list[Group] = [
    Group("soldier_idle", "向日葵战士/待机动画/frame{i:03d}.png",
          "soldier_idle/frame{i:03d}.webp", 19, gamma=IDLE_GAMMA),
    Group("soldier_stand", "向日葵战士/向日葵战士待机.png",
          "soldier_stand.webp", None, gamma=STAND_GAMMA),
    Group("soldier_attack", "向日葵战士/向日葵战士攻击.png",
          "soldier_attack.webp", None),
    Group("soldier_win", "向日葵战士/向日葵战士胜利.png",
          "soldier_win.webp", None),
    Group("monster_m1", "馋光鼠/馋光鼠进攻/frame{i:03d}.png",
          "monster_m1/frame{i:03d}.webp", 7),
    Group("monster_m2", "食叶虫/食叶虫/frame{i:03d}.png",
          "monster_m2/frame{i:03d}.webp", 7),
    Group("monster_m3", "顺手贼/顺手贼/frame{i:03d}.png",
          "monster_m3/frame{i:03d}.webp", 7),
    # 房屋：实体占 94.6%，裁了会丢轮廓，保持原尺寸原样（L1 底图）。
    Group("house", "房屋/房屋(1).png", "house.webp", None, crop=False, resize=False),
]


def solid_bbox(im: Image.Image, thresh: int = ALPHA_THRESHOLD) -> tuple[int, int, int, int] | None:
    """alpha > thresh 的实体 bbox（left, top, right, bottom；right/bottom 开区间）。"""
    alpha = im.convert("RGBA").split()[3].point(lambda v: 255 if v > thresh else 0)
    return alpha.getbbox()


def union_bbox(paths: list[str]) -> tuple[int, int, int, int]:
    """一组帧的**并集** bbox（同一裁切窗口 ⇒ 动画不抖）。"""
    left = top = 10 ** 9
    right = bottom = -1
    for p in paths:
        box = solid_bbox(Image.open(p))
        if box is None:
            continue
        left = min(left, box[0])
        top = min(top, box[1])
        right = max(right, box[2])
        bottom = max(bottom, box[3])
    if right < 0:
        raise ValueError(f"整组素材全透明：{paths[0]}")
    return (left, top, right, bottom)


def apply_gamma(im: Image.Image, gamma: float) -> Image.Image:
    """RGB 三通道幂曲线映射，alpha 原样保留（`out = 255 * (in/255) ** gamma`）。"""
    if gamma == 1.0:
        return im
    lut = [min(255, round(255.0 * ((i / 255.0) ** gamma))) for i in range(256)]
    r, g, b, a = im.split()
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))


def mean_luma(im: Image.Image) -> float:
    """alpha ≥ 16 的像素的平均亮度（Rec.709 权重）。"""
    px = im.convert("RGBA").load()
    w, h = im.size
    rs = gs = bs = 0.0
    n = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16:
                continue
            rs += r
            gs += g
            bs += b
            n += 1
    if n == 0:
        return 0.0
    return 0.2126 * (rs / n) + 0.7152 * (gs / n) + 0.0722 * (bs / n)


def resize_long_side(im: Image.Image, edge: int) -> Image.Image:
    """长边缩到 [edge]（等比，不拉伸）——比「绝对 512×512」更合适：裁边后长宽比各异。"""
    w, h = im.size
    if max(w, h) <= edge:
        return im
    scale = edge / max(w, h)
    return im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)


def main() -> int:
    force = "--force" in sys.argv
    total = 0
    print(f"{'组':<16}{'裁切窗口':<26}{'输出':<12}{'实体/画布(裁后)':<12}备注")
    for g in GROUPS:
        srcs = [os.path.join(SRC, s) for s in g.srcs()]
        missing = [s for s in srcs if not os.path.exists(s)]
        if missing:
            print(f"MISS  {g.name}: {missing[0]}")
            continue
        crop_box = union_bbox(srcs) if g.crop else None
        for src, dst_rel in zip(srcs, g.dsts()):
            dst = os.path.join(DST, dst_rel)
            if (not force and os.path.exists(dst)
                    and os.path.getmtime(dst) >= os.path.getmtime(src)):
                total += os.path.getsize(dst)
                continue
            im = Image.open(src).convert("RGBA")
            canvas = im.size
            if crop_box is not None:
                im = im.crop(crop_box)
            if g.resize:
                im = resize_long_side(im, LONG_SIDE)
            gamma = (g.gamma if g.gamma is not None else 1.0)
            before = mean_luma(im)
            im = apply_gamma(im, gamma)
            after = mean_luma(im)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im.save(dst, "WEBP", quality=QUALITY, method=6)
            total += os.path.getsize(dst)
            box = solid_bbox(im) or (0, 0, *im.size)
            fill = (box[2] - box[0]) * (box[3] - box[1]) / (im.size[0] * im.size[1]) * 100
            note = f"luma {before:.1f}→{after:.1f} γ={gamma}" if gamma != 1.0 else ""
            if dst_rel.endswith("frame001.webp") or g.frames is None:
                cb = f"{crop_box}" if crop_box else "不裁"
                print(f"{g.name:<16}{cb:<26}{im.size[0]}×{im.size[1]:<7}{fill:5.1f}%      "
                      f"画布 {canvas[0]}×{canvas[1]}  {note}")
    print(f"—— assets/guard 总计 {total / 1024 / 1024:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
