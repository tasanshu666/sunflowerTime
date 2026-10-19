/// C91 二轮（玄参 iOS 模拟器反馈）：**核销确认卡跨孩子泄漏** —— 回归守卫。
///
/// 现象：孩子 A 有兑换 → 家长端核销 → 家长切当前孩子到 B → 返回 B 的孩子端
/// → B 端也弹「家长已确认你的兑换」确认卡。应只弹给被核销的孩子 A。
///
/// 防线口径（触发判定全链路按当前孩子隔离）：
///  · 数据源：F123 仓储级过滤（`verifiedRequests()` 只看当前孩子）；
///  · **C91 二轮新增第二层**：`_checkVerifiedNotices` / `_checkRejectedNotices`
///    把拉到的列表再按本次检查捕获的 childId 过滤一次 —— diff 的「待展示列表」
///    与「已读快照键」（`acked_verify_ids_read_$childId`，C90-B 分键）必须
///    同属一个孩子。任何「未过滤 / 旧快照」数据源回归在此被拦下：其他孩子的行
///    绝不 diff 进当前孩子的快照键，也绝不会被当前孩子的「知道啦」写坏。
///
/// 用例①即为变异目标：把数据源故意换回**未过滤**（模拟 F123 前 / 旧快照），
/// 修复前 B 会弹 A 的卡（红），修复后不弹（绿）；再钉「切回 A 通知不丢」。
/// 用例②走真仓储端到端：A 弹卡 → 切 B 不弹（B 自己的未读弹自己的）→ 切回 A
/// 若仍有未读则再弹（口径自洽）。
library verify_notice_child_isolation_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';

const String _kCardTitle = '🎉 家长已确认你的兑换';
const String _kRejectTitle = '🚫 兑换未被通过';

final DateTime _t = DateTime(2026, 10, 19, 10);

RedemptionRequest _verified(String id, String childId, {int cost = 10}) =>
    RedemptionRequest(
      id: id,
      childId: childId,
      templateId: 'tpl_x',
      requestedAt: _t,
      cost: cost,
      status: RequestStatus.verified,
      verifiedAt: _t.add(const Duration(hours: 1)),
    );

RedemptionRequest _rejected(String id, String childId) => RedemptionRequest(
      id: id,
      childId: childId,
      templateId: 'tpl_x',
      requestedAt: _t,
      cost: 10,
      status: RequestStatus.rejected,
    );

const RewardTemplate _tpl = RewardTemplate(
  id: 'tpl_x',
  name: '小零食',
  category: RewardCategory.parentHandled,
  contentCategory: RewardContentCategory.snacks,
  baseCost: 10,
  frequencyLimitPerWeek: 7,
  cooldownRule: CooldownRule.none,
);

/// ⚠️ 故意**不过滤**的假仓储（模拟 F123 前数据源 / 切孩子瞬间的旧快照）：
/// `verifiedRequests()` / `rejectedRequests()` 恒返整表 —— 确认卡触发链必须
/// 自己按 childId 拦下（C91 二轮第二层防线）。
class _UnfilteredRewardRepository implements RewardRepository {
  _UnfilteredRewardRepository({
    List<RedemptionRequest> verified = const <RedemptionRequest>[],
    List<RedemptionRequest> rejected = const <RedemptionRequest>[],
  })  : _verified = verified,
        _rejected = rejected;

  final List<RedemptionRequest> _verified;
  final List<RedemptionRequest> _rejected;

  @override
  Future<List<RewardTemplate>> templates() async => const <RewardTemplate>[_tpl];

  @override
  Future<List<RedemptionRequest>> verifiedRequests() async =>
      List<RedemptionRequest>.of(_verified);

  @override
  Future<List<RedemptionRequest>> rejectedRequests() async =>
      List<RedemptionRequest>.of(_rejected);

  @override
  Future<List<RedemptionRequest>> pendingAndQueued() async =>
      <RedemptionRequest>[];

  @override
  Future<List<RedemptionRequest>> queuedOfWeek(String weekKey) async =>
      <RedemptionRequest>[];

  @override
  Future<void> createRequest(RedemptionRequest request) async {}

  @override
  Future<void> updateRequest(RedemptionRequest request) async {}

  @override
  Future<void> saveTemplate(RewardTemplate t) async {}

  @override
  Future<void> deleteTemplate(String id) async {}

  @override
  Future<int> cooldownCount(String templateId, CooldownPeriod window) async => 0;

  @override
  Future<void> decrementCooldown(String templateId, CooldownPeriod window) async {}
}

Future<SharedPreferences> _mockSp() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

