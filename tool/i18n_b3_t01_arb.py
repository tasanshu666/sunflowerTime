#!/usr/bin/env python3
"""T01 · i18n 地基：给 zh/en ARB 加 101 个新 key + 30 组 child_* 占位符元数据。

铁律：`@key.placeholders` 的声明顺序 = 生成签名里的参数顺序（= 字母序），
每个占位符写真实类型 —— 顺序一旦错位，类型全是 Object 时仍能编译，只是文案错。
"""
import json
import re
import sys

ZH = 'lib/l10n/app_zh.arb'
EN = 'lib/l10n/app_en.arb'

# ── 1. 101 个新 key：(key, zh, en, [(placeholder, type), ...]) ────────────────
NEW = [
    # A 成长项分类 5
    ('shared_task_category_other', '其他', 'Other', []),
    ('shared_task_category_learning', '学习', 'Learning', []),
    ('shared_task_category_sports', '运动', 'Sports', []),
    ('shared_task_category_life', '生活', 'Life', []),
    ('shared_task_category_habit', '习惯', 'Habit', []),
    # B 奖励分类 6
    ('shared_reward_content_other', '其他', 'Other', []),
    ('shared_reward_content_snacks', '零食', 'Snacks', []),
    ('shared_reward_content_play', '游玩', 'Play', []),
    ('shared_reward_content_entertainment', '娱乐', 'Entertainment', []),
    ('shared_reward_content_toys', '玩具', 'Toys', []),
    ('shared_reward_content_books', '阅读', 'Books', []),
    # C 物种名 6
    ('shared_species_sunflower', '向日葵', 'Sunflower', []),
    ('shared_species_moon_orchid', '月光兰', 'Moon Orchid', []),
    ('shared_species_tomato', '番茄', 'Tomato', []),
    ('shared_species_strawberry', '草莓', 'Strawberry', []),
    ('shared_species_coral_orchid', '珊瑚岭兰', 'Coral Ridge Orchid', []),
    ('shared_species_jade_hydrangea', '翡翠绣球', 'Jade Hydrangea', []),
    # D 周几 full 7
    ('shared_weekday_mon', '周一', 'Mon', []),
    ('shared_weekday_tue', '周二', 'Tue', []),
    ('shared_weekday_wed', '周三', 'Wed', []),
    ('shared_weekday_thu', '周四', 'Thu', []),
    ('shared_weekday_fri', '周五', 'Fri', []),
    ('shared_weekday_sat', '周六', 'Sat', []),
    ('shared_weekday_sun', '周日', 'Sun', []),
    # E 第N周 1
    ('parent_report_bucket_week', '第{index}周', 'Wk {index}', [('index', 'int')]),
    # F 称号属性 9
    ('shared_perk_water_discount', '浇水消耗 −{value}', 'Water cost −{value}',
     [('value', 'int')]),
    ('shared_perk_fertilize_discount', '施肥消耗 −{value}',
     'Fertilizer cost −{value}', [('value', 'int')]),
    ('shared_perk_weed_bonus', '除草奖励 +{value}', 'Weeding bonus +{value}',
     [('value', 'int')]),
    ('shared_perk_pest_bonus', '除虫奖励 +{value}', 'Pest bonus +{value}',
     [('value', 'int')]),
    ('shared_perk_bloom_bonus', '开花阳光 +{value}', 'Bloom sunlight +{value}',
     [('value', 'int')]),
    ('shared_perk_dew_bonus', '晨露阳光 +{value}', 'Dew sunlight +{value}',
     [('value', 'int')]),
    ('shared_perk_eyecare_bonus', '护眼奖励 +{value}', 'Eye-care bonus +{value}',
     [('value', 'int')]),
    ('shared_perk_expand_discount', '花盆扩容 −{value}', 'Pot expand −{value}',
     [('value', 'int')]),
    ('shared_perk_shovel_refund', '铲除退款 +{value}', 'Shovel refund +{value}',
     [('value', 'int')]),
    # G 时长 3
    ('shared_duration_minutes', '{m} 分钟', '{m} min', [('m', 'int')]),
    ('shared_duration_hours', '{h} 小时', '{h} h', [('h', 'int')]),
    ('shared_duration_hours_minutes', '{h} 小时 {m} 分钟', '{h} h {m} min',
     [('h', 'int'), ('m', 'int')]),
    # H 称号差距 2
    ('shared_level_gap_next', '距 Lv.{n} 还差 {duration}',
     '{duration} to Lv.{n}', [('n', 'int'), ('duration', 'String')]),
    ('shared_level_gap_max', '已是最高称号 · {title}', 'Max title · {title}',
     [('title', 'String')]),
    # I 周限 2
    ('shared_reward_weekly_limit', '周限 {remaining} 次',
     '{remaining} left this week', [('remaining', 'int')]),
    ('shared_reward_unlimited', '不限次数', 'Unlimited', []),
    # J 植物操作错误 17
    ('shared_plant_err_species_not_found', '未找到该植物物种',
     'Plant species not found', []),
    ('shared_plant_err_pot_out_of_capacity', '花盆序号超出容量（{pot} / {capacity}）',
     'Pot #{pot} is beyond capacity ({capacity})',
     [('pot', 'int'), ('capacity', 'int')]),
    ('shared_plant_err_pot_occupied', '花盆 #{pot} 已被占用，请先清理',
     'Pot #{pot} is occupied — clear it first', [('pot', 'int')]),
    ('shared_plant_err_premium_fragments_only', '精英植物只能用碎片兑换',
     'Premium plants can only be bought with fragments', []),
    ('shared_plant_err_seed_empty', '种子已用完，去开花收集新的种子吧',
     'No seeds left — bloom plants to collect more', []),
    ('shared_plant_err_sunlight_not_enough', '阳光不足，还差 {short} 阳光',
     'Not enough sunlight — {short} more needed', [('short', 'int')]),
    ('shared_plant_err_fragments_not_enough', '碎片不足，还差 {short} 片',
     'Not enough fragments — {short} more needed', [('short', 'int')]),
    ('shared_plant_err_care_state_invalid', '仅成长中/开花/枯萎植物可养护',
     'Only growing, blooming or wilting plants can be cared for', []),
    ('shared_plant_err_water_daily_limit', '今日浇水已达 {max} 次上限',
     'Watering limit reached ({max} today)', [('max', 'int')]),
    ('shared_plant_err_water_interval', '浇水间隔需 {interval} 分钟，还需 {wait} 分钟',
     'Water every {interval} min — wait {wait} min',
     [('interval', 'int'), ('wait', 'int')]),
    ('shared_plant_err_fertilize_daily_limit', '今日施肥已达 {max} 次上限',
     'Fertilizing limit reached ({max} today)', [('max', 'int')]),
    ('shared_plant_err_plant_not_found', '植物不存在', 'Plant not found', []),
    ('shared_plant_err_already_wilted', '这株已经枯萎了，不用清理啦',
     'This plant has already wilted', []),
    ('shared_plant_err_no_weed', '这盆没有杂草哦', 'No weeds in this pot', []),
    ('shared_plant_err_no_pest', '这盆没有害虫哦', 'No pests in this pot', []),
    ('shared_plant_err_garden_full', '花园已达当前档位容量上限（{limit} 盆），解锁可扩容',
     'Garden is full ({limit} pots) — unlock to expand', [('limit', 'int')]),
    ('shared_plant_err_reward_not_mature', '奖励还没成熟，或已经被领取啦',
     'Not ripe yet, or already collected', []),
    # K 核销错误 9
    ('shared_checkin_err_linked_auto', '这个成长项要在专注里自动完成哦',
     'This task completes automatically in a focus session', []),
    ('shared_checkin_err_already_done', '这个成长项今天已经做到啦',
     'You already did this task today', []),
    ('shared_checkin_err_not_linked', '非联动成长项不能走专注结算',
     "This task isn't focus-linked", []),
    ('shared_checkin_err_session_not_today', '这次专注不在今天，不能结算今天的成长项',
     "That session isn't from today", []),
    ('shared_checkin_err_session_used', '这次专注已经结算过成长项啦',
     'That session already settled a task', []),
    ('shared_checkin_err_not_found', '找不到这条记录，可能已被删除',
     'Record not found — it may have been deleted', []),
    ('shared_checkin_err_already_verified', '这条记录已经处理过啦，不能重复核销',
     "Already handled — can't verify twice", []),
    ('shared_checkin_err_already_rejected', '这条记录已经处理过啦，不能重复处理',
     'Already handled', []),
    ('shared_checkin_err_race', '这条记录刚刚已经被处理过了',
     'Just handled a moment ago', []),
    # L 种子名 10
    ('seed_task_homework', '完成学校作业', 'Finish school homework', []),
    ('seed_task_math', '练习数学口算', 'Practice mental math', []),
    ('seed_task_read', '阅读 20 分钟', 'Read for 20 minutes', []),
    ('seed_task_rope_skip', '1分钟跳绳170个以上',
     'Jump rope 170+ times in a minute', []),
    ('seed_task_chores', '帮助家长打扫卫生', 'Help tidy up at home', []),
    ('seed_reward_snack', '小零食', 'A small snack', []),
    ('seed_reward_extra_play', '睡前多玩10分钟',
     '10 more minutes before bed', []),
    ('seed_reward_cartoon', '看一集动画片', 'Watch one cartoon episode', []),
    ('seed_reward_toy', '买一个小玩具', 'A small toy', []),
    ('seed_reward_weekend_outing', '周末出去玩', 'A weekend outing', []),
    # M 默认孩子名 1
    ('shared_child_default_name', '孩子', 'Child', []),
    # N 阳光账本类型标签 22 + 护眼字幕 1
    ('child_hist_ref_focus', '专注产出', 'Focus output', []),
    ('child_hist_ref_focus_session', '专注', 'Focus', []),
    ('child_hist_ref_focus_task_reward', '专注任务奖励', 'Focus task reward', []),
    ('child_hist_ref_task_checkin', '成长项奖励', 'Task reward', []),
    ('child_hist_ref_plant_plant', '种植植物', 'Planted a plant', []),
    ('child_hist_ref_plant_water', '浇水', 'Watering', []),
    ('child_hist_ref_plant_fertilize', '施肥', 'Fertilizing', []),
    ('child_hist_ref_plant_revive', '救回植物', 'Plant revived', []),
    ('child_hist_ref_plant_expand', '花园扩容', 'Garden expanded', []),
    ('child_hist_ref_plant_weed', '拔草', 'Weeding', []),
    ('child_hist_ref_plant_pest', '除虫', 'Pest removal', []),
    ('child_hist_ref_plant_death_refund', '植物死亡返还',
     'Plant death refund', []),
    ('child_hist_ref_eye_care_break', '护眼', 'Eye care', []),
    ('child_hist_ref_plant_shovel_refund', '铲除返还', 'Shovel refund', []),
    ('child_hist_ref_bloom_reward', '开花奖励', 'Bloom reward', []),
    ('child_hist_ref_bloom_reward_24h', '花开回访奖励',
     'Bloom revisit reward', []),
    ('child_hist_ref_redeem', '兑换奖励', 'Reward redeemed', []),
    ('child_hist_ref_redemption', '兑换奖励', 'Reward redeemed', []),
    ('child_hist_ref_queue_release', '阳光池释放', 'Sunlight pool release', []),
    ('child_hist_ref_parent_gift', '家长赠予', 'Parent gift', []),
    ('child_hist_ref_debug_grant', '调试发放', 'Debug grant', []),
    ('child_hist_ref_focus_level_up', '专注升级', 'Focus level up', []),
    ('child_eyecare_seg_default', '跟着动画一起做，保护眼睛',
     'Follow the animation to protect your eyes', []),
]

