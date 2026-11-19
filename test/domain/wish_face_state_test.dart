/// 树上三态判据（v0.3.0 / R3-P0-05 / D5）—— **纯领域测试**，零 widget。
///
/// 守两件事：
///  ① **互斥**：同一 `(wish, wayCount)` 只命中一态（单出口，判定顺序 S3→S2→S1）；
///  ② **边界**：空字符串标签 / 空回信 / 非 pending / 已收箱 的归属不能含糊。
library wish_face_state_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';

Wish _wish({
  String id = 'w1',
  WishStatus status = WishStatus.pending,
  String? tagKey,
  String? parentReply,
  DateTime? releasedAt,
  int targetValue = 0,
  int progressValue = 0,
}) =>
    Wish(
      id: id,
      childId: 'c1',
      text: 'wish',
      status: status,
      createdAt: DateTime(2026, 11, 1),
      tagKey: tagKey,
      parentReply: parentReply,
      releasedAt: releasedAt,
      targetValue: targetValue,
      progressValue: progressValue,
    );

void main() {
  group('S1 hanging（家长未回应）', () {
    test('pending + 无标签 + 无回信 + 0 个小办法 ⇒ hanging', () {
      expect(
        wishTreeFaceOf(wish: _wish(), wayCount: 0),
        WishTreeFace.hanging,
      );
    });

    test('标签/回信为**空字符串**也归 hanging（不是「已回应」）', () {
      expect(
        wishTreeFaceOf(wish: _wish(tagKey: '', parentReply: ''), wayCount: 0),
        WishTreeFace.hanging,
        reason: 'isNotEmpty 判定（U3）：空串不算家长已回应',
      );
    });
  });

  group('S2 parentResponded（家长已回应、未布置办法）', () {
    test('有 tagKey ⇒ parentResponded', () {
      expect(
        wishTreeFaceOf(wish: _wish(tagKey: 'need_more_time'), wayCount: 0),
        WishTreeFace.parentResponded,
      );
    });

    test('只有 parentReply（无标签）⇒ parentResponded', () {
      expect(
        wishTreeFaceOf(wish: _wish(parentReply: '再等等'), wayCount: 0),
        WishTreeFace.parentResponded,
      );
    });

    test('已承诺（committed）但标签/回信暂空 ⇒ 兜底 parentResponded（不回退 S1）', () {
      expect(
        wishTreeFaceOf(wish: _wish(status: WishStatus.committed), wayCount: 0),
        WishTreeFace.parentResponded,
        reason: 'U2 边界：已被家长处理过的愿望不许再挂回 S1 反复催促',
      );
    });

    test('已收进收藏箱（releasedAt != null）且无标签 ⇒ 兜底 parentResponded', () {
      expect(
        wishTreeFaceOf(
          wish: _wish(releasedAt: DateTime(2026, 11, 2)),
          wayCount: 0,
        ),
        WishTreeFace.parentResponded,
      );
    });
  });

  group('S3 hasWays（家长已布置小办法）', () {
    test('wayCount >= 1 ⇒ hasWays（优先级最高）', () {
      expect(
        wishTreeFaceOf(wish: _wish(), wayCount: 1),
        WishTreeFace.hasWays,
      );
      expect(
        wishTreeFaceOf(wish: _wish(), wayCount: 5),
        WishTreeFace.hasWays,
      );
    });

    test('有标签 + 有办法 ⇒ 仍是 hasWays（S3 覆盖 S2）', () {
      expect(
        wishTreeFaceOf(
          wish: _wish(tagKey: 'parents_working', parentReply: '在想办法'),
          wayCount: 2,
        ),
        WishTreeFace.hasWays,
      );
    });
  });

  group('三态互斥（同一份数据只命中一态）', () {
    test('遍历若干组合：三态计数之和 == 用例数，且无「同时命中」', () {
      final List<Wish> cases = <Wish>[
        _wish(id: 'a'),
        _wish(id: 'b', tagKey: 'over_budget'),
        _wish(id: 'c', parentReply: '记在心里了'),
        _wish(id: 'd', status: WishStatus.committed),
        _wish(id: 'e', releasedAt: DateTime(2026, 11, 3)),
      ];
      for (final Wish w in cases) {
        for (final int ways in <int>[0, 1, 3]) {
          final WishTreeFace face = wishTreeFaceOf(wish: w, wayCount: ways);
          final int hits = <WishTreeFace>[
            WishTreeFace.hanging,
            WishTreeFace.parentResponded,
            WishTreeFace.hasWays,
          ].where((WishTreeFace f) => f == face).length;
          expect(hits, 1, reason: '${w.id}/ways=$ways 必须只命中一态');
          // 与判据同构的独立复算（防「函数内部写反」被同一表达式自证）：
          if (ways >= 1) {
            expect(face, WishTreeFace.hasWays);
          } else if ((w.tagKey ?? '').isNotEmpty ||
              (w.parentReply ?? '').isNotEmpty) {
            expect(face, WishTreeFace.parentResponded);
          }
        }
      }
    });

    test('函数是纯的：同输入两次调用结果一致', () {
      final Wish w = _wish(tagKey: 'wait_for_moment');
      expect(wishTreeFaceOf(wish: w, wayCount: 0),
          wishTreeFaceOf(wish: w, wayCount: 0));
    });
  });
}
