import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 在 canvas 上绘制文字的小工具，统一处理描边与淡入淡出。
void drawText(
  Canvas canvas,
  String text,
  Offset center,
  TextStyle style, {
  double alpha = 1.0,
  double scale = 1.0,
  bool centered = true,
  Color? strokeColor,
  double strokeWidth = 3,
}) {
  if (alpha <= 0.01 || scale <= 0.01) return;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (scale != 1.0) canvas.scale(scale);
  final offset = centered ? Offset(-painter.width / 2, -painter.height / 2) : Offset.zero;

  if (strokeColor != null) {
    final stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor.withValues(alpha: strokeColor.a * alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stroke.paint(canvas, offset);
  }

  if (alpha < 0.999) {
    canvas.saveLayer(
      Rect.fromLTWH(offset.dx - 4, offset.dy - 4, painter.width + 8, painter.height + 8),
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
    painter.paint(canvas, offset);
    canvas.restore();
  } else {
    painter.paint(canvas, offset);
  }
  canvas.restore();
}

/// 常用画笔构造。
Paint fillPaint(Color color) => Paint()..color = color;

Paint glowPaint(Color color, double blur, {double alpha = 1.0}) => Paint()
  ..color = color.withValues(alpha: alpha)
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

/// 一段渐变的「能量条」背景。
Paint gradientBar(Rect rect, List<Color> colors) => Paint()
  ..shader = ui.Gradient.linear(rect.topLeft, rect.topRight, colors);

/// 让颜色更亮或更暗。
Color shade(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}
