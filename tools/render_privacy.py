#!/usr/bin/env python3
"""把隐私政策 Markdown 底稿渲染成可直接上传的公网页面（自包含 HTML）。

用法：
    /Users/wangjunchao/.workbuddy/binaries/python/envs/default/bin/python tools/render_privacy.py

输入（底稿，含内部待办，不直接发布）：
    docs/隐私政策_向日葵专注_v1.md
    docs/隐私政策_向日葵专注_v1_EN.md

输出（发布稿，上传到 sunfocused.cn 站点根目录）：
    docs/隐私政策_发布版/privacy.html       → https://sunfocused.cn/privacy.html
    docs/隐私政策_发布版/privacy-en.html    → https://sunfocused.cn/privacy-en.html

发布稿与底稿的差异（有意为之）：
  1. 剔除「附：待确认项汇总 / Open Items」整节（内部待办，不对公众展示）；
  2. 占位符替换为可对外的中性表述；
  3. 加站点导航、语言切换、页脚版本信息。
如底稿改了口径，重跑本脚本即可，勿手改输出文件。
"""

import pathlib
import re

import markdown

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = DOCS / "隐私政策_发布版"

ZH_SRC = DOCS / "隐私政策_向日葵专注_v1.md"
EN_SRC = DOCS / "隐私政策_向日葵专注_v1_EN.md"

# 底稿里的内部占位 → 对外表述（2026-10-23 应用更名后底稿已直接写最终名，以下多为兜底）
ZH_REPLACEMENTS = [
    ("【开发者实体名称占位】", "小小葵（个人开发者）"),
    ("- 开发者实体名称 / 地址：【占位，上架前补全】", "- 开发者：小小葵（个人开发者）"),
    ("【待定】", "说明："),
    ("（待填）", ""),
]
EN_REPLACEMENTS = [
    ("【Developer legal entity name — placeholder】", "Xiaoxiaokui (individual developer)"),
    ("- Developer legal entity name / address: 【placeholder — to be completed before launch】",
     "- Developer: Xiaoxiaokui (individual developer)"),
    ("【TBD】", "Note:"),
    ("(TBD)", ""),
]

TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{canonical}">
<meta name="robots" content="index,follow">
<meta name="theme-color" content="#FBF7EF">
<link rel="icon" href="favicon.ico" sizes="any">
<link rel="icon" type="image/png" sizes="32x32" href="src/assets/img/favicon-32.png">
<meta property="og:type" content="article">
<meta property="og:site_name" content="小小葵番茄钟 Tiny Sunflower">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="https://sunfocused.cn/src/assets/img/og-cover.jpg">
<meta name="twitter:card" content="summary_large_image">
<style>
  :root {{
    --bg: #FBF7EF;
    --card: #FFFDF8;
    --ink: #2E2A24;
    --muted: #6B5F4C;
    --line: #E6DECC;
    --green: #3F6B4E;
    --amber: #C9862F;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB",
                 "Microsoft YaHei", "Segoe UI", Roboto, sans-serif;
    font-size: 16px;
    line-height: 1.85;
    -webkit-font-smoothing: antialiased;
  }}
  .topbar {{
    position: sticky; top: 0; z-index: 10;
    background: rgba(251, 247, 239, .94);
    backdrop-filter: saturate(180%) blur(8px);
    border-bottom: 1px solid var(--line);
  }}
  .topbar .inner {{
    max-width: 780px; margin: 0 auto; padding: 12px 22px;
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    font-size: 14px;
  }}
  .topbar a {{ color: var(--green); text-decoration: none; }}
  .topbar a:hover {{ text-decoration: underline; }}
  .brand {{ font-weight: 600; letter-spacing: .02em; }}
  .wrap {{ max-width: 780px; margin: 0 auto; padding: 40px 22px 72px; }}
  h1 {{ font-size: 30px; line-height: 1.35; margin: 8px 0 20px; letter-spacing: .01em; }}
  h2 {{
    font-size: 21px; margin: 46px 0 14px; padding-bottom: 8px;
    border-bottom: 1px solid var(--line); color: var(--green);
  }}
  h3 {{ font-size: 17px; margin: 28px 0 10px; }}
  p {{ margin: 12px 0; }}
  a {{ color: var(--green); }}
  strong {{ font-weight: 600; }}
  hr {{ border: 0; border-top: 1px solid var(--line); margin: 36px 0; }}
  blockquote {{
    margin: 18px 0; padding: 12px 16px;
    background: var(--card);
    border-left: 3px solid var(--amber);
    border-radius: 4px;
    color: var(--muted);
    font-size: 15px;
  }}
  blockquote p {{ margin: 6px 0; }}
  table {{
    width: 100%; border-collapse: collapse; margin: 16px 0;
    font-size: 14.5px; line-height: 1.7; word-break: break-word;
  }}
  th, td {{ border: 1px solid var(--line); padding: 9px 11px; text-align: left; vertical-align: top; }}
  th {{ background: #F3EDDF; font-weight: 600; }}
  tr:nth-child(even) td {{ background: rgba(255, 253, 248, .6); }}
  code {{
    background: #F1EBDD; padding: 1px 5px; border-radius: 4px;
    font-size: 13.5px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }}
  ul, ol {{ padding-left: 22px; }}
  li {{ margin: 6px 0; }}
  footer {{
    max-width: 780px; margin: 0 auto; padding: 0 22px 56px;
    color: var(--muted); font-size: 13px; line-height: 1.8;
  }}
  @media (max-width: 600px) {{
    body {{ font-size: 15.5px; }}
    h1 {{ font-size: 25px; }}
    h2 {{ font-size: 19px; margin-top: 38px; }}
    table {{ font-size: 13px; }}
    th, td {{ padding: 7px 8px; }}
  }}
</style>
</head>
<body>
<div class="topbar">
  <div class="inner">
    <a class="brand" href="https://sunfocused.cn/">小小葵番茄钟</a>
    <span>{switcher}</span>
  </div>
</div>
<main class="wrap">
{body}
</main>
<footer>
  {footer}
</footer>
</body>
</html>
"""


def render(src: pathlib.Path, lang: str, title: str, description: str,
           canonical: str, drop_heading: str, switcher: str, footer: str, replacements) -> str:
    text = src.read_text(encoding="utf-8")

    # 1) 剔除内部待办小节（从该标题到文件末尾）
    idx = text.find(drop_heading)
    if idx == -1:
        raise SystemExit(f"未找到待剔除小节：{drop_heading}（{src.name}）")
    text = text[:idx].rstrip().rstrip("-").rstrip()

    # 2) 占位符替换
    for old, new in replacements:
        text = text.replace(old, new)

    # 3) 剔除只给内部看的行（发布流程说明、内部裁决编号等）
    internal_line = re.compile(
        r"^>.*(发布稿生成|公网发布|Generated by|Published at).*$\n?", re.MULTILINE
    )
    text = internal_line.sub("", text)
    text = text.replace("二、我们是谁（开发者信息占位）", "二、我们是谁（开发者信息）")
    text = text.replace("2. Who We Are (developer information placeholder)",
                        "2. Who We Are (developer information)")

    # 3.1) 顶部元信息是连续 `>` 行，Markdown 会合并成一段；逐行拆段以便阅读
    lines, spaced, in_quote = text.split("\n"), [], False
    for line in lines:
        if line.startswith(">"):
            if in_quote:
                spaced.append("")
            in_quote = True
        else:
            in_quote = False
        spaced.append(line)
    text = "\n".join(spaced)

    # 4) 去掉与模板重复的一级标题
    text = re.sub(r"^#\s+.*?\n", "", text, count=1)

    body = markdown.markdown(text, extensions=["tables", "sane_lists"])
    return TEMPLATE.format(lang=lang, title=title, description=description,
                           canonical=canonical, switcher=switcher, body=body, footer=footer)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    zh = render(
        ZH_SRC, "zh-CN",
        title="隐私政策｜小小葵番茄钟 Tiny Sunflower",
        description="小小葵番茄钟（Tiny Sunflower）隐私政策：不联网、不收集个人信息，数据仅存本机。",
        canonical="https://sunfocused.cn/privacy.html",
        drop_heading="## 附：待确认项汇总",
        switcher='<a href="privacy-en.html" hreflang="en">English</a>',
        footer='版本 v2.0 ｜ 生效日期 2026-10-23 ｜ 开发者 小小葵 ｜ 1007681634@qq.com<br>'
               'English version: <a href="privacy-en.html">Privacy Policy (English)</a><br>'
               '<a href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">京ICP备2026070040号-1</a>',
        replacements=ZH_REPLACEMENTS,
    )
    (OUT / "privacy.html").write_text(zh, encoding="utf-8")

    en = render(
        EN_SRC, "en",
        title="Privacy Policy | Tiny Sunflower",
        description="Tiny Sunflower privacy policy: offline by design, no personal data collected, everything stays on your device.",
        canonical="https://sunfocused.cn/privacy-en.html",
        drop_heading="## Open Items (to be confirmed)",
        switcher='<a href="privacy.html" hreflang="zh-Hans">简体中文</a>',
        footer='Version v2.0 ｜ Effective 23 October 2026 ｜ Developer Xiaoxiaokui ｜ 1007681634@qq.com<br>'
               '简体中文版：<a href="privacy.html">隐私政策（简体中文）</a><br>'
               '<a href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">京ICP备2026070040号-1</a>',
        replacements=EN_REPLACEMENTS,
    )
    (OUT / "privacy-en.html").write_text(en, encoding="utf-8")

    for name in ("privacy.html", "privacy-en.html"):
        p = OUT / name
        print(f"{p}  ({p.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
