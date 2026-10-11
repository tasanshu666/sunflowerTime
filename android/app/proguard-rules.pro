# 向日葵专注 · R8/ProGuard 规则（release 混淆）
# 2026-10-11 防逆向批次。原则：默认全混淆，只对「确实需要」的符号加 keep。

# ── Flutter 引擎与插件胶水 ─────────────────────────────────────────
# Flutter 官方默认规则已随引擎 AAR 提供（io.flutter.* 的 consumer rules），
# 此处只补工程直接依赖、且可能被反射/JNI 访问的类。

# SQLCipher（sqlcipher_flutter_libs 经 Maven 提供 libsqlcipher.so，
# Java 层 net.zetetic.database.* 通过 JNI 与 native 交互，类名/方法名不能被混淆）
-keep class net.zetetic.database.** { *; }
-dontwarn net.zetetic.database.**

# flutter_secure_storage 走 androidx.security（EncryptedSharedPreferences），
# AAR 已带 consumer rules；这里保险起见保住 JNI 入口
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ── JNI / 反射兜底 ────────────────────────────────────────────────
# 保留源码行号与源文件名仅用于 R8 内部重映射（崩溃栈经 mapping.txt 还原），
# 不影响混淆本身
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# 崩溃栈还原：每次 release 构建产出 app/build/outputs/mapping/release/mapping.txt
# 与 Dart 侧 build/symbols/ 一起备份留存。
