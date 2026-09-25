/// 家长端「夸夸台」页（§5 T-F · M2 极简壳）：收藏给孩子的夸夸语录。
///
/// 持久化：SharedPreferences 存一个 JSON 字符串列表（key = 'praise_notes_v1'），
/// **不**新增 Drift 表（§7 共享纪律：改动保持纯新增、仅 UI + 本地 prefs，不接云）。
/// 支持新增（TextField + 添加按钮）与删除（Dismissible）。
library parent_praise_page;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';

/// 夸夸语录本地持久化 key（SharedPreferences）。
const String kPraiseNotesKey = 'praise_notes_v1';

/// 「夸夸台」页：本地收藏对孩子的夸夸语录。
class ParentPraisePage extends ConsumerStatefulWidget {
  const ParentPraisePage({super.key});

  @override
  ConsumerState<ParentPraisePage> createState() => _ParentPraisePageState();
}

class _ParentPraisePageState extends ConsumerState<ParentPraisePage> {
  final List<String> _notes = <String>[];
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 从 SharedPreferences 读取已保存的夸夸语录。
  Future<void> _load() async {
    try {
      final SharedPreferences prefs =
          ref.read(sharedPreferencesProvider);
      final String? raw = prefs.getString(kPraiseNotesKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List<dynamic>) {
          _notes
            ..clear()
            ..addAll(decoded.map((dynamic e) => e.toString()));
        }
      }
    } catch (_) {
      // 读取失败容忍：以空列表兜底。
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 持久化当前语录列表（§7.5：异常不向上抛，本地降级）。
  Future<void> _persist() async {
    try {
      final SharedPreferences prefs =
          ref.read(sharedPreferencesProvider);
      await prefs.setString(kPraiseNotesKey, jsonEncode(_notes));
    } catch (_) {
      // 持久化失败容忍。
    }
  }

  /// 新增一条夸夸语录（插入列表头部）。
  Future<void> _add() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _notes.insert(0, text);
      _controller.clear();
    });
    await _persist();
    // P0 · B：夸夸语录「送达」埋点（当前以「家长新增语录成功」为送达代理）。
    // 埋点失败绝不影响 UI（本地降级）。
    try {
      await ref.read(memoirServiceProvider).recordPraiseSent(text, DateTime.now());
    } catch (_) {
      // 埋点失败容忍。
    }
  }

  /// 删除一条夸夸语录。
  Future<void> _removeAt(int index) async {
    if (index < 0 || index >= _notes.length) return;
    setState(() => _notes.removeAt(index));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '写一句夸夸孩子的话',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _add,
                child: const Text('添加'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _notes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '还没有夸夸语录～\n把想对孩子说的鼓励话写在这里吧 🌻',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int i) {
                    return Dismissible(
                      key: Key('praise_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _removeAt(i),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.favorite,
                                  color: Colors.pink, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_notes[i])),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
