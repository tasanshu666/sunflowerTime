/// 家长天地顶部「当前孩子」胶囊条（C90 期 1，玄参 2026-10-17 拍板）。
///
/// 口径（详见 tables.dart `ChildProfiles` 注释）：
///  · 设备同一时刻只有一个「当前孩子」；切换 / 新建入口**只在家长天地**（本有
///    家长 PIN 门），孩子端零改动；
///  · 点胶囊条 → **原地下拉菜单**（玄参反馈：不要从屏幕底部弹抽屉）；菜单
///    **宽度与胶囊条对齐**、圆角 / 描边同胶囊一套（玄参反馈：别丑）；
///  · 每行：名字 + 年龄段小字（整行点击 = 切换，当前项打勾）+ 行尾**编辑 / 删除**
///    小按钮（玄参 2026-10-17 追加）；
///  · 编辑 = 对话框预填（改名 / 调年龄段），**不受门控限制**（非新增）；
///  · 删除 = 确认对话框 + **家长 PIN 复核**（玄参拍板）：PIN 错 → 内联报错不关
///    弹窗；最后 1 个档案不可删（居中轻提示）；删的是当前孩子 → 自动切到剩余
///    第一个。🔴 兑换历史等数据期 2 分离，本期删除只摘档案行；
///  · 新建 = 对话框（名字 + 年龄段三档**固定尺寸卡片纵向排列**，文案：低年级 ·
///    小于 8 岁 / 中年级 · 8–12 岁 / 高年级 · 大于 12 岁）；提交后经矩阵单点
///    `quotaAllowsAdd` 判配额（免费 1 / 买断 3）：免费档不过 → `showPremiumUpsell`
///    弹升级；**买断档**不过 → 居中轻提示「最多支持 3 个孩子账户」。🔴 不创建、
///    绝不擅自删任何已存档案（C69），按钮照常可点（C62：不可点 ≠ 静默失败）；
///  · 切换 / 新建 / 编辑 / 删除完成 → **屏幕正中轻提示 1 秒自动淡出**（玄参反馈：
///    底部 SnackBar 太不显眼）。
///  · 数据隔离期 2 实施：本期切换只影响后续兑换记录落哪个 childId。
///
/// ⚠️ 本文件含门控 token（FeatureKey / quotaAllowsAdd / entitlementProvider /
/// showPremiumUpsell），已登记进 `test/qa/entitlement_gate_guard_test.dart`
/// 白名单（判定仍走矩阵单点，无 isPremium 散落）。
library child_profile_bar;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

/// 年龄段展示名（**C90-C 修订**（玄参 2026-10-18 拍板「12 岁归中」）：
/// 低 ≤8 / 中 9–12 / 高 ≥13；与 `tierForAge` 新分界一致）。
String _tierLabel(AgeTier tier) {
  switch (tier) {
    case AgeTier.low:
      return '低年级 · 8 岁及以下';
    case AgeTier.mid:
      return '中年级 · 9–12 岁';
    case AgeTier.high:
      return '高年级 · 13 岁及以上';
  }
}

/// 「当前孩子」胶囊条：人形图标 + 当前孩子名 + 下拉箭头，点开原地下拉菜单。
class ChildProfileBar extends ConsumerStatefulWidget {
  const ChildProfileBar({super.key});

  @override
  ConsumerState<ChildProfileBar> createState() => _ChildProfileBarState();
}

class _ChildProfileBarState extends ConsumerState<ChildProfileBar> {
  /// 「新建孩子」菜单项的哨兵值（菜单 value 用孩子 id，此值不与 id 冲突）。
  static const String _kCreateAction = '__create__';

  /// 胶囊条尺寸测量（菜单宽度与其对齐，玄参反馈）。
  final GlobalKey _barKey = GlobalKey();

  List<ChildProfile> _profiles = const <ChildProfile>[];
  ChildProfile? _current;

  /// 当前在屏的居中轻提示（新提示顶掉旧提示，避免叠加）。
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    // 页面销毁时清掉在屏提示（Overlay 条目不随 State 自动移除）。
    _toastEntry?.remove();
    _toastEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 档案修订号变化（新建 / 切换 / 编辑 / 删除成功）→ 重拉档案列表与当前孩子。
    ref.listen<int>(childProfileRevisionProvider, (_, __) => _reload());

