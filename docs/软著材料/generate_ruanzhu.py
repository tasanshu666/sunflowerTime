#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
向日葵专注(SunFocus)少儿专注力养成软件 V1.0 —— 软著登记材料生成器

生成 5 份 DOCX：
  1. 软件设计说明书
  2. 源代码鉴别材料（前30页 + 后30页，50行/页）
  3. 文档鉴别材料（精简版用户手册，含截图占位）
  4. 软著申请表
  5. 产品使用手册

所有内容基于仓库内真实 PRD（v2.0）/ 开发计划（v1.0）与 lib/ 实际代码结构撰写，
禁止虚构不存在的功能模块。
权利人姓名、开发完成日期由用户提供，未提供时以占位符标注。
"""

import os
import sys
from datetime import date

from docx import Document
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# ----------------------------------------------------------------------------
# 配置（软著登记关键信息；★ 标注项需由权利人确认/替换）
# ----------------------------------------------------------------------------
C = {
    "full_name": "向日葵专注(SunFocus)少儿专注力养成软件",   # 软件全称（证书印名）
    "short_name": "向日葵专注",                               # 软件简称
    "version": "V1.0",
    "right_holder": "【请填写权利人姓名】",                  # ★ 个人姓名 / 公司营业执照全称
    "right_type": "个人",                                    # 个人 / 公司
    "publish_status": "未发表",                              # 未发表 / 已发表
    "acquisition": "原始取得",                               # 原始取得 / 受让取得
    "right_scope": "全部权利",                               # 全部权利 / 部分权利
    "dev_complete": "2026-10-10",  # ★ 开发完成日期（用户指定）
    "first_publish": "不适用（未发表）",
    "classification": "教育软件 / 儿童习惯养成工具",
    "purpose": "为小学阶段儿童提供以“阳光养成植物”为隐喻的专注力与学习习惯训练工具，"
               "帮助孩子在低打扰环境下建立规律、可回看的专注习惯；同时为家长提供"
               "可视化的专注报告与可兑现的家庭奖励体系。",
    "domain": "教育 / 儿童身心健康 / 家庭教育",
    "tech_features": "采用 Flutter 跨平台框架实现单机运行；专注状态检测在设备本地完成、"
                     "零影像上传；本地加密数据库（SQLCipher）存储专注与成长记录；"
                     "分层架构（表现层/领域层/数据层）并通过 Repository 抽象预留账号与云同步接入点；"
                     "以“打盹屏”低亮状态表替代高亮动画，降低对注意力的抢夺。",
    "language": "Dart（Flutter 框架）；少量 Kotlin / Swift 平台桥接代码",
    "os": "Android 8.0 及以上（ARM64 / x86_64）；iOS 12.0 及以上（iPhone / iPad，ARM64）",
    "software_env": "Android / iOS 操作系统；Flutter 3.x 框架、Dart SDK 3.x",
    "dev_env": "Windows / macOS；Android Studio / VS Code；Dart SDK 3.x、Flutter SDK",
    "hw_run": "Android / iOS 移动设备（建议 4GB 以上内存）",
    "hw_dev": "通用个人计算机（x86_64，8GB 以上内存）",
    "dev_os": "Windows 10+ / macOS 12+",
    "code_lines": 0,   # 运行时统计
}

REPO = "/Users/wangjunchao/WorkBuddy/sunflowerTime"
OUT = "/Users/wangjunchao/WorkBuddy/sunflowerTime/docs/软著材料"
# 真实界面截图根目录（用户 2026-10-11 提供，用于替换文档中的占位图）
SCREENSHOT_BASE = "/Users/wangjunchao/OH_WorkSpace/码农爸爸AI养娃运营/assets/产品截图/向日葵专注截图"

# ----------------------------------------------------------------------------
# 基础工具
# ----------------------------------------------------------------------------

def set_eastasia(run, font="宋体"):
    """设置中文（东亚）字体，保证 Windows Word 下中文用宋体/黑体渲染。"""
    run.font.name = "Times New Roman"
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn('w:rFonts'))
    if rfonts is None:
        rfonts = OxmlElement('w:rFonts')
        rpr.append(rfonts)
    rfonts.set(qn('w:ascii'), "Times New Roman")
    rfonts.set(qn('w:hAnsi'), "Times New Roman")
    rfonts.set(qn('w:eastAsia'), font)


def style_doc(doc):
    """正文默认字体：宋体 小四(12pt)，行距 1.5。"""
    normal = doc.styles['Normal']
    normal.font.name = "Times New Roman"
    normal.font.size = Pt(12)
    normal.element.rPr.rFonts.set(qn('w:eastAsia'), "宋体")
    pf = normal.paragraph_format
    pf.line_spacing = 1.5
    pf.space_after = Pt(6)


def add_title(doc, text, size=22, bold=True, color=None, space_before=0, space_after=12):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(space_before)
    p.paragraph_format.space_after = Pt(space_after)
    r = p.add_run(text)
    r.bold = bold
    r.font.size = Pt(size)
    if color:
        r.font.color.rgb = color
    set_eastasia(r, "黑体")
    return p


def add_heading(doc, text, level=1):
    sizes = {1: 16, 2: 14, 3: 13}
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10 if level == 1 else 6)
    p.paragraph_format.space_after = Pt(4)
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(sizes.get(level, 13))
    set_eastasia(r, "黑体")
    return p


def add_para(doc, text, indent=False, size=12, bold=False):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    if indent:
        p.paragraph_format.left_indent = Inches(0.3)
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.bold = bold
    set_eastasia(r, "宋体")
    return p


def add_bullet(doc, text, size=12):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_after = Pt(3)
    r = p.add_run(text)
    r.font.size = Pt(size)
    set_eastasia(r, "宋体")
    return p


def add_image_placeholder(doc, caption, images=None):
    """有真实截图则居中嵌入并加图注；无则保留蓝色占位符待补。"""
    if images:
        from PIL import Image
        for rel in images:
            path = rel if rel.startswith("/") else os.path.join(SCREENSHOT_BASE, rel)
            with Image.open(path) as im:
                w, h = im.size
            # 横屏图放宽、竖屏手机截图收窄，避免超出页高
            width = Inches(5.8) if w >= h else Inches(3.6)
            doc.add_picture(path, width=width)
            last = doc.paragraphs[-1]
            last.alignment = WD_ALIGN_PARAGRAPH.CENTER
            last.paragraph_format.space_before = Pt(6)
            last.paragraph_format.space_after = Pt(2)
        cap = doc.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap.paragraph_format.space_after = Pt(10)
        r = cap.add_run("图：" + caption)
        r.bold = True
        r.font.size = Pt(10)
        set_eastasia(r, "黑体")
        return cap
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(8)
    r = p.add_run("【图：" + caption + "】")
    r.bold = True
    r.font.size = Pt(12)
    r.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)
    set_eastasia(r, "黑体")
    return p


def add_page_number_footer(section):
    """页脚插入 PAGE 域（纯数字页码，无前后缀）。"""
    footer = section.footer
    footer.is_linked_to_previous = False
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    fldChar1 = OxmlElement('w:fldChar'); fldChar1.set(qn('w:fldCharType'), 'begin')
    instrText = OxmlElement('w:instrText'); instrText.set(qn('xml:space'), 'preserve'); instrText.text = 'PAGE'
    fldChar2 = OxmlElement('w:fldChar'); fldChar2.set(qn('w:fldCharType'), 'end')
    run._r.append(fldChar1); run._r.append(instrText); run._r.append(fldChar2)
    set_eastasia(run, "宋体")


def add_header(section, text):
    section.header.is_linked_to_previous = False
    p = section.header.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(text)
    r.font.size = Pt(9)
    set_eastasia(r, "宋体")


def add_cover(doc, title, subtitle=None):
    for _ in range(4):
        doc.add_paragraph()
    add_title(doc, C["full_name"], size=26, space_after=6)
    add_title(doc, "——" + title + "——", size=18, space_after=30)
    if subtitle:
        add_title(doc, subtitle, size=14, bold=False, space_after=30)
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = meta.add_run(f"版本号：{C['version']}    编制日期：{date.today().isoformat()}")
    r.font.size = Pt(12); set_eastasia(r, "宋体")
    doc.add_page_break()


def add_toc_placeholder(doc):
    add_heading(doc, "目录", level=1)
    for _ in range(18):
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(4)
        r = p.add_run("（由编制人使用 Word 自动生成目录功能插入）")
        r.font.size = Pt(11); r.font.color.rgb = RGBColor(0x80, 0x80, 0x80)
        set_eastasia(r, "宋体")
    doc.add_page_break()


# ----------------------------------------------------------------------------
# 1. 软件设计说明书
# ----------------------------------------------------------------------------

def build_design_spec():
    doc = Document()
    style_doc(doc)
    sec = doc.sections[0]
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "软件设计说明书")

    # 正文分节
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)

    add_toc_placeholder(doc)

    # 第1章 概述
    add_heading(doc, "第1章 概述", 1)
    add_heading(doc, "1.1 项目背景", 2)
    add_para(doc, "向日葵专注（SunFocus）是一款面向小学阶段（6–12 岁）儿童的专注力与学习习惯养成工具。"
                  "产品以“阳光养成植物”为教育隐喻：孩子通过专注积累“阳光”，用阳光养护心流花园、兑换由家长真实兑现的家庭奖励，"
                  "从而形成可回看、低挫败的专注习惯。产品定位为“教育工具 / 习惯养成工具”，而非游戏。")
    add_heading(doc, "1.2 设计目标", 2)
    add_bullet(doc, "低打扰：专注中屏幕只做“可瞟不可盯”的状态表，不抢注意力。")
    add_bullet(doc, "损失可挽回：任何惩罚都留有补救路径，避免孩子挫败弃用。")
    add_bullet(doc, "隐私优先：专注状态本地处理、数据最小必要，无账号、无云同步、无影像上传。")
    add_bullet(doc, "家长可参与：提供专注报告与可兑现的家庭奖励体系，降低家长维护成本。")
    add_heading(doc, "1.3 范围", 2)
    add_para(doc, "本说明书覆盖 MVP（Plan B 纯本地单机形态）的设计范围：专注模式、端上专注度检测、学习打卡、"
                  "阳光经济系统、植物养成、阳光商店与家庭奖励、家长端、防沉迷与防作弊，以及数据安全与合规设计。")

    # 第2章 系统架构
    add_heading(doc, "第2章 系统架构", 1)
    add_para(doc, "软件采用典型的分层架构，依赖方向为 表现层 → 领域层 → 数据层，平台层提供原生能力桥接，"
                  "核心层承载全局常量与工具函数。")
    add_image_placeholder(doc, "系统分层架构图", images=[os.path.join(OUT, "arch_diagram.png")])
    add_heading(doc, "2.1 表现层（presentation）", 2)
    add_para(doc, "负责所有界面与交互，包括孩子端竖屏主界面（今日状态卡、专注入口、任务、花园、我的）、"
                  "横屏专注页（打盹屏）、休息/假期态页、锁定页与家长端独立页面。")
    add_heading(doc, "2.2 领域层（domain）", 2)
    add_para(doc, "承载业务实体（如专注会话、阳光账户、植物、任务、奖励、家长配置）、领域服务与 Repository 接口定义，"
                  "不依赖任何 Flutter / 数据库框架，保证业务逻辑可独立测试。")
    add_heading(doc, "2.3 数据层（data）", 2)
    add_para(doc, "基于 Drift（SQLite）与 SQLCipher 实现本地加密数据库，提供 DAO 与本地 Repository 实现；"
                  "设置项使用 shared_preferences，PIN 使用 flutter_secure_storage 哈希加盐存储于安全区。")
    add_heading(doc, "2.4 平台层（platform）", 2)
    add_para(doc, "封装常亮（wakelock_plus）、设备方向（native_device_orientation）、音频播放等原生能力调用。")
    add_heading(doc, "2.5 核心层（core）与共享层（shared）", 2)
    add_para(doc, "core 集中所有可调数值常量（prd_params）并逐条注释对应 PRD 节号，避免“孪生”硬编码；"
                  "shared 承载跨模块复用的基础组件与模型。")
    add_heading(doc, "2.6 账号与云同步预留", 2)
    add_para(doc, "领域层仅依赖接口；MVP 以本地 Repository 实装，代码中预留 account_service 桩与 Synced Repository 接入点，"
                  "未来扩展账号/云同步时领域服务零改动。")

    # 第3章 功能模块详细设计
    add_heading(doc, "第3章 功能模块详细设计", 1)
    add_heading(doc, "3.1 专注模式（打盹屏）", 2)
    add_para(doc, "横屏进入专注页后，屏幕呈现低亮、慢频、零突事件的“打盹屏”：顶部仅保留本次倒计时，"
                  "中央显示呼吸式明暗的向日葵，每完成 1/2 进度向外送出一粒光（半程触发 1 次）。专注期间无操作区、无突事件；"
                  "竖屏退出即暂停并弹出确认。到时自动结算，亮屏播放结算动画（光从屏外归来、落入阳光池）。")
    add_para(doc, "向日葵反馈系统采用四档梯度：常态产光（无声陪伴）、随光报信（画面气泡+极轻震动）、"
                  "欢迎回来（纯视觉光晕）、唤醒提醒（语音，离席超阈值触发，全场有声≤3 次/场 + 结算 1 次/场）。")
    add_image_placeholder(doc, "专注模式流程图 / 打盹屏布局示意",
                          images=["孩子端截图/专注界面.jpg", "孩子端截图/专注中收集阳光过程.jpg"])
    add_heading(doc, "3.2 端上专注度检测（本地，零上传）", 2)
    add_para(doc, "MVP 基线为屏幕交互检测：通过系统灭屏、竖屏、长时间无触摸交互判定“疑似离席”，"
                  "重新亮屏回到专注视为恢复在场。离席期间产出停止且不扣减已有产出；恢复后在场窗口起算、"
                  "10 秒内线性回到 100% 速率。原始帧不落盘、不上传，仅本地推断在场/离席状态。")
    add_heading(doc, "3.3 学习打卡模块", 2)
    add_para(doc, "提供内置任务模板（语文/数学作业、阅读、背单词等），家长可增删改并设定每周重复；"
                  "开启“需关联专注”的任务须有一次≥15 分钟专注记录方可打卡。任务完成获固定阳光，"
                  "“专注+打卡”同日达成触发“完美学习日”加成。成就徽章采用累计制，避免断档清零的挫败。")
    add_heading(doc, "3.4 阳光经济系统", 2)
    add_para(doc, "阳光为唯一虚拟货币，产出侧 1:1 且与年龄系数 K 解耦。专注 1 分钟 = 1 阳光；"
                  "有效阳光 = min(本场专注阳光, 今日剩余额度)，今日剩余额度 = 年段日上限 − 今日已入账专注阳光"
                  "（年段日上限：低年级 6–8 岁 60 分钟、中年级 9–10 岁 90 分钟、高年级 11–12 岁 120 分钟）。"
                  "任务打卡固定值（可调），完美日加成计入额度（受同一上限约束）。"
                  "消耗侧定价以家长设定单价为准（显示价 = 扣费价，不再叠加分龄系数 K）。"
                  "阳光不可充值、不可交易、不可赠送（家长赠予除外），切断游戏内购属性。")
    add_image_placeholder(doc, "阳光经济：有效值与年段日上限示意", images=[os.path.join(OUT, "sun_economy_diagram.png")])
    add_heading(doc, "3.5 植物养成系统", 2)
    add_para(doc, "阳光的主要长期沉淀处——“心流花园”。提供多种植物图鉴，成长分多阶段（种子→发芽→幼苗→含苞→盛开），"
                  "可浇水/施肥加速；植物绝不因专注差而死（底线），成长速度仅与当日有效专注软挂钩。"
                  "花园容量初始若干花盆，可解锁扩展。枯萎可低成本救回，长期未养护则死亡并返还部分种植成本。")
    add_heading(doc, "3.6 阳光商店与家庭奖励", 2)
    add_para(doc, "孩子用阳光发起奖励兑换申请，家长端手动核销（现实兑现后扣除）。"
                  "设定免确认双条件（单笔低于阈值且当月累计不超过预算池比例）自动放行，自服务类不自动放行。"
                  "家长设月度奖励预算池，超额不拒绝、改“排队中”于下月放行。提供冷却期状态化表达与强制替代推荐。")
    add_image_placeholder(doc, "商店兑换与核销流程图",
                          images=["孩子端截图/商店页.png", "家长端截图/家长今日审核页.png"])
    add_heading(doc, "3.7 家长端", 2)
    add_para(doc, "以本地 PIN 锁进入的独立页面，功能含：今日概览、夸夸台（向日葵转述表扬）、专注报告、"
                  "任务配置、奖励配置与核销、专注/防沉迷/年龄档设置、阳光赠予、账号找回与删除入口。")
    add_heading(doc, "3.8 防沉迷与防作弊", 2)
    add_para(doc, "防沉迷：每日专注总时长上限按年龄分档、每日 App 总使用时长上限、可用时段与夜间边界统一收口于单一参数；"
                  "连续专注后强制休息。防作弊：承认单设备无法 100% 判定“真专注”，以本地检测+家长裁决为主，"
                  "靠“产出与真实学习成果脱钩”（奖励需家长核销）稀释作弊价值，文案保持善意。")

    # 第4章 技术栈
    add_heading(doc, "第4章 技术栈与运行环境", 1)
    add_bullet(doc, "开发语言：Dart（Flutter 框架），少量 Kotlin/Swift 平台桥接代码。")
    add_bullet(doc, f"运行平台：{C['os']}")
    add_bullet(doc, "状态管理：Riverpod 2.x。")
    add_bullet(doc, "本地存储：Drift（SQLite）+ SQLCipher 加密；设置 KV 用 shared_preferences；PIN 用 flutter_secure_storage。")
    add_bullet(doc, "动画：Flutter 原生 CustomPainter（打盹屏轻量绘制）。")
    add_bullet(doc, "音频：just_audio（预录台词）+ flutter_tts（备选）。")
    add_bullet(doc, "常亮/方向：wakelock_plus、native_device_orientation。")
    add_bullet(doc, "路由/不可变/时间：go_router、freezed、intl。")

    # 第5章 数据安全与合规
    add_heading(doc, "第5章 数据安全与合规设计", 1)
    add_para(doc, "软件采用 Plan B 纯本地单机形态：无账号、无家庭组、无云同步、无网络传输，"
                  "本地基础义务做足。")
    add_bullet(doc, "本地隐私与处理说明：明确收集范围为本地专注状态与成长记录。")
    add_bullet(doc, "监护人本地告知同意，含拒绝选项。")
    add_bullet(doc, "删除权：提供删除入口、响应时限与删除范围（账户内数据+行为记录）；毕业时先导出成册再清空账户。")
    add_bullet(doc, "最短必要期限 + 到期自清。")
    add_bullet(doc, "本地加密存储敏感字段（SQLCipher）。")
    add_bullet(doc, "对外如实表述收集范围，不使用“不拍摄/不存储/不上传任何影像”等绝对化承诺。")

    # 附录
    add_heading(doc, "附录A 模块与关键类清单（基于实际代码结构）", 1)
    add_para(doc, "源码按分层组织，主要目录如下（均位于 lib/ 下）：")
    add_bullet(doc, "lib/domain —— 实体、枚举、Repository 接口、领域服务。")
    add_bullet(doc, "lib/data —— Drift 数据库定义、DAO、本地 Repository 实现。")
    add_bullet(doc, "lib/presentation —— 孩子端/家长端界面与状态管理（Riverpod）。")
    add_bullet(doc, "lib/core —— 全局常量（prd_params）、工具函数。")
    add_bullet(doc, "lib/platform —— 原生能力桥接。")
    add_bullet(doc, "lib/shared —— 跨模块复用组件与模型。")
    add_para(doc, "详细源代码见随附《源代码鉴别材料》。")

    path = os.path.join(OUT, f"软件设计说明书_{C['short_name']}.docx")
    doc.save(path)
    return path


# ----------------------------------------------------------------------------
# 2. 源代码鉴别材料
# ----------------------------------------------------------------------------

def strip_dart_comments(code: str) -> str:
    """剥离 Dart 源码中的 // 与 /* */ 注释，保留字符串字面量（含单引号/双引号/三引号及 r 前缀）原样。

    用于软著源代码鉴别材料：只保留纯代码，不夹带任何注释。
    """
    out = []
    i = 0
    n = len(code)
    in_block = False
    while i < n:
        if in_block:
            if code[i:i + 2] == "*/":
                in_block = False
                i += 2
            elif code[i] == "\n":
                out.append("\n")
                i += 1
            else:
                i += 1
            continue
        # 字符串检测（含 raw 前缀 r）
        raw = (code[i] == "r" and i + 1 < n and code[i + 1] in ("'", '"'))
        si = i + (1 if raw else 0)
        three = code[si:si + 3]
        if three in ("'''", '"""'):
            out.append(code[i:si])          # 'r' 或 ''
            quote = three
            end = code.find(quote, si + 3)
            if end == -1:
                end = n
            out.append(code[si:end + 3])
            i = end + 3
            continue
        one = code[si:si + 1]
        if one in ("'", '"'):
            out.append(code[i:si])
            quote = one
            j = si
            while j < n:
                if code[j] == "\\":
                    out.append(code[j:j + 2])
                    j += 2
                    continue
                if code[j] == quote:
                    out.append(quote)
                    j += 1
                    break
                out.append(code[j])
                j += 1
            i = j
            continue
        two = code[i:i + 2]
        if two == "//":
            nl = code.find("\n", i)
            if nl == -1:
                i = n
            else:
                out.append("\n")
                i = nl + 1
            continue
        if two == "/*":
            in_block = True
            i += 2
            continue
        out.append(code[i])
        i += 1
    return "".join(out)