# ── 2. 30 个 child_* 带参 key 的占位符元数据 ────────────────────────────────
# 🔴 顺序 = 当前生成签名里的参数顺序（字母序），**不许**按人类语序重排。
ARGS30 = [
    ('child_settle_task_done', [('capped', 'String'), ('name', 'String'),
                                ('sun', 'String')]),
    ('child_cap_single_body', [('minutes', 'int')]),
    ('child_settle_cap_orig_vs_net', [('net', 'String'), ('raw', 'String')]),
    ('child_settle_task_progress', [('name', 'String')]),
    ('child_rest_body', [('sec', 'int')]),
    ('child_entry_custom_hint_max', [('max', 'int')]),
    ('child_shell_item_cost', [('sun', 'int')]),
    ('child_entry_minutes', [('minutes', 'int')]),
    ('child_settle_task_capped', [('sun', 'String')]),
    ('child_shell_reject_subtitle', [('note', 'String')]),
    ('child_lock_body', [('hour', 'int')]),
    ('child_entry_remaining_today', [('cap', 'int'), ('minutes', 'int')]),
    ('child_entry_remaining_snack', [('minutes', 'int'),
                                     ('remaining', 'int')]),
    ('child_eyecare_countdown', [('sec', 'int')]),
    ('child_today_minutes', [('minutes', 'int')]),
    ('child_cap_unlock_in', [('minutes', 'int')]),
    ('child_today_focus_count', [('count', 'int')]),
    ('child_cap_minutes', [('minutes', 'int')]),
    ('child_entry_cap_snack2', [('cap', 'int')]),
    ('child_entry_cap_daily', [('cap', 'int')]),
    ('child_shell_verify_total', [('total', 'int')]),
    ('child_shell_task_footer_partial', [('capped', 'int'), ('total', 'int')]),
    ('child_shell_task_footer', [('total', 'int')]),
    ('child_entry_custom_hint_capped', [('max', 'int')]),
    ('child_settle_secs', [('sec', 'int')]),
    ('child_settle_cap_body_detail', [('cheer', 'String'),
                                      ('detail', 'String')]),
    ('child_shell_task_item_sun', [('sun', 'int')]),
    ('child_settle_mins', [('min', 'int')]),
    ('child_entry_cap_snack', [('cap', 'int')]),
    ('child_settle_min_sec', [('min', 'int'), ('sec', 'int')]),
]


