#!/usr/bin/env python3
"""i18n B3 · T05 的 ARB 批量插入（一次性工具，可复跑审计）。

新增 20 个 key（zh 逐字节抄自迁移前的代码现值，en 为地道英文）：
  · 9 条称号属性名（原 `lib/core/constants/prd_params.dart` 的 `kPerkNames`）；
  · 5 条任务种子名（原 `lib/data/local/task_seed.dart` 的 `kSeedTasks[i].name`）；
  · 5 条奖励种子名（原 `lib/data/local/reward_seed.dart` 的 `kSeedRewardTemplates[i].name`）；
  · 1 条默认孩子名（原 `lib/domain/services/account_service.dart` 的 `'孩子'` 字面量）。

纪律：
  · 全部**无占位符** → 不需要 `@key.placeholders` 元数据（故 meta 数不变）；
  · 已存在同名 key 时**跳过**（幂等），并打印出来；
  · 只改「插入」不动既有行 —— 老 key 的字节序不变，`git diff` 里新增块自成一段。

用法：`python3 tool/i18n_b3_t05_arb.py`（在仓库根跑）
"""
import json
import pathlib
import sys

ZH = pathlib.Path('lib/l10n/app_zh.arb')
EN = pathlib.Path('lib/l10n/app_en.arb')

# (key, zh, en) —— 顺序即插入顺序：属性名 → 任务种子 → 奖励种子 → 默认孩子名
NEW_KEYS = [
    # ── 9 条称号属性名（索引与 kFocusLevelTitleLevels 一一对应）────────────
    ('shared_perk_name_eye_care', '护眼', 'Eye care'),
    ('shared_perk_name_water', '浇水', 'Watering'),
    ('shared_perk_name_fertilize', '施肥', 'Fertilizing'),
    ('shared_perk_name_weed', '除草', 'Weeding'),
    ('shared_perk_name_pest', '除虫', 'Pest control'),
    ('shared_perk_name_bloom', '绽放', 'Bloom'),
    ('shared_perk_name_dew', '晨露', 'Morning dew'),
    ('shared_perk_name_pot_expand', '扩盆', 'Pot upgrade'),
    ('shared_perk_name_shovel', '铲除', 'Removal'),
    # ── 5 条任务种子名 ────────────────────────────────────────────────────
    ('seed_task_homework', '完成学校作业', 'Finish school homework'),
    ('seed_task_math', '练习数学口算', 'Practice mental math'),
    ('seed_task_read', '阅读 20 分钟', 'Read for 20 minutes'),
    ('seed_task_rope_skip', '1分钟跳绳170个以上',
     'Jump rope 170+ times in 1 minute'),
    ('seed_task_chores', '帮助家长打扫卫生', 'Help with the housework'),
    # ── 5 条奖励种子名 ────────────────────────────────────────────────────
    ('seed_reward_snack', '小零食', 'A small snack'),
    ('seed_reward_extra_play', '睡前多玩10分钟',
     '10 more minutes of play before bed'),
    ('seed_reward_cartoon', '看一集动画片', 'Watch one cartoon episode'),
    ('seed_reward_toy', '买一个小玩具', 'A small toy'),
    ('seed_reward_weekend_outing', '周末出去玩', 'A weekend outing'),
    # ── 默认孩子名 ────────────────────────────────────────────────────────
    ('shared_default_child_name', '孩子', 'Child'),
]


def append_keys(path: pathlib.Path, column: int) -> int:
    """把 NEW_KEYS[column] 追加到 [path] 的 JSON 顶层（保持 2 空格缩进风格）。"""
    text = path.read_text(encoding='utf-8')
    # 先做合法性自检：文件当前必须是可解析的 JSON（防上一轮写坏后继续叠加）。
    existing = json.loads(text)
    todo = [(k, vals[column]) for k, *vals in NEW_KEYS if k not in existing]
    if not todo:
        print(f'{path}: 无新增（已全部存在）')
        return 0

    body = text.rstrip()
    assert body.endswith('}'), f'{path} 末字符不是 }}，停止以免写坏'
    # 去掉收尾的 `}` 与其前的空白，再剥掉最后一个 key 的尾逗号。
    body = body[:-1].rstrip()
    if body.endswith(','):
        body = body[:-1]

    chunks = []
    for key, value in todo:
        chunks.append(f'  {json.dumps(key, ensure_ascii=False)}: '
                      f'{json.dumps(value, ensure_ascii=False)}')
    new_text = body + ',\n' + ',\n'.join(chunks) + '\n}\n'

    # 写前再校验一次：解析成功且 key 数 = 旧 + 新增。
    parsed = json.loads(new_text)
    assert len(parsed) == len(existing) + len(todo), '插入后 key 数不符，停止'
    for key, value in todo:
        assert parsed[key] == value, f'{key} 插入值不符'

    path.write_text(new_text, encoding='utf-8')
    print(f'{path}: +{len(todo)} keys（{len(existing)} → {len(parsed)}）')
    return len(todo)


def main() -> int:
    a = append_keys(ZH, 0)
    b = append_keys(EN, 1)
    if a != b:
        print(f'🔴 zh/en 新增数不一致（{a} vs {b}）', file=sys.stderr)
        return 1
    # 收尾对称性核对：两文件 key 集必须相同。
    zh = json.loads(ZH.read_text(encoding='utf-8'))
    en = json.loads(EN.read_text(encoding='utf-8'))
    zh_keys = {k for k in zh if not k.startswith('@')}
    en_keys = {k for k in en if not k.startswith('@')}
    if zh_keys != en_keys:
        print(f'🔴 zh/en key 集不对称：{sorted(zh_keys ^ en_keys)}',
              file=sys.stderr)
        return 1
    print(f'OK — 有效 key {len(zh_keys)}（zh/en 对称），meta '
          f'{len([k for k in zh if k.startswith("@")])}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
