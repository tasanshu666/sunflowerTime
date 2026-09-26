/// 任务模板编辑器（M3 T05，§4.4 / §8.2 任务配置）。
///
/// 家长新增 / 编辑学习任务模板：名称、科目、是否需专注、最少专注分钟、阳光奖励、重复规则。
/// 校验在提交时完成；合法则构造 [Task] 并经 [onSave] 落库（由调用方负责持久化与刷新）。
library task_editor_dialog;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';

/// 任务模板编辑对话框。
///
/// [initial] 为 null 表示新建；否则为编辑既有模板（保留其 id 与 isCustom 标记）。
/// [onSave] 在通过校验后回调，由调用方执行仓储持久化。
class TaskEditorDialog extends ConsumerStatefulWidget {
  final Task? initial;
  final Future<void> Function(Task) onSave;

  const TaskEditorDialog({
    super.key,
    this.initial,
    required this.onSave,
  });

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _customSubjectCtrl = TextEditingController();
  TaskSubject _subject = TaskSubject.general;
  TaskCategory _category = TaskCategory.other; // 成长项内容分类（学习/运动/生活/其他）
  bool _requiresFocus = true;
  int _minFocusMin = kTaskMinFocusDefault;
  int _reward = kTaskRewardDefault;
  RepeatRule _repeat = RepeatRule.none;
  String? _error;
  bool _saving = false;

  /// 奖励上限：联动项 = 最少专注 × 40%；非联动项沿用全局上限
  /// （非联动项由家长手动核销，定价权归家长，且仍受当日软顶约束）。
  int get _maxReward =>
      _requiresFocus ? Task.rewardCapFor(_minFocusMin) : kTaskRewardMax;

  /// 奖励下限：正常是 kTaskRewardMin；上限低于下限时（如最少专注 5 分钟 → 上限 2）取上限。
  int get _minReward => kTaskRewardMin < _maxReward ? kTaskRewardMin : _maxReward;

  /// 把奖励值夹回 [_minReward, _maxReward]。
  int _clampReward(int v) =>
      v > _maxReward ? _maxReward : (v < _minReward ? _minReward : v);

  @override
  void initState() {
    super.initState();
    final Task? t = widget.initial;
    if (t != null) {
      _nameCtrl.text = t.name;
      _subject = t.subject;
      _customSubjectCtrl.text = t.customSubject ?? '';
      _requiresFocus = t.requiresFocus;
      _minFocusMin = t.minFocusMin;
      _reward = t.sunlightReward;
      _repeat = _ruleFrom(t.repeatRule);
      _category = t.category;
    }
    // 编辑历史超标老成长项时，打开即夹回合法区间并显示合规值。
    _reward = _clampReward(_reward);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customSubjectCtrl.dispose();
    super.dispose();
  }

  static RepeatRule _ruleFrom(String? rule) {
    switch (rule) {
      case 'daily':
        return RepeatRule.daily;
      case 'weekly':
        return RepeatRule.weekly;
      default:
        return RepeatRule.none;
    }
  }

  static String? _ruleTo(RepeatRule r) {
    switch (r) {
      case RepeatRule.daily:
        return 'daily';
      case RepeatRule.weekly:
        return 'weekly';
      case RepeatRule.none:
        return null;
    }
  }