def meta_block(key, placeholders, indent='  '):
    """生成 `@key` 元数据块（不含结尾逗号）。"""
    lines = [f'{indent}"@{key}": {{', f'{indent}  "placeholders": {{']
    items = []
    for name, typ in placeholders:
        items.append(
            f'{indent}    "{name}": {{\n'
            f'{indent}      "type": "{typ}"\n'
            f'{indent}    }}'
        )
    lines.append(',\n'.join(items))
    lines.append(f'{indent}  }}')
    lines.append(f'{indent}}}')
    return '\n'.join(lines)


def add_meta(src, table, missing_ok_check=True):
    """在每条 base key 行后插入 `@key` 元数据块。"""
    for key, ph in table:
        meta_key = f'"@{key}"'
        if meta_key in src:
            raise SystemExit(f'{key}: 元数据已存在，拒绝重复插入')
        pattern = re.compile(r'^(  "%s": .*)$' % re.escape(key), re.M)
        matches = pattern.findall(src)
        if len(matches) != 1:
            raise SystemExit(f'{key}: 命中 {len(matches)} 次，无法定位')
        line = matches[0]
        # 该行必须以逗号结尾（后面还有别的 key），否则是文件最后一个 key。
        if not line.rstrip().endswith(','):
            raise SystemExit(f'{key}: 是最后一个 key，需手工处理')
        block = line + '\n' + meta_block(key, ph) + ','
        src = src.replace(line, block, 1)
    return src


