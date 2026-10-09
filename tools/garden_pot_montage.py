#!/usr/bin/env python3
"""全局等盆验证拼板图（2026-10-09 C42）。

模拟游戏渲染口径：每张资产放入 aspect = 2000/1720 的盒子 BoxFit.contain
（等高盒，高度撑满、窄画布居中），与 lib 侧 kGardenArtAspect 行为一致。

上排：6 物种 adult 各一张 —— 验证跨物种盆等大。
下排：sunflower 全生命周期 —— 验证同物种跨阶段/跨枯死盆等大。
     （sunflower 为 legacy 1200×2000 画布，不重排也应等盆）
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "plants"

CELL_W = 280
CANVAS_ASPECT = 2000 / 1720  # 与 kGardenArtAspect 一致
CELL_H = round(CELL_W * CANVAS_ASPECT)
BG = (250, 247, 240)
GRID = (225, 220, 210)
TEXT = (90, 85, 75)
BASE = (200, 80, 60)  # 盆底基线参考线

FONT = None
for cand in (
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
):
    if Path(cand).exists():
        FONT = ImageFont.truetype(cand, 16)
        break


def cell(img_path: Path, label: str) -> Image.Image:
    cell_img = Image.new("RGB", (CELL_W, CELL_H), BG)
    d = ImageDraw.Draw(cell_img)
    art = Image.open(img_path).convert("RGBA")
    # BoxFit.contain
    scale = min(CELL_W / art.width, CELL_H / art.height)
    disp = art.resize((round(art.width * scale), round(art.height * scale)))
    ox = (CELL_W - disp.width) // 2
    oy = CELL_H - disp.height  # 底对齐（游戏内盆落在格底）
    cell_img.paste(disp, (ox, oy), disp)
    # 外框 + 盆底基线
    d.rectangle([0, 0, CELL_W - 1, CELL_H - 1], outline=GRID, width=2)
    d.line([(6, CELL_H - 6), (CELL_W - 6, CELL_H - 6)], fill=BASE, width=2)
    if FONT:
        d.text((CELL_W // 2, CELL_H - 28), label, fill=TEXT,
               font=FONT, anchor="mm")
    return cell_img


def row(paths_labels, pad=8):
    strip = Image.new("RGB", (len(paths_labels) * (CELL_W + pad) + pad,
                              CELL_H + 2 * pad), (255, 255, 255))
    for i, (p, label) in enumerate(paths_labels):
        strip.paste(cell(p, label), (pad + i * (CELL_W + pad), pad))
    return strip


def main() -> None:
    species = ["sunflower", "tomato", "strawberry",
               "coral_orchid", "moon_orchid", "jade_hydrangea"]
    names = {"sunflower": "向日葵", "tomato": "番茄", "strawberry": "草莓",
             "coral_orchid": "珊瑚兰", "moon_orchid": "月光兰",
             "jade_hydrangea": "玉绣球"}
    top = row([(ASSETS / s / f"species_{s}_adult.png", names[s])
               for s in species])

    sun_life = [("sprout", "幼芽"), ("adult", "成株"),
                ("adult_bloomed", "开花"), ("adult_wilting", "枯萎中"),
                ("adult_dead", "枯死")]
    bottom = row([(ASSETS / "sunflower" / f"species_sunflower_{stage}.png",
                   f"{cn}")
                  for stage, cn in sun_life])

    pad = 12
    W = max(top.width, bottom.width) + 2 * pad
    H = top.height + bottom.height + 2 * pad + 8
    out = Image.new("RGB", (W, H), (255, 255, 255))
    out.paste(top, (pad, pad))
    out.paste(bottom, (pad, pad + top.height + 8))
    dest = ROOT / "build" / "garden_pot_montage.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(f"saved {dest} ({out.width}x{out.height})")


if __name__ == "__main__":
    main()
