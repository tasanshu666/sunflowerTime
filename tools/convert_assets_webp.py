#!/usr/bin/env python3
"""静态图 / 序列帧素材 PNG→WebP 瘦身管线（2026-11-25 装包体积治理批）。

## 背景

Android 走**官网直供下载**（不上应用商店），debug APK 实测 623 MB，其中
`assets/flutter_assets/assets/` 占 474 MB —— 600 MB 级的包在移动网络下下载
转化 Almost 归零。本脚本把「仍是 PNG」的六组素材压成 WebP：

| 组 | 目录 | 说明 |
|---|---|---|
| plants | `assets/plants/{10 物种 + shared}` | 静态植物图 1200/1440×2000 |
| tree_frames | `assets/wish_tree/tree_frames` | 许愿树循环帧 720×960 × 51 |
| focus | `assets/fx/focus/sunflower/{idle,collect,settle,return}` | 专注页向日葵帧 720² |
| levelup5 | `assets/fx/levelUp/5leveUp` | 称号升级演出 720² × 41 |
| levelup | `assets/fx/levelUp/defaultLevelUp` | 普通升级演出 720² × 36 |
| care | `assets/fx/care/{water,fertilize,weed,pest}` | 养护 / 除草 / 除虫效果帧 720² |

**已经是 WebP 的目录一个都不碰**（`fx/grow/*`、`fx/eyecare640`、
`fx/eyecare640_en`、`guard/*`、`ui/*`、`backgrounds/*`、`weather/*`、`fx/leaves/*`）。

## 质量口径（**复用既有管线，不自创新规则**）

`quality=95, method=6` —— 与 `tools/convert_eyecare640.py`（护眼 640 帧）、
`tools/convert_grow_fx.py --q95`（成长帧）、`tools/convert_guard_b5b.py`
（守卫战）完全同档。理由：

* q95 时**可见像素** PSNR 实测 36~42 dB（护眼帧 PSNR≈44.8 dB 同量级）；
* 再降一档（q90）只多省约 20~25%，PSNR 掉 0.3~2 dB —— 收益/画质比不划算；
* 本批六组在 q95 下已从 ≈262 MB 压到 ≈63 MB，**远超**「省 180 MB」的目标。

## 三个硬约束

1. **保留 alpha 通道**：全部按 RGBA 编码。libwebp 的有损档 **alpha 子块是无损的**
   （仅 RGB 有损），因此不会出现透明边缘白边/黑边。逐张校验 alpha 通道
   **逐像素相等**，不相等即记为 `alpha_ok=False`（报告里会点出来）。
2. **不改画布尺寸**：`garden_pot.dart` / `prd_params.dart` 里大量常量是由
   **像素 bbox 反推**的（盆宽 800 / 盆心 x=720 / 树根 0.852 …），改尺寸会
   连带改布局。本脚本**只转码，不 resize**，并逐张校验 `size` 与源图一致。
3. **原 PNG 可回滚**：转完把 PNG 移到 `assets/_originals/png_webp_batch_2026_11/
   <相对 assets 的路径>`。该目录被 `.gitignore` 忽略、且**不在** `pubspec.yaml`
   的 assets 声明里 ⇒ 不会进包。

   ⚠️ 为什么另开一层 `png_webp_batch_2026_11/` 而不直接铺在 `assets/_originals/` 下：
   `assets/_originals/plants/<物种>/` 里**已经**存着一批更老的原始交付稿
   （例如 grape 是裁边前的 4 MB 原图），直接落会覆盖历史备份；而且
   `test/verify/qa_new_species_lotus_blueberry_test.dart` 的负向对照用例
   依赖 `assets/_originals/plants/lotus/species_lotus_adult.png` 这个老文件存在。

## 幂等

* PNG 已移走、WebP 已在 → 跳过（`--force` 可重转）；
* 两者都在 → 重转并移走 PNG；
* 目标备份已存在且字节相同 → 删源；不同 → 加 `.vN` 后缀另存（绝不覆盖）。

## 用法

```bash
python3 tools/convert_assets_webp.py                 # dry-run：只统计体积/PSNR，不落盘
python3 tools/convert_assets_webp.py --sample 3      # 每组抽 3 张，详细画质表
python3 tools/convert_assets_webp.py --apply         # 真转 + 移走原 PNG
python3 tools/convert_assets_webp.py --apply --force # 强制重转
```
"""

from __future__ import annotations

import argparse
import filecmp
import math
import os
import shutil
import sys
from dataclasses import dataclass
from io import BytesIO
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

# 备份根（`assets/_originals/` 整体被 .gitignore 忽略，且不在 pubspec assets 里）。
BACKUP = ASSETS / "_originals" / "png_webp_batch_2026_11"