  Future<void> _submit() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写成长项名称');
      return;
    }
    if (_reward < _minReward || _reward > _maxReward) {
      setState(() => _error = '阳光奖励需在 $_minReward–$_maxReward 之间');
      return;
    }
    final String customSubject = _customSubjectCtrl.text.trim();
    if (_subject == TaskSubject.custom && customSubject.isEmpty) {
      setState(() => _error = '请填写自定义科目名称');
      return;
    }
    final Task task = Task(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      subject: _subject,
      category: _category,
      // 仅自定义科目落库科目名；切回内置科目时显式清空，避免残留旧文本。
      customSubject:
          _subject == TaskSubject.custom ? customSubject : null,
      requiresFocus: _requiresFocus,
      minFocusMin: _minFocusMin,
      // 联动项奖励固定 = 专注分钟 × 40%（effectiveSunlightReward 只取该值）；
      // 存盘也写固定值，便于家长端列表展示与数据对账一致。
      sunlightReward: _requiresFocus ? Task.rewardCapFor(_minFocusMin) : _reward,
      repeatRule: _ruleTo(_repeat),
      isCustom: widget.initial?.isCustom ?? true,
    );
    setState(() => _saving = true);
    try {
      await widget.onSave(task);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增成长项' : '编辑成长项'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '成长项名称'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TaskSubject>(
              value: _subject,
              decoration: const InputDecoration(labelText: '科目'),
              items: const <DropdownMenuItem<TaskSubject>>[
                DropdownMenuItem(value: TaskSubject.general, child: Text('通用')),
                DropdownMenuItem(value: TaskSubject.chinese, child: Text('语文')),
                DropdownMenuItem(value: TaskSubject.math, child: Text('数学')),
                DropdownMenuItem(value: TaskSubject.english, child: Text('英语')),
                DropdownMenuItem(
                    value: TaskSubject.custom, child: Text('自定义…')),
              ],
              onChanged: (TaskSubject? v) =>
                  v == null ? null : setState(() => _subject = v),
            ),
            // 自定义科目：自由输入科目名（如「科学」「书法」），内置科目不显示该输入框。
            if (_subject == TaskSubject.custom) ...<Widget>[
              const SizedBox(height: 8),
              TextField(
                controller: _customSubjectCtrl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '自定义科目名称',
                  hintText: '例如：科学 / 书法 / 编程',
                ),
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<TaskCategory>(
              value: _category,
              decoration: const InputDecoration(labelText: '分类'),
              items: const <DropdownMenuItem<TaskCategory>>[
                DropdownMenuItem(
                    value: TaskCategory.learning, child: Text('学习')),
                DropdownMenuItem(
                    value: TaskCategory.sports, child: Text('运动')),
                DropdownMenuItem(value: TaskCategory.life, child: Text('生活')),
                DropdownMenuItem(
                    value: TaskCategory.other, child: Text('其他')),
              ],
              onChanged: (TaskCategory? v) =>
                  v == null ? null : setState(() => _category = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('专注联动（自动结算）'),
              subtitle: const Text(
                '勾选后，孩子从这一项点「开始专注」，达标会自动完成并发放阳光，无需手动打卡。',
              ),
              value: _requiresFocus,
              onChanged: (bool v) => setState(() {
                _requiresFocus = v;
                _reward = _clampReward(_reward);
              }),
            ),
            if (_requiresFocus)
              Row(
                children: <Widget>[
                  const Text('最少专注'),
                  Expanded(
                    child: Slider(
                      value: _minFocusMin.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '$_minFocusMin 分钟',
                      onChanged: (double v) => setState(() {
                        _minFocusMin = v.round();
                        // 分钟变化 → 固定奖励同步变化（联动奖励 = 分钟 × 40%）。
                        _reward = _clampReward(_reward);
                      }),
                    ),
                  ),
                  Text('$_minFocusMin′'),
                ],
              ),
            const SizedBox(height: 8),
            // 联动项奖励固定 = 专注分钟 × 40%，家长不可调（用户 2026-09-21 拍板）。
            if (_requiresFocus)
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.lock_outline, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '奖励固定 = 专注 $_minFocusMin 分钟 × 40% = '
                        '${Task.rewardCapFor(_minFocusMin)} ☀（无需调整）',
                        style: const TextStyle(fontSize: 13, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: <Widget>[
                  const Text('阳光奖励'),
                  Expanded(
                    child: Slider(
                      value: _clampReward(_reward).toDouble(),
                      min: _minReward.toDouble(),
                      max: _maxReward.toDouble(),
                      divisions:
                          _maxReward > _minReward ? (_maxReward - _minReward) : null,
                      label: '$_reward 阳光',
                      onChanged: (double v) => setState(() => _reward = v.round()),
                    ),
                  ),
                  Text('$_reward'),
                ],
              ),
            // 仅非联动项：提示奖励区间（默认 8 / 最大 15）。
            if (!_requiresFocus)
              Text(
                '区间 $_minReward–$_maxReward ☀（默认 $kTaskRewardDefault）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RepeatRule>(
              value: _repeat,
              decoration: const InputDecoration(labelText: '重复规则'),
              items: const <DropdownMenuItem<RepeatRule>>[
                DropdownMenuItem(value: RepeatRule.none, child: Text('不重复')),
                DropdownMenuItem(value: RepeatRule.daily, child: Text('每天')),
                DropdownMenuItem(value: RepeatRule.weekly, child: Text('每周')),
              ],
              onChanged: (RepeatRule? v) =>
                  v == null ? null : setState(() => _repeat = v),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// 重复规则中间枚举（none / daily / weekly），与 task.repeatRule 字符串对应。
enum RepeatRule { none, daily, weekly }
