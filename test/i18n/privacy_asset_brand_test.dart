/// 应用内隐私政策资产的**品牌名**护栏（F159 改名批 · QA 补的覆盖缺口）。
///
/// 为什么存在：应用内政策全文读的是 `assets/docs/privacy_policy_{zh,en}.md`
/// （`tools/gen_privacy_assets.py` 产物，见 `privacy_policy_page.dart` 头注释），
/// 而这两个文件是「脚本派生的静态资产」——底稿或脚本漏改时不会有任何编译错误，
/// 也不会让既有 widget 测试变红（`test/m3/consent_flow_v2_test.dart` 只断言中文
/// 品牌名与章节结构，英文品牌名无人看守）。F159 把英文名 `Tiny Bloom` 改成
/// `Tiny Sunflower` 时，这条链路全靠人工 grep 兜底，故补本守卫。
///
/// 口径（直读文件系统，刻意不走 AssetManifest / 不做 widget 构建）：
///  1. en 资产**含**新名 `Tiny Sunflower`；
///  2. en 资产**不含**旧名 `Tiny Bloom`（改名残留即红）；
///  3. zh 资产**含**中文名「小小葵番茄钟」（原名不变，防误改）。
///
/// 不做 widget 级断言的原因：政策页是懒构建 `ListView`，视口外的正文根本没进树，
/// `find.textContaining` 会因「没滚到」而非「文案错了」假红。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 中文政策资产（与 `lib/presentation/shared/privacy_policy_page.dart`
/// 的 `kPrivacyPolicyAssetZh` 同路径）。
const String assetZh = 'assets/docs/privacy_policy_zh.md';

/// 英文政策资产（同上，对应 `kPrivacyPolicyAssetEn`）。
const String assetEn = 'assets/docs/privacy_policy_en.md';

/// 当前英文品牌名（F159 定名，ASC 已建档，不得再变）。
const String brandEn = 'Tiny Sunflower';

/// 已废弃的英文品牌名（ASC 查重被占用，只允许出现在变更记录/历史文档里）。
const String brandEnObsolete = 'Tiny Bloom';

/// 中文品牌名（本批零改动）。
const String brandZh = '小小葵番茄钟';

/// 工程根目录：测试可能以 `<root>` 或 `<root>/test/i18n` 为当前目录运行。
String _projectRoot() {
  final String cwd = Directory.current.path;
  if (cwd.endsWith('/test/i18n') || cwd.endsWith(r'\test\i18n')) {
    return Directory.current.parent.parent.path;
  }
  return cwd;
}

/// 读取资产正文并按 UTF-8 解码；文件缺失直接失败（缺失本身就是回归）。
String _readAsset(String relPath) {
  final File file = File('${_projectRoot()}/$relPath');
  expect(
    file.existsSync(),
    isTrue,
    reason: '资产缺失：$relPath（应由 tools/gen_privacy_assets.py 从底稿派生）',
  );
  return utf8.decode(file.readAsBytesSync());
}

void main() {
  group('应用内隐私政策资产 · 品牌名护栏（F159 Tiny Bloom → Tiny Sunflower）', () {
    test('en 资产含现用英文名 Tiny Sunflower', () {
      final String body = _readAsset(assetEn);

      expect(
        body.contains(brandEn),
        isTrue,
        reason: '英文政策资产必须出现现用名「$brandEn」——'
            '底稿改名后需重跑 tools/gen_privacy_assets.py 重生成资产',
      );
    });

    test('en 资产不含废弃名 Tiny Bloom', () {
      final String body = _readAsset(assetEn);

      expect(
        body.contains(brandEnObsolete),
        isFalse,
        reason: '英文政策资产出现废弃名「$brandEnObsolete」= 改名未落干净'
            '（ASC 查重冲突，用户可见正文不得再出现）',
      );
    });

    test('zh 资产含中文名「小小葵番茄钟」', () {
      final String body = _readAsset(assetZh);

      expect(
        body.contains(brandZh),
        isTrue,
        reason: '中文政策资产必须出现中文名「$brandZh」（F159 只改英文名，中文名零改动）',
      );
    });
  });
}
