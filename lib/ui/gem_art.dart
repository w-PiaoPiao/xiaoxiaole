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

  static final Map<GemType, Path> _icons = {
    GemType.red: _crossedSwords(),
    GemType.blue: _shield(),
    GemType.green: _healCross(),
    GemType.yellow: _bolt(),
    GemType.purple: _skull(),
  };

  /// 把多边形顶点连成带圆角的路径（坐标是 0~1 的单位空间）。
  static Path roundedPolygon(List<Offset> pts, double radius) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n];
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      final v1 = cur - prev;
      final v2 = next - cur;
      final l1 = v1.distance, l2 = v2.distance;
      final r1 = math.min(radius, l1 / 2);
      final r2 = math.min(radius, l2 / 2);
      final p1 = cur - v1 / l1 * r1;
      final p2 = cur + v2 / l2 * r2;
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  static Path _map(Path unit, Rect rect) {
    final matrix = Matrix4.translationValues(rect.left, rect.top, 0) *
        Matrix4.diagonal3Values(rect.width, rect.height, 1);
    return unit.transform(matrix.storage);
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

  /// 骷髅的眼睛、鼻腔与牙缝（用底座暗色「挖」出来）。
  static List<Path> _skullHoles() {
    return [
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
  }

  /// 获得底座在 [rect] 内的路径。
  static Path pathFor(GemType type, Rect rect) => _map(_tile, rect);

  // ------------------------------------------------------------------ 绘制

  /// 绘制一颗宝石。
  ///
  /// [scale] 用于生成/消散动画，[glow] 是外发光强度，[flash] 是白色闪光强度。
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

    final center = rect.center;
    final side = rect.width * scale;
    final target = Rect.fromCenter(center: center, width: side, height: side);
    final tile = _map(_tile, target);
    final iconRect = Rect.fromCenter(
      center: target.center.translate(0, -side * 0.01),
      width: side * 0.60,
      height: side * 0.60,
    );

    final light = Palette.gem(type);
    final deep = Palette.gemDeep(type);

    final needsLayer = alpha < 0.99;
    if (needsLayer) {
      canvas.saveLayer(rect.inflate(side), Paint()..color = Colors.white.withValues(alpha: alpha));
    }

    // 外发光
    if (glow > 0.01) {
      canvas.drawPath(
        tile,
        Paint()
          ..color = light.withValues(alpha: (0.6 * glow).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, side * 0.20),
      );
    }

    // 底座
    canvas.drawPath(
      tile,
      Paint()
        ..shader = ui.Gradient.linear(
          target.topLeft,
          target.bottomRight,
          [Color.lerp(light, Colors.white, 0.30)!, light, deep],
          [0.0, 0.40, 1.0],
        ),
    );

    // 上方内高光，做出切面感
    final sheen = _map(
      roundedPolygon(const [
        Offset(0.28, 0.06),
        Offset(0.72, 0.06),
        Offset(0.88, 0.30),
        Offset(0.12, 0.30),
      ], 0.10),
      target,
    );
    canvas.drawPath(
      sheen,
      Paint()
        ..shader = ui.Gradient.linear(
          sheen.getBounds().topCenter,
          sheen.getBounds().bottomCenter,
          [Colors.white.withValues(alpha: 0.34), Colors.white.withValues(alpha: 0.0)],
        ),
    );

    // 描边
    canvas.drawPath(
      tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.055
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(light, Colors.white, 0.45)!.withValues(alpha: 0.9),
    );

    _paintIcon(canvas, iconRect, type, light, deep);

    if (special != SpecialKind.none) {
      _paintSpecialOverlay(canvas, target, tile, special, spin);
    }

    if (flash > 0.01) {
      canvas.drawPath(
        tile,
        Paint()..color = Colors.white.withValues(alpha: flash.clamp(0.0, 1.0) * 0.9),
      );
    }

    if (needsLayer) canvas.restore();
  }

  /// 画图标：先用暗色描一圈保证在亮底上也看得清，再填浅色。
  static void _paintIcon(
    Canvas canvas,
    Rect rect,
    GemType type,
    Color light,
    Color deep,
  ) {
    final icon = _map(_icons[type]!, rect);
    final ink = Color.lerp(light, Colors.white, 0.78)!;
    final shadow = Color.lerp(deep, Colors.black, 0.45)!;

    // 外描边（对比度）
    canvas.drawPath(
      icon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rect.width * 0.10
        ..strokeJoin = StrokeJoin.round
        ..color = shadow.withValues(alpha: 0.55),
    );
    // 主体
    canvas.drawPath(icon, Paint()..color = ink);
    // 顶部一点高光，避免死白
    canvas.drawPath(
      icon,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [Colors.white.withValues(alpha: 0.55), Colors.transparent],
        ),
    );

    // 骷髅要「挖」出眼窝与牙齿，否则只是一块白板
    if (type == GemType.purple) {
      final holeFill = Paint()..color = Color.lerp(deep, Colors.black, 0.35)!;
      for (final hole in _skullHoles()) {
        canvas.drawPath(_map(hole, rect), holeFill);
      }
      canvas.drawPath(
        _map(_skull(), rect),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.width * 0.035
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
    }

    // 盾牌的竖脊与横带
    if (type == GemType.blue) {
      canvas.drawPath(
        _map(_shield(), rect),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.width * 0.055
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
    }
  }

  /// 强化宝石的标记：做成外围光带与方向箭头，避免盖住中间的图标。
  static void _paintSpecialOverlay(
    Canvas canvas,
    Rect target,
    Path tile,
    SpecialKind kind,
    double spin,
  ) {
    final side = target.width;
    final center = target.center;

    switch (kind) {
      case SpecialKind.lineH:
        _paintEdgeChevrons(canvas, target, horizontal: true);
      case SpecialKind.lineV:
        _paintEdgeChevrons(canvas, target, horizontal: false);
      case SpecialKind.burst:
        // 四角火花 + 亮环
        canvas.drawPath(
          tile,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = side * 0.07
            ..color = Colors.white.withValues(alpha: 0.85),
        );
        final spark = Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = side * 0.05
          ..strokeCap = StrokeCap.round;
        for (final dx in [-1.0, 1.0]) {
          for (final dy in [-1.0, 1.0]) {
            final p = center + Offset(side * 0.36 * dx, side * 0.36 * dy);
            canvas.drawLine(p, p + Offset(side * 0.14 * dx, side * 0.14 * dy), spark);
          }
        }
      case SpecialKind.prism:
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(spin);
        final ring = Rect.fromCenter(center: Offset.zero, width: side * 0.94, height: side * 0.94);
        canvas.drawArc(
          ring,
          0,
          math.pi * 2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = side * 0.085
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
            ),
        );
        canvas.restore();
      case SpecialKind.none:
        break;
    }
  }

  /// 左右（或上下）两个外向箭头，表示这颗宝石会清掉整行 / 整列。
  static void _paintEdgeChevrons(Canvas canvas, Rect target, {required bool horizontal}) {
    final side = target.width;
    final center = target.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!horizontal) canvas.rotate(math.pi / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.95);

    for (final dir in [-1.0, 1.0]) {
      final tip = Offset(side * 0.46 * dir, 0);
      final wing = Offset(side * 0.33 * dir, side * 0.15);
      canvas.drawLine(Offset(wing.dx, -wing.dy), tip, paint);
      canvas.drawLine(tip, Offset(wing.dx, wing.dy), paint);
    }
    canvas.restore();
  }
}
