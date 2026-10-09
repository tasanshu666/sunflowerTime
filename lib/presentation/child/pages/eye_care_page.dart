/// 少儿护眼休息卡（口径 C28，玄参 2026-10-03 初稿 / 2026-10-04 收口 /
/// 2026-10-05 素材定稿接入 / 2026-10-09 C43 单段素材改版）。
///
/// 一张**全屏 modality 卡**：按 [kEyeCarePlaylist]（C43 起恒为**单段**：640 帧
/// WebP + 单配音 63.974s，玄参把 5 段素材剪辑拼为 1 段、段间过渡更丝滑）播放
/// 「序列帧 + 配音」——**帧速 = 帧数 ÷ 音频时长**（项目既有契约），音频经
/// [AudioService.playSfx]（受「音效」开关控制）。完整休息给
/// +[kEyeCareRewardSunlight] 阳光（`refType='eye_care_break'`）。
///
/// ⚠️ C43 播放器预热已改**滑动窗口**（640 帧 × 2.07MB ≈ 1.3GB 禁止整组预热），
/// 页面侧的「预解码下一槽位」逻辑随 7 槽位播放列表一并移除（单段无下一槽）。
///
/// 三条硬口径（C28 §7，勿改）：
///  · **允许跳过（默认）**：点「跳过」→ **先弹二次确认**（[kEyeCareSkipConfirmText]），
///    确认才生效；确认后**不发奖励、不写账本**，直接继续专注 / 进结算页；
///    取消确认＝回护眼卡继续休息。
///  · **家长关掉「允许跳过」**：点「跳过」**无效**，弹 [kEyeCareNotSkippableText]，
///    流程不推进，只有走完流程一条路。
///  · **返回键拦截**：整页 `PopScope(canPop: false)`，拦截时同样弹
///    [kEyeCareNotSkippableText]（防止孩子按返回绕过护眼）。
///
/// 第四条口径（玄参 2026-10-08）：**主按钮定名「跳过护眼休息」**——自然走完时系统
/// 自动收口进下一界面，主按钮的实际语义就是提前结束＝跳过：没走完就手点＝视同跳过，
/// 弹 [kEyeCareEarlyFinishTitle] 二次确认（明示无奖励 + 爱护眼睛提示），确认后按
/// skipped 处理（不发奖励）；家长禁跳时同样弹 [kEyeCareNotSkippableText] 不推进。
/// 只有自然走完（末槽播放回调 / 兜底保险丝）才是真正的 completed 发奖励。
///
/// 无论跳过与否，护眼时长**都不回溯补算**为专注时长（专注页已用
/// `FocusEngine.pause()` 冻结计时，本页不碰计时、也不「结算补减」）。
library eye_care_page;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

/// 护眼卡入参。
///
/// [skipAllowed] = 家长「是否允许孩子跳过」（`AppSettings.eyeCareSkipAllowed`，默认
/// 允许）；false 时「跳过」按钮**仍在但点了无效**（弹 [kEyeCareNotSkippableText]、
/// 流程不推进），拦截返回键同样走 [kEyeCareNotSkippableText]。
///
/// [source] = 触发来源（场内 / 场末，玄参 2026-10-09），随护眼记录落库，
/// 供家长报告区分「场内护眼 / 场末护眼」。
class EyeCareArgs {
  /// 是否允许孩子跳过（家长端配置，默认允许）。
  final bool skipAllowed;

  /// 触发来源（默认场内；结算页调用必须显式传 [EyeCareSource.sessionEnd]）。
  final EyeCareSource source;

  const EyeCareArgs({
    this.skipAllowed = true,
    this.source = EyeCareSource.inSession,
  });
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
  /// 当前播放槽位（0..[kEyeCarePlaylist].length-1）。
  int _slot = 0;

  /// 已走毫秒（**仅用于「还剩 N 秒」标签**；槽位推进由播放器回调驱动，与音频同源）。
  int _elapsedMs = 0;

  /// 跳过二次确认弹窗是否已打开（防止连续点击叠出多个对话框）。
  bool _confirmOpen = false;

