/// 首次启动同意流（M0 关键交付 / §10.4 合规本地化）。同意后写首启标记。
library consent_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';

class ConsentPage extends ConsumerWidget {
  const ConsentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '欢迎使用向日葵专注',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                '· 我们只收集专注时长、打卡等必要数据；\n'
                '· 全部数据加密存储在本机，不上传云端；\n'
                '· 无账号、无广告、无社交，不采集通讯录与位置。',
                style: TextStyle(height: 1.8),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref
                        .read(settingsStoreProvider)
                        .setFirstLaunchConsented(true);
                    if (context.mounted) context.go('/');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('同意并开始'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
