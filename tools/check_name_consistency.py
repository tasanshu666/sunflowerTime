#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
名称一致性自检 —— 软著 / 商店 / 安装包 四方是否一字不差

背景（2026-11-10 踩坑）：改名批 `4bc9cfb`（2026-10-23）已把 App 全线改为
「小小葵番茄钟 / Tiny Sunflower」，但软著材料与商店文案仍用改名前旧名
「向日葵专注 / SunFocus」—— 商店审核会以「软著与 App 不对应」直接驳回。

四方口径：
  ① 软著证书 · 软件简称     ← docs/软著材料/软著申请表_*.docx
  ② 商店 · 应用名称          ← docs/商店文案_国内安卓_v1.md
  ③ 安装包 · 桌面显示名      ← ios/Runner/*/InfoPlist.strings + android res/values*/
  ④ 商店文案 · App Store 名  ← docs/商店文案_AppStore_v1.md

用法：
    python3 tools/check_name_consistency.py
退出码 0 = 全一致；1 = 有不一致（打印差异明细）
"""

import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def docx_text(path):
    """提取 docx 全部文本（正文 + 页眉页脚 + 文档属性），按段落/单元格分行。"""
    out = []
    try:
        z = zipfile.ZipFile(path)
    except Exception as exc:  # noqa: BLE001
        return f"<读取失败: {exc}>"
    for name in z.namelist():
        if not name.endswith(".xml"):
            continue
        raw = z.read(name).decode("utf-8", errors="ignore")
        # 段落与单元格边界都切成独立行，避免相邻单元格文本粘连
        raw = re.sub(r"</w:p>", "\n", raw)
        raw = re.sub(r"</w:tc>", "\n", raw)
        raw = re.sub(r"</w:tr>", "\n", raw)
        out.extend(re.findall(r"<w:t(?: [^>]*)?>(.*?)</w:t>", raw, re.S))
    return "\n".join(out)


def first_existing(*relpaths):
    for rel in relpaths:
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            return p
    return None


def main():
    problems = []
    notes = []

    # ---- ① 软著申请表：软件简称 / 全称 / 英文名称 ----
    form = first_existing("docs/软著材料/软著申请表_小小葵番茄钟.docx")
    soft = {}
    if form is None:
        problems.append("① 找不到软著申请表 docx（docs/软著材料/）")
    else:
        txt = docx_text(form)
        m = re.search(r"软件简称\s*\n?([^\n]+)", txt)
        soft["short"] = m.group(1).strip() if m else ""
        m = re.search(r"软件名称\s*\n?([^\n]+)", txt)
        soft["full"] = m.group(1).strip() if m else ""
        m = re.search(r"英文名称\s*\n?([^\n]+)", txt)
        soft["en"] = m.group(1).strip() if m else ""
        if not soft["short"]:
            problems.append("① 申请表里读不到「软件简称」")
        if soft["full"] and soft["full"] == soft["short"]:
            problems.append("① 简称与全称相同（新版规则不允许）")

    # ---- ② 商店文案：应用名称主推 ----
    store_doc = os.path.join(ROOT, "docs/商店文案_国内安卓_v1.md")
    store_short = ""
    if os.path.exists(store_doc):
        s = read_text(store_doc)
        m = re.search(r"1（主推）\s*\|\s*\*\*([^*]+)\*\*", s)
        store_short = m.group(1).strip() if m else ""
        if not store_short:
            problems.append("② 商店文案里读不到「1（主推）」应用名称")
    else:
        problems.append("② 找不到 docs/商店文案_国内安卓_v1.md")

    # ---- ③ 安装包桌面显示名 ----
    ios_zh = os.path.join(ROOT, "ios/Runner/zh-Hans.lproj/InfoPlist.strings")
    ios_en = os.path.join(ROOT, "ios/Runner/en.lproj/InfoPlist.strings")
    android_zh = os.path.join(ROOT, "android/app/src/main/res/values-zh/strings.xml")
    android_en = os.path.join(ROOT, "android/app/src/main/res/values/strings.xml")

    pkg = {}
    if os.path.exists(ios_zh):
        m = re.search(r'CFBundleDisplayName\s*=\s*"([^"]+)"', read_text(ios_zh))
        pkg["ios_zh"] = m.group(1) if m else ""
    if os.path.exists(android_zh):
        m = re.search(r'<string name="app_name">([^<]+)</string>', read_text(android_zh))
        pkg["android_zh"] = m.group(1).strip() if m else ""
    if os.path.exists(ios_en):
        m = re.search(r'CFBundleDisplayName\s*=\s*"([^"]+)"', read_text(ios_en))
        pkg["ios_en"] = m.group(1) if m else ""
    if os.path.exists(android_en):
        m = re.search(r'<string name="app_name">([^<]+)</string>', read_text(android_en))
        pkg["android_en"] = m.group(1).strip() if m else ""

    # ---- ④ App Store 文案（英区 / 中区分列） ----
    asc = os.path.join(ROOT, "docs/商店文案_AppStore_v1.md")
    asc_name = ""
    asc_name_en = ""
    if os.path.exists(asc):
        s = read_text(asc)
        m = re.search(r"App Name（中区/简中）\s*\|\s*([^|\n]+?)\s*\|", s)
        asc_name = m.group(1).strip() if m else ""
        m = re.search(r"App Name（英区）\s*\|\s*([^|\n]+?)\s*\|", s)
        asc_name_en = m.group(1).strip() if m else ""
        if not asc_name:
            problems.append("④ App Store 文案里读不到中区名称")
    else:
        notes.append("④ 找不到 docs/商店文案_AppStore_v1.md（跳过）")

    # ---- 判定 ----
    zh_set = {k: v for k, v in {
        "①软著简称": soft.get("short", ""),
        "②商店应用名": store_short,
        "③iOS中文显示名": pkg.get("ios_zh", ""),
        "③Android中文显示名": pkg.get("android_zh", ""),
        "④App Store中区名": asc_name,
    }.items() if v}
    uniq = set(zh_set.values())
    if len(uniq) > 1:
        problems.append("中文名四方不一致：\n      " + "\n      ".join(f"{k} = {v}" for k, v in zh_set.items()))

    en_set = {k: v for k, v in {
        "①软著英文名": soft.get("en", ""),
        "③iOS英文显示名": pkg.get("ios_en", ""),
        "③Android英文显示名": pkg.get("android_en", ""),
        "④App Store英区名": asc_name_en,
    }.items() if v}
    if len(set(en_set.values())) > 1:
        problems.append("英文名不一致：\n      " + "\n      ".join(f"{k} = {v}" for k, v in en_set.items()))

    if asc_name and soft.get("short") and asc_name != soft["short"]:
        problems.append(f"④ App Store 中区名 = {asc_name} ≠ 软著简称 {soft['short']}")

    # ---- 旧名残留扫描（所有软著材料 + 商店文案） ----
    stale = ["向日葵专注(SunFocus)", "向日葵专注 SunFocus"]
    for rel in ["docs/商店文案_国内安卓_v1.md", "docs/商店截图清单.md",
                "docs/上架执行手册_安卓国内渠道_v1.md", "docs/上架注意事项_安卓国内渠道_v1.md"]:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            continue
        s = read_text(p)
        for kw in stale:
            # 修正说明段里引用旧名是允许的，只看是否被当作「当前名称」使用
            for line in s.splitlines():
                if kw in line and ("应用**" in line or "主推" in line or "桌面名" in line):
                    problems.append(f"旧名仍作当前名称使用：{rel} → {line.strip()[:80]}")

    mats = os.path.join(ROOT, "docs/软著材料")
    if os.path.isdir(mats):
        for fn in sorted(os.listdir(mats)):
            if not fn.endswith(".docx") or fn.startswith("~$"):
                continue
            txt = docx_text(os.path.join(mats, fn))
            if "向日葵专注" in txt or "SunFocus" in txt:
                problems.append(f"软著材料残留旧名：{fn}")

    # ---- 输出 ----
    print("=" * 68)
    print("名称一致性自检（软著 / 商店 / 安装包 四方）")
    print("=" * 68)
    print(f"  ① 软著软件全称   : {soft.get('full', '—')}")
    print(f"  ① 软著软件简称   : {soft.get('short', '—')}")
    print(f"  ① 软著英文名称   : {soft.get('en', '—')}")
    print(f"  ② 商店应用名称   : {store_short or '—'}")
    print(f"  ③ iOS 中文显示名 : {pkg.get('ios_zh', '—')}")
    print(f"  ③ iOS 英文显示名 : {pkg.get('ios_en', '—')}")
    print(f"  ③ Android 中文   : {pkg.get('android_zh', '—')}")
    print(f"  ③ Android 英文   : {pkg.get('android_en', '—')}")
    print(f"  ④ App Store 文案 : {asc_name or '—'}")
    print("-" * 68)
    for n in notes:
        print(f"  ℹ️  {n}")
    if problems:
        print(f"\n❌ 发现 {len(problems)} 处问题：")
        for i, p in enumerate(problems, 1):
            print(f"  {i}. {p}")
        return 1
    print("\n✅ 全一致 —— 软著简称 / 商店应用名 / 安装包显示名 / App Store 名 一字不差")
    return 0


if __name__ == "__main__":
    sys.exit(main())
