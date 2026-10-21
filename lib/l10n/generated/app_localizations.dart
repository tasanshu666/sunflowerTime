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
  String child_lock_body(Object hour);

  /// No description provided for @child_rest_title.
  ///
  /// In zh, this message translates to:
  /// **'休息一下'**
  String get child_rest_title;

  /// No description provided for @child_rest_body.
  ///
  /// In zh, this message translates to:
  /// **'休息一下，喝口水～ 还剩 {sec} 秒'**
  String child_rest_body(Object sec);

  /// No description provided for @child_rest_done.
  ///
  /// In zh, this message translates to:
  /// **'我休息好了'**
  String get child_rest_done;

  /// No description provided for @child_eyecare_countdown.
  ///
  /// In zh, this message translates to:
  /// **'还剩 {sec} 秒'**
  String child_eyecare_countdown(Object sec);

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
  String child_today_minutes(Object minutes);

  /// No description provided for @child_today_focus_count.
  ///
  /// In zh, this message translates to:
  /// **'· {count} 次'**
  String child_today_focus_count(Object count);

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
  String child_settle_secs(Object sec);

  /// No description provided for @child_settle_mins.
  ///
  /// In zh, this message translates to:
  /// **'{min} 分钟'**
  String child_settle_mins(Object min);

  /// No description provided for @child_settle_min_sec.
  ///
  /// In zh, this message translates to:
  /// **'{min} 分 {sec} 秒'**
  String child_settle_min_sec(Object min, Object sec);

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
  String child_settle_task_capped(Object sun);

  /// No description provided for @child_settle_task_done.
  ///
  /// In zh, this message translates to:
  /// **'成长项「{name}」完成 +{sun} ☀{capped}'**
  String child_settle_task_done(Object capped, Object name, Object sun);

  /// No description provided for @child_settle_task_progress.
  ///
  /// In zh, this message translates to:
  /// **'成长项「{name}」还差一点，下次专注够时长就算上啦 🌻'**
  String child_settle_task_progress(Object name);

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
  String child_settle_cap_body_detail(Object cheer, Object detail);

  /// No description provided for @child_settle_cap_orig_vs_net.
  ///
  /// In zh, this message translates to:
  /// **'（原本 {raw} ☀️，实到 {net} ☀️）'**
  String child_settle_cap_orig_vs_net(Object net, Object raw);

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
  String child_cap_single_body(Object minutes);

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
  String child_cap_unlock_in(Object minutes);

  /// No description provided for @child_cap_minutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String child_cap_minutes(Object minutes);

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
  String child_entry_cap_daily(Object cap);

  /// No description provided for @child_entry_remaining_today.
  ///
  /// In zh, this message translates to:
  /// **'今天还可以专注 {minutes} 分钟（每日上限 {cap} 分钟）'**
  String child_entry_remaining_today(Object cap, Object minutes);

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
  String child_entry_custom_hint_max(Object max);

  /// No description provided for @child_entry_custom_hint_capped.
  ///
  /// In zh, this message translates to:
  /// **'可选 {max} 分钟以内（受今日剩余额度限制）'**
  String child_entry_custom_hint_capped(Object max);

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
  String child_entry_minutes(Object minutes);

  /// No description provided for @child_entry_cap_snack.
  ///
  /// In zh, this message translates to:
  /// **'今日专注已达上限（{cap} 分钟），明天再来哦'**
  String child_entry_cap_snack(Object cap);

  /// No description provided for @child_entry_cap_snack2.
  ///
  /// In zh, this message translates to:
  /// **'今天的专注时间用完啦（上限 {cap} 分钟），明天再来哦'**
  String child_entry_cap_snack2(Object cap);

  /// No description provided for @child_entry_remaining_snack.
  ///
  /// In zh, this message translates to:
  /// **'今天只剩 {remaining} 分钟额度了，这次就专注 {minutes} 分钟吧'**
  String child_entry_remaining_snack(Object minutes, Object remaining);

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
  String child_shell_item_cost(Object sun);

  /// No description provided for @child_shell_verify_total.
  ///
  /// In zh, this message translates to:
  /// **'共扣除 {total} 阳光'**
  String child_shell_verify_total(Object total);

  /// No description provided for @child_shell_reject_title.
  ///
  /// In zh, this message translates to:
  /// **'🚫 兑换未被通过'**
  String get child_shell_reject_title;

  /// No description provided for @child_shell_reject_subtitle.
  ///
  /// In zh, this message translates to:
  /// **'（{note}）'**
  String child_shell_reject_subtitle(Object note);

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
  String child_shell_task_footer_partial(Object capped, Object total);

  /// No description provided for @child_shell_task_footer.
  ///
  /// In zh, this message translates to:
  /// **'共获得 {total} 阳光'**
  String child_shell_task_footer(Object total);

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
  String child_shell_task_item_sun(Object sun);

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
