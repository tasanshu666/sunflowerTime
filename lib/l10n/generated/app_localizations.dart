import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @app_title.
  ///
  /// In zh, this message translates to:
  /// **'SunFocus 向日葵专注'**
  String get app_title;

  /// No description provided for @consent_welcome_title.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用向日葵专注'**
  String get consent_welcome_title;

  /// No description provided for @consent_compliance_body.
  ///
  /// In zh, this message translates to:
  /// **'· 我们只收集专注时长、打卡等必要数据；\n· 全部数据加密存储在本机，不上传云端；\n· 无账号、无广告、无社交，不采集通讯录与位置。'**
  String get consent_compliance_body;

  /// No description provided for @consent_btn_agree.
  ///
  /// In zh, this message translates to:
  /// **'同意并开始'**
  String get consent_btn_agree;

  /// No description provided for @consent_btn_back_garden.
  ///
  /// In zh, this message translates to:
  /// **'返回花园'**
  String get consent_btn_back_garden;

  /// No description provided for @shared_lang_title.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get shared_lang_title;

  /// No description provided for @shared_lang_follow_system.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get shared_lang_follow_system;

  /// No description provided for @shared_ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get shared_ok;

  /// No description provided for @shared_unlimited.
  ///
  /// In zh, this message translates to:
  /// **'不限'**
  String get shared_unlimited;

  /// No description provided for @parent_settings_lang_entry.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get parent_settings_lang_entry;

  /// No description provided for @premium_gate_feature_one_click_care.
  ///
  /// In zh, this message translates to:
  /// **'花园一键操作'**
  String get premium_gate_feature_one_click_care;

  /// No description provided for @premium_gate_feature_pot_capacity.
  ///
  /// In zh, this message translates to:
  /// **'更多花盆'**
  String get premium_gate_feature_pot_capacity;

  /// No description provided for @premium_gate_feature_parent_report.
  ///
  /// In zh, this message translates to:
  /// **'家长专注报告'**
  String get premium_gate_feature_parent_report;

  /// No description provided for @premium_gate_feature_task_templates.
  ///
  /// In zh, this message translates to:
  /// **'更多成长项模板'**
  String get premium_gate_feature_task_templates;

  /// No description provided for @premium_gate_feature_reward_templates.
  ///
  /// In zh, this message translates to:
  /// **'更多奖励模板'**
  String get premium_gate_feature_reward_templates;

  /// No description provided for @premium_gate_feature_multi_child.
  ///
  /// In zh, this message translates to:
  /// **'多孩子档案'**
  String get premium_gate_feature_multi_child;

  /// No description provided for @premium_gate_feature_deep_report.
  ///
  /// In zh, this message translates to:
  /// **'深度专注报告'**
  String get premium_gate_feature_deep_report;

  /// No description provided for @premium_gate_feature_export_share.
  ///
  /// In zh, this message translates to:
  /// **'数据导出与分享'**
  String get premium_gate_feature_export_share;

  /// No description provided for @premium_gate_feature_memoir_export.
  ///
  /// In zh, this message translates to:
  /// **'纪念册导出'**
  String get premium_gate_feature_memoir_export;

  /// No description provided for @premium_gate_feature_family_sharing.
  ///
  /// In zh, this message translates to:
  /// **'家庭共享'**
  String get premium_gate_feature_family_sharing;

  /// No description provided for @premium_gate_feature_title_perks.
  ///
  /// In zh, this message translates to:
  /// **'称号专属属性'**
  String get premium_gate_feature_title_perks;

  /// No description provided for @premium_gate_upsell_title.
  ///
  /// In zh, this message translates to:
  /// **'解锁「{name}」'**
  String premium_gate_upsell_title(String name);

  /// No description provided for @premium_gate_upsell_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'一次买断，永久解锁全部功能'**
  String get premium_gate_upsell_subtitle;

  /// No description provided for @premium_gate_upsell_btn.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get premium_gate_upsell_btn;

  /// No description provided for @premium_gate_upsell_dialog_title.
  ///
  /// In zh, this message translates to:
  /// **'升级解锁'**
  String get premium_gate_upsell_dialog_title;

  /// No description provided for @premium_gate_upsell_dialog_message.
  ///
  /// In zh, this message translates to:
  /// **'「{name}」需要一次性买断解锁。'**
  String premium_gate_upsell_dialog_message(String name);

  /// No description provided for @premium_gate_later.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get premium_gate_later;

  /// No description provided for @premium_gate_unlock_all.
  ///
  /// In zh, this message translates to:
  /// **'解锁全部功能'**
  String get premium_gate_unlock_all;

  /// No description provided for @premium_quota_snack.
  ///
  /// In zh, this message translates to:
  /// **'免费版最多 {limit}（当前 {count}），删除多余内容后即可新增'**
  String premium_quota_snack(String limit, int count);

  /// No description provided for @child_lock_title.
  ///
  /// In zh, this message translates to:
  /// **'睡觉时间'**
  String get child_lock_title;

  /// No description provided for @child_lock_sleeping.
  ///
  /// In zh, this message translates to:
  /// **'🌻 向日葵睡觉中'**
  String get child_lock_sleeping;

  /// No description provided for @child_lock_body.
  ///
  /// In zh, this message translates to:
  /// **'晚上 {hour}:00 后向日葵要休息啦，明天再陪你专注~'**
  String child_lock_body(int hour);

  /// No description provided for @child_rest_title.
  ///
  /// In zh, this message translates to:
  /// **'休息一下'**
  String get child_rest_title;

  /// No description provided for @child_rest_body.
  ///
  /// In zh, this message translates to:
  /// **'休息一下，喝口水～ 还剩 {sec} 秒'**
  String child_rest_body(int sec);

  /// No description provided for @child_rest_done.
  ///
  /// In zh, this message translates to:
  /// **'我休息好了'**
  String get child_rest_done;

  /// No description provided for @child_eyecare_countdown.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {sec} 秒'**
  String child_eyecare_countdown(int sec);

  /// No description provided for @child_eyecare_title.
  ///
  /// In zh, this message translates to:
  /// **'眼睛休息一下吧'**
  String get child_eyecare_title;

  /// No description provided for @shared_back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get shared_back;

  /// No description provided for @shared_start_focus.
  ///
  /// In zh, this message translates to:
  /// **'开始专注'**
  String get shared_start_focus;

  /// No description provided for @shared_sunlight.
  ///
  /// In zh, this message translates to:
  /// **'阳光'**
  String get shared_sunlight;

  /// No description provided for @child_today_sunlight_title.
  ///
  /// In zh, this message translates to:
  /// **'今日获取阳光'**
  String get child_today_sunlight_title;

  /// No description provided for @child_today_focus_label.
  ///
  /// In zh, this message translates to:
  /// **'今日专注'**
  String get child_today_focus_label;

  /// No description provided for @child_today_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String child_today_minutes(int minutes);

  /// No description provided for @child_today_focus_count.
  ///
  /// In zh, this message translates to:
  /// **'· {count} 次'**
  String child_today_focus_count(int count);

  /// No description provided for @child_today_growth_label.
  ///
  /// In zh, this message translates to:
  /// **'今日成长'**
  String get child_today_growth_label;

  /// No description provided for @child_today_all_done.
  ///
  /// In zh, this message translates to:
  /// **'全部完成 🌻'**
  String get child_today_all_done;

  /// No description provided for @child_today_growth_hint.
  ///
  /// In zh, this message translates to:
  /// **'想赚成长阳光？从「成长」里点具体项目开始专注 🌻'**
  String get child_today_growth_hint;

  /// No description provided for @child_settle_secs.
  ///
  /// In zh, this message translates to:
  /// **'{sec} 秒'**
  String child_settle_secs(int sec);

  /// No description provided for @child_settle_mins.
  ///
  /// In zh, this message translates to:
  /// **'{min} 分钟'**
  String child_settle_mins(int min);

  /// No description provided for @child_settle_min_sec.
  ///
  /// In zh, this message translates to:
  /// **'{min} 分 {sec} 秒'**
  String child_settle_min_sec(int min, int sec);

  /// No description provided for @child_settle_task_label.
  ///
  /// In zh, this message translates to:
  /// **'成长项'**
  String get child_settle_task_label;

  /// No description provided for @child_settle_task_skipped.
  ///
  /// In zh, this message translates to:
  /// **'成长项结算没能完成，不影响本次专注阳光'**
  String get child_settle_task_skipped;

  /// No description provided for @child_settle_task_capped.
  ///
  /// In zh, this message translates to:
  /// **'（今日阳光已达上限，本次只到账 {sun} ☀）'**
  String child_settle_task_capped(String sun);

  /// No description provided for @child_settle_task_done.
  ///
  /// In zh, this message translates to:
  /// **'成长项「{name}」完成 +{sun} ☀{capped}'**
  String child_settle_task_done(String capped, String name, String sun);

  /// No description provided for @child_settle_task_progress.
  ///
  /// In zh, this message translates to:
  /// **'成长项「{name}」还差一点，下次专注够时长就算上啦 🌻'**
  String child_settle_task_progress(String name);

  /// No description provided for @child_settle_task_partial.
  ///
  /// In zh, this message translates to:
  /// **'提前结束 · 实际 {minutes} 分钟 · 完成度 {percent}% · 得 {sun} 阳光'**
  String child_settle_task_partial(int minutes, int percent, String sun);

  /// No description provided for @child_settle_title.
  ///
  /// In zh, this message translates to:
  /// **'专注结束啦'**
  String get child_settle_title;

  /// No description provided for @child_settle_this_session.
  ///
  /// In zh, this message translates to:
  /// **'本次专注'**
  String get child_settle_this_session;

  /// No description provided for @child_settle_collected.
  ///
  /// In zh, this message translates to:
  /// **'收集阳光'**
  String get child_settle_collected;

  /// No description provided for @child_settle_eyecare_reward.
  ///
  /// In zh, this message translates to:
  /// **'护眼奖励'**
  String get child_settle_eyecare_reward;

  /// No description provided for @child_settle_task_reward.
  ///
  /// In zh, this message translates to:
  /// **'任务奖励'**
  String get child_settle_task_reward;

  /// No description provided for @child_settle_today_total.
  ///
  /// In zh, this message translates to:
  /// **'今日累计'**
  String get child_settle_today_total;

  /// No description provided for @child_settle_balance.
  ///
  /// In zh, this message translates to:
  /// **'拥有阳光'**
  String get child_settle_balance;

  /// No description provided for @child_settle_too_short.
  ///
  /// In zh, this message translates to:
  /// **'这次太短啦，向日葵没来得及收集阳光（≥5 分钟才有产出哦）'**
  String get child_settle_too_short;

  /// No description provided for @child_settle_cap_title.
  ///
  /// In zh, this message translates to:
  /// **'🌻 今天专注额度用完啦'**
  String get child_settle_cap_title;

  /// No description provided for @child_settle_cap_body_detail.
  ///
  /// In zh, this message translates to:
  /// **'超出额度的部分就不再收集阳光了{detail}。{cheer}'**
  String child_settle_cap_body_detail(String cheer, String detail);

  /// No description provided for @child_settle_cap_orig_vs_net.
  ///
  /// In zh, this message translates to:
  /// **'（原本 {raw} ☀️，实到 {net} ☀️）'**
  String child_settle_cap_orig_vs_net(String net, String raw);

  /// No description provided for @child_settle_cap_cheer.
  ///
  /// In zh, this message translates to:
  /// **'今天已经很棒啦，明天再来吧！'**
  String get child_settle_cap_cheer;

  /// No description provided for @child_settle_home.
  ///
  /// In zh, this message translates to:
  /// **'回首页'**
  String get child_settle_home;

  /// No description provided for @child_feedback_collected.
  ///
  /// In zh, this message translates to:
  /// **'太好了，又收集到阳光了。'**
  String get child_feedback_collected;

  /// No description provided for @child_feedback_welcome_back.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来'**
  String get child_feedback_welcome_back;

  /// No description provided for @child_feedback_rest_hint.
  ///
  /// In zh, this message translates to:
  /// **'休息一下就回来哦'**
  String get child_feedback_rest_hint;

  /// No description provided for @child_feedback_miss.
  ///
  /// In zh, this message translates to:
  /// **'向日葵想你了，回来看看吧'**
  String get child_feedback_miss;

  /// No description provided for @child_avatar_pick.
  ///
  /// In zh, this message translates to:
  /// **'选择头像'**
  String get child_avatar_pick;

  /// No description provided for @child_avatar_hint.
  ///
  /// In zh, this message translates to:
  /// **'种下过的植物可以拿来当头像'**
  String get child_avatar_hint;

  /// No description provided for @child_cap_single_title.
  ///
  /// In zh, this message translates to:
  /// **'休息一下，等会再来玩'**
  String get child_cap_single_title;

  /// No description provided for @child_cap_daily_title.
  ///
  /// In zh, this message translates to:
  /// **'先歇一会儿吧'**
  String get child_cap_daily_title;

  /// No description provided for @child_cap_single_body.
  ///
  /// In zh, this message translates to:
  /// **'已经连续玩 {minutes} 分钟啦，让眼睛休息一下'**
  String child_cap_single_body(int minutes);

  /// No description provided for @child_cap_daily_body.
  ///
  /// In zh, this message translates to:
  /// **'今天逛 App 的时间用完啦'**
  String get child_cap_daily_body;

  /// No description provided for @child_cap_chip_rest.
  ///
  /// In zh, this message translates to:
  /// **'休息一会'**
  String get child_cap_chip_rest;

  /// No description provided for @child_cap_chip_daily.
  ///
  /// In zh, this message translates to:
  /// **'今日上限'**
  String get child_cap_chip_daily;

  /// No description provided for @child_cap_unlock_in.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟后解锁'**
  String child_cap_unlock_in(int minutes);

  /// No description provided for @child_cap_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String child_cap_minutes(int minutes);

  /// No description provided for @child_cap_chip_go_today.
  ///
  /// In zh, this message translates to:
  /// **'去「今日」'**
  String get child_cap_chip_go_today;

  /// No description provided for @child_cap_chip_earn.
  ///
  /// In zh, this message translates to:
  /// **'专注赚阳光'**
  String get child_cap_chip_earn;

  /// No description provided for @child_cap_btn_go_focus.
  ///
  /// In zh, this message translates to:
  /// **'去「今日」开始专注 🌻'**
  String get child_cap_btn_go_focus;

  /// No description provided for @child_cap_ok.
  ///
  /// In zh, this message translates to:
  /// **'知道啦'**
  String get child_cap_ok;

  /// No description provided for @child_entry_pick_duration.
  ///
  /// In zh, this message translates to:
  /// **'这次想专注多久？'**
  String get child_entry_pick_duration;

  /// No description provided for @child_entry_cap_daily.
  ///
  /// In zh, this message translates to:
  /// **'今天的专注时间已经用完啦（每日上限 {cap} 分钟），明天再来'**
  String child_entry_cap_daily(int cap);

  /// No description provided for @child_entry_remaining_today.
  ///
  /// In zh, this message translates to:
  /// **'今天还可以专注 {minutes} 分钟（每日上限 {cap} 分钟）'**
  String child_entry_remaining_today(int cap, int minutes);

  /// No description provided for @child_entry_free.
  ///
  /// In zh, this message translates to:
  /// **'自由'**
  String get child_entry_free;

  /// No description provided for @child_entry_custom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get child_entry_custom;

  /// No description provided for @child_entry_custom_title.
  ///
  /// In zh, this message translates to:
  /// **'自定义时长（分钟）'**
  String get child_entry_custom_title;

  /// No description provided for @child_entry_quota_empty.
  ///
  /// In zh, this message translates to:
  /// **'今日额度已用完'**
  String get child_entry_quota_empty;

  /// No description provided for @child_entry_custom_hint_max.
  ///
  /// In zh, this message translates to:
  /// **'可选 {max} 分钟以内'**
  String child_entry_custom_hint_max(int max);

  /// No description provided for @child_entry_custom_hint_capped.
  ///
  /// In zh, this message translates to:
  /// **'可选 {max} 分钟以内（受今日剩余额度限制）'**
  String child_entry_custom_hint_capped(int max);

  /// No description provided for @child_entry_options_title.
  ///
  /// In zh, this message translates to:
  /// **'专注时的小设置'**
  String get child_entry_options_title;

  /// No description provided for @child_entry_dnd.
  ///
  /// In zh, this message translates to:
  /// **'屏蔽通知（勿扰）'**
  String get child_entry_dnd;

  /// No description provided for @child_entry_dnd_hint.
  ///
  /// In zh, this message translates to:
  /// **'专注时屏蔽短信/来电等打扰'**
  String get child_entry_dnd_hint;

  /// No description provided for @child_entry_sound.
  ///
  /// In zh, this message translates to:
  /// **'提示音效'**
  String get child_entry_sound;

  /// No description provided for @child_entry_sound_hint.
  ///
  /// In zh, this message translates to:
  /// **'专注时播放轻提示音'**
  String get child_entry_sound_hint;

  /// No description provided for @child_entry_bgm.
  ///
  /// In zh, this message translates to:
  /// **'背景音乐'**
  String get child_entry_bgm;

  /// No description provided for @child_entry_bgm_hint.
  ///
  /// In zh, this message translates to:
  /// **'专注时循环轻柔背景乐'**
  String get child_entry_bgm_hint;

  /// No description provided for @child_entry_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String child_entry_minutes(int minutes);

  /// No description provided for @child_entry_cap_snack.
  ///
  /// In zh, this message translates to:
  /// **'今日专注已达上限（{cap} 分钟），明天再来哦'**
  String child_entry_cap_snack(int cap);

  /// No description provided for @child_entry_cap_snack2.
  ///
  /// In zh, this message translates to:
  /// **'今天的专注时间用完啦（上限 {cap} 分钟），明天再来哦'**
  String child_entry_cap_snack2(int cap);

  /// No description provided for @child_entry_remaining_snack.
  ///
  /// In zh, this message translates to:
  /// **'今天只剩 {remaining} 分钟额度了，这次就专注 {minutes} 分钟吧'**
  String child_entry_remaining_snack(int minutes, int remaining);

  /// No description provided for @child_focus_dnd_permission.
  ///
  /// In zh, this message translates to:
  /// **'请在系统设置中开启勿扰权限以屏蔽通知'**
  String get child_focus_dnd_permission;

  /// No description provided for @child_focus_exit_title.
  ///
  /// In zh, this message translates to:
  /// **'确定结束吗？'**
  String get child_focus_exit_title;

  /// No description provided for @child_focus_exit_body.
  ///
  /// In zh, this message translates to:
  /// **'向日葵还在这儿陪着你，要现在结束专注吗？'**
  String get child_focus_exit_body;

  /// No description provided for @child_focus_exit_stay.
  ///
  /// In zh, this message translates to:
  /// **'再坐一会'**
  String get child_focus_exit_stay;

  /// No description provided for @child_focus_exit_end.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get child_focus_exit_end;

  /// No description provided for @child_focus_debug_ff.
  ///
  /// In zh, this message translates to:
  /// **'调试：快进 5 分钟（护眼触发用）'**
  String get child_focus_debug_ff;

  /// No description provided for @child_focus_free_label.
  ///
  /// In zh, this message translates to:
  /// **'自由专注'**
  String get child_focus_free_label;

  /// No description provided for @child_focus_session_label.
  ///
  /// In zh, this message translates to:
  /// **'本次专注'**
  String get child_focus_session_label;

  /// No description provided for @child_focus_dnd_off.
  ///
  /// In zh, this message translates to:
  /// **'未开启勿扰，通知仍会打扰'**
  String get child_focus_dnd_off;

  /// No description provided for @child_focus_dnd_go.
  ///
  /// In zh, this message translates to:
  /// **'去开启'**
  String get child_focus_dnd_go;

  /// No description provided for @child_focus_wait_back.
  ///
  /// In zh, this message translates to:
  /// **'向日葵在等你回来'**
  String get child_focus_wait_back;

  /// No description provided for @child_focus_paused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get child_focus_paused;

  /// No description provided for @child_focus_buffer_eyecare.
  ///
  /// In zh, this message translates to:
  /// **'🌻 让眼睛休息一下吧'**
  String get child_focus_buffer_eyecare;

  /// No description provided for @child_focus_buffer_end.
  ///
  /// In zh, this message translates to:
  /// **'🌻 专注结束啦'**
  String get child_focus_buffer_end;

  /// No description provided for @child_focus_buffer_resume_hint.
  ///
  /// In zh, this message translates to:
  /// **'休息完继续加油哦'**
  String get child_focus_buffer_resume_hint;

  /// No description provided for @child_focus_buffer_eyecare2.
  ///
  /// In zh, this message translates to:
  /// **'让眼睛休息一下吧'**
  String get child_focus_buffer_eyecare2;

  /// No description provided for @child_focus_cap_notice.
  ///
  /// In zh, this message translates to:
  /// **'今天的专注额度用完啦，剩下的时间不再收集阳光，累了随时可以结束哦'**
  String get child_focus_cap_notice;

  /// No description provided for @child_focus_no_touch.
  ///
  /// In zh, this message translates to:
  /// **'本屏不可交互 · 竖屏即可结束'**
  String get child_focus_no_touch;

  /// No description provided for @child_shell_tab_today.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get child_shell_tab_today;

  /// No description provided for @child_shell_tab_growth.
  ///
  /// In zh, this message translates to:
  /// **'成长'**
  String get child_shell_tab_growth;

  /// No description provided for @child_shell_tab_garden.
  ///
  /// In zh, this message translates to:
  /// **'花园'**
  String get child_shell_tab_garden;

  /// No description provided for @child_shell_tab_store.
  ///
  /// In zh, this message translates to:
  /// **'商店'**
  String get child_shell_tab_store;

  /// No description provided for @child_shell_tab_mine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get child_shell_tab_mine;

  /// No description provided for @child_shell_verify_title.
  ///
  /// In zh, this message translates to:
  /// **'🎉 家长已确认你的兑换'**
  String get child_shell_verify_title;

  /// No description provided for @child_shell_item_reward.
  ///
  /// In zh, this message translates to:
  /// **'奖励'**
  String get child_shell_item_reward;

  /// No description provided for @child_shell_item_cost.
  ///
  /// In zh, this message translates to:
  /// **'-{sun} 阳光'**
  String child_shell_item_cost(int sun);

  /// No description provided for @child_shell_verify_total.
  ///
  /// In zh, this message translates to:
  /// **'共扣除 {total} 阳光'**
  String child_shell_verify_total(int total);

  /// No description provided for @child_shell_reject_title.
  ///
  /// In zh, this message translates to:
  /// **'🚫 兑换未被通过'**
  String get child_shell_reject_title;

  /// No description provided for @child_shell_reject_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'（{note}）'**
  String child_shell_reject_subtitle(String note);

  /// No description provided for @child_shell_reject_reason.
  ///
  /// In zh, this message translates to:
  /// **'家长拒绝了该申请'**
  String get child_shell_reject_reason;

  /// No description provided for @child_shell_reject_footer.
  ///
  /// In zh, this message translates to:
  /// **'本次阳光未被扣除，可重新兑换其他奖励'**
  String get child_shell_reject_footer;

  /// No description provided for @child_shell_task_footer_capped.
  ///
  /// In zh, this message translates to:
  /// **'今日成长奖励已达上限，本次没有新增阳光'**
  String get child_shell_task_footer_capped;

  /// No description provided for @child_shell_task_footer_partial.
  ///
  /// In zh, this message translates to:
  /// **'共获得 {total} 阳光（{capped} 项今日额度已满，未发放）'**
  String child_shell_task_footer_partial(int capped, int total);

  /// No description provided for @child_shell_task_footer.
  ///
  /// In zh, this message translates to:
  /// **'共获得 {total} 阳光'**
  String child_shell_task_footer(int total);

  /// No description provided for @child_shell_task_title.
  ///
  /// In zh, this message translates to:
  /// **'🎉 家长已确认你的成长任务'**
  String get child_shell_task_title;

  /// No description provided for @child_shell_task_fallback.
  ///
  /// In zh, this message translates to:
  /// **'成长任务'**
  String get child_shell_task_fallback;

  /// No description provided for @child_shell_task_item_sun.
  ///
  /// In zh, this message translates to:
  /// **'+{sun} 阳光'**
  String child_shell_task_item_sun(int sun);

  /// No description provided for @child_shell_task_item_capped.
  ///
  /// In zh, this message translates to:
  /// **'今日额度已满'**
  String get child_shell_task_item_capped;

  /// No description provided for @garden_settle_withered.
  ///
  /// In zh, this message translates to:
  /// **'花朵凋谢，奖励已自动收下：{parts}'**
  String garden_settle_withered(Object parts);

  /// No description provided for @shared_op_failed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String shared_op_failed(Object error);

  /// No description provided for @garden_shovel_refund.
  ///
  /// In zh, this message translates to:
  /// **'铲除成功，返还 {refund} ☀'**
  String garden_shovel_refund(int refund);

  /// No description provided for @garden_shovel_ok.
  ///
  /// In zh, this message translates to:
  /// **'铲除成功'**
  String get garden_shovel_ok;

  /// No description provided for @garden_collect_gift_prefix.
  ///
  /// In zh, this message translates to:
  /// **'盛开的礼物：{body}'**
  String garden_collect_gift_prefix(Object body);

  /// No description provided for @garden_cleared_weed.
  ///
  /// In zh, this message translates to:
  /// **'除草成功'**
  String get garden_cleared_weed;

  /// No description provided for @garden_cleared_pest.
  ///
  /// In zh, this message translates to:
  /// **'除虫成功'**
  String get garden_cleared_pest;

  /// No description provided for @garden_reward_sunlight.
  ///
  /// In zh, this message translates to:
  /// **'+{count} ☀ 阳光'**
  String garden_reward_sunlight(int count);

  /// No description provided for @garden_seed_decomposed.
  ///
  /// In zh, this message translates to:
  /// **'重复的「{name}」种子已分解为 {count} 植物碎片'**
  String garden_seed_decomposed(Object name, int count);

  /// No description provided for @garden_reward_fragments.
  ///
  /// In zh, this message translates to:
  /// **'+{count} 植物碎片'**
  String garden_reward_fragments(int count);

  /// No description provided for @garden_seed_dropped.
  ///
  /// In zh, this message translates to:
  /// **'掉落「{name}」种子'**
  String garden_seed_dropped(Object name);

  /// No description provided for @garden_gift_default.
  ///
  /// In zh, this message translates to:
  /// **'收到一份小礼物～'**
  String get garden_gift_default;

  /// No description provided for @garden_fx_sprout.
  ///
  /// In zh, this message translates to:
  /// **'发芽啦！🌱'**
  String get garden_fx_sprout;

  /// No description provided for @garden_fx_grow.
  ///
  /// In zh, this message translates to:
  /// **'长大啦！🌿'**
  String get garden_fx_grow;

  /// No description provided for @garden_fx_bloom.
  ///
  /// In zh, this message translates to:
  /// **'开花啦！🌻'**
  String get garden_fx_bloom;

  /// No description provided for @garden_need_more_sun.
  ///
  /// In zh, this message translates to:
  /// **'阳光不足，还差 {missing} ☀ —— 去专注赚阳光吧'**
  String garden_need_more_sun(int missing);

  /// No description provided for @garden_expand_title.
  ///
  /// In zh, this message translates to:
  /// **'要给花园腾一个花盆吗？'**
  String get garden_expand_title;

  /// No description provided for @garden_row_expand_cost.
  ///
  /// In zh, this message translates to:
  /// **'本次扩容'**
  String get garden_row_expand_cost;

  /// No description provided for @garden_row_balance.
  ///
  /// In zh, this message translates to:
  /// **'当前阳光'**
  String get garden_row_balance;

  /// No description provided for @garden_expand_note.
  ///
  /// In zh, this message translates to:
  /// **'花园容量：{count} 盆 → {next} 盆'**
  String garden_expand_note(int count, int next);

  /// No description provided for @garden_confirm_deduct.
  ///
  /// In zh, this message translates to:
  /// **'确定，扣除'**
  String get garden_confirm_deduct;

  /// No description provided for @garden_batch_none_water.
  ///
  /// In zh, this message translates to:
  /// **'今天没有可浇水的植物'**
  String get garden_batch_none_water;

  /// No description provided for @garden_batch_none_fertilize.
  ///
  /// In zh, this message translates to:
  /// **'今天没有可施肥的植物'**
  String get garden_batch_none_fertilize;

  /// No description provided for @garden_batch_none_care.
  ///
  /// In zh, this message translates to:
  /// **'没有需要护理的植物'**
  String get garden_batch_none_care;

  /// No description provided for @garden_row_total_cost.
  ///
  /// In zh, this message translates to:
  /// **'本次合计扣除'**
  String get garden_row_total_cost;

  /// No description provided for @garden_water_note.
  ///
  /// In zh, this message translates to:
  /// **'将对 {count} 盆植物各浇 1 次水（每盆 {cost} ☀）'**
  String garden_water_note(int count, int cost);

  /// No description provided for @garden_fertilize_note.
  ///
  /// In zh, this message translates to:
  /// **'将对 {count} 盆植物各施 1 次肥（每盆 {cost} ☀）'**
  String garden_fertilize_note(int count, int cost);

  /// No description provided for @garden_row_cleanup.
  ///
  /// In zh, this message translates to:
  /// **'本次清理'**
  String get garden_row_cleanup;

  /// No description provided for @garden_cleanup_count.
  ///
  /// In zh, this message translates to:
  /// **'{count} 处'**
  String garden_cleanup_count(int count);

  /// No description provided for @garden_care_note.
  ///
  /// In zh, this message translates to:
  /// **'奖励照常发放：除草 +{weed} ☀ / 除虫 +{pest} ☀'**
  String garden_care_note(int weed, int pest);

  /// No description provided for @garden_oneclick_water_title.
  ///
  /// In zh, this message translates to:
  /// **'要一键浇水吗？'**
  String get garden_oneclick_water_title;

  /// No description provided for @garden_oneclick_fertilize_title.
  ///
  /// In zh, this message translates to:
  /// **'要一键施肥吗？'**
  String get garden_oneclick_fertilize_title;

  /// No description provided for @garden_oneclick_care_title.
  ///
  /// In zh, this message translates to:
  /// **'要一键护理吗？'**
  String get garden_oneclick_care_title;

  /// No description provided for @garden_oneclick_water_ok.
  ///
  /// In zh, this message translates to:
  /// **'一键浇水成功 ×{count}'**
  String garden_oneclick_water_ok(int count);

  /// No description provided for @garden_oneclick_fertilize_ok.
  ///
  /// In zh, this message translates to:
  /// **'一键施肥成功 ×{count}'**
  String garden_oneclick_fertilize_ok(int count);

  /// No description provided for @garden_oneclick_care_ok.
  ///
  /// In zh, this message translates to:
  /// **'一键护理成功 ×{count}'**
  String garden_oneclick_care_ok(int count);

  /// No description provided for @garden_pick_plant_title.
  ///
  /// In zh, this message translates to:
  /// **'选择要种的植物'**
  String get garden_pick_plant_title;

  /// No description provided for @garden_cost_free.
  ///
  /// In zh, this message translates to:
  /// **'免费'**
  String get garden_cost_free;

  /// No description provided for @garden_cost_seed.
  ///
  /// In zh, this message translates to:
  /// **'种子'**
  String get garden_cost_seed;

  /// No description provided for @garden_cost_sunlight.
  ///
  /// In zh, this message translates to:
  /// **'{count} 阳光'**
  String garden_cost_sunlight(int count);

  /// No description provided for @garden_reason_no_sun.
  ///
  /// In zh, this message translates to:
  /// **'阳光不足'**
  String get garden_reason_no_sun;

  /// No description provided for @garden_cost_fragments.
  ///
  /// In zh, this message translates to:
  /// **'{count} 植物碎片'**
  String garden_cost_fragments(int count);

  /// No description provided for @garden_reason_no_fragments.
  ///
  /// In zh, this message translates to:
  /// **'植物碎片不足（当前 {count} 片）'**
  String garden_reason_no_fragments(int count);

  /// No description provided for @garden_row_plant.
  ///
  /// In zh, this message translates to:
  /// **'本次种植'**
  String get garden_row_plant;

  /// No description provided for @garden_row_use_seed.
  ///
  /// In zh, this message translates to:
  /// **'使用{rarity}种子'**
  String garden_row_use_seed(String rarity);

  /// No description provided for @garden_seed_count.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张'**
  String garden_seed_count(int count);

  /// No description provided for @garden_row_seed_balance.
  ///
  /// In zh, this message translates to:
  /// **'当前种子'**
  String get garden_row_seed_balance;

  /// No description provided for @garden_seed_remaining.
  ///
  /// In zh, this message translates to:
  /// **'种下后剩余 {count} 张'**
  String garden_seed_remaining(int count);

  /// No description provided for @garden_row_use_fragments.
  ///
  /// In zh, this message translates to:
  /// **'使用植物碎片'**
  String get garden_row_use_fragments;

  /// No description provided for @garden_fragment_cost.
  ///
  /// In zh, this message translates to:
  /// **'−{count} 片'**
  String garden_fragment_cost(int count);

  /// No description provided for @garden_row_fragment_balance.
  ///
  /// In zh, this message translates to:
  /// **'当前碎片'**
  String get garden_row_fragment_balance;

  /// No description provided for @garden_fragment_count.
  ///
  /// In zh, this message translates to:
  /// **'{count} 片'**
  String garden_fragment_count(int count);

  /// No description provided for @garden_fragment_remaining.
  ///
  /// In zh, this message translates to:
  /// **'种下后剩余 {count} 片'**
  String garden_fragment_remaining(int count);

  /// No description provided for @garden_sun_remaining.
  ///
  /// In zh, this message translates to:
  /// **'种下后剩余 {count} ☀'**
  String garden_sun_remaining(int count);

  /// No description provided for @garden_unknown_plant.
  ///
  /// In zh, this message translates to:
  /// **'未知植物'**
  String get garden_unknown_plant;

  /// No description provided for @garden_load_failed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String garden_load_failed(Object error);

  /// No description provided for @garden_title.
  ///
  /// In zh, this message translates to:
  /// **'我的花园'**
  String get garden_title;

  /// No description provided for @garden_refresh_tooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新成长'**
  String get garden_refresh_tooltip;

  /// No description provided for @garden_rarity_common.
  ///
  /// In zh, this message translates to:
  /// **'普通'**
  String get garden_rarity_common;

  /// No description provided for @garden_rarity_premium.
  ///
  /// In zh, this message translates to:
  /// **'精英'**
  String get garden_rarity_premium;

  /// No description provided for @garden_flip_back.
  ///
  /// In zh, this message translates to:
  /// **'点此翻回正面'**
  String get garden_flip_back;

  /// No description provided for @garden_action_water.
  ///
  /// In zh, this message translates to:
  /// **'一键浇水'**
  String get garden_action_water;

  /// No description provided for @garden_action_fertilize.
  ///
  /// In zh, this message translates to:
  /// **'一键施肥'**
  String get garden_action_fertilize;

  /// No description provided for @garden_action_care.
  ///
  /// In zh, this message translates to:
  /// **'一键护理'**
  String get garden_action_care;

  /// No description provided for @garden_oneclick_title.
  ///
  /// In zh, this message translates to:
  /// **'一键操作'**
  String get garden_oneclick_title;

  /// No description provided for @garden_help_sheet_title.
  ///
  /// In zh, this message translates to:
  /// **'碎片与种子'**
  String get garden_help_sheet_title;

  /// No description provided for @garden_help_fragment_title.
  ///
  /// In zh, this message translates to:
  /// **'植物碎片'**
  String get garden_help_fragment_title;

  /// No description provided for @garden_help_fragment_use.
  ///
  /// In zh, this message translates to:
  /// **'种植植物时可以代替阳光支付（精英植物要用碎片兑换）。'**
  String get garden_help_fragment_use;

  /// No description provided for @garden_help_fragment_how.
  ///
  /// In zh, this message translates to:
  /// **'植物开花时的奖励里随机掉落。'**
  String get garden_help_fragment_how;

  /// No description provided for @garden_help_common_seed_title.
  ///
  /// In zh, this message translates to:
  /// **'普通植物种子'**
  String get garden_help_common_seed_title;

  /// No description provided for @garden_help_common_seed_use.
  ///
  /// In zh, this message translates to:
  /// **'免费种下一株普通植物，种下时优先使用（不用扣阳光）。'**
  String get garden_help_common_seed_use;

  /// No description provided for @garden_help_common_seed_how.
  ///
  /// In zh, this message translates to:
  /// **'普通植物开花后小概率掉落；重复的种子会自动变成碎片。'**
  String get garden_help_common_seed_how;

  /// No description provided for @garden_help_premium_seed_title.
  ///
  /// In zh, this message translates to:
  /// **'精英植物种子'**
  String get garden_help_premium_seed_title;

  /// No description provided for @garden_help_premium_seed_use.
  ///
  /// In zh, this message translates to:
  /// **'免费种下一株精英植物，种下时优先使用（不用扣碎片）。'**
  String get garden_help_premium_seed_use;

  /// No description provided for @garden_help_premium_seed_how.
  ///
  /// In zh, this message translates to:
  /// **'精英植物开花后小概率掉落；重复的种子会自动变成碎片。'**
  String get garden_help_premium_seed_how;

  /// No description provided for @garden_help_use_prefix.
  ///
  /// In zh, this message translates to:
  /// **'用途：{text}'**
  String garden_help_use_prefix(Object text);

  /// No description provided for @garden_help_how_prefix.
  ///
  /// In zh, this message translates to:
  /// **'获得：{text}'**
  String garden_help_how_prefix(Object text);

  /// No description provided for @shared_got_it.
  ///
  /// In zh, this message translates to:
  /// **'知道啦'**
  String get shared_got_it;

  /// No description provided for @shared_load_failed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String shared_load_failed(Object error);

  /// No description provided for @shared_retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get shared_retry;

  /// No description provided for @shared_refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get shared_refresh;

  /// No description provided for @shared_cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get shared_cancel;

  /// No description provided for @shared_no_sunlight.
  ///
  /// In zh, this message translates to:
  /// **'阳光不足'**
  String get shared_no_sunlight;

  /// No description provided for @shared_week_quota_full.
  ///
  /// In zh, this message translates to:
  /// **'本周额度已满'**
  String get shared_week_quota_full;

  /// No description provided for @shared_redeem.
  ///
  /// In zh, this message translates to:
  /// **'兑换'**
  String get shared_redeem;

  /// No description provided for @store_title.
  ///
  /// In zh, this message translates to:
  /// **'阳光商店'**
  String get store_title;

  /// No description provided for @store_empty_hint.
  ///
  /// In zh, this message translates to:
  /// **'商店还没上架奖励，请让家长先添加奖励模板'**
  String get store_empty_hint;

  /// No description provided for @store_confirm_title.
  ///
  /// In zh, this message translates to:
  /// **'确认兑换？'**
  String get store_confirm_title;

  /// No description provided for @store_row_item.
  ///
  /// In zh, this message translates to:
  /// **'兑换物品'**
  String get store_row_item;

  /// No description provided for @store_row_cost.
  ///
  /// In zh, this message translates to:
  /// **'消耗阳光'**
  String get store_row_cost;

  /// No description provided for @store_row_available.
  ///
  /// In zh, this message translates to:
  /// **'可用阳光'**
  String get store_row_available;

  /// No description provided for @store_warning_redeem.
  ///
  /// In zh, this message translates to:
  /// **'提交后需家长核销，核销通过才会扣除阳光。'**
  String get store_warning_redeem;

  /// No description provided for @store_confirm_ok.
  ///
  /// In zh, this message translates to:
  /// **'确认兑换'**
  String get store_confirm_ok;

  /// No description provided for @store_confirm_think.
  ///
  /// In zh, this message translates to:
  /// **'再想想'**
  String get store_confirm_think;

  /// No description provided for @store_result_verified.
  ///
  /// In zh, this message translates to:
  /// **'兑换成功！阳光已扣除'**
  String get store_result_verified;

  /// No description provided for @store_result_cooldown.
  ///
  /// In zh, this message translates to:
  /// **'本周已领过啦'**
  String get store_result_cooldown;

  /// No description provided for @store_result_no_balance.
  ///
  /// In zh, this message translates to:
  /// **'阳光不足，再去专注赚一些吧'**
  String get store_result_no_balance;

  /// No description provided for @store_result_pool_full.
  ///
  /// In zh, this message translates to:
  /// **'本周额度已满，下周再来吧'**
  String get store_result_pool_full;

  /// No description provided for @store_pending_feedback.
  ///
  /// In zh, this message translates to:
  /// **'已提交，等家长确认哦～'**
  String get store_pending_feedback;

  /// No description provided for @store_pending_pill.
  ///
  /// In zh, this message translates to:
  /// **'待核销 {count}'**
  String store_pending_pill(int count);

  /// No description provided for @store_celebration_text.
  ///
  /// In zh, this message translates to:
  /// **'兑换成功！\n阳光已扣除'**
  String get store_celebration_text;

  /// No description provided for @task_checkin_failed.
  ///
  /// In zh, this message translates to:
  /// **'打卡失败：{error}'**
  String task_checkin_failed(Object error);

  /// No description provided for @task_feedback_pending.
  ///
  /// In zh, this message translates to:
  /// **'已经告诉爸爸妈妈啦，等他们确认就发阳光 🌻'**
  String get task_feedback_pending;

  /// No description provided for @task_feedback_cap.
  ///
  /// In zh, this message translates to:
  /// **'今天的成长奖励已经拿满 {cap} 啦，明天再来'**
  String task_feedback_cap(int cap);

  /// No description provided for @task_feedback_capped.
  ///
  /// In zh, this message translates to:
  /// **'太棒了！+{granted} 阳光（今日成长奖励已达上限，本次只到账 {granted}）'**
  String task_feedback_capped(Object granted);

  /// No description provided for @task_feedback_granted.
  ///
  /// In zh, this message translates to:
  /// **'太棒了！+{granted} 阳光'**
  String task_feedback_granted(Object granted);

  /// No description provided for @task_perfect_title.
  ///
  /// In zh, this message translates to:
  /// **'🌻 今日成长项全部完成！'**
  String get task_perfect_title;

  /// No description provided for @task_perfect_footer.
  ///
  /// In zh, this message translates to:
  /// **'你今天把全部成长项都做完啦，获得「完美日」标记！'**
  String get task_perfect_footer;

  /// No description provided for @task_perfect_ok.
  ///
  /// In zh, this message translates to:
  /// **'太棒啦'**
  String get task_perfect_ok;

  /// No description provided for @task_empty_hint.
  ///
  /// In zh, this message translates to:
  /// **'今天没有成长项，去玩吧 🌻'**
  String get task_empty_hint;

  /// No description provided for @task_progress_title.
  ///
  /// In zh, this message translates to:
  /// **'今日成长'**
  String get task_progress_title;

  /// No description provided for @task_weekly_more.
  ///
  /// In zh, this message translates to:
  /// **'· 另有每周 {count} 项'**
  String task_weekly_more(int count);

  /// No description provided for @task_badge_daily.
  ///
  /// In zh, this message translates to:
  /// **'每日'**
  String get task_badge_daily;

  /// No description provided for @task_badge_weekly.
  ///
  /// In zh, this message translates to:
  /// **'每周'**
  String get task_badge_weekly;

  /// No description provided for @task_info_focus.
  ///
  /// In zh, this message translates to:
  /// **'{subject} · 需专注 · +{reward} ☀'**
  String task_info_focus(Object subject, int reward);

  /// No description provided for @task_info_plain.
  ///
  /// In zh, this message translates to:
  /// **'{subject} · +{reward} ☀'**
  String task_info_plain(Object subject, int reward);

  /// No description provided for @task_status_waiting.
  ///
  /// In zh, this message translates to:
  /// **'等家长确认'**
  String get task_status_waiting;

  /// No description provided for @task_status_done_focus.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get task_status_done_focus;

  /// No description provided for @task_status_done.
  ///
  /// In zh, this message translates to:
  /// **'已做到'**
  String get task_status_done;

  /// No description provided for @child_task_partial_note.
  ///
  /// In zh, this message translates to:
  /// **'实际 {minutes} 分钟 · 完成度 {percent}%'**
  String child_task_partial_note(int minutes, int percent);

  /// No description provided for @task_action_do.
  ///
  /// In zh, this message translates to:
  /// **'我做'**
  String get task_action_do;

  /// No description provided for @task_action_do2.
  ///
  /// In zh, this message translates to:
  /// **'到了'**
  String get task_action_do2;

  /// No description provided for @task_action_focus.
  ///
  /// In zh, this message translates to:
  /// **'去专注'**
  String get task_action_focus;

  /// No description provided for @task_focus_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{count}分钟'**
  String task_focus_minutes(int count);

  /// No description provided for @profile_balance_line.
  ///
  /// In zh, this message translates to:
  /// **'我的阳光：{count} ☀'**
  String profile_balance_line(int count);

  /// No description provided for @profile_source_label.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get profile_source_label;

  /// No description provided for @profile_achievements_title.
  ///
  /// In zh, this message translates to:
  /// **'累计成就'**
  String get profile_achievements_title;

  /// No description provided for @profile_stat_focus_minutes.
  ///
  /// In zh, this message translates to:
  /// **'累计专注时长'**
  String get profile_stat_focus_minutes;

  /// No description provided for @profile_value_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟'**
  String profile_value_minutes(int count);

  /// No description provided for @profile_stat_sessions.
  ///
  /// In zh, this message translates to:
  /// **'累计专注次数'**
  String get profile_stat_sessions;

  /// No description provided for @profile_value_times.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String profile_value_times(int count);

  /// No description provided for @profile_stat_valid_days.
  ///
  /// In zh, this message translates to:
  /// **'累计有效专注天数'**
  String get profile_stat_valid_days;

  /// No description provided for @profile_value_days.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天'**
  String profile_value_days(int count);

  /// No description provided for @profile_stat_checkins.
  ///
  /// In zh, this message translates to:
  /// **'累计成长打卡'**
  String get profile_stat_checkins;

  /// No description provided for @profile_stat_bloomed.
  ///
  /// In zh, this message translates to:
  /// **'累计开花植物'**
  String get profile_stat_bloomed;

  /// No description provided for @profile_value_plants.
  ///
  /// In zh, this message translates to:
  /// **'{count} 株'**
  String profile_value_plants(int count);

  /// No description provided for @profile_stat_eyecare.
  ///
  /// In zh, this message translates to:
  /// **'累计护眼'**
  String get profile_stat_eyecare;

  /// No description provided for @hist_title.
  ///
  /// In zh, this message translates to:
  /// **'阳光来源记录'**
  String get hist_title;

  /// No description provided for @hist_empty_hint.
  ///
  /// In zh, this message translates to:
  /// **'还没有阳光记录哦 🌻'**
  String get hist_empty_hint;

  /// No description provided for @hist_balance_label.
  ///
  /// In zh, this message translates to:
  /// **'当前拥有阳光'**
  String get hist_balance_label;

  /// No description provided for @hist_other.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get hist_other;

  /// No description provided for @hist_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'{time} · 余额 {balance} ☀'**
  String hist_subtitle(Object time, int balance);

  /// No description provided for @card_stage_seed.
  ///
  /// In zh, this message translates to:
  /// **'种子'**
  String get card_stage_seed;

  /// No description provided for @card_stage_sprout.
  ///
  /// In zh, this message translates to:
  /// **'幼苗'**
  String get card_stage_sprout;

  /// No description provided for @card_stage_adult.
  ///
  /// In zh, this message translates to:
  /// **'成株'**
  String get card_stage_adult;

  /// No description provided for @card_status_growing.
  ///
  /// In zh, this message translates to:
  /// **'成长中'**
  String get card_status_growing;

  /// No description provided for @card_status_bloomed.
  ///
  /// In zh, this message translates to:
  /// **'已开花 🌻'**
  String get card_status_bloomed;

  /// No description provided for @card_status_wilting.
  ///
  /// In zh, this message translates to:
  /// **'枯萎中（快救回！）'**
  String get card_status_wilting;

  /// No description provided for @card_status_dead.
  ///
  /// In zh, this message translates to:
  /// **'已枯萎'**
  String get card_status_dead;

  /// No description provided for @card_mood_happy.
  ///
  /// In zh, this message translates to:
  /// **'😊 今天有专注，我很开心'**
  String get card_mood_happy;

  /// No description provided for @card_mood_calm.
  ///
  /// In zh, this message translates to:
  /// **'😌 状态平稳'**
  String get card_mood_calm;

  /// No description provided for @card_mood_thirsty.
  ///
  /// In zh, this message translates to:
  /// **'🥵 有点口渴，该浇水啦'**
  String get card_mood_thirsty;

  /// No description provided for @card_hint_bloomed.
  ///
  /// In zh, this message translates to:
  /// **'已开花 🌻 每天养护，明天晨露阳光满额'**
  String get card_hint_bloomed;

  /// No description provided for @card_hint_next_soon.
  ///
  /// In zh, this message translates to:
  /// **'即将进入下一阶段…'**
  String get card_hint_next_soon;

  /// No description provided for @card_hint_progress.
  ///
  /// In zh, this message translates to:
  /// **'本阶段成长 {percent}%'**
  String card_hint_progress(int percent);

  /// No description provided for @card_hint_grow_days.
  ///
  /// In zh, this message translates to:
  /// **'每天按时养护，还需约 {days} 天长成'**
  String card_hint_grow_days(int days);

  /// No description provided for @card_hint_bloom_left.
  ///
  /// In zh, this message translates to:
  /// **'花期剩余 {days} 天'**
  String card_hint_bloom_left(Object days);

  /// No description provided for @card_action_shovel.
  ///
  /// In zh, this message translates to:
  /// **'铲除'**
  String get card_action_shovel;

  /// No description provided for @card_action_clear.
  ///
  /// In zh, this message translates to:
  /// **'铲除回收'**
  String get card_action_clear;

  /// No description provided for @card_action_water.
  ///
  /// In zh, this message translates to:
  /// **'浇水'**
  String get card_action_water;

  /// No description provided for @card_action_water_gain.
  ///
  /// In zh, this message translates to:
  /// **'浇水 +{gain}%'**
  String card_action_water_gain(Object gain);

  /// No description provided for @card_action_fertilize.
  ///
  /// In zh, this message translates to:
  /// **'施肥'**
  String get card_action_fertilize;

  /// No description provided for @card_action_fertilize_gain.
  ///
  /// In zh, this message translates to:
  /// **'施肥 +{gain}%'**
  String card_action_fertilize_gain(Object gain);

  /// No description provided for @card_quota_left.
  ///
  /// In zh, this message translates to:
  /// **'今日剩余：浇水 {water}/{waterMax} 次 · 施肥 {fert}/{fertMax} 次'**
  String card_quota_left(int water, int waterMax, int fert, int fertMax);

  /// No description provided for @card_wilt_easy.
  ///
  /// In zh, this message translates to:
  /// **'浇水 1 次即可救回'**
  String get card_wilt_easy;

  /// No description provided for @card_wilt_hard.
  ///
  /// In zh, this message translates to:
  /// **'需浇水 {water} 次 + 施肥 {fert} 次才能救回'**
  String card_wilt_hard(int water, int fert);

  /// No description provided for @care_shovel_title.
  ///
  /// In zh, this message translates to:
  /// **'要铲除「{name}」吗？'**
  String care_shovel_title(Object name);

  /// No description provided for @care_this_plant.
  ///
  /// In zh, this message translates to:
  /// **'这株植物'**
  String get care_this_plant;

  /// No description provided for @care_shovel_warning.
  ///
  /// In zh, this message translates to:
  /// **'铲除后这株植物会消失。'**
  String get care_shovel_warning;

  /// No description provided for @care_row_refund.
  ///
  /// In zh, this message translates to:
  /// **'返还种植阳光'**
  String get care_row_refund;

  /// No description provided for @care_note_no_refund_water.
  ///
  /// In zh, this message translates to:
  /// **'浇水施肥的阳光不返还'**
  String get care_note_no_refund_water;

  /// No description provided for @care_note_no_refund.
  ///
  /// In zh, this message translates to:
  /// **'本次铲除不返还阳光'**
  String get care_note_no_refund;

  /// No description provided for @care_confirm_shovel.
  ///
  /// In zh, this message translates to:
  /// **'确定铲除'**
  String get care_confirm_shovel;

  /// No description provided for @care_gone_hint.
  ///
  /// In zh, this message translates to:
  /// **'这株植物已经不在花园里啦'**
  String get care_gone_hint;

  /// No description provided for @care_footer_hint.
  ///
  /// In zh, this message translates to:
  /// **'植物也会随时间自然生长，按时养护才能早点开花 🌻\n盛开后每天浇 1 次水或施 1 次肥，第二天晨露阳光才是满额 🌻\n（忘了也会掉落，只是阳光减半 —— 不会一点都没有）'**
  String get care_footer_hint;

  /// No description provided for @plant_confirm_title.
  ///
  /// In zh, this message translates to:
  /// **'要种下{name}吗？'**
  String plant_confirm_title(Object name);

  /// No description provided for @plant_confirm_ok.
  ///
  /// In zh, this message translates to:
  /// **'确定种植'**
  String get plant_confirm_ok;

  /// No description provided for @pot_tooltip_weed.
  ///
  /// In zh, this message translates to:
  /// **'有杂草，点我拔掉 +{count} ☀'**
  String pot_tooltip_weed(int count);

  /// No description provided for @pot_tooltip_pest.
  ///
  /// In zh, this message translates to:
  /// **'有害虫，点我除掉 +{count} ☀'**
  String pot_tooltip_pest(int count);

  /// No description provided for @pot_label_bloomed.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 开花'**
  String pot_label_bloomed(Object name);

  /// No description provided for @pot_label_wilting.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 快救回'**
  String pot_label_wilting(Object name);

  /// No description provided for @pot_label_dead.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 已枯萎'**
  String pot_label_dead(Object name);

  /// No description provided for @pot_label_locked.
  ///
  /// In zh, this message translates to:
  /// **'需解锁'**
  String get pot_label_locked;

  /// No description provided for @pot_label_expand.
  ///
  /// In zh, this message translates to:
  /// **'加盆 · {cost}☀'**
  String pot_label_expand(int cost);

  /// No description provided for @pot_label_shortfall.
  ///
  /// In zh, this message translates to:
  /// **'还差 {count}☀'**
  String pot_label_shortfall(int count);

  /// No description provided for @ghelp_title.
  ///
  /// In zh, this message translates to:
  /// **'玩法说明'**
  String get ghelp_title;

  /// No description provided for @ghelp_earn_title.
  ///
  /// In zh, this message translates to:
  /// **'怎么挣阳光'**
  String get ghelp_earn_title;

  /// No description provided for @ghelp_earn_detail.
  ///
  /// In zh, this message translates to:
  /// **'白天专注就能挣阳光：每分钟 +{perMinute} ☀；\n完成成长任务打卡，每项还 +{taskReward} ☀。'**
  String ghelp_earn_detail(int perMinute, int taskReward);

  /// No description provided for @ghelp_use_title.
  ///
  /// In zh, this message translates to:
  /// **'阳光能干什么'**
  String get ghelp_use_title;

  /// No description provided for @ghelp_use_detail.
  ///
  /// In zh, this message translates to:
  /// **'在花园种植物（点空花盆选一株，花 ☀ 种下）；\n给植物浇水 {waterCost} ☀/次起、施肥 {fertCost} ☀/次起；\n也可以去「商店」兑换喜欢的奖励。'**
  String ghelp_use_detail(int waterCost, int fertCost);

  /// No description provided for @ghelp_grow_title.
  ///
  /// In zh, this message translates to:
  /// **'植物怎么长大'**
  String get ghelp_grow_title;

  /// No description provided for @ghelp_grow_detail.
  ///
  /// In zh, this message translates to:
  /// **'不照顾也会随时间自己长大；浇水 +{waterGain}%、施肥 +{fertGain}% 长得更快\n（花谢后重新养时增量会小一些，看按钮上的实际数字；\n每天最多浇 {waterMax} 次、施 {fertMax} 次，两次浇水要隔 {interval} 分钟）；\n进度养满就开花，开满 {bloomDays} 天后花谢，再养满又能再开 🌻'**
  String ghelp_grow_detail(int waterGain, int fertGain, int waterMax,
      int fertMax, int interval, int bloomDays);

  /// No description provided for @ghelp_wilt_title.
  ///
  /// In zh, this message translates to:
  /// **'别让植物枯萎'**
  String get ghelp_wilt_title;

  /// No description provided for @ghelp_wilt_detail.
  ///
  /// In zh, this message translates to:
  /// **'浇水或施肥能刷新计时；{wiltDays} 天没浇水就会枯萎，\n枯萎后再拖 {deathDays} 天就会枯死。记得常来看看它 🌱'**
  String ghelp_wilt_detail(int wiltDays, int deathDays);

  /// No description provided for @ghelp_task_title.
  ///
  /// In zh, this message translates to:
  /// **'任务打卡与家长核销'**
  String get ghelp_task_title;

  /// No description provided for @ghelp_task_detail.
  ///
  /// In zh, this message translates to:
  /// **'成长任务有两种：\n「开始专注」的任务，达标后自动结算阳光；\n「我做到了」的任务，先记成「等家长确认」，\n爸爸妈妈核销通过后，阳光才真正到账。'**
  String get ghelp_task_detail;

  /// No description provided for @ghelp_capacity_title.
  ///
  /// In zh, this message translates to:
  /// **'花园容量'**
  String get ghelp_capacity_title;

  /// No description provided for @ghelp_capacity_detail.
  ///
  /// In zh, this message translates to:
  /// **'{capacity} / {max} 盆'**
  String ghelp_capacity_detail(int capacity, int max);

  /// No description provided for @ghelp_expand_title.
  ///
  /// In zh, this message translates to:
  /// **'扩容'**
  String get ghelp_expand_title;

  /// No description provided for @ghelp_expand_detail.
  ///
  /// In zh, this message translates to:
  /// **'点「+」格，花 {cost} ☀ 可以多一个花盆（上限 {max} 盆）'**
  String ghelp_expand_detail(int cost, int max);

  /// No description provided for @prd_pending_reminder.
  ///
  /// In zh, this message translates to:
  /// **'这次的阳光奖励还在等你确认哦～'**
  String get prd_pending_reminder;

  /// No description provided for @prd_avatar_locked_hint.
  ///
  /// In zh, this message translates to:
  /// **'种下这种植物后可以选它当头像'**
  String get prd_avatar_locked_hint;

  /// No description provided for @prd_eyecare_not_skippable.
  ///
  /// In zh, this message translates to:
  /// **'不可跳过，请爱护眼睛'**
  String get prd_eyecare_not_skippable;

  /// No description provided for @prd_eyecare_finish.
  ///
  /// In zh, this message translates to:
  /// **'跳过护眼休息'**
  String get prd_eyecare_finish;

  /// No description provided for @prd_eyecare_early_title.
  ///
  /// In zh, this message translates to:
  /// **'还没休息完就结束吗？'**
  String get prd_eyecare_early_title;

  /// No description provided for @prd_eyecare_early_body.
  ///
  /// In zh, this message translates to:
  /// **'护眼还没做完，现在结束就没有小阳光奖励哦。小眼睛要多休息才会亮晶晶，再坚持一下吧！'**
  String get prd_eyecare_early_body;

  /// No description provided for @prd_eyecare_early_stay.
  ///
  /// In zh, this message translates to:
  /// **'再休息一会儿'**
  String get prd_eyecare_early_stay;

  /// No description provided for @prd_eyecare_early_quit.
  ///
  /// In zh, this message translates to:
  /// **'确定结束'**
  String get prd_eyecare_early_quit;

  /// No description provided for @prd_level_locked_title.
  ///
  /// In zh, this message translates to:
  /// **'尚未解锁称号'**
  String get prd_level_locked_title;

  /// No description provided for @prd_level_detail_ok.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get prd_level_detail_ok;

  /// No description provided for @prd_premium_upsell_hint.
  ///
  /// In zh, this message translates to:
  /// **'请升级到完整版本功能'**
  String get prd_premium_upsell_hint;

  /// No description provided for @fx_level_up_title.
  ///
  /// In zh, this message translates to:
  /// **'解锁新称号！'**
  String get fx_level_up_title;

  /// No description provided for @fx_level_up_level_title.
  ///
  /// In zh, this message translates to:
  /// **'升级啦！'**
  String get fx_level_up_level_title;

  /// No description provided for @fx_level_up_multi.
  ///
  /// In zh, this message translates to:
  /// **'连升 {n} 个称号！'**
  String fx_level_up_multi(int n);

  /// No description provided for @fx_level_up_level_multi.
  ///
  /// In zh, this message translates to:
  /// **'连升 {n} 级！'**
  String fx_level_up_level_multi(int n);

  /// No description provided for @fx_level_up_perk.
  ///
  /// In zh, this message translates to:
  /// **'本称号专属：{text}'**
  String fx_level_up_perk(Object text);

  /// No description provided for @fx_level_up_perk_locked.
  ///
  /// In zh, this message translates to:
  /// **' · 🔒付费解锁'**
  String get fx_level_up_perk_locked;

  /// No description provided for @shared_edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get shared_edit;

  /// No description provided for @shared_delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get shared_delete;

  /// No description provided for @parent_home_title.
  ///
  /// In zh, this message translates to:
  /// **'家长天地'**
  String get parent_home_title;

  /// No description provided for @parent_home_back_tooltip.
  ///
  /// In zh, this message translates to:
  /// **'返回孩子端'**
  String get parent_home_back_tooltip;

  /// No description provided for @parent_home_tab_today.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get parent_home_tab_today;

  /// No description provided for @parent_home_tab_reward.
  ///
  /// In zh, this message translates to:
  /// **'奖励'**
  String get parent_home_tab_reward;

  /// No description provided for @parent_home_tab_growth.
  ///
  /// In zh, this message translates to:
  /// **'成长'**
  String get parent_home_tab_growth;

  /// No description provided for @parent_home_tab_history.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get parent_home_tab_history;

  /// No description provided for @parent_home_tab_settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get parent_home_tab_settings;

  /// No description provided for @parent_login_enter_pin.
  ///
  /// In zh, this message translates to:
  /// **'请输入家长 PIN'**
  String get parent_login_enter_pin;

  /// No description provided for @parent_login_setup_pin.
  ///
  /// In zh, this message translates to:
  /// **'首次进入，请设置家长 PIN'**
  String get parent_login_setup_pin;

  /// No description provided for @parent_login_btn_enter.
  ///
  /// In zh, this message translates to:
  /// **'进入'**
  String get parent_login_btn_enter;

  /// No description provided for @parent_login_btn_setup.
  ///
  /// In zh, this message translates to:
  /// **'设置并进入'**
  String get parent_login_btn_setup;

  /// No description provided for @parent_login_err_short.
  ///
  /// In zh, this message translates to:
  /// **'PIN 至少 4 位'**
  String get parent_login_err_short;

  /// No description provided for @parent_login_err_wrong.
  ///
  /// In zh, this message translates to:
  /// **'PIN 不正确'**
  String get parent_login_err_wrong;

  /// No description provided for @parent_delete_title.
  ///
  /// In zh, this message translates to:
  /// **'删除入口'**
  String get parent_delete_title;

  /// No description provided for @parent_delete_right_title.
  ///
  /// In zh, this message translates to:
  /// **'数据删除权（§10.4 C5）'**
  String get parent_delete_right_title;

  /// No description provided for @parent_delete_right_body.
  ///
  /// In zh, this message translates to:
  /// **'你拥有删除全部本地数据的权利。删除后所有进度与设置将不可恢复。'**
  String get parent_delete_right_body;

  /// No description provided for @parent_delete_dlg_title.
  ///
  /// In zh, this message translates to:
  /// **'删除全部本地数据？'**
  String get parent_delete_dlg_title;

  /// No description provided for @parent_delete_dlg_body.
  ///
  /// In zh, this message translates to:
  /// **'此操作将永久删除：专注记录、阳光账本、植物、成长项、奖励模板、家长 PIN 与所有本地设置，且无法恢复。\n\n建议先「导出成册」留存（导出功能将在 V2 上线）。'**
  String get parent_delete_dlg_body;

  /// No description provided for @parent_delete_btn_ok.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get parent_delete_btn_ok;

  /// No description provided for @parent_delete_btn_export.
  ///
  /// In zh, this message translates to:
  /// **'导出成册（V2 上线）'**
  String get parent_delete_btn_export;

  /// No description provided for @parent_delete_export_snack.
  ///
  /// In zh, this message translates to:
  /// **'导出成册功能将在 V2 上线，请先截图留存'**
  String get parent_delete_export_snack;

  /// No description provided for @parent_delete_btn_all.
  ///
  /// In zh, this message translates to:
  /// **'删除全部本地数据'**
  String get parent_delete_btn_all;

  /// No description provided for @parent_delete_btn_deleting.
  ///
  /// In zh, this message translates to:
  /// **'删除中…'**
  String get parent_delete_btn_deleting;

  /// No description provided for @parent_delete_done_snack.
  ///
  /// In zh, this message translates to:
  /// **'已删除全部本地数据'**
  String get parent_delete_done_snack;

  /// No description provided for @parent_delete_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{error}'**
  String parent_delete_fail_snack(Object error);

  /// No description provided for @parent_today_unknown_reward.
  ///
  /// In zh, this message translates to:
  /// **'未知奖励'**
  String get parent_today_unknown_reward;

  /// No description provided for @parent_today_empty.
  ///
  /// In zh, this message translates to:
  /// **'暂无待确认奖励 🎉'**
  String get parent_today_empty;

  /// No description provided for @parent_today_pending_title.
  ///
  /// In zh, this message translates to:
  /// **'待确认的成长项'**
  String get parent_today_pending_title;

  /// No description provided for @parent_today_count.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项'**
  String parent_today_count(int count);

  /// No description provided for @parent_today_deleted_task.
  ///
  /// In zh, this message translates to:
  /// **'（已删除的成长项）'**
  String get parent_today_deleted_task;

  /// No description provided for @parent_today_submitted_at.
  ///
  /// In zh, this message translates to:
  /// **'提交于 {time}'**
  String parent_today_submitted_at(Object time);

  /// No description provided for @parent_today_should_grant.
  ///
  /// In zh, this message translates to:
  /// **'应发 {sun} 阳光'**
  String parent_today_should_grant(String sun);

  /// No description provided for @parent_today_btn_confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认发放'**
  String get parent_today_btn_confirm;

  /// No description provided for @parent_today_btn_reject.
  ///
  /// In zh, this message translates to:
  /// **'驳回'**
  String get parent_today_btn_reject;

  /// No description provided for @parent_today_reject_title.
  ///
  /// In zh, this message translates to:
  /// **'驳回这项成长？'**
  String get parent_today_reject_title;

  /// No description provided for @parent_today_reject_body.
  ///
  /// In zh, this message translates to:
  /// **'将不发放「{name}」的阳光。'**
  String parent_today_reject_body(String name);

  /// No description provided for @parent_today_reject_reason.
  ///
  /// In zh, this message translates to:
  /// **'理由（选填）'**
  String get parent_today_reject_reason;

  /// No description provided for @parent_today_reject_ok.
  ///
  /// In zh, this message translates to:
  /// **'确认驳回'**
  String get parent_today_reject_ok;

  /// No description provided for @parent_today_confirm_ok_snack.
  ///
  /// In zh, this message translates to:
  /// **'已确认发放，+{sun} 阳光 🌻{capped}'**
  String parent_today_confirm_ok_snack(String sun, String capped);

  /// No description provided for @parent_today_capped_note.
  ///
  /// In zh, this message translates to:
  /// **'（今日成长奖励已达上限，本次只到账 {sun} ☀）'**
  String parent_today_capped_note(String sun);

  /// No description provided for @parent_today_confirm_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'确认失败：{error}'**
  String parent_today_confirm_fail_snack(Object error);

  /// No description provided for @parent_today_rejected_snack.
  ///
  /// In zh, this message translates to:
  /// **'已驳回 🌞 这项不会发阳光'**
  String get parent_today_rejected_snack;

  /// No description provided for @parent_today_reject_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'驳回失败：{error}'**
  String parent_today_reject_fail_snack(Object error);

  /// No description provided for @parent_today_debug_cap_title.
  ///
  /// In zh, this message translates to:
  /// **'🧪 调试：跳过 30 分钟限时'**
  String get parent_today_debug_cap_title;

  /// No description provided for @parent_today_debug_cap_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'调试期间默认开启（不进限时状态）；关闭后恢复防沉迷拦截。仅调试包可见。'**
  String get parent_today_debug_cap_subtitle;

  /// No description provided for @parent_today_debug_cap_on_snack.
  ///
  /// In zh, this message translates to:
  /// **'已跳过 30 分钟限时（调试）'**
  String get parent_today_debug_cap_on_snack;

  /// No description provided for @parent_today_debug_cap_off_snack.
  ///
  /// In zh, this message translates to:
  /// **'已恢复 30 分钟限时拦截'**
  String get parent_today_debug_cap_off_snack;

  /// No description provided for @parent_today_debug_save_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请重试'**
  String get parent_today_debug_save_fail_snack;

  /// No description provided for @parent_verify_cat_self_service.
  ///
  /// In zh, this message translates to:
  /// **'自服务'**
  String get parent_verify_cat_self_service;

  /// No description provided for @parent_verify_cat_parent_handled.
  ///
  /// In zh, this message translates to:
  /// **'家长经手'**
  String get parent_verify_cat_parent_handled;

  /// No description provided for @parent_verify_cost.
  ///
  /// In zh, this message translates to:
  /// **'{cost} 阳光'**
  String parent_verify_cost(int cost);

  /// No description provided for @parent_verify_meta.
  ///
  /// In zh, this message translates to:
  /// **'分类：{category} · 申请于 {time}'**
  String parent_verify_meta(String category, String time);

  /// No description provided for @parent_verify_queue_note.
  ///
  /// In zh, this message translates to:
  /// **'排队第 {pos} 位 · 下月自动释放'**
  String parent_verify_queue_note(Object pos);

  /// No description provided for @parent_verify_confirm_title.
  ///
  /// In zh, this message translates to:
  /// **'确认核销？'**
  String get parent_verify_confirm_title;

  /// No description provided for @parent_verify_confirm_body.
  ///
  /// In zh, this message translates to:
  /// **'确认为「{name}」核销 {cost} 阳光？\n核销后将立即从孩子阳光中扣除，且不可撤销。'**
  String parent_verify_confirm_body(String name, int cost);

  /// No description provided for @parent_verify_confirm_ok.
  ///
  /// In zh, this message translates to:
  /// **'确认核销'**
  String get parent_verify_confirm_ok;

  /// No description provided for @parent_verify_reject_title.
  ///
  /// In zh, this message translates to:
  /// **'确认拒绝？'**
  String get parent_verify_reject_title;

  /// No description provided for @parent_verify_reject_body.
  ///
  /// In zh, this message translates to:
  /// **'拒绝「{name}」（{cost} 阳光）后将不核销该奖励。\n待核销期间阳光从未被扣除，故孩子阳光不受影响。\n此操作不可撤销。'**
  String parent_verify_reject_body(String name, int cost);

  /// No description provided for @parent_verify_reject_ok.
  ///
  /// In zh, this message translates to:
  /// **'确认拒绝'**
  String get parent_verify_reject_ok;

  /// No description provided for @parent_verify_verified_snack.
  ///
  /// In zh, this message translates to:
  /// **'已确认兑换 🎉 阳光已扣除'**
  String get parent_verify_verified_snack;

  /// No description provided for @parent_verify_verify_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'核销失败：{error}'**
  String parent_verify_verify_fail_snack(Object error);

  /// No description provided for @parent_verify_rejected_snack.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝该兑换 🌞 阳光未被扣除'**
  String get parent_verify_rejected_snack;

  /// No description provided for @parent_verify_reject_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'拒绝失败：{error}'**
  String parent_verify_reject_fail_snack(Object error);

  /// No description provided for @parent_verify_release_title.
  ///
  /// In zh, this message translates to:
  /// **'立即发放？'**
  String get parent_verify_release_title;

  /// No description provided for @parent_verify_release_body.
  ///
  /// In zh, this message translates to:
  /// **'确认为「{name}」立即发放 {cost} 阳光？\n将跳过排队等待，立即从孩子阳光中扣除。'**
  String parent_verify_release_body(String name, int cost);

  /// No description provided for @parent_verify_release_ok.
  ///
  /// In zh, this message translates to:
  /// **'立即发放'**
  String get parent_verify_release_ok;

  /// No description provided for @parent_verify_released_snack.
  ///
  /// In zh, this message translates to:
  /// **'已立即发放 🎉 阳光已扣除'**
  String get parent_verify_released_snack;

  /// No description provided for @parent_verify_release_state_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'无法立即发放：{error}'**
  String parent_verify_release_state_fail_snack(Object error);

  /// No description provided for @parent_verify_release_fail_snack.
  ///
  /// In zh, this message translates to:
  /// **'发放失败：{error}'**
  String parent_verify_release_fail_snack(Object error);

  /// No description provided for @parent_task_edit_title_new.
  ///
  /// In zh, this message translates to:
  /// **'新增成长项'**
  String get parent_task_edit_title_new;

  /// No description provided for @parent_task_edit_title_edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑成长项'**
  String get parent_task_edit_title_edit;

  /// No description provided for @parent_task_edit_name_label.
  ///
  /// In zh, this message translates to:
  /// **'成长项名称'**
  String get parent_task_edit_name_label;

  /// No description provided for @parent_task_edit_subject_label.
  ///
  /// In zh, this message translates to:
  /// **'科目'**
  String get parent_task_edit_subject_label;

  /// No description provided for @parent_task_edit_subject_general.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get parent_task_edit_subject_general;

  /// No description provided for @parent_task_edit_subject_chinese.
  ///
  /// In zh, this message translates to:
  /// **'语文'**
  String get parent_task_edit_subject_chinese;

  /// No description provided for @parent_task_edit_subject_math.
  ///
  /// In zh, this message translates to:
  /// **'数学'**
  String get parent_task_edit_subject_math;

  /// No description provided for @parent_task_edit_subject_english.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get parent_task_edit_subject_english;

  /// No description provided for @parent_task_edit_subject_custom.
  ///
  /// In zh, this message translates to:
  /// **'自定义…'**
  String get parent_task_edit_subject_custom;

  /// No description provided for @parent_task_edit_custom_label.
  ///
  /// In zh, this message translates to:
  /// **'自定义科目名称'**
  String get parent_task_edit_custom_label;

  /// No description provided for @parent_task_edit_custom_hint.
  ///
  /// In zh, this message translates to:
  /// **'例如：科学 / 书法 / 编程'**
  String get parent_task_edit_custom_hint;

  /// No description provided for @parent_task_edit_category_label.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get parent_task_edit_category_label;

  /// No description provided for @parent_task_edit_link_title.
  ///
  /// In zh, this message translates to:
  /// **'专注联动（自动结算）'**
  String get parent_task_edit_link_title;

  /// No description provided for @parent_task_edit_link_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'勾选后，孩子从这一项点「开始专注」，达标会自动完成并发放阳光，无需手动打卡。'**
  String get parent_task_edit_link_subtitle;

  /// No description provided for @parent_task_edit_min_focus_label.
  ///
  /// In zh, this message translates to:
  /// **'最少专注'**
  String get parent_task_edit_min_focus_label;

  /// No description provided for @parent_task_edit_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String parent_task_edit_minutes(int minutes);

  /// No description provided for @parent_task_edit_reward_fixed.
  ///
  /// In zh, this message translates to:
  /// **'奖励固定 = 专注 {minutes} 分钟 × 40% = {cap} ☀（无需调整）'**
  String parent_task_edit_reward_fixed(int minutes, int cap);

  /// No description provided for @parent_task_edit_reward_label.
  ///
  /// In zh, this message translates to:
  /// **'阳光奖励'**
  String get parent_task_edit_reward_label;

  /// No description provided for @parent_task_edit_reward_slider.
  ///
  /// In zh, this message translates to:
  /// **'{reward} 阳光'**
  String parent_task_edit_reward_slider(int reward);

  /// No description provided for @parent_task_edit_reward_range.
  ///
  /// In zh, this message translates to:
  /// **'区间 {min}–{max} ☀（默认 {def}）'**
  String parent_task_edit_reward_range(int min, int max, int def);

  /// No description provided for @parent_task_edit_repeat_label.
  ///
  /// In zh, this message translates to:
  /// **'重复规则'**
  String get parent_task_edit_repeat_label;

  /// No description provided for @parent_task_edit_repeat_none.
  ///
  /// In zh, this message translates to:
  /// **'不重复'**
  String get parent_task_edit_repeat_none;

  /// No description provided for @parent_task_edit_repeat_daily.
  ///
  /// In zh, this message translates to:
  /// **'每天'**
  String get parent_task_edit_repeat_daily;

  /// No description provided for @parent_task_edit_repeat_weekly.
  ///
  /// In zh, this message translates to:
  /// **'每周'**
  String get parent_task_edit_repeat_weekly;

  /// No description provided for @parent_task_edit_err_name.
  ///
  /// In zh, this message translates to:
  /// **'请填写成长项名称'**
  String get parent_task_edit_err_name;

  /// No description provided for @parent_task_edit_err_reward.
  ///
  /// In zh, this message translates to:
  /// **'阳光奖励需在 {min}–{max} 之间'**
  String parent_task_edit_err_reward(int min, int max);

  /// No description provided for @parent_task_edit_err_subject.
  ///
  /// In zh, this message translates to:
  /// **'请填写自定义科目名称'**
  String get parent_task_edit_err_subject;

  /// No description provided for @parent_task_edit_err_save.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String parent_task_edit_err_save(Object error);

  /// No description provided for @parent_task_edit_btn_save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get parent_task_edit_btn_save;

  /// No description provided for @parent_task_config_title.
  ///
  /// In zh, this message translates to:
  /// **'成长配置'**
  String get parent_task_config_title;

  /// No description provided for @parent_task_config_list_title.
  ///
  /// In zh, this message translates to:
  /// **'成长任务'**
  String get parent_task_config_list_title;

  /// No description provided for @parent_task_config_empty.
  ///
  /// In zh, this message translates to:
  /// **'还没有成长项，点右上角「新增成长项」创建一个吧'**
  String get parent_task_config_empty;

  /// No description provided for @parent_task_config_delete_title.
  ///
  /// In zh, this message translates to:
  /// **'删除成长项？'**
  String get parent_task_config_delete_title;

  /// No description provided for @parent_task_config_delete_body.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？已生成的打卡记录会保留。'**
  String parent_task_config_delete_body(String name);

  /// No description provided for @parent_task_config_focus_pill.
  ///
  /// In zh, this message translates to:
  /// **'专注 {minutes} 分'**
  String parent_task_config_focus_pill(int minutes);

  /// No description provided for @parent_reward_templates_title.
  ///
  /// In zh, this message translates to:
  /// **'奖励模板'**
  String get parent_reward_templates_title;

  /// No description provided for @parent_reward_btn_add.
  ///
  /// In zh, this message translates to:
  /// **'新增奖励'**
  String get parent_reward_btn_add;

  /// No description provided for @parent_reward_quota_hint.
  ///
  /// In zh, this message translates to:
  /// **'{reason}，删除多余条目后即可新增'**
  String parent_reward_quota_hint(String reason);

  /// No description provided for @parent_reward_edit_hint.
  ///
  /// In zh, this message translates to:
  /// **'点按某条可编辑名称/价格/分类；右侧垃圾桶可删除。改动会同步到孩子端阳光商店。'**
  String get parent_reward_edit_hint;

  /// No description provided for @parent_reward_empty.
  ///
  /// In zh, this message translates to:
  /// **'暂无奖励模板，点「新增奖励」创建'**
  String get parent_reward_empty;

  /// No description provided for @parent_reward_delete_title.
  ///
  /// In zh, this message translates to:
  /// **'删除奖励'**
  String get parent_reward_delete_title;

  /// No description provided for @parent_reward_delete_body.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？孩子端阳光商店将不再展示该奖励。'**
  String parent_reward_delete_body(String name);

  /// No description provided for @parent_reward_edit_title_new.
  ///
  /// In zh, this message translates to:
  /// **'新增奖励'**
  String get parent_reward_edit_title_new;

  /// No description provided for @parent_reward_edit_title_edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑奖励'**
  String get parent_reward_edit_title_edit;

  /// No description provided for @parent_reward_name_label.
  ///
  /// In zh, this message translates to:
  /// **'奖励名称'**
  String get parent_reward_name_label;

  /// No description provided for @parent_reward_err_required.
  ///
  /// In zh, this message translates to:
  /// **'必填'**
  String get parent_reward_err_required;

  /// No description provided for @parent_reward_cat_self_full.
  ///
  /// In zh, this message translates to:
  /// **'自服务（看电视/玩平板）'**
  String get parent_reward_cat_self_full;

  /// No description provided for @parent_reward_content_label.
  ///
  /// In zh, this message translates to:
  /// **'内容分类'**
  String get parent_reward_content_label;

  /// No description provided for @parent_reward_cost_label.
  ///
  /// In zh, this message translates to:
  /// **'阳光价格'**
  String get parent_reward_cost_label;

  /// No description provided for @parent_reward_err_positive.
  ///
  /// In zh, this message translates to:
  /// **'请输入正整数'**
  String get parent_reward_err_positive;

  /// No description provided for @parent_reward_freq_label.
  ///
  /// In zh, this message translates to:
  /// **'每周限领次数'**
  String get parent_reward_freq_label;

  /// No description provided for @parent_reward_err_nonneg.
  ///
  /// In zh, this message translates to:
  /// **'请输入非负整数'**
  String get parent_reward_err_nonneg;

  /// No description provided for @parent_reward_cooldown_label.
  ///
  /// In zh, this message translates to:
  /// **'冷却规则'**
  String get parent_reward_cooldown_label;

  /// No description provided for @parent_reward_cooldown_none.
  ///
  /// In zh, this message translates to:
  /// **'无冷却'**
  String get parent_reward_cooldown_none;

  /// No description provided for @parent_reward_cooldown_weekly.
  ///
  /// In zh, this message translates to:
  /// **'每周限领'**
  String get parent_reward_cooldown_weekly;

  /// No description provided for @parent_reward_cooldown_monthly.
  ///
  /// In zh, this message translates to:
  /// **'每月限领'**
  String get parent_reward_cooldown_monthly;

  /// No description provided for @parent_reward_pool_title.
  ///
  /// In zh, this message translates to:
  /// **'本周阳光预算'**
  String get parent_reward_pool_title;

  /// No description provided for @parent_reward_pool_unit.
  ///
  /// In zh, this message translates to:
  /// **'阳光'**
  String get parent_reward_pool_unit;

  /// No description provided for @parent_reward_pool_used_line.
  ///
  /// In zh, this message translates to:
  /// **'已用 {used} / 共 {budget} 阳光'**
  String parent_reward_pool_used_line(int used, int budget);

  /// No description provided for @parent_reward_pool_unlimited_line.
  ///
  /// In zh, this message translates to:
  /// **'本周不限额，已用 {used} 阳光（兑换只受阳光余额约束）'**
  String parent_reward_pool_unlimited_line(int used);

  /// No description provided for @parent_reward_pool_default_note.
  ///
  /// In zh, this message translates to:
  /// **'每周兑换额度默认值：低年级 {low}☀ · 中年级 {mid}☀ · 高年级{high}（兑换只受阳光余额约束）'**
  String parent_reward_pool_default_note(int low, int mid, String high);

  /// No description provided for @parent_reward_pool_load_failed.
  ///
  /// In zh, this message translates to:
  /// **'周阳光池加载失败：{error}'**
  String parent_reward_pool_load_failed(Object error);

  /// No description provided for @parent_settings_section_screentime.
  ///
  /// In zh, this message translates to:
  /// **'防沉迷与作息'**
  String get parent_settings_section_screentime;

  /// No description provided for @parent_settings_switch_quiet.
  ///
  /// In zh, this message translates to:
  /// **'免打扰模式'**
  String get parent_settings_switch_quiet;

  /// No description provided for @parent_settings_night_title.
  ///
  /// In zh, this message translates to:
  /// **'夜间边界'**
  String get parent_settings_night_title;

  /// No description provided for @parent_settings_night_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'{time} 起进入夜间（夜锁生效时间）'**
  String parent_settings_night_subtitle(String time);

  /// No description provided for @parent_settings_daily_focus_cap.
  ///
  /// In zh, this message translates to:
  /// **'每日专注上限（分钟）'**
  String get parent_settings_daily_focus_cap;

  /// No description provided for @parent_settings_daily_app_cap.
  ///
  /// In zh, this message translates to:
  /// **'每日花园、商店使用时长（分钟）'**
  String get parent_settings_daily_app_cap;

  /// No description provided for @parent_settings_rest_after.
  ///
  /// In zh, this message translates to:
  /// **'每 N 次专注后休息'**
  String get parent_settings_rest_after;

  /// No description provided for @parent_settings_rest_minutes.
  ///
  /// In zh, this message translates to:
  /// **'休息时长（分钟）'**
  String get parent_settings_rest_minutes;

  /// No description provided for @parent_settings_section_eyecare.
  ///
  /// In zh, this message translates to:
  /// **'护眼休息'**
  String get parent_settings_section_eyecare;

  /// No description provided for @parent_settings_switch_eyecare.
  ///
  /// In zh, this message translates to:
  /// **'护眼提醒'**
  String get parent_settings_switch_eyecare;

  /// No description provided for @parent_settings_eyecare_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'专注每满一定时间弹出护眼卡，帮孩子歇歇眼睛（固定 60 秒）'**
  String get parent_settings_eyecare_subtitle;

  /// No description provided for @parent_settings_eyecare_interval.
  ///
  /// In zh, this message translates to:
  /// **'护眼触发间隔（每 N 分钟）'**
  String get parent_settings_eyecare_interval;

  /// No description provided for @parent_settings_switch_eyecare_skip.
  ///
  /// In zh, this message translates to:
  /// **'允许孩子跳过护眼'**
  String get parent_settings_switch_eyecare_skip;

  /// No description provided for @parent_settings_eyecare_skip_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'关掉后孩子只能完成休息，跳过按钮不生效'**
  String get parent_settings_eyecare_skip_subtitle;

  /// No description provided for @parent_settings_section_sound.
  ///
  /// In zh, this message translates to:
  /// **'环境与音效'**
  String get parent_settings_section_sound;

  /// No description provided for @parent_settings_switch_sound.
  ///
  /// In zh, this message translates to:
  /// **'音效'**
  String get parent_settings_switch_sound;

  /// No description provided for @parent_settings_switch_bgm.
  ///
  /// In zh, this message translates to:
  /// **'背景音乐'**
  String get parent_settings_switch_bgm;

  /// No description provided for @parent_settings_switch_dark.
  ///
  /// In zh, this message translates to:
  /// **'深色主题'**
  String get parent_settings_switch_dark;

  /// No description provided for @parent_settings_section_lock.
  ///
  /// In zh, this message translates to:
  /// **'家长锁与赠予'**
  String get parent_settings_section_lock;

  /// No description provided for @parent_settings_reset_pin.
  ///
  /// In zh, this message translates to:
  /// **'重设家长 PIN'**
  String get parent_settings_reset_pin;

  /// No description provided for @parent_settings_grant_title.
  ///
  /// In zh, this message translates to:
  /// **'赠予阳光'**
  String get parent_settings_grant_title;

  /// No description provided for @parent_settings_grant_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'日上限 {daily} / 月上限 {monthly}'**
  String parent_settings_grant_subtitle(Object daily, Object monthly);

  /// No description provided for @parent_settings_section_data.
  ///
  /// In zh, this message translates to:
  /// **'数据与隐私'**
  String get parent_settings_section_data;

  /// No description provided for @parent_settings_entry_delete.
  ///
  /// In zh, this message translates to:
  /// **'删除入口'**
  String get parent_settings_entry_delete;

  /// No description provided for @parent_settings_entry_delete_sub.
  ///
  /// In zh, this message translates to:
  /// **'删除全部本地数据（§10.4 C5）'**
  String get parent_settings_entry_delete_sub;

  /// No description provided for @parent_settings_section_debug.
  ///
  /// In zh, this message translates to:
  /// **'调试（仅 Debug 构建）'**
  String get parent_settings_section_debug;

  /// No description provided for @parent_settings_pin_dlg_title.
  ///
  /// In zh, this message translates to:
  /// **'重设家长 PIN'**
  String get parent_settings_pin_dlg_title;

  /// No description provided for @parent_settings_pin_dlg_old.
  ///
  /// In zh, this message translates to:
  /// **'当前 PIN'**
  String get parent_settings_pin_dlg_old;

  /// No description provided for @parent_settings_pin_dlg_new.
  ///
  /// In zh, this message translates to:
  /// **'新 PIN（≥4 位）'**
  String get parent_settings_pin_dlg_new;

  /// No description provided for @parent_settings_pin_dlg_ok.
  ///
  /// In zh, this message translates to:
  /// **'重设'**
  String get parent_settings_pin_dlg_ok;

  /// No description provided for @parent_settings_pin_too_short_snack.
  ///
  /// In zh, this message translates to:
  /// **'新 PIN 至少 4 位'**
  String get parent_settings_pin_too_short_snack;

  /// No description provided for @parent_settings_pin_wrong_snack.
  ///
  /// In zh, this message translates to:
  /// **'当前 PIN 不正确'**
  String get parent_settings_pin_wrong_snack;

  /// No description provided for @parent_settings_pin_ok_snack.
  ///
  /// In zh, this message translates to:
  /// **'PIN 已重设'**
  String get parent_settings_pin_ok_snack;

  /// No description provided for @parent_settings_gift_dlg_title.
  ///
  /// In zh, this message translates to:
  /// **'赠予阳光'**
  String get parent_settings_gift_dlg_title;

  /// No description provided for @parent_settings_gift_daily_line.
  ///
  /// In zh, this message translates to:
  /// **'今日已赠 {given} / {daily} ☀，还可赠 {remain} ☀'**
  String parent_settings_gift_daily_line(int given, int daily, int remain);

  /// No description provided for @parent_settings_gift_monthly_line.
  ///
  /// In zh, this message translates to:
  /// **'本月已赠 {given} / {monthly} ☀，还可赠 {remain} ☀'**
  String parent_settings_gift_monthly_line(int given, int monthly, int remain);

  /// No description provided for @parent_settings_gift_amount_label.
  ///
  /// In zh, this message translates to:
  /// **'赠予数量'**
  String get parent_settings_gift_amount_label;

  /// No description provided for @parent_settings_gift_err_positive.
  ///
  /// In zh, this message translates to:
  /// **'请输入正数'**
  String get parent_settings_gift_err_positive;

  /// No description provided for @parent_settings_gift_err_over.
  ///
  /// In zh, this message translates to:
  /// **'最多可赠 {max} ☀（今日剩 {day} / 本月剩 {month}）'**
  String parent_settings_gift_err_over(int max, int day, int month);

  /// No description provided for @parent_settings_gift_btn.
  ///
  /// In zh, this message translates to:
  /// **'赠予'**
  String get parent_settings_gift_btn;

  /// No description provided for @parent_settings_gift_daily_cap_snack.
  ///
  /// In zh, this message translates to:
  /// **'今日赠予已达上限（{daily} ☀/天），明天再来'**
  String parent_settings_gift_daily_cap_snack(int daily);

  /// No description provided for @parent_settings_gift_monthly_cap_snack.
  ///
  /// In zh, this message translates to:
  /// **'本月赠予已达上限（{monthly} ☀/月）'**
  String parent_settings_gift_monthly_cap_snack(int monthly);

  /// No description provided for @parent_settings_gift_over_snack.
  ///
  /// In zh, this message translates to:
  /// **'超出赠予上限，未赠予（今日剩 {remain} ☀）'**
  String parent_settings_gift_over_snack(int remain);

  /// No description provided for @parent_settings_gift_ok_snack.
  ///
  /// In zh, this message translates to:
  /// **'已赠予 {amount} ☀，孩子端已到账（今日剩 {remain} ☀）'**
  String parent_settings_gift_ok_snack(int amount, int remain);

  /// No description provided for @parent_settings_debug_member_title.
  ///
  /// In zh, this message translates to:
  /// **'会员模式（仅调试）'**
  String get parent_settings_debug_member_title;

  /// No description provided for @parent_settings_debug_member_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开即解锁全部付费功能；重启 App 后失效'**
  String get parent_settings_debug_member_subtitle;

  /// No description provided for @parent_profile_tier_low.
  ///
  /// In zh, this message translates to:
  /// **'低年级 · 8 岁及以下'**
  String get parent_profile_tier_low;

  /// No description provided for @parent_profile_tier_mid.
  ///
  /// In zh, this message translates to:
  /// **'中年级 · 9–12 岁'**
  String get parent_profile_tier_mid;

  /// No description provided for @parent_profile_tier_high.
  ///
  /// In zh, this message translates to:
  /// **'高年级 · 13 岁及以上'**
  String get parent_profile_tier_high;

  /// No description provided for @parent_profile_menu_edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get parent_profile_menu_edit;

  /// No description provided for @parent_profile_menu_delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get parent_profile_menu_delete;

  /// No description provided for @parent_profile_menu_create.
  ///
  /// In zh, this message translates to:
  /// **'新建孩子'**
  String get parent_profile_menu_create;

  /// No description provided for @parent_profile_toast_switched.
  ///
  /// In zh, this message translates to:
  /// **'已切换到「{name}」'**
  String parent_profile_toast_switched(String name);

  /// No description provided for @parent_profile_toast_added.
  ///
  /// In zh, this message translates to:
  /// **'已添加「{name}」'**
  String parent_profile_toast_added(String name);

  /// No description provided for @parent_profile_toast_updated.
  ///
  /// In zh, this message translates to:
  /// **'已更新「{name}」'**
  String parent_profile_toast_updated(String name);

  /// No description provided for @parent_profile_toast_deleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除「{name}」'**
  String parent_profile_toast_deleted(String name);

  /// No description provided for @parent_profile_max_toast.
  ///
  /// In zh, this message translates to:
  /// **'最多支持 {count} 个孩子账户'**
  String parent_profile_max_toast(int count);

  /// No description provided for @parent_profile_min_toast.
  ///
  /// In zh, this message translates to:
  /// **'至少保留一个孩子档案'**
  String get parent_profile_min_toast;

  /// No description provided for @parent_profile_create_title.
  ///
  /// In zh, this message translates to:
  /// **'新建孩子'**
  String get parent_profile_create_title;

  /// No description provided for @parent_profile_edit_title.
  ///
  /// In zh, this message translates to:
  /// **'编辑孩子'**
  String get parent_profile_edit_title;

  /// No description provided for @parent_profile_name_label.
  ///
  /// In zh, this message translates to:
  /// **'孩子名字'**
  String get parent_profile_name_label;

  /// No description provided for @parent_profile_name_hint.
  ///
  /// In zh, this message translates to:
  /// **'比如：小向日葵'**
  String get parent_profile_name_hint;

  /// No description provided for @parent_profile_btn_create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get parent_profile_btn_create;

  /// No description provided for @parent_profile_delete_title.
  ///
  /// In zh, this message translates to:
  /// **'删除「{name}」？'**
  String parent_profile_delete_title(String name);

  /// No description provided for @parent_profile_delete_body.
  ///
  /// In zh, this message translates to:
  /// **'删除后该孩子的档案设置将被移除，且无法恢复。'**
  String get parent_profile_delete_body;

  /// No description provided for @parent_profile_pin_label.
  ///
  /// In zh, this message translates to:
  /// **'家长 PIN'**
  String get parent_profile_pin_label;

  /// No description provided for @parent_profile_pin_err_empty.
  ///
  /// In zh, this message translates to:
  /// **'请输入家长 PIN'**
  String get parent_profile_pin_err_empty;

  /// No description provided for @parent_profile_pin_err_wrong.
  ///
  /// In zh, this message translates to:
  /// **'PIN 不正确，请重试'**
  String get parent_profile_pin_err_wrong;

  /// No description provided for @parent_history_seg_report.
  ///
  /// In zh, this message translates to:
  /// **'专注报告'**
  String get parent_history_seg_report;

  /// No description provided for @parent_history_seg_activity.
  ///
  /// In zh, this message translates to:
  /// **'任务与奖励'**
  String get parent_history_seg_activity;

  /// No description provided for @parent_hist_section_tasks.
  ///
  /// In zh, this message translates to:
  /// **'成长任务完成记录'**
  String get parent_hist_section_tasks;

  /// No description provided for @parent_hist_task_tail.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 次'**
  String parent_hist_task_tail(int count);

  /// No description provided for @parent_hist_empty_tasks.
  ///
  /// In zh, this message translates to:
  /// **'本期间还没有成长项完成记录'**
  String get parent_hist_empty_tasks;

  /// No description provided for @parent_hist_section_rewards.
  ///
  /// In zh, this message translates to:
  /// **'奖励兑换记录'**
  String get parent_hist_section_rewards;

  /// No description provided for @parent_hist_reward_tail.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 次 · 消耗 {cost} 阳光'**
  String parent_hist_reward_tail(int count, int cost);

  /// No description provided for @parent_hist_empty_rewards.
  ///
  /// In zh, this message translates to:
  /// **'本期间还没有奖励兑换记录'**
  String get parent_hist_empty_rewards;

  /// No description provided for @parent_hist_deleted_task.
  ///
  /// In zh, this message translates to:
  /// **'（已删除的成长项）'**
  String get parent_hist_deleted_task;

  /// No description provided for @parent_hist_deleted_reward.
  ///
  /// In zh, this message translates to:
  /// **'（已删除的奖励）'**
  String get parent_hist_deleted_reward;

  /// No description provided for @parent_hist_done_badge.
  ///
  /// In zh, this message translates to:
  /// **'完成 {count} 次'**
  String parent_hist_done_badge(int count);

  /// No description provided for @parent_hist_redeem_badge.
  ///
  /// In zh, this message translates to:
  /// **'兑换 {count} 次'**
  String parent_hist_redeem_badge(int count);

  /// No description provided for @parent_verify_partial_badge.
  ///
  /// In zh, this message translates to:
  /// **'部分完成 {percent}%'**
  String parent_verify_partial_badge(int percent);

  /// No description provided for @parent_hist_range_multi.
  ///
  /// In zh, this message translates to:
  /// **'首次 {first} ～ 最近 {last}'**
  String parent_hist_range_multi(String first, String last);

  /// No description provided for @parent_hist_cost_line.
  ///
  /// In zh, this message translates to:
  /// **'{range} · 消耗 {cost} 阳光'**
  String parent_hist_cost_line(String range, int cost);

  /// No description provided for @parent_hist_summary_done.
  ///
  /// In zh, this message translates to:
  /// **'本期完成成长项'**
  String get parent_hist_summary_done;

  /// No description provided for @parent_hist_summary_redeem.
  ///
  /// In zh, this message translates to:
  /// **'本期兑换奖励'**
  String get parent_hist_summary_redeem;

  /// No description provided for @parent_hist_summary_cost.
  ///
  /// In zh, this message translates to:
  /// **'本期消耗阳光'**
  String get parent_hist_summary_cost;

  /// No description provided for @parent_report_error_hint.
  ///
  /// In zh, this message translates to:
  /// **'报告生成失败，请下拉重试'**
  String get parent_report_error_hint;

  /// No description provided for @parent_report_period_day.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get parent_report_period_day;

  /// No description provided for @parent_report_period_week.
  ///
  /// In zh, this message translates to:
  /// **'周'**
  String get parent_report_period_week;

  /// No description provided for @parent_report_period_month.
  ///
  /// In zh, this message translates to:
  /// **'月'**
  String get parent_report_period_month;

  /// No description provided for @parent_report_period_year.
  ///
  /// In zh, this message translates to:
  /// **'年'**
  String get parent_report_period_year;

  /// No description provided for @parent_report_prev_tooltip.
  ///
  /// In zh, this message translates to:
  /// **'上一期间'**
  String get parent_report_prev_tooltip;

  /// No description provided for @parent_report_next_tooltip.
  ///
  /// In zh, this message translates to:
  /// **'下一期间'**
  String get parent_report_next_tooltip;

  /// No description provided for @parent_report_hero_title.
  ///
  /// In zh, this message translates to:
  /// **'本期间专注'**
  String get parent_report_hero_title;

  /// No description provided for @parent_report_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String parent_report_minutes(int minutes);

  /// No description provided for @parent_report_valid_days.
  ///
  /// In zh, this message translates to:
  /// **'有效专注日 {days} 天'**
  String parent_report_valid_days(int days);

  /// No description provided for @parent_report_avg_daily.
  ///
  /// In zh, this message translates to:
  /// **'平均每日 {minutes} 分钟'**
  String parent_report_avg_daily(int minutes);

  /// No description provided for @parent_report_trend_day.
  ///
  /// In zh, this message translates to:
  /// **'近 7 日专注分布'**
  String get parent_report_trend_day;

  /// No description provided for @parent_report_trend_week.
  ///
  /// In zh, this message translates to:
  /// **'本周专注分布'**
  String get parent_report_trend_week;

  /// No description provided for @parent_report_trend_month.
  ///
  /// In zh, this message translates to:
  /// **'本月专注分布（按周）'**
  String get parent_report_trend_month;

  /// No description provided for @parent_report_trend_year.
  ///
  /// In zh, this message translates to:
  /// **'本年专注分布（按月）'**
  String get parent_report_trend_year;

  /// No description provided for @parent_report_stability_title.
  ///
  /// In zh, this message translates to:
  /// **'专注稳定性 · 近 4 周'**
  String get parent_report_stability_title;

  /// No description provided for @parent_report_heatmap_title.
  ///
  /// In zh, this message translates to:
  /// **'专注热力图 · 近 1 年'**
  String get parent_report_heatmap_title;

  /// No description provided for @parent_report_eyecare_title.
  ///
  /// In zh, this message translates to:
  /// **'护眼统计'**
  String get parent_report_eyecare_title;

  /// No description provided for @parent_report_eyecare_loading.
  ///
  /// In zh, this message translates to:
  /// **'护眼统计读取中…'**
  String get parent_report_eyecare_loading;

  /// No description provided for @parent_report_trend_empty.
  ///
  /// In zh, this message translates to:
  /// **'本期间还没有专注记录。陪孩子完成一次 15 分钟专注，这里就会亮起来。'**
  String get parent_report_trend_empty;

  /// No description provided for @parent_report_label_today.
  ///
  /// In zh, this message translates to:
  /// **'今天 · {date}'**
  String parent_report_label_today(String date);

  /// No description provided for @parent_report_label_yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天 · {date}'**
  String parent_report_label_yesterday(String date);

  /// No description provided for @parent_report_label_range.
  ///
  /// In zh, this message translates to:
  /// **'{start} ～ {end}'**
  String parent_report_label_range(String start, String end);

  /// No description provided for @parent_report_label_month.
  ///
  /// In zh, this message translates to:
  /// **'{year} 年 {month} 月'**
  String parent_report_label_month(int year, int month);

  /// No description provided for @parent_report_label_year.
  ///
  /// In zh, this message translates to:
  /// **'{year} 年'**
  String parent_report_label_year(int year);

  /// No description provided for @parent_report_wd_mon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get parent_report_wd_mon;

  /// No description provided for @parent_report_wd_tue.
  ///
  /// In zh, this message translates to:
  /// **'二'**
  String get parent_report_wd_tue;

  /// No description provided for @parent_report_wd_wed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get parent_report_wd_wed;

  /// No description provided for @parent_report_wd_thu.
  ///
  /// In zh, this message translates to:
  /// **'四'**
  String get parent_report_wd_thu;

  /// No description provided for @parent_report_wd_fri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get parent_report_wd_fri;

  /// No description provided for @parent_report_wd_sat.
  ///
  /// In zh, this message translates to:
  /// **'六'**
  String get parent_report_wd_sat;

  /// No description provided for @parent_report_wd_sun.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get parent_report_wd_sun;

  /// No description provided for @parent_report_heat_empty.
  ///
  /// In zh, this message translates to:
  /// **'近 1 年还没有专注记录。'**
  String get parent_report_heat_empty;

  /// No description provided for @parent_report_heat_tip.
  ///
  /// In zh, this message translates to:
  /// **'{date} · {minutes} 分钟'**
  String parent_report_heat_tip(String date, int minutes);

  /// No description provided for @parent_report_month_tick.
  ///
  /// In zh, this message translates to:
  /// **'{month}月'**
  String parent_report_month_tick(int month);

  /// No description provided for @parent_report_legend_less.
  ///
  /// In zh, this message translates to:
  /// **'少'**
  String get parent_report_legend_less;

  /// No description provided for @parent_report_legend_more.
  ///
  /// In zh, this message translates to:
  /// **'多'**
  String get parent_report_legend_more;

  /// No description provided for @parent_report_streak_current.
  ///
  /// In zh, this message translates to:
  /// **'当前连续 {days} 天'**
  String parent_report_streak_current(int days);

  /// No description provided for @parent_report_streak_longest.
  ///
  /// In zh, this message translates to:
  /// **'最长连续 {days} 天'**
  String parent_report_streak_longest(int days);

  /// No description provided for @parent_report_stability_empty.
  ///
  /// In zh, this message translates to:
  /// **'近 4 周还没有专注记录。'**
  String get parent_report_stability_empty;

  /// No description provided for @parent_report_weeks_ago.
  ///
  /// In zh, this message translates to:
  /// **'{count} 周前'**
  String parent_report_weeks_ago(int count);

  /// No description provided for @parent_report_week_this.
  ///
  /// In zh, this message translates to:
  /// **'本周'**
  String get parent_report_week_this;

  /// No description provided for @parent_report_stability_score.
  ///
  /// In zh, this message translates to:
  /// **'稳定性 {percent}%'**
  String parent_report_stability_score(int percent);

  /// No description provided for @parent_report_upsell_title.
  ///
  /// In zh, this message translates to:
  /// **'解锁深度专注报告'**
  String get parent_report_upsell_title;

  /// No description provided for @parent_report_upsell_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'近 4 周稳定性 · 全年热力图'**
  String get parent_report_upsell_subtitle;

  /// No description provided for @parent_report_eyecare_completed.
  ///
  /// In zh, this message translates to:
  /// **'完成护眼'**
  String get parent_report_eyecare_completed;

  /// No description provided for @parent_report_eyecare_skipped.
  ///
  /// In zh, this message translates to:
  /// **'跳过护眼'**
  String get parent_report_eyecare_skipped;

  /// No description provided for @parent_report_eyecare_duration.
  ///
  /// In zh, this message translates to:
  /// **'累计护眼时长'**
  String get parent_report_eyecare_duration;

  /// No description provided for @parent_report_eyecare_rate.
  ///
  /// In zh, this message translates to:
  /// **'跳过率'**
  String get parent_report_eyecare_rate;

  /// No description provided for @parent_report_times.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String parent_report_times(int count);

  /// No description provided for @parent_report_secs.
  ///
  /// In zh, this message translates to:
  /// **'{count} 秒'**
  String parent_report_secs(int count);

  /// No description provided for @parent_report_minutes_1f.
  ///
  /// In zh, this message translates to:
  /// **'{value} 分钟'**
  String parent_report_minutes_1f(String value);

  /// No description provided for @parent_report_eyecare_skip_note.
  ///
  /// In zh, this message translates to:
  /// **'有 {count} 次护眼被跳过（跳过的观看时长已如实计入）。'**
  String parent_report_eyecare_skip_note(int count);

  /// No description provided for @premium_table_free_pill.
  ///
  /// In zh, this message translates to:
  /// **'免费版'**
  String get premium_table_free_pill;

  /// No description provided for @premium_table_gold_pill.
  ///
  /// In zh, this message translates to:
  /// **'解锁全部功能 ★'**
  String get premium_table_gold_pill;

  /// No description provided for @premium_table_owned.
  ///
  /// In zh, this message translates to:
  /// **'已拥有'**
  String get premium_table_owned;

  /// No description provided for @premium_table_band_free.
  ///
  /// In zh, this message translates to:
  /// **'免费就能用'**
  String get premium_table_band_free;

  /// No description provided for @premium_table_band_unlock.
  ///
  /// In zh, this message translates to:
  /// **'买断后解锁'**
  String get premium_table_band_unlock;

  /// No description provided for @premium_table_row_pomodoro.
  ///
  /// In zh, this message translates to:
  /// **'专注番茄钟'**
  String get premium_table_row_pomodoro;

  /// No description provided for @premium_table_row_screentime.
  ///
  /// In zh, this message translates to:
  /// **'防沉迷与作息'**
  String get premium_table_row_screentime;

  /// No description provided for @premium_table_row_eyecare.
  ///
  /// In zh, this message translates to:
  /// **'少儿护眼休息'**
  String get premium_table_row_eyecare;

  /// No description provided for @premium_table_row_garden.
  ///
  /// In zh, this message translates to:
  /// **'花园养成'**
  String get premium_table_row_garden;

  /// No description provided for @premium_table_row_economy.
  ///
  /// In zh, this message translates to:
  /// **'阳光经济与账本'**
  String get premium_table_row_economy;

  /// No description provided for @premium_table_row_store.
  ///
  /// In zh, this message translates to:
  /// **'商店兑换'**
  String get premium_table_row_store;

  /// No description provided for @premium_table_row_levels.
  ///
  /// In zh, this message translates to:
  /// **'专注等级 + 9 称号'**
  String get premium_table_row_levels;

  /// No description provided for @premium_table_row_report.
  ///
  /// In zh, this message translates to:
  /// **'家长专注报告'**
  String get premium_table_row_report;

  /// No description provided for @premium_table_report_days.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天'**
  String get premium_table_report_days;

  /// No description provided for @premium_table_footnote_report.
  ///
  /// In zh, this message translates to:
  /// **'更多报告能力开发中'**
  String get premium_table_footnote_report;

  /// No description provided for @premium_table_row_one_click.
  ///
  /// In zh, this message translates to:
  /// **'花园「一键操作」'**
  String get premium_table_row_one_click;

  /// No description provided for @premium_table_row_pots.
  ///
  /// In zh, this message translates to:
  /// **'花盆上限'**
  String get premium_table_row_pots;

  /// No description provided for @premium_table_row_tasks.
  ///
  /// In zh, this message translates to:
  /// **'成长项模板'**
  String get premium_table_row_tasks;

  /// No description provided for @premium_table_row_rewards.
  ///
  /// In zh, this message translates to:
  /// **'奖励模板'**
  String get premium_table_row_rewards;

  /// No description provided for @premium_table_row_perks.
  ///
  /// In zh, this message translates to:
  /// **'称号属性'**
  String get premium_table_row_perks;

  /// No description provided for @premium_table_free_pots.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String premium_table_free_pots(int count);

  /// No description provided for @premium_table_free_items.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String premium_table_free_items(int count);

  /// No description provided for @premium_table_unlimited.
  ///
  /// In zh, this message translates to:
  /// **'✓ 不限'**
  String get premium_table_unlimited;

  /// No description provided for @premium_table_max.
  ///
  /// In zh, this message translates to:
  /// **'最多 {count}'**
  String premium_table_max(int count);

  /// No description provided for @premium_table_pots_note.
  ///
  /// In zh, this message translates to:
  /// **'扩容仍需花阳光'**
  String get premium_table_pots_note;

  /// No description provided for @premium_table_perks_count.
  ///
  /// In zh, this message translates to:
  /// **'✓ {count} 条'**
  String premium_table_perks_count(int count);

  /// No description provided for @premium_quota_inline_reason.
  ///
  /// In zh, this message translates to:
  /// **'免费上限 {limit}（当前 {count}）'**
  String premium_quota_inline_reason(String limit, int count);

  /// No description provided for @parent_premium_title.
  ///
  /// In zh, this message translates to:
  /// **'解锁全部功能'**
  String get parent_premium_title;

  /// No description provided for @parent_premium_hero_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'一次买断 · 永久解锁，陪孩子一起专注成长'**
  String get parent_premium_hero_subtitle;

  /// No description provided for @parent_premium_pill_unlocked.
  ///
  /// In zh, this message translates to:
  /// **'已解锁'**
  String get parent_premium_pill_unlocked;

  /// No description provided for @parent_premium_pill_locked.
  ///
  /// In zh, this message translates to:
  /// **'未解锁'**
  String get parent_premium_pill_locked;

  /// No description provided for @parent_premium_gold_pill.
  ///
  /// In zh, this message translates to:
  /// **'一次买断 · 永久'**
  String get parent_premium_gold_pill;

  /// No description provided for @parent_premium_unavailable_title.
  ///
  /// In zh, this message translates to:
  /// **'暂时连不上商店'**
  String get parent_premium_unavailable_title;

  /// No description provided for @parent_premium_unavailable_body.
  ///
  /// In zh, this message translates to:
  /// **'现在无法获取商品信息，不影响你继续使用 App 的其他功能。请检查网络后再试。'**
  String get parent_premium_unavailable_body;

  /// No description provided for @parent_premium_btn_unlocked_done.
  ///
  /// In zh, this message translates to:
  /// **'已解锁 · 感谢支持'**
  String get parent_premium_btn_unlocked_done;

  /// No description provided for @parent_premium_btn_buying.
  ///
  /// In zh, this message translates to:
  /// **'购买中…'**
  String get parent_premium_btn_buying;

  /// No description provided for @parent_premium_btn_unavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂不可购买'**
  String get parent_premium_btn_unavailable;

  /// No description provided for @parent_premium_btn_unlock_now.
  ///
  /// In zh, this message translates to:
  /// **'立即解锁 · {price}'**
  String parent_premium_btn_unlock_now(String price);

  /// No description provided for @parent_premium_restoring.
  ///
  /// In zh, this message translates to:
  /// **'恢复中…'**
  String get parent_premium_restoring;

  /// No description provided for @parent_premium_restore.
  ///
  /// In zh, this message translates to:
  /// **'恢复购买'**
  String get parent_premium_restore;

  /// No description provided for @parent_premium_notes_title.
  ///
  /// In zh, this message translates to:
  /// **'购买前请知悉'**
  String get parent_premium_notes_title;

  /// No description provided for @parent_premium_note_1.
  ///
  /// In zh, this message translates to:
  /// **'一次买断、永久解锁 —— 不是订阅，不会自动续费。'**
  String get parent_premium_note_1;

  /// No description provided for @parent_premium_note_2.
  ///
  /// In zh, this message translates to:
  /// **'同一 Apple ID 换手机 / 卸载重装后，点「恢复购买」即可找回。'**
  String get parent_premium_note_2;

  /// No description provided for @parent_premium_note_3.
  ///
  /// In zh, this message translates to:
  /// **'⚠️ 在 iOS 上购买的内容，无法在 Android 设备上「恢复购买」（反之亦然）。'**
  String get parent_premium_note_3;

  /// No description provided for @parent_premium_note_4.
  ///
  /// In zh, this message translates to:
  /// **'支付通过 Apple App Store 完成，开发者不会接触到你的任何支付信息。'**
  String get parent_premium_note_4;

  /// No description provided for @parent_premium_snack_unlocked.
  ///
  /// In zh, this message translates to:
  /// **'已解锁，感谢支持 🌻'**
  String get parent_premium_snack_unlocked;

  /// No description provided for @parent_premium_snack_incomplete.
  ///
  /// In zh, this message translates to:
  /// **'购买未完成，可稍后再试'**
  String get parent_premium_snack_incomplete;

  /// No description provided for @parent_premium_snack_buy_failed.
  ///
  /// In zh, this message translates to:
  /// **'购买失败，请稍后重试'**
  String get parent_premium_snack_buy_failed;

  /// No description provided for @parent_premium_snack_restored.
  ///
  /// In zh, this message translates to:
  /// **'已恢复购买，欢迎回来 🌻'**
  String get parent_premium_snack_restored;

  /// No description provided for @parent_premium_snack_nothing.
  ///
  /// In zh, this message translates to:
  /// **'没有找到可恢复的购买记录'**
  String get parent_premium_snack_nothing;

  /// No description provided for @parent_premium_snack_restore_net.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败，请检查网络后重试'**
  String get parent_premium_snack_restore_net;

  /// No description provided for @parent_premium_snack_restore_failed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败，请稍后重试'**
  String get parent_premium_snack_restore_failed;

  /// No description provided for @parent_reward_category_label.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get parent_reward_category_label;

  /// No description provided for @shared_lang_zh_name.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get shared_lang_zh_name;

  /// No description provided for @shared_task_category_other.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get shared_task_category_other;

  /// No description provided for @shared_task_category_learning.
  ///
  /// In zh, this message translates to:
  /// **'学习'**
  String get shared_task_category_learning;

  /// No description provided for @shared_task_category_sports.
  ///
  /// In zh, this message translates to:
  /// **'运动'**
  String get shared_task_category_sports;

  /// No description provided for @shared_task_category_life.
  ///
  /// In zh, this message translates to:
  /// **'生活'**
  String get shared_task_category_life;

  /// No description provided for @shared_task_category_habit.
  ///
  /// In zh, this message translates to:
  /// **'习惯'**
  String get shared_task_category_habit;

  /// No description provided for @shared_reward_content_other.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get shared_reward_content_other;

  /// No description provided for @shared_reward_content_snacks.
  ///
  /// In zh, this message translates to:
  /// **'零食'**
  String get shared_reward_content_snacks;

  /// No description provided for @shared_reward_content_play.
  ///
  /// In zh, this message translates to:
  /// **'游玩'**
  String get shared_reward_content_play;

  /// No description provided for @shared_reward_content_entertainment.
  ///
  /// In zh, this message translates to:
  /// **'娱乐'**
  String get shared_reward_content_entertainment;

  /// No description provided for @shared_reward_content_toys.
  ///
  /// In zh, this message translates to:
  /// **'玩具'**
  String get shared_reward_content_toys;

  /// No description provided for @shared_reward_content_books.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get shared_reward_content_books;

  /// No description provided for @shared_species_sunflower.
  ///
  /// In zh, this message translates to:
  /// **'向日葵'**
  String get shared_species_sunflower;

  /// No description provided for @shared_species_moon_orchid.
  ///
  /// In zh, this message translates to:
  /// **'月光兰'**
  String get shared_species_moon_orchid;

  /// No description provided for @shared_species_tomato.
  ///
  /// In zh, this message translates to:
  /// **'番茄'**
  String get shared_species_tomato;

  /// No description provided for @shared_species_strawberry.
  ///
  /// In zh, this message translates to:
  /// **'草莓'**
  String get shared_species_strawberry;

  /// No description provided for @shared_species_coral_orchid.
  ///
  /// In zh, this message translates to:
  /// **'珊瑚岭兰'**
  String get shared_species_coral_orchid;

  /// No description provided for @shared_species_jade_hydrangea.
  ///
  /// In zh, this message translates to:
  /// **'翡翠绣球'**
  String get shared_species_jade_hydrangea;

  /// No description provided for @shared_weekday_mon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get shared_weekday_mon;

  /// No description provided for @shared_weekday_tue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get shared_weekday_tue;

  /// No description provided for @shared_weekday_wed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get shared_weekday_wed;

  /// No description provided for @shared_weekday_thu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get shared_weekday_thu;

  /// No description provided for @shared_weekday_fri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get shared_weekday_fri;

  /// No description provided for @shared_weekday_sat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get shared_weekday_sat;

  /// No description provided for @shared_weekday_sun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get shared_weekday_sun;

  /// No description provided for @parent_report_bucket_week.
  ///
  /// In zh, this message translates to:
  /// **'第{index}周'**
  String parent_report_bucket_week(int index);

  /// No description provided for @shared_perk_water_discount.
  ///
  /// In zh, this message translates to:
  /// **'浇水消耗 −{value}'**
  String shared_perk_water_discount(int value);

  /// No description provided for @shared_perk_fertilize_discount.
  ///
  /// In zh, this message translates to:
  /// **'施肥消耗 −{value}'**
  String shared_perk_fertilize_discount(int value);

  /// No description provided for @shared_perk_weed_bonus.
  ///
  /// In zh, this message translates to:
  /// **'除草奖励 +{value}'**
  String shared_perk_weed_bonus(int value);

  /// No description provided for @shared_perk_pest_bonus.
  ///
  /// In zh, this message translates to:
  /// **'除虫奖励 +{value}'**
  String shared_perk_pest_bonus(int value);

  /// No description provided for @shared_perk_bloom_bonus.
  ///
  /// In zh, this message translates to:
  /// **'开花阳光 +{value}'**
  String shared_perk_bloom_bonus(int value);

  /// No description provided for @shared_perk_dew_bonus.
  ///
  /// In zh, this message translates to:
  /// **'晨露阳光 +{value}'**
  String shared_perk_dew_bonus(int value);

  /// No description provided for @shared_perk_eyecare_bonus.
  ///
  /// In zh, this message translates to:
  /// **'护眼奖励 +{value}'**
  String shared_perk_eyecare_bonus(int value);

  /// No description provided for @shared_perk_expand_discount.
  ///
  /// In zh, this message translates to:
  /// **'花盆扩容 −{value}'**
  String shared_perk_expand_discount(int value);

  /// No description provided for @shared_perk_shovel_refund.
  ///
  /// In zh, this message translates to:
  /// **'铲除退款 +{value}'**
  String shared_perk_shovel_refund(int value);

  /// No description provided for @shared_duration_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{m} 分钟'**
  String shared_duration_minutes(int m);

  /// No description provided for @shared_duration_hours.
  ///
  /// In zh, this message translates to:
  /// **'{h} 小时'**
  String shared_duration_hours(int h);

  /// No description provided for @shared_duration_hours_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{h} 小时 {m} 分钟'**
  String shared_duration_hours_minutes(int h, int m);

  /// No description provided for @shared_level_gap_next.
  ///
  /// In zh, this message translates to:
  /// **'距 Lv.{n} 还差 {duration}'**
  String shared_level_gap_next(int n, String duration);

  /// No description provided for @shared_level_gap_max.
  ///
  /// In zh, this message translates to:
  /// **'已是最高称号 · {title}'**
  String shared_level_gap_max(String title);

  /// No description provided for @shared_reward_weekly_limit.
  ///
  /// In zh, this message translates to:
  /// **'周限 {remaining} 次'**
  String shared_reward_weekly_limit(int remaining);

  /// No description provided for @shared_reward_unlimited.
  ///
  /// In zh, this message translates to:
  /// **'不限次数'**
  String get shared_reward_unlimited;

  /// No description provided for @shared_plant_err_species_not_found.
  ///
  /// In zh, this message translates to:
  /// **'未找到该植物物种'**
  String get shared_plant_err_species_not_found;

  /// No description provided for @shared_plant_err_pot_out_of_capacity.
  ///
  /// In zh, this message translates to:
  /// **'花盆序号超出容量（{pot} / {capacity}）'**
  String shared_plant_err_pot_out_of_capacity(int pot, int capacity);

  /// No description provided for @shared_plant_err_pot_occupied.
  ///
  /// In zh, this message translates to:
  /// **'花盆 #{pot} 已被占用，请先清理'**
  String shared_plant_err_pot_occupied(int pot);

  /// No description provided for @shared_plant_err_premium_fragments_only.
  ///
  /// In zh, this message translates to:
  /// **'精英植物只能用碎片兑换'**
  String get shared_plant_err_premium_fragments_only;

  /// No description provided for @shared_plant_err_seed_empty.
  ///
  /// In zh, this message translates to:
  /// **'种子已用完，去开花收集新的种子吧'**
  String get shared_plant_err_seed_empty;

  /// No description provided for @shared_plant_err_sunlight_not_enough.
  ///
  /// In zh, this message translates to:
  /// **'阳光不足，还差 {short} 阳光'**
  String shared_plant_err_sunlight_not_enough(int short);

  /// No description provided for @shared_plant_err_fragments_not_enough.
  ///
  /// In zh, this message translates to:
  /// **'碎片不足，还差 {short} 片'**
  String shared_plant_err_fragments_not_enough(int short);

  /// No description provided for @shared_plant_err_care_state_invalid.
  ///
  /// In zh, this message translates to:
  /// **'仅成长中/开花/枯萎植物可养护'**
  String get shared_plant_err_care_state_invalid;

  /// No description provided for @shared_plant_err_water_daily_limit.
  ///
  /// In zh, this message translates to:
  /// **'今日浇水已达 {max} 次上限'**
  String shared_plant_err_water_daily_limit(int max);

  /// No description provided for @shared_plant_err_water_interval.
  ///
  /// In zh, this message translates to:
  /// **'浇水间隔需 {interval} 分钟，还需 {wait} 分钟'**
  String shared_plant_err_water_interval(int interval, int wait);

  /// No description provided for @shared_plant_err_fertilize_daily_limit.
  ///
  /// In zh, this message translates to:
  /// **'今日施肥已达 {max} 次上限'**
  String shared_plant_err_fertilize_daily_limit(int max);

  /// No description provided for @shared_plant_err_plant_not_found.
  ///
  /// In zh, this message translates to:
  /// **'植物不存在'**
  String get shared_plant_err_plant_not_found;

  /// No description provided for @shared_plant_err_already_wilted.
  ///
  /// In zh, this message translates to:
  /// **'这株已经枯萎了，不用清理啦'**
  String get shared_plant_err_already_wilted;

  /// No description provided for @shared_plant_err_no_weed.
  ///
  /// In zh, this message translates to:
  /// **'这盆没有杂草哦'**
  String get shared_plant_err_no_weed;

  /// No description provided for @shared_plant_err_no_pest.
  ///
  /// In zh, this message translates to:
  /// **'这盆没有害虫哦'**
  String get shared_plant_err_no_pest;

  /// No description provided for @shared_plant_err_garden_full.
  ///
  /// In zh, this message translates to:
  /// **'花园已达当前档位容量上限（{limit} 盆），解锁可扩容'**
  String shared_plant_err_garden_full(int limit);

  /// No description provided for @shared_plant_err_reward_not_mature.
  ///
  /// In zh, this message translates to:
  /// **'奖励还没成熟，或已经被领取啦'**
  String get shared_plant_err_reward_not_mature;

  /// No description provided for @shared_checkin_err_linked_auto.
  ///
  /// In zh, this message translates to:
  /// **'这个成长项要在专注里自动完成哦'**
  String get shared_checkin_err_linked_auto;

  /// No description provided for @shared_checkin_err_already_done.
  ///
  /// In zh, this message translates to:
  /// **'这个成长项今天已经做到啦'**
  String get shared_checkin_err_already_done;

  /// No description provided for @shared_checkin_err_not_linked.
  ///
  /// In zh, this message translates to:
  /// **'非联动成长项不能走专注结算'**
  String get shared_checkin_err_not_linked;

  /// No description provided for @shared_checkin_err_session_not_today.
  ///
  /// In zh, this message translates to:
  /// **'这次专注不在今天，不能结算今天的成长项'**
  String get shared_checkin_err_session_not_today;

  /// No description provided for @shared_checkin_err_session_used.
  ///
  /// In zh, this message translates to:
  /// **'这次专注已经结算过成长项啦'**
  String get shared_checkin_err_session_used;

  /// No description provided for @shared_checkin_err_not_found.
  ///
  /// In zh, this message translates to:
  /// **'找不到这条记录，可能已被删除'**
  String get shared_checkin_err_not_found;

  /// No description provided for @shared_checkin_err_already_verified.
  ///
  /// In zh, this message translates to:
  /// **'这条记录已经处理过啦，不能重复核销'**
  String get shared_checkin_err_already_verified;

  /// No description provided for @shared_checkin_err_already_rejected.
  ///
  /// In zh, this message translates to:
  /// **'这条记录已经处理过啦，不能重复处理'**
  String get shared_checkin_err_already_rejected;

  /// No description provided for @shared_checkin_err_race.
  ///
  /// In zh, this message translates to:
  /// **'这条记录刚刚已经被处理过了'**
  String get shared_checkin_err_race;

  /// No description provided for @seed_task_homework.
  ///
  /// In zh, this message translates to:
  /// **'完成学校作业'**
  String get seed_task_homework;

  /// No description provided for @seed_task_math.
  ///
  /// In zh, this message translates to:
  /// **'练习数学口算'**
  String get seed_task_math;

  /// No description provided for @seed_task_read.
  ///
  /// In zh, this message translates to:
  /// **'阅读 20 分钟'**
  String get seed_task_read;

  /// No description provided for @seed_task_rope_skip.
  ///
  /// In zh, this message translates to:
  /// **'1分钟跳绳170个以上'**
  String get seed_task_rope_skip;

  /// No description provided for @seed_task_chores.
  ///
  /// In zh, this message translates to:
  /// **'帮助家长打扫卫生'**
  String get seed_task_chores;

  /// No description provided for @seed_reward_snack.
  ///
  /// In zh, this message translates to:
  /// **'小零食'**
  String get seed_reward_snack;

  /// No description provided for @seed_reward_extra_play.
  ///
  /// In zh, this message translates to:
  /// **'睡前多玩10分钟'**
  String get seed_reward_extra_play;

  /// No description provided for @seed_reward_cartoon.
  ///
  /// In zh, this message translates to:
  /// **'看一集动画片'**
  String get seed_reward_cartoon;

  /// No description provided for @seed_reward_toy.
  ///
  /// In zh, this message translates to:
  /// **'买一个小玩具'**
  String get seed_reward_toy;

  /// No description provided for @seed_reward_weekend_outing.
  ///
  /// In zh, this message translates to:
  /// **'周末出去玩'**
  String get seed_reward_weekend_outing;

  /// No description provided for @shared_child_default_name.
  ///
  /// In zh, this message translates to:
  /// **'孩子'**
  String get shared_child_default_name;

  /// No description provided for @child_hist_ref_focus.
  ///
  /// In zh, this message translates to:
  /// **'专注产出'**
  String get child_hist_ref_focus;

  /// No description provided for @child_hist_ref_focus_session.
  ///
  /// In zh, this message translates to:
  /// **'专注'**
  String get child_hist_ref_focus_session;

  /// No description provided for @child_hist_ref_focus_task_reward.
  ///
  /// In zh, this message translates to:
  /// **'专注任务奖励'**
  String get child_hist_ref_focus_task_reward;

  /// No description provided for @child_hist_ref_task_checkin.
  ///
  /// In zh, this message translates to:
  /// **'成长项奖励'**
  String get child_hist_ref_task_checkin;

  /// No description provided for @child_hist_ref_plant_plant.
  ///
  /// In zh, this message translates to:
  /// **'种植植物'**
  String get child_hist_ref_plant_plant;

  /// No description provided for @child_hist_ref_plant_water.
  ///
  /// In zh, this message translates to:
  /// **'浇水'**
  String get child_hist_ref_plant_water;

  /// No description provided for @child_hist_ref_plant_fertilize.
  ///
  /// In zh, this message translates to:
  /// **'施肥'**
  String get child_hist_ref_plant_fertilize;

  /// No description provided for @child_hist_ref_plant_revive.
  ///
  /// In zh, this message translates to:
  /// **'救回植物'**
  String get child_hist_ref_plant_revive;

  /// No description provided for @child_hist_ref_plant_expand.
  ///
  /// In zh, this message translates to:
  /// **'花园扩容'**
  String get child_hist_ref_plant_expand;

  /// No description provided for @child_hist_ref_plant_weed.
  ///
  /// In zh, this message translates to:
  /// **'拔草'**
  String get child_hist_ref_plant_weed;

  /// No description provided for @child_hist_ref_plant_pest.
  ///
  /// In zh, this message translates to:
  /// **'除虫'**
  String get child_hist_ref_plant_pest;

  /// No description provided for @child_hist_ref_plant_death_refund.
  ///
  /// In zh, this message translates to:
  /// **'植物死亡返还'**
  String get child_hist_ref_plant_death_refund;

  /// No description provided for @child_hist_ref_eye_care_break.
  ///
  /// In zh, this message translates to:
  /// **'护眼'**
  String get child_hist_ref_eye_care_break;

  /// No description provided for @child_hist_ref_plant_shovel_refund.
  ///
  /// In zh, this message translates to:
  /// **'铲除返还'**
  String get child_hist_ref_plant_shovel_refund;

  /// No description provided for @child_hist_ref_bloom_reward.
  ///
  /// In zh, this message translates to:
  /// **'开花奖励'**
  String get child_hist_ref_bloom_reward;

  /// No description provided for @child_hist_ref_bloom_reward_24h.
  ///
  /// In zh, this message translates to:
  /// **'花开回访奖励'**
  String get child_hist_ref_bloom_reward_24h;

  /// No description provided for @child_hist_ref_redeem.
  ///
  /// In zh, this message translates to:
  /// **'兑换奖励'**
  String get child_hist_ref_redeem;

  /// No description provided for @child_hist_ref_redemption.
  ///
  /// In zh, this message translates to:
  /// **'兑换奖励'**
  String get child_hist_ref_redemption;

  /// No description provided for @child_hist_ref_queue_release.
  ///
  /// In zh, this message translates to:
  /// **'阳光池释放'**
  String get child_hist_ref_queue_release;

  /// No description provided for @child_hist_ref_parent_gift.
  ///
  /// In zh, this message translates to:
  /// **'家长赠予'**
  String get child_hist_ref_parent_gift;

  /// No description provided for @child_hist_ref_debug_grant.
  ///
  /// In zh, this message translates to:
  /// **'调试发放'**
  String get child_hist_ref_debug_grant;

  /// No description provided for @child_hist_ref_focus_level_up.
  ///
  /// In zh, this message translates to:
  /// **'专注升级'**
  String get child_hist_ref_focus_level_up;

  /// No description provided for @child_eyecare_seg_default.
  ///
  /// In zh, this message translates to:
  /// **'跟着动画一起做，保护眼睛'**
  String get child_eyecare_seg_default;

  /// No description provided for @shared_perk_name_eye_care.
  ///
  /// In zh, this message translates to:
  /// **'护眼'**
  String get shared_perk_name_eye_care;

  /// No description provided for @shared_perk_name_water.
  ///
  /// In zh, this message translates to:
  /// **'浇水'**
  String get shared_perk_name_water;

  /// No description provided for @shared_perk_name_fertilize.
  ///
  /// In zh, this message translates to:
  /// **'施肥'**
  String get shared_perk_name_fertilize;

  /// No description provided for @shared_perk_name_weed.
  ///
  /// In zh, this message translates to:
  /// **'除草'**
  String get shared_perk_name_weed;

  /// No description provided for @shared_perk_name_pest.
  ///
  /// In zh, this message translates to:
  /// **'除虫'**
  String get shared_perk_name_pest;

  /// No description provided for @shared_perk_name_bloom.
  ///
  /// In zh, this message translates to:
  /// **'绽放'**
  String get shared_perk_name_bloom;

  /// No description provided for @shared_perk_name_dew.
  ///
  /// In zh, this message translates to:
  /// **'晨露'**
  String get shared_perk_name_dew;

  /// No description provided for @shared_perk_name_pot_expand.
  ///
  /// In zh, this message translates to:
  /// **'扩盆'**
  String get shared_perk_name_pot_expand;

  /// No description provided for @shared_perk_name_shovel.
  ///
  /// In zh, this message translates to:
  /// **'铲除'**
  String get shared_perk_name_shovel;

  /// No description provided for @shared_default_child_name.
  ///
  /// In zh, this message translates to:
  /// **'孩子'**
  String get shared_default_child_name;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