    final String name = _current?.name ?? kDefaultChildNickname;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      // ⚠️ 不用 PopupMenuButton：它的 constraints 必须在 build 期给死，而胶囊
      //    首帧还没量出尺寸（"Cannot get size during build"）。改为点按后用
      //    showMenu + 实测 RenderBox 定位，菜单宽度在打开瞬间与胶囊对齐。
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openMenu,
          child: Container(
            key: _barKey,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 胶囊条实测宽度（菜单对齐用；未挂树时回退 280）。
  double get _barWidth => _barKey.currentContext?.size?.width ?? 280.0;

  /// 打开原地下拉菜单：锚在胶囊正下方，宽度 = 胶囊实测宽度（玄参反馈对齐）。
  Future<void> _openMenu() async {
    final BuildContext? barCtx = _barKey.currentContext;
    if (barCtx == null || !mounted) return;
    final RenderObject? ro = barCtx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;

    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final Offset anchor =
        ro.localToGlobal(ro.size.bottomLeft(Offset.zero), ancestor: overlayBox);
    final Offset anchorEnd =
        ro.localToGlobal(ro.size.bottomRight(Offset.zero), ancestor: overlayBox);
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(anchor + const Offset(0, 6),
          anchorEnd + const Offset(0, 6)),
      Offset.zero & overlayBox.size,
    );

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      items: _buildMenuItems(context),
      // 🔴 样式与胶囊条同一套：同圆角 / 描边、surface 底 + 去 M3 色染
      //    （玄参反馈：菜单别丑、宽度对齐）。
      color: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      constraints: BoxConstraints(minWidth: _barWidth, maxWidth: _barWidth),
    );
    if (selected == null || !mounted) return;
    await _onMenuSelected(selected);
  }

  /// 重拉档案列表 + 当前孩子（fire-and-forget；调用点均为用户动作后）。
  Future<void> _reload() async {
    final List<ChildProfile> list =
        await ref.read(childProfileRepositoryProvider).children();
    final ChildProfile? current =
        await ref.read(accountServiceProvider).currentProfile();
    if (!mounted) return;
    setState(() {
      _profiles = list;
      _current = current ?? (list.isEmpty ? null : list.first);
    });
  }

  /// 下拉菜单：档案列表（行尾编辑 / 删除）+ 分隔线 +「新建孩子」。
  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final Color hint = Theme.of(context).hintColor;
    return <PopupMenuEntry<String>>[
      for (final ChildProfile p in _profiles)
        PopupMenuItem<String>(
          value: p.id,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(p.name, style: const TextStyle(fontSize: 15)),
                      Text(
                        _tierLabel(p.ageTier),
                        style: TextStyle(fontSize: 12, color: hint),
                      ),
                    ],
                  ),
                ),
                _MenuIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: '编辑',
                  color: hint,
                  onTap: () => _onEdit(p),
                ),
                _MenuIconButton(
                  icon: Icons.delete_outline,
                  tooltip: '删除',
                  color: hint,
                  onTap: () => _onDelete(p),
                ),
                if (p.id == _current?.id)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.check, color: Color(0xFF2E7D32), size: 20),
                  ),
              ],
            ),
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: _kCreateAction,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.add),
              SizedBox(width: 8),
              Text('新建孩子'),
            ],
          ),
        ),
      ),
    ];
  }

  /// 菜单选中回调：孩子 id → 切换；哨兵值 → 新建流程。
  ///
  /// （行尾编辑 / 删除按钮由内部 GestureDetector 拦截，不走本回调。）
  Future<void> _onMenuSelected(String value) async {
    if (value == _kCreateAction) {
      await _openCreateFlow();
      return;
    }
    for (final ChildProfile p in _profiles) {
      if (p.id == value) {
        await _switchTo(p);
        return;
      }
    }
  }

  /// 菜单路由切换 / 编辑 / 删除动作前先收起菜单（对话胶囊条仍在，不闪）。
  void _dismissMenu() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 行尾「编辑」：先收菜单 → 预填对话框 → 更新落库（不受门控，非新增）。
  void _onEdit(ChildProfile p) {
    _dismissMenu();
    _openEditFlow(p);
  }

  /// 行尾「删除」：先收菜单 → PIN 复核确认 → 删除（兜底见 [_openDeleteFlow]）。
  void _onDelete(ChildProfile p) {
    _dismissMenu();
    _openDeleteFlow(p);
  }

  /// 切换当前孩子：switchTo（校验存在 + 写 SP）→ 修订号自增 → 居中轻提示。
  Future<void> _switchTo(ChildProfile p) async {
    if (p.id == _current?.id) return; // 点的就是当前孩子，无动作
    await ref.read(accountServiceProvider).switchTo(p.id);
    ref.read(childProfileRevisionProvider.notifier).state++;
    await _reload();
    if (!mounted) return;
    _showCenterToast('已切换到「${p.name}」');
  }

  /// 新建孩子流程：对话框收名字 + 年龄段 → 矩阵单点判配额 → 创建或提示。
  Future<void> _openCreateFlow() async {
    final _CreateResult? result = await showDialog<_CreateResult>(
      context: context,
      builder: (_) => _CreateChildDialog.create(
        initialTier: _current?.ageTier ?? AgeTier.high,
      ),
    );
    if (result == null || !mounted) return;

    // 🔴 门控单点：免费 1 / 买断 3，只拦新增（C69）。
    final EntitlementTier tier = ref.read(entitlementProvider).tier;
    if (!quotaAllowsAdd(
        FeatureKey.multiChildProfile, tier, _profiles.length)) {
      // 免费档 → 弹升级；买断档已到顶 → 居中轻提示（不再「升级解锁」，玄参反馈）。
      if (tier == EntitlementTier.free) {
        showPremiumUpsell(context, FeatureKey.multiChildProfile);
      } else {
        _showCenterToast('最多支持 $kPremiumChildProfileCount 个孩子账户');
      }
      return;
    }

    final ChildProfile created = await ref
        .read(accountServiceProvider)
        .createChild(result.name, result.tier);
    ref.read(childProfileRevisionProvider.notifier).state++;
    await _reload();
    if (!mounted) return;
    _showCenterToast('已添加「${created.name}」');
  }

  /// 编辑孩子流程：预填对话框 → 更新落库（改名 / 调年龄段，不受门控）。
  Future<void> _openEditFlow(ChildProfile p) async {
    final _CreateResult? result = await showDialog<_CreateResult>(
      context: context,
      builder: (_) => _CreateChildDialog.edit(existing: p),
    );
    if (result == null || !mounted) return;

    await ref
        .read(childProfileRepositoryProvider)
        .update(p.id, name: result.name, ageTier: result.tier);
    // C90 期 2 第二批：改的是**当前孩子** → 刷新 AccountService 缓存的活跃档案
    //（switchTo 重读仓储，使孩子端年龄段 / 「我的」页展示即时跟档；id 不变，
    // 写 SP 幂等无害）。
    if (p.id == ref.read(accountServiceProvider).childId) {
      await ref.read(accountServiceProvider).switchTo(p.id);
    }
    ref.read(childProfileRevisionProvider.notifier).state++;
    await _reload();
    if (!mounted) return;
    _showCenterToast('已更新「${result.name}」');
  }

  /// 删除孩子流程（玄参拍板：家长 PIN 复核）：
  /// ① 最后 1 个不可删（居中提示）；② PIN 错 → 内联报错不关弹窗；
  /// ③ 删的是当前孩子 → 自动切到剩余第一个。
  Future<void> _openDeleteFlow(ChildProfile p) async {
    if (_profiles.length <= 1) {
      _showCenterToast('至少保留一个孩子档案');
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(
        name: p.name,
        onVerify: (String pin) =>
            ref.read(secureStoreProvider).verify(pin),
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(childProfileRepositoryProvider).deleteById(p.id);
    if (p.id == _current?.id) {
      // 删的是当前孩子 → 自动切到剩余第一个（switchTo 内部校验存在 + 写 SP）。
      final List<ChildProfile> rest =
          await ref.read(childProfileRepositoryProvider).children();
      if (rest.isNotEmpty) {
        await ref.read(accountServiceProvider).switchTo(rest.first.id);
      }
    }
    ref.read(childProfileRevisionProvider.notifier).state++;
    await _reload();
    if (!mounted) return;
    _showCenterToast('已删除「${p.name}」');
  }

  /// 屏幕正中轻提示：显示 1 秒后 250ms 淡出、随后自摘（新提示顶掉旧提示）。
  void _showCenterToast(String message) {
    _toastEntry?.remove();
    _toastEntry = null;
    final OverlayEntry entry = OverlayEntry(
      builder: (_) => _CenterToast(
        message: message,
        onExpired: () {
          _toastEntry?.remove();
          _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

/// 菜单行尾小按钮（编辑 / 删除）：拦截点击不触发整行「切换」，热区 40×40。
class _MenuIconButton extends StatelessWidget {
  const _MenuIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// 新建 / 编辑对话框的提交结果（本地 UI 类型，不出本文件）。
class _CreateResult {
  const _CreateResult(this.name, this.tier);
  final String name;
  final AgeTier tier;
}

/// 新建 / 编辑孩子对话框：名字输入 + 年龄段三档**固定尺寸卡片纵向排列**（选中高亮）。
///
/// 只做**收集**：配额判定与落库都在 [_ChildProfileBarState] 的流程方法里
///（门控判定必须经矩阵单点，不在对话框里散落）。
class _CreateChildDialog extends StatefulWidget {
  const _CreateChildDialog.create({required this.initialTier})
      : initialName = null,
        isEdit = false;

  // ⚠️ 不能标 const：初始化式解引用了参数 `existing`（const 构造器只允许
  //    potentially-const 表达式）。
  // ignore: prefer_const_constructors_in_immutables
  _CreateChildDialog.edit({required ChildProfile existing})
      : initialName = existing.name,
        initialTier = existing.ageTier,
        isEdit = true;

  final String? initialName;
  final AgeTier initialTier;
  final bool isEdit;

  @override
  State<_CreateChildDialog> createState() => _CreateChildDialogState();
}

class _CreateChildDialogState extends State<_CreateChildDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName ?? '');
  late AgeTier _tier = widget.initialTier;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? '编辑孩子' : '新建孩子'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: kChildNicknameMaxLength,
            decoration: const InputDecoration(
              labelText: '孩子名字',
              hintText: '比如：小向日葵',
            ),
          ),
          const SizedBox(height: 4),
          // 三档卡片：纵向并列、固定尺寸（同宽 48 高）、选中高亮（玄参反馈）。
          for (final AgeTier t in AgeTier.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: Material(
                  color: _tier == t
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _tier = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _tier == t
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _tierLabel(t),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: _tier == t
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (_tier == t)
                            Icon(
                              Icons.check,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final String name = _name.text.trim();
            if (name.isEmpty) return; // 空名不提交
            Navigator.of(context).pop(_CreateResult(name, _tier));
          },
          child: Text(widget.isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 删除确认对话框：风险提示 + **家长 PIN 复核**（玄参拍板）。
///
/// PIN 错 → 内联报错、弹窗不关；PIN 对 → `pop(true)` 交宿主落库。
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({
    required this.name,
    required this.onVerify,
  });

  final String name;

  /// PIN 校验回调（由宿主注入，读 `secureStoreProvider`）。
  final Future<bool> Function(String pin) onVerify;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final TextEditingController _pin = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String pin = _pin.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = '请输入家长 PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await widget.onVerify(pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'PIN 不正确，请重试';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('删除「${widget.name}」？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '删除后该孩子的档案设置将被移除，且无法恢复。',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            focusNode: _pinFocus,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '家长 PIN',
              errorText: _error,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy ? null : _submit,
          child: const Text('删除'),
        ),
      ],
    );
  }
}

/// 屏幕正中轻提示：1 秒后淡出、淡出完自摘（C90 期 1，玄参反馈）。
///
/// 挂在根 Overlay、`IgnorePointer` 不挡交互；不随页面路由销毁（胶囊条常驻）。
class _CenterToast extends StatefulWidget {
  const _CenterToast({required this.message, required this.onExpired});

  final String message;

  /// 淡出动画结束后回调（宿主移除 OverlayEntry）。
  final VoidCallback onExpired;

  @override
  State<_CenterToast> createState() => _CenterToastState();
}

class _CenterToastState extends State<_CenterToast> {
  static const Duration _kHold = Duration(milliseconds: 1000);
  static const Duration _kFade = Duration(milliseconds: 250);

  bool _visible = false;
  Timer? _holdTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    // 首帧后再置 true，保证淡入动画生效。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _holdTimer = Timer(_kHold, () {
      if (mounted) setState(() => _visible = false);
    });
    // 淡出完成后自摘（留 50ms 余量防边界抖动）。
    _removeTimer = Timer(_kHold + _kFade + const Duration(milliseconds: 50),
        widget.onExpired);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _kFade,
            child: Material(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
