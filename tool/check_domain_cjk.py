#!/usr/bin/env python3
"""T03/T04/T05 收尾自查：`lib/domain/**` 内「注释外」是否残留 CJK。

判定口径：
  · 逐行扫描；识别 `//` 行注释、`///` 文档注释、`/* ... */` 块注释；
  · 字符串字面量里的 CJK **不算注释**，会被报出来（这是真正的漏网文案）；
  · 输出「文件:行号: 片段」，并给出总计数与按文件汇总。

用途：i18n B3 的验收门槛之一（domain 零 CJK）。

演进：
  · T03 只清「枚举 / 实体 / 异常」几个文件（白名单登记 `task_checkin_service`）；
  · **T05 收口：白名单已清空** —— 全部 dev 侧 `StateError` / `ArgumentError` 文案
    改为 ASCII 英文，故本脚本零豁免，PASS 即代表真·零 CJK。
"""
import pathlib
import re
import sys

CJK = re.compile(r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]')
DOMAIN = pathlib.Path('lib/domain')

# 豁免白名单（**T05 起为空**）：任何人想往里加名字，都必须先说服
# `test/i18n/no_han_in_domain_test.dart` 的白名单也为空 —— 该测试直接钉死「零豁免」。
EXEMPT_MSG_FILES = set()


def strip_line_comment(line: str) -> str:
    """去掉行注释（引号内的 `//` 不算）。"""
    out = []
    i = 0
    quote = None
    while i < len(line):
        c = line[i]
        if quote:
            out.append(c)
            if c == '\\' and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in ('"', "'"):
            quote = c
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < len(line) and line[i + 1] == '/':
            break
        out.append(c)
        i += 1
    return ''.join(out)


def scan(path: pathlib.Path):
    hits = []
    in_block = False
    for lineno, raw in enumerate(path.read_text(encoding='utf-8').split('\n'), 1):
        line = raw
        if in_block:
            end = line.find('*/')
            if end < 0:
                continue
            line = ' ' * (end + 2) + line[end + 2:]
            in_block = False
        start = line.find('/*')
        while start >= 0:
            end = line.find('*/', start + 2)
            if end < 0:
                line = line[:start]
                in_block = True
                break
            line = line[:start] + ' ' * (end + 2 - start) + line[end + 2:]
            start = line.find('/*')
        code = strip_line_comment(line)
        if CJK.search(code):
            hits.append((lineno, raw.strip()))
    return hits


def main():
    total = 0
    per_file = {}
    for path in sorted(DOMAIN.rglob('*.dart')):
        hits = scan(path)
        if hits:
            per_file[str(path)] = hits
            total += len(hits)

    if not per_file:
        print('RESULT: PASS — lib/domain/** 注释外零 CJK')
        return 0

    print(f'RESULT: {total} 处非注释 CJK，分布 {len(per_file)} 个文件\n')
    for path, hits in per_file.items():
        exempt = path in EXEMPT_MSG_FILES
        tag = ' [StateError 豁免登记]' if exempt else ''
        print(f'--- {path}  （{len(hits)} 处）{tag}')
        for lineno, text in hits:
            print(f'    {lineno}: {text}')
        print()
    return 1


if __name__ == '__main__':
    sys.exit(main())
