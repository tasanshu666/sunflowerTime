/// 系统安全区封装（flutter_secure_storage）：家长 PIN 哈希 + salt（§4.9 / §10.4）。
library secure_store;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/utils/pin_hash.dart';

class SecureStore {
  final FlutterSecureStorage _storage;

  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// 是否已设置过 PIN。
  Future<bool> hasPin() async => (await _storage.read(key: kSecurePinHash)) != null;

  /// 首次设置 PIN（生成 salt + 哈希写入安全区）。
  Future<void> setupPin(String pin) async {
    final salt = newSalt();
    final hash = hashPin(pin, salt);
    await _storage.write(key: kSecurePinSalt, value: salt);
    await _storage.write(key: kSecurePinHash, value: hash);
  }

  /// 校验 PIN（与已存哈希比对）。
  Future<bool> verify(String pin) async {
    final salt = await _storage.read(key: kSecurePinSalt);
    final hash = await _storage.read(key: kSecurePinHash);
    if (salt == null || hash == null) return false;
    return verifyPin(pin, salt, hash);
  }

  /// 清除 PIN（家长重置用）。
  Future<void> clear() async {
    await _storage.delete(key: kSecurePinHash);
    await _storage.delete(key: kSecurePinSalt);
  }
}
