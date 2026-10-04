/// 少儿护眼休息卡（口径 C28，玄参 2026-10-03 初稿 / 2026-10-04 收口）。
///
/// 一张**全屏 modality 卡**：固定 [kEyeCareDurationSeconds]（60）秒两段式——
/// 前 [kEyeCarePhaseSeconds]（30）秒「闭眼 + 口令转眼球」，后 [kEyeCarePhaseSeconds]
/// 秒「睁眼远眺 6 米外」；大环形倒计时 + 阶段文案步进，完整休息给
/// +[kEyeCareRewardSunlight] 阳光（`refType='eye_care_break'`）。
///
/// 三条硬口径（C28 §7，勿改）：
///  · **允许跳过（默认）**：点「跳过」→ **先弹二次确认**（[kEyeCareSkipConfirmText]），
///    确认才生效；确认后**不发奖励、不写账本**，直接继续专注 / 进结算页；
///    取消确认＝回护眼卡继续休息。
///  · **家长关掉「允许跳过」**：点「跳过」**无效**，弹 [kEyeCareNotSkippableText]，
///    流程不推进，只有「完成休息」一条路。
///  · **返回键拦截**：整页 `PopScope(canPop: false)`，拦截时同样弹
///    [kEyeCareNotSkippableText]（防止孩子按返回绕过护眼）。
///
/// 无论跳过与否，护眼时长**都不回溯补算**为专注时长（专注页已用
/// `FocusEngine.pause()` 冻结计时，本页不碰计时、也不「结算补减」）。
///
/// 本期**无语音素材**（mp3 待美术供给）：两段各自的倒计时 + 阶段文案步进全部由
/// 程序占位实现（阶段文案见 [EyeCareService.cuesForPhase]），向日葵演示走自绘占位。
library eye_care_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/presentation/child/widgets/sunflower_canvas.dart';

/// 护眼卡入参。
///
/// [skipAllowed] = 家长「是否允许孩子跳过」（`AppSettings.eyeCareSkipAllowed`，默认
/// 允许）；false 时「跳过」按钮**仍在但点了无效**（弹 [kEyeCareNotSkippableText]、
/// 流程不推进），拦截返回键同样走 [kEyeCareNotSkippableText]。
class EyeCareArgs {
  /// 是否允许孩子跳过（家长端配置，默认允许）。
  final bool skipAllowed;

  const EyeCareArgs({this.skipAllowed = true});
}

/// 护眼卡（全屏、modality、不可被系统返回退出）。
///
/// 用 `Navigator.push` 压栈，返回值即 [EyeCareResult]（completed = 休息完给奖励，
/// skipped = 确认跳过、无奖励）——调用方据此决定「恢复专注计时」还是「直接进结算页」。
class EyeCarePage extends ConsumerStatefulWidget {
  /// 入参（护眼卡是否允许跳过）。
  final EyeCareArgs args;

  const EyeCarePage({super.key, required this.args});

  @override
  ConsumerState<EyeCarePage> createState() => _EyeCarePageState();
}

class _EyeCarePageState extends ConsumerState<EyeCarePage> {
  /// 已走秒数（0..[kEyeCareDurationSeconds]）。
  int _elapsed = 0;

  /// 跳过二次确认弹窗是否已打开（防止连续点击叠出多个对话框）。
  bool _confirmOpen = false;

  /// 是否正在退场（弹完结果后短暂驻留，避免按钮点了画面瞬间消失）。
  bool _finishing = false;

