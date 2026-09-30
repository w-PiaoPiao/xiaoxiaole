import 'package:flutter/material.dart';

/// 画布文字默认使用的字体族。生产环境保持 null。
///
/// `CustomPaint` 里的 `TextStyle` 不经过 Widget 树，拿不到主题的字体，
/// 只能落到系统的默认字体上——这在 Android 上没问题（中文会自动回退到
/// 系统字体），但测试环境里的默认字体把所有字形都画成方块，于是
/// `tool/ui_preview.dart` 截出来的伤害飘字与连击提示全是实心矩形，没法校对。
/// 预览工具会把它设成已注册的字体族，让画布文字也进得了截图。
String? debugCanvasFontFamily;

/// 在 canvas 上绘制文字的小工具，统一处理描边与淡入淡出。
///
/// 淡出是把透明度直接编进颜色，而不是套一层 `saveLayer`——后者会为每个飘字
/// 申请一块离屏缓冲，在真机上是实打实的显存与合成开销。
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
  final base = style.color ?? const Color(0xFFFFFFFF);
  final family = debugCanvasFontFamily;
  final styled = family == null || style.fontFamily != null
      ? style
      : style.copyWith(fontFamily: family);
  final effective = alpha >= 0.999
      ? styled
      : styled.copyWith(color: base.withValues(alpha: base.a * alpha));

  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
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
        style: effective.copyWith(
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

  painter.paint(canvas, offset);
  canvas.restore();
}
