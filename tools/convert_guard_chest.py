#!/usr/bin/env python3
"""花园守卫 · 宝箱开箱序列帧 PNG→WebP 转换（T02 素材管线）。

来源（只读，绝不改动源文件）：
    /Volumes/DataHD-2TB/素材归档/专注素材/花园守护/宝箱/
        普通宝箱/frame001..030.png    720×720 RGBA   整组 16.5 MB
        高级宝箱01/frame001..030.png  720×720 RGBA   整组 23.56 MB
        （2026-11-12 玄参换素材：旧目录「高级宝箱/」已被替换为「高级宝箱01/」，
          旧目录**已不存在**，不要再引用它）

落位（命名对齐 `docs/美术资源_序列帧与音频命名规范_v1.md`「三位零填充、从 001 起」）：
    assets/guard/chest_normal/frame001..030.webp    512×512  q90
    assets/guard/chest_premium/frame001..030.webp   512×512  q80

口径依据 `docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §6.2（实测压缩矩阵）：

| 组合      | 普通宝箱 30 帧 | 高级宝箱 30 帧 |
|-----------|---------------|---------------|
| 720 q90   | 2.16 MB       | ≈12.1 MB ❌    |
| 512 q90   | 1.72 MB       | 7.13 MB       |
| 512 q80   | —             | 6.16 MB       |

⇒ 统一 512×512（保方形画布、**不裁边**：高级宝箱 30 帧并集 bbox ≈ 满幅，
    裁了会切掉飞出的道具；普通宝箱裁边会让静态首帧与动画帧两套方框、切换必跳），
    普通 q90 / 高级 q80。

## 目标体积预算：**整批 ≤ 8 MB**

宝箱两目录合计必须 ≤ 8 MB（守卫素材单批预算，见 pubspec 里 B5b 那条注释的口径）。
当前实测 ≈ 7.9 MB，余量约 0.1 MB。**换素材后若超预算**，按 §6.2 矩阵降级，
优先级从低到高：`--normal-q 85` → 高级减到 480 长边 → 高级只取前 15 帧（帧率腰斩，最差手段）。

## 换素材时怎么重跑

```bash
# 1) 先 dry-run 看体积（不落盘）：
python3 tools/convert_guard_chest.py

# 2) 确认体积达标后落盘：
python3 tools/convert_guard_chest.py --apply

# 3) 重跑（素材改过但想强制重导；默认已幂等，见下）：
python3 tools/convert_guard_chest.py --apply --force

# 4) 只想跑一个档 / 改质量 / 改边长：
python3 tools/convert_guard_chest.py --apply --only premium --premium-q 80 --edge 512
```

**幂等保证**：编码参数固定（`method=6`，quality 固定），PIL/libwebp 对同一输入
产出字节完全一致；脚本先把结果编码进内存，**与磁盘上已有文件逐字节比对**，
相同则不写盘（打印 `same`），因此重复执行既稳定又不会产生 mtime 抖动。—— 这也是
`flutter test` 里「帧数与文件名契约」用例可反复跑而结果不变的前提。

## 🔴 改帧数 / 改画布 / 改开箱时长时要同步的地方（漏一处必红，共 4 组）

| # | 位置 | 改什么 | 不改的后果 |
|---|---|---|---|
| 1 | `lib/core/constants/prd_params.dart` | `kGuardChestFrameCount` / `kGuardChestFrameExt`（改时长还有 `kGuardChestOpenMs`） | `resolveFxFrames` 的 `fallbackCount` 与实际不符（清单读不到时按错数补） |
| 2 | `test/guard/guard_chest_overlay_test.dart`（**两个硬编码点，别只改一个**） | ① `_frameStep = Duration(microseconds: 166700)`（= 5000ms ÷ 30 帧）与其推导 `_frameStep * 24`；② `pump(Duration(milliseconds: 4999))` —— 到点前一刻的边界值，**是字面量、不是 `kGuardChestOpenMs - 1`**（**故意不引用常量——引用常量会让「改错时长也不红」退化成恒真断言，见项目 K26~K28 期望值独立原则**） | ① 逐帧推进断言当场红；② 会红在一条看起来毫不相关的「onOpened 回调」用例上（4999 与 5000 严格差 1ms），最难归因 |
| 3 | `test/m3/guard_chest_assets_guard_test.dart` | `kChestFrameEdge`（画布变时）；帧数**不用**改（已引用 `kGuardChestFrameCount`） | 画布变了会红在 A-02/A-07b（这是护栏的本职） |
| 4 | `docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §6.1/§6.2 表格 | 帧数、体积、单帧区间 | 文档与磁盘不符，下一个人按旧数做预算 |

⚠️ 只换素材（帧数/画布/时长都不变，仅重新导出）：**上面 4 组都不用改**，跑本脚本 `--apply` + 守卫测试即闭环。

**为什么不做 apad / 不转码音效**：`开启宝箱音效.mp3` 实测 5.198333s，
已过 ≥3s 红线（iOS CoreAudio −11849），原样拷贝即可，见 `copy_guard_chest_audio()`。
音画尾差：动画 5000ms vs 音效 5198ms ⇒ 尾部 **198ms 溢到结算卡**，按设计 §7.5 / R-04
**已知接受**（本批不把动画改 5198ms；真机嫌不同步再单独提）。

**排他**：源目录里的 `*.mp4`、`微信图片_*.png`、`*.zip`、`.DS_Store` 一律不接包（仅参考）。
"""
from __future__ import annotations

