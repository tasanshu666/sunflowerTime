assets/fx/ —— 序列帧资源（只放 PNG）

目录即接口（2026-09-28 实际交付定稿）：

grow/{物种}/{过渡名}/frame001.png ... frameNNN.png
    成长过渡帧，720x720 透明底、含盆+植物整体。
    例：grow/sunflower/seed_to_sprout/frame001.png
    已交付：sunflower 三段（seed_to_sprout / sprout_to_adult / adult_to_bloomed，各 25 帧）。
    接入代码：frame_sequence_player.dart 的 growFxDir() / GrowTransition。

care/{water|fertilize}/frame001.png ... frameNNN.png
    浇水/施肥纯效果层帧，720x720 透明底、不含盆与植物。
    已交付：water 25 帧 / fertilize 25 帧。
    接入代码：frame_sequence_player.dart 的 kCareWaterFxDir / kCareFertilizeFxDir。

帧速口径：每帧时长 = 对应音频时长 / 帧数（常量在 lib/core/constants/prd_params.dart）。

规范文档：docs/美术资源_序列帧与音频命名规范_v1.md