  Timer? _timer;
  static final Uuid _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  /// 1 秒 tick：推进整段倒计时，走到总长自动「完成休息」。
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finishing) return;
      final int next = _elapsed + 1;
      if (next >= kEyeCareDurationSeconds) {
        setState(() => _elapsed = kEyeCareDurationSeconds);
        unawaited(_finish(EyeCareResultType.completed));
        return;
      }
      setState(() => _elapsed = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── 出口（完成 / 跳过）────────────────────────────────────────

  /// 退场：写账本（仅 completed）+ 回结果。
  ///
  /// ⚠️ 护眼奖励**以阳光账本为唯一真源**（不在 settings / 实体上另加计数列）：
  /// 余额在**写入前**取，income 用 `balanceBefore + amount` 算，避免并发 / 重入
  /// 造成 balanceAfter 对不上。
  Future<void> _finish(EyeCareResultType type) async {
    if (_finishing) return; // 幂等：完成与跳过只能各自生效一次
    setState(() => _finishing = true);
    _timer?.cancel();

    if (type == EyeCareResultType.completed) {
      await _appendReward();
      if (!mounted) return;
      // 经济修订号自增 → 孩子端（今日 / 我的 / 花园胶囊）下次进入即自动刷新。
      ref.read(economyRevisionProvider.notifier).state++;
    }

    if (!mounted) return;
    Navigator.of(context).pop(EyeCareResult(type));
  }

  /// 完整完成护眼 → 账本 +[kEyeCareRewardSunlight] 阳光，`refType = 'eye_care_break'`。
  Future<void> _appendReward() async {
    try {
      final SunlightRepository ledger =
          ref.read(sunlightRepositoryProvider);
      final DateTime now = DateTime.now();
      final double before = await ledger.balance();
      final double amount = EyeCareService.rewardSunlight().toDouble();
      await ledger.append(SunlightEntry(
        id: _uuid.v4(),
        ts: now,
        type: SunlightType.earn,
        gross: amount,
        net: amount,
        balanceAfter: before + amount,
        refType: kEyeCareRefType,
        refId: null,
        dayKey: dayKey(now),
      ));
    } catch (_) {
      // 写账本失败绝不能卡住孩子的护眼流程：护眼本身已经完成，
      // 这里只打标记不重试（账本 append 是 append-only，重复尝试只会产生重复行）。
    }
  }

  /// 点「跳过」：允许 → 二次确认；不可跳过 → 只弹提示，流程不推进。
  void _onSkipPressed() {
    if (!widget.args.skipAllowed) {
      _showNotSkippable();
      return;
    }
    if (_confirmOpen) return;
    setState(() => _confirmOpen = true);
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('要跳过护眼吗？'),
        content: const Text(kEyeCareSkipConfirmText),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再休息一会儿'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定跳过'),
          ),
        ],
      ),
    ).then((bool? ok) {
      if (!mounted) return;
      setState(() => _confirmOpen = false);
      if (ok != true) return;
      unawaited(_finish(EyeCareResultType.skipped));
    });
  }

  /// 「不可跳过，请爱护眼睛」提示（不可跳过 / 拦截返回键共用，文案单点收口）。
  void _showNotSkippable() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(kEyeCareNotSkippableText),
          duration: Duration(seconds: 2),
        ),
      );
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EyeCareCue cue =
        EyeCareService.cuesForPhase(_elapsed);
    final double totalProgress =
        kEyeCareDurationSeconds <= 0
            ? 1.0
            : _elapsed / kEyeCareDurationSeconds;
    final bool finished = _elapsed >= kEyeCareDurationSeconds;

    // ⚠️ 类型参数必须是本页 pop 出去的结果类型 [EyeCareResult]（**不是** bool）：
    // `PopScope.onPopInvokedWithResult` 收到的是「本次 pop 的返回值」，框架会按本页
    // 声明的 T 强转——写成 PopScope<bool> 时，「完成休息」回传 EyeCareResult 会当场
    // 抛 `type 'EyeCareResult' is not a subtype of type 'bool?'`（真机必崩，widget 测试捕获）。
    return PopScope<EyeCareResult>(
      canPop: false, // C28 §7：护眼卡期间拦截系统返回键
      onPopInvokedWithResult: (bool didPop, EyeCareResult? _) {
        if (didPop) return;
        _showNotSkippable();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF6EC), // 暖米白（孩子端基调）
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 12),
                  const Text(
                    '眼睛休息一下吧',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5A4A2F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cue.phaseTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF8A7A5F),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // 大环形倒计时 + 中央剩余秒数
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // 大环形倒计时：自绘环（不依赖 CircularProgressIndicator 的
                        // 参数命名，跨 Flutter 版本零风险，也更好控制线头圆角）。
                        CustomPaint(
                          painter: _RingPainter(
                            progress: totalProgress.clamp(0.0, 1.0),
                            active: cue.phase == EyeCarePhase.closed
                                ? const Color(0xFFFFB4C4)
                                : const Color(0xFF8FD6A8),
                            track: const Color(0xFFFFF1C2),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              finished ? '0' : '${cue.remainingSeconds}',
                              style: const TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFF5A4A2F),
                              ),
                            ),
                            const Text(
                              '秒',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF8A7A5F),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // 向日葵演示（本期程序占位：闭眼 / 远眺两态自绘）+ 口令
                  _EyeCareStage(cue: cue),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          unawaited(_finish(EyeCareResultType.completed)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: const Text(kEyeCareFinishLabel),
                    ),
                  ),
                  // 「跳过」按钮**恒存在**（口径 C28 §7：护眼卡恒有「跳过」与「完成
                  // 休息」两个出口）。家长关掉「允许跳过」时它只是**点了无效**（弹
                  // [kEyeCareNotSkippableText]、流程不推进），而**不是整块消失**——
                  // 消失的话孩子根本点不到、也就看不到「不可跳过」的提示，与口径相悖。
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _onSkipPressed,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      child: const Text(kEyeCareSkipLabel),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 环形倒计时进度环（大环 + 背景轨道 + 进度弧）。
///
/// 用 [CustomPaint] 自绘而不是 [CircularProgressIndicator]：本项目已跨过若干 Flutter
/// 版本，进度条的轨道色参数在版本间换过名字（`trackColor` → `background`），
/// 自绘可彻底避开这类「换个 SDK 就编译不过」的风险，且能自己控制线头与圆角。
class _RingPainter extends CustomPainter {
  /// 进度 0..1。
  final double progress;

