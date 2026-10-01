import 'package:flutter/material.dart';

/// 画布文字默认使用的字体族。生产环境保持 null。
///
/// `CustomPaint` 里的 `TextStyle` 不经过 Widget 树，拿不到主题的字体，
/// 只能落到系统的默认字体上——这在 Android 上没问题（中文会自动回退到
/// 系统字体），但测试环境里的默认字体把所有字形都画成方块，于是
/// `tool/ui_preview.dart` 截出来的伤害飘字与连击提示全是实心矩形，没法校对。
/// 预览工具会把它设成已注册的字体族，让画布文字也进得了截图。
String? debugCanvasFontFamily;

/// 已经布局好的文本。
class _LaidOutText {
  final TextPainter fill;
  final TextPainter? stroke;

  const _LaidOutText(this.fill, this.stroke);

  void dispose() {
    fill.dispose();
    stroke?.dispose();
  }
}

/// 布局结果的复用缓存。
///
/// 飘字与连击提示在 1 秒的生命里会被重画五六十帧，每帧都跑一次 shaping
/// 是这条路径上最贵的一步。键里带上量化后的透明度档位，同一段文字在整个
/// 淡出过程里只需布局十几次。
final Map<int, _LaidOutText> _textCache = {};

/// 缓存上限。飘字文本（「-123」「怒气 +5」）种类有限，64 条足够覆盖同屏
/// 的所有组合；超了淘汰最早的一条，避免缓存跟着数字无限增长。
const int _textCacheLimit = 64;

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

  // 透明度量化到 1/16：淡出时的每一档都稳定命中缓存，十六档的色阶差
  // 在飘字上肉眼不可辨。
  final fadeStep = (alpha.clamp(0.0, 1.0) * 16).round();
  final effectiveAlpha = fadeStep / 16;
  final cacheKey = Object.hash(styled, strokeColor, strokeWidth, fadeStep);

  final laidOut =
      _textCache[cacheKey] ??
      _layout(
        text: text,
        styled: styled,
        base: base,
        effectiveAlpha: effectiveAlpha,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        cacheKey: cacheKey,
      );

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (scale != 1.0) canvas.scale(scale);
  final offset = centered
      ? Offset(-laidOut.fill.width / 2, -laidOut.fill.height / 2)
      : Offset.zero;

  laidOut.stroke?.paint(canvas, offset);
  laidOut.fill.paint(canvas, offset);
  canvas.restore();
}

/// 布局并缓存一份文本（描边与填充各一个 painter）。
_LaidOutText _layout({
  required String text,
  required TextStyle styled,
  required Color base,
  required double effectiveAlpha,
  required Color? strokeColor,
  required double strokeWidth,
  required int cacheKey,
}) {
  final effective = effectiveAlpha >= 0.999
      ? styled
      : styled.copyWith(color: base.withValues(alpha: base.a * effectiveAlpha));

  final fill = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  TextPainter? stroke;
  if (strokeColor != null) {
    // 描边也要居中：多行文本时 fill 与 stroke 的换行位置必须一致，
    // 否则描边会整体偏到左边（当前调用点都是单行，但这里不该留坑）。
    stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: effective.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor.withValues(
              alpha: strokeColor.a * effectiveAlpha,
            ),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }

  final laidOut = _LaidOutText(fill, stroke);
  if (_textCache.length >= _textCacheLimit) {
    final oldest = _textCache.keys.first;
    _textCache.remove(oldest)?.dispose();
  }
  _textCache[cacheKey] = laidOut;
  return laidOut;
}
