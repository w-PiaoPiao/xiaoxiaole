// 音效生成器：程序化合成游戏音效，输出 16-bit PCM WAV 到 assets/sfx/。
//
// 项目不含任何位图素材（美术全是矢量绘制），音效同样用合成的方式生成，
// 保证素材可复现、可调参、体积小，也不引入第三方音频版权。
//
// 用法：dart run tool/sfx_generator.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 22050;

// ------------------------------------------------------------------ 合成基元

/// 指数衰减包络：起音 [attack] 秒，之后按 [decay] 速度衰减。
double _env(double t, double dur, {double attack = 0.004, double decay = 5.0}) {
  if (t < 0 || t > dur) return 0;
  final a = attack <= 0 ? 1.0 : (t / attack).clamp(0.0, 1.0);
  return a * math.exp(-decay * t / dur);
}

/// 带谐波的音调。[harmonics] 越高音色越"亮"。
double _tone(double t, double freq, {double harmonics = 0.35}) {
  final w = 2 * math.pi * freq * t;
  return math.sin(w) +
      harmonics * 0.55 * math.sin(2 * w) +
      harmonics * 0.28 * math.sin(3 * w) +
      harmonics * 0.12 * math.sin(5 * w);
}

/// 伪随机噪声（固定种子，保证每次生成的素材完全一致）。
double _noise(math.Random rng) => rng.nextDouble() * 2 - 1;

/// 频率从上到下线性扫过（用于"挥砍""落雷"这类动态音色）。
double _sweep(double t, double dur, double f0, double f1) {
  final k = (t / dur).clamp(0.0, 1.0);
  return f0 + (f1 - f0) * k;
}

// ------------------------------------------------------------------ 音色

typedef _Voice = double Function(double t, double dur, math.Random rng);

/// 消除：清脆的水晶音。连击越高音阶越高。
_Voice _clearVoice(double base) => (t, dur, rng) {
  final e = _env(t, dur, attack: 0.002, decay: 7.0);
  final shimmer =
      0.25 * _tone(t, base * 2, harmonics: 0.1) * _env(t, dur, decay: 14);
  return e * (0.8 * _tone(t, base, harmonics: 0.5) + shimmer);
};

/// 强化宝石：生成时上扬、引爆时下坠。
_Voice _specialVoice({required bool rising}) => (t, dur, rng) {
  final f = rising ? _sweep(t, dur, 420, 1500) : _sweep(t, dur, 1500, 380);
  final e = _env(t, dur, attack: 0.006, decay: 4.5);
  final crack = 0.35 * _noise(rng) * _env(t, dur, attack: 0.001, decay: 22);
  return e * _tone(t, f, harmonics: 0.7) + crack;
};

/// 命中：一记闷响，低频冲击 + 噪声爆。
_Voice get _hit => (t, dur, rng) {
  final e = _env(t, dur, attack: 0.001, decay: 9.0);
  final thump = _tone(t, _sweep(t, dur, 180, 60), harmonics: 0.25);
  final crack = 0.55 * _noise(rng) * _env(t, dur, attack: 0.0005, decay: 16);
  return e * thump * 1.1 + crack;
};

/// 玩家受击：低沉的下行，带一点不祥的余韵。
_Voice get _hurt => (t, dur, rng) {
  final e = _env(t, dur, attack: 0.004, decay: 3.4);
  final body = _tone(t, _sweep(t, dur, 220, 72), harmonics: 0.4);
  final grit = 0.3 * _noise(rng) * _env(t, dur, attack: 0.002, decay: 8);
  return e * body + grit;
};

/// 必杀「斩月」：拔刀般的上扬横扫 + 长长的月华余韵。
_Voice get _ultimate => (t, dur, rng) {
  final swing =
      _tone(t, _sweep(t, dur, 260, 1900), harmonics: 0.8) *
      _env(t, dur, attack: 0.02, decay: 3.0);
  final tail =
      0.5 *
      _tone(t, _sweep(t, dur, 1900, 900), harmonics: 0.2) *
      _env(t, dur, attack: 0.08, decay: 1.6);
  final clash = 0.4 * _noise(rng) * _env(t, dur, attack: 0.001, decay: 26);
  return swing + tail + clash;
};

