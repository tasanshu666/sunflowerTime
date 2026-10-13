#!/usr/bin/env bash
# 从源图一次性生成**全平台** App 图标（iOS 15 档 + Android 5 档）。
#
# 用法：bash tools/gen_app_icons.sh
#
# 口径（C27 品牌修订 / F79 修 Android 未替换）：
#   · 源图 `assets/appicon/icon_1024.png`（玄参交付，实际 2048×2048，**无 alpha**）；
#   · 等比缩放一律走 `sips -Z`（含 `-s format png` 强制 PNG 容器）；
#   · iOS 1024 档必须 **RGB 无 alpha**（App Store 规范）——源图本身无 alpha，
#     故**不要**加任何 `--padColor` / alpha 相关参数；
#   · iOS 档位与文件名以 `AppIcon.appiconset/Contents.json` 为准（改那里必须同步本脚本）；
#   · Android 仅 5 档 `mipmap-*/ic_launcher.png`（`AndroidManifest` 的 `@mipmap/ic_launcher`
#     引用不变；**无** anydpi-v26 自适应图标）。
#
# ⚠️ 换图流程：替换源图 → 跑本脚本 → 两端各看一眼桌面图标（AI 不自查 UI，由玄参真机确认）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/appicon/icon_1024.png"
IOS_DIR="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
AND_DIR="$ROOT/android/app/src/main/res"

if [ ! -f "$SRC" ]; then
  echo "✗ 找不到源图：$SRC" >&2
  exit 1
fi

echo "源图：$SRC"
sips -g pixelWidth -g pixelHeight "$SRC" | tail -2

# ── iOS：`像素:文件名` ────────────────────────────────────────────────────────
IOS_SIZES=(
  "20:Icon-App-20x20@1x.png"
  "40:Icon-App-20x20@2x.png"
  "60:Icon-App-20x20@3x.png"
  "29:Icon-App-29x29@1x.png"
  "58:Icon-App-29x29@2x.png"
  "87:Icon-App-29x29@3x.png"
  "40:Icon-App-40x40@1x.png"
  "80:Icon-App-40x40@2x.png"
  "120:Icon-App-40x40@3x.png"
  "120:Icon-App-60x60@2x.png"
  "180:Icon-App-60x60@3x.png"
  "76:Icon-App-76x76@1x.png"
  "152:Icon-App-76x76@2x.png"
  "167:Icon-App-83.5x83.5@2x.png"
  "1024:Icon-App-1024x1024@1x.png"
)

# ── Android：`像素:目录` ─────────────────────────────────────────────────────
AND_SIZES=(
  "48:mipmap-mdpi"
  "72:mipmap-hdpi"
  "96:mipmap-xhdpi"
  "144:mipmap-xxhdpi"
  "192:mipmap-xxxhdpi"
)

echo
echo "── iOS（${#IOS_SIZES[@]} 档）──"
for entry in "${IOS_SIZES[@]}"; do
  px="${entry%%:*}"
  name="${entry##*:}"
  out="$IOS_DIR/$name"
  sips -s format png -Z "$px" "$SRC" --out "$out" >/dev/null
  printf '  %-30s %sx%s\n' "$name" "$(sips -g pixelWidth "$out" | tail -1 | tr -dc 0-9)" "$(sips -g pixelHeight "$out" | tail -1 | tr -dc 0-9)"
done

echo
echo "── Android（${#AND_SIZES[@]} 档）──"
for entry in "${AND_SIZES[@]}"; do
  px="${entry%%:*}"
  dir="${entry##*:}"
  out="$AND_DIR/$dir/ic_launcher.png"
  mkdir -p "$(dirname "$out")"
  sips -s format png -Z "$px" "$SRC" --out "$out" >/dev/null
  printf '  %-24s %spx\n' "$dir/ic_launcher.png" "$(sips -g pixelWidth "$out" | tail -1 | tr -dc 0-9)"
done

echo
echo "── 规范校验（alpha / 尺寸）──"
fail=0
alpha="$(sips -g hasAlpha "$IOS_DIR/Icon-App-1024x1024@1x.png" | tail -1)"
echo "  iOS 1024 hasAlpha → ${alpha}（必须 no）"
case "$alpha" in *no*) ;; *) echo "  ✗ iOS 1024 带 alpha，App Store 会拒" >&2; fail=1 ;; esac

for entry in "${IOS_SIZES[@]}"; do
  px="${entry%%:*}"; name="${entry##*:}"
  w="$(sips -g pixelWidth "$IOS_DIR/$name" | tail -1 | tr -dc 0-9)"
  if [ "$w" != "$px" ]; then echo "  ✗ $name 实际 ${w}px ≠ 期望 ${px}px" >&2; fail=1; fi
done
for entry in "${AND_SIZES[@]}"; do
  px="${entry%%:*}"; dir="${entry##*:}"
  w="$(sips -g pixelWidth "$AND_DIR/$dir/ic_launcher.png" | tail -1 | tr -dc 0-9)"
  if [ "$w" != "$px" ]; then echo "  ✗ $dir 实际 ${w}px ≠ 期望 ${px}px" >&2; fail=1; fi
done

[ "$fail" -eq 0 ] && echo "  ✓ 全部档位尺寸正确、1024 档无 alpha"
echo
echo "完成。换图后请重跑 iOS/Android 构建并真机确认桌面图标。"
exit "$fail"
