/// 阳光胶囊（2026-09-24 花园页 UI 改造）。
///
/// ## 为什么有这个组件
/// 改造前花园页顶部有一条**横跨整宽的「我的阳光」大卡**（`_SunlightBanner`），
/// 它压在草地上挡住第一行花盆。玄参大人要求把阳光余额**收成一个小胶囊**放到左上角
/// （孩子端 shell 的 AppBar `leading` 位置），把整片草地让出来。
///
/// 胶囊在**孩子端 shell 花园 tab** 的 AppBar 左上角展示一次；独立路由 `/garden`
/// （无 shell AppBar）时由花园页自己在内容区左上角补一个（见 `GardenPage`）。
///
/// ## 数据来源与「不要显示 0」
/// 余额读 [sunlightBalanceProvider]（随 `economyRevisionProvider` 自动重算）。
/// 加载中 / 出错时**必须显示 `— ☀` 兜底**，绝不能回退成 `0 ☀` —— 否则孩子会以为
/// 阳光被扣光了，比「暂时看不到」伤害大得多。
library sunlight_pill;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';

/// 阳光余额小胶囊 —— 花园页左上角展示（替代原整宽横幅）。
class SunlightPill extends ConsumerWidget {
  const SunlightPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<double> snap = ref.watch(sunlightBalanceProvider);
    // hasValue 为 false（加载中 / 出错）时显示 '— ☀'，不显示 0（避免误导孩子）。
    final String text = snap.hasValue ? '${snap.requireValue.toInt()} ☀' : '— ☀';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.wb_sunny, size: 16, color: Color(0xFFE8A600)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFFD98F00),
            ),
          ),
        ],
      ),
    );
  }
}
