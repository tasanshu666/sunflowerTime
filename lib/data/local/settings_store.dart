/// shared_preferences 封装（§1.1 简单 KV 设置）。
/// 当前仅承载「首次启动同意」标记；其余设置走 Drift settings 表。
library settings_store;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';

class SettingsStore {
  final SharedPreferences _sp;

  SettingsStore(this._sp);

  // ── 首启同意（首启告知 2.0 / C110：版本三要素）────────────────────────────

  /// 已同意的隐私政策版本号：新键缺失时回读 v1 遗留布尔键迁移 ——
  /// `kPrefFirstLaunchConsented == true` 视为已同意 **v1**（老用户升级后会因
  /// 「记录版本 < 当前版本」重弹一次同意页，即 §10.3 重新确认机制）；两键皆无
  /// = 0（从未同意）。
  Future<int> consentedPolicyVersion() async {
    final int? v = _sp.getInt(kPrefConsentPolicyVersion);
    if (v != null) return v;
    final bool legacy = _sp.getBool(kPrefFirstLaunchConsented) ?? false;
    return legacy ? 1 : 0;
  }

  /// 是否已同意**当前版本**政策（路由守卫重弹判据：记录版本 ≥ 当前内置版本）。
  Future<bool> isCurrentPolicyConsented() async =>
      await consentedPolicyVersion() >= kPrivacyPolicyVersion;

