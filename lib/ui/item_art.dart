import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/items.dart';

/// 道具的矢量图标（单位空间，占满传入的 rect）。
///
/// 与宝石 / 强化图标同一套画法：路径预建一次，位置交给
/// `canvas.translate / scale`，颜色由调用方按主题传进来。
class ItemArt {
  const ItemArt._();

  /// 锤头（本地坐标，中心在原点，绘制时旋转）。
  static final RRect _hammerHead = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 0.58, height: 0.32),
    const Radius.circular(0.07),
  );

  /// 沙漏的框：上边、左斜、下边、右斜围出的外形。
  static final Path _hourglassFrame = Path()
    ..moveTo(0.26, 0.12)
    ..lineTo(0.74, 0.12)
    ..lineTo(0.26, 0.88)
    ..lineTo(0.74, 0.88)
    ..close();

  /// 上半的沙（正往下漏）。
  static final Path _sandTop = Path()
    ..moveTo(0.34, 0.22)
    ..lineTo(0.66, 0.22)
    ..lineTo(0.50, 0.46)
    ..close();

  /// 下半堆起来的沙。
  static final Path _sandBottom = Path()
    ..moveTo(0.50, 0.54)
    ..lineTo(0.68, 0.80)
    ..lineTo(0.32, 0.80)
    ..close();

  /// 循环箭头的圆环范围。
  static const Rect _cycleRect = Rect.fromLTRB(0.16, 0.16, 0.84, 0.84);

  /// 画一枚道具图标。
  static void paint(Canvas canvas, Rect rect, ItemKind kind, Color color) {
    if (rect.isEmpty) return;
    final side = rect.width;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(side, side);
    switch (kind) {
      case ItemKind.hammer:
        _paintHammer(canvas, color);
      case ItemKind.shuffle:
        _paintShuffle(canvas, color);
      case ItemKind.stall:
        _paintStall(canvas, color);
    }
    canvas.restore();
  }

  static void _paintHammer(Canvas canvas, Color color) {
    // 手柄：从锤头斜向右下。
    canvas.drawLine(
      const Offset(0.44, 0.46),
      const Offset(0.82, 0.86),
      Paint()
        ..strokeWidth = 0.13
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // 锤头：长边垂直于手柄。
    canvas.save();
    canvas.translate(0.33, 0.33);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(_hammerHead, Paint()..color = color);
    canvas.restore();
  }

  static void _paintShuffle(Canvas canvas, Color color) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.10
      ..strokeCap = StrokeCap.round
      ..color = color;
    // 两段弧围成循环。
    canvas.drawArc(_cycleRect, math.pi * 1.08, math.pi * 0.70, false, stroke);
    canvas.drawArc(_cycleRect, math.pi * 0.08, math.pi * 0.70, false, stroke);
    // 弧末端的箭头。
    _arrow(canvas, const Offset(0.76, 0.28), math.pi * 0.28, color);
    _arrow(canvas, const Offset(0.24, 0.72), math.pi * 1.28, color);
  }

  /// 一个朝 [angle] 方向的三角箭头。
  static void _arrow(Canvas canvas, Offset at, double angle, Color color) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.drawPath(
      Path()
        ..moveTo(-0.07, -0.13)
        ..lineTo(0.14, 0.0)
        ..lineTo(-0.07, 0.13)
        ..close(),
      Paint()..color = color,
    );
    canvas.restore();
  }

  static void _paintStall(Canvas canvas, Color color) {
    canvas.drawPath(
      _hourglassFrame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.085
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawPath(_sandTop, Paint()..color = color);
    canvas.drawPath(
      _sandBottom,
      Paint()..color = color.withValues(alpha: 0.72),
    );
  }
}
