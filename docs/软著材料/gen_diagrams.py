#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成软著材料用的两张示意图（PIL 手绘，嵌入真实算法口径）。
① 系统分层架构图
② 阳光经济模型：有效值与年段日上限
输出：OUT 目录下的 arch_diagram.png / sun_economy_diagram.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = "/Users/wangjunchao/WorkBuddy/sunflowerTime/docs/软著材料"

FONTS = [
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/ArialHB.ttc",
]


def load_font(size):
    for path in FONTS:
        if not os.path.exists(path):
            continue
        for idx in (0, 1, 2):
            try:
                return ImageFont.truetype(path, size, index=idx)
            except Exception:
                continue
    return ImageFont.load_default()


def new_canvas(w, h):
    img = Image.new("RGB", (w, h), (255, 255, 255))
    return img, ImageDraw.Draw(img)


def text_w(draw, s, font):
    b = draw.textbbox((0, 0), s, font=font)
    return b[2] - b[0]


def draw_text_center(draw, cx, y, s, font, fill=(0, 0, 0)):
    w = text_w(draw, s, font)
    draw.text((cx - w / 2, y), s, font=font, fill=fill)


def draw_text_left(draw, x, y, s, font, fill=(0, 0, 0)):
    draw.text((x, y), s, font=font, fill=fill)


def rounded_box(draw, x0, y0, x1, y1, fill, outline=(60, 60, 60), width=2, radius=10):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill,
                           outline=outline, width=width)


# ---------------------------------------------------------------------------
# ① 系统分层架构图
# ---------------------------------------------------------------------------
def build_architecture():
    W, H = 1100, 760
    img, d = new_canvas(W, H)
    fTitle = load_font(30)
    fBox = load_font(20)
    fSub = load_font(14)
    fArrow = load_font(15)

    draw_text_center(d, W / 2, 24, "系统分层架构图", fTitle, (20, 40, 90))

    # 主列三层（表现→领域→数据）
    col_x0, col_x1 = 300, 760
    layers = [
        ("表现层 Presentation", "UI / 交互 / 状态管理 (Riverpod)", (220, 235, 245)),
        ("领域层 Domain", "实体 / 领域服务 / Repository 接口（flutter-free）", (215, 240, 220)),
        ("数据层 Data", "Drift + SQLCipher 本地加密库 / shared_preferences / secure_storage", (248, 235, 210)),
    ]
    y = 110
    bh = 96
    gap = 56
    boxes = []
    for title, sub, color in layers:
        rounded_box(d, col_x0, y, col_x1, y + bh, fill=color)
        draw_text_center(d, (col_x0 + col_x1) / 2, y + 22, title, fBox, (20, 40, 90))
        # 子说明可能过长，分两行
        draw_text_center(d, (col_x0 + col_x1) / 2, y + 56, sub, fSub, (40, 40, 40))
        boxes.append((y, y + bh))
        y += bh + gap

    # 依赖方向箭头（向下）
    for i in range(len(boxes) - 1):
        mid_y = (boxes[i][1] + boxes[i + 1][0]) / 2
        ax = (col_x0 + col_x1) / 2
        d.line([(ax, boxes[i][1] + 6), (ax, boxes[i + 1][0] - 6)], fill=(30, 30, 30), width=2)
        d.polygon([(ax, boxes[i + 1][0] - 2), (ax - 7, boxes[i + 1][0] - 14), (ax + 7, boxes[i + 1][0] - 14)], fill=(30, 30, 30))
    draw_text_center(d, (col_x0 + col_x1) / 2 + 70, (boxes[0][1] + boxes[1][0]) / 2 - 10, "依赖方向", fArrow, (120, 60, 60))
    draw_text_center(d, (col_x0 + col_x1) / 2 + 70, (boxes[1][1] + boxes[2][0]) / 2 - 10, "依赖方向", fArrow, (120, 60, 60))

    # 右侧支撑层（平台/核心/共享）
    sup = [
        ("平台层 Platform", "wakelock / 设备方向 / 音频 原生桥接", (235, 235, 245)),
        ("核心层 Core", "全局常量 prd_params / 工具函数", (240, 240, 240)),
        ("共享层 Shared", "跨模块复用组件与模型", (245, 238, 235)),
    ]
    sx0, sx1 = 820, 1070
    sy = 140
    for title, sub, color in sup:
        rounded_box(d, sx0, sy, sx1, sy + 80, fill=color)
        draw_text_center(d, (sx0 + sx1) / 2, sy + 20, title, fBox, (20, 40, 90))
        draw_text_center(d, (sx0 + sx1) / 2, sy + 48, sub, fSub, (40, 40, 40))
        # 虚线连到主列
        d.line([(col_x1, sy + 40), (sx0, sy + 40)], fill=(150, 150, 150), width=1)
        sy += 110

    # 左侧预留接入点（虚线框）
    px0, px1 = 40, 270
    py0, py1 = 470, 590
    d.rounded_rectangle([px0, py0, px1, py1], radius=10, outline=(180, 120, 40), width=2)
    draw_text_center(d, (px0 + px1) / 2, py0 + 18, "账号 / 云同步", fBox, (160, 100, 20))
    draw_text_center(d, (px0 + px1) / 2, py0 + 50, "接入点（预留）", fBox, (160, 100, 20))
    draw_text_center(d, (px0 + px1) / 2, py0 + 82, "领域层仅依赖接口", fSub, (120, 80, 20))
    draw_text_center(d, (px0 + px1) / 2, py0 + 104, "MVP 以本地 Repository 实装", fSub, (120, 80, 20))
    d.line([((col_x0 + col_x1) / 2, (boxes[2][0] + boxes[2][1]) / 2), ((px0 + px1) / 2, py0 + 20)], fill=(180, 120, 40), width=1)

    path = os.path.join(OUT, "arch_diagram.png")
    img.save(path)
    return path


