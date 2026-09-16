/// 专注入口页（T09，竖屏）：选时长 + 音效/背景音乐开关 + 横屏引导。
///
/// 依据 PRD §4.1.2（进入前选时长）/ §4.1.6（音效、背景音乐前移至进入前设置页）/ §4.2。
/// 点「开始专注」→ `/focus?minutes=N&dnd=1|0`（横屏打盹屏，独占屏，经 go 进入）。
library entry_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  int _minutes = kFocusDurationDefaultMinutes;
  // B29：音频功能属 M2，本批不接音频播放；开关仅占位展示，故设为 final（不可切换）。
  final bool _soundOn = true; // 音效开关默认值（占位）
  final bool _bgmOn = false; // 背景音乐默认值（占位）
  bool _dndOn = true; // 屏蔽通知（勿扰），默认开（F01）

  void _start() =>
      context.go('/focus?minutes=$_minutes&dnd=${_dndOn ? 1 : 0}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开始专注'),
        // 本页经 go('/entry') 进入 = 路由栈底，显式返回箭头回孩子端（B19 约定）。
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '这次想专注多久？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kFocusDurationOptions.map((m) {
                final selected = m == _minutes;
                return ChoiceChip(
                  label: Text('$m 分钟'),
                  selected: selected,
                  onSelected: (_) => setState(() => _minutes = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('屏蔽通知（勿扰）'),
              subtitle: const Text('专注时屏蔽短信/来电等打扰'),
              value: _dndOn,
              onChanged: (v) => setState(() => _dndOn = v),
            ),
            const SizedBox(height: 12),
            // B29：音频功能属 M2，本批不接音频播放；开关诚实置灰，避免误导用户以为已生效。
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('音效'),
              subtitle: const Text('音频功能即将上线（M2）'),
              value: _soundOn, // 默认值保持（音效 true），但不可切换
              onChanged: null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('背景音乐'),
              subtitle: const Text('音频功能即将上线（M2）'),
              value: _bgmOn, // 默认值保持（BGM false），但不可切换
              onChanged: null,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.screen_rotation, color: Color(0xFFF9A825)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '把手机横过来放好，向日葵就开工啦。',
                      style: TextStyle(fontSize: 16, color: Color(0xFF5D4037)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('开始专注'),
            ),
          ],
        ),
      ),
    );
  }
}