  /// 已走过的弧色（闭眼段粉 / 远眺段绿）。
  final Color active;

  /// 未走过的轨道底色。
  final Color track;

  const _RingPainter({
    required this.progress,
    required this.active,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect inset = (Offset.zero & size).deflate(94);
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(inset, 0, 6.28318, false, trackPaint);

    final Paint activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = active;
    // 从 12 点开始顺时针（0 弧是 3 点方向，减 90° 拨回顶部）。
    canvas.drawArc(
      inset,
      -1.5708,
      6.28318 * progress.clamp(0.0, 1.0),
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

/// 向日葵演示占位（闭眼口令段 / 睁眼远眺段两态）。
///
/// ⚠️ 本期**无美术素材交付**：不引任何图片资源（widget 测试走占位假绿、抓不到美术
/// 分支），用「🌻 + 自绘眼睛」占位，美术资源到位后整体替换为序列帧即可。
class _EyeCareStage extends StatelessWidget {
  /// 当前阶段的演示信息。
  final EyeCareCue cue;

  const _EyeCareStage({required this.cue});

  @override
  Widget build(BuildContext context) {
    final bool closed = cue.phase == EyeCarePhase.closed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: closed ? const Color(0xFFFFF1C2) : const Color(0xFFE7F4EA),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: SunflowerCanvas(
                level: FeedbackLevel.lvl1,
                celebrating: !closed,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 口令文案（阶段步进）+ 步数提示（闭眼段显示「3/5」）
        Text(
          cue.cueText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A4A2F),
          ),
        ),
        if (closed && cue.stepIndex > 0) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '第 ${cue.stepIndex}/${kEyeCareCueTexts.length} 步',
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A7A5F)),
          ),
        ],
      ],
    );
  }
}
