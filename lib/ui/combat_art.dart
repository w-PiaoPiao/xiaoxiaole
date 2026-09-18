import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/gem.dart';
import 'fx.dart';
import 'palette.dart';

/// 战斗打击特效的绘制。
///
/// 单独抽出来有两个好处：战斗视图只负责组合，特效本身可以被
/// `tool/fx_preview.dart` 直接渲染成图片来校对，不必反复在设备上抓帧。
///
/// 全部使用「多层描边 + 透明叠加」而不是模糊，兼顾观感与性能。
class CombatArt {
  const CombatArt._();

  /// 一道「两头收尖」的弧形剑气——斩击类特效的基础形状。
  ///
  /// 用弧线采样成多边形，宽度按 sin 曲线从两端收尖，
  /// 比单纯描边更像刀光。
  static Path taperedArc(
    Offset center,
    double radius,
    double startAngle,
    double sweep,
    double maxWidth, {
    int samples = 26,
  }) {
    if (sweep.abs() < 0.001) return Path();
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final u = i / samples;
      final a = startAngle + sweep * u;
      final w = maxWidth * math.sin(u * math.pi);
      final dir = Offset(math.cos(a), math.sin(a));
      outer.add(center + dir * (radius + w / 2));
      inner.add(center + dir * (radius - w / 2));
    }
    final path = Path()..moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in inner.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  static double _noise(int seed, int i) {
    final v = math.sin((seed % 997) * 12.9898 + i * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  // ------------------------------------------------------------------ 打击特效

  static void paintStrikes(Canvas canvas, Size size, List<StrikeFx> strikes) {
    for (final strike in strikes) {
      switch (strike.kind) {
        case StrikeKind.sword:
          _paintSwordSlash(canvas, size, strike);
        case StrikeKind.lightning:
          _paintLightning(canvas, size, strike);
        case StrikeKind.curse:
          _paintCurseMark(canvas, size, strike);
        case StrikeKind.heal:
          _paintHeal(canvas, size, strike);
        case StrikeKind.shield:
          _paintShield(canvas, size, strike);
        case StrikeKind.enemyHit:
          _paintEnemyGash(canvas, size, strike);
      }
    }
  }

  /// 红色·交叉双剑：两道剑气先后交叉斩过，末端有亮芒。
  static void _paintSwordSlash(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    final center = Offset(strike.nx * size.width, strike.ny * size.height);
    final maxWidth = size.width * (0.020 + strike.power * 0.012);

    for (var i = 0; i < 2; i++) {
      // 两道剑气错开一点时间，形成"唰—唰—"的两连击
      final local = ((t - i * 0.16) / (1 - i * 0.16)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final alpha = math.sin(local * math.pi).clamp(0.0, 1.0);
      final ease = Curves.easeOutCubic.transform(local);
      final sign = i == 0 ? 1.0 : -1.0;

      // 弧心放在敌人的斜上方：弧线自上而下穿过身体，两道交叉成 X。
      // 尺寸按「角色大小」而不是整个舞台来定，否则在竖长比例的战斗区里
      // 剑气会拉成两根又长又粗的光柱。
      final arcCenter = center +
          Offset(-sign * size.width * 0.34, -size.height * 0.10);
      final arcRadius = (center - arcCenter).distance;
      final aim = (center - arcCenter).direction;
      const spread = 0.92;
      final start = aim - spread * sign;
      final sweep = spread * 1.6 * sign * ease;

      for (final layer in [
        (1.0, 0.20, Palette.hpEnemy, 1.0),
        (0.55, 0.62, Palette.hpEnemy, 0.9),
        (0.24, 1.0, Colors.white, 1.0),
      ]) {
        canvas.drawPath(
          taperedArc(arcCenter, arcRadius, start, sweep, maxWidth * layer.$1),
          Paint()..color = layer.$3.withValues(alpha: alpha * layer.$2 * layer.$4),
        );
      }

      // 锥形弧线本身两端就是尖的，不再另外点缀（否则会看成两颗光球）
    }
  }

  /// 黄色·闪电：从天而降的折线落雷，带分叉与强闪。
  static void _paintLightning(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    // 落雷很快：前 40% 劈下，后面余辉
    final strikeT = (t / 0.4).clamp(0.0, 1.0);
    final fadeT = t < 0.4 ? 1.0 : 1 - (t - 0.4) / 0.6;
    final alpha = fadeT.clamp(0.0, 1.0);
    if (alpha <= 0.01) return;

    final target = Offset(strike.nx * size.width, strike.ny * size.height);
    final top = Offset(target.dx + (_noise(strike.seed, 0) - 0.5) * size.width * 0.3, -size.height * 0.05);
    final drawn = Offset.lerp(top, target, Curves.easeInCubic.transform(strikeT))!;

    // 折线主干
    final path = Path()..moveTo(top.dx, top.dy);
    const segments = 9;
    for (var i = 1; i <= segments; i++) {
      final u = i / segments;
      final p = Offset.lerp(top, drawn, u)!;
      final jitter = (_noise(strike.seed, i) - 0.5) * size.width * 0.16 * (1 - u * 0.5);
      path.lineTo(p.dx + jitter, p.dy);
    }

    // 三层叠加：光晕 → 电光 → 白核
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * (0.030 + strike.power * 0.016)
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.rage.withValues(alpha: alpha * 0.30));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * (0.014 + strike.power * 0.007)
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.rage.withValues(alpha: alpha * 0.95));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.005
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: alpha));

