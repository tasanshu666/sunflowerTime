/// 任务模板编辑器（M3 T05，§4.4 / §8.2 任务配置）。
///
/// 家长新增 / 编辑学习任务模板：名称、科目、是否需专注、最少专注分钟、阳光奖励、重复规则。
/// 校验在提交时完成；合法则构造 [Task] 并经 [onSave] 落库（由调用方负责持久化与刷新）。
library task_editor_dialog;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/core/i18n/enum_l10n.dart';

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

  /// 分类下拉项（C52）：UI 图标 + 文字；图标加载失败回退 emoji（美术永不阻塞）。
  ///
  /// i18n B3：分类名不再从 domain 的 `c.label` 取（已删除），改传 [t] 走 ARB。
  DropdownMenuItem<TaskCategory> _categoryDropdownItem(
      TaskCategory c, AppLocalizations t) {
    return DropdownMenuItem<TaskCategory>(
      value: c,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              taskCategoryIconAsset(c),
              width: 22,
              height: 22,
              errorBuilder: (_, Object __, StackTrace? ___) =>
                  Text(c.icon, style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          Text(taskCategoryLabel(c, t)),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final AppLocalizations t = l10nOf(context);
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = t.parent_task_edit_err_name);
      return;
    }
    if (_reward < _minReward || _reward > _maxReward) {
      setState(
          () => _error = t.parent_task_edit_err_reward(_minReward, _maxReward));
      return;
    }
    final String customSubject = _customSubjectCtrl.text.trim();
    if (_subject == TaskSubject.custom && customSubject.isEmpty) {
      setState(() => _error = t.parent_task_edit_err_subject);
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
      if (mounted) setState(() => _error = l10nOf(context).parent_task_edit_err_save(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 自含弹窗（i18n B2）：本对话框经 `showDialog` 挂在根 Navigator 上，
    // 页级 scope 拿不到 → 内部自带 [L10nScope]（B1 先例：PlantConfirmDialog）。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations t = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(widget.initial == null
                ? t.parent_task_edit_title_new
                : t.parent_task_edit_title_edit),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                        labelText: t.parent_task_edit_name_label),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TaskSubject>(
                    value: _subject,
                    decoration: InputDecoration(
                        labelText: t.parent_task_edit_subject_label),
                    items: <DropdownMenuItem<TaskSubject>>[
                      DropdownMenuItem(
                          value: TaskSubject.general,
                          child: Text(t.parent_task_edit_subject_general)),
                      DropdownMenuItem(
                          value: TaskSubject.chinese,
                          child: Text(t.parent_task_edit_subject_chinese)),
                      DropdownMenuItem(
                          value: TaskSubject.math,
                          child: Text(t.parent_task_edit_subject_math)),
                      DropdownMenuItem(
                          value: TaskSubject.english,
                          child: Text(t.parent_task_edit_subject_english)),
                      DropdownMenuItem(
                          value: TaskSubject.custom,
                          child: Text(t.parent_task_edit_subject_custom)),
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
                      decoration: InputDecoration(
                        labelText: t.parent_task_edit_custom_label,
                        hintText: t.parent_task_edit_custom_hint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 分类下拉（C52 / 玄参 2026-10-10：换「UI 图标 + 文字」渲染，并新增
                  // 「习惯」分类；图标与孩子端卡片同一素材池，视觉语言统一）。
                  DropdownButtonFormField<TaskCategory>(
                    value: _category,
                    decoration: InputDecoration(
                        labelText: t.parent_task_edit_category_label),
                    items: TaskCategory.values
                        .map((TaskCategory c) => _categoryDropdownItem(c, t))
                        .toList(),
                    onChanged: (TaskCategory? v) =>
                        v == null ? null : setState(() => _category = v),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.parent_task_edit_link_title),
                    subtitle: Text(t.parent_task_edit_link_subtitle),
                    value: _requiresFocus,
                    onChanged: (bool v) => setState(() {
                      _requiresFocus = v;
                      _reward = _clampReward(_reward);
                    }),
                  ),
                  if (_requiresFocus)
                    Row(
                      children: <Widget>[
                        Text(t.parent_task_edit_min_focus_label),
                        Expanded(
                          child: Slider(
                            value: _minFocusMin.toDouble(),
                            min: 5,
                            max: 60,
                            divisions: 11,
                            label:
                                t.parent_task_edit_minutes(_minFocusMin),
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
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.lock_outline,
                              size: 18, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.parent_task_edit_reward_fixed(
                                _minFocusMin,
                                Task.rewardCapFor(_minFocusMin),
                              ),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.teal),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: <Widget>[
                        Text(t.parent_task_edit_reward_label),
                        Expanded(
                          child: Slider(
                            value: _clampReward(_reward).toDouble(),
                            min: _minReward.toDouble(),
                            max: _maxReward.toDouble(),
                            divisions: _maxReward > _minReward
                                ? (_maxReward - _minReward)
                                : null,
                            label:
                                t.parent_task_edit_reward_slider(_reward),
                            onChanged: (double v) =>
                                setState(() => _reward = v.round()),
                          ),
                        ),
                        Text('$_reward'),
                      ],
                    ),
                  // 仅非联动项：提示奖励区间（默认 8 / 最大 15）。
                  if (!_requiresFocus)
                    Text(
                      t.parent_task_edit_reward_range(
                          _minReward, _maxReward, kTaskRewardDefault),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<RepeatRule>(
                    value: _repeat,
                    decoration: InputDecoration(
                        labelText: t.parent_task_edit_repeat_label),
                    items: <DropdownMenuItem<RepeatRule>>[
                      DropdownMenuItem(
                          value: RepeatRule.none,
                          child: Text(t.parent_task_edit_repeat_none)),
                      DropdownMenuItem(
                          value: RepeatRule.daily,
                          child: Text(t.parent_task_edit_repeat_daily)),
                      DropdownMenuItem(
                          value: RepeatRule.weekly,
                          child: Text(t.parent_task_edit_repeat_weekly)),
                    ],
                    onChanged: (RepeatRule? v) =>
                        v == null ? null : setState(() => _repeat = v),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child: Text(t.shared_cancel),
              ),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.parent_task_edit_btn_save),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 重复规则中间枚举（none / daily / weekly），与 task.repeatRule 字符串对应。
enum RepeatRule { none, daily, weekly }