import argparse
import glob
import io
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

# 源素材根（只读）。外接盘路径写死：本项目所有素材脚本同口径。
SRC_ROOT = Path('/Volumes/DataHD-2TB/素材归档/专注素材/花园守护/宝箱')

# 音效源（原样拷贝，不改码率、不做 apad）
SRC_AUDIO = SRC_ROOT / '开启宝箱音效.mp3'
DST_AUDIO = ROOT / 'assets' / 'audio' / 'sfx' / 'guard_chest_open.mp3'

# 目标边长（方形画布，不裁边）
DEFAULT_EDGE = 512

# 整批体积预算（普通 + 高级 + 音效 合计）
BUDGET_BYTES = 8 * 1024 * 1024

# libwebp 编码档：method=6 = 最高压缩努力（体积最小，耗时最长；30 帧量级耗时可接受）
WEBP_METHOD = 6


@dataclass(frozen=True)
class ChestTier:
    """一个宝箱档的转换规格。

    Attributes:
        name: 档位标识（也是目标目录名后缀：`chest_<name>`）。
        src_dir: 源帧目录（`frame001..030.png`）。
        dst_rel: 目标相对工程根的目录。
        quality: WebP 有损质量（普通 q90 / 高级 q80，依据设计 §6.2 实测矩阵）。
    """

    name: str
    src_dir: Path
    dst_rel: str
    quality: int

    def dst_dir(self) -> Path:
        return ROOT / self.dst_rel


TIERS: tuple[ChestTier, ...] = (
    ChestTier(
        name='normal',
        src_dir=SRC_ROOT / '普通宝箱',
        dst_rel='assets/guard/chest_normal',
        quality=90,
    ),
    ChestTier(
        name='premium',
        # 2026-11-12 玄参换素材：源目录由「高级宝箱」→「高级宝箱01」（旧目录已删）。
        src_dir=SRC_ROOT / '高级宝箱01',
        dst_rel='assets/guard/chest_premium',
        quality=80,
    ),
)

# 源帧命名契约（三位零填充，从 001 起）
FRAME_COUNT = 30