  /// 护眼流程是否已**自然走完**（末槽播放回调触发收口前置位）。
  ///
  /// 玄参 2026-10-08 新口径：没走完就手点「完成休息」**不能**按完成发奖励——
  /// 必须二次确认、确认后按跳过处理（无奖励）。只有自然走完的那条收口路径
  /// （`_onSlotComplete` 末槽 / 兜底保险丝）才是真正的 completed。
  bool _flowPlayedOut = false;

  /// 是否正在退场（弹完结果后短暂驻留，避免按钮点了画面瞬间消失）。
  bool _finishing = false;

  Timer? _timer;
  static const Uuid _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    // 单段配音（initState 里 ref 仍可用；dispose 里才禁用 ref——本项目 Riverpod 铁律）。
    ref.read(audioServiceProvider).playSfx(AudioCue.eyeCare);
    // 1s tick：只刷新「还剩 N 秒」标签 + 兜底保险丝（播放器回调才是推进正源）。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _finishing) return;
    setState(() => _elapsedMs += 1000);
    // 兜底保险丝：正常应永远走不到（播放器回调先到）；万一序列帧播放器异常卡死，
    // 超过列表总长 + 10s 仍要放孩子出去，别把人锁死在护眼卡里。
    if (_elapsedMs >= kEyeCarePlaylistTotalMs + 10000) {
      unawaited(_finish(EyeCareResultType.completed));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── 播放收口 ──────────────────────────────────────────────────

  /// 播放完毕（[FrameSequencePlayer.onComplete]，与音频同时长 → 天然同步）。
  ///
  /// C43 起播放列表恒为单段：播完 = 自然走完，直接收口发奖励。
  void _onSlotComplete() {
    if (!mounted || _finishing) return;
    _flowPlayedOut = true; // 自然走完 → 「完成休息」按钮此后按 completed 处理
    unawaited(_finish(EyeCareResultType.completed));
  }

  // ── 出口（完成 / 跳过）────────────────────────────────────────

  /// 退场：写账本（仅 completed）+ 写护眼记录（完成 / 跳过都记）+ 回结果。
  ///
  /// ⚠️ 护眼奖励**以阳光账本为唯一真源**（不在 settings / 实体上另加计数列）：
  /// 余额在**写入前**取，income 用 `balanceBefore + amount` 算，避免并发 / 重入
  /// 造成 balanceAfter 对不上。
  ///
  /// 护眼记录（`eye_care_logs` 表，玄参 2026-10-09）：完成 / 跳过**都落一行**，
  /// 记录实际观看秒数与触发来源 —— 补齐账本没有的「跳过」与「时长」两个维度，
  /// 供家长报告统计；写失败与账本同纪律：不重试、不卡流程。
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

    unawaited(_appendEyeCareLog(type));

    if (!mounted) return;
    Navigator.of(context).pop(EyeCareResult(type));
  }

