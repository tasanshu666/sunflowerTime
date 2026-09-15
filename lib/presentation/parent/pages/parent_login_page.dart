/// 家长端登录（M0 关键交付：本地 PIN 锁框架，§4.9 / §10.4）。
///
/// 形态：本地 PIN（与 Plan B「无账号/无云」一致，不接短信验证码，见架构 §9.3）。
/// 首次进入为「设置 PIN」，之后为「校验 PIN」。PIN 哈希 + salt 存系统安全区。
library parent_login_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';

class ParentLoginPage extends ConsumerStatefulWidget {
  const ParentLoginPage({super.key});

  @override
  ConsumerState<ParentLoginPage> createState() => _ParentLoginPageState();
}

class _ParentLoginPageState extends ConsumerState<ParentLoginPage> {
  final _pinController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'PIN 至少 4 位');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final secure = ref.read(secureStoreProvider);
    final hasPin = await secure.hasPin();
    if (!hasPin) {
      // 首次：设置 PIN
      await secure.setupPin(pin);
      ref.invalidate(pinSetupProvider);
      if (mounted) context.go('/parent/home');
      return;
    }
    final ok = await secure.verify(pin);
    if (!mounted) return;
    if (ok) {
      context.go('/parent/home');
    } else {
      setState(() {
        _busy = false;
        _error = 'PIN 不正确';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = ref.watch(pinSetupProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('家长天地')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              hasPin ? '请输入家长 PIN' : '首次进入，请设置家长 PIN',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'PIN',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(hasPin ? '进入' : '设置并进入'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