def webp_size(path: Path) -> int | None:
    """直读 WebP 头解析画布尺寸，返回 `w * h`；非法容器返回 None。

    支持三种 chunk：`VP8 `（有损简单格式，本脚本产物）、`VP8L`（无损）、`VP8X`（扩展）。
    与 `test/m3/fx_frame_assets_guard_test.dart` 的 `_webpSize` 同一口径（双端互校）。
    """
    b = path.open('rb').read(30)
    if len(b) < 30 or b[:4] != b'RIFF' or b[8:12] != b'WEBP':
        return None
    fourcc = b[12:16]
    if fourcc == b'VP8 ':
        if b[23:26] != b'\x9d\x01\x2a':
            return None
        w = (b[26] | (b[27] << 8)) & 0x3FFF
        h = (b[28] | (b[29] << 8)) & 0x3FFF
        return w * h
    if fourcc == b'VP8L':
        bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
        return ((bits & 0x3FFF) + 1) * (((bits >> 14) & 0x3FFF) + 1)
    if fourcc == b'VP8X':
        w = b[24] | (b[25] << 8) | (b[26] << 16)
        h = b[27] | (b[28] << 8) | (b[29] << 16)
        return (w + 1) * (h + 1)
    return None


def frame_paths(src_dir: Path) -> list[Path]:
    """源目录下 `frame*.png`（升序）。缺目录/空目录 → 抛 FileNotFoundError。"""
    if not src_dir.is_dir():
        raise FileNotFoundError(f'源帧目录不存在：{src_dir}')
    paths = sorted(Path(p) for p in glob.glob(str(src_dir / 'frame*.png')))
    if not paths:
        raise FileNotFoundError(f'源帧目录里没有 frame*.png：{src_dir}')
    return paths


def convert_frame(src: Path, dst: Path, edge: int, quality: int,
                  force: bool) -> tuple[str, int, int]:
    """转换单帧。

    Returns:
        (状态, 前字节数, 后字节数)。状态 ∈ {'written', 'same', 'skip'}。
    """
    src_bytes = src.stat().st_size
    im = Image.open(src).convert('RGBA')  # 保留 alpha（宝箱是透明底素材）
    if im.size != (edge, edge):
        # 源为 720×720 方形；统一缩到 edge×edge（LANCZOS，与 convert_guard_b5b.py 同口径）。
        # exact=False（默认）：允许编码器改写全透明像素底下的 RGB —— 不渲染，画面零差别，
        # 体积显著更小；alpha 通道本身逐像素无损保留（决定羽化边观感的是 alpha）。
        im = im.resize((edge, edge), Image.LANCZOS)

    buf = _encode(im, quality)
    if not force and dst.exists() and dst.read_bytes() == buf:
        return ('same', src_bytes, len(buf))

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(buf)
    if webp_size(dst) != edge * edge:
        raise RuntimeError(f'产物尺寸漂移：{dst}（应 {edge}×{edge}）')
    return ('written', src_bytes, len(buf))


def _encode(im: Image.Image, quality: int) -> bytes:
    """把 RGBA 图编码为 WebP 字节串（内存内，便于与磁盘比对实现幂等）。"""
    out = io.BytesIO()
    im.save(out, format='WEBP', quality=quality, method=WEBP_METHOD)
    return out.getvalue()


def process_tier(tier: ChestTier, edge: int, apply: bool,
                 force: bool) -> dict[str, object]:
    """转换一个档位的全部帧，返回统计（不含副作用：apply=False 时只算体积）。"""
    srcs = frame_paths(tier.src_dir)
    if len(srcs) != FRAME_COUNT:
        print(f'  ⚠️  {tier.name}: 源帧数 {len(srcs)} ≠ 契约 {FRAME_COUNT}（照实转换）')

    dst_dir = tier.dst_dir()
    sizes: list[int] = []
    src_total = 0
    written = same = 0
    for i, src in enumerate(srcs, 1):
        dst = dst_dir / f'frame{i:03d}.webp'
        if apply:
            state, s0, s1 = convert_frame(src, dst, edge, tier.quality, force)
            if state == 'written':
                written += 1
            else:
                same += 1
        else:
            # dry-run：只编码算体积，不落盘。
            im = Image.open(src).convert('RGBA')
            if im.size != (edge, edge):
                im = im.resize((edge, edge), Image.LANCZOS)
            s0 = src.stat().st_size
            s1 = len(_encode(im, tier.quality))
        src_total += s0
        sizes.append(s1)

    return {
        'tier': tier,
        'frames': len(srcs),
        'src_total': src_total,
        'dst_total': sum(sizes),
        'min': min(sizes),
        'max': max(sizes),
        'written': written,
        'same': same,
    }


