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
  String child_lock_body(int hour) {
    return '晚上 $hour:00 后向日葵要休息啦，明天再陪你专注~';
  }

  @override
  String get child_rest_title => '休息一下';

  @override
  String child_rest_body(int sec) {
    return '休息一下，喝口水～ 还剩 $sec 秒';
  }

  @override
  String get child_rest_done => '我休息好了';

  @override
  String child_eyecare_countdown(int sec) {
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
  String child_today_minutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String child_today_focus_count(int count) {
    return '· $count 次';
  }

  @override
  String get child_today_growth_label => '今日成长';

  @override
  String get child_today_all_done => '全部完成 🌻';

  @override
  String get child_today_growth_hint => '想赚成长阳光？从「成长」里点具体项目开始专注 🌻';

  @override
  String child_settle_secs(int sec) {
    return '$sec 秒';
  }

  @override
  String child_settle_mins(int min) {
    return '$min 分钟';
  }

  @override
  String child_settle_min_sec(int min, int sec) {
    return '$min 分 $sec 秒';
  }

  @override
  String get child_settle_task_label => '成长项';

  @override
  String get child_settle_task_skipped => '成长项结算没能完成，不影响本次专注阳光';

  @override
  String child_settle_task_capped(String sun) {
    return '（今日阳光已达上限，本次只到账 $sun ☀）';
  }

  @override
  String child_settle_task_done(String capped, String name, String sun) {
    return '成长项「$name」完成 +$sun ☀$capped';
  }

  @override
  String child_settle_task_progress(String name) {
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
  String child_settle_cap_body_detail(String cheer, String detail) {
    return '超出额度的部分就不再收集阳光了$detail。$cheer';
  }

  @override
  String child_settle_cap_orig_vs_net(String net, String raw) {
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
  String child_cap_single_body(int minutes) {
    return '已经连续玩 $minutes 分钟啦，让眼睛休息一下';
  }

  @override
  String get child_cap_daily_body => '今天逛 App 的时间用完啦';

  @override
  String get child_cap_chip_rest => '休息一会';

  @override
  String get child_cap_chip_daily => '今日上限';

  @override
  String child_cap_unlock_in(int minutes) {
    return '$minutes 分钟后解锁';
  }

  @override
  String child_cap_minutes(int minutes) {
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
  String child_entry_cap_daily(int cap) {
    return '今天的专注时间已经用完啦（每日上限 $cap 分钟），明天再来';
  }

  @override
  String child_entry_remaining_today(int cap, int minutes) {
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
  String child_entry_custom_hint_max(int max) {
    return '可选 $max 分钟以内';
  }

  @override
  String child_entry_custom_hint_capped(int max) {
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
  String child_entry_minutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String child_entry_cap_snack(int cap) {
    return '今日专注已达上限（$cap 分钟），明天再来哦';
  }

  @override
  String child_entry_cap_snack2(int cap) {
    return '今天的专注时间用完啦（上限 $cap 分钟），明天再来哦';
  }

  @override
  String child_entry_remaining_snack(int minutes, int remaining) {
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
  String child_shell_item_cost(int sun) {
    return '-$sun 阳光';
  }

  @override
  String child_shell_verify_total(int total) {
    return '共扣除 $total 阳光';
  }

  @override
  String get child_shell_reject_title => '🚫 兑换未被通过';

  @override
  String child_shell_reject_subtitle(String note) {
    return '（$note）';
  }

  @override
  String get child_shell_reject_reason => '家长拒绝了该申请';

  @override
  String get child_shell_reject_footer => '本次阳光未被扣除，可重新兑换其他奖励';

  @override
  String get child_shell_task_footer_capped => '今日成长奖励已达上限，本次没有新增阳光';

  @override
  String child_shell_task_footer_partial(int capped, int total) {
    return '共获得 $total 阳光（$capped 项今日额度已满，未发放）';
  }

  @override
  String child_shell_task_footer(int total) {
    return '共获得 $total 阳光';
  }

  @override
  String get child_shell_task_title => '🎉 家长已确认你的成长任务';

  @override
  String get child_shell_task_fallback => '成长任务';

  @override
  String child_shell_task_item_sun(int sun) {
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

  @override
  String get shared_edit => '编辑';

  @override
  String get shared_delete => '删除';

  @override
  String get parent_home_title => '家长天地';

  @override
  String get parent_home_back_tooltip => '返回孩子端';

  @override
  String get parent_home_tab_today => '今日';

  @override
  String get parent_home_tab_reward => '奖励';

  @override
  String get parent_home_tab_growth => '成长';

  @override
  String get parent_home_tab_history => '记录';

  @override
  String get parent_home_tab_settings => '设置';

  @override
  String get parent_login_enter_pin => '请输入家长 PIN';

  @override
  String get parent_login_setup_pin => '首次进入，请设置家长 PIN';

  @override
  String get parent_login_btn_enter => '进入';

  @override
  String get parent_login_btn_setup => '设置并进入';

  @override
  String get parent_login_err_short => 'PIN 至少 4 位';

  @override
  String get parent_login_err_wrong => 'PIN 不正确';

  @override
  String get parent_delete_title => '删除入口';

  @override
  String get parent_delete_right_title => '数据删除权（§10.4 C5）';

  @override
  String get parent_delete_right_body => '你拥有删除全部本地数据的权利。删除后所有进度与设置将不可恢复。';

  @override
  String get parent_delete_dlg_title => '删除全部本地数据？';

  @override
  String get parent_delete_dlg_body =>
      '此操作将永久删除：专注记录、阳光账本、植物、成长项、奖励模板、家长 PIN 与所有本地设置，且无法恢复。\n\n建议先「导出成册」留存（导出功能将在 V2 上线）。';

  @override
  String get parent_delete_btn_ok => '确认删除';

  @override
  String get parent_delete_btn_export => '导出成册（V2 上线）';

  @override
  String get parent_delete_export_snack => '导出成册功能将在 V2 上线，请先截图留存';

  @override
  String get parent_delete_btn_all => '删除全部本地数据';

  @override
  String get parent_delete_btn_deleting => '删除中…';

  @override
  String get parent_delete_done_snack => '已删除全部本地数据';

  @override
  String parent_delete_fail_snack(Object error) {
    return '删除失败：$error';
  }

  @override
  String get parent_today_unknown_reward => '未知奖励';

  @override
  String get parent_today_empty => '暂无待确认奖励 🎉';

  @override
  String get parent_today_pending_title => '待确认的成长项';

  @override
  String parent_today_count(int count) {
    return '$count 项';
  }

  @override
  String get parent_today_deleted_task => '（已删除的成长项）';

  @override
  String parent_today_submitted_at(Object time) {
    return '提交于 $time';
  }

  @override
  String parent_today_should_grant(String sun) {
    return '应发 $sun 阳光';
  }

  @override
  String get parent_today_btn_confirm => '确认发放';

  @override
  String get parent_today_btn_reject => '驳回';

  @override
  String get parent_today_reject_title => '驳回这项成长？';

  @override
  String parent_today_reject_body(String name) {
    return '将不发放「$name」的阳光。';
  }

  @override
  String get parent_today_reject_reason => '理由（选填）';

  @override
  String get parent_today_reject_ok => '确认驳回';

  @override
  String parent_today_confirm_ok_snack(String sun, String capped) {
    return '已确认发放，+$sun 阳光 🌻$capped';
  }

  @override
  String parent_today_capped_note(String sun) {
    return '（今日成长奖励已达上限，本次只到账 $sun ☀）';
  }

  @override
  String parent_today_confirm_fail_snack(Object error) {
    return '确认失败：$error';
  }

  @override
  String get parent_today_rejected_snack => '已驳回 🌞 这项不会发阳光';

  @override
  String parent_today_reject_fail_snack(Object error) {
    return '驳回失败：$error';
  }

  @override
  String get parent_today_debug_cap_title => '🧪 调试：跳过 30 分钟限时';

  @override
  String get parent_today_debug_cap_subtitle =>
      '调试期间默认开启（不进限时状态）；关闭后恢复防沉迷拦截。仅调试包可见。';

  @override
  String get parent_today_debug_cap_on_snack => '已跳过 30 分钟限时（调试）';

  @override
  String get parent_today_debug_cap_off_snack => '已恢复 30 分钟限时拦截';

  @override
  String get parent_today_debug_save_fail_snack => '保存失败，请重试';

  @override
  String get parent_verify_cat_self_service => '自服务';

  @override
  String get parent_verify_cat_parent_handled => '家长经手';

  @override
  String parent_verify_cost(int cost) {
    return '$cost 阳光';
  }

  @override
  String parent_verify_meta(String category, String time) {
    return '分类：$category · 申请于 $time';
  }

  @override
  String parent_verify_queue_note(Object pos) {
    return '排队第 $pos 位 · 下月自动释放';
  }

  @override
  String get parent_verify_confirm_title => '确认核销？';

  @override
  String parent_verify_confirm_body(String name, int cost) {
    return '确认为「$name」核销 $cost 阳光？\n核销后将立即从孩子阳光中扣除，且不可撤销。';
  }

  @override
  String get parent_verify_confirm_ok => '确认核销';

  @override
  String get parent_verify_reject_title => '确认拒绝？';

  @override
  String parent_verify_reject_body(String name, int cost) {
    return '拒绝「$name」（$cost 阳光）后将不核销该奖励。\n待核销期间阳光从未被扣除，故孩子阳光不受影响。\n此操作不可撤销。';
  }

  @override
  String get parent_verify_reject_ok => '确认拒绝';

  @override
  String get parent_verify_verified_snack => '已确认兑换 🎉 阳光已扣除';

  @override
  String parent_verify_verify_fail_snack(Object error) {
    return '核销失败：$error';
  }

  @override
  String get parent_verify_rejected_snack => '已拒绝该兑换 🌞 阳光未被扣除';

  @override
  String parent_verify_reject_fail_snack(Object error) {
    return '拒绝失败：$error';
  }

  @override
  String get parent_verify_release_title => '立即发放？';

  @override
  String parent_verify_release_body(String name, int cost) {
    return '确认为「$name」立即发放 $cost 阳光？\n将跳过排队等待，立即从孩子阳光中扣除。';
  }

  @override
  String get parent_verify_release_ok => '立即发放';

  @override
  String get parent_verify_released_snack => '已立即发放 🎉 阳光已扣除';

  @override
  String parent_verify_release_state_fail_snack(Object error) {
    return '无法立即发放：$error';
  }

  @override
  String parent_verify_release_fail_snack(Object error) {
    return '发放失败：$error';
  }

  @override
  String get parent_task_edit_title_new => '新增成长项';

  @override
  String get parent_task_edit_title_edit => '编辑成长项';

  @override
  String get parent_task_edit_name_label => '成长项名称';

  @override
  String get parent_task_edit_subject_label => '科目';

  @override
  String get parent_task_edit_subject_general => '通用';

  @override
  String get parent_task_edit_subject_chinese => '语文';

  @override
  String get parent_task_edit_subject_math => '数学';

  @override
  String get parent_task_edit_subject_english => '英语';

  @override
  String get parent_task_edit_subject_custom => '自定义…';

  @override
  String get parent_task_edit_custom_label => '自定义科目名称';

  @override
  String get parent_task_edit_custom_hint => '例如：科学 / 书法 / 编程';

  @override
  String get parent_task_edit_category_label => '分类';

  @override
  String get parent_task_edit_link_title => '专注联动（自动结算）';

  @override
  String get parent_task_edit_link_subtitle =>
      '勾选后，孩子从这一项点「开始专注」，达标会自动完成并发放阳光，无需手动打卡。';

  @override
  String get parent_task_edit_min_focus_label => '最少专注';

  @override
  String parent_task_edit_minutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String parent_task_edit_reward_fixed(int minutes, int cap) {
    return '奖励固定 = 专注 $minutes 分钟 × 40% = $cap ☀（无需调整）';
  }

  @override
  String get parent_task_edit_reward_label => '阳光奖励';

  @override
  String parent_task_edit_reward_slider(int reward) {
    return '$reward 阳光';
  }

  @override
  String parent_task_edit_reward_range(int min, int max, int def) {
    return '区间 $min–$max ☀（默认 $def）';
  }

  @override
  String get parent_task_edit_repeat_label => '重复规则';

  @override
  String get parent_task_edit_repeat_none => '不重复';

  @override
  String get parent_task_edit_repeat_daily => '每天';

  @override
  String get parent_task_edit_repeat_weekly => '每周';

  @override
  String get parent_task_edit_err_name => '请填写成长项名称';

  @override
  String parent_task_edit_err_reward(int min, int max) {
    return '阳光奖励需在 $min–$max 之间';
  }

  @override
  String get parent_task_edit_err_subject => '请填写自定义科目名称';

  @override
  String parent_task_edit_err_save(Object error) {
    return '保存失败：$error';
  }

  @override
  String get parent_task_edit_btn_save => '保存';

  @override
  String get parent_task_config_title => '成长配置';

  @override
  String get parent_task_config_list_title => '成长任务';

  @override
  String get parent_task_config_empty => '还没有成长项，点右上角「新增成长项」创建一个吧';

  @override
  String get parent_task_config_delete_title => '删除成长项？';

  @override
  String parent_task_config_delete_body(String name) {
    return '确定删除「$name」？已生成的打卡记录会保留。';
  }

  @override
  String parent_task_config_focus_pill(int minutes) {
    return '专注 $minutes 分';
  }

  @override
  String get parent_reward_templates_title => '奖励模板';

  @override
  String get parent_reward_btn_add => '新增奖励';

  @override
  String parent_reward_quota_hint(String reason) {
    return '$reason，删除多余条目后即可新增';
  }

  @override
  String get parent_reward_edit_hint =>
      '点按某条可编辑名称/价格/分类；右侧垃圾桶可删除。改动会同步到孩子端阳光商店。';

  @override
  String get parent_reward_empty => '暂无奖励模板，点「新增奖励」创建';

  @override
  String get parent_reward_delete_title => '删除奖励';

  @override
  String parent_reward_delete_body(String name) {
    return '确定删除「$name」？孩子端阳光商店将不再展示该奖励。';
  }

  @override
  String get parent_reward_edit_title_new => '新增奖励';

  @override
  String get parent_reward_edit_title_edit => '编辑奖励';

  @override
  String get parent_reward_name_label => '奖励名称';

  @override
  String get parent_reward_err_required => '必填';

  @override
  String get parent_reward_cat_self_full => '自服务（看电视/玩平板）';

  @override
  String get parent_reward_content_label => '内容分类';

  @override
  String get parent_reward_cost_label => '阳光价格';

  @override
  String get parent_reward_err_positive => '请输入正整数';

  @override
  String get parent_reward_freq_label => '每周限领次数';

  @override
  String get parent_reward_err_nonneg => '请输入非负整数';

  @override
  String get parent_reward_cooldown_label => '冷却规则';

  @override
  String get parent_reward_cooldown_none => '无冷却';

  @override
  String get parent_reward_cooldown_weekly => '每周限领';

  @override
  String get parent_reward_cooldown_monthly => '每月限领';

  @override
  String get parent_reward_pool_title => '本周阳光预算';

  @override
  String get parent_reward_pool_unit => '阳光';

  @override
  String parent_reward_pool_used_line(int used, int budget) {
    return '已用 $used / 共 $budget 阳光';
  }

  @override
  String parent_reward_pool_unlimited_line(int used) {
    return '本周不限额，已用 $used 阳光（兑换只受阳光余额约束）';
  }

  @override
  String parent_reward_pool_default_note(int low, int mid, String high) {
    return '每周兑换额度默认值：低年级 $low☀ · 中年级 $mid☀ · 高年级$high（兑换只受阳光余额约束）';
  }

  @override
  String parent_reward_pool_load_failed(Object error) {
    return '周阳光池加载失败：$error';
  }

  @override
  String get parent_settings_section_screentime => '防沉迷与作息';

  @override
  String get parent_settings_switch_quiet => '免打扰模式';

  @override
  String get parent_settings_night_title => '夜间边界';

  @override
  String parent_settings_night_subtitle(String time) {
    return '$time 起进入夜间（夜锁生效时间）';
  }

  @override
  String get parent_settings_daily_focus_cap => '每日专注上限（分钟）';

  @override
  String get parent_settings_daily_app_cap => '每日花园、商店使用时长（分钟）';

  @override
  String get parent_settings_rest_after => '每 N 次专注后休息';

  @override
  String get parent_settings_rest_minutes => '休息时长（分钟）';

  @override
  String get parent_settings_section_eyecare => '护眼休息';

  @override
  String get parent_settings_switch_eyecare => '护眼提醒';

  @override
  String get parent_settings_eyecare_subtitle =>
      '专注每满一定时间弹出护眼卡，帮孩子歇歇眼睛（固定 60 秒）';

  @override
  String get parent_settings_eyecare_interval => '护眼触发间隔（每 N 分钟）';

  @override
  String get parent_settings_switch_eyecare_skip => '允许孩子跳过护眼';

  @override
  String get parent_settings_eyecare_skip_subtitle => '关掉后孩子只能完成休息，跳过按钮不生效';

  @override
  String get parent_settings_section_sound => '环境与音效';

  @override
  String get parent_settings_switch_sound => '音效';

  @override
  String get parent_settings_switch_bgm => '背景音乐';

  @override
  String get parent_settings_switch_dark => '深色主题';

  @override
  String get parent_settings_section_lock => '家长锁与赠予';

  @override
  String get parent_settings_reset_pin => '重设家长 PIN';

  @override
  String get parent_settings_grant_title => '赠予阳光';

  @override
  String parent_settings_grant_subtitle(Object daily, Object monthly) {
    return '日上限 $daily / 月上限 $monthly';
  }

  @override
  String get parent_settings_section_data => '数据与隐私';

  @override
  String get parent_settings_entry_delete => '删除入口';

  @override
  String get parent_settings_entry_delete_sub => '删除全部本地数据（§10.4 C5）';

  @override
  String get parent_settings_section_debug => '调试（仅 Debug 构建）';

  @override
  String get parent_settings_pin_dlg_title => '重设家长 PIN';

  @override
  String get parent_settings_pin_dlg_old => '当前 PIN';

  @override
  String get parent_settings_pin_dlg_new => '新 PIN（≥4 位）';

  @override
  String get parent_settings_pin_dlg_ok => '重设';

  @override
  String get parent_settings_pin_too_short_snack => '新 PIN 至少 4 位';

  @override
  String get parent_settings_pin_wrong_snack => '当前 PIN 不正确';

  @override
  String get parent_settings_pin_ok_snack => 'PIN 已重设';

  @override
  String get parent_settings_gift_dlg_title => '赠予阳光';

  @override
  String parent_settings_gift_daily_line(int given, int daily, int remain) {
    return '今日已赠 $given / $daily ☀，还可赠 $remain ☀';
  }

  @override
  String parent_settings_gift_monthly_line(int given, int monthly, int remain) {
    return '本月已赠 $given / $monthly ☀，还可赠 $remain ☀';
  }

  @override
  String get parent_settings_gift_amount_label => '赠予数量';

  @override
  String get parent_settings_gift_err_positive => '请输入正数';

  @override
  String parent_settings_gift_err_over(int max, int day, int month) {
    return '最多可赠 $max ☀（今日剩 $day / 本月剩 $month）';
  }

  @override
  String get parent_settings_gift_btn => '赠予';

  @override
  String parent_settings_gift_daily_cap_snack(int daily) {
    return '今日赠予已达上限（$daily ☀/天），明天再来';
  }

  @override
  String parent_settings_gift_monthly_cap_snack(int monthly) {
    return '本月赠予已达上限（$monthly ☀/月）';
  }

  @override
  String parent_settings_gift_over_snack(int remain) {
    return '超出赠予上限，未赠予（今日剩 $remain ☀）';
  }

  @override
  String parent_settings_gift_ok_snack(int amount, int remain) {
    return '已赠予 $amount ☀，孩子端已到账（今日剩 $remain ☀）';
  }

  @override
  String get parent_settings_debug_member_title => '会员模式（仅调试）';

  @override
  String get parent_settings_debug_member_subtitle => '打开即解锁全部付费功能；重启 App 后失效';

  @override
  String get parent_profile_tier_low => '低年级 · 8 岁及以下';

  @override
  String get parent_profile_tier_mid => '中年级 · 9–12 岁';

  @override
  String get parent_profile_tier_high => '高年级 · 13 岁及以上';

  @override
  String get parent_profile_menu_edit => '编辑';

  @override
  String get parent_profile_menu_delete => '删除';

  @override
  String get parent_profile_menu_create => '新建孩子';

  @override
  String parent_profile_toast_switched(String name) {
    return '已切换到「$name」';
  }

  @override
  String parent_profile_toast_added(String name) {
    return '已添加「$name」';
  }

  @override
  String parent_profile_toast_updated(String name) {
    return '已更新「$name」';
  }

  @override
  String parent_profile_toast_deleted(String name) {
    return '已删除「$name」';
  }

  @override
  String parent_profile_max_toast(int count) {
    return '最多支持 $count 个孩子账户';
  }

  @override
  String get parent_profile_min_toast => '至少保留一个孩子档案';

  @override
  String get parent_profile_create_title => '新建孩子';

  @override
  String get parent_profile_edit_title => '编辑孩子';

  @override
  String get parent_profile_name_label => '孩子名字';

  @override
  String get parent_profile_name_hint => '比如：小向日葵';

  @override
  String get parent_profile_btn_create => '创建';

  @override
  String parent_profile_delete_title(String name) {
    return '删除「$name」？';
  }

  @override
  String get parent_profile_delete_body => '删除后该孩子的档案设置将被移除，且无法恢复。';

  @override
  String get parent_profile_pin_label => '家长 PIN';

  @override
  String get parent_profile_pin_err_empty => '请输入家长 PIN';

  @override
  String get parent_profile_pin_err_wrong => 'PIN 不正确，请重试';

  @override
  String get parent_history_seg_report => '专注报告';

  @override
  String get parent_history_seg_activity => '任务与奖励';

  @override
  String get parent_hist_section_tasks => '成长任务完成记录';

  @override
  String parent_hist_task_tail(int count) {
    return '共 $count 次';
  }

  @override
  String get parent_hist_empty_tasks => '本期间还没有成长项完成记录';

  @override
  String get parent_hist_section_rewards => '奖励兑换记录';

  @override
  String parent_hist_reward_tail(int count, int cost) {
    return '共 $count 次 · 消耗 $cost 阳光';
  }

  @override
  String get parent_hist_empty_rewards => '本期间还没有奖励兑换记录';

  @override
  String get parent_hist_deleted_task => '（已删除的成长项）';

  @override
  String get parent_hist_deleted_reward => '（已删除的奖励）';

  @override
  String parent_hist_done_badge(int count) {
    return '完成 $count 次';
  }

  @override
  String parent_hist_redeem_badge(int count) {
    return '兑换 $count 次';
  }

  @override
  String parent_hist_range_multi(String first, String last) {
    return '首次 $first ～ 最近 $last';
  }

  @override
  String parent_hist_cost_line(String range, int cost) {
    return '$range · 消耗 $cost 阳光';
  }

  @override
  String get parent_hist_summary_done => '本期完成成长项';

  @override
  String get parent_hist_summary_redeem => '本期兑换奖励';

  @override
  String get parent_hist_summary_cost => '本期消耗阳光';

  @override
  String get parent_report_error_hint => '报告生成失败，请下拉重试';

  @override
  String get parent_report_period_day => '日';

  @override
  String get parent_report_period_week => '周';

  @override
  String get parent_report_period_month => '月';

  @override
  String get parent_report_period_year => '年';

  @override
  String get parent_report_prev_tooltip => '上一期间';

  @override
  String get parent_report_next_tooltip => '下一期间';

  @override
  String get parent_report_hero_title => '本期间专注';

  @override
  String parent_report_minutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String parent_report_valid_days(int days) {
    return '有效专注日 $days 天';
  }

  @override
  String parent_report_avg_daily(int minutes) {
    return '平均每日 $minutes 分钟';
  }

  @override
  String get parent_report_trend_day => '近 7 日专注分布';

  @override
  String get parent_report_trend_week => '本周专注分布';

  @override
  String get parent_report_trend_month => '本月专注分布（按周）';

  @override
  String get parent_report_trend_year => '本年专注分布（按月）';

  @override
  String get parent_report_stability_title => '专注稳定性 · 近 4 周';

  @override
  String get parent_report_heatmap_title => '专注热力图 · 近 1 年';

  @override
  String get parent_report_eyecare_title => '护眼统计';

  @override
  String get parent_report_eyecare_loading => '护眼统计读取中…';

  @override
  String get parent_report_trend_empty => '本期间还没有专注记录。陪孩子完成一次 15 分钟专注，这里就会亮起来。';

  @override
  String parent_report_label_today(String date) {
    return '今天 · $date';
  }

  @override
  String parent_report_label_yesterday(String date) {
    return '昨天 · $date';
  }

  @override
  String parent_report_label_range(String start, String end) {
    return '$start ～ $end';
  }

  @override
  String parent_report_label_month(int year, int month) {
    return '$year 年 $month 月';
  }

  @override
  String parent_report_label_year(int year) {
    return '$year 年';
  }

  @override
  String get parent_report_wd_mon => '一';

  @override
  String get parent_report_wd_tue => '二';

  @override
  String get parent_report_wd_wed => '三';

  @override
  String get parent_report_wd_thu => '四';

  @override
  String get parent_report_wd_fri => '五';

  @override
  String get parent_report_wd_sat => '六';

  @override
  String get parent_report_wd_sun => '日';

  @override
  String get parent_report_heat_empty => '近 1 年还没有专注记录。';

  @override
  String parent_report_heat_tip(String date, int minutes) {
    return '$date · $minutes 分钟';
  }

  @override
  String parent_report_month_tick(int month) {
    return '$month月';
  }

  @override
  String get parent_report_legend_less => '少';

  @override
  String get parent_report_legend_more => '多';

  @override
  String parent_report_streak_current(int days) {
    return '当前连续 $days 天';
  }

  @override
  String parent_report_streak_longest(int days) {
    return '最长连续 $days 天';
  }

  @override
  String get parent_report_stability_empty => '近 4 周还没有专注记录。';

  @override
  String parent_report_weeks_ago(int count) {
    return '$count 周前';
  }

  @override
  String get parent_report_week_this => '本周';

  @override
  String parent_report_stability_score(int percent) {
    return '稳定性 $percent%';
  }

  @override
  String get parent_report_upsell_title => '解锁深度专注报告';

  @override
  String get parent_report_upsell_subtitle => '近 4 周稳定性 · 全年热力图';

  @override
  String get parent_report_eyecare_completed => '完成护眼';

  @override
  String get parent_report_eyecare_skipped => '跳过护眼';

  @override
  String get parent_report_eyecare_duration => '累计护眼时长';

  @override
  String get parent_report_eyecare_rate => '跳过率';

  @override
  String parent_report_times(int count) {
    return '$count 次';
  }

  @override
  String parent_report_secs(int count) {
    return '$count 秒';
  }

  @override
  String parent_report_minutes_1f(String value) {
    return '$value 分钟';
  }

  @override
  String parent_report_eyecare_skip_note(int count) {
    return '有 $count 次护眼被跳过（跳过的观看时长已如实计入）。';
  }

  @override
  String get premium_table_free_pill => '免费版';

  @override
  String get premium_table_gold_pill => '解锁全部功能 ★';

  @override
  String get premium_table_owned => '已拥有';

  @override
  String get premium_table_band_free => '免费就能用';

  @override
  String get premium_table_band_unlock => '买断后解锁';

  @override
  String get premium_table_row_pomodoro => '专注番茄钟';

  @override
  String get premium_table_row_screentime => '防沉迷与作息';

  @override
  String get premium_table_row_eyecare => '少儿护眼休息';

  @override
  String get premium_table_row_garden => '花园养成';

  @override
  String get premium_table_row_economy => '阳光经济与账本';

  @override
  String get premium_table_row_store => '商店兑换';

  @override
  String get premium_table_row_levels => '专注等级 + 9 称号';

  @override
  String get premium_table_row_report => '家长专注报告';

  @override
  String get premium_table_report_days => '近 7 天';

  @override
  String get premium_table_footnote_report => '更多报告能力开发中';

  @override
  String get premium_table_row_one_click => '花园「一键操作」';

  @override
  String get premium_table_row_pots => '花盆上限';

  @override
  String get premium_table_row_tasks => '成长项模板';

  @override
  String get premium_table_row_rewards => '奖励模板';

  @override
  String get premium_table_row_perks => '称号属性';

  @override
  String premium_table_free_pots(int count) {
    return '$count 个';
  }

  @override
  String premium_table_free_items(int count) {
    return '$count 条';
  }

  @override
  String get premium_table_unlimited => '✓ 不限';

  @override
  String premium_table_max(int count) {
    return '最多 $count';
  }

  @override
  String get premium_table_pots_note => '扩容仍需花阳光';

  @override
  String premium_table_perks_count(int count) {
    return '✓ $count 条';
  }

  @override
  String premium_quota_inline_reason(String limit, int count) {
    return '免费上限 $limit（当前 $count）';
  }

  @override
  String get parent_premium_title => '解锁全部功能';

  @override
  String get parent_premium_hero_subtitle => '一次买断 · 永久解锁，陪孩子一起专注成长';

  @override
  String get parent_premium_pill_unlocked => '已解锁';

  @override
  String get parent_premium_pill_locked => '未解锁';

  @override
  String get parent_premium_gold_pill => '一次买断 · 永久';

  @override
  String get parent_premium_unavailable_title => '暂时连不上商店';

  @override
  String get parent_premium_unavailable_body =>
      '现在无法获取商品信息，不影响你继续使用 App 的其他功能。请检查网络后再试。';

  @override
  String get parent_premium_btn_unlocked_done => '已解锁 · 感谢支持';

  @override
  String get parent_premium_btn_buying => '购买中…';

  @override
  String get parent_premium_btn_unavailable => '暂不可购买';

  @override
  String parent_premium_btn_unlock_now(String price) {
    return '立即解锁 · $price';
  }

  @override
  String get parent_premium_restoring => '恢复中…';

  @override
  String get parent_premium_restore => '恢复购买';

  @override
  String get parent_premium_notes_title => '购买前请知悉';

  @override
  String get parent_premium_note_1 => '一次买断、永久解锁 —— 不是订阅，不会自动续费。';

  @override
  String get parent_premium_note_2 => '同一 Apple ID 换手机 / 卸载重装后，点「恢复购买」即可找回。';

  @override
  String get parent_premium_note_3 =>
      '⚠️ 在 iOS 上购买的内容，无法在 Android 设备上「恢复购买」（反之亦然）。';

  @override
  String get parent_premium_note_4 =>
      '支付通过 Apple App Store 完成，开发者不会接触到你的任何支付信息。';

  @override
  String get parent_premium_snack_unlocked => '已解锁，感谢支持 🌻';

  @override
  String get parent_premium_snack_incomplete => '购买未完成，可稍后再试';

  @override
  String get parent_premium_snack_buy_failed => '购买失败，请稍后重试';

  @override
  String get parent_premium_snack_restored => '已恢复购买，欢迎回来 🌻';

  @override
  String get parent_premium_snack_nothing => '没有找到可恢复的购买记录';

  @override
  String get parent_premium_snack_restore_net => '恢复失败，请检查网络后重试';

  @override
  String get parent_premium_snack_restore_failed => '恢复失败，请稍后重试';

  @override
  String get parent_reward_category_label => '分类';

  @override
  String get shared_lang_zh_name => '简体中文';

  @override
  String get shared_task_category_other => '其他';

  @override
  String get shared_task_category_learning => '学习';

  @override
  String get shared_task_category_sports => '运动';

  @override
  String get shared_task_category_life => '生活';

  @override
  String get shared_task_category_habit => '习惯';

  @override
  String get shared_reward_content_other => '其他';

  @override
  String get shared_reward_content_snacks => '零食';

  @override
  String get shared_reward_content_play => '游玩';

  @override
  String get shared_reward_content_entertainment => '娱乐';

  @override
  String get shared_reward_content_toys => '玩具';

  @override
  String get shared_reward_content_books => '阅读';

  @override
  String get shared_species_sunflower => '向日葵';

  @override
  String get shared_species_moon_orchid => '月光兰';

  @override
  String get shared_species_tomato => '番茄';

  @override
  String get shared_species_strawberry => '草莓';

  @override
  String get shared_species_coral_orchid => '珊瑚岭兰';

  @override
  String get shared_species_jade_hydrangea => '翡翠绣球';

  @override
  String get shared_weekday_mon => '周一';

  @override
  String get shared_weekday_tue => '周二';

  @override
  String get shared_weekday_wed => '周三';

  @override
  String get shared_weekday_thu => '周四';

  @override
  String get shared_weekday_fri => '周五';

  @override
  String get shared_weekday_sat => '周六';

  @override
  String get shared_weekday_sun => '周日';

  @override
  String parent_report_bucket_week(int index) {
    return '第$index周';
  }

  @override
  String shared_perk_water_discount(int value) {
    return '浇水消耗 −$value';
  }

  @override
  String shared_perk_fertilize_discount(int value) {
    return '施肥消耗 −$value';
  }

  @override
  String shared_perk_weed_bonus(int value) {
    return '除草奖励 +$value';
  }

  @override
  String shared_perk_pest_bonus(int value) {
    return '除虫奖励 +$value';
  }

  @override
  String shared_perk_bloom_bonus(int value) {
    return '开花阳光 +$value';
  }

  @override
  String shared_perk_dew_bonus(int value) {
    return '晨露阳光 +$value';
  }

  @override
  String shared_perk_eyecare_bonus(int value) {
    return '护眼奖励 +$value';
  }

  @override
  String shared_perk_expand_discount(int value) {
    return '花盆扩容 −$value';
  }

  @override
  String shared_perk_shovel_refund(int value) {
    return '铲除退款 +$value';
  }

  @override
  String shared_duration_minutes(int m) {
    return '$m 分钟';
  }

  @override
  String shared_duration_hours(int h) {
    return '$h 小时';
  }

  @override
  String shared_duration_hours_minutes(int h, int m) {
    return '$h 小时 $m 分钟';
  }

  @override
  String shared_level_gap_next(int n, String duration) {
    return '距 Lv.$n 还差 $duration';
  }

  @override
  String shared_level_gap_max(String title) {
    return '已是最高称号 · $title';
  }

  @override
  String shared_reward_weekly_limit(int remaining) {
    return '周限 $remaining 次';
  }

  @override
  String get shared_reward_unlimited => '不限次数';

  @override
  String get shared_plant_err_species_not_found => '未找到该植物物种';

  @override
  String shared_plant_err_pot_out_of_capacity(int pot, int capacity) {
    return '花盆序号超出容量（$pot / $capacity）';
  }

  @override
  String shared_plant_err_pot_occupied(int pot) {
    return '花盆 #$pot 已被占用，请先清理';
  }

  @override
  String get shared_plant_err_premium_fragments_only => '精英植物只能用碎片兑换';

  @override
  String get shared_plant_err_seed_empty => '种子已用完，去开花收集新的种子吧';

  @override
  String shared_plant_err_sunlight_not_enough(int short) {
    return '阳光不足，还差 $short 阳光';
  }

  @override
  String shared_plant_err_fragments_not_enough(int short) {
    return '碎片不足，还差 $short 片';
  }

  @override
  String get shared_plant_err_care_state_invalid => '仅成长中/开花/枯萎植物可养护';

  @override
  String shared_plant_err_water_daily_limit(int max) {
    return '今日浇水已达 $max 次上限';
  }

  @override
  String shared_plant_err_water_interval(int interval, int wait) {
    return '浇水间隔需 $interval 分钟，还需 $wait 分钟';
  }

  @override
  String shared_plant_err_fertilize_daily_limit(int max) {
    return '今日施肥已达 $max 次上限';
  }

  @override
  String get shared_plant_err_plant_not_found => '植物不存在';

  @override
  String get shared_plant_err_already_wilted => '这株已经枯萎了，不用清理啦';

  @override
  String get shared_plant_err_no_weed => '这盆没有杂草哦';

  @override
  String get shared_plant_err_no_pest => '这盆没有害虫哦';

  @override
  String shared_plant_err_garden_full(int limit) {
    return '花园已达当前档位容量上限（$limit 盆），解锁可扩容';
  }

  @override
  String get shared_plant_err_reward_not_mature => '奖励还没成熟，或已经被领取啦';

  @override
  String get shared_checkin_err_linked_auto => '这个成长项要在专注里自动完成哦';

  @override
  String get shared_checkin_err_already_done => '这个成长项今天已经做到啦';

  @override
  String get shared_checkin_err_not_linked => '非联动成长项不能走专注结算';

  @override
  String get shared_checkin_err_session_not_today => '这次专注不在今天，不能结算今天的成长项';

  @override
  String get shared_checkin_err_session_used => '这次专注已经结算过成长项啦';

  @override
  String get shared_checkin_err_not_found => '找不到这条记录，可能已被删除';

  @override
  String get shared_checkin_err_already_verified => '这条记录已经处理过啦，不能重复核销';

  @override
  String get shared_checkin_err_already_rejected => '这条记录已经处理过啦，不能重复处理';

  @override
  String get shared_checkin_err_race => '这条记录刚刚已经被处理过了';

  @override
  String get seed_task_homework => '完成学校作业';

  @override
  String get seed_task_math => '练习数学口算';

  @override
  String get seed_task_read => '阅读 20 分钟';

  @override
  String get seed_task_rope_skip => '1分钟跳绳170个以上';

  @override
  String get seed_task_chores => '帮助家长打扫卫生';

  @override
  String get seed_reward_snack => '小零食';

  @override
  String get seed_reward_extra_play => '睡前多玩10分钟';

  @override
  String get seed_reward_cartoon => '看一集动画片';

  @override
  String get seed_reward_toy => '买一个小玩具';

  @override
  String get seed_reward_weekend_outing => '周末出去玩';

  @override
  String get shared_child_default_name => '孩子';

  @override
  String get child_hist_ref_focus => '专注产出';

  @override
  String get child_hist_ref_focus_session => '专注';

  @override
  String get child_hist_ref_focus_task_reward => '专注任务奖励';

  @override
  String get child_hist_ref_task_checkin => '成长项奖励';

  @override
  String get child_hist_ref_plant_plant => '种植植物';

  @override
  String get child_hist_ref_plant_water => '浇水';

  @override
  String get child_hist_ref_plant_fertilize => '施肥';

  @override
  String get child_hist_ref_plant_revive => '救回植物';

  @override
  String get child_hist_ref_plant_expand => '花园扩容';

  @override
  String get child_hist_ref_plant_weed => '拔草';

  @override
  String get child_hist_ref_plant_pest => '除虫';

  @override
  String get child_hist_ref_plant_death_refund => '植物死亡返还';

  @override
  String get child_hist_ref_eye_care_break => '护眼';

  @override
  String get child_hist_ref_plant_shovel_refund => '铲除返还';

  @override
  String get child_hist_ref_bloom_reward => '开花奖励';

  @override
  String get child_hist_ref_bloom_reward_24h => '花开回访奖励';

  @override
  String get child_hist_ref_redeem => '兑换奖励';

  @override
  String get child_hist_ref_redemption => '兑换奖励';

  @override
  String get child_hist_ref_queue_release => '阳光池释放';

  @override
  String get child_hist_ref_parent_gift => '家长赠予';

  @override
  String get child_hist_ref_debug_grant => '调试发放';

  @override
  String get child_hist_ref_focus_level_up => '专注升级';

  @override
  String get child_eyecare_seg_default => '跟着动画一起做，保护眼睛';

  @override
  String get shared_perk_name_eye_care => '护眼';

  @override
  String get shared_perk_name_water => '浇水';

  @override
  String get shared_perk_name_fertilize => '施肥';

  @override
  String get shared_perk_name_weed => '除草';

  @override
  String get shared_perk_name_pest => '除虫';

  @override
  String get shared_perk_name_bloom => '绽放';

  @override
  String get shared_perk_name_dew => '晨露';

  @override
  String get shared_perk_name_pot_expand => '扩盆';

  @override
  String get shared_perk_name_shovel => '铲除';

  @override
  String get shared_default_child_name => '孩子';
}