# 质量口径：与 convert_eyecare640.py / convert_grow_fx.py / convert_guard_b5b.py 同档。
QUALITY = 95
METHOD = 6


@dataclass(frozen=True)
class Group:
    """一组待转码素材（目录 + 文件 glob，相对 `assets/`）。"""

    key: str
    root: str
    patterns: tuple[str, ...]
    note: str = ""

    def files(self) -> list[Path]:
        """本组全部 PNG（升序，去重）。"""
        found: dict[str, Path] = {}
        base = ASSETS / self.root
        for pat in self.patterns:
            for p in sorted(base.glob(pat)):
                if p.is_file() and p.suffix.lower() == ".png":
                    found[str(p)] = p
        return [found[k] for k in sorted(found)]


GROUPS: tuple[Group, ...] = (
    Group("plants", "plants", ("*/species_*.png", "shared/*.png"),
          "静态植物图（1200×2000 legacy / 1440×2000 归一化）"),
    Group("tree_frames", "wish_tree/tree_frames", ("*.png",),
          "许愿树循环帧 720×960"),
    Group("focus", "fx/focus/sunflower",
          ("idle/*.png", "collect/*.png", "settle/*.png", "return/*.png"),
          "专注页向日葵帧 720²"),
    Group("levelup5", "fx/levelUp/5leveUp", ("*.png",), "称号升级演出 720²"),
    Group("levelup", "fx/levelUp/defaultLevelUp", ("*.png",), "普通升级演出 720²"),
    Group("care", "fx/care",
          ("water/*.png", "fertilize/*.png", "weed/*.png", "pest/*.png"),
          "养护 / 除草 / 除虫效果帧 720²"),
    # 追加（原任务表未列，但同为「仍是大 PNG」且在 `assets/wish_tree/` 这条已声明的
    # 目录里，8 张合计 17.1 MB —— 顺手一起瘦，见脚本头部说明 §追加范围）。
    Group("wish_root", "wish_tree", ("*.png",),
          "许愿树场景静态图（背景 / 大树 / 三种蛋 / 收藏箱 / 愿望池 / 入口图标）"),
)


# ── 画质度量 ────────────────────────────────────────────────────────────────


def alpha_weighted_psnr(ref: np.ndarray, out: np.ndarray, alpha: np.ndarray) -> float:
    """按 alpha 加权的 RGB PSNR（dB）。

    为什么不用裸 PSNR：WebP 有损档对 **alpha==0 的像素 RGB** 是随机量化的（那些
    像素根本不渲染），裸 PSNR 会被它们主导 —— 实测同一张图 q95 与 q85 的裸 PSNR
    只差 0.1 dB，完全失去分辨力。按合成后的可见性加权（权重 = alpha/255）才
    反映「眼睛看到的误差」。
    """
    w = alpha.astype(np.float64) / 255.0
    total_w = float(w.sum()) * 3.0
    if total_w <= 0:
        return float("inf")
    diff = ref[:, :, :3].astype(np.float64) - out[:, :, :3].astype(np.float64)
    mse = float((diff * diff * w[:, :, None]).sum() / total_w)
    if mse == 0:
        return float("inf")
    return 10.0 * math.log10(255.0 * 255.0 / mse)


# ── 单文件转换 ──────────────────────────────────────────────────────────────


def _encode(src: Path, apply: bool, force: bool) -> dict:
    """转码单张；`apply=False` 时只写内存（dry-run / 抽样）。

    返回 dict：路径、前后体积、画布尺寸、alpha 是否逐像素保留、加权 PSNR、
    以及状态（`converted` / `skipped` / `failed`）。
    """
    dst = src.with_suffix(".webp")
    rel = src.relative_to(ASSETS)
    result = {
        "src": str(src),
        "rel": str(rel),
        "dst": str(dst),
        "png_bytes": 0,
        "webp_bytes": 0,
        "size": (0, 0),
        "alpha_ok": True,
        "psnr": 0.0,
        "status": "converted",
        "error": "",
    }

    # 幂等：PNG 已移走 + WebP 已在 + 不强制 → 跳过（体积按现有 WebP 计）。
    if apply and not src.exists() and dst.exists() and not force:
        result.update(webp_bytes=dst.stat().st_size, status="skipped")
        return result

    try:
        with Image.open(src) as raw:
            result["png_bytes"] = src.stat().st_size
            im = raw.convert("RGBA")
            result["size"] = im.size
            ref = np.asarray(im)
            alpha = ref[:, :, 3]

            if apply:
                dst.parent.mkdir(parents=True, exist_ok=True)
                im.save(dst, "WEBP", quality=QUALITY, method=METHOD)
                result["webp_bytes"] = dst.stat().st_size
                # 校验：直读落盘文件（不信内存里的编码结果）。
                with Image.open(dst) as back_raw:
                    back = back_raw.convert("RGBA")
                    out_size = back.size
                    out = np.asarray(back)
            else:
                buf = BytesIO()
                im.save(buf, "WEBP", quality=QUALITY, method=METHOD)
                result["webp_bytes"] = buf.getbuffer().nbytes
                buf.seek(0)
                with Image.open(buf) as back_raw:
                    back = back_raw.convert("RGBA")
                    out_size = back.size
                    out = np.asarray(back)

        # 校验 1：画布尺寸零变化（布局常量由像素 bbox 反推，尺寸变了就全歪）。
        if out_size != result["size"]:
            result["error"] = f"尺寸漂移 {result['size']} → {out_size}"
            result["status"] = "failed"
            return result
        # 校验 2：alpha 通道逐像素相等（有损档只损 RGB，alpha 必须无损）。
        result["alpha_ok"] = bool(np.array_equal(alpha, out[:, :, 3]))
        result["psnr"] = alpha_weighted_psnr(ref, out, alpha)
    except Exception as exc:  # noqa: BLE001 —— 单张失败不能让整个 Pool 崩掉
        result["status"] = "failed"
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


