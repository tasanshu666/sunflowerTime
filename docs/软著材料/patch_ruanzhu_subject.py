#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
软著材料「主体信息」一键补丁脚本
================================
用途：把 5 份软著材料 docx 里的主体/格式项一次性改对，避免在 Word 里手改漏项。

改什么
------
1. 软著申请表  → 著作权人 = 营业执照名称全称；著作权人类型 = 企业
2. 产品使用手册 → 「本软件由个人开发者维护」→ 改为「由<主体简称>维护」
3. 全部 5 份  → 纸张 Letter(12240×15840) 改 A4(11906×16838)【软著要求 A4 纵向单面打印】

不改什么
--------
· 软件名称 / 版本号 / 开发完成日期 / 代码行数  → 这些要看路线选择，脚本不改，
  但会在结尾打印「一致性核对表」提醒你确认。
· 不碰图片、不碰目录占位符、不碰代码内容。

用法
----
  1) 先编辑同目录的 subject_info.json，填好主体信息
  2) python3 patch_ruanzhu_subject.py --dry-run   # 预演，不改文件
  3) python3 patch_ruanzhu_subject.py             # 实际改写（自动备份 .bak）
"""

import json
import os
import re
import shutil
import sys
import zipfile

BASE = os.path.dirname(os.path.abspath(__file__))
INFO = os.path.join(BASE, "subject_info.json")

DOCS = [
    "软著申请表_小小葵番茄钟.docx",
    "源代码鉴别材料_小小葵番茄钟.docx",
    "文档鉴别材料_小小葵番茄钟.docx",
    "产品使用手册_小小葵番茄钟.docx",
    "软件设计说明书_小小葵番茄钟.docx",
]

# Letter -> A4 (twips)
LETTER = '<w:pgSz w:w="12240" w:h="15840"/>'
A4 = '<w:pgSz w:w="11906" w:h="16838"/>'

PLACEHOLDER_MARK = "【"


def load_info():
    with open(INFO, encoding="utf-8") as f:
        return json.load(f)


def patch_docx(path, info):
    """返回 (改动说明列表, 是否实际写入)"""
    changes = []
    zin = zipfile.ZipFile(path, "r")
    items = zin.infolist()
    blobs = {i.filename: zin.read(i.filename) for i in items}
    zin.close()

    # ---------- 1) 主体信息替换 ----------
    for part in ("word/document.xml",):
        if part not in blobs:
            continue
        xml = blobs[part].decode("utf-8")

        # 著作权人：只替换「【请填写权利人姓名】」这一处精确串
        if "【请填写权利人姓名】" in xml:
            xml = xml.replace("【请填写权利人姓名】", info["full_name"])
            changes.append(f"{os.path.basename(path)}: 著作权人 → {info['full_name']}")

        # 著作权人类型：把「个人」单独成 run 的那一格换掉
        # 只替换 <w:t>个人</w:t> 这种整段等于「个人」的 run，不动「通用个人计算机…」
        xml2, n = re.subn(
            r"(<w:t(?: [^>]*)?>)个人(</w:t>)",
            lambda m: m.group(1) + info["type"] + m.group(2),
            xml,
        )
        if n:
            xml = xml2
            changes.append(f"{os.path.basename(path)}: 著作权人类型 → {info['type']}（{n} 处）")

        # 产品使用手册里的「本软件由个人开发者维护」
        for old, new in [
            ("本软件由个人开发者维护", f"本软件由{info['short_name']}开发维护"),
        ]:
            if old in xml:
                xml = xml.replace(old, new)
                changes.append(f"{os.path.basename(path)}: 「{old}」→「{new}」")

        blobs[part] = xml.encode("utf-8")

    # ---------- 2) 纸张 Letter → A4 ----------
    for part in list(blobs.keys()):
        if not part.startswith("word/") or not part.endswith(".xml"):
            continue
        xml = blobs[part].decode("utf-8")
        if LETTER in xml:
            c = xml.count(LETTER)
            xml = xml.replace(LETTER, A4)
            blobs[part] = xml.encode("utf-8")
            changes.append(
                f"{os.path.basename(path)}/{part.split('/')[-1]}: 纸张 Letter→A4（{c} 处）"
            )

    return changes, blobs, items


def write_docx(path, blobs, items):
    shutil.copy2(path, path + ".bak")
    tmp = path + ".tmp"
    zout = zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED)
    for i in items:
        zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = i.external_attr
        zout.writestr(zi, blobs[i.filename])
    zout.close()
    os.replace(tmp, path)


def main():
    dry = "--dry-run" in sys.argv
    info = load_info()

    print("=" * 68)
    print("软著材料主体信息补丁" + ("（预演模式，不写文件）" if dry else ""))
    print("=" * 68)
    print(f"  著作权人    : {info['full_name']}")
    print(f"  简称        : {info['short_name']}")
    print(f"  类型        : {info['type']}")
    print(f"  经营者      : {info['operator']}")
    print(f"  经营场所    : {info['address']}")
    print("-" * 68)

    if PLACEHOLDER_MARK in info["full_name"] or PLACEHOLDER_MARK in info["short_name"]:
        print("⚠️  subject_info.json 里还有【】占位符，先填好再跑。")
        return 1

    all_changes = []
    for d in DOCS:
        p = os.path.join(BASE, d)
        if not os.path.exists(p):
            print(f"✗ 缺文件: {d}")
            continue
        changes, blobs, items = patch_docx(p, info)
        if changes:
            all_changes.extend(changes)
            if not dry:
                write_docx(p, blobs, items)
        else:
            print(f"· {d}: 无需改动")
        for c in changes:
            print(f"  ✓ {c}")

    print("-" * 68)
    print(f"合计 {len(all_changes)} 处改动" + ("（未写入）" if dry else "（已写入，原文件已存 .bak）"))
    print()
    print("📋 接下来请你人工确认（脚本不改这些）：")
    print("   1) 申请表「软件主要功能」字数需落在 500–1300 字")
    print("   2) 申请表「代码行数」是否与当前 lib/ 实际行数一致")
    print("   3) 申请表「开发完成日期」必须 ≥ 源码最后修改日")
    print("   4) 三份文档的目录占位符需在 Word 里用「引用→目录」自动生成")
    print("   5) 官方申请表必须在中国版权保护中心官网在线生成，本 docx 仅作草稿")
    return 0


if __name__ == "__main__":
    sys.exit(main())