def collect_source():
    """收集 lib/ 下所有 .dart 源码（排除 test），剥离全部注释（含中/英），
    返回 (纯代码行列表, 文件数, 原始非空行数)。"""
    root = os.path.join(REPO, "lib")
    files = []
    for base, dirs, fnames in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("test", "tests", "build") and not d.startswith(".")]
        for fn in fnames:
            if fn.endswith(".dart"):
                files.append(os.path.join(base, fn))
    files.sort()
    lines = []
    raw_count = 0
    for fp in files:
        try:
            with open(fp, "r", encoding="utf-8", errors="ignore") as fh:
                content = fh.read()
        except Exception:
            continue
        raw_count += sum(1 for ln in content.split("\n") if ln.strip() != "")
        content = strip_dart_comments(content)
        for ln in content.split("\n"):
            s = ln.rstrip("\n")
            lines.append(s if s.strip() != "" else "")
    return lines, len(files), raw_count


def build_source_code():
    all_lines, nfiles, raw_count = collect_source()
    # 仅统计非空行（与软著口径一致）；字段“代码行数”用仓库原始非空行数（含注释，反映真实规模）
    non_empty = [ln for ln in all_lines if ln.strip() != ""]
    C["code_lines"] = raw_count

    per_page = 50
    pages = [non_empty[i:i + per_page] for i in range(0, len(non_empty), per_page)]
    total = len(pages)
    front = pages[:30]
    back = pages[-30:] if total > 30 else []

    doc = Document()
    style_doc(doc)
    sec = doc.sections[0]
    sec.top_margin = Inches(0.8); sec.bottom_margin = Inches(0.8)
    sec.left_margin = Inches(0.8); sec.right_margin = Inches(0.8)
    add_header(sec, f"{C['full_name']} {C['version']}")
    add_page_number_footer(sec)

    def emit_page(plines, page_no):
        p = doc.add_paragraph()
        # 关键：固定行距，避免中文注释使行高超过一页导致渲染溢出（曾误成 120 页）
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = Pt(10)
        r = p.add_run("\n".join(plines))
        r.font.name = "Consolas"
        r.font.size = Pt(9)
        rpr = r._element.get_or_add_rPr()
        rf = rpr.find(qn('w:rFonts'))
        if rf is None:
            rf = OxmlElement('w:rFonts'); rpr.append(rf)
        rf.set(qn('w:ascii'), "Consolas"); rf.set(qn('w:hAnsi'), "Consolas")
        rf.set(qn('w:eastAsia'), "宋体")
        doc.add_page_break()

    # 前30页
    add_title(doc, f"{C['full_name']} {C['version']}", size=14, space_after=4)
    add_title(doc, "源代码鉴别材料（前30页，每页50行）", size=12, bold=False, space_after=10)
    no = 1
    for pg in front:
        emit_page(pg, no); no += 1

    # 分隔提示
    sp = doc.add_paragraph()
    sp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    rr = sp.add_run("（以下为后30页源代码，每页50行）")
    rr.bold = True; rr.font.size = Pt(11); set_eastasia(rr, "黑体")
    doc.add_page_break()

    for pg in back:
        emit_page(pg, no); no += 1

    path = os.path.join(OUT, f"源代码鉴别材料_{C['short_name']}.docx")
    doc.save(path)
    return path, nfiles, len(non_empty), total


