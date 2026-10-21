// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get app_title => 'SunFocus';

  @override
  String get consent_welcome_title => 'Welcome to SunFocus';

  @override
  String get consent_compliance_body =>
      '· We only collect necessary data such as focus time and check-ins;\n· All data is encrypted and stays on this device, never uploaded;\n· No account, no ads, no social features; we never access contacts or location.';

  @override
  String get consent_btn_agree => 'Let\'s Start';

  @override
  String get consent_btn_back_garden => 'Back to Garden';

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
  String child_lock_body(Object hour) {
    return 'After $hour:00 the sunflower goes to sleep — see you tomorrow~';
  }

  @override
  String get child_rest_title => 'Take a Break';

  @override
  String child_rest_body(Object sec) {
    return 'Take a break and sip some water — $sec s left';
  }

  @override
  String get child_rest_done => 'I\'m Done Resting';

  @override
  String child_eyecare_countdown(Object sec) {
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
  String child_today_minutes(Object minutes) {
    return '$minutes min';
  }

  @override
  String child_today_focus_count(Object count) {
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
  String child_settle_secs(Object sec) {
    return '$sec s';
  }

  @override
  String child_settle_mins(Object min) {
    return '$min min';
  }

  @override
  String child_settle_min_sec(Object min, Object sec) {
    return '$min min $sec s';
  }

  @override
  String get child_settle_task_label => 'Growth task';

  @override
  String get child_settle_task_skipped =>
      'Task settlement did not finish; this session\'s sunlight is unaffected';

  @override
  String child_settle_task_capped(Object sun) {
    return '(Daily sunlight cap reached; only $sun ☀ credited)';
  }

  @override
  String child_settle_task_done(Object capped, Object name, Object sun) {
    return 'Task \"$name\" done +$sun ☀$capped';
  }

  @override
  String child_settle_task_progress(Object name) {
    return 'Task \"$name\" is nearly there — it counts once a session is long enough 🌻';
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
  String child_settle_cap_body_detail(Object cheer, Object detail) {
    return 'No sunlight is collected beyond the quota$detail. $cheer';
  }

  @override
  String child_settle_cap_orig_vs_net(Object net, Object raw) {
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
  String child_cap_single_body(Object minutes) {
    return 'You\'ve played $minutes minutes straight — rest your eyes';
  }

  @override
  String get child_cap_daily_body => 'Today\'s app time is used up';

  @override
  String get child_cap_chip_rest => 'Break';

  @override
  String get child_cap_chip_daily => 'Daily Cap';

  @override
  String child_cap_unlock_in(Object minutes) {
    return 'Unlocks in $minutes min';
  }

  @override
  String child_cap_minutes(Object minutes) {
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
  String child_entry_cap_daily(Object cap) {
    return 'Today\'s focus time is used up (daily limit $cap min) — see you tomorrow';
  }

  @override
  String child_entry_remaining_today(Object cap, Object minutes) {
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
  String child_entry_custom_hint_max(Object max) {
    return 'Up to $max minutes';
  }

  @override
  String child_entry_custom_hint_capped(Object max) {
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
  String child_entry_minutes(Object minutes) {
    return '$minutes min';
  }

  @override
  String child_entry_cap_snack(Object cap) {
    return 'Daily focus limit reached ($cap min) — come back tomorrow';
  }

  @override
  String child_entry_cap_snack2(Object cap) {
    return 'Today\'s focus time is used up (limit $cap min) — come back tomorrow';
  }

  @override
  String child_entry_remaining_snack(Object minutes, Object remaining) {
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
  String child_shell_item_cost(Object sun) {
    return '-$sun sunlight';
  }

  @override
  String child_shell_verify_total(Object total) {
    return 'A total of $total sunlight was deducted';
  }

  @override
  String get child_shell_reject_title => '🚫 Redeem not approved';

  @override
  String child_shell_reject_subtitle(Object note) {
    return '($note)';
  }

  @override
  String get child_shell_reject_reason => 'Parent declined this request';

  @override
  String get child_shell_reject_footer =>
      'No sunlight was deducted; you can redeem another reward';

  @override
  String get child_shell_task_footer_capped =>
      'Daily growth rewards are capped; no sunlight this time';

  @override
  String child_shell_task_footer_partial(Object capped, Object total) {
    return 'Got $total sunlight ($capped item(s) hit the daily cap)';
  }

  @override
  String child_shell_task_footer(Object total) {
    return 'Got $total sunlight';
  }

  @override
  String get child_shell_task_title => '🎉 Parent approved your task';

  @override
  String get child_shell_task_fallback => 'Growth task';

  @override
  String child_shell_task_item_sun(Object sun) {
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
  String garden_seed_decomposed(Object name, int count) {
    return 'Duplicate $name seed became $count fragments';
  }

  @override
  String garden_reward_fragments(int count) {
    return '+$count fragments';
  }

  @override
  String garden_seed_dropped(Object name) {
    return 'Dropped a $name seed';
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
    return '$count';
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
    return 'My sunlight: $count ☀';
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
  String ghelp_earn_detail(int perMinute, int taskReward) {
    return 'Focus during the day to earn sunlight: +$perMinute ☀ per minute;\nfinish a growth task check-in for +$taskReward ☀ each.';
  }

  @override
  String get ghelp_use_title => 'Spending sunlight';

  @override
  String ghelp_use_detail(int waterCost, int fertCost) {
    return 'Plant in the garden (tap an empty pot, pay ☀ to plant);\nwater plants from $waterCost ☀/time, fertilize from $fertCost ☀/time;\nor redeem rewards you like in the Store.';
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
  String ghelp_wilt_detail(int wiltDays, int deathDays) {
    return 'Watering or fertilizing refreshes the timer; $wiltDays days without water means wilting,\nand $deathDays more days means the plant dies. Come visit often 🌱';
  }

  @override
  String get ghelp_task_title => 'Task check-ins & parent approval';

  @override
  String get ghelp_task_detail =>
      'There are two kinds of growth tasks:\n\"Start focus\" tasks settle automatically when the goal is met;\n\"I did it\" tasks are recorded as \"waiting for parent approval\" —\nsunlight arrives only after a parent approves.';

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
  String get prd_level_locked_title => 'Title not unlocked yet';

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
}
