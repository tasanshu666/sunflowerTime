/// 守卫战 v2 · **素材单点替换口**（设计文档 §3.4 / §7-B5）。
///
/// ## 这是什么
/// 每个素材位一个取值函数；**素材在位走真图 / 帧序列，缺失时回退
/// `BoxDecoration` 色块占位** —— 占位色块即低保真可玩，缺失分支绝不 crash。
///
/// ## B5b 接入状态（2026-11-10 玄参第一批；管线 `tools/convert_guard_b5b.py`）
/// | 素材位 | 资产 | 缺失回退 |
/// |---|---|---|
/// | L1 场景卡底图 | `assets/guard/house.webp`（房屋 1984×1118） | 奶油绿渐变 |
/// | 战士待机（L3 右侧） | `assets/guard/soldier_idle/frame001..019.webp` 循环 | 金色块 |
/// | 战士攻击（开火瞬间 300ms） | `assets/guard/soldier_attack.webp` | 金色块 |
/// | 战士胜利（横幅时刻） | `assets/guard/soldier_win.webp` | 金色块 |
/// | m1 怪行走 | `assets/guard/monster_m1/frame001..007.webp` 循环 | 棕色块 |
/// | m2 怪行走 | `assets/guard/monster_m2/frame001..007.webp` 循环（B9/D2 接入） | 绿色块 |
/// | m3 怪行走 | `assets/guard/monster_m3/frame001..007.webp` 循环（B9/D2 接入） | 灰紫块 |
/// | 子弹 / 开火钮 / 能量点两态 | 🔴 玄参未画，**仍占位** | （即占位） |
///
/// ## 🔴 B9：素材已按**实体并集 bbox** 裁掉透明边（`tools/convert_guard_b5b.py`）
/// 裁边前战士实体只占画布 ~26% 面积 ⇒ 标称 72pt 肉眼只有 ~36pt（玄参「太小」的
/// 全部原因）。裁边后**标称 = 视觉**：战士 78pt 就是肉眼 78pt。
/// 战士三态用 `BoxFit.fitHeight` 绘制（**禁止 contain**，否则攻击帧会被按宽度
/// 缩到 53pt，一开火就变小），横向溢出由卡内 `OverflowBox` 放行。
///
/// ⚠️ `assets/guard/` 的**浇水变体**（房屋浇水）本批不接（设计：底图只有晴态）。
///
/// ## 换素材怎么改
/// 只改**这一个文件**：路径常量在 `_GuardAssetPaths`；帧数不写死（
/// `resolveFxFrames` 读 AssetManifest 实测，玄参补帧/删帧零代码改动）。
///
/// ## 占位色约定（PRD §6 / 设计 §3.4）
/// 战士 = 金色块、m1 = 棕色块、m2 = 绿色块、m3 = 灰紫色块、
/// 子弹 = 亮黄圆点、底图 = 奶油绿渐变。
library guard_art;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart'
    show GuardChestTier;
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart'
    show GuardCardLayout;

/// 占位色（与设计 §3.4 的色约定逐条对应；素材位缺图时的回退色）。
const Color _soldierGold = Color(0xFFE8A600);
const Color _m1Brown = Color(0xFF8D6E63);
const Color _m2Green = Color(0xFF66BB6A);
const Color _m3GreyPurple = Color(0xFF7E57C2);
const Color _bulletYellow = Color(0xFFFFD54F);

/// B5b 资产路径契约（命名对齐《美术资源_序列帧与音频命名规范_v1》）。
abstract final class _GuardAssetPaths {
  /// 场景卡 L1 底图（房屋；浇水变体不接，见文件头注释）。
  static const String house = 'assets/guard/house.webp';

  /// 战士待机序列帧目录（19 帧，AssetManifest 实测）。
  static const String soldierIdleDir = 'assets/guard/soldier_idle';

  /// 战士站立静态（B12 新增：战斗进行中的「端枪站立」专用图 —— 玄参要求
  /// 攻击情况下的站立用这张单独的图，不用待机动作帧里的定格）。
  static const String soldierStand = 'assets/guard/soldier_stand.webp';

  /// 战士攻击静态（开火瞬间切换）。
  static const String soldierAttack = 'assets/guard/soldier_attack.webp';

  /// 战士胜利静态（胜利横幅时刻切换）。
  static const String soldierWin = 'assets/guard/soldier_win.webp';

