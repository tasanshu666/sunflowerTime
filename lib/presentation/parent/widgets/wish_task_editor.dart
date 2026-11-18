/// 家长端「设定目标 + 布置任务」编辑器（A21.4 / A-T05 组2）。
///
/// 同一弹层两个页签：
///  · 「目标」：选口径（专注分钟 / 任务条数）+ 目标值，写 `target_mode` /
///    `target_value`（只写一次，R1/G12）；mode 0 下不给行为型任务选项（R8）。
///  · 「任务」：任务列表（≤ kWishTaskMaxCount），名称 / 重复 / 专注型开关 +
///    单次时长（`tasks.minFocusMin`），写 `tasks.wishId`（v0.4）。
///
/// 目标值护栏（PRD W23.2 不变式④）：下调触发 100% ⇒ 二次确认 + 钳制到
/// `max(设定值, progressValue)`；上调 ⇒ 二次确认 + 双重护栏（`upscaleAllowed`）。
/// mode 1 下增删任务 ⇒ 二次确认（R3：分母与任务条数耦合）。
///
/// 判据真源复用领域纯函数（[upscaleAllowed] / [clampedGoalAfterDecrease]），
/// 本文件不造第二套数值判据；UI 只负责弹确认与编排写调用。
library wish_task_editor;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 目标值变更的判定结果（纯函数，便于单测独立断言护栏）。
class GoalChangeVerdict {
  const GoalChangeVerdict({
    required this.kind,
    this.clampedValue,
    this.reason,
  });

  /// 变更类别。
  final GoalChangeKind kind;
  /// 下调钳制后的值（仅 [GoalChangeKind.decrease] 有值）。
  final int? clampedValue;
  /// 拒绝原因（仅 [GoalChangeKind.rejected] 有值）。
  final String? reason;
}

enum GoalChangeKind {
  unchanged,
  decrease, // 需二次确认 + 钳制
  increase, // 需二次确认
  rejected, // 双重护栏超限，拒绝
}

/// 目标值变更判据（唯一 UI 判定，复用领域护栏函数）。
///
/// - 下调：钳制到 `max(requested, progress)`；若钳制后仍 < 原目标且会触发
///   100%（requested < progress），判 decrease（需二次确认）。
/// - 上调：`upscaleAllowed` 为 false ⇒ rejected（"请分几次调整"）；否则 increase。
GoalChangeVerdict judgeGoalChange({
  required int oldTarget,
  required int requestedTarget,
  required int progressValue,
  String rejectReason = '',
}) {
  if (requestedTarget == oldTarget) {
    return const GoalChangeVerdict(kind: GoalChangeKind.unchanged);
  }
  if (requestedTarget < oldTarget) {
    final int clamped = clampedGoalAfterDecrease(
      requestedTarget: requestedTarget,
      progressValue: progressValue,
    );
    return GoalChangeVerdict(
      kind: GoalChangeKind.decrease,
      clampedValue: clamped,
    );
  }
  // 上调（含 oldTarget == 0 的首次设定不在此路径：首次由调用方直接写）。
  if (oldTarget > 0 &&
      !upscaleAllowed(
        oldTarget: oldTarget,
        requestedTarget: requestedTarget,
        progressValue: progressValue,
      )) {
    return GoalChangeVerdict(
      kind: GoalChangeKind.rejected,
      reason: rejectReason,
    );
  }
  return const GoalChangeVerdict(kind: GoalChangeKind.increase);
}

/// 目标值可选列表（mode 0 / mode 1）—— 判据量由常量暴露的真量生成。
List<int> goalValueChoices(WishGoalMode mode) {
  final int min = mode == WishGoalMode.focusMinutes
      ? kWishGoalFocusMinutesMin
      : kWishGoalTaskCountMin;
  final int max = mode == WishGoalMode.focusMinutes
      ? kWishGoalFocusMinutesMax
      : kWishGoalTaskCountMax;
  final int step = mode == WishGoalMode.focusMinutes ? 10 : 1;
  final List<int> values = <int>[];
  for (int v = min; v <= max; v += step) {
    values.add(v);
  }
  if (values.isEmpty || values.last != max) values.add(max);
  return values;
}

/// 编辑器内的一条任务草稿。
class WishTaskDraft {
  const WishTaskDraft({
    this.id,
    this.name = '',
    this.requiresFocus = true,
    this.minFocusMin = kTaskMinFocusDefault,
    this.repeatRule,
  });

  final String? id;
  final String name;
  final bool requiresFocus;
  final int minFocusMin;
  final String? repeatRule;

  WishTaskDraft copyWith({
    String? name,
    bool? requiresFocus,
    int? minFocusMin,
    Object? repeatRule = _unset,
  }) =>
      WishTaskDraft(
        id: id,
        name: name ?? this.name,
        requiresFocus: requiresFocus ?? this.requiresFocus,
        minFocusMin: minFocusMin ?? this.minFocusMin,
        repeatRule: identical(repeatRule, _unset)
            ? this.repeatRule
            : repeatRule as String?,
      );

  static const Object _unset = Object();
}