def append_new(src, lang, idx):
    """把新 key（base + 元数据）追加到 JSON 对象末尾。"""
    body = src.rstrip()
    assert body.endswith('}'), 'ARB 必须以 } 结尾'
    body = body[:-1].rstrip()
    # 末条 key 可能没有尾逗号 —— 统一去掉，之后逐块用 `,\n` 拼接（末块不加）。
    if body.endswith(','):
        body = body[:-1].rstrip()
    chunks = []
    for key, zh, en, ph in NEW:
        value = zh if idx == 0 else en
        chunks.append(f'  "{key}": {json.dumps(value, ensure_ascii=False)}')
        if ph:
            chunks.append(meta_block(key, ph))
    body = body + ',\n' + ',\n'.join(chunks) + '\n}\n'
    return body


def main():
    for path, lang, idx in ((ZH, 'zh', 0), (EN, 'en', 1)):
        with open(path, encoding='utf-8') as f:
            src = f.read()
        src = add_meta(src, ARGS30)
        src = append_new(src, lang, idx)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src)
        data = json.load(open(path, encoding='utf-8'))
        keys = [k for k in data if not k.startswith('@')]
        metas = [k for k in data if k.startswith('@')]
        print(f'{path}: {len(keys)} keys, {len(metas)} meta blocks')


if __name__ == '__main__':
    main()