  /// m1（馋光鼠）进攻序列帧目录（7 帧）。
  static const String monsterM1Dir = 'assets/guard/monster_m1';

  /// m2（食叶虫）进攻序列帧目录（7 帧；B9 接入）。
  static const String monsterM2Dir = 'assets/guard/monster_m2';

  /// m3（贪婪鼬）进攻序列帧目录（7 帧；B9 接入）。
  static const String monsterM3Dir = 'assets/guard/monster_m3';

  /// 「开始战斗」图标（🔴 B13.5：玄参 11:42 交付新版「开始战斗UI.jpg」
  /// —— 红底圆角方 + 双太阳矛，256²，圆角遮罩抠掉 jpg 四角黑底；
  /// 旧「金徽」版已覆盖）。
  static const String startButton = 'assets/guard/start_button.webp';

  /// 守卫成功旗帜动画帧目录（B13.3；10 帧 160²，循环播放）。
  static const String claimFlagDir = 'assets/guard/claim_flag';

  /// 普通宝箱帧目录（Guard-B13.11 T02；30 帧 512² WebP）。
  ///
  /// ⚠️ 目录常量本身在 `prd_params.dart`（[kGuardChestNormalDir] /
  /// [kGuardChestPremiumDir]）—— 那里同时被资产守卫测试（`test/m3/
  /// guard_chest_assets_guard_test.dart`）直读，单一真源不复制。
  static const String chestNormalDir = kGuardChestNormalDir;

  /// 高级宝箱帧目录。
  static const String chestPremiumDir = kGuardChestPremiumDir;

  /// buff 券卡面（🔴 B13.5：玄参交付 3 种券美术，无字 ——
  /// 名字 / 增益描述由 `GuardBuffChip` 用 ARB 文字叠，方便中英切换）。
  /// 施肥券美术**自带烤字**（zh「通用花肥」/ en 版），按语言二选一；
  /// 免费浇水 / 免费施肥券没有专属美术 ⇒ 复用浇水 / 施肥卡面。
  static const String voucherWater = 'assets/guard/buff_voucher/water.webp';
  static const String voucherLabor = 'assets/guard/buff_voucher/labor.webp';
  static const String voucherFertilizeZh =
      'assets/guard/buff_voucher/fertilize_zh.webp';
  static const String voucherFertilizeEn =
      'assets/guard/buff_voucher/fertilize_en.webp';

  /// 专注双券（加餐 / 放大）共用图标（🔴 B13.20b，玄参 2026-11-13：
  /// 「专注放大券和专注加餐券应该是同一个图标」）—— 即**专注页向日葵
  /// 待机动画的第一帧**（`assets/fx/focus/sunflower/idle/frame001.png`，
  /// 720×720；B13.20a 先给加餐券用了这张，本批放大券对齐同款；
  /// 目录常量真源见 `frame_sequence_player.dart` 的 [kFocusIdleFxDir]，
  /// 此处只引首帧文件）。
  static const String voucherFocusIcon =
      'assets/fx/focus/sunflower/idle/frame001.png';
}

/// 素材位取值函数集（纯静态，无状态；全部返回**新** widget）。
class GuardArt {
  const GuardArt._();

  /// 战士**攻击帧覆盖层**的 Key（B7）。
  ///
  /// 攻击帧是盖在待机帧序列**上面**的一层（帧序列一直挂在树里，见
  /// [soldier] 的说明）；测试据此判定「此刻渲染的是攻击帧」。
  static const Key attackOverlayKey = Key('guardSoldierAttackOverlay');

  /// 战士**帧序列层**（待机 / 站立）的 Key（B10/B2）。
  ///
  /// 🔴 玄参第五轮：「攻击的时候原地还站着一个待机的小人」—— 攻击帧只是
  /// **盖在上面**，下层帧序列没有隐藏 ⇒ 两个人物同屏。B10 给下层套一层
  /// `Opacity(opacity: attack ? 0 : 1)`：`RenderOpacity` 在 alpha = 0 时不绘制
  /// 子树（肉眼只剩攻击帧），但**子树仍然挂载**（AssetManifest 缓存 + 播放器
  /// 位置全保留，切回来同帧有画面、不闪占位色）。
  ///
  /// 测试读法：`tester.widget<Opacity>(find.byKey(idleLayerKey)).opacity`。
  static const Key idleLayerKey = Key('guardSoldierIdleLayer');

