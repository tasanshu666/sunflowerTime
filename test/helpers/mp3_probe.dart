// 测试用 mp3 时长探针（零第三方依赖，直读字节解析 MPEG 帧头）。
//
// 为什么需要：`docs/美术资源_序列帧与音频命名规范_v1.md` §红线（F77 实证）要求
// 「所有 sfx mp3 时长不得 <3s」——过短的 mp3 在 iOS 上 just_audio `setAsset` 会抛
// CoreAudio `-11849 NotOptimized`，且异常被 AudioService 静默吞掉 → 无声无日志。
// 判据必须来自**真实文件字节**（常量可能与素材漂移），且项目已确认「容器读数 vs
// 逐帧累计」存在几十毫秒差异，故采用逐帧累加（CBR / VBR 均适用）。
//
// 本文件是把 `test/m3/fx_frame_assets_guard_test.dart` 里的同款实现提为**测试公共
// 助手**，供宝箱音效护栏（`test/m3/guard_chest_assets_guard_test.dart`）复用，
// 避免两份逐帧累加逻辑各写一遍。fx 那支仍保留自己的私有副本（不在本批改动范围内，
// 后续可平滑迁移到本助手，行为完全一致）。
library mp3_probe;

/// 直读 mp3 字节、解析 MPEG 音频帧头并**逐帧累加**时长（秒）。
///
/// 帧头格式（ISO/IEC 11172-3 / 13818-3），4 字节大端：
///   位 31..21 帧同步（11 个 1，字节级掩码 `0xFF 0xE0`）
///   位 20..19 MPEG 版本：3=MPEG1 / 2=MPEG2 / 0=MPEG2.5 / 1=保留
///   位 18..17 Layer：3=LayerI / 2=LayerII / 1=LayerIII / 0=保留
///   位 15..12 比特率索引；位 11..10 采样率索引；位 9 padding
///
/// 找不到合法帧头、或未累加到任何帧 → 抛 [FormatException]（调用方据此失败并报路径，
/// 绝不静默跳过）。
double mp3DurationSeconds(List<int> bytes) {
  int pos = _skipId3v2(bytes);
  // 先扫到第一个合法帧头（跳过 ID3 尾部 / 元数据里的伪同步字）。
  while (pos + 4 <= bytes.length && _parseMp3FrameHeader(bytes, pos) == null) {
    pos++;
  }
  if (pos + 4 > bytes.length) {
    throw const FormatException('整文件未找到合法 MPEG 帧头（0xFFEx）');
  }

  double totalSeconds = 0;
  int frames = 0;
  while (pos + 4 <= bytes.length) {
    final _Mp3FrameHeader? h = _parseMp3FrameHeader(bytes, pos);
    if (h == null) break; // 尾部非帧数据（如 ID3v1 的 'TAG'）→ 结束
    totalSeconds += h.samplesPerFrame / h.sampleRate;
    frames++;
    pos += h.frameLength;
  }
  if (frames == 0) {
    throw const FormatException('未累加到任何 MPEG 帧');
  }
  return totalSeconds;
}

/// 跳过 ID3v2 标签（若存在）：10 字节头 + syncsafe 尺寸 + 可选 footer（+10B）。
int _skipId3v2(List<int> b) {
  if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) {
    return 0; // 非 'ID3'
  }
  final int size = ((b[6] & 0x7F) << 21) |
      ((b[7] & 0x7F) << 14) |
      ((b[8] & 0x7F) << 7) |
      (b[9] & 0x7F);
  int skip = 10 + size;
  if ((b[5] & 0x10) != 0) skip += 10; // footer present
  return skip <= b.length ? skip : 0;
}

/// 解析 `pos` 处 4 字节帧头；非法（保留值 / free / bad 索引）返回 null。
_Mp3FrameHeader? _parseMp3FrameHeader(List<int> b, int pos) {
  if (pos + 4 > b.length) return null;
  if (b[pos] != 0xFF || (b[pos + 1] & 0xE0) != 0xE0) return null;

  final int hdr =
      (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
  final int versionBits = (hdr >> 19) & 0x3;
  final int layerBits = (hdr >> 17) & 0x3;
  final int bitrateIdx = (hdr >> 12) & 0xF;
  final int sampleRateIdx = (hdr >> 10) & 0x3;
  final int padding = (hdr >> 9) & 0x1;

  if (versionBits == 1 || layerBits == 0) return null; // 保留
  if (bitrateIdx == 0 || bitrateIdx == 15) return null; // free / bad
  if (sampleRateIdx == 3) return null; // 保留

  final bool isV1 = versionBits == 3;
  final int samplesPerFrame = switch (layerBits) {
    3 => 384, // Layer I
    2 => 1152, // Layer II
    _ => isV1 ? 1152 : 576, // Layer III：MPEG1=1152 / MPEG2/2.5=576
  };
  final int sampleRate = switch (versionBits) {
    3 => _sampleRateV1[sampleRateIdx],
    2 => _sampleRateV2[sampleRateIdx],
    _ => _sampleRateV25[sampleRateIdx],
  };
  final int bitrateKbps = switch (layerBits) {
    3 => (isV1 ? _bitrateV1L1 : _bitrateV2L1)[bitrateIdx],
    2 => (isV1 ? _bitrateV1L2 : _bitrateV2L23)[bitrateIdx],
    _ => (isV1 ? _bitrateV1L3 : _bitrateV2L23)[bitrateIdx],
  };
  if (bitrateKbps <= 0) return null;

  final int bitrate = bitrateKbps * 1000;
  // Layer I：帧长按 4 字节槽对齐；Layer II/III：帧长 = 每帧采样数/8 × 码率 ÷ 采样率。
  final int frameLength = layerBits == 3
      ? ((12 * bitrate ~/ sampleRate) + padding) * 4
      : (samplesPerFrame ~/ 8) * bitrate ~/ sampleRate + padding;

  return _Mp3FrameHeader(
    sampleRate: sampleRate,
    samplesPerFrame: samplesPerFrame,
    frameLength: frameLength,
  );
}

// ── MPEG 比特率 / 采样率表（kbps / Hz）────────────────────────────────────────

const List<int> _bitrateV1L1 = <int>[
  0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0,
];
const List<int> _bitrateV1L2 = <int>[
  0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0,
];
const List<int> _bitrateV1L3 = <int>[
  0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
];
const List<int> _bitrateV2L1 = <int>[
  0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0,
];
const List<int> _bitrateV2L23 = <int>[
  0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
];
const List<int> _sampleRateV1 = <int>[44100, 48000, 32000, 0];
const List<int> _sampleRateV2 = <int>[22050, 24000, 16000, 0];
const List<int> _sampleRateV25 = <int>[11025, 12000, 8000, 0];

/// 单个 MPEG 帧的解析结果。
class _Mp3FrameHeader {
  const _Mp3FrameHeader({
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.frameLength,
  });

  final int sampleRate;
  final int samplesPerFrame;
  final int frameLength;
}