# ----------------------------------------------------------------------------
# 3. 文档鉴别材料（精简版用户手册）
# ----------------------------------------------------------------------------

def build_doc_identification():
    doc = Document()
    style_doc(doc)
    sec = doc.sections[0]
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "文档鉴别材料")
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)
    add_toc_placeholder(doc)

    add_heading(doc, "第1章 软件概述", 1)
    add_para(doc, "向日葵专注(SunFocus)是一款面向小学阶段儿童的专注力与学习习惯养成工具，"
                  "采用 Flutter 框架开发的跨平台（Android / iOS）单机应用。软件以“阳光养成植物”为隐喻，"
                  "帮助孩子在低打扰环境下建立专注习惯，并为家长提供专注报告与家庭奖励体系。")
    add_heading(doc, "第2章 运行环境", 1)
    add_bullet(doc, f"硬件环境：{C['hw_run']}")
    add_bullet(doc, f"软件环境：{C['software_env']}")
    add_bullet(doc, f"运行平台：{C['os']}")
    add_heading(doc, "第3章 主要功能与界面", 1)
    add_para(doc, "软件主要功能分为孩子端与家长端两大部分：")
    add_bullet(doc, "孩子端：今日状态卡、专注入口（横屏打盹屏）、学习成长卡打卡、植物园与阳光商店、我的（徽章/设置/家长天地）。")
    add_bullet(doc, "家长端：今日概览、夸夸台、专注报告、任务配置、奖励配置与核销、各类设置、删除入口。")
    add_image_placeholder(doc, "孩子端首页界面", images=["孩子端截图/今日首页.png"])
    add_image_placeholder(doc, "横屏专注（打盹屏）界面", images=["孩子端截图/专注界面.jpg"])
    add_image_placeholder(doc, "家长端今日/核销界面", images=["家长端截图/家长今日审核页.png"])
    add_heading(doc, "第4章 典型操作流程", 1)
    add_para(doc, "1）孩子在首页选择专注时长，横放设备进入专注页；2）打盹屏呈现低亮状态表，专注结束自动结算并发放阳光；"
                  "3）孩子到植物园养护植物、到商店发起奖励兑换；4）家长端收到核销请求，现实兑现后确认，阳光扣除。")
    add_image_placeholder(doc, "专注-结算-养护-兑换流程",
                          images=["孩子端截图/专注结束.jpg", "孩子端截图/花园.jpg", "孩子端截图/商店页.png"])
    add_heading(doc, "第5章 数据安全", 1)
    add_para(doc, "软件为纯本地单机应用，专注与成长记录仅本机存储、不上传；支持一键删除与到期自清，"
                  "敏感字段本地加密存储。")

    path = os.path.join(OUT, f"文档鉴别材料_{C['short_name']}.docx")
    doc.save(path)
    return path


