import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/gem.dart';
import 'palette.dart';

/// 宝石的矢量美术。
///
/// 设计原则是「一眼看懂这块宝石干什么」：所有宝石共用同一块切面宝石底座
/// （保证棋盘整洁），靠**图标**区分功能——
///
///   烈焰 = 交叉双剑（造成伤害）   寒霜 = 盾牌（积累护盾）
///   生机 = 十字（恢复生命）       雷霆 = 闪电（积攒怒气）
///   诅咒 = 骷髅（敌人易伤）
///
/// 图标比抽象几何形状更直白，也不需要玩家先记图例。
class GemArt {
  const GemArt._();

  /// 底座：八边切角宝石牌，所有宝石共用。
  static final Path _tile = roundedPolygon(const [
    Offset(0.28, 0.02),
    Offset(0.72, 0.02),
    Offset(0.98, 0.28),
    Offset(0.98, 0.72),
    Offset(0.72, 0.98),
    Offset(0.28, 0.98),
    Offset(0.02, 0.72),
    Offset(0.02, 0.28),
  ], 0.075);

  /// 底座上方的高光切面。它是形状固定的，提成常量后不必每次绘制都重建。
  static final Path _sheen = roundedPolygon(const [
    Offset(0.28, 0.06),
    Offset(0.72, 0.06),
    Offset(0.88, 0.30),
    Offset(0.12, 0.30),
  ], 0.10);

  static final Map<GemType, Path> _icons = {
    GemType.red: _crossedSwords(),
    GemType.blue: _shield(),
    GemType.green: _healCross(),
    GemType.yellow: _bolt(),
    GemType.purple: _skull(),
  };

