/// 家长 PIN 哈希工具（§4.9 / §10.4）。
///
/// ⚠️ 骨架阶段用 sha256(pin + salt) 做演示性哈希；生产应换 PBKDF2/Argon2 等
/// 慢哈希。盐由 uuid 生成，存于系统安全区（flutter_secure_storage）。
library pin_hash;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// 生成新盐（UUID v4，去横线）。
String newSalt() => const Uuid().v4().replaceAll('-', '');

/// 计算 PIN 哈希（sha256(pin + salt)，hex 小写）。
String hashPin(String pin, String salt) {
  final bytes = utf8.encode('$pin$salt');
  return sha256.convert(bytes).toString();
}

/// 校验 PIN：输入是否与已存哈希一致。
bool verifyPin(String pin, String salt, String storedHash) =>
    hashPin(pin, salt) == storedHash;
