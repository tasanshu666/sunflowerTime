/// 账号服务（Plan B 单机版留桩，§3.2 / §7.6 / C1）。
///
/// Plan B 无多账号 / 云同步：固定单孩子 `childId`，所有账号相关能力一律抛
/// `UnsupportedError('account disabled in Plan B')`。V2 多档案时再落地真实实现。
library account_service;

import 'package:sunflower_time/core/constants/prd_params.dart';

class AccountService {
  /// 当前孩子的固定 childId（Plan B 单孩子）。
  String get childId => kChildIdDefault;

  /// 当前孩子的固定 childId（语义化别名，供编排层调用，与 [childId] 等价）。
  String currentChildId() => kChildIdDefault;

  /// 确保当前孩子档案存在（Plan B 不需要，留桩）。
  Future<void> ensureChild() =>
      throw UnsupportedError('account disabled in Plan B');

  /// 登录（Plan B 不支持）。
  Never signIn() => throw UnsupportedError('account disabled in Plan B');

  /// 关联家庭（Plan B 不支持）。
  Never linkFamily() => throw UnsupportedError('account disabled in Plan B');

  /// 同步档案（Plan B 不支持）。
  Never syncProfile() => throw UnsupportedError('account disabled in Plan B');
}
