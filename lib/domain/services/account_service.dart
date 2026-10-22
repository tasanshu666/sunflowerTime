/// 账号服务（C90 期 1 真实现 · 多孩子档案底座，玄参 2026-10-17 拍板）。
///
/// 演进：Plan B 留桩（恒返 `kChildIdDefault`）→ C90 期 1 落地**本地多档案**：
/// children 表 + 家长天地切换/新建（门控只拦新增、绝不删已存档案，C69）。
/// 云同步仍留桩（C1）：[signIn] / [linkFamily] / [syncProfile] 一律抛
/// `UnsupportedError`，G2+ 接云同步时再落地。
///
/// 口径（详见 tables.dart `ChildProfiles` 注释）：
///  · 设备同一时刻只有一个「当前孩子」；无孩子端选择页；
///  · 数据隔离期 2 实施：本期只有兑换记录落新 childId（唯一业务数据效应）；
///  · 默认孩子由 [initialize] 冷启动补（空表才建，幂等），不在迁移里插。
library account_service;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/repositories/child_profile_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';

class AccountService {
  /// 全部依赖可选（仓内兼容优先）：无参构造 = 旧行为桩（`childId` 恒返
  /// [kChildIdDefault]），供既有调用方 / 测试零改动沿用；DI 注入全量依赖后
  /// 才具备多档案能力。
  AccountService({
    ChildProfileRepository? children,
    SettingsRepository? settings,
    SharedPreferences? prefs,
    String Function()? defaultChildName,
  })  : _children = children,
        _settings = settings,
        _prefs = prefs,
        _defaultChildName = defaultChildName ?? _kFallbackChildName;

  final ChildProfileRepository? _children;
  final SettingsRepository? _settings;
  final SharedPreferences? _prefs;

  /// 默认孩子名的取值器（i18n B3 · T05 新增）。
  ///
  /// 领域层**不再持有**中文「孩子」：名字是展示文案，由表现层注入
  /// （`providers.dart` 注入 `() => defaultChildName(lookupAppLocalizations(...))`，
  /// 取 ARB 的 `shared_default_child_name`）。
  ///
  /// 未注入时用 ASCII 兜底 `Child` —— 只在「无 DI 的纯领域单测 / 桩模式」下生效，
  /// 保证 `lib/domain/**` 注释外零 CJK（`test/i18n/no_han_in_domain_test`）。
  final String Function() _defaultChildName;

  /// 未注入时的 ASCII 兜底名（**故意不是中文**：domain 不许持有 CJK）。
  static String _kFallbackChildName() => 'Child';

  /// 当前活跃档案（[initialize] 后缓存；null = 未初始化 / 桩模式）。
  ChildProfile? _active;

  bool _initialized = false;

  /// 冷启动初始化：加载档案 → 恢复活跃孩子 → 空表补建默认孩子。
  ///
  /// 幂等：可安全多次调用（只生效一次）。
  ///
  /// 默认孩子口径：id = [kChildIdDefault]、name = [_defaultChildName]（注入的本地化
  /// 名字，未注入时 ASCII `Child`）、ageTier = 当前 settings 单行值（无 settings
  /// 时回退 [AgeTier.high]，与 settings 空表默认语义一致）。活跃 id 从 SP
  /// `active_child_id` 恢复；键缺失或指向不存在的孩子 → 回退第一个孩子
  /// （🔴 绝不因此删任何档案）。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final ChildProfileRepository? repo = _children;
    if (repo == null) return; // 桩模式（无依赖注入），保持旧行为

    List<ChildProfile> list = await repo.children();
    if (list.isEmpty) {
      final AgeTier tier =
          (await _settings?.getSettings())?.ageTier ?? AgeTier.high;
      await repo.create(_defaultChildName(), tier, id: kChildIdDefault);
      list = await repo.children();
    }

    final String? savedId = _prefs?.getString(kPrefActiveChildId);
    ChildProfile active = list.first;
    for (final ChildProfile c in list) {
      if (c.id == savedId) active = c;
    }
    _active = active;
  }

  /// 当前孩子的 childId（同步）。
  ///
  /// [initialize] 后 = 活跃档案 id；未初始化 / 桩模式 = [kChildIdDefault]
  /// （Plan B 语义，既有调用方零感知）。
  String get childId => _active?.id ?? kChildIdDefault;

  /// 当前孩子的 childId（语义化别名，供编排层调用，与 [childId] 等价）。
  ///
  /// ⚠️ 调用签名不得变（`RedemptionOrchestrationService` 依赖）。
  String currentChildId() => childId;

  /// 当前孩子的年龄段（C90 期 2 第二批：**年龄段跟孩子走**，玄参拍板）。
  ///
  /// 有档案 → 档案 `ageTier`；无档案（未初始化 / 桩模式 / 空表）→ 回退全局
  /// settings 单行值，再回退 [AgeTier.high] —— 与隔离前「读全局设置」行为逐位
  /// 一致，既有调用方（未注入依赖的测试）零感知。
  Future<AgeTier> currentAgeTier() async {
    final ChildProfile? profile = await currentProfile();
    if (profile != null) return profile.ageTier;
    return (await _settings?.getSettings())?.ageTier ?? AgeTier.high;
  }

  /// 确保当前孩子档案存在（幂等别名 = [initialize]）。
  Future<void> ensureChild() => initialize();

  /// 切换当前孩子（家长天地入口；孩子端零改动）。
  ///
  /// [id] 必须是已存档案，否则抛 [ArgumentError]；成功后写 SP 持久化。
  Future<void> switchTo(String id) async {
    final ChildProfileRepository? repo = _children;
    // dev 侧异常文案一律 ASCII 英文（i18n B3 · T05 裁定）：`StateError` /
    // `ArgumentError` 只进开发者日志与测试断言，**永不预上屏**，故不进 ARB。
    if (repo == null) {
      throw StateError('AccountService: dependencies not injected (stub mode)');
    }
    final List<ChildProfile> list = await repo.children();
    for (final ChildProfile c in list) {
      if (c.id == id) {
        _active = c;
        await _prefs?.setString(kPrefActiveChildId, id);
        return;
      }
    }
    throw ArgumentError.value(id, 'id', 'child profile not found');
  }

  /// 新建孩子档案（门控配额判定在调用方：矩阵单点 `quotaAllowsAdd`）。
  Future<ChildProfile> createChild(String name, AgeTier ageTier) {
    final ChildProfileRepository? repo = _children;
    if (repo == null) {
      throw StateError('AccountService: dependencies not injected (stub mode)');
    }
    return repo.create(name, ageTier);
  }

  /// 当前活跃档案快照（未初始化时惰性加载，不建默认孩子；桩模式返 null）。
  Future<ChildProfile?> currentProfile() async {
    if (_active != null) return _active;
    final ChildProfileRepository? repo = _children;
    if (repo == null) return null;
    final List<ChildProfile> list = await repo.children();
    if (list.isEmpty) return null;
    final String? savedId = _prefs?.getString(kPrefActiveChildId);
    for (final ChildProfile c in list) {
      if (c.id == savedId) return _active = c;
    }
    return _active = list.first;
  }

  /// 登录（云同步留桩，C1）。
  Never signIn() => throw UnsupportedError('account disabled in Plan B');

  /// 关联家庭（云同步留桩，C1）。
  Never linkFamily() => throw UnsupportedError('account disabled in Plan B');

  /// 同步档案（云同步留桩，C1）。
  Never syncProfile() => throw UnsupportedError('account disabled in Plan B');
}