  /// 某个**素材状态层**的质心配准位移 `Transform` 的 Key（B11/C4）。
  ///
  /// [state] ∈ `'idle'` / `'attack'` / `'win'`（= `kGuardSoldierStateCentroidX`
  /// 的键）。测试读法：
  /// ```dart
  /// tester.widget<Transform>(find.byKey(GuardArt.centroidAlignKey('attack')))
  ///     .transform.getTranslation().x   // = 该状态层的横向位移（pt）
  /// ```
  /// 用 Key 而不是让测试自己算：位移值必须来自**真实 widget**，
  /// 否则「实现改了但测试还在按旧公式算」就会双双通过（假绿）。
  static Key centroidAlignKey(String state) =>
      Key('guardSoldierCentroidShift_$state');

  /// 素材位：场景卡 L1 通栏底图。
  /// 素材 = 房屋横图（cover 铺满）；缺失回退 = 奶油绿渐变（上浅下深，
  /// 与今日页底图同色系）。
  ///
  /// ⚠️ B6 起**场景卡不再调用本函数**（玄参裁定：cover 在 iPad 宽卡上把
  /// 1.77:1 的房屋图裁掉 75%，只剩巨型局部）。卡改为「程序化草地板（
  /// [GuardSceneCard] 内 `_GrassBackdrop`）+ [house]（contain 完整可见）」。
  /// 本函数保留是为了：① 两个美术测试（`guard_art_live` / `guard_art_fallback`）
  /// 仍以它为「房屋素材位」的验收入口；② 其它页面若需要一张通栏封面图可直接用。
  /// 需要「完整房子」请用 [house]。
  static Widget sceneBackground() {
    return SizedBox.expand(
      child: Image.asset(
        _GuardAssetPaths.house,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFEAF4DF), Color(0xFFD7E8C8)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }

  /// 素材位：**房屋本体**（B6）—— `contain` 完整可见，不被裁切。
  ///
  /// 与 [sceneBackground] 的区别只有 `fit`：室内/室外两张卡都按「房子是一个
  /// 完整物件」来摆（玄参：房子必须完整可见，且宽高比 ≈ 1.7746），
  /// 由调用方给定容器尺寸（[GuardCardLayout.houseRect]），本函数只负责画。
  /// 缺失回退 = 奶油绿渐变（与 [sceneBackground] 的回退同色，避免闪烁感）。
  static Widget house() {
    return SizedBox.expand(
      child: Image.asset(
        _GuardAssetPaths.house,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFEAF4DF), Color(0xFFD7E8C8)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }

  /// 素材位：向日葵战士（卡内 L3 **常驻位**，B7 起待机态也在树）。
  ///
  /// 三种姿态**共用同一个 [ _GuardSequence ] widget 类型**（只切参数）：
  ///  · [animate] = true、[attack] = false ⇒ 19 帧待机**循环**（待机 / 战斗收场后）；
  ///  · [animate] = false、[attack] = false ⇒ **静止定格首帧**（战斗进行中
  ///    「端枪站立」，玄参 B7：「fighting 静止站立 = idle frame001 静态不循环」）；
  ///  · [attack] = true ⇒ 攻击静态（开火瞬间 300ms）；
  ///  · [win] = true ⇒ 胜利静态（胜利横幅时刻；B11 起也走质心对齐）。
  ///
  /// 🔴 为什么是「同一 widget 类型切参数」而不是「换一个 widget」：换类型会丢掉
  /// 本 State（AssetManifest 解析结果 + 帧序列播放器位置）⇒ 每次开火都要重解析、
  /// 且会插进一帧占位色块（玄参最反感的「一闪一闪」）。同类型切参 ⇒ 帧缓存
  /// 与播放器位置全保留，三种姿态之间**零闪烁**切换。
  ///
  /// 🔴 **B11/C4**：三态各按**自己的身体质心**对齐绘制框中轴（见
  /// `GuardCardLayout.soldierStateAlignShiftX` 与 `kGuardSoldierStateCentroidX`）
  /// —— 玄参第六轮「攻击时人往左挪了一点」的治本项（根因是素材配准差 9.69pt，
  /// 不是定位公式算错）。
  static Widget soldier({
    bool animate = true,
    bool attack = false,
    bool win = false,
    bool stand = false,
  }) {
    return _GuardSequence(
      dir: _GuardAssetPaths.soldierIdleDir,
      fallbackColor: _soldierGold,
      animate: animate,
      stillAsset: attack
          ? _GuardAssetPaths.soldierAttack
          : (win
              ? _GuardAssetPaths.soldierWin
              : (stand ? _GuardAssetPaths.soldierStand : null)),
      // 🔴 B9：**高度铺满、宽度按素材比例横向溢出**（不用 contain）。
      // 素材已按实体裁边：待机 362×372（宽 0.973h）、攻击 512×349（宽 1.467h）。
      // contain 会把攻击帧按宽度缩到 53pt（一开火就变小）；fitHeight 让三种姿态
      // 都是同一高度（B10/C1 起 **68pt**，玄参「68 刚好」——B11 锁定不动），
      // 攻击帧左右各溢出 ~15.8pt（只闪 300ms，压在房子/跑道上很自然）。
      fit: BoxFit.fitHeight,
      // 🔴 B10/B2：只有**战士**这一层需要「攻击时隐藏下层」的可测锚点
      // （三种怪的帧序列没有叠层，共用同一个 key 会让 finder 命中多个）。
      idleLayerKey: GuardArt.idleLayerKey,
      // 🔴 B11/C4：两层的「素材状态」——由它们查质心常量，算出各自的横向配准位移。
      // 🔴 B12：stand（战斗站立静态）也必须配准 —— 0.5262 已入表
      // （漏了它 stand 身体就会比 idle 偏 ~7pt，与 B11 治的「两个人错位」同病）。
      idleStateKey: 'idle',
      stillStateKey: attack
          ? 'attack'
          : (win ? 'win' : (stand ? 'stand' : null)),
    );
  }

  /// 素材位：战士攻击静态（L4 开火瞬间切 300ms，见 guard_battle_field）。
  static Widget soldierAttack() {
    return _staticAsset(_GuardAssetPaths.soldierAttack, _soldierGold,
        fit: BoxFit.fitHeight);
  }

  /// 素材位：战士胜利静态（Victory 横幅时刻切换）。
  static Widget soldierWin() {
    return _staticAsset(_GuardAssetPaths.soldierWin, _soldierGold,
        fit: BoxFit.fitHeight);
  }

  /// 素材位：怪物行走帧。
  ///
  /// B9/D2 起 **m1（馋光鼠）/ m2（食叶虫）/ m3（贪婪鼬）三种怪都有真实 7 帧
  /// 序列**；占位色块只在素材缺失时兜底（`_GuardSequence` 内部三级回退）。
  /// [frameIndex] 是 B2 时代的占位翻帧参数：真帧序列有自己的时间轴，**忽略**；
  /// 占位分支同样不消费它（guard_art_fallback_test ③ 钉「帧号不影响占位色」）。
  static Widget monsterWalk(GuardBattleMonsterKind kind, int frameIndex) {
    // 🔴 B9：三种怪都有真实 7 帧序列（m2 食叶虫 / m3 贪婪鼬 已交付）。
    // 占位色块只在**素材缺失**时兜底（`_GuardSequence` 内部三级回退）。
    //
    // 🔴 B9.1：**与战士同一套口径 —— `BoxFit.fitHeight`，不用 contain**。
    // 裁边后三种怪的画布比例差一倍（m1 1.261 / m2 1.000 / m3 1.918），
    // contain 按宽度贴边 ⇒ 贪婪鼬只有 22.9pt 高（食叶虫的一半，玄参一眼就会说
    // 「小怪大小不一」）。fitHeight 让三种怪**高度恒等 44pt**，宽度各自按原图
    // 比例横向溢出（由战斗层的 `OverflowBox` 放行、不裁）。
    switch (kind) {
      case GuardBattleMonsterKind.m1:
        return const _GuardSequence(
          dir: _GuardAssetPaths.monsterM1Dir,
          fallbackColor: _m1Brown,
          fit: BoxFit.fitHeight,
        );
      case GuardBattleMonsterKind.m2:
        return const _GuardSequence(
          dir: _GuardAssetPaths.monsterM2Dir,
          fallbackColor: _m2Green,
          fit: BoxFit.fitHeight,
        );
      case GuardBattleMonsterKind.m3:
        return const _GuardSequence(
          dir: _GuardAssetPaths.monsterM3Dir,
          fallbackColor: _m3GreyPurple,
          fit: BoxFit.fitHeight,
        );
    }
  }

  /// 素材位：阳光弹（L4 子弹层）。🔴 素材未画，占位。
  static Widget bullet() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: _bulletYellow,
        shape: BoxShape.circle,
      ),
      child: SizedBox.expand(),
    );
  }

  /// 素材位：开火大圆钮（L3 战斗态；PRD 素材清单 #11「常态 + 按下两态」，
  /// P2 素材到位前用既有圆形按钮体系顶）。🔴 素材未画，占位。
  static Widget fireButton() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: _soldierGold,
        shape: BoxShape.circle,
      ),
      child: SizedBox.expand(),
    );
  }

  /// 素材位：能量点两态（点亮 = 金色实心 / 未点亮 = 灰色描边；PRD 素材清单 #9）。
  /// 🔴 素材未画，占位。
  static Widget energyDot({required bool lit}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: lit ? _soldierGold : const Color(0x00000000),
        shape: BoxShape.circle,
        border: lit
            ? Border.all(color: const Color(0xFFB37400), width: 1.5)
            : Border.all(color: const Color(0xFFB9AE96), width: 1.5),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// 静态素材位通用实现：`Image.asset` + 缺失回退色块。
  static Widget _staticAsset(String path, Color fallbackColor,
      {BoxFit fit = BoxFit.contain}) {
    return SizedBox.expand(
      child: Image.asset(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            ColoredBox(color: fallbackColor, child: const SizedBox.expand()),
      ),
    );
  }

  /// 素材位：**「开始战斗」金徽图标**（B13.3，玄参交付）。
  ///
  /// 场景卡右簇开始钮整体替换：素材自带金色圆角框底（256×252），原「橙色圆 +
  /// play 箭头」退役。contain 在 64pt 槽位完整可见；缺失回退 = 金色圆块
  /// （调用方已包 Semantics，按钮语义不依赖图）。
  static Widget startButton() {
    return _staticAsset(_GuardAssetPaths.startButton, _soldierGold);
  }

  /// 素材位：**守卫成功旗帜动画**（B13.3，玄参交付 10 帧 160²）。
  ///
  /// claimed 徽章占位旗（Material `flag_rounded`）替换为真实帧动画，循环播放；
  /// 帧数由 AssetManifest 实测（玄参补帧/删帧零代码改动）；缺失回退金色块
  /// （徽章上还有「成功守卫」文字兜底语义）。
  static Widget claimFlag() {
    return const _GuardSequence(
      dir: _GuardAssetPaths.claimFlagDir,
      fallbackColor: _soldierGold,
      animate: true,
      fit: BoxFit.contain,
    );
  }

  /// buff 券卡面路径（🔴 B13.5；B13.20a/b 加专注双券共用图标）。
  ///
  /// * 浇水 / 劳动美术**无烤字**（名字 / 描述由 `GuardBuffChip` 叠 ARB 文字）；
  /// * 施肥美术自带烤字（zh「通用花肥」/ en 版）⇒ 按语言二选一；
  /// * 免费浇水 / 免费施肥（含 B13.19 的 ×3 / ×2 版）没有专属美术 ⇒ 复用
  ///   浇水 / 施肥卡面（券名与描述仍用自己的 ARB 文案，卡面相同但文字不同，
  ///   不混淆）；
  /// * 🔴 **专注加餐券 / 专注放大券共用同一图标** = 专注页向日葵待机首帧
  ///   （玄参 2026-11-13 两轮拍板：20a 先给加餐券，20b 放大券对齐同款）。
  static String voucherArtPath(GuardDropKind kind, {required bool isZh}) {
    switch (kind) {
      case GuardDropKind.waterVoucher:
      case GuardDropKind.freeWater:
      case GuardDropKind.freeWater3:
        return _GuardAssetPaths.voucherWater;
      case GuardDropKind.laborVoucher:
        return _GuardAssetPaths.voucherLabor;
      case GuardDropKind.fertilizeVoucher:
      case GuardDropKind.freeFertilize:
      case GuardDropKind.freeFertilize2:
        return isZh
            ? _GuardAssetPaths.voucherFertilizeZh
            : _GuardAssetPaths.voucherFertilizeEn;
      case GuardDropKind.focusMeal:
      case GuardDropKind.focusBoost:
        // 🔴 B13.20b：专注双券共用同一图标 = 专注页向日葵待机首帧
        // （玄参「应该是同一个图标」；券名 / 描述仍各自用 ARB 文案区分）。
        return _GuardAssetPaths.voucherFocusIcon;
      case GuardDropKind.none:
        return _GuardAssetPaths.voucherWater; // 不可达（chip 不渲染 none）
    }
  }

  /// buff 券卡面图（缺失回退 = 金色块，不 crash）。
  ///
  /// 🔴 B13.8：素材已二次裁切（328×475 带上下空白带 → **276×294**，只剩中间
  /// 插画），回退块比例同步改 276/294。
  ///
  /// 🔴 B13.20a/b：**专注双券**图标是 **720×720 正方形**（专注待机首帧），
  /// 在 276:294 的槽里用 `contain` 完整可见（左右仅 ~3% 留白；`fitWidth` 会
  /// 裁掉向日葵头顶/盆底各 ~3%，不裁）。其余卡面维持 `fitWidth`（窄图铺满槽宽）。
  static Widget voucherCard(GuardDropKind kind, {required bool isZh}) {
    final bool squareIcon =
        kind == GuardDropKind.focusMeal || kind == GuardDropKind.focusBoost;
    return Image.asset(
      voucherArtPath(kind, isZh: isZh),
      fit: squareIcon ? BoxFit.contain : BoxFit.fitWidth,
      errorBuilder: (_, __, ___) => const AspectRatio(
        aspectRatio: 276 / 294,
        child: ColoredBox(color: _soldierGold),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 宝箱（Guard-B13.11 T03）：帧目录解析 + 静态展示帧
  // ══════════════════════════════════════════════════════════════════════

  /// 宝箱帧目录（`GuardChestTier.normal` → 普通档 / `premium` → 高级档）。
  ///
  /// 纯函数，可单测；目录常量真源在 [kGuardChestNormalDir] / [kGuardChestPremiumDir]。
  static String chestDirOf(GuardChestTier tier) => tier.isPremium
      ? _GuardAssetPaths.chestPremiumDir
      : _GuardAssetPaths.chestNormalDir;

  /// 宝箱**静态展示帧**路径（= 各档 `frame001.webp`）。
  ///
  /// 🔴 为什么是 `frame001` 而不是「解析出来的第一张」：A-03 资产守卫测试钉死
  /// 「`frame001` 必须是字典序第一张」，故静图 == 动画首帧 ⇒ 点击切入动画时
  /// **零跳变**。写死这一条比运行时排序更早暴露漂移（排序得错也只是静默偏移）。
  static String chestStillPath(GuardChestTier tier) =>
      '${chestDirOf(tier)}/frame001.$kGuardChestFrameExt';

  /// 宝箱帧列表（AssetManifest 实测，帧数不写死；清单不可用 ⇒ 契约推导 30 帧）。
  ///
  /// 与既有 `_guardFrameCache` 同一套缓存纪律：同一档只解析一次清单。
  static Future<List<String>> chestFrames(GuardChestTier tier) {
    final String dir = chestDirOf(tier);
    final List<String>? cached = _guardFrameCache[dir];
    if (cached != null) return Future<List<String>>.value(cached);
    return resolveFxFrames(
      dir,
      ext: kGuardChestFrameExt,
      fallbackCount: kGuardChestFrameCount,
    ).then((List<String> frames) {
      // 空列表也缓存（目录整体丢失时不必每帧重读清单）。
      return _guardFrameCache[dir] = frames;
    });
  }

  /// 宝箱静态图（`BoxFit.contain`；缺失回退金色块 —— 掉落中也不留空白）。
  static Widget chestStill(GuardChestTier tier) {
    return Image.asset(
      chestStillPath(tier),
      fit: BoxFit.contain,
      // ⚠️ 必须显式传宽高（项目硬规则：loose 约束下无宽高会按原图 512² 撑爆）。
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const ColoredBox(color: _soldierGold),
    );
  }
}

/// 「目录 → 帧列表」进程级缓存（key = 目录名；避免每帧 build 重复解析清单）。
final Map<String, List<String>> _guardFrameCache = <String, List<String>>{};

/// 守卫战循环帧序列：AssetManifest 实测目录里的 `frame*.webp`（帧数不写死），
/// **空 / 清单不可读 / 加载异常 ⇒ 回退占位色块**（缺失分支绝不 crash）。
class _GuardSequence extends StatefulWidget {
  const _GuardSequence({
    required this.dir,
    required this.fallbackColor,
    this.animate = true,
    this.stillAsset,
    this.fit = BoxFit.contain,
    this.idleLayerKey,
    this.idleStateKey,
    this.stillStateKey,
  });

  /// 序列帧目录（`assets/guard/...`）。
  final String dir;

  /// 素材缺失时的占位色（设计 §3.4）。
  final Color fallbackColor;

  /// 是否循环播放（false ⇒ **只播首帧并定格**，用于「战斗进行中站立」）。
  final bool animate;

  /// 帧图绘制方式（[GuardArt.soldier] 传 `fitHeight`，见那里的说明）。
  final BoxFit fit;

  /// 帧序列层（下层）`Opacity` 的 Key（**仅战士**传；见 [GuardArt.idleLayerKey]）。
  ///
  /// 为什么不做成常量：三种怪的帧序列在同一个 `Stack` 语义里也可能有叠层，
  /// 共用一个 key 会让 `find.byKey` 命中多个 widget（实测踩到）。
  final Key? idleLayerKey;

  /// 帧序列层对应的**素材状态键**（`'idle'`；查 `kGuardSoldierStateCentroidX`
  /// 得质心、算横向配准位移）。为 null ⇒ 不做配准（怪的行序列不配准）。
  final String? idleStateKey;

  /// 静态层对应的**素材状态键**（`'attack'` / `'win'`；同上）。为 null ⇒ 不配准。
  final String? stillStateKey;

  /// 非空 ⇒ 不播帧序列，直接渲染这张**静态图**（战士攻击帧用）。
  ///
  /// 🔴 静态图与帧序列共用同一个 State：切到攻击帧再切回来，帧列表缓存与
  /// 播放器位置都不丢（见 [GuardArt.soldier] 的说明）。
  final String? stillAsset;

  @override
  State<_GuardSequence> createState() => _GuardSequenceState();
}

class _GuardSequenceState extends State<_GuardSequence> {
  Future<List<String>>? _frames;

  Future<List<String>> _resolve() async {
    final String key = widget.dir;
    final List<String>? cached = _guardFrameCache[key];
    if (cached != null) return cached;
    // fallbackCount = 0：目录里一帧都没有 → 空列表 → build 回退占位色块
    // （与 frame_sequence_player 的三级回退同口径，但守卫位不做契约推导 ——
    // 占位色块本身就是设计里的「未交付」态）。
    final List<String> frames =
        await resolveFxFrames(key, ext: 'webp', fallbackCount: 0);
    return _guardFrameCache[key] = List<String>.unmodifiable(frames);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frames ??= _resolve();
  }

  @override
  void didUpdateWidget(covariant _GuardSequence oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🔴 B9：**目录换了必须重新解析帧列表**。同一个树位置换素材（调试剧本
    // 重开战局后该槽位换成另一种怪 / 测试里换素材位）时 State 会被复用，
    // 若不重置 `_frames` 就会一直播上一只怪的帧（画面串线，实测踩到）。
    if (oldWidget.dir != widget.dir) {
      _frames = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? still = widget.stillAsset;
    // 🔴 帧序列**永远挂在树里**（攻击帧只是盖在上面的一层）：
    // 若改成「攻击时换掉整棵子树」，切回待机就要重建 FutureBuilder ⇒ 一帧
    // 占位色块（玄参最反感的「一闪一闪」）+ 每枪一次无谓重解析。
    //
    // 🔴 B10/B2：但**下层的可见性必须跟着切** —— 攻击帧（512×349 ⇒ 比待机帧
    // 宽）盖不住下面的待机小人，玄参就会看到「两个人物」。故帧序列层包一层
    // `Opacity`：攻击时 opacity = 0（`RenderOpacity` 在 0 时**跳过整棵子树
    // 的绘制** ⇒ 只剩攻击帧），子树本身仍挂载 ⇒ 缓存与播放位置都不丢。
    //
    // 🔴 B11/C4：每层再各套一个**质心配准位移**（`Transform.translate`）——
    // 三态的 alpha 加权质心在各自画布里位置不同（0.5559 / 0.4400 / 0.4660），
    // 「实体框居中」必然让身体错位 9.69pt；按质心位移后三态身体共线。
    // 这个 Transform **只影响绘制**（不消耗布局），且绘制框本来就留了余量
    // （113.33 > 攻击帧 99.76 + 位移 5.99）⇒ 与 B10 削顶那次的 `Transform` 无关。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 绘制框高度是**紧约束**（卡内 OverflowBox 给的 68 × scale）。
        final double paintHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0;
        return Stack(
          fit: StackFit.expand,
          // 🔴 B9/C2：允许横向溢出（攻击帧比 68 宽的框宽 99.76，由卡内
          // `OverflowBox` 居中放行）—— 这里绝不能裁。
          clipBehavior: Clip.none,
          children: <Widget>[
            _centroidAligned(
              stateKey: widget.idleStateKey,
              paintHeight: paintHeight,
              child: Opacity(
                key: widget.idleLayerKey,
                opacity: still == null ? 1.0 : 0.0,
                child: _sequence(),
              ),
            ),
            if (still != null)
              Positioned.fill(
                key: GuardArt.attackOverlayKey,
                child: _centroidAligned(
                  stateKey: widget.stillStateKey,
                  paintHeight: paintHeight,
                  child: GuardArt._staticAsset(still, widget.fallbackColor,
                      fit: widget.fit),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 按 [stateKey] 把 [child] 横向位移「使身体质心落在绘制框中轴」。
  ///
  /// `stateKey == null`（三种怪的帧序列）⇒ 原样返回，行为与 B10 逐位相同。
  /// 🔴 位移量 = `GuardCardLayout.soldierStateAlignShiftX(state, 绘制高)`；
  /// 测试经 [GuardArt.centroidAlignKey] 直接读这个 `Transform` 的 `dx`。
  Widget _centroidAligned({
    required String? stateKey,
    required double paintHeight,
    required Widget child,
  }) {
    if (stateKey == null) return child;
    final double dx =
        GuardCardLayout.soldierStateAlignShiftX(stateKey, paintHeight);
    return Transform.translate(
      key: GuardArt.centroidAlignKey(stateKey),
      offset: Offset(dx, 0),
      child: child,
    );
  }

  /// 帧序列本体（待机循环 / 站立定格）。
  ///
  /// 🔴 B13.20c（玄参 2026-11-13 真机反馈「看到的是方块闪烁不是怪物闪烁」）：
  /// FutureBuilder 必须带 `initialData` —— 帧目录缓存（`_guardFrameCache`）是
  /// **全局**的，任何上层把本 State 销毁重建（B13.20b 受击闪动曾用「条件包
  /// Opacity」改树结构，开始/结束各重建一次）时，waiting 帧若无 initialData
  /// 就会画一帧兜底色块 ⇒ 实机表现为「绿方块在闪」。带 initialData 后：
  /// 缓存命中 ⇒ 第一帧就画真帧序列，重建零感知；首次加载（无缓存）仍走
  /// 原兜底（仅首次，可接受）。
  Widget _sequence() {
    return FutureBuilder<List<String>>(
      future: _frames,
      // 🔴 同步读全局缓存当 initialData：State 重建时立刻有帧可画。
      initialData: _guardFrameCache[widget.dir],
      builder: (BuildContext context, AsyncSnapshot<List<String>> snap) {
        final bool ready = snap.hasData && snap.data!.isNotEmpty;
        if (!ready) {
          // 等待中 / 缺失：占位色块（低保真可玩，不白屏不 crash）。
          return ColoredBox(
            color: widget.fallbackColor,
            child: const SizedBox.expand(),
          );
        }
        // 定格模式（`animate == false`）只把**首帧**交给播放器：
        // 单帧 + loop ⇒ 画面恒定不动，且不会像 loop:false 那样播完渐隐消失。
        final List<String> frames = widget.animate
            ? snap.data!
            : <String>[snap.data!.first];
        return FrameSequencePlayer(
          frames: frames,
          fit: widget.fit,
          // 单帧时长 × 帧数（帧数变化不改常量，节奏恒定）。
          durationMs: frames.length * kGuardAnimFrameMs,
          loop: true,
        );
      },
    );
  }
}