  /// 落一行护眼记录（完成 / 跳过都记；失败静默，不打断孩子退场）。
  Future<void> _appendEyeCareLog(EyeCareResultType type) async {
    try {
      final DateTime now = DateTime.now();
      await ref.read(eyeCareLogRepositoryProvider).append(EyeCareLog(
            id: _uuid.v4(),
            ts: now,
            dayKey: dayKey(now),
            result: type,
            watchedSeconds: math.max(0, _elapsedMs ~/ 1000),
            source: widget.args.source,
          ));
    } catch (_) {
      // 与账本同纪律：记录失败不重试（append 重复尝试只会产生重复行）、不卡退场。
    }
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

  /// 点主按钮「跳过护眼休息」（玄参 2026-10-08 定名 + 新口径）：
  ///
  /// 自然走完时系统自动收口，主按钮的实际语义 = 提前结束 = 跳过：
  /// · **流程已自然走完**（末槽回调收口，实际到不了这里，防御保留）→ 正常 completed；
  /// · **没走完就手点** = 视同跳过，绝不能白拿奖励：
  ///   - 家长关掉「允许跳过」→ 弹「不可跳过，请爱护眼睛」，流程不推进；
  ///   - 允许跳过 → **二次确认**（明示无奖励 + 爱护眼睛提示），确认后按
  ///     [EyeCareResultType.skipped] 退场（不发奖励、不写账本），取消＝继续休息。
  void _onFinishPressed() {
    if (_finishing) return; // 收口已在进行，幂等
    if (_flowPlayedOut) {
      unawaited(_finish(EyeCareResultType.completed));
      return;
    }
    if (!widget.args.skipAllowed) {
      _showNotSkippable();
      return;
    }
    _showEarlyFinishConfirm();
  }

  /// 未走完就手点「完成休息」的二次确认卡（无奖励明示 + 爱护眼睛提示）。
  void _showEarlyFinishConfirm() {
    if (_confirmOpen) return;
    setState(() => _confirmOpen = true);
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text(kEyeCareEarlyFinishTitle),
        content: const Text(kEyeCareEarlyFinishConfirmText),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(kEyeCareEarlyFinishStayLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(kEyeCareEarlyFinishQuitLabel),
          ),
        ],
      ),
    ).then((bool? ok) {
      if (!mounted) return;
      setState(() => _confirmOpen = false);
      if (ok != true) return;
      // 确认结束 = 按跳过处理：无奖励、不写账本。
      unawaited(_finish(EyeCareResultType.skipped));
    });
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EyeCareSegment seg = kEyeCarePlaylist[_slot]; // C43：恒为单段（_slot 恒 0）
    final double totalProgress =
        kEyeCarePlaylistTotalMs <= 0
            ? 1.0
            : (_elapsedMs / kEyeCarePlaylistTotalMs).clamp(0.0, 1.0);
    final int remainingSeconds = (_elapsedMs ~/ 1000) >= kEyeCareDurationSeconds
        ? 0
        : kEyeCareDurationSeconds - _elapsedMs ~/ 1000;

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
          // B35（玄参 2026-10-08）：横屏竖向空间小，动画帧 340 底部快出屏。
          // 用 LayoutBuilder 拿 SafeArea 内真实可用高度自适应画面边长：
          // 竖屏（高 ≥ 600）维持 340 不变；矮横屏按可用高度的 45% 缩小（160~300 夹紧）。
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double frameSide = c.maxHeight < 600
                  ? math.min(300.0, math.max(160.0, c.maxHeight * 0.45))
                  : 340.0;
              return SingleChildScrollView(
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
                // 段标题（配音已含口令，这里只做同步字幕）。
                Text(
                  seg.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF8A7A5F),
                  ),
                ),
                const SizedBox(height: 16),
                // 整幅画面序列帧（素材 720×720 带背景；圆角白卡裁切，
                // 边长自适应：竖屏最大 340，横屏按可用高度缩小——B35）。
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: frameSide),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: FrameSequencePlayer(
                          // C43（2026-10-09）：单段 640 帧一次播完（63.974s），
                          // 无槽位切换 → 无需 playToken；整组预热已被播放器的
                          // **滑动窗口预热**取代（640 帧 × 2.07MB ≈ 1.3GB 禁整组预热）。
                          frames: fxFrameAssets(seg.dir, seg.frameCount,
                              ext: seg.frameExt),
                          durationMs: seg.durationMs,
                          fadeOutMs: 0, // 播完即收口（自然走完 = completed）
                          onComplete: _onSlotComplete,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '还剩 $remainingSeconds 秒',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4A2F),
                  ),
                ),
                const SizedBox(height: 8),
                // 整体进度条（圆角细条，暖色）。
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalProgress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFFFF1C2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFB4C4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _onFinishPressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text(kEyeCareFinishLabel),
                  ),
                ),
                // 「跳过」按钮**恒存在**（口径 C28 §7：护眼卡恒有两个出口）。家长关掉
                // 「允许跳过」时它只是**点了无效**（弹 [kEyeCareNotSkippableText]、
                // 流程不推进），而**不是整块消失**——消失的话孩子根本点不到、也就
                // 看不到「不可跳过」的提示，与口径相悖。
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
          ); // SingleChildScrollView（return 语句收口）
            },
          ),
        ),
      ),
    );
  }
}