# ----------------------------------------------------------------------------
# 4. 软著申请表
# ----------------------------------------------------------------------------

def build_application_form():
    doc = Document()
    style_doc(doc)
    sec = doc.sections[0]
    add_header(sec, f"{C['full_name']} {C['version']}")
    add_page_number_footer(sec)

    add_title(doc, "计算机软件著作权登记申请表", size=18, space_after=20)
    rows = [
        ("著作权人", C["right_holder"]),
        ("著作权人类型", C["right_type"]),
        ("软件名称", C["full_name"]),
        ("软件简称", C["short_name"]),
        ("版本号", C["version"]),
        ("软件分类", C["classification"]),
        ("开发目的", C["purpose"]),
        ("面向领域和行业", C["domain"]),
        ("技术特点", C["tech_features"]),
        ("开发语言", C["language"]),
        ("运行支撑环境/支持软件", C["software_env"]),
        ("运行平台/操作系统", C["os"]),
        ("软件开发环境/开发工具", C["dev_env"]),
        ("运行的硬件环境", C["hw_run"]),
        ("开发的硬件环境", C["hw_dev"]),
        ("开发该软件的操作系统", C["dev_os"]),
        ("权利取得方式", C["acquisition"]),
        ("权利范围", C["right_scope"]),
        ("发表状态", C["publish_status"]),
        ("开发完成日期", C["dev_complete"]),
        ("首次发表日期", C["first_publish"]),
        ("代码行数（实际统计）", str(C["code_lines"]) + " 行（不含测试）"),
    ]
    table = doc.add_table(rows=0, cols=2)
    table.style = "Table Grid"
    for k, v in rows:
        cells = table.add_row().cells
        rk = cells[0].paragraphs[0].add_run(k)
        rk.bold = True; rk.font.size = Pt(11); set_eastasia(rk, "黑体")
        cells[0].width = Inches(2.2)
        rv = cells[1].paragraphs[0].add_run(v)
        rv.font.size = Pt(11); set_eastasia(rv, "宋体")
        cells[1].width = Inches(4.3)

    # 功能描述（≥500 字）
    add_heading(doc, "软件主要功能（功能描述）", 1)
    func = (
        "向日葵专注(SunFocus)是一款面向小学阶段儿童的专注力与学习习惯养成软件，主要功能如下："
        "（1）专注模式：孩子横放设备进入横屏“打盹屏”专注页，屏幕以低亮、慢频、零突事件的状态表呈现，"
        "顶部保留倒计时，中央显示呼吸式明暗的向日葵，每完成 1/2 进度向外送出一粒光（半程触发 1 次），全程无操作区、不抢注意力；"
        "到时自动结算并发放阳光。（2）端上专注度检测：于设备本地通过灭屏、竖屏、长时间无触摸交互判定疑似离席，"
        "离席期间产出暂停且不扣减已有产出，恢复后在场窗口起算 10 秒内线性回到满速，全程零影像上传。"
        "（3）学习打卡：提供内置任务模板，家长可配置并设定每周重复，开启关联专注的任务须有≥15 分钟专注记录方可打卡，"
        "“专注+打卡”同日达成触发完美学习日加成，成就徽章采用累计制避免挫败。"
        "（4）阳光经济：专注 1 分钟 = 1 阳光、任务打卡获固定阳光，设年段日上限（低年段 60 / 中年级 90 / 高年级 120 分钟）与有效值算法，阳光不可充值交易，"
        "切断游戏内购属性。（5）植物养成：以阳光养护心流花园中的多种植物，分多阶段成长，可浇水施肥加速，"
        "植物不因病差而死，长期未养护可救回或死亡返还。（6）阳光商店与家庭奖励：孩子发起兑换申请，"
        "家长端手动核销，设免确认双条件与月度预算池，超额进入排队下月放行。（7）家长端：以本地 PIN 锁进入，"
        "提供今日概览、夸夸台、专注报告、任务/奖励配置与核销、防沉迷与年龄档设置、删除入口等。"
        "（8）防沉迷与防作弊：按年龄分档设每日专注与 App 使用时长上限、夜间边界统一收口，连续专注后强制休息；"
        "以本地检测结合家长裁决降低作弊价值。软件为纯本地单机应用，数据仅本机加密存储、不上传，支持一键删除与到期自清。"
    )
    add_para(doc, func, size=11)

    path = os.path.join(OUT, f"软著申请表_{C['short_name']}.docx")
    doc.save(path)
    return path