/// 「设定目标 + 布置任务」弹层。
///
/// [initialTasks] 为名下已有愿望任务（编辑用）；[onSaved] 在写操作成功后回调
/// （页面刷新）。本 widget 自含 [L10nScope]（弹层挂在根 Navigator 上）。
class WishTaskEditor extends ConsumerStatefulWidget {
  const WishTaskEditor({
    super.key,
    required this.wish,
    this.initialTasks = const <Task>[],
    required this.onSaved,
  });

  final Wish wish;
  final List<Task> initialTasks;
  final VoidCallback onSaved;

  @override
  ConsumerState<WishTaskEditor> createState() => _WishTaskEditorState();
}

class _WishTaskEditorState extends ConsumerState<WishTaskEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late WishGoalMode _mode;
  late int _targetValue;
  final List<WishTaskDraft> _drafts = <WishTaskDraft>[];
  final List<TextEditingController> _nameControllers = <TextEditingController>[];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _mode = widget.wish.targetMode;
    _targetValue = widget.wish.targetValue == 0
        ? (_mode == WishGoalMode.focusMinutes
            ? kWishGoalFocusMinutesDefault
            : kWishGoalTaskCountDefault)
        : widget.wish.targetValue;
    for (final Task task in widget.initialTasks) {
      _drafts.add(WishTaskDraft(
        id: task.id,
        name: task.name,
        requiresFocus: task.requiresFocus,
        minFocusMin: task.minFocusMin,
        repeatRule: task.repeatRule,
      ));
      _nameControllers.add(TextEditingController(text: task.name));
    }
    if (_drafts.isEmpty) {
      _drafts.add(WishTaskDraft(
        requiresFocus: _focusMode ? true : false,
        minFocusMin: kTaskMinFocusDefault,
      ));
      _nameControllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final TextEditingController c in _nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _focusMode => _mode == WishGoalMode.focusMinutes;

  Future<bool> _confirmDecrease(AppLocalizations t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_wish_goal_value_label),
        content: Text(t.parent_wish_goal_decrease_confirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_wish_action_setup),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<bool> _confirmIncrease(AppLocalizations t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_wish_goal_value_label),
        content: Text(t.parent_wish_goal_increase_confirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_wish_action_setup),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 提交：目标页签写 setGoal（若变更），任务页签写新任务 + assignTasks。
  Future<void> _submit() async {
    final AppLocalizations t = l10nOf(context);
    setState(() => _saving = true);
    try {
      final WishOrchestrationService service =
          ref.read(wishOrchestrationServiceProvider);
      // ① 目标（只写一次）—— 首次设定（原值 0）直写；变更走护栏确认。
      if (_targetValue != widget.wish.targetValue || _mode != widget.wish.targetMode) {
        int toWrite = _targetValue;
        if (widget.wish.targetValue > 0 && _targetValue != widget.wish.targetValue) {
          final GoalChangeVerdict verdict = judgeGoalChange(
            oldTarget: widget.wish.targetValue,
            requestedTarget: _targetValue,
            progressValue: widget.wish.progressValue,
            rejectReason: t.parent_wish_goal_upscale_reject,
          );
          switch (verdict.kind) {
            case GoalChangeKind.unchanged:
              break;
            case GoalChangeKind.rejected:
              _error = verdict.reason;
              if (mounted) setState(() => _saving = false);
              return;
            case GoalChangeKind.decrease:
              if (!await _confirmDecrease(t)) {
                if (mounted) setState(() => _saving = false);
                return;
              }
              toWrite = verdict.clampedValue ?? _targetValue;
            case GoalChangeKind.increase:
              if (!await _confirmIncrease(t)) {
                if (mounted) setState(() => _saving = false);
                return;
              }
          }
        }
        await service.setGoal(
          wishId: widget.wish.id,
          mode: _mode,
          targetValue: toWrite,
          now: DateTime.now(),
        );
      }

      // ② 任务：新建草稿任务 → saveTask → assignTasks（写 tasks.wishId）。
      final List<String> newIds = <String>[];
      final List<String> allIds = <String>[
        for (final WishTaskDraft d in _drafts) if (d.id != null) d.id!,
      ];
      for (final WishTaskDraft draft in _drafts) {
        if (draft.id != null) continue; // 已有任务保留归属，不重建。
        final String name = draft.name.trim();
        if (name.isEmpty) continue;
        final String id = const Uuid().v4();
        await ref.read(taskRepositoryProvider).saveTask(Task(
              id: id,
              name: name,
              subject: TaskSubject.general,
              requiresFocus: _focusMode ? true : draft.requiresFocus,
              minFocusMin: draft.minFocusMin,
              sunlightReward: 5,
              repeatRule: draft.repeatRule,
              isCustom: true,
              wishId: widget.wish.id,
            ));
        newIds.add(id);
        allIds.add(id);
      }
      if (allIds.isNotEmpty) {
        await service.assignTasks(
          wishId: widget.wish.id,
          taskIds: allIds,
          now: DateTime.now(),
        );
      }
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  /// mode1 下增删任务需二次确认（R3）。返回是否继续。
  Future<bool> _confirmTaskMutation(AppLocalizations t) async {
    if (_focusMode) return true; // mode0 分母是分钟，与任务条数无关。
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_wish_task_name),
        content: Text(t.parent_wish_task_remove_confirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_wish_action_setup),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addTask() async {
    final AppLocalizations t = l10nOf(context);
    if (_drafts.length >= kWishTaskMaxCount) {
      setState(() => _error = t.parent_wish_task_max(kWishTaskMaxCount));
      return;
    }
    if (!await _confirmTaskMutation(t)) return;
    if (!mounted) return;
    setState(() {
      _drafts.add(WishTaskDraft(
        requiresFocus: _focusMode ? true : false,
        minFocusMin: kTaskMinFocusDefault,
      ));
      _nameControllers.add(TextEditingController());
      _error = null;
    });
  }

  Future<void> _removeTask(int index) async {
    final AppLocalizations t = l10nOf(context);
    if (!await _confirmTaskMutation(t)) return;
    if (!mounted) return;
    setState(() {
      _drafts.removeAt(index);
      _nameControllers.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations t = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(t.parent_wish_editor_title),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TabBar(
                    controller: _tab,
                    tabs: <Widget>[
                      Tab(text: t.parent_wish_tab_goal),
                      Tab(text: t.parent_wish_tab_tasks),
                    ],
                  ),
                  SizedBox(
                    height: 360,
                    child: TabBarView(
                      controller: _tab,
                      children: <Widget>[
                        _goalTab(t),
                        _tasksTab(t),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
                    : Text(t.parent_wish_action_setup),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 「目标」页签：口径下拉 + 目标值下拉（区间真量）。
  Widget _goalTab(AppLocalizations t) {
    final List<int> choices = goalValueChoices(_mode);
    final int value = choices.contains(_targetValue)
        ? _targetValue
        : choices.first;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: <Widget>[
        DropdownButtonFormField<WishGoalMode>(
          isExpanded: true,
          initialValue: _mode,
          decoration: InputDecoration(labelText: t.parent_wish_goal_mode_label),
          items: <DropdownMenuItem<WishGoalMode>>[
            DropdownMenuItem(
              value: WishGoalMode.focusMinutes,
              child: Text(t.wishGoalFocusMinutes),
            ),
            DropdownMenuItem(
              value: WishGoalMode.taskCount,
              child: Text(t.wishGoalTaskCount),
            ),
          ],
          onChanged: (WishGoalMode? v) {
            if (v == null) return;
            setState(() {
              _mode = v;
              final List<int> next = goalValueChoices(v);
              final int def = v == WishGoalMode.focusMinutes
                  ? kWishGoalFocusMinutesDefault
                  : kWishGoalTaskCountDefault;
              _targetValue = next.contains(def) ? def : next.first;
            });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: t.parent_wish_goal_value_label),
          items: <DropdownMenuItem<int>>[
            for (final int v in choices)
              DropdownMenuItem<int>(value: v, child: Text('$v')),
          ],
          onChanged: (int? v) => v == null ? null : setState(() => _targetValue = v),
        ),
        const SizedBox(height: 12),
        Text(t.wishPlanTogetherHint, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  /// 「任务」页签：任务列表（名称 / 专注型开关 / 单次时长 / 重复）。
  Widget _tasksTab(AppLocalizations t) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            itemCount: _drafts.length,
            itemBuilder: (BuildContext context, int index) {
              return _taskRow(t, index, _drafts[index]);
            },
          ),
        ),
        OutlinedButton.icon(
          key: const Key('parent_wish_task_add'),
          onPressed: _addTask,
          icon: const Icon(Icons.add),
          label: Text(t.parent_wish_task_add),
        ),
      ],
    );
  }

  Widget _taskRow(AppLocalizations t, int index, WishTaskDraft draft) {
    final int idx = index;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: <Widget>[
            TextField(
              key: Key('parent_wish_task_name_$idx'),
              controller: _nameControllers[idx],
              decoration: InputDecoration(labelText: t.parent_wish_task_name),
              onChanged: (String v) =>
                  _drafts[idx] = draft.copyWith(name: v),
            ),
            if (!_focusMode)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.parent_wish_task_focus),
                value: draft.requiresFocus,
                onChanged: (bool v) => setState(
                    () => _drafts[idx] = draft.copyWith(requiresFocus: v)),
              ),
            if (draft.requiresFocus || _focusMode)
              Row(
                children: <Widget>[
                  Text(t.parent_wish_task_minutes),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: draft.minFocusMin,
                    items: <DropdownMenuItem<int>>[
                      for (final int m in <int>[5, 10, 15, 20, 30, 45, 60])
                        DropdownMenuItem<int>(value: m, child: Text('$m')),
                    ],
                    onChanged: (int? v) => v == null
                        ? null
                        : setState(() =>
                            _drafts[idx] = draft.copyWith(minFocusMin: v)),
                  ),
                ],
              ),
            Text(
              _focusMode ? t.parent_wish_focus_desc : t.parent_wish_manual_desc,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _removeTask(idx),
                child: Text(t.parent_wish_reject),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