  /// 骷髅的眼睛、鼻腔与牙缝（用底座暗色「挖」出来）。
  static final List<Path> _skullHoles = [
    Path()..addOval(Rect.fromCircle(center: const Offset(0.33, 0.36), radius: 0.135)),
    Path()..addOval(Rect.fromCircle(center: const Offset(0.67, 0.36), radius: 0.135)),
    Path()
      ..moveTo(0.5, 0.52)
      ..lineTo(0.585, 0.66)
      ..lineTo(0.415, 0.66)
      ..close(),
    for (final x in [0.40, 0.50, 0.60])
      Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(x - 0.022, 0.70, x + 0.022, 0.90),
          const Radius.circular(0.012),
        )),
  ];

  /// 某种颜色宝石的图标路径（单位空间，占满 0~1）。
  ///
  /// 强化卡片直接复用这五个图标：玩家已经把「双剑 = 伤害」「盾牌 = 护盾」
  /// 这些对应关系记住了，不该再学一套新的。
  static Path iconPath(GemType type) => _icons[type]!;

  /// 八边切角底座（单位空间）。强化卡片沿用同一个形状，让卡片上的东西
  /// 看起来和棋盘上的是同一个世界的——共用一份路径也免得两处顶点各改各的。
  static Path get tilePath => _tile;

  /// 骷髅的眼窝与牙缝。单独暴露出来，供复用图标的一方自己填底色。
  static List<Path> get skullHoles => _skullHoles;

  /// 把多边形顶点连成带圆角的路径（坐标是 0~1 的单位空间）。
  static Path roundedPolygon(List<Offset> pts, double radius) {
    final path = Path();
    final n = pts.length;
    var started = false;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n];
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      final v1 = cur - prev;
      final v2 = next - cur;
      final l1 = v1.distance, l2 = v2.distance;
      // 相邻顶点重合（l == 0）时方向向量没有定义：跳过这一点，
      // 而不是让它算出 Inf/NaN 把整条路径废掉。
      if (l1 < 1e-9 || l2 < 1e-9) continue;
      final r1 = math.min(radius, l1 / 2);
      final r2 = math.min(radius, l2 / 2);
      final p1 = cur - v1 / l1 * r1;
      final p2 = cur + v2 / l2 * r2;
      if (started) {
        path.lineTo(p1.dx, p1.dy);
      } else {
        path.moveTo(p1.dx, p1.dy);
        started = true;
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  // ------------------------------------------------------------------ 图标

  /// 一把朝上的剑（剑身 + 护手 + 握柄 + 剑柄头）。
  static Path _singleSword() {
    final p = Path();
    // 剑身
    p.moveTo(0.5, 0.00);
    p.lineTo(0.545, 0.10);
    p.lineTo(0.545, 0.58);
    p.lineTo(0.455, 0.58);
    p.lineTo(0.455, 0.10);
    p.close();
    // 护手
    p.addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.29, 0.575, 0.71, 0.645),
      const Radius.circular(0.04),
    ));
    // 握柄
    p.addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.462, 0.655, 0.538, 0.88),
      const Radius.circular(0.028),
    ));
    // 剑柄头
    p.addOval(Rect.fromCircle(center: const Offset(0.5, 0.915), radius: 0.082));
    return p;
  }

  /// 交叉双剑：剑代表物理伤害，是最直白的攻击符号。
  static Path _crossedSwords() {
    final sword = _singleSword();
    final result = Path();
    // 稍微收一点，旋转后不超出底座
    final scaled = sword.transform(
      (Matrix4.translationValues(0.5, 0.5, 0) *
              Matrix4.diagonal3Values(0.90, 0.90, 1) *
              Matrix4.translationValues(-0.5, -0.5, 0))
          .storage,
    );
    for (final angle in [-0.66, 0.66]) {
      result.addPath(
        scaled.transform(
          (Matrix4.translationValues(0.5, 0.5, 0) *
                  Matrix4.rotationZ(angle) *
                  Matrix4.translationValues(-0.5, -0.5, 0))
              .storage,
        ),
        Offset.zero,
      );
    }
    return result;
  }

  /// 盾牌：上半圆润、下方收尖，中间一道竖脊。
  static Path _shield() {
    final p = Path()
      ..moveTo(0.5, 0.03)
      ..cubicTo(0.66, 0.13, 0.82, 0.16, 0.95, 0.16)
      ..cubicTo(0.95, 0.54, 0.86, 0.82, 0.5, 0.98)
      ..cubicTo(0.14, 0.82, 0.05, 0.54, 0.05, 0.16)
      ..cubicTo(0.18, 0.16, 0.34, 0.13, 0.5, 0.03)
      ..close();
    // 内部挖空，做出盾面与边框的层次
    p.addPath(
      Path()
        ..moveTo(0.5, 0.16)
        ..cubicTo(0.61, 0.23, 0.71, 0.25, 0.81, 0.25)
        ..cubicTo(0.80, 0.53, 0.73, 0.73, 0.5, 0.85)
        ..cubicTo(0.27, 0.73, 0.20, 0.53, 0.19, 0.25)
        ..cubicTo(0.29, 0.25, 0.39, 0.23, 0.5, 0.16)
        ..close(),
      Offset.zero,
    );
    return p;
  }

  /// 十字：医疗/恢复的通用符号。
  static Path _healCross() {
    final p = Path();
    const thick = 0.175;
    p.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(0.5 - thick, 0.05, 0.5 + thick, 0.95),
      const Radius.circular(0.06),
    ));
    p.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(0.05, 0.5 - thick, 0.95, 0.5 + thick),
      const Radius.circular(0.06),
    ));
    return p;
  }

  /// 闪电：怒气/能量。
  static Path _bolt() {
    return Path()
      ..moveTo(0.62, 0.02)
      ..lineTo(0.18, 0.55)
      ..lineTo(0.44, 0.55)
      ..lineTo(0.34, 0.98)
      ..lineTo(0.84, 0.42)
      ..lineTo(0.55, 0.42)
      ..close();
  }

  /// 骷髅：诅咒/易伤。
  static Path _skull() {
    final p = Path();
    // 颅骨
    p.addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.08, 0.05, 0.92, 0.70),
      const Radius.circular(0.34),
    ));
    // 下颌
    p.addRRect(RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.27, 0.62, 0.73, 0.95),
      const Radius.circular(0.13),
    ));
    return p;
  }

  // ------------------------------------------------------------------ 绘制

  /// 每种颜色预建好的画笔与着色器。
  ///
  /// 宝石的颜色只取决于类型，而绘制位置可以交给 canvas 变换处理——于是
  /// 这些画笔在整个生命周期里都是常量，一次构建、全局复用。改造前每颗宝石
  /// 每帧都要新建 3 个渐变着色器与若干 Paint，64 颗就是每帧两百多个对象，
  /// 在软件光栅化下这一项就占掉了棋盘一半的绘制时间。
  static final Map<GemType, _GemBrush> _brushes = {
    for (final type in GemType.values) type: _makeBrush(type),
  };

  static _GemBrush _makeBrush(GemType type) {
    final light = Palette.gem(type);
    final deep = Palette.gemDeep(type);
    final ink = Color.lerp(light, Colors.white, 0.78)!;
    final shadow = Color.lerp(deep, Colors.black, 0.45)!;

    Paint ridge(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..color = ink;

    return _GemBrush(
      // 单位空间里的渐变：从左上到右下，与底座同一个坐标系。
      base: Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(1, 1),
          [Color.lerp(light, Colors.white, 0.30)!, light, deep],
          const [0.0, 0.40, 1.0],
        ),
      sheen: Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0.5, 0.06),
          const Offset(0.5, 0.30),
          [Colors.white.withValues(alpha: 0.34), Colors.white.withValues(alpha: 0.0)],
        ),
      outline: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.055
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(light, Colors.white, 0.45)!.withValues(alpha: 0.9),
      iconShadow: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.10
        ..strokeJoin = StrokeJoin.round
        ..color = shadow.withValues(alpha: 0.55),
      iconFill: Paint()..color = ink,
      iconSheen: Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0.5, 0),
          const Offset(0.5, 1),
          [Colors.white.withValues(alpha: 0.55), Colors.transparent],
        ),
      detailFill: Paint()..color = Color.lerp(deep, Colors.black, 0.35)!,
      // 骷髅的牙缝与盾牌的脊线用的是同一种颜色、不同粗细：各留一支专用
      // 画笔，免得共用一个 Paint 时靠"先改 strokeWidth 再画"来区分类别。
      skullRidge: ridge(0.035),
      shieldRidge: ridge(0.055),
    );
  }

  /// 每种宝石的静态图层只由类型决定，逐帧重建 Path 与渐变没有意义——
  /// 但**录制 Picture 也换不来收益**：实测棋盘每帧 6.2ms 里，Dart 侧的
  /// 构建只占 0.06ms，其余全在光栅化（真机由 GPU 承担，更便宜）。
  /// 所以这里保持直白的逐帧绘制，把画笔提成常量就够了。

  /// 外发光画笔：只有颜色在变，模糊半径是常量。
  static final Paint _glow = Paint()
    ..maskFilter = MaskFilter.blur(BlurStyle.outer, 0.20);

  /// 白闪画笔：同样只有透明度在变。
  static final Paint _flash = Paint();

  /// 绘制一颗宝石。
  ///
  /// [scale] 用于生成/消散动画，[glow] 是外发光强度，[flash] 是白色闪光强度。
  ///
  /// 全部绘制都在 0~1 的单位空间里完成，实际位置与大小由 canvas 变换承担：
  /// 这样形状、描边宽度、渐变都可以是常量，不必每帧重新映射成新 Path。
  static void paint(
    Canvas canvas,
    Rect rect,
    GemType type,
    SpecialKind special, {
    double scale = 1.0,
    double alpha = 1.0,
    double glow = 0.0,
    double spin = 0.0,
    double flash = 0.0,
  }) {
    if (scale <= 0.001 || alpha <= 0.01) return;

    // 传入的 rect 始终是正方形，因此这里可以放心用等比缩放。
    final side = rect.width * scale;
    final left = rect.left + (rect.width - side) / 2;
    final top = rect.top + (rect.height - side) / 2;
    final brush = _brushes[type]!;

    final needsLayer = alpha < 0.99;
    if (needsLayer) {
      canvas.saveLayer(rect.inflate(side), Paint()..color = Colors.white.withValues(alpha: alpha));
    }

    canvas.save();
    canvas.translate(left, top);
    canvas.scale(side, side);

    // 外发光（强度逐帧在变，复用一支画笔即可）
    if (glow > 0.01) {
      canvas.drawPath(
        _tile,
        _glow..color = Palette.gem(type).withValues(alpha: (0.6 * glow).clamp(0.0, 1.0)),
      );
    }

    canvas.drawPath(_tile, brush.base);
    canvas.drawPath(_sheen, brush.sheen);
    canvas.drawPath(_tile, brush.outline);
    _paintIcon(canvas, type, brush);

    if (special != SpecialKind.none) {
      _paintSpecialOverlay(canvas, special, spin);
    }

    if (flash > 0.01) {
      canvas.drawPath(
        _tile,
        _flash..color = Colors.white.withValues(alpha: flash.clamp(0.0, 1.0) * 0.9),
      );
    }

    canvas.restore();
    if (needsLayer) canvas.restore();
  }

  /// 画图标：先用暗色描一圈保证在亮底上也看得清，再填浅色。
  static void _paintIcon(Canvas canvas, GemType type, _GemBrush brush) {
    final icon = _icons[type]!;

    // 图标占底座中间 60%，略微上移一点。
    canvas.save();
    canvas.translate(0.2, 0.19);
    canvas.scale(0.6, 0.6);

    canvas.drawPath(icon, brush.iconShadow);
    canvas.drawPath(icon, brush.iconFill);
    canvas.drawPath(icon, brush.iconSheen);

    // 骷髅要「挖」出眼窝与牙齿，否则只是一块白板
    if (type == GemType.purple) {
      for (final hole in _skullHoles) {
        canvas.drawPath(hole, brush.detailFill);
      }
      canvas.drawPath(icon, brush.skullRidge);
    }

    // 盾牌的竖脊与横带
    if (type == GemType.blue) {
      canvas.drawPath(icon, brush.shieldRidge);
    }

    canvas.restore();
  }

  /// 强化宝石的标记：做成外围光带与方向箭头，避免盖住中间的图标。
  static void _paintSpecialOverlay(Canvas canvas, SpecialKind kind, double spin) {
    switch (kind) {
      case SpecialKind.lineH:
        _paintEdgeChevrons(canvas, horizontal: true);
      case SpecialKind.lineV:
        _paintEdgeChevrons(canvas, horizontal: false);
      case SpecialKind.burst:
        // 四角火花 + 亮环
        canvas.drawPath(_tile, _burstRing);
        for (final dx in [-1.0, 1.0]) {
          for (final dy in [-1.0, 1.0]) {
            final p = Offset(0.5 + 0.36 * dx, 0.5 + 0.36 * dy);
            canvas.drawLine(p, p + Offset(0.14 * dx, 0.14 * dy), _burstSpark);
          }
        }
      case SpecialKind.prism:
        canvas.save();
        canvas.translate(0.5, 0.5);
        canvas.rotate(spin);
        canvas.drawArc(
          Rect.fromCenter(center: Offset.zero, width: 0.94, height: 0.94),
          0,
          math.pi * 2,
          false,
          _prismRing,
        );
        canvas.restore();
      case SpecialKind.none:
        break;
    }
  }

  static final Paint _burstRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.07
    ..color = Colors.white.withValues(alpha: 0.85);

  static final Paint _burstSpark = Paint()
    ..color = Colors.white.withValues(alpha: 0.95)
    ..strokeWidth = 0.05
    ..strokeCap = StrokeCap.round;

  static final Paint _prismRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.085
    ..shader = ui.Gradient.sweep(
      Offset.zero,
      const [
        Color(0xFFFF6B6B),
        Color(0xFFFFD34D),
        Color(0xFF5CE39A),
        Color(0xFF5FC8FF),
        Color(0xFFC08CFF),
        Color(0xFFFF6B6B),
      ],
      // 颜色数超过 2 时必须显式给出 stop，否则 dart:ui 会抛异常
      const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    );

  static final Paint _chevron = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.075
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white.withValues(alpha: 0.95);

  /// 左右（或上下）两个外向箭头，表示这颗宝石会清掉整行 / 整列。
  static void _paintEdgeChevrons(Canvas canvas, {required bool horizontal}) {
    canvas.save();
    canvas.translate(0.5, 0.5);
    if (!horizontal) canvas.rotate(math.pi / 2);
    for (final dir in [-1.0, 1.0]) {
      final tip = Offset(0.46 * dir, 0);
      final wing = Offset(0.33 * dir, 0.15);
      canvas.drawLine(Offset(wing.dx, -wing.dy), tip, _chevron);
      canvas.drawLine(tip, Offset(wing.dx, wing.dy), _chevron);
    }
    canvas.restore();
  }
}

/// 一种颜色对应的一整套画笔（全部定义在单位空间，可长期复用）。
class _GemBrush {
  final Paint base;
  final Paint sheen;
  final Paint outline;
  final Paint iconShadow;
  final Paint iconFill;
  final Paint iconSheen;
  final Paint detailFill;
  final Paint skullRidge;
  final Paint shieldRidge;

  const _GemBrush({
    required this.base,
    required this.sheen,
    required this.outline,
    required this.iconShadow,
    required this.iconFill,
    required this.iconSheen,
    required this.detailFill,
    required this.skullRidge,
    required this.shieldRidge,
  });
}
