// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get app_title => 'Tiny Sunflower';

  @override
  String get consent_welcome_title => 'Welcome to Tiny Sunflower';

  @override
  String get consent_compliance_body =>
      '· We only collect necessary data such as focus time and check-ins;\n· All data is encrypted and stays on this device, never uploaded;\n· No account, no ads, no social features; we never access contacts or location.';

  @override
  String get consent_btn_agree => 'Let\'s Start';

  @override
  String get consent_btn_back_garden => 'Back to Garden';

  @override
  String consent_update_notice(String version) {
    return 'The privacy policy has been updated ($version). Please review and confirm again.';
  }

  @override
  String get consent_btn_disagree => 'Decline';

  @override
  String get consent_view_policy => 'View full privacy policy ›';

  @override
  String get consent_decline_title => 'Why is consent needed?';

  @override
  String get consent_decline_body =>
      'All Tiny Sunflower data stays only on this device and is never uploaded to any server. We need your consent to this notice before the app can be used.\n\nYou can review the notice or the privacy policy again, or exit the app.';

  @override
  String get consent_decline_stay => 'Reconsider';

  @override
  String get consent_decline_exit => 'Exit app';

  @override
  String get consent_data_title => 'What data lives in this app';

  @override
  String get consent_data_focus => 'Focus timers and task check-in records';

  @override
  String get consent_data_garden =>
      'Garden plants and child profile (nickname, avatar)';

  @override
  String get consent_data_local =>
      'All encrypted on this device only; uninstalling deletes everything';

  @override
  String get consent_data_none =>
      'No account, no ads, no tracking, nothing uploaded';

  @override
  String get privacy_policy_title => 'Privacy Policy';

  @override
  String get privacy_policy_load_failed =>
      'Failed to load the policy. Please try again.';

  @override
  String get parent_settings_entry_privacy_sub =>
      'Read the full privacy policy anytime in-app';

  @override
  String get shared_lang_title => 'Language';

  @override
  String get shared_lang_follow_system => 'Follow System';

  @override
  String get shared_ok => 'OK';

  @override
  String get shared_unlimited => 'Unlimited';

  @override
  String get parent_settings_lang_entry => 'Language';

  @override
  String get premium_gate_feature_one_click_care => 'One-tap garden care';

  @override
  String get premium_gate_feature_pot_capacity => 'More pots';

  @override
  String get premium_gate_feature_parent_report => 'Parent focus report';

  @override
  String get premium_gate_feature_task_templates => 'More task templates';

  @override
  String get premium_gate_feature_reward_templates => 'More reward templates';

  @override
  String get premium_gate_feature_multi_child => 'Multiple profiles';

  @override
  String get premium_gate_feature_deep_report => 'In-depth focus report';

  @override
  String get premium_gate_feature_export_share => 'Export & share';

  @override
  String get premium_gate_feature_memoir_export => 'Memoir export';

  @override
  String get premium_gate_feature_family_sharing => 'Family sharing';

  @override
  String get premium_gate_feature_title_perks => 'Title perks';

  @override
  String premium_gate_upsell_title(String name) {
    return 'Unlock \"$name\"';
  }

  @override
  String get premium_gate_upsell_subtitle => 'One purchase, unlock all';

  @override
  String get premium_gate_upsell_btn => 'Details';

  @override
  String get premium_gate_upsell_dialog_title => 'Upgrade';

  @override
  String premium_gate_upsell_dialog_message(String name) {
    return '\"$name\" requires a one-time purchase.';
  }

  @override
  String get premium_gate_later => 'Later';

  @override
  String get premium_gate_unlock_all => 'Unlock All';

  @override
  String premium_quota_snack(String limit, int count) {
    return 'Free limit: $limit (now $count). Remove extras to add more.';
  }

  @override
  String get child_lock_title => 'Bedtime';

  @override
  String get child_lock_sleeping => '🌻 The sunflower is sleeping';

  @override
  String child_lock_body(int hour) {
    return 'After $hour:00 the sunflower goes to sleep — see you tomorrow~';
  }

  @override
  String get child_rest_title => 'Take a Break';

  @override
  String child_rest_body(int sec) {
    return 'Take a break and sip some water — $sec s left';
  }

  @override
  String get child_rest_done => 'I\'m Done Resting';

  @override
  String child_eyecare_countdown(int sec) {
    return '$sec s left';
  }

  @override
  String get child_eyecare_title => 'Rest Your Eyes';

  @override
  String get shared_back => 'Back';

  @override
  String get shared_start_focus => 'Start Focus';

  @override
  String get shared_sunlight => 'Sunlight';

  @override
  String get child_today_sunlight_title => 'Sunlight Today';

  @override
  String get child_today_focus_label => 'Focus Today';

  @override
  String child_today_minutes(int minutes) {
    return '$minutes min';
  }

  @override
  String child_today_focus_count(int count) {
    return '· $count sessions';
  }

  @override
  String get child_today_growth_label => 'Growth Today';

  @override
  String get child_today_all_done => 'All Done 🌻';

  @override
  String get child_today_growth_hint =>
      'Want growth sunlight? Tap a task in \"Growth\" and start focusing 🌻';

  @override
  String child_settle_secs(int sec) {
    return '$sec s';
  }

  @override
  String child_settle_mins(int min) {
    return '$min min';
  }

  @override
  String child_settle_min_sec(int min, int sec) {
    return '$min min $sec s';
  }

  @override
  String get child_settle_task_label => 'Growth task';

  @override
  String get child_settle_task_skipped =>
      'Task settlement did not finish; this session\'s sunlight is unaffected';

  @override
  String child_settle_task_capped(String sun) {
    return '(Daily sunlight cap reached; only $sun ☀ credited)';
  }

  @override
  String child_settle_task_done(String capped, String name, String sun) {
    return 'Task \"$name\" done +$sun ☀$capped';
  }

  @override
  String child_settle_task_progress(String name) {
    return 'Task \"$name\" is nearly there — it counts once a session is long enough 🌻';
  }

  @override
  String child_settle_task_partial(int minutes, int percent, String sun) {
    return 'Ended early · $minutes min · $percent% done · +$sun sunlight';
  }

  @override
  String get child_settle_title => 'Focus Finished';

  @override
  String get child_settle_this_session => 'This Session';

  @override
  String get child_settle_collected => 'Sunlight Earned';

  @override
  String get child_settle_eyecare_reward => 'Eye-Break Reward';

  @override
  String get child_settle_task_reward => 'Task Reward';

  @override
  String get child_settle_today_total => 'Today\'s Total';

  @override
  String get child_settle_balance => 'Sunlight Balance';

  @override
  String get child_settle_too_short =>
      'Too short — the sunflower collected nothing (output starts at 5 min)';

  @override
  String get child_settle_cap_title => '🌻 Today\'s focus quota is used up';

  @override
  String child_settle_cap_body_detail(String cheer, String detail) {
    return 'No sunlight is collected beyond the quota$detail. $cheer';
  }

  @override
  String child_settle_cap_orig_vs_net(String net, String raw) {
    return '(originally $raw ☀️, credited $net ☀️)';
  }

  @override
  String get child_settle_cap_cheer => 'Great job today — see you tomorrow!';

  @override
  String get child_settle_home => 'Back Home';

  @override
  String get child_feedback_collected => 'Great! More sunlight collected.';

  @override
  String get child_feedback_welcome_back => 'Welcome back';

  @override
  String get child_feedback_rest_hint => 'Rest a bit and come back';

  @override
  String get child_feedback_miss =>
      'The sunflower misses you — come take a look';

  @override
  String get child_avatar_pick => 'Choose an Avatar';

  @override
  String get child_avatar_hint => 'Plants you\'ve grown can be your avatar';

  @override
  String get child_cap_single_title => 'Time for a Break';

  @override
  String get child_cap_daily_title => 'Take a Rest';

  @override
  String child_cap_single_body(int minutes) {
    return 'You\'ve played $minutes minutes straight — rest your eyes';
  }

  @override
  String get child_cap_daily_body => 'Today\'s app time is used up';

  @override
  String get child_cap_chip_rest => 'Break';

  @override
  String get child_cap_chip_daily => 'Daily Cap';

  @override
  String child_cap_unlock_in(int minutes) {
    return 'Unlocks in $minutes min';
  }

  @override
  String child_cap_minutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get child_cap_chip_go_today => 'Go to \"Today\"';

  @override
  String get child_cap_chip_earn => 'Focus for Sunlight';

  @override
  String get child_cap_btn_go_focus => 'Go Focus in \"Today\" 🌻';

  @override
  String get child_cap_ok => 'Got it';

  @override
  String get child_entry_pick_duration => 'How long will you focus?';

  @override
  String child_entry_cap_daily(int cap) {
    return 'Today\'s focus time is used up (daily limit $cap min) — see you tomorrow';
  }

  @override
  String child_entry_remaining_today(int cap, int minutes) {
    return 'You can still focus $minutes min today (daily limit $cap min)';
  }

  @override
  String get child_entry_free => 'Open';

  @override
  String get child_entry_custom => 'Custom';

  @override
  String get child_entry_custom_title => 'Custom duration (minutes)';

  @override
  String get child_entry_quota_empty => 'Daily quota used up';

  @override
  String child_entry_custom_hint_max(int max) {
    return 'Up to $max minutes';
  }

  @override
  String child_entry_custom_hint_capped(int max) {
    return 'Up to $max minutes (limited by today\'s quota)';
  }

  @override
  String get child_entry_options_title => 'Focus Options';

  @override
  String get child_entry_dnd => 'Block notifications (DND)';

  @override
  String get child_entry_dnd_hint => 'Mute messages and calls while focusing';

  @override
  String get child_entry_sound => 'Sound cues';

  @override
  String get child_entry_sound_hint => 'Play gentle sounds while focusing';

  @override
  String get child_entry_bgm => 'Background music';

  @override
  String get child_entry_bgm_hint => 'Loop soft music while focusing';

  @override
  String child_entry_minutes(int minutes) {
    return '$minutes min';
  }

  @override
  String child_entry_cap_snack(int cap) {
    return 'Daily focus limit reached ($cap min) — come back tomorrow';
  }

  @override
  String child_entry_cap_snack2(int cap) {
    return 'Today\'s focus time is used up (limit $cap min) — come back tomorrow';
  }

  @override
  String child_entry_remaining_snack(int minutes, int remaining) {
    return 'Only $remaining min left today, so this session is $minutes min';
  }

  @override
  String get child_focus_dnd_permission =>
      'Enable Do Not Disturb in system settings to block notifications';

  @override
  String get child_focus_exit_title => 'End now?';

  @override
  String get child_focus_exit_body =>
      'Your sunflower is still here with you. End this session now?';

  @override
  String get child_focus_exit_stay => 'Stay a bit';

  @override
  String get child_focus_exit_end => 'End';

  @override
  String get child_focus_debug_ff =>
      'Debug: fast-forward 5 min (eye-care trigger)';

  @override
  String get child_focus_free_label => 'Open focus';

  @override
  String get child_focus_session_label => 'This session';

  @override
  String get child_focus_dnd_off => 'DND is off; notifications may still come';

  @override
  String get child_focus_dnd_go => 'Turn on';

  @override
  String get child_focus_wait_back => 'Your sunflower is waiting for you';

  @override
  String get child_focus_paused => 'Paused';

  @override
  String get child_focus_buffer_eyecare => '🌻 Time for an eye break';

  @override
  String get child_focus_buffer_end => '🌻 Session finished';

  @override
  String get child_focus_buffer_resume_hint => 'Keep it up after the break';

  @override
  String get child_focus_buffer_eyecare2 => 'Time for an eye break';

  @override
  String get child_focus_cap_notice =>
      'Today\'s focus quota is used up — no more sunlight is collected. End anytime you feel tired';

  @override
  String get child_focus_no_touch =>
      'This screen is not interactive · Hold upright to end';

  @override
  String get child_shell_tab_today => 'Today';

  @override
  String get child_shell_tab_growth => 'Growth';

  @override
  String get child_shell_tab_garden => 'Garden';

  @override
  String get child_shell_tab_store => 'Store';

  @override
  String get child_shell_tab_mine => 'Mine';

  @override
  String get child_shell_verify_title => '🎉 Parent approved your redeem';

  @override
  String get child_shell_item_reward => 'Reward';

  @override
  String child_shell_item_cost(int sun) {
    return '-$sun sunlight';
  }

  @override
  String child_shell_verify_total(int total) {
    return 'A total of $total sunlight was deducted';
  }

  @override
  String get child_shell_reject_title => '🚫 Redeem not approved';

  @override
  String child_shell_reject_subtitle(String note) {
    return '($note)';
  }

  @override
  String get child_shell_reject_reason => 'Parent declined this request';

  @override
  String get child_shell_gift_title => '🎁 Sunshine from Mom & Dad!';

  @override
  String get child_shell_gift_item_name => 'Parent gift';

  @override
  String get child_shell_gift_footer =>
      'The sunshine is in your garden — go plant something!';

  @override
  String get child_shell_reject_footer =>
      'No sunlight was deducted; you can redeem another reward';

  @override
  String get child_shell_task_footer_capped =>
      'Daily growth rewards are capped; no sunlight this time';

  @override
  String child_shell_task_footer_partial(int capped, int total) {
    return 'Got $total sunlight ($capped item(s) hit the daily cap)';
  }

  @override
  String child_shell_task_footer(int total) {
    return 'Got $total sunlight';
  }

  @override
  String get child_shell_task_title => '🎉 Parent approved your task';

  @override
  String get child_shell_task_fallback => 'Growth task';

  @override
  String child_shell_task_item_sun(int sun) {
    return '+$sun sunlight';
  }

  @override
  String get child_shell_task_item_capped => 'Daily cap reached';

  @override
  String garden_settle_withered(Object parts) {
    return 'Flowers withered, rewards collected: $parts';
  }

  @override
  String shared_op_failed(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String garden_shovel_refund(int refund) {
    return 'Shoveled, $refund ☀ refunded';
  }

  @override
  String get garden_shovel_ok => 'Shoveled';

  @override
  String garden_collect_gift_prefix(Object body) {
    return 'Bloom gift: $body';
  }

  @override
  String get garden_cleared_weed => 'Weeds cleared';

  @override
  String get garden_cleared_pest => 'Pests cleared';

  @override
  String garden_reward_sunlight(int count) {
    return '+$count ☀ sunlight';
  }

  @override
  String garden_seed_decomposed(int count, String rarity) {
    return 'Duplicate $rarity seed turned into $count fragments';
  }

  @override
  String garden_reward_fragments(int count) {
    return '+$count fragments';
  }

  @override
  String garden_seed_dropped(String rarity) {
    return 'Dropped a $rarity seed';
  }

  @override
  String get garden_gift_default => 'Received a little gift~';

  @override
  String get garden_fx_sprout => 'Sprouted! 🌱';

  @override
  String get garden_fx_grow => 'Grown up! 🌿';

  @override
  String get garden_fx_bloom => 'In bloom! 🌻';

  @override
  String garden_need_more_sun(int missing) {
    return 'Not enough sunlight — $missing ☀ short. Go focus to earn more!';
  }

  @override
  String get garden_expand_title => 'Add a flower pot?';

  @override
  String get garden_row_expand_cost => 'Expansion';

  @override
  String get garden_row_balance => 'Current sunlight';

  @override
  String garden_expand_note(int count, int next) {
    return 'Garden capacity: $count → $next pots';
  }

  @override
  String get garden_confirm_deduct => 'OK, deduct';

  @override
  String get garden_batch_none_water => 'No plants to water today';

  @override
  String get garden_batch_none_fertilize => 'No plants to fertilize today';

  @override
  String get garden_batch_none_care => 'No plants need care';

  @override
  String get garden_row_total_cost => 'Total cost';

  @override
  String garden_water_note(int count, int cost) {
    return 'Water each of $count plants once ($cost ☀ each)';
  }

  @override
  String garden_fertilize_note(int count, int cost) {
    return 'Fertilize each of $count plants once ($cost ☀ each)';
  }

  @override
  String get garden_row_cleanup => 'Cleanup';

  @override
  String garden_cleanup_count(int count) {
    return '$count spot(s)';
  }

  @override
  String garden_care_note(int weed, int pest) {
    return 'Rewards as usual: weeds +$weed ☀ / pests +$pest ☀';
  }

  @override
  String get garden_oneclick_water_title => 'Water all at once?';

  @override
  String get garden_oneclick_fertilize_title => 'Fertilize all at once?';

  @override
  String get garden_oneclick_care_title => 'Care for all at once?';

  @override
  String garden_oneclick_water_ok(int count) {
    return 'Watered ×$count';
  }

  @override
  String garden_oneclick_fertilize_ok(int count) {
    return 'Fertilized ×$count';
  }

  @override
  String garden_oneclick_care_ok(int count) {
    return 'Cared ×$count';
  }

  @override
  String get garden_pick_plant_title => 'Choose a plant';

  @override
  String get garden_cost_free => 'Free';

  @override
  String get garden_cost_seed => 'Seed';

  @override
  String garden_cost_sunlight(int count) {
    return '$count sunlight';
  }

  @override
  String get garden_reason_no_sun => 'Not enough sunlight';

  @override
  String garden_cost_fragments(int count) {
    return '$count fragments';
  }

  @override
  String garden_reason_no_fragments(int count) {
    return 'Not enough fragments ($count left)';
  }

  @override
  String get garden_row_plant => 'Planting';

  @override
  String garden_row_use_seed(String rarity) {
    return 'Use $rarity seed';
  }

  @override
  String garden_seed_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seeds',
      one: '$count seed',
    );
    return '$_temp0';
  }

  @override
  String get garden_row_seed_balance => 'Current seeds';

  @override
  String garden_seed_remaining(int count) {
    return '$count seeds left after planting';
  }

  @override
  String get garden_row_use_fragments => 'Use fragments';

  @override
  String garden_fragment_cost(int count) {
    return '−$count';
  }

  @override
  String get garden_row_fragment_balance => 'Current fragments';

  @override
  String garden_fragment_count(int count) {
    return '$count';
  }

  @override
  String garden_fragment_remaining(int count) {
    return '$count fragments left after planting';
  }

  @override
  String garden_sun_remaining(int count) {
    return '$count ☀ left after planting';
  }

  @override
  String get garden_unknown_plant => 'Unknown plant';

  @override
  String garden_load_failed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get garden_title => 'My Garden';

  @override
  String get garden_refresh_tooltip => 'Refresh growth';

  @override
  String get garden_rarity_common => 'Common';

  @override
  String get garden_rarity_premium => 'Premium';

  @override
  String get garden_flip_back => 'Tap to flip back';

  @override
  String get garden_action_water => 'Water all';

  @override
  String get garden_action_fertilize => 'Fertilize all';

  @override
  String get garden_action_care => 'Care all';

  @override
  String get garden_oneclick_title => 'One-tap care';

  @override
  String get garden_help_sheet_title => 'Fragments & Seeds';

  @override
  String get garden_help_fragment_title => 'Plant fragments';

  @override
  String get garden_help_fragment_use =>
      'Pays for planting instead of sunlight (premium plants need fragments).';

  @override
  String get garden_help_fragment_how => 'Randomly dropped in bloom rewards.';

  @override
  String get garden_help_common_seed_title => 'Common seed';

  @override
  String get garden_help_common_seed_use =>
      'Plants a common flower for free; used first, no sunlight cost.';

  @override
  String get garden_help_common_seed_how =>
      'Rarely dropped when common plants bloom; duplicates turn into fragments.';

  @override
  String get garden_help_premium_seed_title => 'Premium seed';

  @override
  String get garden_help_premium_seed_use =>
      'Plants a premium flower for free; used first, no fragment cost.';

  @override
  String get garden_help_premium_seed_how =>
      'Rarely dropped when premium plants bloom; duplicates turn into fragments.';

  @override
  String garden_help_use_prefix(Object text) {
    return 'Use: $text';
  }

  @override
  String garden_help_how_prefix(Object text) {
    return 'How to get: $text';
  }

  @override
  String get shared_got_it => 'Got it';

  @override
  String shared_load_failed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get shared_retry => 'Retry';

  @override
  String get shared_refresh => 'Refresh';

  @override
  String get shared_cancel => 'Cancel';

  @override
  String get shared_no_sunlight => 'Not enough sunlight';

  @override
  String get shared_week_quota_full => 'Weekly quota full';

  @override
  String get shared_redeem => 'Redeem';

  @override
  String get store_title => 'Sunlight Store';

  @override
  String get store_empty_hint =>
      'No rewards yet — ask a parent to add reward templates first';

  @override
  String get store_confirm_title => 'Confirm redemption?';

  @override
  String get store_row_item => 'Item';

  @override
  String get store_row_cost => 'Cost';

  @override
  String get store_row_available => 'Available';

  @override
  String get store_warning_redeem =>
      'A parent must approve before sunlight is deducted.';

  @override
  String get store_confirm_ok => 'Confirm';

  @override
  String get store_confirm_think => 'Let me think';

  @override
  String get store_result_verified => 'Redeemed! Sunlight deducted';

  @override
  String get store_result_cooldown => 'Already claimed this week';

  @override
  String get store_result_no_balance =>
      'Not enough sunlight — go earn more by focusing';

  @override
  String get store_result_pool_full =>
      'Weekly quota is full — come back next week';

  @override
  String get store_pending_feedback =>
      'Submitted! Waiting for parent approval~';

  @override
  String store_pending_pill(int count) {
    return 'Pending $count';
  }

  @override
  String get store_celebration_text => 'Redeemed!\nSunlight deducted';

  @override
  String task_checkin_failed(Object error) {
    return 'Check-in failed: $error';
  }

  @override
  String get task_feedback_pending =>
      'Told your parents! Sunlight comes after they approve 🌻';

  @override
  String task_feedback_cap(int cap) {
    return 'Daily growth rewards maxed out ($cap) — come back tomorrow';
  }

  @override
  String task_feedback_capped(Object granted) {
    return 'Awesome! +$granted sunlight (daily growth rewards capped, only $granted credited)';
  }

  @override
  String task_feedback_granted(Object granted) {
    return 'Awesome! +$granted sunlight';
  }

  @override
  String get task_perfect_title => '🌻 All growth tasks done today!';

  @override
  String get task_perfect_footer =>
      'You finished every growth task today and earned a \"Perfect Day\" badge!';

  @override
  String get task_perfect_ok => 'Awesome!';

  @override
  String get task_empty_hint => 'No growth tasks today — go play 🌻';

  @override
  String get task_progress_title => 'Today\'s Growth';

  @override
  String task_weekly_more(int count) {
    return '· Plus $count weekly item(s)';
  }

  @override
  String get task_badge_daily => 'Daily';

  @override
  String get task_badge_weekly => 'Weekly';

  @override
  String task_info_focus(Object subject, int reward) {
    return '$subject · focus · +$reward ☀';
  }

  @override
  String task_info_plain(Object subject, int reward) {
    return '$subject · +$reward ☀';
  }

  @override
  String get task_status_waiting => 'Waiting for approval';

  @override
  String get task_status_done_focus => 'Done';

  @override
  String get task_status_done => 'Done';

  @override
  String child_task_partial_note(int minutes, int percent) {
    return '$minutes min · $percent% done';
  }

  @override
  String get task_action_do => 'I did';

  @override
  String get task_action_do2 => 'it!';

  @override
  String get task_action_focus => 'Focus';

  @override
  String task_focus_minutes(int count) {
    return '$count min';
  }

  @override
  String profile_balance_line(int count) {
    return 'Sunlight: $count';
  }

  @override
  String get profile_source_label => 'History';

  @override
  String get profile_achievements_title => 'Achievements';

  @override
  String get profile_stat_focus_minutes => 'Total focus time';

  @override
  String profile_value_minutes(int count) {
    return '$count min';
  }

  @override
  String get profile_stat_sessions => 'Total focus sessions';

  @override
  String profile_value_times(int count) {
    return '$count times';
  }

  @override
  String get profile_stat_valid_days => 'Total valid focus days';

  @override
  String profile_value_days(int count) {
    return '$count days';
  }

  @override
  String get profile_stat_checkins => 'Total task check-ins';

  @override
  String get profile_stat_bloomed => 'Total bloomed plants';

  @override
  String profile_value_plants(int count) {
    return '$count plants';
  }

  @override
  String get profile_stat_eyecare => 'Total eye-care breaks';

  @override
  String get hist_title => 'Sunlight History';

  @override
  String get hist_empty_hint => 'No sunlight records yet 🌻';

  @override
  String get hist_balance_label => 'Current sunlight';

  @override
  String get hist_other => 'Other';

  @override
  String hist_subtitle(Object time, int balance) {
    return '$time · balance $balance ☀';
  }

  @override
  String get card_stage_seed => 'Seed';

  @override
  String get card_stage_sprout => 'Sprout';

  @override
  String get card_stage_adult => 'Grown';

  @override
  String get card_status_growing => 'Growing';

  @override
  String get card_status_bloomed => 'In bloom 🌻';

  @override
  String get card_status_wilting => 'Wilting (save it!)';

  @override
  String get card_status_dead => 'Withered';

  @override
  String get card_mood_happy => '😊 I focused today, I\'m happy';

  @override
  String get card_mood_calm => '😌 Feeling fine';

  @override
  String get card_mood_thirsty => '🥵 A bit thirsty — water me!';

  @override
  String get card_hint_bloomed =>
      'In bloom 🌻 daily care keeps tomorrow\'s dew sunlight full';

  @override
  String get card_hint_next_soon => 'About to reach the next stage…';

  @override
  String card_hint_progress(int percent) {
    return '$percent% through this stage';
  }

  @override
  String card_hint_grow_days(int days) {
    return 'Care daily — about $days more days to grow';
  }

  @override
  String card_hint_bloom_left(Object days) {
    return '$days days of bloom left';
  }

  @override
  String get card_action_shovel => 'Remove';

  @override
  String get card_action_clear => 'Clear away';

  @override
  String get card_action_water => 'Water';

  @override
  String card_action_water_gain(Object gain) {
    return 'Water +$gain%';
  }

  @override
  String get card_action_fertilize => 'Fertilize';

  @override
  String card_action_fertilize_gain(Object gain) {
    return 'Fertilize +$gain%';
  }

  @override
  String card_quota_left(int water, int waterMax, int fert, int fertMax) {
    return 'Today left: water $water/$waterMax · fertilize $fert/$fertMax';
  }

  @override
  String get card_wilt_easy => 'One watering revives it';

  @override
  String card_wilt_hard(int water, int fert) {
    return 'Needs $water waterings + $fert fertilizings to revive';
  }

  @override
  String care_shovel_title(Object name) {
    return 'Remove \"$name\"?';
  }

  @override
  String get care_this_plant => 'this plant';

  @override
  String get care_shovel_warning => 'This plant will be gone after removal.';

  @override
  String get care_row_refund => 'Planting refund';

  @override
  String get care_note_no_refund_water => 'Care sunlight is not refunded';

  @override
  String get care_note_no_refund => 'No sunlight refunded this time';

  @override
  String get care_confirm_shovel => 'Remove it';

  @override
  String get care_gone_hint => 'This plant is no longer in the garden';

  @override
  String get care_footer_hint =>
      'Plants also grow naturally over time; daily care helps them bloom sooner 🌻\nAfter blooming, water or fertilize once a day to keep dew sunlight full 🌻\n(Missed dew still drops, just at half — never zero)';

  @override
  String plant_confirm_title(Object name) {
    return 'Plant the $name?';
  }

  @override
  String get plant_confirm_ok => 'Plant it';

  @override
  String pot_tooltip_weed(int count) {
    return 'Weeds! Tap to clear +$count ☀';
  }

  @override
  String pot_tooltip_pest(int count) {
    return 'Pests! Tap to clear +$count ☀';
  }

  @override
  String pot_label_bloomed(Object name) {
    return '$name · bloom';
  }

  @override
  String pot_label_wilting(Object name) {
    return '$name · save me';
  }

  @override
  String pot_label_dead(Object name) {
    return '$name · withered';
  }

  @override
  String get pot_label_locked => 'Locked';

  @override
  String pot_label_expand(int cost) {
    return 'Add pot · $cost☀';
  }

  @override
  String pot_label_shortfall(int count) {
    return 'Need $count☀ more';
  }

  @override
  String get ghelp_title => 'How to play';

  @override
  String get ghelp_earn_title => 'Earning sunlight';

  @override
  String ghelp_earn_detail(int perMinute, int eyeCare) {
    return 'Focus during the day to earn sunlight: +$perMinute ☀ per minute;\nfinish a growth task check-in for extra sunlight based on focus time;\ncomplete an eye-care break for +$eyeCare ☀.';
  }

  @override
  String get ghelp_use_title => 'Spending sunlight';

  @override
  String ghelp_use_detail(
      int sunCost, int fragmentCost, int waterCost, int fertCost) {
    return 'Plant in the garden (tap an empty pot): common plants cost $sunCost ☀ or $fragmentCost fragments;\nwater plants from $waterCost ☀/time, fertilize from $fertCost ☀/time;\ndig up a plant you don\'t want to get half the sunlight back;\nor redeem rewards you like in the Store.';
  }

  @override
  String get ghelp_grow_title => 'How plants grow';

  @override
  String ghelp_grow_detail(int waterGain, int fertGain, int waterMax,
      int fertMax, int interval, int bloomDays) {
    return 'Plants grow on their own over time; watering +$waterGain% and fertilizing +$fertGain% speeds it up\n(re-growth after blooming gives less — check the numbers on the buttons;\nup to $waterMax waterings and $fertMax fertilizings a day, $interval minutes apart);\nwhen progress is full it blooms; after $bloomDays days in bloom it fades, then can bloom again 🌻';
  }

  @override
  String get ghelp_wilt_title => 'Keep plants from wilting';

  @override
  String ghelp_wilt_detail(
      int wiltDays, int deathDays, int hardDays, int hardWater, int hardFert) {
    return 'Watering or fertilizing refreshes the timer; $wiltDays days without water means wilting,\nand $deathDays more days means the plant dies. If it wilts, don\'t worry:\nwithin $hardDays days, watering brings it back; later it takes $hardWater waterings\nand $hardFert fertilizings. Come visit often 🌱';
  }

  @override
  String get ghelp_task_title => 'Task check-ins & parent approval';

  @override
  String get ghelp_task_detail =>
      'There are two kinds of growth tasks:\n\"Start focus\" tasks settle automatically when the goal is met;\nfinishing early still counts — sunlight is given for the time you actually focused;\n\"I did it\" tasks are recorded as \"waiting for parent approval\" —\nsunlight arrives only after a parent approves.';

  @override
  String get ghelp_bloom_title => 'Blooming surprises';

  @override
  String ghelp_bloom_detail(int instantSun) {
    return 'Blooming brings surprises: at least +$instantSun ☀, plus a chance of\nbonus sunlight, rare fragments, or seeds of the same species;\nduring bloom a morning-dew reward drops every morning —\ncare for the plant the day before and the reward is fuller. Come collect 🌸';
  }

  @override
  String get ghelp_weed_title => 'Weeds & pests';

  @override
  String ghelp_weed_detail(int weedReward, int pestReward) {
    return 'Weeds and little pests show up now and then — even empty pots can grow them. Tap them to clear:\n+$weedReward ☀ for a weed, +$pestReward ☀ for a pest.';
  }

  @override
  String get ghelp_seed_title => 'Seeds & fragments';

  @override
  String ghelp_seed_detail(int fragmentPremium) {
    return 'Blooming also drops seeds and rare fragments of the same species:\nseeds can be used as payment when planting; duplicates turn into fragments;\nelite plants need $fragmentPremium fragments to plant.';
  }

  @override
  String get ghelp_capacity_title => 'Garden capacity';

  @override
  String ghelp_capacity_detail(int capacity, int max) {
    return '$capacity / $max pots';
  }

  @override
  String get ghelp_expand_title => 'Expand';

  @override
  String ghelp_expand_detail(int cost, int max) {
    return 'Tap the \"+\" cell and pay $cost ☀ to add a pot (max $max pots).';
  }

  @override
  String get prd_pending_reminder =>
      'Your sunlight reward is still waiting for approval~';

  @override
  String get prd_avatar_locked_hint =>
      'Plant this flower to unlock it as an avatar';

  @override
  String get prd_eyecare_not_skippable => 'Can\'t skip — be kind to your eyes';

  @override
  String get prd_eyecare_finish => 'Skip the eye break';

  @override
  String get prd_eyecare_early_title => 'End the break early?';

  @override
  String get prd_eyecare_early_body =>
      'The eye break isn\'t finished — ending now means no sunlight reward. Resting your eyes makes them sparkle! Hang in there!';

  @override
  String get prd_eyecare_early_stay => 'Keep resting';

  @override
  String get prd_eyecare_early_quit => 'End it';

  @override
  String get prd_level_locked_title => 'Locked';

  @override
  String get prd_level_detail_ok => 'Got it';

  @override
  String get prd_premium_upsell_hint => 'Upgrade to unlock this feature';

  @override
  String get fx_level_up_title => 'New title unlocked!';

  @override
  String get fx_level_up_level_title => 'Level up!';

  @override
  String fx_level_up_multi(int n) {
    return '$n titles in a row!';
  }

  @override
  String fx_level_up_level_multi(int n) {
    return '$n levels in a row!';
  }

  @override
  String fx_level_up_perk(Object text) {
    return 'Title perk: $text';
  }

  @override
  String get fx_level_up_perk_locked => ' · 🔒 paid unlock';

  @override
  String get shared_edit => 'Edit';

  @override
  String get shared_delete => 'Delete';

  @override
  String get parent_home_title => 'Parent Hub';

  @override
  String get parent_home_back_tooltip => 'Back to kid zone';

  @override
  String get parent_home_tab_today => 'Today';

  @override
  String get parent_home_tab_reward => 'Rewards';

  @override
  String get parent_home_tab_growth => 'Growth';

  @override
  String get parent_home_tab_history => 'Records';

  @override
  String get parent_home_tab_settings => 'Settings';

  @override
  String get parent_login_enter_pin => 'Enter parent PIN';

  @override
  String get parent_login_setup_pin => 'First time here — set a parent PIN';

  @override
  String get parent_login_btn_enter => 'Enter';

  @override
  String get parent_login_btn_setup => 'Set PIN & enter';

  @override
  String get parent_login_err_short => 'PIN must be at least 4 digits';

  @override
  String get parent_login_err_wrong => 'Incorrect PIN';

  @override
  String get parent_delete_title => 'Delete Data';

  @override
  String get parent_delete_right_title => 'Data deletion right (§10.4 C5)';

  @override
  String get parent_delete_right_body =>
      'You have the right to delete all local data. Once deleted, progress and settings cannot be recovered.';

  @override
  String get parent_delete_dlg_title => 'Delete all local data?';

  @override
  String get parent_delete_dlg_body =>
      'This permanently deletes focus records, the sunlight ledger, plants, growth items, reward templates, the parent PIN and all local settings. It cannot be undone.\n\nTip: export a memoir first (export arrives in v2).';

  @override
  String get parent_delete_btn_ok => 'Delete';

  @override
  String get parent_delete_btn_export => 'Export memoir (coming in v2)';

  @override
  String get parent_delete_export_snack =>
      'Export arrives in v2 — take screenshots for now';

  @override
  String get parent_delete_btn_all => 'Delete all local data';

  @override
  String get parent_delete_btn_deleting => 'Deleting…';

  @override
  String get parent_delete_done_snack => 'All local data deleted';

  @override
  String parent_delete_fail_snack(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get parent_today_unknown_reward => 'Unknown reward';

  @override
  String get parent_today_empty => 'Nothing waiting 🎉';

  @override
  String get parent_today_pending_title => 'Items to confirm';

  @override
  String parent_today_count(int count) {
    return '$count items';
  }

  @override
  String get parent_today_deleted_task => '(deleted growth item)';

  @override
  String parent_today_submitted_at(Object time) {
    return 'Submitted $time';
  }

  @override
  String parent_today_should_grant(String sun) {
    return 'Grant $sun ☀';
  }

  @override
  String get parent_today_btn_confirm => 'Confirm';

  @override
  String get parent_today_btn_reject => 'Reject';

  @override
  String get parent_today_reject_title => 'Reject this item?';

  @override
  String parent_today_reject_body(String name) {
    return 'No sunlight will be granted for \"$name\".';
  }

  @override
  String get parent_today_reject_reason => 'Reason (optional)';

  @override
  String get parent_today_reject_ok => 'Reject';

  @override
  String parent_today_confirm_ok_snack(String sun, String capped) {
    return 'Confirmed, +$sun ☀ 🌻$capped';
  }

  @override
  String parent_today_capped_note(String sun) {
    return ' (daily cap reached — only $sun ☀ credited)';
  }

  @override
  String parent_today_confirm_fail_snack(Object error) {
    return 'Confirm failed: $error';
  }

  @override
  String get parent_today_rejected_snack => 'Rejected 🌞 No sunlight granted';

  @override
  String parent_today_reject_fail_snack(Object error) {
    return 'Reject failed: $error';
  }

  @override
  String get parent_today_debug_cap_title => '🧪 Debug: skip 30-min limit';

  @override
  String get parent_today_debug_cap_subtitle =>
      'On by default while debugging (no screen-time lock); turning off restores the limit. Debug builds only.';

  @override
  String get parent_today_debug_cap_on_snack => '30-min limit skipped (debug)';

  @override
  String get parent_today_debug_cap_off_snack =>
      '30-min screen-time limit restored';

  @override
  String get parent_today_debug_save_fail_snack => 'Save failed, try again';

  @override
  String get parent_verify_cat_self_service => 'Self-service';

  @override
  String get parent_verify_cat_parent_handled => 'Parent-handled';

  @override
  String parent_verify_cost(int cost) {
    return '$cost ☀';
  }

  @override
  String parent_verify_meta(String category, String time) {
    return '$category · requested $time';
  }

  @override
  String parent_verify_queue_note(Object pos) {
    return 'Queue #$pos · auto-releases next month';
  }

  @override
  String get parent_verify_confirm_title => 'Confirm redemption?';

  @override
  String parent_verify_confirm_body(String name, int cost) {
    return 'Redeem \"$name\" for $cost ☀?\nSunlight is deducted from your kid\'s balance immediately and cannot be undone.';
  }

  @override
  String get parent_verify_confirm_ok => 'Confirm';

  @override
  String get parent_verify_reject_title => 'Reject this request?';

  @override
  String parent_verify_reject_body(String name, int cost) {
    return 'Rejecting \"$name\" ($cost ☀) means no redemption.\nSunlight was never deducted while pending, so your kid\'s balance is unaffected.\nThis cannot be undone.';
  }

  @override
  String get parent_verify_reject_ok => 'Reject';

  @override
  String get parent_verify_verified_snack => 'Redeemed 🎉 Sunlight deducted';

  @override
  String parent_verify_verify_fail_snack(Object error) {
    return 'Redeem failed: $error';
  }

  @override
  String get parent_verify_rejected_snack =>
      'Rejected 🌞 Sunlight not deducted';

  @override
  String parent_verify_reject_fail_snack(Object error) {
    return 'Reject failed: $error';
  }

  @override
  String get parent_verify_release_title => 'Release now?';

  @override
  String parent_verify_release_body(String name, int cost) {
    return 'Release \"$name\" for $cost ☀ right now?\nThis skips the queue wait and deducts sunlight immediately.';
  }

  @override
  String get parent_verify_release_ok => 'Release now';

  @override
  String get parent_verify_released_snack => 'Released 🎉 Sunlight deducted';

  @override
  String parent_verify_release_state_fail_snack(Object error) {
    return 'Can\'t release yet: $error';
  }

  @override
  String parent_verify_release_fail_snack(Object error) {
    return 'Release failed: $error';
  }

  @override
  String get parent_task_edit_title_new => 'New growth item';

  @override
  String get parent_task_edit_title_edit => 'Edit growth item';

  @override
  String get parent_task_edit_name_label => 'Item name';

  @override
  String get parent_task_edit_subject_label => 'Subject';

  @override
  String get parent_task_edit_subject_general => 'General';

  @override
  String get parent_task_edit_subject_chinese => 'Chinese';

  @override
  String get parent_task_edit_subject_math => 'Math';

  @override
  String get parent_task_edit_subject_english => 'English';

  @override
  String get parent_task_edit_subject_custom => 'Custom…';

  @override
  String get parent_task_edit_custom_label => 'Custom subject name';

  @override
  String get parent_task_edit_custom_hint =>
      'e.g. Science / Calligraphy / Coding';

  @override
  String get parent_task_edit_category_label => 'Category';

  @override
  String get parent_task_edit_link_title => 'Focus-linked (auto settle)';

  @override
  String get parent_task_edit_link_subtitle =>
      'When on, tapping \"Start focus\" on this item settles and grants sunlight automatically — no manual check-in needed.';

  @override
  String get parent_task_edit_min_focus_label => 'Min focus';

  @override
  String parent_task_edit_minutes(int minutes) {
    return '$minutes min';
  }

  @override
  String parent_task_edit_reward_fixed(int minutes, int cap) {
    return 'Fixed reward = $minutes min × 40% = $cap ☀ (no adjustment needed)';
  }

  @override
  String get parent_task_edit_reward_label => 'Sunlight reward';

  @override
  String parent_task_edit_reward_slider(int reward) {
    return '$reward ☀';
  }

  @override
  String parent_task_edit_reward_range(int min, int max, int def) {
    return 'Range $min–$max ☀ (default $def)';
  }

  @override
  String get parent_task_edit_repeat_label => 'Repeat';

  @override
  String get parent_task_edit_repeat_none => 'Never';

  @override
  String get parent_task_edit_repeat_daily => 'Daily';

  @override
  String get parent_task_edit_repeat_weekly => 'Weekly';

  @override
  String get parent_task_edit_err_name => 'Please enter a name';

  @override
  String parent_task_edit_err_reward(int min, int max) {
    return 'Reward must be $min–$max';
  }

  @override
  String get parent_task_edit_err_subject => 'Please enter the custom subject';

  @override
  String parent_task_edit_err_save(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get parent_task_edit_btn_save => 'Save';

  @override
  String get parent_task_config_title => 'Growth Setup';

  @override
  String get parent_task_config_list_title => 'Growth tasks';

  @override
  String get parent_task_config_empty =>
      'No items yet — tap \"New growth item\" to add one';

  @override
  String get parent_task_config_delete_title => 'Delete this item?';

  @override
  String parent_task_config_delete_body(String name) {
    return 'Delete \"$name\"? Existing check-in records will be kept.';
  }

  @override
  String parent_task_config_focus_pill(int minutes) {
    return 'Focus $minutes min';
  }

  @override
  String get parent_reward_templates_title => 'Reward templates';

  @override
  String get parent_reward_btn_add => 'Add reward';

  @override
  String parent_reward_quota_hint(String reason) {
    return '$reason. Delete extras to add more';
  }

  @override
  String get parent_reward_edit_hint =>
      'Tap an item to edit name/price/type; the trash icon deletes. Changes sync to your kid\'s store.';

  @override
  String get parent_reward_empty =>
      'No templates yet — tap \"Add reward\" to create one';

  @override
  String get parent_reward_delete_title => 'Delete reward';

  @override
  String parent_reward_delete_body(String name) {
    return 'Delete \"$name\"? It will disappear from your kid\'s store.';
  }

  @override
  String get parent_reward_edit_title_new => 'New reward';

  @override
  String get parent_reward_edit_title_edit => 'Edit reward';

  @override
  String get parent_reward_name_label => 'Reward name';

  @override
  String get parent_reward_err_required => 'Required';

  @override
  String get parent_reward_cat_self_full => 'Self-service (TV/tablet time)';

  @override
  String get parent_reward_content_label => 'Content type';

  @override
  String get parent_reward_cost_label => 'Sunlight price';

  @override
  String get parent_reward_err_positive => 'Enter a positive whole number';

  @override
  String get parent_reward_freq_label => 'Weekly redemption limit';

  @override
  String get parent_reward_err_nonneg => 'Enter a non-negative whole number';

  @override
  String get parent_reward_cooldown_label => 'Cooldown rule';

  @override
  String get parent_reward_cooldown_none => 'None';

  @override
  String get parent_reward_cooldown_weekly => 'Weekly limit';

  @override
  String get parent_reward_cooldown_monthly => 'Monthly limit';

  @override
  String get parent_reward_pool_title => 'This week\'s sunlight budget';

  @override
  String get parent_reward_pool_unit => '☀';

  @override
  String parent_reward_pool_used_line(int used, int budget) {
    return 'Used $used of $budget ☀';
  }

  @override
  String parent_reward_pool_unlimited_line(int used) {
    return 'No weekly cap — $used ☀ used (redemptions only bounded by balance)';
  }

  @override
  String parent_reward_pool_default_note(int low, int mid, String high) {
    return 'Weekly default limits — lower grade $low☀ · middle $mid☀ · upper $high (redemptions only bounded by balance)';
  }

  @override
  String parent_reward_pool_load_failed(Object error) {
    return 'Failed to load weekly pool: $error';
  }

  @override
  String get parent_settings_section_screentime => 'Screen time & routines';

  @override
  String get parent_settings_switch_quiet => 'Do not disturb';

  @override
  String get parent_settings_night_title => 'Night boundary';

  @override
  String parent_settings_night_subtitle(String time) {
    return 'Night lock takes effect from $time';
  }

  @override
  String get parent_settings_daily_focus_cap => 'Daily focus limit (min)';

  @override
  String get parent_settings_daily_app_cap => 'Daily garden & store time (min)';

  @override
  String get parent_settings_rest_after => 'Rest after N focus sessions';

  @override
  String get parent_settings_rest_minutes => 'Break length (min)';

  @override
  String get parent_settings_section_eyecare => 'Eye-care breaks';

  @override
  String get parent_settings_switch_eyecare => 'Eye-care reminder';

  @override
  String get parent_settings_eyecare_subtitle =>
      'An eye-care card pops up after enough focus time to rest little eyes (fixed 60 s)';

  @override
  String get parent_settings_eyecare_interval =>
      'Eye-care interval (every N min)';

  @override
  String get parent_settings_switch_eyecare_skip => 'Allow skipping eye-care';

  @override
  String get parent_settings_eyecare_skip_subtitle =>
      'When off, kids must finish the break — the skip button does nothing';

  @override
  String get parent_settings_section_sound => 'Sound & ambience';

  @override
  String get parent_settings_switch_sound => 'Sound effects';

  @override
  String get parent_settings_switch_bgm => 'Background music';

  @override
  String get parent_settings_switch_dark => 'Dark theme';

  @override
  String get parent_settings_section_lock => 'Parent lock & gifts';

  @override
  String get parent_settings_reset_pin => 'Reset parent PIN';

  @override
  String get parent_settings_grant_title => 'Gift sunlight';

  @override
  String parent_settings_grant_subtitle(Object daily, Object monthly) {
    return 'Daily cap $daily · monthly $monthly';
  }

  @override
  String get parent_settings_section_data => 'Data & privacy';

  @override
  String get parent_settings_entry_delete => 'Delete data';

  @override
  String get parent_settings_entry_delete_sub =>
      'Delete all local data (§10.4 C5)';

  @override
  String get parent_settings_section_debug => 'Debug (debug builds only)';

  @override
  String get parent_settings_pin_dlg_title => 'Reset parent PIN';

  @override
  String get parent_settings_pin_dlg_old => 'Current PIN';

  @override
  String get parent_settings_pin_dlg_new => 'New PIN (≥4 digits)';

  @override
  String get parent_settings_pin_dlg_ok => 'Reset';

  @override
  String get parent_settings_pin_too_short_snack =>
      'New PIN must be at least 4 digits';

  @override
  String get parent_settings_pin_wrong_snack => 'Current PIN is incorrect';

  @override
  String get parent_settings_pin_ok_snack => 'PIN has been reset';

  @override
  String get parent_settings_gift_dlg_title => 'Gift sunlight';

  @override
  String parent_settings_gift_daily_line(int given, int daily, int remain) {
    return 'Today gifted $given/$daily ☀ — $remain ☀ left';
  }

  @override
  String parent_settings_gift_monthly_line(int given, int monthly, int remain) {
    return 'This month gifted $given/$monthly ☀ — $remain ☀ left';
  }

  @override
  String get parent_settings_gift_amount_label => 'Amount';

  @override
  String get parent_settings_gift_err_positive => 'Enter a positive number';

  @override
  String parent_settings_gift_err_over(int max, int day, int month) {
    return 'Up to $max ☀ (today $day / month $month left)';
  }

  @override
  String get parent_settings_gift_btn => 'Gift';

  @override
  String parent_settings_gift_daily_cap_snack(int daily) {
    return 'Daily gift cap reached ($daily ☀/day) — come back tomorrow';
  }

  @override
  String parent_settings_gift_monthly_cap_snack(int monthly) {
    return 'Monthly gift cap reached ($monthly ☀/month)';
  }

  @override
  String parent_settings_gift_over_snack(int remain) {
    return 'Over the gift cap — nothing gifted ($remain ☀ left today)';
  }

  @override
  String parent_settings_gift_ok_snack(int amount, int remain) {
    return 'Gifted $amount ☀ to your kid ($remain ☀ left today)';
  }

  @override
  String get parent_settings_debug_member_title => 'Member mode (debug only)';

  @override
  String get parent_settings_debug_member_subtitle =>
      'Unlocks all premium features; resets after app restart';

  @override
  String get parent_profile_tier_low => 'Lower grade · age ≤8';

  @override
  String get parent_profile_tier_mid => 'Middle grade · age 9–12';

  @override
  String get parent_profile_tier_high => 'Upper grade · age ≥13';

  @override
  String get parent_profile_menu_edit => 'Edit';

  @override
  String get parent_profile_menu_delete => 'Delete';

  @override
  String get parent_profile_menu_create => 'New child';

  @override
  String parent_profile_toast_switched(String name) {
    return 'Switched to \"$name\"';
  }

  @override
  String parent_profile_toast_added(String name) {
    return 'Added \"$name\"';
  }

  @override
  String parent_profile_toast_updated(String name) {
    return 'Updated \"$name\"';
  }

  @override
  String parent_profile_toast_deleted(String name) {
    return 'Deleted \"$name\"';
  }

  @override
  String parent_profile_max_toast(int count) {
    return 'Up to $count child profiles';
  }

  @override
  String get parent_profile_min_toast => 'Keep at least one child profile';

  @override
  String get parent_profile_create_title => 'New child';

  @override
  String get parent_profile_edit_title => 'Edit child';

  @override
  String get parent_profile_name_label => 'Child\'s name';

  @override
  String get parent_profile_name_hint => 'e.g. Little Sunflower';

  @override
  String get parent_profile_btn_create => 'Create';

  @override
  String parent_profile_delete_title(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get parent_profile_delete_body =>
      'The profile and its settings will be removed and cannot be restored.';

  @override
  String get parent_profile_pin_label => 'Parent PIN';

  @override
  String get parent_profile_pin_err_empty => 'Enter the parent PIN';

  @override
  String get parent_profile_pin_err_wrong => 'Wrong PIN — try again';

  @override
  String get parent_history_seg_report => 'Focus report';

  @override
  String get parent_history_seg_activity => 'Tasks & rewards';

  @override
  String get parent_hist_section_tasks => 'Growth task completions';

  @override
  String parent_hist_task_tail(int count) {
    return '$count in total';
  }

  @override
  String get parent_hist_empty_tasks => 'No completions in this period';

  @override
  String get parent_hist_section_rewards => 'Reward redemptions';

  @override
  String parent_hist_reward_tail(int count, int cost) {
    return '$count in total · $cost ☀ spent';
  }

  @override
  String get parent_hist_empty_rewards => 'No redemptions in this period';

  @override
  String get parent_hist_deleted_task => '(deleted growth item)';

  @override
  String get parent_hist_deleted_reward => '(deleted reward)';

  @override
  String parent_hist_done_badge(int count) {
    return 'Done ×$count';
  }

  @override
  String parent_hist_redeem_badge(int count) {
    return 'Redeemed ×$count';
  }

  @override
  String parent_verify_partial_badge(int percent) {
    return 'Partial $percent%';
  }

  @override
  String parent_hist_range_multi(String first, String last) {
    return 'First $first – latest $last';
  }

  @override
  String parent_hist_cost_line(String range, int cost) {
    return '$range · $cost ☀ spent';
  }

  @override
  String get parent_hist_summary_done => 'Items completed';

  @override
  String get parent_hist_summary_redeem => 'Rewards redeemed';

  @override
  String get parent_hist_summary_cost => 'Sunlight spent';

  @override
  String get parent_report_error_hint =>
      'Couldn\'t build the report — pull down to retry';

  @override
  String get parent_report_period_day => 'D';

  @override
  String get parent_report_period_week => 'W';

  @override
  String get parent_report_period_month => 'M';

  @override
  String get parent_report_period_year => 'Y';

  @override
  String get parent_report_prev_tooltip => 'Previous period';

  @override
  String get parent_report_next_tooltip => 'Next period';

  @override
  String get parent_report_hero_title => 'Focus this period';

  @override
  String parent_report_minutes(int minutes) {
    return '$minutes min';
  }

  @override
  String parent_report_valid_days(int days) {
    return '$days valid focus days';
  }

  @override
  String parent_report_avg_daily(int minutes) {
    return '$minutes min/day average';
  }

  @override
  String get parent_report_trend_day => 'Last 7 days';

  @override
  String get parent_report_trend_week => 'This week';

  @override
  String get parent_report_trend_month => 'This month (by week)';

  @override
  String get parent_report_trend_year => 'This year (by month)';

  @override
  String get parent_report_stability_title => 'Focus stability · last 4 weeks';

  @override
  String get parent_report_heatmap_title => 'Focus heatmap · last year';

  @override
  String get parent_report_eyecare_title => 'Eye-care stats';

  @override
  String get parent_report_eyecare_loading => 'Loading eye-care stats…';

  @override
  String get parent_report_trend_empty =>
      'Nothing here yet. Complete one 15-minute focus session with your kid and this will light up.';

  @override
  String parent_report_label_today(String date) {
    return 'Today · $date';
  }

  @override
  String parent_report_label_yesterday(String date) {
    return 'Yesterday · $date';
  }

  @override
  String parent_report_label_range(String start, String end) {
    return '$start – $end';
  }

  @override
  String parent_report_label_month(int year, int month) {
    return '$month/$year';
  }

  @override
  String parent_report_label_year(int year) {
    return '$year';
  }

  @override
  String get parent_report_wd_mon => 'M';

  @override
  String get parent_report_wd_tue => 'T';

  @override
  String get parent_report_wd_wed => 'W';

  @override
  String get parent_report_wd_thu => 'T';

  @override
  String get parent_report_wd_fri => 'F';

  @override
  String get parent_report_wd_sat => 'S';

  @override
  String get parent_report_wd_sun => 'S';

  @override
  String get parent_report_heat_empty => 'No focus records in the last year.';

  @override
  String parent_report_heat_tip(String date, int minutes) {
    return '$date · $minutes min';
  }

  @override
  String parent_report_month_tick(int month) {
    return '$month';
  }

  @override
  String get parent_report_legend_less => 'Less';

  @override
  String get parent_report_legend_more => 'More';

  @override
  String parent_report_streak_current(int days) {
    return '$days-day current streak';
  }

  @override
  String parent_report_streak_longest(int days) {
    return '$days-day best streak';
  }

  @override
  String get parent_report_stability_empty =>
      'No focus records in the last 4 weeks.';

  @override
  String parent_report_weeks_ago(int count) {
    return '${count}w ago';
  }

  @override
  String get parent_report_week_this => 'This week';

  @override
  String parent_report_stability_score(int percent) {
    return 'Stability $percent%';
  }

  @override
  String get parent_report_upsell_title => 'Unlock the in-depth report';

  @override
  String get parent_report_upsell_subtitle =>
      '4-week stability · full-year heatmap';

  @override
  String get parent_report_eyecare_completed => 'Breaks done';

  @override
  String get parent_report_eyecare_skipped => 'Skipped';

  @override
  String get parent_report_eyecare_duration => 'Total eye-care time';

  @override
  String get parent_report_eyecare_rate => 'Skip rate';

  @override
  String parent_report_times(int count) {
    return '×$count';
  }

  @override
  String parent_report_secs(int count) {
    return '$count s';
  }

  @override
  String parent_report_minutes_1f(String value) {
    return '$value min';
  }

  @override
  String parent_report_eyecare_skip_note(int count) {
    return '$count breaks were skipped (watched time still counted honestly).';
  }

  @override
  String get premium_table_free_pill => 'Free';

  @override
  String get premium_table_gold_pill => 'Unlock All ★';

  @override
  String get premium_table_owned => 'Owned';

  @override
  String get premium_table_band_free => 'Free to use';

  @override
  String get premium_table_row_core => 'Core features — all free';

  @override
  String get premium_table_footnote_core =>
      'Focus timer · screen time · eye care · garden · ledger · store · 40 levels & 9 titles';

  @override
  String get premium_table_band_capacity => 'Buy once · more capacity';

  @override
  String get premium_table_band_advanced => 'Buy once · advanced features';

  @override
  String get premium_table_row_report => 'Parent focus report';

  @override
  String get premium_table_report_days => 'Last 7 days';

  @override
  String get premium_table_report_premium =>
      'Adds monthly & yearly reports · heatmap';

  @override
  String get premium_table_row_one_click => 'Garden one-tap care';

  @override
  String get premium_table_row_pots => 'Pot capacity';

  @override
  String get premium_table_row_templates => 'Task & reward templates';

  @override
  String get premium_table_row_profiles => 'Child profiles';

  @override
  String get premium_table_row_tasks => 'Growth templates';

  @override
  String get premium_table_row_rewards => 'Reward templates';

  @override
  String get premium_table_row_perks => 'Title perks';

  @override
  String premium_table_free_pots(int count) {
    return '$count pots';
  }

  @override
  String premium_table_free_items(int count) {
    return '$count each';
  }

  @override
  String premium_table_free_items_single(int count) {
    return '$count items';
  }

  @override
  String get premium_table_unlimited => '✓ Unlimited';

  @override
  String premium_table_max(int count) {
    return 'Up to $count';
  }

  @override
  String get premium_table_pots_note => 'Extra pots still cost sunlight';

  @override
  String premium_table_perks_count(int count) {
    return '✓ $count perks';
  }

  @override
  String premium_quota_inline_reason(String limit, int count) {
    return 'Free limit $limit (now $count)';
  }

  @override
  String get parent_premium_title => 'Unlock All';

  @override
  String get parent_premium_hero_subtitle =>
      'One purchase — your child\'s focus garden blooms for life';

  @override
  String get parent_premium_pill_unlocked => 'Unlocked';

  @override
  String get parent_premium_pill_locked => 'Locked';

  @override
  String get parent_premium_gold_pill => 'One-time · forever';

  @override
  String get parent_premium_scene_garden_title => 'A roomier garden';

  @override
  String parent_premium_scene_garden_detail(int potMax) {
    return 'Up to $potMax pots · one-tap care';
  }

  @override
  String get parent_premium_scene_routine_title => 'Flexible routines';

  @override
  String get parent_premium_scene_routine_detail => 'Unlimited tasks & rewards';

  @override
  String get parent_premium_scene_perk_title => 'Growth perks';

  @override
  String parent_premium_scene_perk_detail(int perkCount, int profileMax) {
    return '$perkCount title perks · up to $profileMax child profiles';
  }

  @override
  String get parent_premium_unavailable_title => 'Store is unreachable';

  @override
  String get parent_premium_unavailable_body =>
      'Product info is unavailable right now; everything else in the app still works. Check your network and retry.';

  @override
  String get parent_premium_btn_unlocked_done => 'Unlocked · thank you';

  @override
  String get parent_premium_btn_buying => 'Purchasing…';

  @override
  String get parent_premium_btn_unavailable => 'Not available now';

  @override
  String parent_premium_btn_unlock_now(String price) {
    return 'Unlock now · $price';
  }

  @override
  String get parent_premium_restoring => 'Restoring…';

  @override
  String get parent_premium_restore => 'Restore purchases';

  @override
  String get parent_premium_notes_title => 'Before you buy';

  @override
  String get parent_premium_note_1 =>
      'One-time buy, unlocked forever — not a subscription, no auto-renewal.';

  @override
  String get parent_premium_note_2 =>
      'Same Apple ID on a new phone or after reinstall: tap \"Restore purchases\" to get it back.';

  @override
  String get parent_premium_note_3 =>
      '⚠️ Purchases made on iOS cannot be restored on Android devices (and vice versa).';

  @override
  String get parent_premium_note_4 =>
      'Payment is handled by Apple App Store; developers never see your payment details.';

  @override
  String get parent_premium_snack_unlocked => 'Unlocked — thank you 🌻';

  @override
  String get parent_premium_snack_incomplete =>
      'Purchase not completed — try again later';

  @override
  String get parent_premium_snack_buy_failed =>
      'Purchase failed — try again later';

  @override
  String get parent_premium_snack_restored =>
      'Purchases restored — welcome back 🌻';

  @override
  String get parent_premium_snack_nothing => 'No purchases found to restore';

  @override
  String get parent_premium_snack_restore_net =>
      'Restore failed — check your network and retry';

  @override
  String get parent_premium_snack_restore_failed =>
      'Restore failed — try again later';

  @override
  String get parent_reward_category_label => 'Type';

  @override
  String get shared_lang_zh_name => '简体中文';

  @override
  String get shared_task_category_other => 'Other';

  @override
  String get shared_task_category_learning => 'Learning';

  @override
  String get shared_task_category_sports => 'Sports';

  @override
  String get shared_task_category_life => 'Life';

  @override
  String get shared_task_category_habit => 'Habit';

  @override
  String get shared_reward_content_other => 'Other';

  @override
  String get shared_reward_content_snacks => 'Snacks';

  @override
  String get shared_reward_content_play => 'Play';

  @override
  String get shared_reward_content_entertainment => 'Entertainment';

  @override
  String get shared_reward_content_toys => 'Toys';

  @override
  String get shared_reward_content_books => 'Books';

  @override
  String get shared_species_sunflower => 'Sunflower';

  @override
  String get shared_species_moon_orchid => 'Moon Orchid';

  @override
  String get shared_species_tomato => 'Tomato';

  @override
  String get shared_species_strawberry => 'Strawberry';

  @override
  String get shared_species_coral_orchid => 'Coral Ridge Orchid';

  @override
  String get shared_species_jade_hydrangea => 'Jade Hydrangea';

  @override
  String get shared_species_grape => 'Grape';

  @override
  String get shared_species_rose => 'Rose';

  @override
  String get shared_weekday_mon => 'Mon';

  @override
  String get shared_weekday_tue => 'Tue';

  @override
  String get shared_weekday_wed => 'Wed';

  @override
  String get shared_weekday_thu => 'Thu';

  @override
  String get shared_weekday_fri => 'Fri';

  @override
  String get shared_weekday_sat => 'Sat';

  @override
  String get shared_weekday_sun => 'Sun';

  @override
  String parent_report_bucket_week(int index) {
    return 'Wk $index';
  }

  @override
  String shared_perk_water_discount(int value) {
    return 'Water cost −$value';
  }

  @override
  String shared_perk_fertilize_discount(int value) {
    return 'Fertilizer cost −$value';
  }

  @override
  String shared_perk_weed_bonus(int value) {
    return 'Weeding bonus +$value';
  }

  @override
  String shared_perk_pest_bonus(int value) {
    return 'Pest bonus +$value';
  }

  @override
  String shared_perk_bloom_bonus(int value) {
    return 'Bloom sunlight +$value';
  }

  @override
  String shared_perk_dew_bonus(int value) {
    return 'Dew sunlight +$value';
  }

  @override
  String shared_perk_eyecare_bonus(int value) {
    return 'Eye-care bonus +$value';
  }

  @override
  String shared_perk_expand_discount(int value) {
    return 'Pot expand −$value';
  }

  @override
  String shared_perk_shovel_refund(int value) {
    return 'Shovel refund +$value';
  }

  @override
  String shared_duration_minutes(int m) {
    return '$m min';
  }

  @override
  String shared_duration_hours(int h) {
    return '$h h';
  }

  @override
  String shared_duration_hours_minutes(int h, int m) {
    return '$h h $m min';
  }

  @override
  String shared_level_gap_next(int n, String duration) {
    return '$duration to Lv.$n';
  }

  @override
  String shared_level_gap_max(String title) {
    return 'Max title · $title';
  }

  @override
  String shared_reward_weekly_limit(int remaining) {
    return '$remaining left this week';
  }

  @override
  String get shared_reward_unlimited => 'Unlimited';

  @override
  String get shared_plant_err_species_not_found => 'Plant species not found';

  @override
  String shared_plant_err_pot_out_of_capacity(int pot, int capacity) {
    return 'Pot #$pot is beyond capacity ($capacity)';
  }

  @override
  String shared_plant_err_pot_occupied(int pot) {
    return 'Pot #$pot is occupied — clear it first';
  }

  @override
  String get shared_plant_err_premium_fragments_only =>
      'Premium plants can only be bought with fragments';

  @override
  String get shared_plant_err_seed_empty =>
      'No seeds left — bloom plants to collect more';

  @override
  String shared_plant_err_sunlight_not_enough(int short) {
    return 'Not enough sunlight — $short more needed';
  }

  @override
  String shared_plant_err_fragments_not_enough(int short) {
    return 'Not enough fragments — $short more needed';
  }

  @override
  String get shared_plant_err_care_state_invalid =>
      'Only growing, blooming or wilting plants can be cared for';

  @override
  String shared_plant_err_water_daily_limit(int max) {
    return 'Watering limit reached ($max today)';
  }

  @override
  String shared_plant_err_water_interval(int interval, int wait) {
    return 'Water every $interval min — wait $wait min';
  }

  @override
  String shared_plant_err_fertilize_daily_limit(int max) {
    return 'Fertilizing limit reached ($max today)';
  }

  @override
  String get shared_plant_err_plant_not_found => 'Plant not found';

  @override
  String get shared_plant_err_already_wilted => 'This plant has already wilted';

  @override
  String get shared_plant_err_no_weed => 'No weeds in this pot';

  @override
  String get shared_plant_err_no_pest => 'No pests in this pot';

  @override
  String shared_plant_err_garden_full(int limit) {
    return 'Garden is full ($limit pots) — unlock to expand';
  }

  @override
  String get shared_plant_err_reward_not_mature =>
      'Not ripe yet, or already collected';

  @override
  String get shared_checkin_err_linked_auto =>
      'This task completes automatically in a focus session';

  @override
  String get shared_checkin_err_already_done =>
      'You already did this task today';

  @override
  String get shared_checkin_err_not_linked => 'This task isn\'t focus-linked';

  @override
  String get shared_checkin_err_session_not_today =>
      'That session isn\'t from today';

  @override
  String get shared_checkin_err_session_used =>
      'That session already settled a task';

  @override
  String get shared_checkin_err_not_found =>
      'Record not found — it may have been deleted';

  @override
  String get shared_checkin_err_already_verified =>
      'Already handled — can\'t verify twice';

  @override
  String get shared_checkin_err_already_rejected => 'Already handled';

  @override
  String get shared_checkin_err_race => 'Just handled a moment ago';

  @override
  String get seed_task_homework => 'Finish school homework';

  @override
  String get seed_task_math => 'Practice mental math';

  @override
  String get seed_task_read => 'Read for 20 minutes';

  @override
  String get seed_task_rope_skip => 'Jump rope 170+ times in a minute';

  @override
  String get seed_task_chores => 'Help tidy up at home';

  @override
  String get seed_reward_snack => 'A small snack';

  @override
  String get seed_reward_extra_play => '10 more minutes before bed';

  @override
  String get seed_reward_cartoon => 'Watch one cartoon episode';

  @override
  String get seed_reward_toy => 'A small toy';

  @override
  String get seed_reward_weekend_outing => 'A weekend outing';

  @override
  String get shared_child_default_name => 'Child';

  @override
  String get child_hist_ref_focus => 'Focus output';

  @override
  String get child_hist_ref_focus_session => 'Focus';

  @override
  String get child_hist_ref_focus_task_reward => 'Focus task reward';

  @override
  String get child_hist_ref_task_checkin => 'Task reward';

  @override
  String get child_hist_ref_plant_plant => 'Planted a plant';

  @override
  String get child_hist_ref_plant_water => 'Watering';

  @override
  String get child_hist_ref_plant_fertilize => 'Fertilizing';

  @override
  String get child_hist_ref_plant_revive => 'Plant revived';

  @override
  String get child_hist_ref_plant_expand => 'Garden expanded';

  @override
  String get child_hist_ref_plant_weed => 'Weeding';

  @override
  String get child_hist_ref_plant_pest => 'Pest removal';

  @override
  String get child_hist_ref_plant_death_refund => 'Plant death refund';

  @override
  String get child_hist_ref_eye_care_break => 'Eye care';

  @override
  String get child_hist_ref_plant_shovel_refund => 'Shovel refund';

  @override
  String get child_hist_ref_bloom_reward => 'Bloom reward';

  @override
  String get child_hist_ref_bloom_reward_24h => 'Bloom revisit reward';

  @override
  String get child_hist_ref_redeem => 'Reward redeemed';

  @override
  String get child_hist_ref_redemption => 'Reward redeemed';

  @override
  String get child_hist_ref_queue_release => 'Sunlight pool release';

  @override
  String get child_hist_ref_parent_gift => 'Parent gift';

  @override
  String get child_hist_ref_debug_grant => 'Debug grant';

  @override
  String get child_hist_ref_focus_level_up => 'Focus level up';

  @override
  String get child_eyecare_seg_default =>
      'Follow the animation to protect your eyes';

  @override
  String get shared_perk_name_eye_care => 'Eye care';

  @override
  String get shared_perk_name_water => 'Watering';

  @override
  String get shared_perk_name_fertilize => 'Fertilizing';

  @override
  String get shared_perk_name_weed => 'Weeding';

  @override
  String get shared_perk_name_pest => 'Pest control';

  @override
  String get shared_perk_name_bloom => 'Bloom';

  @override
  String get shared_perk_name_dew => 'Morning dew';

  @override
  String get shared_perk_name_pot_expand => 'Pot upgrade';

  @override
  String get shared_perk_name_shovel => 'Removal';

  @override
  String get shared_default_child_name => 'Child';

  @override
  String get shared_title_lv1 => 'Sprout';

  @override
  String get shared_title_lv5 => 'Seedling';

  @override
  String get shared_title_lv10 => 'Calm Reader';

  @override
  String get shared_title_lv15 => 'Time Warden';

  @override
  String get shared_title_lv20 => 'Focus Knight';

  @override
  String get shared_title_lv25 => 'Star Envoy';

  @override
  String get shared_title_lv30 => 'Focus Mage';

  @override
  String get shared_title_lv35 => 'Star Guard';

  @override
  String get shared_title_lv40 => 'Time Sage';

  @override
  String get species_lore_sunflower_intro =>
      'A golden face that follows the sun';

  @override
  String get species_lore_sunflower_story =>
      'Little sunflower watches the sun all day. Wherever the sun goes, it turns to follow. That is how it grew its shiny golden face — the brightest little sun in the garden.';

  @override
  String get species_lore_tomato_intro => 'Little red lanterns in a row';

  @override
  String get species_lore_tomato_story =>
      'Baby tomatoes start out green. As they soak up the sunshine, they blush redder and redder. When ripe, they hang on the vine like tiny lanterns.';

  @override
  String get species_lore_strawberry_intro =>
      'A heart-shaped berry with speckles';

  @override
  String get species_lore_strawberry_story =>
      'A strawberry is covered with tiny speckles. Each speckle is a real little seed! One berry can hide two hundred seeds.';

  @override
  String get species_lore_moon_orchid_intro => 'Blooms only under the moon';

  @override
  String get species_lore_moon_orchid_story =>
      'Moon orchid sleeps soundly all day. When the moon rises, it gently opens its petals. The flower brews moonlight into a soft scent that helps children drift to sleep.';

  @override
  String get species_lore_coral_orchid_intro => 'Pink like undersea coral';

  @override
  String get species_lore_coral_orchid_story =>
      'Legend says it is a dream of undersea coral resting on land. In that dream, pink flowers bloomed. Now little seashells whisper between its leaves.';

  @override
  String get species_lore_jade_hydrangea_intro =>
      'Many blooms hug into one ball';

  @override
  String get species_lore_jade_hydrangea_story =>
      'A jade hydrangea is dozens of tiny flowers holding hands. Even the strongest wind cannot blow them apart. Flowers that stick together are the prettiest.';

  @override
  String get species_lore_grape_intro => 'Bunches of little purple pearls';

  @override
  String get species_lore_grape_story =>
      'Grapes are little climbing champions! They use tiny curly tendrils as hands to climb up, step by step. And guess what — their flowers are so shy they open backwards: the fruit pops out before the tiny flower even blooms.';

  @override
  String get species_lore_rose_intro => 'A little guard with thorns';

  @override
  String get species_lore_rose_story =>
      'A rose wears its thorns like tiny armor, keeping its soft petals safe from hungry visitors. That lovely smell comes from little drops of oil hiding inside the petals — it takes heaps and heaps of petals to fill just one small bottle of rose perfume!';

  @override
  String get species_lore_fallback_intro => 'A little garden plant';

  @override
  String get species_lore_fallback_story =>
      'Every plant has its own little story, waiting for you to discover.';

  @override
  String get praise_phrase_1 =>
      'Awesome! You just focused through a whole stretch of time!';

  @override
  String get praise_phrase_2 => 'Amazing! Your sunflower is so happy for you!';

  @override
  String get praise_phrase_3 =>
      'Your focus power just got a little bit stronger!';

  @override
  String get praise_phrase_4 =>
      'Sticking with it is a superpower — and you did it!';

  @override
  String get praise_phrase_5 => 'Today is another sparkling day!';

  @override
  String get praise_phrase_6 =>
      'Way to go! One step closer to a full jar of sunlight!';

  @override
  String get praise_phrase_7 => 'You look so cool when you concentrate!';

  @override
  String get praise_phrase_8 => 'Every focus time makes you even more awesome!';

  @override
  String get praise_phrase_9 =>
      'The sunflower says: thanks for working hard with me!';

  @override
  String get praise_phrase_10 => 'Wow, you focused even better than yesterday!';

  @override
  String get praise_phrase_11 => 'Small efforts, big growth!';

  @override
  String get praise_phrase_12 => 'You\'re the best little sunshine ever!';

  @override
  String get praise_phrase_13 =>
      'Well done! Give yourself a great big thumbs-up!';

  @override
  String get praise_phrase_14 => 'When you focus, that\'s when you shine!';

  @override
  String get praise_phrase_15 => 'More sunlight earned — keep it up!';

  @override
  String get praise_phrase_16 =>
      'Another focus challenge done — you\'re amazing!';

  @override
  String get praise_phrase_17 => 'Your sunflower sees all your hard work!';

  @override
  String get praise_phrase_18 => 'Fantastic! Let\'s shine again tomorrow!';

  @override
  String get praise_phrase_19 => 'Every bit of focus helps a flower bloom!';

  @override
  String get praise_phrase_20 =>
      'You shine brighter than the sun when you focus!';

  @override
  String get parent_settings_section_about => 'About & feedback';

  @override
  String get parent_settings_version_title => 'Version';

  @override
  String get parent_settings_contact_title => 'Contact the developer';

  @override
  String get parent_settings_contact_sub =>
      'Questions, ideas or a bug? Send me an email';

  @override
  String get parent_settings_website_title => 'Official website';

  @override
  String get parent_settings_website_sub =>
      'Guides, release notes and privacy policy';

  @override
  String parent_settings_contact_mail_subject(String version) {
    return 'Tiny Sunflower feedback v$version';
  }

  @override
  String parent_settings_contact_mail_body(String version, String platform) {
    return 'Tell me what happened below:\n\n\n\n--\nVersion: $version\nPlatform: $platform';
  }

  @override
  String parent_settings_open_failed(String target) {
    return 'Could not open the app. Please use: $target';
  }

  @override
  String get garden_pot_locked_hint =>
      'More flowers can grow here! Ask your parents to unlock more pots 🌻';
}
