#!/usr/bin/env python3
"""向日葵守卫 · 大招素材转换管线（一次性离线运行，产物入仓）。

口径（PRD §3-10 / C6 / 架构 §1.4）：
  * 🔴 2026-11-23 C129（玄参拍板「大招动画帧中英统一一套，区别只在音效」）：
      「释放大招 27 帧英文」+「中文大招 27 帧」**退役**，改接源目录
      「统一大招动画帧」27 帧 PNG（720×720）→ assets/guard/soldier_ultimate/
      frame001..027.webp（该目录语义变为**统一帧**，语言无关）。
      assets/guard/soldier_ultimate_zh/ 目录 + pubspec 声明 +
      prd_params `kUltimateFxCastDirZh` 一并删除；cast 音效仍分语言
      （guard_ultimate_cast.mp3 / guard_ultimate_cast_zh.mp3 保留）。
      🔴 2026-11-23 C130（玄参两条否决：**「你不要给我切割」+「放大招的时候
      战士变小了」）：裁边窗口 **废除**，素材**一概不裁切** —— 统一帧保留原始
      **720×720 全画布**导出（光效帧 012..026 铺满画布，任何窗口都会把光效
      切出硬边）。「标称 = 视觉」改由**绘制框按实体占比补偿**：cast 绘制高 =
      待机绘制高 × (待机实体占比 / 大招实体占比)（几何在
      `guard_card_layout.ultimateCastPaintHeight`，待机实体并集 = 全画布
      362×372、统一帧战士实体帧子集并集高 255/720 ⇒ 60 × 720/255 ≈ 169.41pt；
      越界部分由卡根 Stack `Clip.none` 放行）。亮度归一口径不变（见下）。
      - 亮度归一：🔴 校准口径修订 —— 统一素材的光效亮度分布与旧两版不同
        （旧 EN 自检 27 帧均值 156.59 时其战士实体帧已达 159~169、高于待机），
        若仍按 27 帧均值对齐 156.77 会反解出 <1 的增益把战士压暗。故按玄参
        「战士亮度与待机对齐」的**本意**改用**纯战士实体帧子集（001..009/027）**
        校准：实体帧原始 luma 144.49 ⇒ 增益 **1.1027**（「乘后 255 截断」二分
        反解）⇒ 实体帧导出后 luma = **156.77**（= 待机参考，逐位对齐）；27 帧
        全帧自检均值 ≈ 172.65（光效更亮所致，仅记录不做目标）。alpha 通道
        原样保留（只在 RGB 上做亮度）。
  * 「释放大招」旧英文 27 帧（720×720）→ 裁 (150,152,562,532)=412×380、增益
      1.2228（历史口径，已被统一帧取代）；「中文大招」27 帧同理退役（原窗口
      (150,152,612,532)=462×380、增益 1.1607，备份留在 assets/_originals/）。
  * 🔴 2026-11-22 玄参「替换现有大招特效」：特效段 27 帧源由「大招特效」
      （旧版）改为**「统一技能特效」**（新版，1470×630，画面/音轨与旧版
      不同）；路径 assets/guard/ultimate_fx/ 与帧数 27、音轨时长 4.086s、
      所有 Dart 常量均不变 ⇒ 纯素材替换，代码零改动。
      `python3 tools/convert_guard_ultimate_assets.py --force-fx` 强制重转 FX
      帧 + 重抽 FX 音轨（默认仍「已在仓跳过」以保持入仓字节稳定）。
  * 三段 mp4 抽 AAC→mp3（192k / 44.1k / 2ch）；产物已在仓时跳过（不重编码）。
      - 释放大招.mp4 → assets/audio/sfx/guard_ultimate_cast.mp3
      - 中文大招.mp4 → assets/audio/sfx/guard_ultimate_cast_zh.mp3（音效分语言，保留）
      - 统一技能特效.mp4 → assets/audio/sfx/guard_ultimate_fx.mp3（2026-11-22 换源）
  * 🔴 不套 normalize_plant_art.py（1440×2000 植物专用，C13）；这里只做
    PNG→WebP 有损压缩（q92），保留原始尺寸与透明通道（🔴 C130 起不裁切）。
  * 其余待机 / 受击 / 胜利 / 未命名 mp4 素材零改动。

依赖：Pillow（WebP 编码）、系统 ffmpeg（音轨抽取）。
用法：python3 tools/convert_guard_ultimate_assets.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageEnhance, ImageStat

SOURCE_DIR = Path(
    "/Volumes/DataHD-2TB/素材归档/专注素材/花园守护/向日葵战士"
)
REPO_ROOT = Path(__file__).resolve().parent.parent

FRAME_COUNT = 27
FRAME_QUALITY = 92

# 🔴 大招特效帧（横向通道素材）：产物已在仓（27 帧连号）时跳过重转。
# 2026-11-22 换源：旧「大招特效」→「统一技能特效」（玄参拍板替换）。
FX_SRC_DIR = SOURCE_DIR / "统一技能特效"
FX_DST_DIR = REPO_ROOT / "assets/guard/ultimate_fx"
# --force-fx：强制重转 FX 帧 + 重抽 FX 音轨（换源替换时用）。
FORCE_FX = "--force-fx" in sys.argv

# 🔴 统一大招帧（C129 接入 / 🔴 C130 玄参「你不要给我切割」）：**不裁切**。
# 统一帧保留原始 720×720 全画布（光效帧 012..026 铺满画布，任何裁窗都会把
# 光效切出硬边）；「战士与待机大小一致」由**绘制框按实体占比补偿**实现
# （guard_card_layout.ultimateCastPaintHeight，实测口径：战士实体帧子集
# 001..009/027 的 alpha>128 并集 bbox = (215,214,468,469) = 253×255，
# 实体中心 (341.5, 341.5)/720 —— 与待机 362×372 实体并集=全画布对齐）。
# 🔴 2026-11-22 玄参「替换向日葵大招动作美术」（只换美术、其余零改动）：
#   源由「统一大招动画帧」改为「大招动作优化」27 帧 720×720；几何/音轨/
#   fx/代码一律不动。旧源备份 soldier_ultimate_unified 保留不删，新源备份另起。
CAST_SRC_DIR = SOURCE_DIR / "大招动作优化"
CAST_BACKUP_DIR = REPO_ROOT / "assets/_originals/soldier_ultimate_actionopt"

# 🔴 亮度增益（RGB 乘后截断到 255；alpha 不动）。待机实测 luminance
# （alpha>128 掩码）= 156.77。统一素材**战士实体帧子集**（001..009/027）全画布
# 原始 luma = 144.49，按「乘后截断」模型二分反解增益 1.1027 ⇒ 实体帧导出后
# 156.77（= 待机，逐位对齐；裁切与否不影响 alpha>128 掩码内的亮度统计）。
# 🔴 不按 27 帧均值对齐：统一素材光效更亮，27 帧均值口径会反解出 <1 增益把
# 战士压暗（违背「战士亮度与待机对齐」本意）。
# 🔴 2026-11-22 新素材「大招动作优化」实体帧原始 luma = 149.39（比旧 144.49 更亮），
#   沿用 1.1027 会导出 162.26（偏亮）；按同款「乘后截断」模型二分反解增益
#   1.0586 ⇒ 实体帧导出 156.77（= 待机，逐位对齐）。自检判据不变。
CAST_BRIGHTNESS_GAIN = 1.0586
IDLE_LUMA_REFERENCE = 156.77  # 待机 19 帧实测均值（对账用，不参与导出）

# 亮度校准用的**战士实体帧**下标（0 基；001..009 + 027）。导出自检按此子集
# 对账待机参考；光效帧不做亮度目标。
CAST_SOLDIER_ONLY_FRAME_INDICES = tuple(list(range(0, 9)) + [26])

# (源目录, 产物目录, 原图备份目录, 亮度增益)——🔴 C130 无裁边。
CAST_GROUPS: tuple[tuple[Path, Path, Path, float], ...] = (
    (
        CAST_SRC_DIR,
        REPO_ROOT / "assets/guard/soldier_ultimate",
        CAST_BACKUP_DIR,
        CAST_BRIGHTNESS_GAIN,
    ),
)

AUDIO_GROUPS: tuple[tuple[Path, Path], ...] = (
    (SOURCE_DIR / "释放大招.mp4", REPO_ROOT / "assets/audio/sfx/guard_ultimate_cast.mp3"),
    # 🔴 中文大招音效单独抽（AAC 4.06s，参数与英文/特效一致）。C129：帧统一了，
    # 音效仍分语言 ⇒ 本音轨保留。
    (SOURCE_DIR / "中文大招.mp4", REPO_ROOT / "assets/audio/sfx/guard_ultimate_cast_zh.mp3"),
    # 🔴 2026-11-22 换源：音轨从「统一技能特效.mp4」提取（旧「大招特效.mp4」退役）。
    (SOURCE_DIR / "统一技能特效.mp4", REPO_ROOT / "assets/audio/sfx/guard_ultimate_fx.mp3"),
)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def dir_has_full_frames(dst_dir: Path) -> bool:
    """产物目录是否已有恰好 FRAME_COUNT 张连号 webp（幂等跳过判据）。"""
    if not dst_dir.is_dir():
        return False
    produced = sorted(p.name for p in dst_dir.glob("frame*.webp"))
    expected = [f"frame{i:03d}.webp" for i in range(1, FRAME_COUNT + 1)]
    return produced == expected


def backup_source_frames(src_dir: Path, backup_dir: Path) -> None:
    """把源 PNG 原样复制到 assets/_originals/（该目录不在 pubspec 声明中，不入包）。"""
    backup_dir.mkdir(parents=True, exist_ok=True)
    for i in range(1, FRAME_COUNT + 1):
        src = src_dir / f"frame{i:03d}.png"
        if not src.is_file():
            fail(f"缺帧: {src}")
        dst = backup_dir / src.name
        if not dst.is_file() or dst.stat().st_size != src.stat().st_size:
            shutil.copy2(src, dst)


def brighten_rgba(rgba: Image.Image, gain: float) -> Image.Image:
    """只在 RGB 上提亮，alpha 通道逐位保留（不产生新半透明边）。"""
    if gain == 1.0:
        return rgba
    rgb = ImageEnhance.Brightness(rgba.convert("RGB")).enhance(gain)
    out = rgb.convert("RGBA")
    out.putalpha(rgba.getchannel("A"))
    return out


def convert_frames(
    src_dir: Path,
    dst_dir: Path,
    crop_box: tuple[int, int, int, int] | None = None,
    brightness_gain: float = 1.0,
) -> None:
    if not src_dir.is_dir():
        fail(f"源帧目录不存在（源盘未挂载？）: {src_dir}")
    dst_dir.mkdir(parents=True, exist_ok=True)
    for i in range(1, FRAME_COUNT + 1):
        src = src_dir / f"frame{i:03d}.png"
        if not src.is_file():
            fail(f"缺帧: {src}")
        dst = dst_dir / f"frame{i:03d}.webp"
        with Image.open(src) as img:
            rgba = img.convert("RGBA") if "A" in img.getbands() else img.convert("RGBA")
            if crop_box is not None:
                rgba = rgba.crop(crop_box)
            rgba = brighten_rgba(rgba, brightness_gain)
            rgba.save(dst, format="WEBP", quality=FRAME_QUALITY, method=4)
    # 连号无缺 + 无多余帧（目录里恰好 FRAME_COUNT 张 webp）。
    produced = sorted(p.name for p in dst_dir.glob("frame*.webp"))
    expected = [f"frame{i:03d}.webp" for i in range(1, FRAME_COUNT + 1)]
    if produced != expected:
        fail(f"帧连号校验失败: {dst_dir} -> {produced}")
    print(f"OK frames: {src_dir.name} -> {dst_dir} ({len(produced)} webp)")


def _frame_luma(rgba: Image.Image) -> float:
    """单帧 alpha>128 掩码的加权 luminance（与历史 measure 口径一致）。"""
    alpha = rgba.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > 128 else 0)
    mean_rgb = ImageStat.Stat(rgba.convert("RGB"), mask=mask).mean
    return 0.299 * mean_rgb[0] + 0.587 * mean_rgb[1] + 0.114 * mean_rgb[2]


def measure_cast_frames(dst_dir: Path) -> None:
    """导出后自检：尺寸 / 战士实体并集几何（绘制框补偿的实测依据）/ luminance。

    🔴 亮度对账两条（C129 口径）：
      * **战士实体帧子集**（[CAST_SOLDIER_ONLY_FRAME_INDICES]）均值必须 ≈
        [IDLE_LUMA_REFERENCE]（156.77）—— 这才是「战士亮度与待机对齐」的判据；
      * 27 帧全帧均值仅记录（统一素材光效更亮，均值天然高于待机，不是目标）。

    🔴 C130 几何对账（绘制框补偿的实测依据，与
    `guard_card_layout.ultimateCastPaintHeight` / 常量逐位对账）：
      * 战士实体帧子集 alpha>128 **并集 bbox** 高（应 = 255）与中心（应 ≈
        341.5, 341.5）—— 绘制框按「待机画高 × 720/并集高」补偿、按中心配准；
      * 待机参考（assets/guard/soldier_idle）：实体并集 = 全画布 362×372
        （逐帧高度占比均值 0.9929 / 最大 1.0，中心 (0.5, 0.5)）。
    """
    sizes: set[tuple[int, int]] = set()
    lumas: list[float] = []
    soldier_lumas: list[float] = []
    soldier_union: tuple[int, int, int, int] | None = None
    for i in range(1, FRAME_COUNT + 1):
        with Image.open(dst_dir / f"frame{i:03d}.webp") as img:
            rgba = img.convert("RGBA")
            sizes.add(rgba.size)
            if (i - 1) in CAST_SOLDIER_ONLY_FRAME_INDICES:
                alpha = rgba.getchannel("A")
                bbox = alpha.point(lambda v: 255 if v > 128 else 0).getbbox()
                if bbox is not None:
                    soldier_union = (
                        bbox
                        if soldier_union is None
                        else (
                            min(soldier_union[0], bbox[0]),
                            min(soldier_union[1], bbox[1]),
                            max(soldier_union[2], bbox[2]),
                            max(soldier_union[3], bbox[3]),
                        )
                    )
                soldier_lumas.append(_frame_luma(rgba))
            else:
                lumas.append(_frame_luma(rgba))
    union_text = ""
    if soldier_union is not None:
        u = soldier_union
        union_text = (
            f" soldier_union={u} union_h={u[3] - u[1]} "
            f"center=({(u[0] + u[2]) / 2:.1f},{(u[1] + u[3]) / 2:.1f})"
        )
    print(
        f"CHECK {dst_dir.name}: size={sorted(sizes)}{union_text} "
        f"soldier_luma={sum(soldier_lumas) / len(soldier_lumas):.2f} "
        f"(idle ref={IDLE_LUMA_REFERENCE}) "
        f"all27_luma={sum(lumas) / len(lumas):.2f} (记录值，非目标)"
    )


def extract_audio(src_mp4: Path, dst_mp3: Path, force: bool = False) -> None:
    if not force and dst_mp3.is_file() and dst_mp3.stat().st_size >= 1000:
        # 音效分语言保留口径：已在仓的 mp3 不重编码，保持入仓字节稳定。
        print(f"SKIP audio (already present): {dst_mp3.name}")
        return
    if force:
        print(f"FORCE audio: {dst_mp3.name} <- {src_mp4.name}")
    if not src_mp4.is_file():
        fail(f"源 mp4 不存在（源盘未挂载？）: {src_mp4}")
    dst_mp3.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(src_mp4),
        "-vn",
        "-acodec", "libmp3lame",
        "-b:a", "192k",
        "-ar", "44100",
        "-ac", "2",
        str(dst_mp3),
    ]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        fail("系统未安装 ffmpeg")
    except subprocess.CalledProcessError as exc:
        fail(f"ffmpeg 抽取失败: {src_mp4} ({exc})")
    if not dst_mp3.is_file() or dst_mp3.stat().st_size < 1000:
        fail(f"音轨产物异常（过小/缺失）: {dst_mp3}")
    print(f"OK audio: {src_mp4.name} -> {dst_mp3} ({dst_mp3.stat().st_size} bytes)")


def main() -> None:
    print(f"SOURCE_DIR = {SOURCE_DIR}")
    if not SOURCE_DIR.is_dir():
        fail("源盘未挂载，终止（禁止臆造素材）")
    # 特效帧 1470×630 横向通道素材保持原尺寸（宽高比 2.333 由
    # GuardUltimateFx 绘制盒反推，不在此裁 / 不做语言切换）；已在仓时跳过。
    if dir_has_full_frames(FX_DST_DIR) and not FORCE_FX:
        print(f"SKIP frames (already present): {FX_DST_DIR}")
    else:
        convert_frames(FX_SRC_DIR, FX_DST_DIR)
    for src, dst, backup_dir, gain in CAST_GROUPS:
        backup_source_frames(src, backup_dir)
        convert_frames(src, dst, brightness_gain=gain)
        measure_cast_frames(dst)
    for idx, (src, dst) in enumerate(AUDIO_GROUPS):
        # FX 音轨（末项）在 --force-fx 下强制重抽；cast 两版永不重编码。
        extract_audio(src, dst, force=FORCE_FX and idx == len(AUDIO_GROUPS) - 1)
    print("ALL DONE.")


if __name__ == "__main__":
    main()
