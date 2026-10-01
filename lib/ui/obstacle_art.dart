import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/gem.dart';

/// 机关（附着在宝石上的障碍物）的矢量美术。
///
/// 三种机关共用一套视觉语言：**都盖在宝石之上**，并且都带"这一格现在动不了"
/// 的信号——玩家看到覆盖层就知道它锁着。画法沿用宝石的约定：路径按单位空间
/// （0~1）预建一次，实际位置交给 `canvas.translate / scale`，不逐帧重建。
class ObstacleArt {
  const ObstacleArt._();

  static const Color frostLight = Color(0xFFCDEDFF);
  static const Color frostDeep = Color(0xFF4E8FC7);
  static const Color vineLight = Color(0xFF5FBF6A);
  static const Color vineDeep = Color(0xFF1E5427);
  static const Color altarLight = Color(0xFFFFE9A8);
  static const Color altarDeep = Color(0xFF8A6414);

  /// 冰壳上的两道裂纹。
  static final List<Path> _cracks = [
    Path()
      ..moveTo(0.18, 0.30)
      ..lineTo(0.44, 0.48)
      ..lineTo(0.30, 0.76),
    Path()
      ..moveTo(0.80, 0.22)
      ..lineTo(0.58, 0.44)
      ..lineTo(0.82, 0.64),
  ];

  /// 冰壳的斜向高光。
  static final Path _sheen = Path()
    ..moveTo(0.14, 0.70)
    ..lineTo(0.58, 0.12)
    ..lineTo(0.72, 0.12)
    ..lineTo(0.28, 0.70)
    ..close();

  /// 藤蔓的本体（两条缠住宝石的粗藤，横跨整格）。
  static final Path _vineBody = Path()
    ..moveTo(0.06, 0.22)
    ..cubicTo(0.32, 0.06, 0.48, 0.36, 0.66, 0.18)
    ..cubicTo(0.78, 0.06, 0.88, 0.18, 0.94, 0.28)
    ..moveTo(0.06, 0.78)
    ..cubicTo(0.24, 0.94, 0.44, 0.64, 0.66, 0.84)
    ..cubicTo(0.78, 0.94, 0.88, 0.84, 0.94, 0.74);

  /// 四角的短刺。
  static final List<Path> _spikes = [
    Path()
      ..moveTo(0.10, 0.10)
      ..lineTo(0.26, 0.14)
      ..lineTo(0.14, 0.26)
      ..close(),
    Path()
      ..moveTo(0.90, 0.10)
      ..lineTo(0.74, 0.14)
      ..lineTo(0.86, 0.26)
      ..close(),
    Path()
      ..moveTo(0.10, 0.90)
      ..lineTo(0.26, 0.86)
      ..lineTo(0.14, 0.74)
      ..close(),
    Path()
      ..moveTo(0.90, 0.90)
      ..lineTo(0.74, 0.86)
      ..lineTo(0.86, 0.74)
      ..close(),
  ];

  /// 祭坛中心的菱形符文。
  static final Path _rune = Path()
    ..moveTo(0.5, 0.32)
    ..lineTo(0.66, 0.5)
    ..lineTo(0.5, 0.68)
    ..lineTo(0.34, 0.5)
    ..close();

  static final Path _runeCore = Path()
    ..moveTo(0.5, 0.40)
    ..lineTo(0.59, 0.5)
    ..lineTo(0.5, 0.60)
    ..lineTo(0.41, 0.5)
    ..close();

  // ---------------------------------------------------------------- 画笔
  //
  // 与 GemArt 同一套做法：颜色与粗细是常量，画笔一次构建、长期复用。
  // 一屏最多二十几格机关，每格每帧新建四五支 Paint 是纯粹的分配浪费。
  // 只有需要呼吸的两支（冰裂纹、祭坛光点）留着按帧改 alpha。

  static final Paint _frostShade = Paint()
    ..color = const Color(0xFF0B1B30).withValues(alpha: 0.34);
  static final Paint _frostShell = Paint()
    ..color = frostLight.withValues(alpha: 0.36);
  static final Paint _frostSheen = Paint()
    ..color = Colors.white.withValues(alpha: 0.22);
  static final Paint _frostEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.045
    ..color = frostLight.withValues(alpha: 0.95);
  static final Paint _frostCrack = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.028
    ..strokeCap = StrokeCap.round;

