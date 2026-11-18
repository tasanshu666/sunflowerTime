/// A-T03 跨端刷新守卫（验收 ①~⑩）。
///
/// 全部断言跑在真实 in-memory drift 库 + mock SharedPreferences 上；源码守卫
/// 用例只读文件系统，不启动 widget。测试判据量由实现暴露的真量取得，期望值
/// 独立于实现（例如事件 id 由 payload 反读，不复用生产 helper 造期望）。
library wish_cross_end_refresh_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/tracking_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/presentation/child/state/wish_state.dart';

String _read(String path) => File(path).readAsStringSync();

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(db.AppDatabase database, SharedPreferences sp) =>
    ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(sp),
    ]);

TrackingEvent _event({
  required String wishId,
  required String kind,
  required DateTime at,
}) {
  final String name = kind == 'taskRejected'
      ? TrackingEventNames.wishTaskRejected
      : kind == 'taskVerified'
          ? TrackingEventNames.wishTaskVerified
          : TrackingEventNames.wishParentAction;
  return TrackingEvent(
    id: 'track_${wishId}_${kind}_${at.microsecondsSinceEpoch}',
    name: name,
    type: TrackingType.metric,
    ts: at,
    payload: <String, dynamic>{
      'wish_id': wishId,
      'kind': kind,
      'event_id': wishEventIdOf(wishId, kind, at.millisecondsSinceEpoch),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('① 愿望写入成功后跨端修订号 +1', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    final int before = c.read(economyRevisionProvider);
    await c.read(wishOrchestrationServiceProvider).createWish(
          text: '想去海边',
          category: WishCategory.experience,
          now: DateTime(2026, 11, 20, 9),
        );
    expect(c.read(economyRevisionProvider), before + 1);
  });

  test('② 孩子端 wishTreeProvider 随修订号重算', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    expect(await c.read(wishTreeProvider.future), isEmpty);
    await c.read(wishOrchestrationServiceProvider).createWish(
          text: '养一只小狗',
          category: WishCategory.gift,
          now: DateTime(2026, 11, 20, 10),
        );
    final List<Wish> tree = await c.read(wishTreeProvider.future);
    expect(tree.length, 1);
    expect(tree.single.text, '养一只小狗');
  });

  test('③ 已读键按 childId 分键（键名不变）', () async {
    final SharedPreferences sp = await _freshPrefs();
    final SettingsStore store = SettingsStore(sp);
    await store.setAcknowledgedWishEventIds(<String>['w#taskAssigned#1'],
        childId: 'child_a');
    expect(sp.getStringList('wish_acked_event_ids_child_a'),
        <String>['w#taskAssigned#1']);
    expect(sp.containsKey(wishAckedEventIdsKey('child_b')), isFalse);
    expect(await store.acknowledgedWishEventIds(childId: 'child_b'), isEmpty);
  });

  test('④ 已读 diff：同一事件只提示一次', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    final TrackingLocalRepository tracking = TrackingLocalRepository(database);
    final DateTime at = DateTime(2026, 11, 20, 11);
    await tracking.track(_event(wishId: 'w1', kind: 'taskAssigned', at: at));
    await tracking.track(
        _event(wishId: 'w1', kind: 'taskVerified', at: at.add(const Duration(minutes: 1))));

    final List<String> first = await c.read(pendingWishEventIdsProvider.future);
    expect(first.length, 2);
    final SettingsStore store = SettingsStore(sp);
    await store.setAcknowledgedWishEventIds(<String>[first.first],
        childId: kChildIdDefault);
    c.invalidate(pendingWishEventsProvider);
    final List<String> second = await c.read(pendingWishEventIdsProvider.future);
    expect(second, <String>[first.last]);
    await store.setAcknowledgedWishEventIds(first, childId: kChildIdDefault);
    c.invalidate(pendingWishEventsProvider);
    expect(await c.read(pendingWishEventIdsProvider.future), isEmpty);
  });

  test('⑤ 事件 id 带 kind + millis（同 kind 两次 = 两个 id）', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    final TrackingLocalRepository tracking = TrackingLocalRepository(database);
    final DateTime at = DateTime(2026, 11, 20, 12);
    await tracking.track(_event(wishId: 'w1', kind: 'taskAssigned', at: at));
    await tracking.track(
        _event(wishId: 'w1', kind: 'taskAssigned', at: at.add(const Duration(milliseconds: 1))));
    final List<String> ids = await c.read(pendingWishEventIdsProvider.future);
    expect(ids.length, 2);
    expect(ids.toSet().length, 2);
    for (final String id in ids) {
      final List<String> parts = id.split('#');
      expect(parts.length, 3);
      expect(parts[1], 'taskAssigned');
      expect(int.tryParse(parts[2]), isNotNull);
      expect(
        <String>[
          at.millisecondsSinceEpoch.toString(),
          at.add(const Duration(milliseconds: 1)).millisecondsSinceEpoch.toString(),
        ],
        contains(parts[2]),
      );
    }
  });

  test('⑥ 进度推进本身不产生跨端事件', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    final WishLocalRepository wishes = WishLocalRepository(database);
    await wishes.save(Wish(
      id: 'w_progress',
      childId: kChildIdDefault,
      text: '攒够 30 分钟',
      createdAt: DateTime(2026, 11, 1),
      treeSlot: 0,
      targetValue: 30,
    ));
    final TrackingLocalRepository tracking = TrackingLocalRepository(database);
    final int before = (await tracking.eventsOfType(TrackingType.metric)).length;
    await c.read(wishOrchestrationServiceProvider).advanceProgress(
          wishId: 'w_progress',
          delta: 5,
          now: DateTime(2026, 11, 20, 13),
        );
    expect((await tracking.eventsOfType(TrackingType.metric)).length, before);
  });

  test('⑦ 跨孩子隔离：A 的已读不影响 B 的未读', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    await TrackingLocalRepository(database).track(
        _event(wishId: 'w1', kind: 'goalSet', at: DateTime(2026, 11, 20, 14)));
    final String id = (await c.read(pendingWishEventIdsProvider.future)).single;
    await SettingsStore(sp).setAcknowledgedWishEventIds(<String>[id],
        childId: 'child_a');
    expect(await SettingsStore(sp).acknowledgedWishEventIds(childId: 'child_a'),
        <String>[id]);
    expect(await SettingsStore(sp).acknowledgedWishEventIds(childId: kChildIdDefault),
        isEmpty);
    c.invalidate(pendingWishEventsProvider);
    expect(await c.read(pendingWishEventIdsProvider.future), <String>[id]);
  });

  test('⑧ 源码守卫：全仓只有一个跨端修订号 provider', () {
    final Directory lib = Directory('lib');
    final int declarations = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .map((File f) => f.readAsStringSync())
        .join('\n')
        .split('\n')
        .where((String line) =>
            line.contains('final economyRevisionProvider = StateProvider'))
        .length;
    expect(declarations, 1);
    for (final String path in <String>[
      'lib/presentation/child/state/wish_state.dart',
      'lib/presentation/parent/state/wish_state.dart',
    ]) {
      expect(_read(path).contains('RevisionProvider ='), isFalse, reason: path);
    }
  });

  test('⑨ 源码守卫：_checkWishNotices 不在修订号监听路径', () {
    final String src = _read('lib/presentation/child/pages/child_shell_page.dart');
    final int listener = src.indexOf('ref.listen(economyRevisionProvider');
    final int listenerEnd = src.indexOf('});', listener);
    final String listenerBody = src.substring(listener, listenerEnd);
    expect(listenerBody.contains('_checkWishNotices'), isFalse);
    expect(listenerBody.contains('_checkLegacyNotices'), isTrue);
    final int all = src.indexOf('Future<void> _checkAllNotices()');
    final String allBody = src.substring(all, src.indexOf('\n  }', all));
    expect(allBody.contains('_checkWishNotices'), isTrue);
    // 两个触发点：首帧 postFrame（经 _checkAllNotices）+ didPopNext。
    expect(allBody.contains('_checkLegacyNotices'), isTrue);
    final int pop = src.indexOf('void didPopNext()');
    final String popBody = src.substring(pop, src.indexOf('\n  }', pop));
    expect(popBody.contains('_checkWishNotices'), isTrue);
  });

  test('⑩ 驳回事件 taskRejected 出现在未读列表', () async {
    final SharedPreferences sp = await _freshPrefs();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ProviderContainer c = _container(database, sp);
    addTearDown(c.dispose);
    await TrackingLocalRepository(database).track(
        _event(wishId: 'w1', kind: 'taskRejected', at: DateTime(2026, 11, 20, 15)));
    final List<WishPendingEvent> pending =
        await c.read(pendingWishEventsProvider.future);
    expect(pending.single.kind, 'taskRejected');
    expect(pending.single.eventId.split('#')[1], 'taskRejected');
  });
}
