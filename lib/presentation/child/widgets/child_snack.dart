/// 儿童风浮空提示条（2026-09-29 玄参：默认黑色 SnackBar 太丑，重做）。
///
/// 视觉：暖奶油底 + 琥珀描边 + 浮空圆角大胶囊，左端一个彩色圆片表情，
/// 与花园草地 / 马卡龙卡片语言一致；替代全宽贴底的黑色 Material SnackBar。
///
/// 用法：`showChildSnack(context, '盛开的礼物：+1 植物碎片')`。
/// 顶部弹出（`SnackBehavior.floating` + 从上滑入需自定义，默认底部浮空已足够柔和），
/// 文案由调用方拼装，本组件不感知业务。
library child_snack;

import 'package:flutter/material.dart';

/// 弹出一条儿童风提示条。内容文案原样展示（含 emoji）。
void showChildSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      // SnackBar 自身不再画任何底色，视觉全部交给内层卡片。
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD98E), width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF8A5A00).withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 左端彩色圆片 + 向日葵吉祥物，一眼识别「这是花园的提示」。
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE9B8),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('🌻', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Color(0xFF5D4037),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