# ---------------------------------------------------------------------------
# ② 阳光经济模型：有效值与年段日上限
# ---------------------------------------------------------------------------
def build_sun_economy():
    W, H = 1100, 760
    img, d = new_canvas(W, H)
    fTitle = load_font(28)
    fBox = load_font(19)
    fSub = load_font(14)
    fFormula = load_font(16)

    draw_text_center(d, W / 2, 22, "阳光经济模型：有效值与年段日上限", fTitle, (20, 40, 90))

    # 左：公式面板
    fx0, fy0, fx1, fy1 = 40, 90, 540, 360
    rounded_box(d, fx0, fy0, fx1, fy1, fill=(245, 248, 252), outline=(60, 90, 150), width=2)
    draw_text_left(d, fx0 + 20, fy0 + 18, "计算口径（2026-09-23 起）", fBox, (20, 40, 90))
    formulas = [
        "专注 1 分钟 = 1 阳光",
        "有效阳光 = min(本场专注阳光, 今日剩余额度)",
        "今日剩余额度 = 年段日上限 − 今日已入账专注阳光",
        "（消耗侧：显示价 = 扣费价，",
        "  不再叠加分龄系数 K）",
    ]
    ty = fy0 + 64
    for line in formulas:
        draw_text_left(d, fx0 + 24, ty, line, fFormula, (30, 30, 30))
        ty += 30

    # 右：年段日上限表
    tx0, ty0, tx1, ty1 = 580, 90, 1060, 360
    rounded_box(d, tx0, ty0, tx1, ty1, fill=(252, 248, 240), outline=(150, 110, 40), width=2)
    draw_text_left(d, tx0 + 20, ty0 + 18, "年段日上限（硬封顶）", fBox, (140, 90, 20))
    tiers = [
        ("低年段 6–8 岁", "60 分钟 / 日", (70, 130, 200)),
        ("中年级 9–10 岁", "90 分钟 / 日", (60, 160, 90)),
        ("高年级 11–12 岁", "120 分钟 / 日", (200, 120, 40)),
    ]
    ry = ty0 + 64
    for name, cap, col in tiers:
        draw_text_left(d, tx0 + 24, ry, name, fFormula, (30, 30, 30))
        draw_text_left(d, tx0 + 250, ry, cap, fFormula, col)
        ry += 44

    # 底部：实得阳光 vs 专注分钟 图
    gx0, gy0, gx1, gy1 = 110, 430, 1000, 700
    rounded_box(d, gx0, gy0, gx1, gy1, fill=(255, 255, 255), outline=(180, 180, 180), width=1)
    draw_text_center(d, (gx0 + gx1) / 2, gy0 + 12, "实得阳光 vs 专注分钟（1:1，受年段日上限封顶）", fSub, (40, 40, 40))

    # 坐标轴
    ax_x, ax_y = gx0 + 70, gy1 - 50
    ax_w, ax_h = 760, 180
    d.line([(ax_x, gy0 + 60), (ax_x, ax_y)], fill=(80, 80, 80), width=2)   # y
    d.line([(ax_x, ax_y), (ax_x + ax_w, ax_y)], fill=(80, 80, 80), width=2)  # x
    draw_text_left(d, ax_x - 30, gy0 + 50, "阳光", fSub, (40, 40, 40))
    draw_text_left(d, ax_x + ax_w - 30, ax_y + 8, "专注分钟", fSub, (40, 40, 40))

    max_val = 130  # 分钟/阳光 轴上限
    def sx(v):
        return ax_x + (v / max_val) * ax_w
    def sy(v):
        return ax_y - (v / max_val) * ax_h

    caps = [("低 60", 60, (70, 130, 200)), ("中 90", 90, (60, 160, 90)), ("高 120", 120, (200, 120, 40))]
    for label, cap, col in caps:
        # 1:1 线段 0->cap，再水平到 max
        d.line([(sx(0), sy(0)), (sx(cap), sy(cap))], fill=col, width=3)
        d.line([(sx(cap), sy(cap)), (sx(max_val), sy(cap))], fill=col, width=3)
        draw_text_left(d, sx(cap) - 4, sy(cap) - 18, label, fSub, col)

    # 网格刻度
    for t in (30, 60, 90, 120):
        d.line([(sx(t), ax_y - 3), (sx(t), ax_y + 3)], fill=(120, 120, 120), width=1)
        d.line([(ax_x - 3, sy(t)), (ax_x + 3, sy(t))], fill=(120, 120, 120), width=1)

    path = os.path.join(OUT, "sun_economy_diagram.png")
    img.save(path)
    return path


if __name__ == "__main__":
    p1 = build_architecture()
    p2 = build_sun_economy()
    print("生成:", p1, os.path.getsize(p1), "bytes")
    print("生成:", p2, os.path.getsize(p2), "bytes")
