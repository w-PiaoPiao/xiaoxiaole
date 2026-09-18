import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 敌方角色的绘制参数。
class EnemyPose {
  /// 待机动画时间（秒）。
  final double time;

  /// 敌人剩余生命比例，用来决定「相位」（越残血越狰狞）。
  final double hpRatio;

  /// 受击白闪强度 0~1。
  final double hitFlash;

  /// 出手时的前冲姿态 0~1。
  final double lunge;

  /// 是否处于狂暴。
  final bool enraged;

  /// 败北消散进度 0~1。
  final double dissolve;

  const EnemyPose({
    required this.time,
    required this.hpRatio,
    this.hitFlash = 0,
    this.lunge = 0,
    this.enraged = false,
    this.dissolve = 0,
  });

  /// 相位 0~3，越接近 3 越残破。
  int get phase {
    if (hpRatio > 0.75) return 0;
    if (hpRatio > 0.5) return 1;
    if (hpRatio > 0.25) return 2;
    return 3;
  }
}

/// 用矢量图形直接画出敌方角色：一位悬浮的暗影魔女。
///
/// 造型思路是「深色剪影 + 主题色轮廓光」：躯干、长发、裙摆分层绘制，
/// 靠渐变填充与定向轮廓光做出体积感，不依赖任何位图资源。
/// 身形比例（相对画布高度 h）：
///   角尖 0.05 · 头顶 0.13 · 眼睛 0.205 · 下巴 0.27 · 肩 0.325
///   胸 0.40 · 腰 0.53 · 胯 0.60 · 裙摆 0.90
class EnemyArt {
  const EnemyArt._();

  static const double _hornTip = 0.062;
  static const double _headTop = 0.125;
  static const double _eyeY = 0.205;
  static const double _shoulderY = 0.325;
  static const double _bustY = 0.40;
  static const double _waistY = 0.53;
  static const double _hipY = 0.60;
  static const double _hemY = 0.90;

  static void paint(Canvas canvas, Size size, Color theme, EnemyPose pose) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final t = pose.time;
    final breath = math.sin(t * 1.5) * h * 0.008;
    final shift = pose.lunge * h * 0.045;

    _paintAura(canvas, size, theme, pose);
    _paintMagicCircle(canvas, size, theme, t, pose);
    _paintCrystals(canvas, size, theme, t, pose);

    canvas.save();
    canvas.translate(cx, breath + shift);

    final hair = _buildHair(w, h, t, pose, back: true);
    final body = _buildBody(w, h, t, pose);
    final arms = _buildArms(w, h, t, pose);
    final frontHair = _buildFrontHair(w, h, t, pose);
    final horns = _buildHorns(w, h, t);

    _fill(canvas, hair, theme, pose, 0.62, const Color(0xFF1B1030), const Color(0xFF0A0514));
    _fill(canvas, body, theme, pose, 1.0, const Color(0xFF4E3580), const Color(0xFF180E2C));
    _paintDressShading(canvas, w, h, theme, pose);
    _fill(canvas, arms, theme, pose, 0.96, const Color(0xFF33204F), const Color(0xFF150C28));
    _paintChestGem(canvas, w, h, theme, pose);
    _fill(canvas, horns, theme, pose, 0.9, const Color(0xFF33204F), const Color(0xFF120A22));
    _fill(canvas, frontHair, theme, pose, 0.88, const Color(0xFF1D1132), const Color(0xFF0A0516));

    _paintFace(canvas, w, h, theme, pose, t);
    _paintCracks(canvas, w, h, pose);