/// 挂载孩子端外壳（脚手架参照 probe / child_avatar_test：内存 Drift + mock SP）。
Future<void> _pumpShell(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
  required AccountService account,
  RewardRepository? reward,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
          if (reward != null) rewardRepositoryProvider.overrideWithValue(reward),
        ],
      ),
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载当前外壳（模拟离开孩子端），下次 [_pumpShell] 即 remount（initState 重跑）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '① 数据源回归模拟：未过滤 verified 列表（A 的行）在 B 的孩子端绝不弹卡；'
      '切回 A 通知不丢', (tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ChildProfile second = await account.createChild('二娃', AgeTier.mid);

    // 数据源：A（默认孩子）的已核销行 —— **未过滤**，B 检查时也拿得到。
    final _UnfilteredRewardRepository reward = _UnfilteredRewardRepository(
      verified: <RedemptionRequest>[_verified('r_a1', kChildIdDefault)],
    );

    // 当前孩子 = B → 即使数据源把 A 的行吐过来，B 也绝不弹卡。
    await account.switchTo(second.id);
    await _pumpShell(tester, sp: sp, database: database, account: account,
        reward: reward);
    expect(find.text(_kCardTitle), findsNothing,
        reason: 'B 的孩子端绝不弹 A 的核销确认卡（跨孩子泄漏）');
    // B 的已读快照键不得被写坏。
    expect(sp.getStringList('acked_verify_ids_read_${second.id}'), isNull,
        reason: 'B 的检查没有可 diff 的本孩子行，快照键保持为空');

    // 切回 A：A 的未读通知不丢（B 的检查没有吃掉它）。
    await _unmount(tester);
    await account.switchTo(kChildIdDefault);
    await _pumpShell(tester, sp: sp, database: database, account: account,
        reward: reward);
    expect(find.text(_kCardTitle), findsOneWidget, reason: 'A 自己的确认卡照常弹');
    await tester.tap(find.text('知道啦'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sp.getStringList('acked_verify_ids_read_$kChildIdDefault'),
        <String>['r_a1']);
  });

  testWidgets(
      '② 拒绝对称通知同款防线：未过滤 rejected 列表（A 的行）在 B 的孩子端不弹',
      (tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
    await account.switchTo(second.id);

    final _UnfilteredRewardRepository reward = _UnfilteredRewardRepository(
      rejected: <RedemptionRequest>[_rejected('r_rej_a', kChildIdDefault)],
    );
    await _pumpShell(tester, sp: sp, database: database, account: account,
        reward: reward);
    expect(find.text(_kRejectTitle), findsNothing,
        reason: 'B 的孩子端绝不弹 A 的拒绝通知');
    expect(sp.getStringList('acked_reject_ids_read_${second.id}'), isNull);
  });

  testWidgets(
      '③ 真仓储端到端：A 被核销弹卡 → 切 B 不弹（B 自己的未读弹自己的）→ '
      '切回 A 若仍有未读则再弹（口径自洽）', (tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
    final RewardLocalRepository repo =
        RewardLocalRepository(database, account: account);
    await repo.saveTemplate(_tpl);

    // A 的兑换被家长核销。
    await repo.createRequest(RedemptionRequest(
      id: 'r_a1',
      childId: account.childId,
      templateId: 'tpl_x',
      requestedAt: _t,
      cost: 10,
    ));
    await repo.updateRequest(_verified('r_a1', kChildIdDefault));

    // A 的孩子端：弹卡 → 知道啦。
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kCardTitle), findsOneWidget);
    await tester.tap(find.text('知道啦'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(_kCardTitle), findsNothing);
    expect(sp.getStringList('acked_verify_ids_read_$kChildIdDefault'),
        <String>['r_a1']);

    // 家长切到 B；B 自己也有一笔已核销未读。
    await account.switchTo(second.id);
    await repo.createRequest(RedemptionRequest(
      id: 'r_b1',
      childId: second.id,
      templateId: 'tpl_x',
      requestedAt: _t.add(const Duration(minutes: 5)),
      cost: 10,
    ));
    await repo.updateRequest(_verified('r_b1', second.id));

    await _unmount(tester);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    // B 弹的是**自己的**未读（数据源与快照键都按孩子隔离）——不是 A 的 r_a1。
    expect(find.text(_kCardTitle), findsOneWidget,
        reason: 'B 有自己的未读核销 → 弹自己的卡（不是 A 的行）');
    await tester.tap(find.text('知道啦'));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sp.getStringList('acked_verify_ids_read_${second.id}'),
        <String>['r_b1'], reason: 'B 的快照键只含 B 自己的行');
    expect(sp.getStringList('acked_verify_ids_read_$kChildIdDefault'),
        <String>['r_a1'], reason: 'A 的快照键不被 B 的检查串写');

    // 切回 A：r_a1 已读不重复弹；再核销一笔 A 的 → 仍有未读则再弹（口径自洽）。
    await repo.createRequest(RedemptionRequest(
      id: 'r_a2',
      childId: kChildIdDefault,
      templateId: 'tpl_x',
      requestedAt: _t.add(const Duration(minutes: 10)),
      cost: 12,
    ));
    await repo.updateRequest(_verified('r_a2', kChildIdDefault, cost: 12));

    await _unmount(tester);
    await account.switchTo(kChildIdDefault);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kCardTitle), findsOneWidget,
        reason: 'A 有新的未读核销 → 再弹（不丢、不残留）');
    // 卡内条目为 A 的两笔未读中新的一笔（扣 12 阳光）。
    expect(find.text('-12 阳光'), findsOneWidget);
  });
}