    // 分叉
    for (var b = 0; b < 2; b++) {
      final u = 0.35 + _noise(strike.seed, 20 + b) * 0.4;
      final base = Offset.lerp(top, drawn, u)!;
      final dir = _noise(strike.seed, 30 + b) > 0.5 ? 1.0 : -1.0;
      final branch = Path()
        ..moveTo(base.dx, base.dy)
        ..lineTo(
          base.dx + dir * size.width * 0.10,
          base.dy + size.height * 0.06,
        )
        ..lineTo(
          base.dx + dir * size.width * 0.13,
          base.dy + size.height * 0.13,
        );
      canvas.drawPath(branch, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.008
        ..color = Palette.rage.withValues(alpha: alpha * 0.7));
    }

    // 落点闪
    if (strikeT >= 0.999) {
      canvas.drawCircle(
        target,
        size.width * 0.10 * (1 - t),
        Paint()..color = Palette.rage.withValues(alpha: alpha * 0.45),
      );
    }
  }

  /// 紫色·骷髅：诅咒印记砸在敌人身上，向外扩散两圈符文环。
  static void _paintCurseMark(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    final center = Offset(strike.nx * size.width, strike.ny * size.height);
    final pop = t < 0.22
        ? Curves.easeOutBack.transform((t / 0.22).clamp(0.0, 1.0))
        : 1.0;
    final alpha = (t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3).clamp(0.0, 1.0) * 0.95;
    final scale = size.width * 0.075 * strike.power * pop;
    final purple = Palette.gem(GemType.purple);

    // 符文环
    for (var i = 0; i < 2; i++) {
      final r = size.width * (0.06 + 0.10 * i) + size.width * 0.14 * t * (1 + i * 0.6);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.008 * (1 - t)
          ..color = purple.withValues(alpha: alpha * (1 - t) * 0.8),
      );
    }

    // 印记本体：圆环 + 骷髅
    canvas.drawCircle(
      center,
      scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.010
        ..color = purple.withValues(alpha: alpha),
    );
    canvas.drawCircle(
      center,
      scale * 0.82,
      Paint()..color = purple.withValues(alpha: alpha * 0.24),
    );

    final skull = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, -scale * 0.12), width: scale * 1.05, height: scale * 0.92),
        Radius.circular(scale * 0.42),
      ))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, scale * 0.34), width: scale * 0.62, height: scale * 0.44),
        Radius.circular(scale * 0.16),
      ));
    canvas.drawPath(skull, Paint()..color = Colors.white.withValues(alpha: alpha * 0.92));
    final hole = Paint()..color = purple.withValues(alpha: alpha);
    canvas.drawCircle(center.translate(-scale * 0.24, -scale * 0.16), scale * 0.17, hole);
    canvas.drawCircle(center.translate(scale * 0.24, -scale * 0.16), scale * 0.17, hole);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy + scale * 0.02)
        ..lineTo(center.dx + scale * 0.12, center.dy + scale * 0.22)
        ..lineTo(center.dx - scale * 0.12, center.dy + scale * 0.22)
        ..close(),
      hole,
    );
  }

  /// 绿色·十字：治疗十字升起，周围光点上浮（作用在玩家一侧）。
  static void _paintHeal(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    final alpha = math.sin(t * math.pi).clamp(0.0, 1.0);
    final center = Offset(
      strike.nx * size.width,
      strike.ny * size.height - size.height * 0.10 * t,
    );
    final s = size.width * 0.045 * strike.power * (0.7 + 0.3 * t);
    final green = Palette.hpPlayer;

    // 十字
    final cross = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * 0.62, height: s * 2.3),
        Radius.circular(s * 0.2),
      ))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * 2.3, height: s * 0.62),
        Radius.circular(s * 0.2),
      ));
    canvas.drawPath(cross, Paint()..color = green.withValues(alpha: alpha * 0.28));
    canvas.drawPath(
      Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s * 0.34, height: s * 1.7),
          Radius.circular(s * 0.14),
        ))
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s * 1.7, height: s * 0.34),
          Radius.circular(s * 0.14),
        )),
      Paint()..color = Colors.white.withValues(alpha: alpha * 0.92),
    );

    // 上浮光点
    for (var i = 0; i < 6; i++) {
      final u = _noise(strike.seed, i);
      final x = center.dx + (u - 0.5) * size.width * 0.26;
      final y = center.dy + size.height * 0.06 - size.height * 0.18 * t * (0.5 + u);
      canvas.drawCircle(
        Offset(x, y),
        size.width * (0.005 + u * 0.006),
        Paint()..color = green.withValues(alpha: alpha * 0.75),
      );
    }
  }

  /// 蓝色·盾牌：六边护盾张开，边缘有一道扫过的光。
  static void _paintShield(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    final center = Offset(strike.nx * size.width, strike.ny * size.height);
    final pop = t < 0.25
        ? Curves.easeOutBack.transform((t / 0.25).clamp(0.0, 1.0))
        : 1.0;
    final alpha = (t < 0.65 ? 1.0 : 1 - (t - 0.65) / 0.35).clamp(0.0, 1.0);
    final r = size.width * 0.085 * strike.power * pop;
    final blue = Palette.shield;

    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i - math.pi / 2;
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        hex.moveTo(p.dx, p.dy);
      } else {
        hex.lineTo(p.dx, p.dy);
      }
    }
    hex.close();

    canvas.drawPath(hex, Paint()..color = blue.withValues(alpha: alpha * 0.22));
    canvas.drawPath(hex, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.009
      ..strokeJoin = StrokeJoin.round
      ..color = blue.withValues(alpha: alpha * 0.9));

    // 盾面扫光
    canvas.save();
    canvas.clipPath(hex);
    final sweepX = center.dx - r + 2 * r * Curves.easeOutCubic.transform(t);
    canvas.drawRect(
      Rect.fromLTWH(sweepX - r * 0.18, center.dy - r, r * 0.36, r * 2),
      Paint()..color = Colors.white.withValues(alpha: alpha * 0.35),
    );
    canvas.restore();
  }

  /// 敌人命中玩家：三道红色爪痕斜着划过，配一道压边红闪。
  static void _paintEnemyGash(Canvas canvas, Size size, StrikeFx strike) {
    final t = strike.t;
    final alpha = math.sin(t * math.pi).clamp(0.0, 1.0);
    if (alpha <= 0.01) return;
    final center = Offset(strike.nx * size.width, strike.ny * size.height);

    // 压边红闪
    if (t < 0.35) {
      final flash = 1 - t / 0.35;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Palette.danger.withValues(alpha: flash * 0.20),
      );
    }

    for (var i = 0; i < 3; i++) {
      final spread = (i - 1) * size.width * 0.075;
      final from = Offset(center.dx - size.width * 0.30 + spread, center.dy + size.height * 0.10);
      final to = Offset(center.dx + size.width * 0.26 + spread, center.dy - size.height * 0.12);
      final grow = Curves.easeOutCubic.transform(t).clamp(0.0, 1.0);
      final end = Offset.lerp(from, to, grow)!;
      final width = size.width * (0.020 - i * 0.003) * (0.8 + 0.4 * strike.power);

      canvas.drawPath(
        _taperedLine(from, end, width),
        Paint()..color = Palette.danger.withValues(alpha: alpha * 0.35),
      );
      canvas.drawPath(
        _taperedLine(from, end, width * 0.35),
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.85),
      );
    }
  }

  /// 两头收尖的直线段（爪痕用）。
  static Path _taperedLine(Offset from, Offset to, double maxWidth) {
    final v = to - from;
    final len = v.distance;
    if (len < 0.001) return Path();
    final dir = v / len;
    final normal = Offset(-dir.dy, dir.dx);
    final outer = <Offset>[];
    final inner = <Offset>[];
    const samples = 14;
    for (var i = 0; i <= samples; i++) {
      final u = i / samples;
      final p = from + v * u;
      final w = maxWidth * math.sin(u * math.pi);
      outer.add(p + normal * (w / 2));
      inner.add(p - normal * (w / 2));
    }
    final path = Path()..moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in inner.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  // ------------------------------------------------------------------ 必杀·斩月

  /// 「斩月」：一道月牙形剑气横贯战场，附带月华余韵。
  static void paintUltimate(Canvas canvas, Size size, UltimateFx ult) {
    final t = ult.t;

    // 起手全屏闪
    if (t < 0.18) {
      final flash = 1 - t / 0.18;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Palette.gold.withValues(alpha: flash * 0.30),
      );
    }

    // 月牙：绕战场外侧的大圆扫过
    final center = Offset(size.width * 0.5, size.height * 1.25);
    final radius = size.height * 0.92;
    final base = -math.pi * 0.72 + ult.tilt;
    final sweepTotal = math.pi * 0.62;
    final progress = Curves.easeOutCubic.transform((t / 0.72).clamp(0.0, 1.0));
    if (progress <= 0.001) return;
    final alpha = (t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);

    // 三层：金色余韵 → 金色刀身 → 白色锋芒
    for (final layer in [
      (1.0, 0.20, Palette.gold, 1.0),
      (0.62, 0.62, Palette.gold, 0.85),
      (0.26, 1.0, Colors.white, 0.98),
    ]) {
      final arc = taperedArc(
        center,
        radius,
        base,
        sweepTotal * progress,
        size.width * 0.075 * layer.$1,
      );
      canvas.drawPath(
        arc,
        Paint()..color = layer.$3.withValues(alpha: alpha * layer.$2 * layer.$4),
      );
    }

    // 刀尖月华
    if (progress > 0.06) {
      final tipAngle = base + sweepTotal * progress;
      final tip = center + Offset(math.cos(tipAngle), math.sin(tipAngle)) * radius;
      canvas.drawCircle(
        tip,
        size.width * 0.035 * (1 - t * 0.5),
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.55),
      );
      canvas.drawCircle(
        tip,
        size.width * 0.016,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    // 月牙扫过后的细碎月华
    for (var i = 0; i < 10; i++) {
      final u = _noise(ult.hashCode, i);
      final a = base + sweepTotal * progress * u;
      final rr = radius * (0.86 + u * 0.2);
      final p = center + Offset(math.cos(a), math.sin(a)) * rr;
      canvas.drawCircle(
        p,
        size.width * (0.003 + u * 0.005),
        Paint()..color = Palette.gold.withValues(alpha: alpha * 0.6 * (1 - progress * u)),
      );
    }
  }

}
