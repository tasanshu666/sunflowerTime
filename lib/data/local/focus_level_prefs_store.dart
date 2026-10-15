/// C74 · 「已结算到的最高等级」的 SharedPreferences 实现（`data/local`，插件收敛层）。
///
/// ## 为什么插件只在这一层
/// `shared_preferences` 是 Flutter 插件：domain 一旦 import 就破了「纯 Dart → 可被
/// `package:test` 直接单测」的底线，故由本类实现 `FocusLevelSettledStore` 抽象
/// （同 `settings_store.dart` 既有先例）。
///
/// ## 只增不减（🔴 硬要求）
/// [write] 内部对「已有值」取 **max**：低于当前值一律忽略（否则降级会导致历史等级
/// 阳光被重复发放，破 C74 §3「同一等级绝不重复发」）。
/// 「一键删除全部本地数据」（`DataManagementService.clearAll`）会用 `_prefs.clear()`
/// 连本键一起清 → 重装后是新用户：Lv.1 起算、**不补发**（PRD §8.3，天然一致）。
library focus_level_prefs_store;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';

class FocusLevelPrefsStore implements FocusLevelSettledStore {
  FocusLevelPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<int?> read() async {
    final int? value = _prefs.getInt(kPrefFocusLevelSettled);
    if (value == null) return null;
    // 脏值兜底（键被外部写坏 / 旧版本残留）：非 0..40 一律视为「未写过」。
    // 代价 = 走一次首用分支（认等级与称号、不补发），绝不重复发阳光。
    return (value >= 0 && value <= kFocusLevelMaxLevel) ? value : null;
  }

  @override
  Future<void> write(int settledLevel) async {
    final int? current = _prefs.getInt(kPrefFocusLevelSettled);
    final int next = current == null ? settledLevel : (current > settledLevel ? current : settledLevel);
    await _prefs.setInt(kPrefFocusLevelSettled, next);
  }

  @override
  Future<void> clear() async => _prefs.remove(kPrefFocusLevelSettled);
}