def copy_guard_chest_audio(apply: bool) -> int:
    """原样拷贝开箱音效（不转码、不做 apad：源 5.198s 已过 ≥3s 红线）。

    Returns:
        目标文件字节数（源缺失时返回 0 并打印提示）。
    """
    if not SRC_AUDIO.exists():
        print(f'  ⚠️  音效源缺失，跳过：{SRC_AUDIO}')
        return 0
    data = SRC_AUDIO.read_bytes()
    if apply:
        DST_AUDIO.parent.mkdir(parents=True, exist_ok=True)
        if not DST_AUDIO.exists() or DST_AUDIO.read_bytes() != data:
            DST_AUDIO.write_bytes(data)
    return len(data)


def _mb(n: int) -> str:
    return f'{n / 1048576:.2f} MB'


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description='花园守卫宝箱序列帧 PNG→WebP（512²，普通 q90 / 高级 q80，预算 ≤8MB）')
    ap.add_argument('--apply', action='store_true',
                    help='真正写盘（默认 dry-run，只报体积）')
    ap.add_argument('--force', action='store_true',
                    help='即使产物字节与已有文件相同也重写（默认幂等跳过）')
    ap.add_argument('--only', choices=['normal', 'premium'], default=None,
                    help='只处理一个档位（默认两档都处理）')
    ap.add_argument('--edge', type=int, default=DEFAULT_EDGE,
                    help=f'目标方形边长（默认 {DEFAULT_EDGE}）')
    ap.add_argument('--normal-q', type=int, default=TIERS[0].quality,
                    help='普通宝箱 WebP 质量（默认 90）')
    ap.add_argument('--premium-q', type=int, default=TIERS[1].quality,
                    help='高级宝箱 WebP 质量（默认 80）')
    a = ap.parse_args(argv)

    tiers = tuple(
        ChestTier(name=t.name, src_dir=t.src_dir, dst_rel=t.dst_rel,
                  quality=(a.normal_q if t.name == 'normal' else a.premium_q))
        for t in TIERS
        if a.only is None or t.name == a.only
    )

    print(f'模式={"APPLY" if a.apply else "DRY-RUN"}  edge={a.edge}  '
          f'q={", ".join(f"{t.name}:{t.quality}" for t in tiers)}  force={a.force}')

    grand_total = 0
    for tier in tiers:
        try:
            st = process_tier(tier, a.edge, a.apply, a.force)
        except (FileNotFoundError, RuntimeError) as e:
            print(f'  ❌ {tier.name}: {e}')
            return 1
        grand_total += int(st['dst_total'])
        print(f'  {tier.dst_rel}: {st["frames"]} 帧  '
              f'{_mb(int(st["src_total"]))} → {_mb(int(st["dst_total"]))}  '
              f'单帧最小 {int(st["min"]) / 1024:.1f} KB / '
              f'最大 {int(st["max"]) / 1024:.1f} KB  '
              f'(written={st["written"]} same={st["same"]})')

    audio_bytes = copy_guard_chest_audio(a.apply)
    grand_total += audio_bytes
    print(f'  {DST_AUDIO.relative_to(ROOT)}: {audio_bytes} B（原样拷贝，不改码率/不 apad）')
    print(f'—— 宝箱两目录合计 {_mb(grand_total - audio_bytes)}；'
          f'含音效 {_mb(grand_total)} / 预算 {_mb(BUDGET_BYTES)}')

    if grand_total > BUDGET_BYTES:
        print('  ❌ 超预算！降级顺序：--normal-q 85 → --edge 480 → 高级只取前 15 帧')
        return 1
    print('  ✅ 在预算内')
    return 0


if __name__ == '__main__':
    sys.exit(main())