# ----------------------------------------------------------------------------
# 5. 产品使用手册
# ----------------------------------------------------------------------------

def build_user_manual():
    doc = Document()
    style_doc(doc)
    sec = doc.sections[0]
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "产品使用手册")
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)
    add_toc_placeholder(doc)

    add_heading(doc, "第1章 产品概述", 1)
    add_para(doc, "向日葵专注(SunFocus)是一款帮助小学阶段孩子建立专注与学习习惯的陪伴型工具。"
                  "孩子通过专注积累阳光、养护植物、兑换家庭奖励；家长可查看专注报告并兑现奖励。")
    add_heading(doc, "第2章 运行环境", 1)
    add_bullet(doc, f"硬件环境：{C['hw_run']}")
    add_bullet(doc, f"软件环境：{C['software_env']}")
    add_heading(doc, "第3章 安装与启动", 1)
    add_para(doc, "1）在 Android（8.0 及以上）或 iOS（12.0 及以上）设备安装本软件；2）首次启动阅读并勾选监护人同意（含拒绝选项）；"
                  "3）按引导设置专注时长档位与基础偏好，即可进入主界面。")
    add_heading(doc, "第4章 快速入门（孩子端专注）", 1)
    add_para(doc, "1）首页点击“专注”选择时长；2）横放设备自动进入打盹屏；3）专注期间屏幕低亮、向日葵呼吸式明暗，"
                  "每 1/2 进度送出一粒光（半程 1 次）；4）到时自动结算，阳光入账并返回主界面。")
    add_image_placeholder(doc, "专注入口与横屏打盹屏",
                          images=["孩子端截图/今日首页.png", "孩子端截图/专注界面.jpg"])
    add_heading(doc, "第5章 功能操作说明", 1)
    add_heading(doc, "5.1 学习成长卡", 2)
    add_para(doc, "在“成长”页（孩子端今日成长卡）查看今日待完成项，完成后点击完成打卡；关联专注的成长卡须先完成一次有效专注。")
    add_image_placeholder(doc, "孩子端成长页（学习成长卡）", images=["孩子端截图/成长页.png"])
    add_heading(doc, "5.2 植物园与养护", 2)
    add_para(doc, "在“花园”页查看植物状态，用阳光种植新植物、浇水/施肥加速成长；植物长期未养护会枯萎，可低成本救回。")
    add_image_placeholder(doc, "植物园界面", images=["孩子端截图/花园.jpg"])
    add_heading(doc, "5.3 阳光商店兑换", 2)
    add_para(doc, "在商店选择奖励发起兑换申请，家长端确认核销后阳光扣除；额度不足时显示排队位次。")
    add_image_placeholder(doc, "阳光商店界面", images=["孩子端截图/商店页.png"])
    add_heading(doc, "5.4 家长端", 2)
    add_para(doc, "首页进入“家长天地”，输入本地 PIN 进入；在今日/报告/夸夸台/任务/奖励/设置各页完成配置与核销。")
    add_image_placeholder(doc, "家长端 PIN 与今日页",
                          images=["家长端截图/家长PIN页.png", "家长端截图/家长今日审核页.png"])
    add_heading(doc, "第6章 常见问题", 1)
    add_bullet(doc, "Q：专注中途竖屏会怎样？A：竖屏即暂停并弹出确认，保留本次进度。")
    add_bullet(doc, "Q：数据会上传吗？A：不会。所有专注与成长记录仅本机存储，不上传任何服务器。")
    add_bullet(doc, "Q：如何删除数据？A：家长端删除入口可一键删除账户内全部数据。")
    add_heading(doc, "第7章 技术支持", 1)
    add_para(doc, "本软件由个人开发者维护；如需支持，请通过应用内反馈入口联系。软件为纯本地单机应用，"
                  "无需联网即可正常使用全部核心功能。")

    path = os.path.join(OUT, f"产品使用手册_{C['short_name']}.docx")
    doc.save(path)
    return path


# ----------------------------------------------------------------------------
def main():
    os.makedirs(OUT, exist_ok=True)
    res = []
    res.append(build_design_spec())
    src_path, nfiles, nlines, npages = build_source_code()
    res.append(src_path)
    res.append(build_doc_identification())
    res.append(build_application_form())
    res.append(build_user_manual())
    print("=== 生成完成 ===")
    print(f"源文件数: {nfiles}, 非空代码行: {nlines}, 分页总数: {npages}（提交前30+后30页）")
    for p in res:
        print(" -", p)


if __name__ == "__main__":
    main()
