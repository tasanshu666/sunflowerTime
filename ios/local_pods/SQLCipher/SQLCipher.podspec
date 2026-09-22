# 本地空壳 pod：顶替 CocoaPods 上的 SQLCipher（仅用于本机离线构建 iOS 模拟器包）。
#
# 为什么需要它：
#   本机无法访问 github.com（实测 `curl https://github.com` → http=000），而 SQLCipher pod
#   的源码地址是 https://github.com/sqlcipher/sqlcipher.git，导致 `pod install` 必然失败。
#
# 为什么可以这样顶替（已核对源码，非猜测）：
#   1. 本工程 pubspec.yaml 里配置了 sqlite3 native assets 的 `source: system`，
#      说明 iOS 上 sqlite3 加载的是系统 libsqlite3，本来就不使用 SQLCipher；
#   2. sqlcipher_flutter_libs 的 iOS 原生类（ios/Classes/SwiftSqlite3FlutterLibsPlugin.swift、
#      Sqlite3FlutterLibsPlugin.m）是**空实现**，源码注释原文：
#      「No need to do anything at runtime, we only care about the build script」，
#      没有任何代码引用 SQLCipher 的符号。
#   因此本 pod 不提供任何实现即可满足构建，并且不影响 App 在 iOS 上的运行行为。
#
# 已知差异（可接受）：
#   iOS 模拟器上数据库不加密。这与 `source: system` 的既定行为一致 —— 加密只在 Android
#   生效（sqlcipher_flutter_libs 经 Maven 提供 libsqlcipher.so）。
#
# 影响范围：
#   仅影响 iOS 构建。Android 构建完全不读这个文件（走 Maven 的 net.zetetic:android-database-sqlcipher）。
Pod::Spec.new do |s|
  s.name             = 'SQLCipher'
  s.version          = '4.5.7'
  s.summary          = 'Offline no-op stand-in for the SQLCipher pod (local build workaround only).'
  s.description      = 'See the comment block at the top of this podspec for the full rationale.'
  s.homepage         = 'https://example.invalid/sqlcipher-local-stub'
  s.license          = { :type => 'MIT', :text => 'Local build workaround only; contains no third-party code.' }
  s.author           = { 'local-build-workaround' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '12.0'
  s.source_files     = 'Classes/**/*'
  s.requires_arc     = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