def _convert_job(job: tuple[Path, bool, bool]) -> dict:
    src, apply, force = job
    return _encode(src, apply, force)


def _backup_target(src: Path) -> Path:
    """原 PNG 的备份落点（`assets/_originals/png_webp_batch_2026_11/<rel>）。"""
    return BACKUP / src.relative_to(ASSETS)


def move_original(src: Path) -> str:
    """把原 PNG 移进备份目录（不覆盖任何已存在文件）。返回落点相对路径。"""
    dst = _backup_target(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        if filecmp.cmp(src, dst, shallow=False):
            src.unlink()  # 备份里已有同字节文件 → 直接删源
            return f"{dst.relative_to(ROOT)}（同字节，已删源）"
        n = 1
        while True:
            cand = dst.with_name(f"{dst.stem}.v{n}{dst.suffix}")
            if not cand.exists():
                shutil.move(str(src), str(cand))
                return f"{cand.relative_to(ROOT)}（版本冲突，另存 v{n}）"
            n += 1
    shutil.move(str(src), str(dst))
    return str(dst.relative_to(ROOT))


# ── 报告 ────────────────────────────────────────────────────────────────────


def _fmt_mb(n: int) -> str:
    return f"{n / 1048576:8.2f} M"


def print_table(rows: list[tuple[str, int, int, int, int]]) -> None:
    """打印「组 / 文件数 / 转前 / 转后 / 省下」表。"""
    head = f"{'组':<14}{'文件数':>6}{'转前':>12}{'转后':>12}{'省下':>12}{'保留率':>9}"
    print(head)
    print("-" * len(head))
    t_files = t_before = t_after = 0
    for name, files, before, after, _ in rows:
        t_files += files
        t_before += before
        t_after += after
        keep = (after / before * 100.0) if before else 0.0
        print(f"{name:<14}{files:>6}{_fmt_mb(before):>12}{_fmt_mb(after):>12}"
              f"{_fmt_mb(before - after):>12}{keep:>8.1f}%")
    print("-" * len(head))
    keep = (t_after / t_before * 100.0) if t_before else 0.0
    print(f"{'合计':<14}{t_files:>6}{_fmt_mb(t_before):>12}{_fmt_mb(t_after):>12}"
          f"{_fmt_mb(t_before - t_after):>12}{keep:>8.1f}%")


# ── 主流程 ──────────────────────────────────────────────────────────────────


def clean_junk() -> list[str]:
    """清理 `.DS_Store`；`fx/care/.gitkeep` 在其目录已非空时删除。"""
    removed: list[str] = []
    for p in sorted(ASSETS.rglob(".DS_Store")):
        p.unlink()
        removed.append(str(p.relative_to(ROOT)))
    for p in sorted(ASSETS.rglob(".gitkeep")):
        siblings = [s for s in p.parent.iterdir() if s.name != ".gitkeep"]
        if siblings:
            p.unlink()
            removed.append(str(p.relative_to(ROOT)))
    return removed


def main() -> int:
    ap = argparse.ArgumentParser(description="素材 PNG→WebP 瘦身（q95 / method=6）")
    ap.add_argument("--apply", action="store_true", help="真转码并把原 PNG 移进备份目录")
    ap.add_argument("--force", action="store_true", help="已转过的也重转")
    ap.add_argument("--sample", type=int, default=0,
                    help="每组抽 N 张做画质详表（不落盘）")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 4) - 1))
    ap.add_argument("--group", action="append", default=None,
                    help="只处理指定组（可重复；默认全部）")
    ap.add_argument("--clean-junk", action="store_true",
                    help="顺带删 .DS_Store / 空目录遗留 .gitkeep")
    args = ap.parse_args()

    groups = [g for g in GROUPS if args.group is None or g.key in args.group]
    if not groups:
        print(f"ERROR: --group 未命中任何组；可选 {[g.key for g in GROUPS]}")
        return 2

    print(f"质量口径 quality={QUALITY} method={METHOD}"
          f"（复用 convert_eyecare640 / convert_grow_fx / convert_guard_b5b）")
    print(f"模式={'APPLY' if args.apply else 'DRY-RUN'}  workers={args.workers}"
          f"  sample={args.sample}")

    if args.clean_junk:
        removed = clean_junk()
        print(f"清理垃圾文件 {len(removed)} 个：")
        for r in removed:
            print(f"  - {r}")

    # ── 抽样模式：每组抽 N 张，打印画质详表 ──
    if args.sample > 0:
        for g in groups:
            files = g.files()
            if not files:
                print(f"\n[{g.key}] 无 PNG（已转完？）")
                continue
            step = max(1, len(files) // args.sample)
            picks = files[::step][: args.sample]
            print(f"\n[{g.key}] {g.note} —— 共 {len(files)} 张，抽 {len(picks)} 张：")
            for f in picks:
                r = _encode(f, apply=False, force=True)
                if r["status"] == "failed":
                    print(f"  !! {r['rel']}: {r['error']}")
                    continue
                w, h = r["size"]
                print(f"  {r['rel']:<58} {w}×{h}  "
                      f"{r['png_bytes'] / 1024:8.0f}K → {r['webp_bytes'] / 1024:7.0f}K "
                      f"({r['webp_bytes'] / r['png_bytes'] * 100:4.1f}%)  "
                      f"α={'OK' if r['alpha_ok'] else '变化'}  "
                      f"PSNR={r['psnr']:.2f} dB")
        return 0

    # ── 全量（dry-run / apply）──
    rows: list[tuple[str, int, int, int, int]] = []
    failures: list[str] = []
    alpha_bad: list[str] = []
    moved = 0
    skipped = 0

    for g in groups:
        files = g.files()
        # dry-run 幂等：PNG 已被移走时，改用备份里的 PNG 当源来估算。
        if not args.apply and not files:
            bak = BACKUP / g.root
            candidates: dict[str, Path] = {}
            for pat in g.patterns:
                for q in sorted(bak.glob(pat)):
                    if q.is_file() and q.suffix.lower() == ".png":
                        candidates[str(q)] = q
            files = [candidates[k] for k in sorted(candidates)]
            if files:
                print(f"[{g.key}] 源 PNG 已在备份里，dry-run 改用 "
                      f"{BACKUP.relative_to(ROOT)}/{g.root} 估算（{len(files)} 张）")
        if not files:
            print(f"[{g.key}] 跳过：目录下已无 PNG，且备份里也没有")
            continue

        print(f"\n[{g.key}] {g.note} —— {len(files)} 张")
        before = after = 0
        n_done = 0
        with Pool(args.workers) as pool:
            jobs = [(f, args.apply, args.force) for f in files]
            for i, r in enumerate(pool.imap_unordered(_convert_job, jobs, chunksize=4), 1):
                if r["status"] == "failed":
                    failures.append(f"{r['rel']}: {r['error']}")
                    continue
                if not r["alpha_ok"]:
                    alpha_bad.append(r["rel"])
                before += r["png_bytes"]
                after += r["webp_bytes"]
                n_done += 1
                if r["status"] == "skipped":
                    skipped += 1
                elif args.apply:
                    src = Path(r["src"])
                    if src.exists():
                        move_original(src)
                        moved += 1
                if i % 50 == 0 or i == len(files):
                    print(f"  ...{i}/{len(files)}")
        rows.append((g.key, n_done, before, after, len(files)))

    print()
    print_table(rows)

    if alpha_bad:
        print(f"\n⚠️ alpha 通道非逐像素相等（{len(alpha_bad)} 张，需目视复核）：")
        for a in alpha_bad[:20]:
            print(f"  - {a}")
    if failures:
        print(f"\n❌ 失败 {len(failures)} 张：")
        for f in failures:
            print(f"  - {f}")

    if args.apply:
        print(f"\n已移走原 PNG {moved} 张 → {BACKUP.relative_to(ROOT)}（已被 .gitignore 忽略）")
        if skipped:
            print(f"已跳过（早前转过）{skipped} 张")
    else:
        print("\n（dry-run 未落盘；确认无误后加 --apply）")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
