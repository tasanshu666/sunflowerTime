// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get app_title => 'SunFocus 向日葵专注';

  @override
  String get consent_welcome_title => '欢迎使用向日葵专注';

  @override
  String get consent_compliance_body =>
      '· 我们只收集专注时长、打卡等必要数据；\n· 全部数据加密存储在本机，不上传云端；\n· 无账号、无广告、无社交，不采集通讯录与位置。';

  @override
  String get consent_btn_agree => '同意并开始';

  @override
  String get consent_btn_back_garden => '返回花园';

  @override
  String get shared_lang_title => '语言';

  @override
  String get shared_lang_follow_system => '跟随系统';

  @override
  String get shared_ok => '确定';

  @override
  String get shared_unlimited => '不限';

  @override
  String get parent_settings_lang_entry => '语言';

  @override
  String get premium_gate_feature_one_click_care => '花园一键操作';

  @override
  String get premium_gate_feature_pot_capacity => '更多花盆';

  @override
  String get premium_gate_feature_parent_report => '家长专注报告';

  @override
  String get premium_gate_feature_task_templates => '更多成长项模板';

  @override
  String get premium_gate_feature_reward_templates => '更多奖励模板';

  @override
  String get premium_gate_feature_multi_child => '多孩子档案';

  @override
  String get premium_gate_feature_deep_report => '深度专注报告';

  @override
  String get premium_gate_feature_export_share => '数据导出与分享';

  @override
  String get premium_gate_feature_memoir_export => '纪念册导出';

  @override
  String get premium_gate_feature_family_sharing => '家庭共享';

  @override
  String get premium_gate_feature_title_perks => '称号专属属性';

  @override
  String premium_gate_upsell_title(String name) {
    return '解锁「$name」';
  }

  @override
  String get premium_gate_upsell_subtitle => '一次买断，永久解锁全部功能';

  @override
  String get premium_gate_upsell_btn => '查看详情';

  @override
  String get premium_gate_upsell_dialog_title => '升级解锁';

  @override
  String premium_gate_upsell_dialog_message(String name) {
    return '「$name」需要一次性买断解锁。';
  }

  @override
  String get premium_gate_later => '稍后';

  @override
  String get premium_gate_unlock_all => '解锁全部功能';

  @override
  String premium_quota_snack(String limit, int count) {
    return '免费版最多 $limit（当前 $count），删除多余内容后即可新增';
  }

  @override
  String get child_lock_title => '睡觉时间';

  @override
  String get child_lock_sleeping => '🌻 向日葵睡觉中';

  @override
  String child_lock_body(Object hour) {
    return '晚上 $hour:00 后向日葵要休息啦，明天再陪你专注~';
  }

  @override
  String get child_rest_title => '休息一下';

  @override
  String child_rest_body(Object sec) {
    return '休息一下，喝口水～ 还剩 $sec 秒';
  }

  @override
  String get child_rest_done => '我休息好了';

  @override
  String child_eyecare_countdown(Object sec) {
    return '还剩 $sec 秒';
  }

  @override
  String get child_eyecare_title => '眼睛休息一下吧';

  @override
  String get shared_back => '返回';

  @override
  String get shared_start_focus => '开始专注';

  @override
  String get shared_sunlight => '阳光';

  @override
  String get child_today_sunlight_title => '今日获取阳光';

  @override
  String get child_today_focus_label => '今日专注';

  @override
  String child_today_minutes(Object minutes) {
    return '$minutes 分钟';
  }

  @override
  String child_today_focus_count(Object count) {
    return '· $count 次';
  }

  @override
  String get child_today_growth_label => '今日成长';

  @override
  String get child_today_all_done => '全部完成 🌻';

  @override
  String get child_today_growth_hint => '想赚成长阳光？从「成长」里点具体项目开始专注 🌻';

  @override
  String child_settle_secs(Object sec) {
    return '$sec 秒';
  }

  @override
  String child_settle_mins(Object min) {
    return '$min 分钟';
  }

  @override
  String child_settle_min_sec(Object min, Object sec) {
    return '$min 分 $sec 秒';
  }

  @override
  String get child_settle_task_label => '成长项';

  @override
  String get child_settle_task_skipped => '成长项结算没能完成，不影响本次专注阳光';

  @override
  String child_settle_task_capped(Object sun) {
    return '（今日阳光已达上限，本次只到账 $sun ☀）';
  }

  @override
  String child_settle_task_done(Object capped, Object name, Object sun) {
    return '成长项「$name」完成 +$sun ☀$capped';
  }

  @override
  String child_settle_task_progress(Object name) {
    return '成长项「$name」还差一点，下次专注够时长就算上啦 🌻';
  }

  @override
  String get child_settle_title => '专注结束啦';

  @override
  String get child_settle_this_session => '本次专注';

  @override
  String get child_settle_collected => '收集阳光';

  @override
  String get child_settle_eyecare_reward => '护眼奖励';

  @override
  String get child_settle_task_reward => '任务奖励';

  @override
  String get child_settle_today_total => '今日累计';

  @override
  String get child_settle_balance => '拥有阳光';

  @override
  String get child_settle_too_short => '这次太短啦，向日葵没来得及收集阳光（≥5 分钟才有产出哦）';

  @override
  String get child_settle_cap_title => '🌻 今天专注额度用完啦';

  @override
  String child_settle_cap_body_detail(Object cheer, Object detail) {
    return '超出额度的部分就不再收集阳光了$detail。$cheer';
  }

  @override
  String child_settle_cap_orig_vs_net(Object net, Object raw) {
    return '（原本 $raw ☀️，实到 $net ☀️）';
  }

  @override
  String get child_settle_cap_cheer => '今天已经很棒啦，明天再来吧！';

  @override
  String get child_settle_home => '回首页';

  @override
  String get child_feedback_collected => '太好了，又收集到阳光了。';

  @override
  String get child_feedback_welcome_back => '欢迎回来';

  @override
  String get child_feedback_rest_hint => '休息一下就回来哦';

  @override
  String get child_feedback_miss => '向日葵想你了，回来看看吧';

  @override
  String get child_avatar_pick => '选择头像';

  @override
  String get child_avatar_hint => '种下过的植物可以拿来当头像';

  @override
  String get child_cap_single_title => '休息一下，等会再来玩';

  @override
  String get child_cap_daily_title => '先歇一会儿吧';

  @override
  String child_cap_single_body(Object minutes) {
    return '已经连续玩 $minutes 分钟啦，让眼睛休息一下';
  }

  @override
  String get child_cap_daily_body => '今天逛 App 的时间用完啦';

  @override
  String get child_cap_chip_rest => '休息一会';

  @override
  String get child_cap_chip_daily => '今日上限';

  @override
  String child_cap_unlock_in(Object minutes) {
    return '$minutes 分钟后解锁';
  }

  @override
  String child_cap_minutes(Object minutes) {
    return '$minutes 分钟';
  }

  @override
  String get child_cap_chip_go_today => '去「今日」';

  @override
  String get child_cap_chip_earn => '专注赚阳光';

  @override
  String get child_cap_btn_go_focus => '去「今日」开始专注 🌻';

  @override
  String get child_cap_ok => '知道啦';

  @override
  String get child_entry_pick_duration => '这次想专注多久？';

  @override
  String child_entry_cap_daily(Object cap) {
    return '今天的专注时间已经用完啦（每日上限 $cap 分钟），明天再来';
  }

  @override
  String child_entry_remaining_today(Object cap, Object minutes) {
    return '今天还可以专注 $minutes 分钟（每日上限 $cap 分钟）';
  }

  @override
  String get child_entry_free => '自由';

  @override
  String get child_entry_custom => '自定义';

  @override
  String get child_entry_custom_title => '自定义时长（分钟）';

  @override
  String get child_entry_quota_empty => '今日额度已用完';

  @override
  String child_entry_custom_hint_max(Object max) {
    return '可选 $max 分钟以内';
  }

  @override
  String child_entry_custom_hint_capped(Object max) {
    return '可选 $max 分钟以内（受今日剩余额度限制）';
  }

  @override
  String get child_entry_options_title => '专注时的小设置';

  @override
  String get child_entry_dnd => '屏蔽通知（勿扰）';

  @override
  String get child_entry_dnd_hint => '专注时屏蔽短信/来电等打扰';

  @override
  String get child_entry_sound => '提示音效';

  @override
  String get child_entry_sound_hint => '专注时播放轻提示音';

  @override
  String get child_entry_bgm => '背景音乐';

  @override
  String get child_entry_bgm_hint => '专注时循环轻柔背景乐';

  @override
  String child_entry_minutes(Object minutes) {
    return '$minutes 分钟';
  }

  @override
  String child_entry_cap_snack(Object cap) {
    return '今日专注已达上限（$cap 分钟），明天再来哦';
  }

  @override
  String child_entry_cap_snack2(Object cap) {
    return '今天的专注时间用完啦（上限 $cap 分钟），明天再来哦';
  }

  @override
  String child_entry_remaining_snack(Object minutes, Object remaining) {
    return '今天只剩 $remaining 分钟额度了，这次就专注 $minutes 分钟吧';
  }

  @override
  String get child_focus_dnd_permission => '请在系统设置中开启勿扰权限以屏蔽通知';

  @override
  String get child_focus_exit_title => '确定结束吗？';

  @override
  String get child_focus_exit_body => '向日葵还在这儿陪着你，要现在结束专注吗？';

  @override
  String get child_focus_exit_stay => '再坐一会';

  @override
  String get child_focus_exit_end => '结束';

  @override
  String get child_focus_debug_ff => '调试：快进 5 分钟（护眼触发用）';

  @override
  String get child_focus_free_label => '自由专注';

  @override
  String get child_focus_session_label => '本次专注';

  @override
  String get child_focus_dnd_off => '未开启勿扰，通知仍会打扰';

  @override
  String get child_focus_dnd_go => '去开启';

  @override
  String get child_focus_wait_back => '向日葵在等你回来';

  @override
  String get child_focus_paused => '已暂停';

  @override
  String get child_focus_buffer_eyecare => '🌻 让眼睛休息一下吧';

  @override
  String get child_focus_buffer_end => '🌻 专注结束啦';

  @override
  String get child_focus_buffer_resume_hint => '休息完继续加油哦';

  @override
  String get child_focus_buffer_eyecare2 => '让眼睛休息一下吧';

  @override
  String get child_focus_cap_notice => '今天的专注额度用完啦，剩下的时间不再收集阳光，累了随时可以结束哦';

  @override
  String get child_focus_no_touch => '本屏不可交互 · 竖屏即可结束';

  @override
  String get child_shell_tab_today => '今日';

  @override
  String get child_shell_tab_growth => '成长';

  @override
  String get child_shell_tab_garden => '花园';

  @override
  String get child_shell_tab_store => '商店';

  @override
  String get child_shell_tab_mine => '我的';

  @override
  String get child_shell_verify_title => '🎉 家长已确认你的兑换';

  @override
  String get child_shell_item_reward => '奖励';

  @override
  String child_shell_item_cost(Object sun) {
    return '-$sun 阳光';
  }

  @override
  String child_shell_verify_total(Object total) {
    return '共扣除 $total 阳光';
  }

  @override
  String get child_shell_reject_title => '🚫 兑换未被通过';

  @override
  String child_shell_reject_subtitle(Object note) {
    return '（$note）';
  }

  @override
  String get child_shell_reject_reason => '家长拒绝了该申请';

  @override
  String get child_shell_reject_footer => '本次阳光未被扣除，可重新兑换其他奖励';

  @override
  String get child_shell_task_footer_capped => '今日成长奖励已达上限，本次没有新增阳光';

  @override
  String child_shell_task_footer_partial(Object capped, Object total) {
    return '共获得 $total 阳光（$capped 项今日额度已满，未发放）';
  }

  @override
  String child_shell_task_footer(Object total) {
    return '共获得 $total 阳光';
  }

  @override
  String get child_shell_task_title => '🎉 家长已确认你的成长任务';

  @override
  String get child_shell_task_fallback => '成长任务';

  @override
  String child_shell_task_item_sun(Object sun) {
    return '+$sun 阳光';
  }

  @override
  String get child_shell_task_item_capped => '今日额度已满';

  @override
  String garden_settle_withered(Object parts) {
    return '花朵凋谢，奖励已自动收下：$parts';
  }

  @override
  String shared_op_failed(Object error) {
    return '操作失败：$error';
  }

  @override
  String garden_shovel_refund(int refund) {
    return '铲除成功，返还 $refund ☀';
  }

  @override
  String get garden_shovel_ok => '铲除成功';

  @override
  String garden_collect_gift_prefix(Object body) {
    return '盛开的礼物：$body';
  }

  @override
  String get garden_cleared_weed => '除草成功';

  @override
  String get garden_cleared_pest => '除虫成功';

  @override
  String garden_reward_sunlight(int count) {
    return '+$count ☀ 阳光';
  }

  @override
  String garden_seed_decomposed(Object name, int count) {
    return '重复的「$name」种子已分解为 $count 植物碎片';
  }

  @override
  String garden_reward_fragments(int count) {
    return '+$count 植物碎片';
  }

  @override
  String garden_seed_dropped(Object name) {
    return '掉落「$name」种子';
  }

  @override
  String get garden_gift_default => '收到一份小礼物～';

  @override
  String get garden_fx_sprout => '发芽啦！🌱';

  @override
  String get garden_fx_grow => '长大啦！🌿';

  @override
  String get garden_fx_bloom => '开花啦！🌻';

  @override
  String garden_need_more_sun(int missing) {
    return '阳光不足，还差 $missing ☀ —— 去专注赚阳光吧';
  }

  @override
  String get garden_expand_title => '要给花园腾一个花盆吗？';

  @override
  String get garden_row_expand_cost => '本次扩容';

  @override
  String get garden_row_balance => '当前阳光';

  @override
  String garden_expand_note(int count, int next) {
    return '花园容量：$count 盆 → $next 盆';
  }

  @override
  String get garden_confirm_deduct => '确定，扣除';

  @override
  String get garden_batch_none_water => '今天没有可浇水的植物';

  @override
  String get garden_batch_none_fertilize => '今天没有可施肥的植物';

  @override
  String get garden_batch_none_care => '没有需要护理的植物';

  @override
  String get garden_row_total_cost => '本次合计扣除';

  @override
  String garden_water_note(int count, int cost) {
    return '将对 $count 盆植物各浇 1 次水（每盆 $cost ☀）';
  }

  @override
  String garden_fertilize_note(int count, int cost) {
    return '将对 $count 盆植物各施 1 次肥（每盆 $cost ☀）';
  }

  @override
  String get garden_row_cleanup => '本次清理';

  @override
  String garden_cleanup_count(int count) {
    return '$count 处';
  }

  @override
  String garden_care_note(int weed, int pest) {
    return '奖励照常发放：除草 +$weed ☀ / 除虫 +$pest ☀';
  }

  @override
  String get garden_oneclick_water_title => '要一键浇水吗？';

  @override
  String get garden_oneclick_fertilize_title => '要一键施肥吗？';

  @override
  String get garden_oneclick_care_title => '要一键护理吗？';

  @override
  String garden_oneclick_water_ok(int count) {
    return '一键浇水成功 ×$count';
  }

  @override
  String garden_oneclick_fertilize_ok(int count) {
    return '一键施肥成功 ×$count';
  }

  @override
  String garden_oneclick_care_ok(int count) {
    return '一键护理成功 ×$count';
  }

  @override
  String get garden_pick_plant_title => '选择要种的植物';

  @override
  String get garden_cost_free => '免费';

  @override
  String get garden_cost_seed => '种子';

  @override
  String garden_cost_sunlight(int count) {
    return '$count 阳光';
  }

  @override
  String get garden_reason_no_sun => '阳光不足';

  @override
  String garden_cost_fragments(int count) {
    return '$count 植物碎片';
  }

  @override
  String garden_reason_no_fragments(int count) {
    return '植物碎片不足（当前 $count 片）';
  }

  @override
  String get garden_row_plant => '本次种植';

  @override
  String garden_row_use_seed(String rarity) {
    return '使用$rarity种子';
  }

  @override
  String garden_seed_count(int count) {
    return '$count 张';
  }

  @override
  String get garden_row_seed_balance => '当前种子';

  @override
  String garden_seed_remaining(int count) {
    return '种下后剩余 $count 张';
  }

  @override
  String get garden_row_use_fragments => '使用植物碎片';

  @override
  String garden_fragment_cost(int count) {
    return '−$count 片';
  }

  @override
  String get garden_row_fragment_balance => '当前碎片';

  @override
  String garden_fragment_count(int count) {
    return '$count 片';
  }

  @override
  String garden_fragment_remaining(int count) {
    return '种下后剩余 $count 片';
  }

  @override
  String garden_sun_remaining(int count) {
    return '种下后剩余 $count ☀';
  }

  @override
  String get garden_unknown_plant => '未知植物';

  @override
  String garden_load_failed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get garden_title => '我的花园';

  @override
  String get garden_refresh_tooltip => '刷新成长';

  @override
  String get garden_rarity_common => '普通';

  @override
  String get garden_rarity_premium => '精英';

  @override
  String get garden_flip_back => '点此翻回正面';

  @override
  String get garden_action_water => '一键浇水';

  @override
  String get garden_action_fertilize => '一键施肥';

  @override
  String get garden_action_care => '一键护理';

  @override
  String get garden_oneclick_title => '一键操作';

  @override
  String get garden_help_sheet_title => '碎片与种子';

  @override
  String get garden_help_fragment_title => '植物碎片';

  @override
  String get garden_help_fragment_use => '种植植物时可以代替阳光支付（精英植物要用碎片兑换）。';

  @override
  String get garden_help_fragment_how => '植物开花时的奖励里随机掉落。';

  @override
  String get garden_help_common_seed_title => '普通植物种子';

  @override
  String get garden_help_common_seed_use => '免费种下一株普通植物，种下时优先使用（不用扣阳光）。';

  @override
  String get garden_help_common_seed_how => '普通植物开花后小概率掉落；重复的种子会自动变成碎片。';

  @override
  String get garden_help_premium_seed_title => '精英植物种子';

  @override
  String get garden_help_premium_seed_use => '免费种下一株精英植物，种下时优先使用（不用扣碎片）。';

  @override
  String get garden_help_premium_seed_how => '精英植物开花后小概率掉落；重复的种子会自动变成碎片。';

  @override
  String garden_help_use_prefix(Object text) {
    return '用途：$text';
  }

  @override
  String garden_help_how_prefix(Object text) {
    return '获得：$text';
  }

  @override
  String get shared_got_it => '知道啦';

  @override
  String shared_load_failed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get shared_retry => '重试';

  @override
  String get shared_refresh => '刷新';

  @override
  String get shared_cancel => '取消';

  @override
  String get shared_no_sunlight => '阳光不足';

  @override
  String get shared_week_quota_full => '本周额度已满';

  @override
  String get shared_redeem => '兑换';

  @override
  String get store_title => '阳光商店';

  @override
  String get store_empty_hint => '商店还没上架奖励，请让家长先添加奖励模板';

  @override
  String get store_confirm_title => '确认兑换？';

  @override
  String get store_row_item => '兑换物品';

  @override
  String get store_row_cost => '消耗阳光';

  @override
  String get store_row_available => '可用阳光';

  @override
  String get store_warning_redeem => '提交后需家长核销，核销通过才会扣除阳光。';

  @override
  String get store_confirm_ok => '确认兑换';

  @override
  String get store_confirm_think => '再想想';

  @override
  String get store_result_verified => '兑换成功！阳光已扣除';

  @override
  String get store_result_cooldown => '本周已领过啦';

  @override
  String get store_result_no_balance => '阳光不足，再去专注赚一些吧';

  @override
  String get store_result_pool_full => '本周额度已满，下周再来吧';

  @override
  String get store_pending_feedback => '已提交，等家长确认哦～';

  @override
  String store_pending_pill(int count) {
    return '待核销 $count';
  }

  @override
  String get store_celebration_text => '兑换成功！\n阳光已扣除';

  @override
  String task_checkin_failed(Object error) {
    return '打卡失败：$error';
  }

  @override
  String get task_feedback_pending => '已经告诉爸爸妈妈啦，等他们确认就发阳光 🌻';

  @override
  String task_feedback_cap(int cap) {
    return '今天的成长奖励已经拿满 $cap 啦，明天再来';
  }

  @override
  String task_feedback_capped(Object granted) {
    return '太棒了！+$granted 阳光（今日成长奖励已达上限，本次只到账 $granted）';
  }

  @override
  String task_feedback_granted(Object granted) {
    return '太棒了！+$granted 阳光';
  }

  @override
  String get task_perfect_title => '🌻 今日成长项全部完成！';

  @override
  String get task_perfect_footer => '你今天把全部成长项都做完啦，获得「完美日」标记！';

  @override
  String get task_perfect_ok => '太棒啦';

  @override
  String get task_empty_hint => '今天没有成长项，去玩吧 🌻';

  @override
  String get task_progress_title => '今日成长';

  @override
  String task_weekly_more(int count) {
    return '· 另有每周 $count 项';
  }

  @override
  String get task_badge_daily => '每日';

  @override
  String get task_badge_weekly => '每周';

  @override
  String task_info_focus(Object subject, int reward) {
    return '$subject · 需专注 · +$reward ☀';
  }

  @override
  String task_info_plain(Object subject, int reward) {
    return '$subject · +$reward ☀';
  }

  @override
  String get task_status_waiting => '等家长确认';

  @override
  String get task_status_done_focus => '已完成';

  @override
  String get task_status_done => '已做到';

  @override
  String get task_action_do => '我做';

  @override
  String get task_action_do2 => '到了';

  @override
  String get task_action_focus => '去专注';

  @override
  String task_focus_minutes(int count) {
    return '$count分钟';
  }

  @override
  String profile_balance_line(int count) {
    return '我的阳光：$count ☀';
  }

  @override
  String get profile_source_label => '来源';

  @override
  String get profile_achievements_title => '累计成就';

  @override
  String get profile_stat_focus_minutes => '累计专注时长';

  @override
  String profile_value_minutes(int count) {
    return '$count 分钟';
  }

  @override
  String get profile_stat_sessions => '累计专注次数';

  @override
  String profile_value_times(int count) {
    return '$count 次';
  }

  @override
  String get profile_stat_valid_days => '累计有效专注天数';

  @override
  String profile_value_days(int count) {
    return '$count 天';
  }

  @override
  String get profile_stat_checkins => '累计成长打卡';

  @override
  String get profile_stat_bloomed => '累计开花植物';

  @override
  String profile_value_plants(int count) {
    return '$count 株';
  }

  @override
  String get profile_stat_eyecare => '累计护眼';

  @override
  String get hist_title => '阳光来源记录';

  @override
  String get hist_empty_hint => '还没有阳光记录哦 🌻';

  @override
  String get hist_balance_label => '当前拥有阳光';

  @override
  String get hist_other => '其他';

  @override
  String hist_subtitle(Object time, int balance) {
    return '$time · 余额 $balance ☀';
  }

  @override
  String get card_stage_seed => '种子';

  @override
  String get card_stage_sprout => '幼苗';

  @override
  String get card_stage_adult => '成株';

  @override
  String get card_status_growing => '成长中';

  @override
  String get card_status_bloomed => '已开花 🌻';

  @override
  String get card_status_wilting => '枯萎中（快救回！）';

  @override
  String get card_status_dead => '已枯萎';

  @override
  String get card_mood_happy => '😊 今天有专注，我很开心';

  @override
  String get card_mood_calm => '😌 状态平稳';

  @override
  String get card_mood_thirsty => '🥵 有点口渴，该浇水啦';

  @override
  String get card_hint_bloomed => '已开花 🌻 每天养护，明天晨露阳光满额';

  @override
  String get card_hint_next_soon => '即将进入下一阶段…';

  @override
  String card_hint_progress(int percent) {
    return '本阶段成长 $percent%';
  }

  @override
  String card_hint_grow_days(int days) {
    return '每天按时养护，还需约 $days 天长成';
  }

  @override
  String card_hint_bloom_left(Object days) {
    return '花期剩余 $days 天';
  }

  @override
  String get card_action_shovel => '铲除';

  @override
  String get card_action_clear => '铲除回收';

  @override
  String get card_action_water => '浇水';

  @override
  String card_action_water_gain(Object gain) {
    return '浇水 +$gain%';
  }

  @override
  String get card_action_fertilize => '施肥';

  @override
  String card_action_fertilize_gain(Object gain) {
    return '施肥 +$gain%';
  }

  @override
  String card_quota_left(int water, int waterMax, int fert, int fertMax) {
    return '今日剩余：浇水 $water/$waterMax 次 · 施肥 $fert/$fertMax 次';
  }

  @override
  String get card_wilt_easy => '浇水 1 次即可救回';

  @override
  String card_wilt_hard(int water, int fert) {
    return '需浇水 $water 次 + 施肥 $fert 次才能救回';
  }

  @override
  String care_shovel_title(Object name) {
    return '要铲除「$name」吗？';
  }

  @override
  String get care_this_plant => '这株植物';

  @override
  String get care_shovel_warning => '铲除后这株植物会消失。';

  @override
  String get care_row_refund => '返还种植阳光';

  @override
  String get care_note_no_refund_water => '浇水施肥的阳光不返还';

  @override
  String get care_note_no_refund => '本次铲除不返还阳光';

  @override
  String get care_confirm_shovel => '确定铲除';

  @override
  String get care_gone_hint => '这株植物已经不在花园里啦';

  @override
  String get care_footer_hint =>
      '植物也会随时间自然生长，按时养护才能早点开花 🌻\n盛开后每天浇 1 次水或施 1 次肥，第二天晨露阳光才是满额 🌻\n（忘了也会掉落，只是阳光减半 —— 不会一点都没有）';

  @override
  String plant_confirm_title(Object name) {
    return '要种下$name吗？';
  }

  @override
  String get plant_confirm_ok => '确定种植';

  @override
  String pot_tooltip_weed(int count) {
    return '有杂草，点我拔掉 +$count ☀';
  }

  @override
  String pot_tooltip_pest(int count) {
    return '有害虫，点我除掉 +$count ☀';
  }

  @override
  String pot_label_bloomed(Object name) {
    return '$name · 开花';
  }

  @override
  String pot_label_wilting(Object name) {
    return '$name · 快救回';
  }

  @override
  String pot_label_dead(Object name) {
    return '$name · 已枯萎';
  }

  @override
  String get pot_label_locked => '需解锁';

  @override
  String pot_label_expand(int cost) {
    return '加盆 · $cost☀';
  }

  @override
  String pot_label_shortfall(int count) {
    return '还差 $count☀';
  }

  @override
  String get ghelp_title => '玩法说明';

  @override
  String get ghelp_earn_title => '怎么挣阳光';

  @override
  String ghelp_earn_detail(int perMinute, int taskReward) {
    return '白天专注就能挣阳光：每分钟 +$perMinute ☀；\n完成成长任务打卡，每项还 +$taskReward ☀。';
  }

  @override
  String get ghelp_use_title => '阳光能干什么';

  @override
  String ghelp_use_detail(int waterCost, int fertCost) {
    return '在花园种植物（点空花盆选一株，花 ☀ 种下）；\n给植物浇水 $waterCost ☀/次起、施肥 $fertCost ☀/次起；\n也可以去「商店」兑换喜欢的奖励。';
  }

  @override
  String get ghelp_grow_title => '植物怎么长大';

  @override
  String ghelp_grow_detail(int waterGain, int fertGain, int waterMax,
      int fertMax, int interval, int bloomDays) {
    return '不照顾也会随时间自己长大；浇水 +$waterGain%、施肥 +$fertGain% 长得更快\n（花谢后重新养时增量会小一些，看按钮上的实际数字；\n每天最多浇 $waterMax 次、施 $fertMax 次，两次浇水要隔 $interval 分钟）；\n进度养满就开花，开满 $bloomDays 天后花谢，再养满又能再开 🌻';
  }

  @override
  String get ghelp_wilt_title => '别让植物枯萎';

  @override
  String ghelp_wilt_detail(int wiltDays, int deathDays) {
    return '浇水或施肥能刷新计时；$wiltDays 天没浇水就会枯萎，\n枯萎后再拖 $deathDays 天就会枯死。记得常来看看它 🌱';
  }

  @override
  String get ghelp_task_title => '任务打卡与家长核销';

  @override
  String get ghelp_task_detail =>
      '成长任务有两种：\n「开始专注」的任务，达标后自动结算阳光；\n「我做到了」的任务，先记成「等家长确认」，\n爸爸妈妈核销通过后，阳光才真正到账。';

  @override
  String get ghelp_capacity_title => '花园容量';

  @override
  String ghelp_capacity_detail(int capacity, int max) {
    return '$capacity / $max 盆';
  }

  @override
  String get ghelp_expand_title => '扩容';

  @override
  String ghelp_expand_detail(int cost, int max) {
    return '点「+」格，花 $cost ☀ 可以多一个花盆（上限 $max 盆）';
  }

  @override
  String get prd_pending_reminder => '这次的阳光奖励还在等你确认哦～';

  @override
  String get prd_avatar_locked_hint => '种下这种植物后可以选它当头像';

  @override
  String get prd_eyecare_not_skippable => '不可跳过，请爱护眼睛';

  @override
  String get prd_eyecare_finish => '跳过护眼休息';

  @override
  String get prd_eyecare_early_title => '还没休息完就结束吗？';

  @override
  String get prd_eyecare_early_body =>
      '护眼还没做完，现在结束就没有小阳光奖励哦。小眼睛要多休息才会亮晶晶，再坚持一下吧！';

  @override
  String get prd_eyecare_early_stay => '再休息一会儿';

  @override
  String get prd_eyecare_early_quit => '确定结束';

  @override
  String get prd_level_locked_title => '尚未解锁称号';

  @override
  String get prd_level_detail_ok => '知道了';

  @override
  String get prd_premium_upsell_hint => '请升级到完整版本功能';

  @override
  String get fx_level_up_title => '解锁新称号！';

  @override
  String get fx_level_up_level_title => '升级啦！';

  @override
  String fx_level_up_multi(int n) {
    return '连升 $n 个称号！';
  }

  @override
  String fx_level_up_level_multi(int n) {
    return '连升 $n 级！';
  }

  @override
  String fx_level_up_perk(Object text) {
    return '本称号专属：$text';
  }

  @override
  String get fx_level_up_perk_locked => ' · 🔒付费解锁';
}