  /// 记录「同意当前版本政策」：写版本号 + 同意时刻（epoch 毫秒，仅审计用；
  /// 幂等覆盖写）。**不再写 v1 遗留布尔键**。
  Future<void> acceptCurrentPolicyConsent() async {
    await _sp.setInt(kPrefConsentPolicyVersion, kPrivacyPolicyVersion);
    await _sp.setInt(
        kPrefConsentAcceptedAtMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// 同意时刻（epoch 毫秒；无记录返回 null，仅供审计/调试展示）。
  Future<int?> consentAcceptedAtMs() async => _sp.getInt(kPrefConsentAcceptedAtMs);

  // ── 已读通知键（C90 期 2 第二批：按孩子分键，键名单点见 app_constants）──────

  /// 孩子端已展示过的「家长核销成功」申请 id（默认空；按 [childId] 分键，
  /// 历史全局键不迁移）。
  Future<List<String>> acknowledgedVerifyIds({required String childId}) async =>
      _sp.getStringList(ackedVerifyIdsKey(childId)) ?? <String>[];

  /// 覆写「家长核销成功」已读 id 列表（按 [childId] 分键）。
  Future<void> setAcknowledgedVerifyIds(
    List<String> ids, {
    required String childId,
  }) async =>
      _sp.setStringList(ackedVerifyIdsKey(childId), ids);

  /// 孩子端已展示过的「家长拒绝」申请 id（默认空，B4 对称通知去重；按
  /// [childId] 分键）。
  Future<List<String>> acknowledgedRejectIds({required String childId}) async =>
      _sp.getStringList(ackedRejectIdsKey(childId)) ?? <String>[];

  /// 覆写「家长拒绝」已读 id 列表（按 [childId] 分键）。
  Future<void> setAcknowledgedRejectIds(
    List<String> ids, {
    required String childId,
  }) async =>
      _sp.setStringList(ackedRejectIdsKey(childId), ids);

  /// 孩子端已展示过的「家长审批成长任务」打卡 id（F126 补缺口；默认空，
  /// 按 [childId] 分键）。
  ///
  /// 与 [acknowledgedVerifyIds] **刻意分开**：装的是不同实体（打卡 id vs 兑换
  /// 申请 id），去重必须互不干扰。方向同 C90 期 2：历史全局键不迁移。
  Future<List<String>> acknowledgedTaskCheckInIds({
    required String childId,
  }) async =>
      _sp.getStringList(ackedTaskCheckInIdsKey(childId)) ?? <String>[];

  /// 覆写「家长审批成长任务」已读打卡 id 列表（按 [childId] 分键）。
  Future<void> setAcknowledgedTaskCheckInIds(
    List<String> ids, {
    required String childId,
  }) async =>
      _sp.setStringList(ackedTaskCheckInIdsKey(childId), ids);

  /// 孩子端已展示过的「家长赠予到账」**最新账本记录 id**（F150；默认 null =
  /// 从未弹过 —— 首次有赠予必弹。按 [childId] 分键）。
  Future<String?> acknowledgedParentGiftId({required String childId}) async =>
      _sp.getString(ackedParentGiftIdKey(childId));

  /// 覆写「家长赠予到账」已读 id（按 [childId] 分键）。
  Future<void> setAcknowledgedParentGiftId(
    String id, {
    required String childId,
  }) async =>
      _sp.setString(ackedParentGiftIdKey(childId), id);

  // ── 花园：孩子上次**看到**的植物阶段快照（按孩子分键）─────────────────────

  /// 孩子上次在花园里**看到**的各植物阶段：`plantId → 'stage.name:status.name'`。
  ///
  /// 用于「离开期间升级 → 回来补播一次成长演出」。默认空表（= 没有可比对的基线，
  /// 首次安装 / 新建植物都不补播）。解析失败 / 脏数据（手工改 SP、老版本遗留）一律
  /// 返回空表，**绝不抛异常** —— 花园页的刷新链路不能被一段坏 JSON 打断。
  Future<Map<String, String>> lastSeenPlantPhases({
    required String childId,
  }) async {
    final String? raw = _sp.getString(lastSeenPlantPhasesKey(childId));
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final Map<String, String> out = <String, String>{};
      decoded.forEach((Object? k, Object? v) {
        if (k is String && v is String) out[k] = v;
      });
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// 覆写「孩子上次看到的植物阶段」快照（按 [childId] 分键；空表也照写，能正确往返）。
  Future<void> setLastSeenPlantPhases(
    Map<String, String> phases, {
    required String childId,
  }) async =>
      _sp.setString(lastSeenPlantPhasesKey(childId), jsonEncode(phases));

  // ── P0 · A App 总使用时长（§6.1）：日键 + 当日累计秒 ──────────────────

  /// App 当日累计时长所属自然日 key（yyyy-MM-dd；无记录返回 null）。
  Future<String?> appUsageDate() async => _sp.getString(kPrefAppUsageDate);

  /// App 当日累计秒数（无记录默认 0）。
  Future<int> appUsageSeconds() async => _sp.getInt(kPrefAppUsageSeconds) ?? 0;

  /// 覆写 App 当日累计时长（日期 + 秒数）。
  Future<void> saveAppUsage({
    required String date,
    required int seconds,
  }) async {
    await _sp.setString(kPrefAppUsageDate, date);
    await _sp.setInt(kPrefAppUsageSeconds, seconds);
  }

  /// 单次锁定解锁时刻（epoch ms；无记录 / 已清 → null = 未锁定）。F99。
  Future<int?> appUsageLockedUntilMs() async =>
      _sp.getInt(kPrefAppUsageLockedUntilMs);

  /// 覆写单次锁定解锁时刻（传 null = 清除锁定）。
  Future<void> saveAppUsageLockedUntilMs(int? ms) async {
    if (ms == null) {
      await _sp.remove(kPrefAppUsageLockedUntilMs);
    } else {
      await _sp.setInt(kPrefAppUsageLockedUntilMs, ms);
    }
  }

  /// 调试期「跳过 30 分钟防沉迷限时」开关（仅 kDebugMode 消费）。
  ///
  /// 默认 **true**（玄参 2026-09-29：调试期间默认不进限时状态）。
  Future<bool> debugCapBypass() async =>
      _sp.getBool(kPrefDebugCapBypass) ?? true;

  /// 覆写调试限时开关。
  Future<void> setDebugCapBypass(bool value) async =>
      _sp.setBool(kPrefDebugCapBypass, value);

  // ── 界面语言（i18n B1 批次）────────────────────────────────────────────

  /// 界面语言存档（键见 [kPrefAppLanguage]；null / 脏值一律回
  /// [AppLanguage.system]）。
  Future<AppLanguage> getAppLanguage() async =>
      appLanguageFromStored(_sp.getString(kPrefAppLanguage));

  /// 覆写界面语言存档（`AppLocaleController.set` 落盘走此处）。
  Future<void> setAppLanguage(AppLanguage lang) async =>
      _sp.setString(kPrefAppLanguage, appLanguageToKey(lang));
}