    canvas.restore();
  }

  // ------------------------------------------------------------ 氛围

  static void _paintAura(Canvas canvas, Size size, Color theme, EnemyPose pose) {
    final intensity = 0.20 + pose.phase * 0.075 + (pose.enraged ? 0.16 : 0.0);
    final alpha = intensity * (1 - pose.dissolve);
    final center = Offset(size.width * 0.5, size.height * 0.55);
    final radius = size.width * (0.60 + pose.phase * 0.04);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          theme.withValues(alpha: alpha),
          theme.withValues(alpha: alpha * 0.28),
          Colors.transparent,
        ], const [0.0, 0.42, 1.0]),
    );
  }

  static void _paintMagicCircle(
    Canvas canvas,
    Size size,
    Color theme,
    double t,
    EnemyPose pose,
  ) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.875;
    final rx = size.width * (0.30 + 0.008 * math.sin(t * 1.2));
    final ry = rx * 0.24;
    final alpha = (1 - pose.dissolve);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(1.0, ry / rx);
    canvas.translate(-cx, -cy);
    final center = Offset(cx, cy);

    // 光晕底盘
    canvas.drawCircle(
      center,
      rx,
      Paint()
        ..shader = ui.Gradient.radial(center, rx, [
          theme.withValues(alpha: 0.20 * alpha),
          Colors.transparent,
        ]),
    );

    canvas.drawArc(
      Rect.fromCenter(center: center, width: rx * 2, height: rx * 2),
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.0055
        ..color = theme.withValues(alpha: 0.55 * alpha),
    );
    canvas.drawArc(
      Rect.fromCenter(center: center, width: rx * 1.55, height: rx * 1.55),
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.0028
        ..color = theme.withValues(alpha: 0.38 * alpha),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 0.32);
    final tick = Paint()
      ..color = theme.withValues(alpha: 0.8 * alpha)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.005;
    for (var i = 0; i < 16; i++) {
      final angle = math.pi * 2 / 16 * i;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final long = i.isEven;
      canvas.drawLine(dir * rx * (long ? 0.82 : 0.88), dir * rx * 0.99, tick);
    }
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-t * 0.2);
    final rune = Paint()..color = theme.withValues(alpha: 0.6 * alpha);
    for (var i = 0; i < 8; i++) {
      final angle = math.pi * 2 / 8 * i;
      final p = Offset(math.cos(angle), math.sin(angle)) * rx * 1.24;
      canvas.drawCircle(p, size.width * 0.0075, rune);
    }
    canvas.restore();
    canvas.restore();
  }

  static void _paintCrystals(
    Canvas canvas,
    Size size,
    Color theme,
    double t,
    EnemyPose pose,
  ) {
    final count = math.max(2, 6 - pose.phase);
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    for (var i = 0; i < count; i++) {
      final base = math.pi * 2 / count * i;
      final angle = base + t * 0.4;
      final p = Offset(
        cx + size.width * 0.40 * math.cos(angle),
        cy + size.height * 0.13 * math.sin(angle * 1.3),
      );
      final s = size.width * (0.016 + 0.005 * math.sin(t * 2 + i));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle);
      final shard = Path()
        ..moveTo(0, -s * 1.7)
        ..lineTo(s * 0.8, 0)
        ..lineTo(0, s * 1.7)
        ..lineTo(-s * 0.8, 0)
        ..close();
      canvas.drawPath(shard, Paint()..color = theme.withValues(alpha: 0.8 * (1 - pose.dissolve)));
      canvas.drawPath(
        shard,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.24
          ..color = Colors.white.withValues(alpha: 0.55 * (1 - pose.dissolve)),
      );
      canvas.restore();
    }
  }

  // ------------------------------------------------------------ 剪影分层

  /// 统一的填充：竖向渐变 + 定向轮廓光 + 受击闪白 + 消散粒子。
  static void _fill(
    Canvas canvas,
    Path path,
    Color theme,
    EnemyPose pose,
    double layer,
    Color top,
    Color bottom,
  ) {
    final bounds = path.getBounds();

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [top, bottom]),
    );

    // 主轮廓光：左上偏亮，右下渐隐，制造方向感
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          [
            Color.lerp(theme, Colors.white, 0.45)!.withValues(alpha: 0.95 * layer),
            theme.withValues(alpha: 0.55 * layer),
            theme.withValues(alpha: 0.06 * layer),
          ],
          const [0.0, 0.45, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    // 内侧提亮，给剪影一点厚度
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.13 * layer),
    );

    if (pose.hitFlash > 0.01) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: pose.hitFlash * 0.6 * layer),
      );
    }

    if (pose.dissolve > 0.01) {
      final rng = math.Random(bounds.hashCode);
      for (var i = 0; i < 22; i++) {
        final p = Offset(
          bounds.left + rng.nextDouble() * bounds.width,
          bounds.bottom - rng.nextDouble() * bounds.height * pose.dissolve * 1.5,
        );
        canvas.drawCircle(
          p,
          0.8 + rng.nextDouble() * 2.2,
          Paint()
            ..color = theme.withValues(alpha: (1 - pose.dissolve) * 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
        );
      }
    }
  }

  /// 躯干 + 头部 + 脖颈。
  static Path _buildBody(double w, double h, double t, EnemyPose pose) {
    final sway = math.sin(t * 1.1) * w * 0.010;
    final hemWave = math.sin(t * 0.9) * h * 0.008;
    final path = Path()
      ..moveTo(-w * 0.108, h * _shoulderY)
      ..quadraticBezierTo(-w * 0.100, h * _bustY, -w * 0.062, h * _waistY)
      ..quadraticBezierTo(-w * 0.090, h * _hipY, -w * 0.230, h * 0.79)
      ..quadraticBezierTo(-w * 0.286, h * 0.855, -w * 0.268, h * _hemY)
      // 波浪裙摆
      ..quadraticBezierTo(-w * 0.150, h * (0.862 + hemWave / h), -w * 0.075, h * 0.895)
      ..quadraticBezierTo(-w * 0.010 + sway, h * (0.925 + hemWave / h), w * 0.078, h * 0.893)
      ..quadraticBezierTo(w * 0.155, h * (0.860 - hemWave / h), w * 0.268, h * _hemY)
      ..quadraticBezierTo(w * 0.286, h * 0.855, w * 0.230, h * 0.79)
      ..quadraticBezierTo(w * 0.090, h * _hipY, w * 0.062, h * _waistY)
      ..quadraticBezierTo(w * 0.100, h * _bustY, w * 0.108, h * _shoulderY)
      // 肩线
      ..quadraticBezierTo(w * 0.055, h * 0.297, 0, h * 0.301)
      ..quadraticBezierTo(-w * 0.055, h * 0.297, -w * 0.108, h * _shoulderY)
      ..close();

    // 头部
    path.addPath(
      Path()
        ..addOval(Rect.fromCenter(
          center: Offset(sway * 0.5, h * (_headTop + _eyeY) / 2 + h * 0.012),
          width: w * 0.132,
          height: h * 0.155,
        )),
      Offset.zero,
    );

    // 脖颈
    path.addPath(
      Path()
        ..moveTo(-w * 0.030, h * 0.255)
        ..lineTo(w * 0.030, h * 0.255)
        ..lineTo(w * 0.042, h * 0.315)
        ..lineTo(-w * 0.042, h * 0.315)
        ..close(),
      Offset.zero,
    );
    return path;
  }

  /// 垂在身侧的双臂。
  static Path _buildArms(double w, double h, double t, EnemyPose pose) {
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      final sway = math.sin(t * 1.3 + (side > 0 ? 1.2 : 0)) * w * 0.006;
      // 上臂 + 小臂
      path.addPath(
        Path()
          ..moveTo(w * 0.104 * side, h * 0.335)
          ..quadraticBezierTo(
            w * 0.163 * side,
            h * 0.44,
            w * 0.148 * side + sway,
            h * 0.545,
          )
          ..quadraticBezierTo(
            w * 0.142 * side + sway,
            h * 0.60,
            w * 0.126 * side + sway,
            h * 0.635,
          )
          ..quadraticBezierTo(
            w * 0.112 * side,
            h * 0.60,
            w * 0.104 * side,
            h * 0.545,
          )
          ..quadraticBezierTo(
            w * 0.106 * side,
            h * 0.44,
            w * 0.070 * side,
            h * 0.352,
          )
          ..close(),
        Offset.zero,
      );
      // 手
      path.addPath(
        Path()
          ..addOval(Rect.fromCenter(
            center: Offset(w * 0.124 * side + sway, h * 0.652),
            width: w * 0.032,
            height: h * 0.028,
          )),
        Offset.zero,
      );
    }
    return path;
  }

  /// 身后的长发主体。
  static Path _buildHair(double w, double h, double t, EnemyPose pose, {required bool back}) {
    final flutter = 0.010 + pose.phase * 0.004;
    final path = Path();
    final spread = back ? 1.0 : 0.66;
    for (final side in [-1.0, 1.0]) {
      final wave = math.sin(t * 1.5 + (side > 0 ? 0.9 : 0)) * h * flutter;
      final wave2 = math.sin(t * 1.05 + (side > 0 ? 2.1 : 1.3)) * h * flutter;
      final wave3 = math.sin(t * 1.8 + side) * h * flutter * 0.7;
      path.addPath(
        Path()
          ..moveTo(w * 0.046 * side, h * 0.115)
          ..quadraticBezierTo(
            w * 0.140 * side * spread,
            h * 0.20 + wave,
            w * 0.150 * side * spread,
            h * 0.44 + wave2,
          )
          ..quadraticBezierTo(
            w * 0.140 * side * spread,
            h * 0.62 + wave,
            w * 0.104 * side * spread,
            h * 0.80 + wave2 * 1.6,
          )
          ..quadraticBezierTo(
            w * 0.126 * side * spread,
            h * 0.58 + wave3,
            w * 0.112 * side * spread,
            h * 0.38 + wave3,
          )
          ..quadraticBezierTo(
            w * 0.098 * side * spread,
            h * 0.21 + wave3,
            w * 0.016 * side,
            h * 0.145,
          )
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  /// 贴着脸颊的刘海，让头部有层次。
  static Path _buildFrontHair(double w, double h, double t, EnemyPose pose) {
    final sway = math.sin(t * 1.4) * w * 0.005;
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      path.addPath(
        Path()
          ..moveTo(w * 0.012 * side, h * 0.115)
          ..quadraticBezierTo(
            w * 0.092 * side,
            h * 0.155,
            w * 0.108 * side + sway,
            h * 0.27,
          )
          ..quadraticBezierTo(
            w * 0.088 * side + sway,
            h * 0.40,
            w * 0.052 * side + sway,
            h * 0.50,
          )
          ..quadraticBezierTo(
            w * 0.070 * side,
            h * 0.36,
            w * 0.056 * side,
            h * 0.26,
          )
          ..quadraticBezierTo(
            w * 0.040 * side,
            h * 0.17,
            w * 0.004 * side,
            h * 0.145,
          )
          ..close(),
        Offset.zero,
      );
    }
    // 头顶发盖
    path.addPath(
      Path()
        ..addOval(Rect.fromCenter(
          center: Offset(0, h * 0.152),
          width: w * 0.152,
          height: h * 0.088,
        )),
      Offset.zero,
    );
    return path;
  }

  static Path _buildHorns(double w, double h, double t) {
    final sway = math.sin(t * 1.3) * w * 0.005;
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      path.addPath(
        Path()
          ..moveTo(w * 0.030 * side, h * 0.150)
          ..quadraticBezierTo(
            w * 0.090 * side,
            h * 0.112,
            w * 0.104 * side + sway,
            h * _hornTip,
          )
          ..quadraticBezierTo(
            w * 0.082 * side,
            h * 0.106,
            w * 0.062 * side,
            h * 0.142,
          )
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  /// 裙装的明暗与衣褶：让深色剪影内部有可读的结构。
  static void _paintDressShading(Canvas canvas, double w, double h, Color theme, EnemyPose pose) {
    final hem = h * _hemY;
    // 胸口到腰的高光
    final highlight = Path()
      ..moveTo(-w * 0.086, h * (_bustY - 0.03))
      ..quadraticBezierTo(-w * 0.040, h * _waistY, -w * 0.072, h * (_hipY + 0.03))
      ..quadraticBezierTo(0, h * 0.655, w * 0.072, h * (_hipY + 0.03))
      ..quadraticBezierTo(w * 0.040, h * _waistY, w * 0.086, h * (_bustY - 0.03))
      ..quadraticBezierTo(0, h * (_bustY - 0.065), -w * 0.086, h * (_bustY - 0.03))
      ..close();
    canvas.drawPath(
      highlight,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * _bustY),
          Offset(0, h * _hipY),
          [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.0)],
        ),
    );

    // 裙摆衣褶
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.10);
    for (final offset in [-0.14, -0.06, 0.05, 0.13]) {
      final path = Path()
        ..moveTo(w * offset * 0.55, h * (_hipY + 0.02))
        ..quadraticBezierTo(
          w * offset,
          h * 0.74,
          w * offset * 1.75,
          hem - h * 0.012,
        );
      canvas.drawPath(path, fold);
    }

    // 裙摆下缘的轮廓提亮
    canvas.drawPath(
      Path()
        ..moveTo(-w * 0.268, hem)
        ..quadraticBezierTo(-w * 0.150, h * 0.862, -w * 0.075, h * 0.895)
        ..quadraticBezierTo(0, h * 0.925, w * 0.078, h * 0.893)
        ..quadraticBezierTo(w * 0.155, h * 0.860, w * 0.268, hem),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = theme.withValues(alpha: 0.55 * (1 - pose.dissolve)),
    );

    // 肩颈处的主题色披肩，强调上半身结构
    final collar = Path()
      ..moveTo(-w * 0.108, h * _shoulderY)
      ..quadraticBezierTo(0, h * 0.288, w * 0.108, h * _shoulderY)
      ..quadraticBezierTo(w * 0.060, h * 0.352, 0, h * 0.358)
      ..quadraticBezierTo(-w * 0.060, h * 0.352, -w * 0.108, h * _shoulderY)
      ..close();
    canvas.drawPath(
      collar,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.29),
          Offset(0, h * 0.36),
          [
            theme.withValues(alpha: 0.55),
            theme.withValues(alpha: 0.05),
          ],
        ),
    );
  }

  /// 胸口的契约宝石，随相位变亮。
  static void _paintChestGem(Canvas canvas, double w, double h, Color theme, EnemyPose pose) {
    final glow = 0.5 + pose.phase * 0.14 + (pose.enraged ? 0.3 : 0.0);
    final center = Offset(0, h * 0.415);
    final s = w * 0.022;
    final gem = Path()
      ..moveTo(center.dx, center.dy - s * 1.4)
      ..lineTo(center.dx + s, center.dy)
      ..lineTo(center.dx, center.dy + s * 1.4)
      ..lineTo(center.dx - s, center.dy)
      ..close();
    canvas.drawPath(
      gem,
      Paint()
        ..color = theme.withValues(alpha: glow * 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
    );
    canvas.drawPath(gem, Paint()..color = Color.lerp(theme, Colors.white, 0.55)!);
  }

  /// 面部：一张浅色的「脸」，配合发光的眼睛。
  static void _paintFace(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
    double t,
  ) {
    // 与 _buildBody 中头部椭圆的圆心保持一致
    final faceCenter = Offset(0, h * 0.177);
    final faceRect = Rect.fromCenter(
      center: faceCenter,
      width: w * 0.120,
      height: h * 0.132,
    );
    canvas.drawOval(
      faceRect,
      Paint()
        ..shader = ui.Gradient.linear(faceRect.topCenter, faceRect.bottomCenter, [
          const Color(0xFFFBEFF4),
          const Color(0xFFE0C2D4),
          const Color(0xFFA9859F),
        ]),
    );

    final blink = math.sin(t * 0.85) > 0.965 ? 0.12 : 1.0;
    final glow = 0.65 + pose.phase * 0.12 + (pose.enraged ? 0.4 : 0.0);
    for (final side in [-1.0, 1.0]) {
      final p = Offset(w * 0.032 * side, h * _eyeY);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: w * 0.046, height: h * 0.024 * blink),
        Paint()
          ..color = theme.withValues(alpha: glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.014),
      );
      canvas.drawOval(
        Rect.fromCenter(center: p, width: w * 0.032, height: h * 0.017 * blink),
        Paint()..color = Colors.white.withValues(alpha: 0.98),
      );
      canvas.drawOval(
        Rect.fromCenter(center: p, width: w * 0.012, height: h * 0.010 * blink),
        Paint()..color = theme,
      );
    }
  }

  static void _paintCracks(Canvas canvas, double w, double h, EnemyPose pose) {
    if (pose.phase <= 0) return;
    final alpha = (0.22 + pose.phase * 0.2).clamp(0.0, 0.95);
    final rng = math.Random(97 + pose.phase);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFFFE9F2).withValues(alpha: alpha);
    for (var i = 0; i < pose.phase * 3; i++) {
      var p = Offset(
        (rng.nextDouble() - 0.5) * w * 0.34,
        h * (0.34 + rng.nextDouble() * 0.42),
      );
      final path = Path()..moveTo(p.dx, p.dy);
      for (var k = 0; k < 3; k++) {
        p += Offset((rng.nextDouble() - 0.5) * w * 0.06, rng.nextDouble() * h * 0.045);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}
