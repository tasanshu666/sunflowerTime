#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
小小葵番茄钟少儿专注力养成软件 V1.0 —— 软著登记材料生成器

⚠️ 2026-11-10 改名修正：软件全称/简称由「向日葵专注(SunFocus)」改为「小小葵番茄钟」。
   依据：改名批 `4bc9cfb`（2026-10-23）已把 App 全线改名为「小小葵番茄钟 / Tiny Sunflower」
   （iOS zh-Hans CFBundleDisplayName、values-zh/strings.xml、ARB app_title 均为新名），
   本脚本此前仍用改名前旧名，会导致「材料名称 ≠ 安装包显示名」被商店审核驳回。
   命名规则依据（2026-03-15 新版申请表）：品牌 + 用途 + 功能 + 后缀；8–20 字；不可纯英文；
   简称不得与全称相同；所有申请材料中的软件全称必须一字不差一致。

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
from docx.shared import Pt, RGBColor, Inches, Mm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

# ----------------------------------------------------------------------------
# 配置（软著登记关键信息；★ 标注项需由权利人确认/替换）
# ----------------------------------------------------------------------------
C = {
    # ★ 名称口径（2026-11-10 改名修正）：以 App 实际显示名为准
    #   中文显示名 = 小小葵番茄钟（iOS zh-Hans / Android values-zh / ARB app_title）
    #   英文显示名 = Tiny Sunflower（iOS en / Android values）
    #   全称取纯中文，规避「中英混排 >30 字符」与「英文缩写需另附说明」两项补正风险
    "full_name": "小小葵番茄钟少儿专注力养成软件",         # 软件全称（证书印名，14 字）
    "short_name": "小小葵番茄钟",                            # 软件简称（＝商店上架名，≠全称）
    "name_en": "Tiny Sunflower",                             # 英文显示名（备案/商店后台填此）
    "version": "V1.0",
    "right_holder": "遵化市云程智服软件技术服务部",          # ★ 个体工商户执照名称全称（非经营者姓名）
    "right_type": "企业",                                    # 个体工商户在版权中心归入企业类目
    "publish_status": "未发表",                              # 未发表 / 已发表
    "acquisition": "原始取得",                               # 原始取得 / 受让取得
    "right_scope": "全部权利",                               # 全部权利 / 部分权利
    "dev_complete": "2026-11-10",  # ★ 开发完成日期（须 ≥ 源码最后修改日）
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


def set_a4(section):
    """软著要求 A4 纵向单面打印。python-docx 默认是 Letter，必须显式改。"""
    section.page_width = Mm(210)
    section.page_height = Mm(297)


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
    set_a4(sec)
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "软件设计说明书")

    # 正文分节
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    set_a4(body)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)

    add_toc_placeholder(doc)

    # 第1章 概述
    add_heading(doc, "第1章 概述", 1)
    add_heading(doc, "1.1 项目背景", 2)
    add_para(doc, "小小葵番茄钟（英文名 Tiny Sunflower）是一款面向小学阶段（6–12 岁）儿童的专注力与学习习惯养成工具。"
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
    add_image_placeholder(doc, "成长卡与孩子申请状态",
                          images=["孩子端截图/成长页.png", "孩子端截图/成长页-孩子申请状态.png"])
    add_para(doc, "任务配置页除增删改外，还支持设定每周重复规则（指定星期几）与「是否必须先完成专注」的开关。"
                  "开启关联专注的任务在孩子提交前须校验当日有效专注记录是否满足门槛，不满足时不允许提交；"
                  "驳回须填写原因，原因文本回传至孩子的成长卡，形成可回看的反馈闭环。")
    add_image_placeholder(doc, "家长端任务编辑页",
                          images=["家长端截图/成长（任务）编辑页.png"])
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
                  "本版本起兑换一律由家长显式核销，不设自动放行条件——"
                  "免确认双条件（单笔阈值与月度/周度预算池比例）已整体移除，"
                  "以避免奖励在家长未兑现的情况下被自动扣除，从机制上保证「孩子拿到的必然是真实兑现过的奖励」。"
                  "家长设周阳光预算池额度，低年级默认每周 300 阳光、中年级默认每周 600 阳光，"
                  "高年级默认不设上限（此时兑换只受阳光余额约束）。"
                  "预算已满时超额申请不拒绝，改显示「排队中」于下期放行，并提供冷却期状态化表达与强制替代推荐。")
    add_image_placeholder(doc, "商店兑换与核销流程图",
                          images=["孩子端截图/商店页.png", "家长端截图/家长今日审核页.png"])
    add_heading(doc, "3.7 家长端", 2)
    add_para(doc, "以本地 PIN 锁进入的独立页面，功能含：今日概览、夸夸台（向日葵转述表扬）、专注报告、"
                  "任务配置、奖励配置与核销、专注/防沉迷/年龄档设置、阳光赠予、账号找回与删除入口。"
                  "家长端与孩子端在同一应用内但为完全独立的导航栈，进入后孩子无法通过返回手势回到孩子端。")
    add_image_placeholder(doc, "家长端入口（PIN 锁）与今日概览",
                          images=["家长端截图/家长PIN页.png", "家长端截图/家长今日审核页.png"])
    add_para(doc, "家长端今日概览汇总当日已完成的专注时长、阳光产出、成长卡完成情况与待核销兑换申请，"
                  "并提供各设置项的快捷入口；顶部显示孩子当日的年龄档位与剩余专注额度。"
                  "家长在待审核队列中可逐条处理成长卡与兑换申请，驳回成长卡时须填写原因，该原因回传至孩子端形成反馈闭环。")
    add_image_placeholder(doc, "家长端今日审核队列与奖励编辑",
                          images=["家长端截图/今日带审核页.jpg", "家长端截图/奖励编辑页.jpg"])
    add_para(doc, "专注报告按日、周、月三个维度展示专注时长、有效专注占比、离席次数与时段分布，"
                  "并列出每段专注会话的起止时间与产出。报告数据全部来自本机记录，不含任何影像或音视频内容。")
    add_image_placeholder(doc, "专注报告与历史记录",
                          images=["家长端截图/专注报告.jpg", "家长端截图/成长、奖励历史记录页.jpg"])
    add_para(doc, "家长端设置页包含专注时长档位、每日专注与 App 使用时长上限、可用时段与夜间边界、"
                  "年龄档位、护眼提醒与界面语言切换等选项，并提供阳光赠予、账号找回与「删除全部数据」入口。"
                  "删除入口会一次性清除本机全部专注、成长、奖励与设置数据，操作前需二次确认。")
    add_image_placeholder(doc, "家长端设置页",
                          images=["家长端截图/设置01.jpg", "家长端截图/设置02.jpg"])
    add_heading(doc, "3.8 防沉迷与防作弊", 2)
    add_para(doc, "防沉迷：每日专注总时长上限按年龄分档、每日 App 总使用时长上限、可用时段与夜间边界统一收口于单一参数；"
                  "连续专注后强制休息。防作弊：承认单设备无法 100% 判定“真专注”，以本地检测+家长裁决为主，"
                  "靠“产出与真实学习成果脱钩”（奖励需家长核销）稀释作弊价值，文案保持善意。")

    # 第4章 关键算法与数据口径
    add_heading(doc, "第4章 关键算法与数据口径", 1)
    add_heading(doc, "4.1 有效专注口径", 2)
    add_para(doc, "软件存在两个含义不同但易被混淆的时长口径，实现上以独立常量承载、互不引用。"
                  "其一是单次有效专注门槛：一次专注会话实际专注时长不足 5 分钟记为中断，不产生任何产出。"
                  "其二是有效专注日：当日累计专注时长达到 15 分钟即计为一个有效专注日，"
                  "该口径是产品的核心衡量指标，成长页展示、成就徽章与家长端报告均以此为准。"
                  "两者不共用同一常量，也不允许出现相���字面量，避免口径漂移。")
    add_heading(doc, "4.2 每日额度三处收口", 2)
    add_para(doc, "每日专注上限若仅在开始专注时判断一次，会留下绕过漏洞——"
                  "例如今日尚未专注时选择一个远超上限的自定义时长，即可单场冲过上限。"
                  "因此上限在三个位置同时收口：一是选时长阶段，超出今日剩余额度的档位置灰且自定义输入上限跟随收窄；"
                  "二是开始前，剩余不足 1 分钟直接拦截，否则将本次时长截断到剩余额度；"
                  "三是结算阶段，由账本当日净额做硬截断，作为真正的兜底。")
    add_para(doc, "额度的单点真源是账本中专注来源条目的当日净额，而不是当日各次会话实际时长之和。"
                  "原因是当某场专注被额度截断时，会话仍记录真实时长，直接累加会话时长会把已用额度算多，"
                  "导致后续档位被过早置灰。")
    add_heading(doc, "4.3 完成率与成长结算", 2)
    add_para(doc, "完成率定义为实际专注时长与设定时长之比，判定阈值为 0.90。"
                  "成长卡的结算按专注时长比例折算，而非一律全额发放，"
                  "以保证孩子只有真正投入相应时长才能获得对应产出；"
                  "但家长核销的非联动类手动打卡则按全额口径结算，因为该类打卡不存在专注时长比例的概念。")
    add_heading(doc, "4.4 护眼休息的计时口径", 2)
    add_para(doc, "护眼提醒触发时，专注引擎进入暂停态，专注时长与阳光产出均不累计。"
                  "无论孩子完成休息还是确认跳过，护眼时长都不回溯补算为专注时长，"
                  "也不折算为任何阳光；休息结束后专注计时从零重新累计下一个间隔。"
                  "这一设计避免了「跳过护眼反而获得更多产出」的激励扭曲。")
    add_heading(doc, "4.5 成长阶段与养护", 2)
    add_para(doc, "植物成长分种子、发芽、幼苗、含苞、盛开五个阶段。"
                  "普通档物种每阶段需 240 小时，完全不养护约 30 天可长成；"
                  "精英档物种每阶段需 480 小时，完全不养护约 60 天可长成。"
                  "浇水与施肥均受每日次数额度约束，额度按账户状态计算，二者取较小值同时生效；"
                  "额度用尽时按钮呈禁用态。植物绝不因专注不足而死亡，仅在长期完全未养护时进入枯萎态，"
                  "且枯萎后保留低成本救回路径。")
    add_heading(doc, "4.6 参数单点原则", 2)
    add_para(doc, "所有可调数值常量集中于单一参数文件，每条均注明对应的需求节号，"
                  "任何其他位置出现同义字面量即视为缺陷。"
                  "年龄分档参数亦独立成文件，包含档位区间、分档系数、周预算默认值与每日专注上限，"
                  "业务代码一律查表，禁止在调用处内联条件表达式。"
                  "该原则保证了同一数值在多处使用时的一致性，也是后续调整产品参数只需改动单点的前提。")

    # 第5章 技术栈
    add_heading(doc, "第5章 技术栈与运行环境", 1)
    add_bullet(doc, "开发语言：Dart（Flutter 框架），少量 Kotlin/Swift 平台桥接代码。")
    add_bullet(doc, f"运行平台：{C['os']}")
    add_bullet(doc, "状态管理：Riverpod 2.x。")
    add_bullet(doc, "本地存储：Drift（SQLite）+ SQLCipher 加密；设置 KV 用 shared_preferences；PIN 用 flutter_secure_storage。")
    add_bullet(doc, "动画：Flutter 原生 CustomPainter（打盹屏轻量绘制）。")
    add_bullet(doc, "音频：just_audio（预录台词）+ flutter_tts（备选）。")
    add_bullet(doc, "常亮/方向：wakelock_plus、native_device_orientation。")
    add_bullet(doc, "路由/不可变/时间：go_router、freezed、intl。")

    # 第5章 数据安全与合规
    add_heading(doc, "第6章 数据模型与交互流程", 1)
    add_heading(doc, "6.1 主要数据实体", 2)
    add_para(doc, "领域层以实体描述业务概念，各实体不依赖任何持久化或界面框架，可独立进行单元测试。"
                  "专注会话实体记录设定时长、实际专注时长、离席次数、暂停与恢复时刻及本次产出；"
                  "阳光账本实体以流水形式记录每一笔产出与消耗，条目带有来源类型标记，"
                  "其中专注来源的当日净额即为每日额度计算的单点真源；"
                  "植物实体记录物种标识、种植时刻、当前成长阶段、累计养护次数与产出记录；"
                  "任务实体记录任务模板、每周重复规则、是否要求关联专注、结算比例与审核状态；"
                  "奖励实体记录奖励名称、类别、代价、库存与核销状态；"
                  "家长配置实体集中承载年龄档位、每日上限、可用时段、周预算池与界面语言等设置项。")
    add_heading(doc, "6.2 专注会话状态机", 2)
    add_para(doc, "专注会话的状态流转为：待开始 → 运行 → 暂停 → 运行 → 已完成，"
                  "并在任意时刻可因超时进入已结算。状态机约束三条规则："
                  "其一，仅运行态累计专注时长与产出，暂停态冻结计时；"
                  "其二，离席判定仅改变状态与速率，不回溯扣减已累积的产出；"
                  "其三，护眼提醒期间强制进入暂停态，其时长不回溯补算为专注时长。"
                  "结算由引擎在到时、家长提前结束或额度截断三种触发路径下统一执行，"
                  "保证任何路径下的产出计算口径一致。")
    add_heading(doc, "6.3 成长卡审核流程", 2)
    add_para(doc, "成长卡的生命周期为：待完成 → 待审核 → 已通过或已驳回。"
                  "孩子提交后进入待审核队列，由家长在今日页逐条处理。"
                  "关联专注的任务在提交前须校验当日有效专注记录是否满足门槛，"
                  "不满足时不允许提交；驳回须填写原因，原因文本回传至孩子的成长卡形成反馈闭环。"
                  "审核通过后阳光即时入账并写入账本，同一笔打卡不重复入账。")
    add_heading(doc, "6.4 兑换核销流程", 2)
    add_para(doc, "兑换的生命周期为：已提交 → 已核销或已排队。"
                  "孩子提交时校验阳光余额与周预算池额度；"
                  "预算池额度充足时进入待核销队列，不充足时置为已排队并保留申请顺序；"
                  "家长在现实兑现后执行核销，核销瞬间扣除阳光并关闭申请。"
                  "整个流程不存在自动放行分支，保证扣除必然对应一次真实兑现。")
    add_heading(doc, "6.5 界面与领域层的交互约定", 2)
    add_para(doc, "表现层通过状态管理读取领域服务的结果并渲染，不直接访问数据库；"
                  "所有涉及余额与额度的写操作必须经由领域层的编排服务，"
                  "以保证校验、入账与流水写入在同一事务边界内完成；"
                  "表现层不得自行计算任何金额或额度，避免出现界面显示与账本实际不一致的情形。")

    add_heading(doc, "第7章 数据安全与合规设计", 1)
    add_para(doc, "软件采用 Plan B 纯本地单机形态：无账号、无家庭组、无云同步、无网络传输，"
                  "本地基础义务做足。")
    add_bullet(doc, "本地隐私与处理说明：明确收集范围为本地专注状态与成长记录。")
    add_bullet(doc, "监护人本地告知同意，含拒绝选项。")
    add_bullet(doc, "删除权：提供删除入口、响应时限与删除范围（账户内数据+行为记录）；毕业时先导出成册再清空账户。")
    add_bullet(doc, "最短必要期限 + 到期自清。")
    add_bullet(doc, "本地加密存储敏感字段（SQLCipher）。")
    add_bullet(doc, "对外如实表述收集范围，不使用“不拍摄/不存储/不上传任何影像”等绝对化承诺。")

    # 第8章 增量模块设计
    add_heading(doc, "第8章 增量模块设计", 1)
    add_para(doc, "本章说明在核心版本之后新增的模块：花园天气系统、植物图鉴扩充、向日葵守卫者玩法与多语言支持。"
                  "各模块均沿用第2章的分层约定，领域层不依赖 UI 框架。")
    add_heading(doc, "8.1 花园天气系统", 2)
    add_para(doc, "天气系统按「日型 → 成长修正 → 展示层」三段解耦设计。日型由领域层的枚举描述，"
                  "包括晴天、阴天、小雨、暴雨、大风、降雪、极寒等取值；成长修正由独立的天气权重表描述，"
                  "以月份为第一维、日型为第二维，给出该月该日型出现的相对可能性。")
    add_para(doc, "季节约束方面，干旱型天气只在 5 至 9 月参与权重计算，其余月份不触发；"
                  "系统在实现上对权重做年度口径归一化，使得断年度名义权重加权结果为 1，"
                  "而逐月加权值允许略高于或低于 1，作为可接受的季节特征保留，不做额外修正。")
    add_para(doc, "展示层与领域层之间通过独立的展示服务对接：领域层只产出「当日日型」这一结论，"
                  "由展示层决定在花园场景中叠加何种动效（雨丝、雨滴、雪花等）以及在任务确认环节展示何种提示文案。")
    add_para(doc, "动效实现需保证循环动画的时间连续性：主循环时长取 12 分钟，每颗粒子的循环次数由速度参数取整得到，"
                  "确保动画首尾帧相位一致，避免控制器每次归零造成的视觉跳变；"
                  "动效层的绘制范围必须覆盖完整可见区域，避免粒子在可见区边界被裁切。")
    add_heading(doc, "8.2 植物图鉴扩充", 2)
    add_para(doc, "植物物种以种子数据形式内置于数据层，首��启动即写入本地库。当前共 10 种，"
                  "稀有度在界面上仅呈现「普通 / 精英」两档：普通档包括向日葵、番茄、草莓、玫瑰、蓝莓，"
                  "精英档包括月光兰、珊瑚岭兰、翡翠绣球、葡萄、荷花。")
    add_para(doc, "计价规则为按物种计价：向日葵作为初始物种免费；普通档可选 300 阳光或 10 碎片二选一；"
                  "精英档仅支持 20 碎片。价格仅在种下时扣除，已种植植物与铲除返还不受影响。"
                  "精英档植物每阶段成长时长为 480 小时，普通档为 240 小时。")
    add_para(doc, "物种名称是落库基线，不随界面语言切换而改写，以避免同一物种出现两个名字；"
                  "上屏名称统一经物种本地化解析，以物种标识为键查表，未知标识回退到基线名称。")
    add_heading(doc, "8.3 向日葵守卫者", 2)
    add_para(doc, "守卫者是位于今日页顶部的可选轻量回合制玩法。领域层实现战斗结算数学，"
                  "涉及每日券的获取与消耗、结算结果与奖励产出；展示层负责胶囊入口、战斗界面与结算卡片的表现。"
                  "该模块与专注会话、成长卡记录完全解耦，不写入专注产出，不影响阳光经济的产出规则。")
    add_heading(doc, "8.4 多语言支持", 2)
    add_para(doc, "多语言采用 ARB 资源文件加代码生成的方式，键名在各语言间严格一致，"
                  "缺失键回退到中文基准。切换语言在运行时即时生效，覆盖孩子端与家长端全部文案。"
                  "落库型基线数据（物种名称、任务模板名、奖励模板名）不参与翻译，以保证数据唯一性与历史一致性。")
    add_heading(doc, "8.5 权益刷新与即时生效", 2)
    add_para(doc, "家长端完成一次性买断后，权益状态需要立即反映到孩子端界面。"
                  "实现上由权益状态提供单一数据源，并在应用生命周期恢复时重新读取，"
                  "确保从后台切回后扩容入口与相关标识立即出现或消失，无需重启应用。")

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
    set_a4(sec)
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
    set_a4(sec)
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "文档鉴别材料")
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    set_a4(body)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)
    add_toc_placeholder(doc)

    add_heading(doc, "第1章 软件概述", 1)
    add_para(doc, "小小葵番茄钟（英文名 Tiny Sunflower）是一款面向小学阶段儿童的专注力与学习习惯养成工具，"
                  "采用 Flutter 框架开发的跨平台（Android / iOS）单机应用。软件以“阳光养成植物”为隐喻，"
                  "帮助孩子在低打扰环境下建立专注习惯，并为家长提供专注报告与家庭奖励体系。"
                  "产品以“阳光养成植物”为教育隐喻：孩子通过专注积累阳光，用阳光养护心流花园、"
                  "兑换由家长真实兑现的家庭奖励，从而形成可回看、低挫败的专注习惯。"
                  "产品定位为“教育工具 / 习惯养成工具”，而非游戏。")
    add_para(doc, "设计目标围绕四点：其一，低打扰——专注中屏幕只做“可瞟不可盯”的状态表，不抢注意力；"
                  "其二，损失可挽回——任何惩罚都留有补救路径，避免孩子挫败弃用；"
                  "其三，隐私优先——专注状态本地处理、数据最小必要，无账号、无云同步、无影像上传；"
                  "其四，家长可参与——提供专注报告与可兑现的家庭奖励体系，降低家长维护成本。")
    add_heading(doc, "第2章 运行环境", 1)
    add_bullet(doc, f"硬件环境：{C['hw_run']}")
    add_bullet(doc, f"软件环境：{C['software_env']}")
    add_bullet(doc, f"运行平台：{C['os']}")
    add_heading(doc, "第3章 主要功能与界面", 1)
    add_para(doc, "软件主要功能分为孩子端与家长端两大部分。孩子端面向 6 至 12 岁儿童，"
                  "以「今日状态卡—专注—成长卡—花园—商店」为主线；家长端以本地 PIN 进入，"
                  "承担配置、核销与查看三类操作。")
    add_bullet(doc, "孩子端：今日状态卡、专注入口（横屏打盹屏）、学习成长卡打卡、植物园与阳光商店、我的（徽章/设置/家长天地）。")
    add_bullet(doc, "家长端：今日概览、夸夸台、专注报告、任务配置、奖励配置与核销、各类设置、删除入口。")
    add_image_placeholder(doc, "孩子端首页界面", images=["孩子端截图/今日首页.png"])
    add_image_placeholder(doc, "横屏专注（打盹屏）界面", images=["孩子端截图/专注界面.jpg"])
    add_image_placeholder(doc, "家长端今日/核销界面", images=["家长端截图/家长今日审核页.png"])
    add_heading(doc, "第4章 典型操作流程", 1)
    add_para(doc, "1）孩子在首页选择专注时长，横放设备进入专注页；2）打盹屏呈现低亮状态表，专注结束自动结算并发放阳光；"
                  "3）孩子到植物园养护植物、到商店发起奖励兑换；4）家长端收到核销请求，现实兑现后确认，阳光扣除。"
                  "整条链路的共同前提是：全部数据仅存本机，任何环节都不需要网络连接。")
    add_para(doc, "时长选择页提供三排共 8 个档位：第一排 15、20、25 分钟，第二排 30、45、60 分钟，"
                  "第三排为「自由」与「自定义」。「自由」档不预设时长、不自动结算，由孩子自行决定何时结束，"
                  "但计时照常进行，每日额度与防沉迷约束依然生效；「自定义」档可输入任意分钟数，"
                  "输入上限随今日剩余额度动态收窄。各档位以等宽三排布局呈现，选中态不引起行位重排。")
    add_para(doc, "专注过程中设有护眼休息提醒：到达设定间隔时弹出护眼卡，此时专注计时冻结，"
                  "护眼时长不计入专注时长也不折算为阳光；无论孩子选择完成休息还是确认跳过，护眼时长都不回溯补算。"
                  "专注结束时自动进入结算页，展示本次专注时长、本次产出阳光与当日累计，并播放光粒回归的庆祝动画。")
    add_image_placeholder(doc, "专注界面与专注设置",
                          images=["孩子端截图/专注设置页.png", "孩子端截图/专注中收集阳光过程.jpg"])
    add_image_placeholder(doc, "护眼休息与专注结束",
                          images=["孩子端截图/护眼休息02.jpg", "孩子端截图/专注结束.jpg"])
    add_image_placeholder(doc, "孩子端我的页与阳光来源",
                          images=["孩子端截图/我的页.png", "孩子端截图/阳光来源.png"])
    add_image_placeholder(doc, "家长端专注报告与历史记录",
                          images=["家长端截图/专注报告.jpg", "家长端截图/成长、奖励历史记录页.jpg"])
    add_image_placeholder(doc, "专注-结算-养护-兑换流程",
                          images=["孩子端截图/专注结束.jpg", "孩子端截图/花园.jpg", "孩子端截图/商店页.png"])
    add_heading(doc, "第5章 增量功能说明", 1)
    add_heading(doc, "5.1 花园天气系统", 2)
    add_para(doc, "软件在花园场景内叠加当日天气表现，日型包括晴天、阴天、小雨、暴雨、大风、降雪与极寒等。"
                  "不同日型对植物成长速率产生不同影响：雨天与极寒会降低成长效率，部分天气带来额外加成。"
                  "干旱型天气只在夏季（5 至 9 月）触发，其余月份不参与。"
                  "系统按月份维度对天气权重做归一化处理，使全年整体影响保持在可控范围。"
                  "天气同时会在任务确认环节以卡片形式提示当日日型，家长与孩子都能看到当日环境。")
    add_para(doc, "展示层以循环动画表现天气：雨丝沿竖向缓慢下落，雨滴在玻璃面聚散，雪花横向漂移并带有旋转。"
                  "动效层覆盖完整可见区域，不对粒子做边界裁切，且循环首尾相位一致，视觉上连续无跳变。"
                  "天气动效为纯表现层能力，不参与任何业务判定，关闭动效不影响天气规则本身。")
    add_image_placeholder(doc, "花园界面与植物状态",
                          images=["孩子端截图/花园植物状态信息.jpg", "孩子端截图/花园长草和产物.jpg"])
    add_heading(doc, "5.2 植物图鉴", 2)
    add_para(doc, "当前内置 10 种植物：向日葵、番茄、草莓、玫瑰、蓝莓为普通档；"
                  "月光兰、珊瑚岭兰、翡翠绣球、葡萄、荷花为精英档。"
                  "普通档可用 300 阳光或 10 碎片兑换，精英档需 20 碎片；向日葵作为初始物种免费。"
                  "植物可重复种植，唯一约束为花盆容量；铲除已种植物可返还部分投入。"
                  "普通档每阶段成长 240 小时，精英档每阶段 480 小时。")
    add_image_placeholder(doc, "可种植物列表",
                          images=["孩子端截图/花园可种植物列表.jpg"])
    add_heading(doc, "5.3 向日葵守卫者", 2)
    add_para(doc, "今日页顶部提供守卫者胶囊入口，进入后为轻量回合制玩法。"
                  "孩子可通过每日券参与，战斗胜利获得额外奖励。该玩法为可选激励模块，"
                  "不与专注时长或成长记录绑定，不影响核心习惯养成的产出规则。")
    add_heading(doc, "5.4 多语言", 2)
    add_para(doc, "支持简体中文与英文两种界面语言，切换入口位于家长端设置页，切换后即时全量生效。"
                  "物种名称等落库基线数据不随语言切换改变，以保证历史数据唯一。")
    add_image_placeholder(doc, "家长端设置页（语言切换入口）",
                          images=["家长端截图/设置01.jpg"])
    add_heading(doc, "第6章 关键参数说明", 1)
    add_para(doc, "以下参数集中定义于单一参数文件，所有业务代码统一查表，避免多处出现同义数值。")
    add_bullet(doc, "单次有效专注门槛：一次专注实际时长不足 5 分钟记为中断，不产生阳光产出。")
    add_bullet(doc, "有效专注日：当日累计专注达 15 分钟计为一个有效专注日，为核心衡量指标。")
    add_bullet(doc, "年龄分档与每日专注上限：8 岁及以下 60 分钟、9 至 12 岁 90 分钟、13 岁及以上 120 分钟。")
    add_bullet(doc, "完成率阈值：实际专注时长与设定时长之比达到 0.90 视为完成。")
    add_bullet(doc, "周阳光预算池：低年级默认 300 阳光、中年级默认 600 阳光、高年级默认不设上限。")
    add_bullet(doc, "成长卡结算：联动类任务按专注时长比例折算，非联动类手动打卡按全额结算。")
    add_para(doc, "每日专注上限在三处同时收口：选时长阶段超额度档位置灰并收窄自定义上限；"
                  "开始前剩余不足 1 分钟直接拦截，否则截断本次时长；结算阶段按账本当日净额硬截断兜底。")
    add_heading(doc, "第7章 数据安全", 1)
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
    set_a4(sec)
    add_header(sec, f"{C['full_name']} {C['version']}")
    add_page_number_footer(sec)

    add_title(doc, "计算机软件著作权登记申请表", size=18, space_after=20)
    rows = [
        ("著作权人", C["right_holder"]),
        ("著作权人类型", C["right_type"]),
        ("软件名称", C["full_name"]),
        ("软件简称", C["short_name"]),
        ("英文名称", C["name_en"]),
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

    # 功能描述（官方新版要求 500–1300 字，且须覆盖研发背景/核心架构/功能模块/技术实现/应用场景）
    add_heading(doc, "软件主要功能（功能描述）", 1)
    func = (
        "本软件面向小学阶段（6–12 岁）儿童，是一款以“阳光养成植物”为教育隐喻的专注力与学习习惯养成工具。"
        "研发背景：低龄儿童在专注时容易被高亮动画与即时反馈打断，且单纯的计时器无法形成可回看的习惯记录，"
        "家长也缺少低成本的激励手段；本软件据此以低打扰、可累积、可兑现为设计原点。"
        "核心架构：采用表现层、领域层、数据层分层结构，依赖方向自上而下，领域层不依赖界面框架与数据库框架，"
        "核心层集中所有可调数值常量；本地数据经 Drift 与 SQLCipher 加密存储，领域层仅依赖 Repository 接口，"
        "预留账号与云同步接入点。应用场景：孩子独立使用完成日常专注与养成，家长通过本地 PIN 进入家长端完成配置与核销，"
        "全程无需联网、无需注册账号。"
        "主要功能如下：（1）专注模式：孩子横放设备进入横屏“打盹屏”专注页，屏幕以低亮、慢频、零突事件的状态表呈现，"
        "顶部保留倒计时，中央显示呼吸式明暗的向日葵，每完成 1/2 进度向外送出一粒光（半程触发 1 次），全程无操作区、不抢注意力；"
        "到时自动结算并发放阳光。（2）端上专注度检测：于设备本地通过灭屏、竖屏、长时间无触摸交互判定疑似离席，"
        "离席期间产出暂停且不扣减已有产出，恢复后在场窗口起算 10 秒内线性回到满速，全程零影像上传。"
        "（3）学习打卡：提供内置任务模板，家长可配置并设定每周重复，开启关联专注的任务须有≥15 分钟专注记录方可打卡，"
        "“专注+打卡”同日达成触发完美学习日加成，成就徽章采用累计制避免挫败。"
        "（4）阳光经济：专注 1 分钟 = 1 阳光、任务打卡获固定阳光，设年段日上限（低年段 60 / 中年级 90 / 高年级 120 分钟）与有效值算法，阳光不可充值交易，"
        "切断游戏内购属性。（5）植物养成：内置向日葵、番茄、草莓、玫瑰、蓝莓、月光兰、珊瑚岭兰、翡翠绣球、葡萄、荷花共 10 种植物，"
        "按普通与精英两档计价（普通档 300 阳光或 10 碎片、精英档 20 碎片），分多阶段成长，可浇水施肥加速，"
        "植物不因专注差而死，长期未养护可救回或死亡返还。（6）花园天气系统：按日型（晴、阴、小雨、暴雨、大风、降雪、极寒等）"
        "与月份权重描述当日天气，干旱型仅在 5 至 9 月触发并对全年权重归一化，天气对成长速率的影响在花园内以循环动效与提示卡片呈现。"
        "（7）阳光商店与家庭奖励：孩子发起兑换申请，家长端显式核销（不设自动放行条件），"
        "设周阳光预算池（低年级默认每周 300 / 中年级 600 / 高年级默认不限额），超额进入排队下期放行。"
        "（8）家长端：以本地 PIN 锁进入，提供今日概览、夸夸台、专注报告、任务/奖励配置与核销、防沉迷与年龄档设置、删除入口等。"
        "（9）向日葵守卫者：今日页胶囊入口进入的轻量回合制玩法，作为可选激励模块，不与专注记录绑定。"
        "（10）多语言与权益刷新：支持中英文即时切换；家长端完成买断后权益状态即时生效，无需重启。"
        "（11）防沉迷与防作弊：按年龄分档设每日专注与 App 使用时长上限、夜间边界统一收口，连续专注后强制休息；"
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
    set_a4(sec)
    sec.top_margin = Inches(1.0); sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.0); sec.right_margin = Inches(1.0)
    add_header(sec, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(sec)

    add_cover(doc, "产品使用手册")
    body = doc.add_section(WD_SECTION.NEW_PAGE)
    set_a4(body)
    add_header(body, f"{C['full_name']}用户手册 {C['version']}")
    add_page_number_footer(body)
    add_toc_placeholder(doc)

    add_heading(doc, "第1章 产品概述", 1)
    add_para(doc, "小小葵番茄钟（英文名 Tiny Sunflower）是一款帮助小学阶段孩子建立专注与学习习惯的陪伴型工具。"
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
    add_para(doc, "时长选择页提供三排共 8 个档位：第一排 15、20、25 分钟，第二排 30、45、60 分钟，"
                  "第三排为「自由」与「自定义」。「自由」档不预设时长、不自动结算，由孩子自行决定何时结束，"
                  "但计时照常进行，每日额度与防沉迷约束依然生效；「自定义」档可输入任意分钟数，"
                  "输入上限随今日剩余额度动态收窄。各档位以等宽三排布局呈现，选中态不引起行位重排。")
    add_para(doc, "每日专注上限按年龄档位设置：8 岁及以下每天 60 分钟、9 至 12 岁每天 90 分钟、13 岁及以上每天 120 分钟。"
                  "上限在三处同时收口：选时长时超过今日剩余额度的档位置灰不可选；开始前若剩余不足 1 分钟则直接拦截，"
                  "否则把本次时长截断到剩余额度；结算时再按账本当日净额做一次硬截断兜底，"
                  "确保无法通过分多次专注绕过上限。")
    add_para(doc, "单次专注实际时长不足 5 分钟记为中断，不产生阳光产出；当日累计专注达到 15 分钟计为一个有效专注日，"
                  "该口径是软件的核心衡量指标，成长页与家长端报告均以此为准。")
    add_image_placeholder(doc, "专注入口与横屏打盹屏",
                          images=["孩子端截图/今日首页.png", "孩子端截图/专注界面.jpg"])
    add_para(doc, "专注过程中设有护眼休息提醒：到达设定间隔时弹出护眼卡，此时专注计时冻结，"
                  "护眼时长不计入专注时长也不折算为阳光；无论孩子选择完成休息还是确认跳过，护眼时长都不回溯补算。"
                  "护眼休息结束后，专注从 0 重新累计下一个间隔。")
    add_image_placeholder(doc, "护眼提醒流程与休息界面",
                          images=["孩子端截图/专注转护眼提醒流程.jpg", "孩子端截图/护眼休息01.jpg"])
    add_para(doc, "专注结束时自动进入结算页，展示本次专注时长、本次产出阳光与当日累计，"
                  "并播放光粒回归的庆祝动画。结算页同时是家长核对产出的入口，"
                  "孩子可在同一界面查看累计专注时长、阳光来源明细与已开花植物数量。")
    add_image_placeholder(doc, "专注结算与阳光来源",
                          images=["孩子端截图/专注结束.jpg", "孩子端截图/阳光来源.png"])
    add_heading(doc, "第5章 功能操作说明", 1)
    add_heading(doc, "5.1 学习成长卡", 2)
    add_para(doc, "在“成长”页（孩子端今日成长卡）查看今日待完成项，完成后点击完成打卡；关联专注的成长卡须先完成一次有效专注。"
                  "成长卡分为作业类、阅读类与自定义类，家长可设定每周重复规则（指定星期几），并可要求该项必须先完成一次专注才允许打卡。"
                  "同一天内「完成专注」与「完成成长卡」同时达成，会在成长页顶部出现完美学习日提示，并额外计入当日阳光加成。")
    add_image_placeholder(doc, "孩子端成长页（学习成长卡）", images=["孩子端截图/成长页.png"])
    add_para(doc, "成长卡提交后进入家长端待审核队列，家长在「今日」页逐条确认或驳回。驳回时须填写驳回原因，该原因会显示在孩子的成长卡上，"
                  "用于形成可回看的反馈闭环；审核通过后阳光即时入账并写入专注与成长的历史记录，可在家长端「成长、奖励历史记录」中按时间轴回看。")
    add_image_placeholder(doc, "成长卡提交与家长审核状态",
                          images=["孩子端截图/成长页-孩子申请状态.png", "家长端截图/成长、奖励历史记录页.jpg"])
    add_heading(doc, "5.2 植物园与养护", 2)
    add_para(doc, "在“花园”页查看植物状态，用阳光种植新植物、浇水/施肥加速成长；植物长期未养护会枯萎，可低成本救回。"
                  "花园首页展示全部花盆位，每株植物显示当前成长阶段（种子→发芽→幼苗→含苞→盛开）、剩余成长时长与养护状态；"
                  "点击植物可进入详情，查看该株植物的品种说明、累计养护次数与产出记录。")
    add_image_placeholder(doc, "植物园总览与植物状态信息",
                          images=["孩子端截图/花园.jpg", "孩子端截图/花园植物状态信息.jpg"])
    add_para(doc, "「选择要种的植物」弹窗按固定顺序展示全部可选物种，并标注每个物种的稀有度与兑换代价。"
                  "当前共 10 种：向日葵（免费初始物种）、月光兰、珊瑚岭兰、翡翠绣球、葡萄、荷花为精英档，"
                  "番茄、草莓、玫瑰、蓝莓为普通档。普通档可用 300 阳光或 10 碎片兑换，精英档需 20 碎片兑换；"
                  "碎片可由专注与成长行为掉落获得，掉落的种子同时等价于该物种的一张免费种植券。"
                  "植物可重复种植，唯一约束为花盆容量；铲除已种植物可返还部分投入。")
    add_image_placeholder(doc, "选择要种的植物列表与可种植物图鉴",
                          images=["孩子端截图/花园可种植物列表.jpg"])
    add_para(doc, "浇水与施肥可加速当前阶段成长，两者均有每日次数额度限制（浇水每日额度按账户状态计算，"
                  "施肥额度与浇水额度取较小值），额度用尽时对应按钮置为禁用态并给出提示。植物绝不因专注不足而死亡，"
                  "仅在长期完全未养护时进入枯萎态，且枯萎后可用低成本路径救回，避免孩子因失败而弃用。")
    add_image_placeholder(doc, "花园长草与产出",
                          images=["孩子端截图/花园长草和产物.jpg"])
    add_heading(doc, "5.3 阳光商店兑换", 2)
    add_para(doc, "在商店选择奖励发起兑换申请，家长端确认核销后阳光扣除；额度不足时显示排队位次。"
                  "商店内奖励分为「实物类」（如额外游戏时间、亲子活动）与「服务类」（如代做家务、挑选晚餐）。"
                  "孩子点击奖励卡片可查看所需阳光数与当前持有量，并提交兑换申请；"
                  "申请提交后统一进入家长端待核销队列，由家长在现实兑现后手动确认。")
    add_image_placeholder(doc, "阳光商店界面", images=["孩子端截图/商店页.png"])
    add_para(doc, "家长端核销时，家长在现实世界兑现奖励后点击「已兑现」才会扣除孩子阳光。"
                  "本版本起所有兑换申请一律由家长显式核销，不设自动放行条件，避免奖励在家长未兑现时被自动扣除。"
                  "家长可设置周阳光预算池额度，低年级默认每周 300 阳光、中年级默认每周 600 阳光，"
                  "高年级默认不设上限（此时兑换只受阳光余额约束）；"
                  "当周预算已满时新申请显示为「排队中」并给出预计放行周期，而不是直接拒绝，以降低孩子的挫败感。"
                  "家长亦可在奖励编辑页调整单个奖励的代价与库存。")
    add_image_placeholder(doc, "家长端奖励编辑与核销",
                          images=["家长端截图/奖励编辑页.jpg", "家长端截图/今日带审核页.jpg"])
    add_heading(doc, "5.4 家长端", 2)
    add_para(doc, "首页进入“家长天地”，输入本地 PIN 进入；在今日/报告/夸夸台/任务/奖励/设置各页完成配置与核销。"
                  "本地 PIN 使用安全区（Keychain / Keystore）加盐哈希存储，连续多次输错会临时锁定输入，"
                  "防止孩子反复试探。家长端与孩子端在同一应用内但为完全独立的导航栈，进入后孩子无法通过返回手势回到孩子端。")
    add_image_placeholder(doc, "家长端 PIN 与今日页",
                          images=["家长端截图/家长PIN页.png", "家长端截图/家长今日审核页.png"])
    add_heading(doc, "5.4.1 今日概览", 3)
    add_para(doc, "今日页汇总当日已完成的专注时长、阳光产出、成长卡完成情况与待核销兑换申请，"
                  "并提供快捷入口跳转至各设置项；顶部显示孩子当日的年龄档位与剩余专注额度，便于家长判断是否需要调整。")
    add_heading(doc, "5.4.2 专注报告", 3)
    add_para(doc, "专注报告按日/周/月维度展示专注时长、有效专注占比、离席次数与时段分布，"
                  "并列出每段专注会话的起止时间与产出。报告数据全部来自本机记录，不含任何影像或音视频内容。")
    add_image_placeholder(doc, "专注报告", images=["家长端截图/专注报告.jpg"])
    add_heading(doc, "5.4.3 夸夸台", 3)
    add_para(doc, "家长可在夸夸台录入一条表扬语，孩子端将以向日葵转述的口吻呈现，"
                  "用于强化正向反馈。夸夸台支持按日期查看历史记录。")
    add_heading(doc, "5.4.4 任务与奖励配置", 3)
    add_para(doc, "任务配置页提供语文作业、数学作业、阅读、背单词等内置模板，家长可增删改并设定每周重复；"
                  "奖励配置页可录入自定义奖励、设定代价（阳光数）与月度预算池。两类配置页均可查看已有的历史记录与核销流水。")
    add_image_placeholder(doc, "成长任务编辑与奖励编辑",
                          images=["家长端截图/成长（任务）编辑页.png", "家长端截图/奖励编辑页.png"])
    add_heading(doc, "5.4.5 设置与数据管理", 3)
    add_para(doc, "设置页包含专注时长档位、每日专注与 App 使用时长上限、可用时段与夜间边界、年龄档位、"
                  "护眼提醒与语言切换等选项；并提供阳光赠予、账号找回与「删除全部数据」入口。"
                  "删除入口会一次性清除本机全部专注、成长、奖励与设置数据，操作前需二次确认。")
    add_image_placeholder(doc, "家长端设置页",
                          images=["家长端截图/设置01.jpg", "家长端截图/设置02.jpg"])
    add_heading(doc, "5.5 花园天气与天气动效", 2)
    add_para(doc, "软件会根据当前日期与所处季节，在花园内叠加当日的天气表现。日型包含晴天、阴天、小雨、暴雨、"
                  "大风、降雪与极寒等，不同日型对植物成长速率有不同影响：雨天与极寒会降低成长效率，"
                  "而部分天气会额外带来生长加成。应用会以卡片形式在任务确认环节提示当日天气，"
                  "同时在花园场景中播放对应的天气动效（雨丝、雨滴、雪花等），动效为循环动画，不阻断任何交互。")
    add_para(doc, "天气影响与季节因素共同参与生长计算：干旱型天气只在夏季（5 至 9 月）出现，"
                  "其余月份不触发；系统在实现上以月份权重表描述各月天气出现的相对可能性，"
                  "并在年度口径上对整体影响做归一化处理，使得全年的天气影响保持在可控范围。")
    add_heading(doc, "5.6 向日葵守卫者", 2)
    add_para(doc, "今日页顶部提供一个「向日葵守卫者」胶囊入口。点击后进入以向日葵为主角的轻量回合制小游戏，"
                  "孩子在专注之外可通过每日券参与，战斗胜利可获得额外奖励。"
                  "该玩法为可选的激励模块，不与专注时长或成长记录绑定，不影响核心习惯养成的产出规则。")
    add_heading(doc, "5.7 多语言支持", 2)
    add_para(doc, "软件支持简体中文与英文两种界面语言，切换入口位于家长端设置页，切换后立即全量生效，"
                  "包括孩子端全部文案、家长端设置项与提示信息。物种名称等落库基线数据不随语言切换改变，"
                  "以保证历史数据的唯一性。")
    add_heading(doc, "第6章 常见问题", 1)
    add_bullet(doc, "Q：专注中途竖屏会怎样？A：竖屏即暂停并弹出确认，保留本次进度。")
    add_bullet(doc, "Q：数据会上传吗？A：不会。所有专注与成长记录仅本机存储，不上传任何服务器。")
    add_bullet(doc, "Q：如何删除数据？A：家长端删除入口可一键删除账户内全部数据。")
    add_bullet(doc, "Q：没有网络能不能用？A：可以。软件全部核心功能均可离线使用，无需登录任何账号。")
    add_bullet(doc, "Q：换手机后数据会同步吗？A：当前版本不做云同步，数据随设备存储，新机需重新开始。")
    add_bullet(doc, "Q：孩子能否自己绕过家长设置？A：家长端由本地 PIN 保护，孩子端不提供进入家长端的路径。")
    add_bullet(doc, "Q：浇水、施肥按钮为什么是灰的？A：当日额度已用尽，次日恢复。")
    add_bullet(doc, "Q：兑换申请为什么显示排队中？A：家长设置的当月奖励预算池已满，排队可于下月放行。")
    add_bullet(doc, "Q：如何联系开发者？A：通过应用内反馈入口反馈，由遵化市云程智服软件技术服务部处理。")
    add_heading(doc, "第7章 技术支持", 1)
    add_para(doc, "本软件由遵化市云程智服软件技术服务部开发维护；如需支持，请通过应用内反馈入口联系。软件为纯本地单机应用，"
                  "无需联网即可正常使用全部核心功能。")
    add_heading(doc, "第8章 版本信息", 1)
    add_bullet(doc, f"软件全称：{C['full_name']}")
    add_bullet(doc, f"软件简称：{C['short_name']}")
    add_bullet(doc, f"英文名称：{C['name_en']}")
    add_bullet(doc, f"版本号：{C['version']}")
    add_bullet(doc, f"开发完成日期：{C['dev_complete']}")
    add_bullet(doc, f"运行平台：{C['os']}")
    add_bullet(doc, "著作权人：遵化市云程智服软件技术服务部（统一社会信用代码 92130281MAKRRERD1N）")

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