  static final Paint _vineStem = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.115
    ..strokeCap = StrokeCap.round
    ..color = vineDeep;
  static final Paint _vineCore = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.055
    ..strokeCap = StrokeCap.round
    ..color = vineLight.withValues(alpha: 0.85);
  static final Paint _vineSpike = Paint()..color = vineDeep;
  static final Paint _vineKnot = Paint()..color = vineDeep;
  static final Paint _vineKnotCore = Paint()..color = vineLight;

  static final Paint _altarRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..color = altarDeep.withValues(alpha: 0.92);
  static final Paint _altarDot = Paint();
  static final Paint _altarRune = Paint()
    ..color = altarLight.withValues(alpha: 0.95);
  static final Paint _altarRuneCore = Paint()..color = altarDeep;

  /// 把机关画在 [rect] 给出的格子里。[time] 用于缓慢的呼吸 / 旋转，
  /// 静止时传 0 也能画出一张完整的静态图；[scale] 让机关跟随宝石的
  /// 选中 / 出生动画一起缩放（以格子中心为基准）。
  static void paint(
    Canvas canvas,
    Rect rect,
    ObstacleKind kind, {
    double time = 0,
    double scale = 1,
  }) {
    if (rect.isEmpty) return;
    final side = rect.width;
    canvas.save();
    canvas.translate(rect.left + side / 2, rect.top + side / 2);
    canvas.scale(side * scale);
    canvas.translate(-0.5, -0.5);
    switch (kind) {
      case ObstacleKind.frost:
        _paintFrost(canvas, time);
      case ObstacleKind.vine:
        _paintVine(canvas, time);
      case ObstacleKind.altar:
        _paintAltar(canvas, time);
    }
    canvas.restore();
  }

  static void _paintFrost(Canvas canvas, double time) {
    // 冰壳：罩住整格的半透明晶体。
    final shell = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.05, 0.05, 0.90, 0.90),
      const Radius.circular(0.24),
    );
    // 冰下的宝石先被压暗一层：被冻住的东西是"失去光泽"的，这一层让
    // 冰封在浅色宝石（黄、绿）上也一眼可辨。
    canvas.drawRRect(shell, _frostShade);
    canvas.drawRRect(shell, _frostShell);
    canvas.drawPath(_sheen, _frostSheen);
    canvas.drawRRect(shell, _frostEdge);

    // 裂纹呼吸：冰是"活的"，盯着看能看出它还在结。
    final glow = 0.55 + 0.25 * math.sin(time * 2.4);
    _frostCrack.color = Colors.white.withValues(
      alpha: (glow * 0.9).clamp(0.0, 1.0),
    );
    for (final path in _cracks) {
      canvas.drawPath(path, _frostCrack);
    }
  }

  static void _paintVine(Canvas canvas, double time) {
    final sway = 0.015 * math.sin(time * 1.6);
    canvas.save();
    canvas.translate(0, sway);
    // 粗藤打底 + 亮芯，看起来是"缠在宝石上"而不是贴纸。
    canvas.drawPath(_vineBody, _vineStem);
    canvas.drawPath(_vineBody, _vineCore);
    canvas.restore();

    for (final path in _spikes) {
      canvas.drawPath(path, _vineSpike);
    }

    // 中心的锁扣：藤蔓系在一起的那一个结。
    canvas.drawCircle(const Offset(0.5, 0.5), 0.11, _vineKnot);
    canvas.drawCircle(const Offset(0.5, 0.5), 0.06, _vineKnotCore);
  }

  static void _paintAltar(Canvas canvas, double time) {
    final pulse = 0.62 + 0.38 * math.sin(time * 2.0);
    _altarDot.color = altarLight.withValues(alpha: pulse.clamp(0.0, 1.0));

    canvas.save();
    canvas.translate(0.5, 0.5);
    canvas.rotate(time * 0.4);
    canvas.drawCircle(Offset.zero, 0.40, _altarRing);
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      canvas.drawCircle(const Offset(0, -0.40), 0.055, _altarDot);
      canvas.restore();
    }
    canvas.restore();

    // 中心符文不转：它是祭坛的"心"。
    canvas.drawPath(_rune, _altarRune);
    canvas.drawPath(_runeCore, _altarRuneCore);
  }
}
