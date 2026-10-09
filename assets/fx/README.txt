assets/fx/ —— 序列帧资源（PNG 为主；eyecare640 为 WebP q95 压缩管线产物）

目录即接口（2026-09-28 实际交付定稿；2026-10-09 C43 护眼改版）：

grow/{物种}/{过渡名}/frame001.png ... frameNNN.png
    成长过渡帧，720x720 透明底、含盆+植物整体。
    例：grow/sunflower/seed_to_sprout/frame001.png
    已交付：sunflower 三段（seed_to_sprout / sprout_to_adult / adult_to_bloomed，各 25 帧）。
    接入代码：frame_sequence_player.dart 的 growFxDir() / GrowTransition。

care/{water|fertilize|weed|pest}/frame001.png ... frameNNN.png
    浇水/施肥/除草/除虫帧。water/fertilize 为纯效果层帧（720x720 透明底、
    不含盆与植物）；weed/pest 为 27 帧效果层（2026-10-03 交付）。
    接入代码：frame_sequence_player.dart 的 kCare*FxDir。

focus/sunflower/{idle|collect|settle|return}/frame001.png ... frameNNN.png
    专注页向日葵（2026-09-29 交付），各组帧数不同（见 prd_params.dart）。

eyecare640/frame001.webp ... frame640.webp
    护眼卡动画（2026-10-09 C43 玄参交付）：5 段素材已剪辑拼为 1 个视频再逐帧
    导出（640 帧，720x720，段间过渡更丝滑），音频单段 eyecare.mp3（63.974s）。
    ⚠️ WebP q95 压缩管线产物（284.4M PNG → 40.2M，PSNR≈44.8dB 视觉无损），
    转换脚本 tools/convert_eyecare640.py；本目录**禁止再放 PNG**。
    ⚠️ 640 帧 × 2.07MB 解码位图 ≈ 1.3GB，播放器走**滑动窗口预热**
    （frame_sequence_player.dart，禁止整组预热）。
    旧 5 套素材（eyecare/close|doitagain|lookTip|look|done）已全部弃用删除。
    接入代码：prd_params.dart 的 kEyeCareSegment / kEyeCarePlaylist。

帧速口径：每帧时长 = 对应音频时长 / 帧数（常量在 lib/core/constants/prd_params.dart）。

规范文档：docs/美术资源_序列帧与音频命名规范_v1.md