/// 暴击：金属撞击的"当啷"。高频泛音 + 极短的噪声爆，
/// 比普通命中的闷响亮得多——一耳朵就能听出"这一下不一样"。
_Voice get _crit => (t, dur, rng) {
  final e = _env(t, dur, attack: 0.0008, decay: 9.0);
  final strike = _tone(t, _sweep(t, dur, 2400, 1500), harmonics: 1.0);
  final ring =
      0.6 *
      _tone(t, 1760, harmonics: 0.6) *
      _env(t, dur, attack: 0.002, decay: 4.0);
  final grit = 0.5 * _noise(rng) * _env(t, dur, attack: 0.0004, decay: 30);
  return e * strike + ring + grit;
};

/// 胜利：上行的琶音。
_Voice get _win => (t, dur, rng) {
  const notes = [523.25, 659.25, 783.99, 1046.5];
  const step = 0.13;
  var v = 0.0;
  for (var i = 0; i < notes.length; i++) {
    final start = i * step;
    if (t >= start) {
      v +=
          _tone(t - start, notes[i], harmonics: 0.4) *
          _env(t - start, dur - start, attack: 0.005, decay: 5.0);
    }
  }
  return v * 0.5;
};

/// 失败：下行的长音，收在低音上。
_Voice get _lose => (t, dur, rng) {
  const notes = [392.0, 311.13, 261.63];
  const step = 0.16;
  var v = 0.0;
  for (var i = 0; i < notes.length; i++) {
    final start = i * step;
    if (t >= start) {
      v +=
          _tone(t - start, notes[i], harmonics: 0.25) *
          _env(t - start, dur - start, attack: 0.01, decay: 3.2);
    }
  }
  return v * 0.5;
};

// ------------------------------------------------------------------ 输出

Uint8List _encodeWav(List<double> samples, int sampleRate) {
  // 先做峰值归一化，避免叠加后削波失真。
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  final gain = peak > 1e-6 ? 0.72 / peak : 1.0;

  final dataLen = samples.length * 2;
  final out = ByteData(44 + dataLen);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // PCM 块长度
  out.setUint16(20, 1, Endian.little); // 格式：PCM
  out.setUint16(22, 1, Endian.little); // 单声道
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // 字节率
  out.setUint16(32, 2, Endian.little); // 块对齐
  out.setUint16(34, 16, Endian.little); // 位深
  ascii(36, 'data');
  out.setUint32(40, dataLen, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * gain).clamp(-1.0, 1.0);
    out.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

void _write(String name, double seconds, _Voice voice, {int seed = 7}) {
  final count = (seconds * _sampleRate).round();
  final rng = math.Random(seed);
  final samples = List<double>.generate(
    count,
    (i) => voice(i / _sampleRate, seconds, rng),
  );
  final bytes = _encodeWav(samples, _sampleRate);
  final file = File('assets/sfx/$name.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print(
    '已生成 assets/sfx/$name.wav  ${(bytes.length / 1024).toStringAsFixed(1)} KB',
  );
}

void main() {
  // 消除音按连击升调：三档足够听出"越连越高"。
  _write('clear1', 0.17, _clearVoice(880.00), seed: 11); // A5
  _write('clear2', 0.19, _clearVoice(1108.73), seed: 12); // C#6
  _write('clear3', 0.22, _clearVoice(1318.51), seed: 13); // E6
  _write('special', 0.36, _specialVoice(rising: true), seed: 21);
  _write('burst', 0.42, _specialVoice(rising: false), seed: 22);
  _write('hit', 0.16, _hit, seed: 31);
  _write('crit', 0.30, _crit, seed: 32);
  _write('hurt', 0.34, _hurt, seed: 41);
  _write('ultimate', 0.85, _ultimate, seed: 51);
  _write('win', 0.95, _win, seed: 61);
  _write('lose', 0.85, _lose, seed: 62);
}
