import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engine/levels.dart';

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

  /// 受击后仰强度 0~1：被击中时整个人向后一顿。
  final double recoil;

  /// 是否处于狂暴。
  final bool enraged;

  /// 败北消散进度 0~1。
  final double dissolve;

  const EnemyPose({
    required this.time,
    required this.hpRatio,
    this.hitFlash = 0,
    this.lunge = 0,
    this.recoil = 0,
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

/// 用矢量图形直接画出敌方角色。六个原型各有一套剪影：
/// 鬼火是火焰幽灵、守卫是石甲巨人、刺客是兜帽双刀客、巫女与魔女是
/// 悬浮魔女（后者多一对深渊触须）、终焉是弯角斗篷魔王。
/// 统一思路是「深色剪影 + 主题色轮廓光」：靠渐变填充与定向轮廓光做出
/// 体积感，不依赖任何位图资源。
/// 剪影缓存的键：量化时间 + 尺寸 + 配色 + 阶段 + 原型。
@immutable
class _SilhouetteKey {
  final double t;
  final double w;
  final double h;
  final Color theme;
  final int phase;
  final bool enraged;
  final EnemyArchetype archetype;

  /// 白闪的量化档位（0~10）。白闪是逐帧衰减的，但量化到十档之后肉眼
  /// 分辨不出与连续淡出的差别——换来的是命中期间不再逐帧重建整幅剪影。
  final int flashStep;

  const _SilhouetteKey(
    this.t,
    this.w,
    this.h,
    this.theme,
    this.phase,
    this.enraged,
    this.archetype,
    this.flashStep,
  );

  @override
  bool operator ==(Object other) =>
      other is _SilhouetteKey &&
      other.t == t &&
      other.w == w &&
      other.h == h &&
      other.theme == theme &&
      other.phase == phase &&
      other.enraged == enraged &&
      other.archetype == archetype &&
      other.flashStep == flashStep;

  @override
  int get hashCode => Object.hash(t, w, h, theme, phase, enraged, archetype);
}

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

  static void paint(
    Canvas canvas,
    Size size,
    Color theme,
    EnemyPose pose, {
    EnemyArchetype archetype = EnemyArchetype.enchantress,
  }) {
    // 首帧布局完成前 CustomPaint 可能以零尺寸触发一次 paint，此时任何
    // 渐变都会拿到 NaN 偏移。直接跳过，等真实尺寸的那一帧再画。
    if (size.width <= 0 || size.height <= 0) return;
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

    // 受击后仰：整体后撤一点、轻微倾斜，配合白闪读出"被打中"的顿挫
    if (pose.recoil > 0.01) {
      final r = pose.recoil;
      canvas.translate(0, -h * 0.020 * r);
      canvas.rotate(0.022 * r * math.sin(t * 26));
      canvas.scale(1 - 0.022 * r);
    }

    // 剪影本身是低频摆动（约 0.15~0.2 Hz），把它按 1/8 秒量化后录成 Picture
    // 复用，省掉每帧重建五个复杂 Path 与二十来个渐变着色器的开销。
    //
    // 受击白闪也进缓存键（量化成十档）：白闪要持续约 0.38 秒，逐帧实时绘制
    // 就是二十多帧的全量重建；量化之后最多重建十次，肉眼分辨不出差别。
    // 消散（战败）每局只播一次，仍走实时路径——它还要配合整幅淡出。
    final canCache = pose.dissolve <= 0.01;

    // 消散（战败）：整幅剪影一起淡出。
    //
    // 这里用一次 saveLayer 统一处理，而不是让内部每一笔各自乘系数——剪影有
    // 二十来层填充（本体、发丝、面部、胸口宝石、裂纹……），漏掉任何一层都会
    // 留下"光环没了、人还完好站着"的残留。消散每局最多播一次、且此时战斗
    // 已经结束，这一层离屏缓冲的代价是划算的。
    final dissolving = pose.dissolve > 0.01;
    if (dissolving) {
      canvas.saveLayer(
        Rect.fromLTWH(-w, -h * 0.4, w * 2, h * 1.8),
        Paint()
          ..color = Colors.white.withValues(
            alpha: (1 - pose.dissolve).clamp(0.0, 1.0),
          ),
      );
    }

    if (canCache) {
      canvas.drawPicture(_silhouette(w, h, t, theme, pose, archetype));
    } else {
      _paintSilhouette(canvas, w, h, t, theme, pose, archetype);
    }

    if (dissolving) canvas.restore();

    canvas.restore();
  }

  // ------------------------------------------------------------ 剪影缓存

  /// 量化后的时间：摆动是低频运动，1/8 秒的粒度肉眼分辨不出，
  /// 但 Path 与着色器的重建次数降到约 1/8。
  static double _quantize(double t) => (t * 8).floorToDouble() / 8;

  static ui.Picture? _cachedSilhouette;
  static _SilhouetteKey? _cachedKey;

  static ui.Picture _silhouette(
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    final key = _SilhouetteKey(
      _quantize(t),
      w,
      h,
      theme,
      pose.phase,
      pose.enraged,
      archetype,
      (pose.hitFlash.clamp(0.0, 1.0) * 10).round(),
    );
    if (_cachedKey == key && _cachedSilhouette != null) {
      return _cachedSilhouette!;
    }
    _cachedSilhouette?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintSilhouette(canvas, w, h, _quantize(t), theme, pose, archetype);
    _cachedSilhouette = recorder.endRecording();
    _cachedKey = key;
    return _cachedSilhouette!;
  }

  /// 按原型分发到各自的剪影绘制。
  static void _paintSilhouette(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    switch (archetype) {
      case EnemyArchetype.wisp:
        _paintWisp(canvas, w, h, t, theme, pose);
      case EnemyArchetype.guardian:
        _paintGuardian(canvas, w, h, t, theme, pose);
      case EnemyArchetype.assassin:
        _paintAssassin(canvas, w, h, t, theme, pose);
      case EnemyArchetype.witch:
      case EnemyArchetype.enchantress:
        _paintEnchantress(canvas, w, h, t, theme, pose, archetype);
      case EnemyArchetype.warlord:
        _paintWarlord(canvas, w, h, t, theme, pose);
    }
  }

  // ============================================================ 巫女 / 魔女

  /// 悬浮的暗影魔女（血月巫女与深渊魔女共用一套身形）。
  /// 身形比例（相对画布高度 h）：
  ///   角尖 0.05 · 头顶 0.13 · 眼睛 0.205 · 下巴 0.27 · 肩 0.325
  ///   胸 0.40 · 腰 0.53 · 胯 0.60 · 裙摆 0.90
  /// 深渊魔女（enchantress）比巫女多一对从肩后探出的深渊触须——
  /// 同族不同阶，靠触须与更深的配色区分。
  static void _paintEnchantress(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    if (archetype == EnemyArchetype.enchantress) {
      _fill(
        canvas,
        _buildTendrils(w, h, t, pose),
        theme,
        pose,
        0.55,
        const Color(0xFF2A0F1E),
        const Color(0xFF0D0410),
      );
    }
    final hair = _buildHair(w, h, t, pose, back: true);
    final body = _buildBody(w, h, t, pose);
    final arms = _buildArms(w, h, t, pose);
    final frontHair = _buildFrontHair(w, h, t, pose);
    final horns = _buildHorns(w, h, t);

    _fill(
      canvas,
      hair,
      theme,
      pose,
      0.62,
      const Color(0xFF1B1030),
      const Color(0xFF0A0514),
    );
    _fill(
      canvas,
      body,
      theme,
      pose,
      1.0,
      const Color(0xFF4E3580),
      const Color(0xFF180E2C),
    );
    _paintDressShading(canvas, w, h, theme, pose);
    _fill(
      canvas,
      arms,
      theme,
      pose,
      0.96,
      const Color(0xFF33204F),
      const Color(0xFF150C28),
    );
    _paintChestGem(canvas, w, h, theme, pose);
    _fill(
      canvas,
      horns,
      theme,
      pose,
      0.9,
      const Color(0xFF33204F),
      const Color(0xFF120A22),
    );
    _fill(
      canvas,
      frontHair,
      theme,
      pose,
      0.88,
      const Color(0xFF1D1132),
      const Color(0xFF0A0516),
    );

    _paintFace(canvas, w, h, theme, pose, t);
    _paintCracks(canvas, w, h, pose);
  }

  /// 深渊魔女肩后的触须：细长的锥形曲线，随呼吸缓慢摆动。
  static Path _buildTendrils(double w, double h, double t, EnemyPose pose) {
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      final sway = math.sin(t * 1.2 + (side > 0 ? 1.6 : 0)) * w * 0.02;
      path.addPath(
        Path()
          ..moveTo(w * 0.09 * side, h * 0.34)
          ..quadraticBezierTo(
            w * 0.24 * side,
            h * 0.24 + sway,
            w * 0.30 * side + sway,
            h * 0.10,
          )
          ..quadraticBezierTo(
            w * 0.26 * side + sway,
            h * 0.13,
            w * 0.20 * side,
            h * 0.26,
          )
          ..quadraticBezierTo(
            w * 0.15 * side,
            h * 0.32,
            w * 0.09 * side,
            h * 0.34,
          )
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  // ============================================================ 迷雾鬼火

  /// 火焰幽灵：一团青色的火苗，底宽上尖，内里是更亮的焰心与两只空洞眼。
  /// 没有身体结构——它的"攻击性"来自形态本身的飘忽。
  static void _paintWisp(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    // 外焰：泪滴形，随时间轻轻摇曳，低相位时火焰更收敛。
    final lean = math.sin(t * 1.6) * w * 0.035;
    final flicker = math.sin(t * 3.1) * h * 0.012;
    final flame = Path()
      ..moveTo(0, h * (0.06 + flicker / h) + lean)
      ..quadraticBezierTo(w * 0.30, h * 0.22, w * 0.34, h * 0.50)
      ..quadraticBezierTo(w * 0.36, h * 0.74, w * 0.20, h * 0.86)
      // 底缘的火舌波浪
      ..quadraticBezierTo(w * 0.12, h * 0.92, w * 0.05, h * 0.86)
      ..quadraticBezierTo(0, h * 0.94, -w * 0.06, h * 0.86)
      ..quadraticBezierTo(-w * 0.13, h * 0.92, -w * 0.20, h * 0.86)
      ..quadraticBezierTo(-w * 0.36, h * 0.74, -w * 0.34, h * 0.50)
      ..quadraticBezierTo(
        -w * 0.30,
        h * 0.22,
        0,
        h * (0.06 + flicker / h) + lean,
      )
      ..close();
    _fill(
      canvas,
      flame,
      theme,
      pose,
      0.9,
      const Color(0xFF2E6E68),
      const Color(0xFF0E2724),
    );

    // 焰心：一道竖向亮带，是整个身体的"光源"。
    final core = Path()
      ..moveTo(0, h * 0.17 + lean * 0.6)
      ..quadraticBezierTo(w * 0.14, h * 0.34, w * 0.15, h * 0.55)
      ..quadraticBezierTo(w * 0.14, h * 0.72, 0, h * 0.80)
      ..quadraticBezierTo(-w * 0.14, h * 0.72, -w * 0.15, h * 0.55)
      ..quadraticBezierTo(-w * 0.14, h * 0.34, 0, h * 0.17 + lean * 0.6)
      ..close();
    canvas.drawPath(
      core,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, h * 0.50),
          h * 0.34,
          [
            Color.lerp(theme, Colors.white, 0.55)!.withValues(alpha: 0.55),
            theme.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // 双眼：焰心里的两只深色空穴，比任何表情都更像"残念"。
    final blink = math.sin(t * 0.85) > 0.965 ? 0.12 : 1.0;
    for (final side in [-1.0, 1.0]) {
      final p = Offset(w * 0.062 * side + lean * 0.5, h * 0.40);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: w * 0.052, height: h * 0.042 * blink),
        Paint()..color = const Color(0xFF03110F).withValues(alpha: 0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: p.translate(0, -h * 0.004),
          width: w * 0.022,
          height: h * 0.014 * blink,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }

    // 底部的雾尾：三缕从火焰下方拖出的烟。
    final mist = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final drift = math.sin(t * 1.1 + i * 2.2) * w * 0.03;
      final x = (i - 1) * w * 0.12;
      mist
        ..strokeWidth = w * (0.030 - i * 0.006)
        ..color = theme.withValues(
          alpha: (0.30 - i * 0.07) * (1 - pose.dissolve),
        );
      canvas.drawPath(
        Path()
          ..moveTo(x, h * 0.87)
          ..quadraticBezierTo(
            x + drift,
            h * 0.93,
            x + drift * 1.8,
            h * (0.97 + i * 0.01),
          ),
        mist,
      );
    }
  }

  // ============================================================ 石甲守卫

  /// 石甲巨人：宽厚的梯形石甲 + 一侧巨盾 + 头盔缝眼，脚下踩着碎石。
  /// 它的存在感来自"宽"——同一画布里它比其他角色横向占得多。
  static void _paintGuardian(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    // 脚下的浮空碎石：随时间轻轻升降。
    for (var i = 0; i < 4; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final bob = math.sin(t * 1.3 + i * 1.9) * h * 0.012;
      final rock = Path()
        ..moveTo(w * (0.16 + i * 0.05) * side, h * 0.93 + bob)
        ..lineTo(w * (0.22 + i * 0.05) * side, h * 0.89 + bob)
        ..lineTo(w * (0.28 + i * 0.05) * side, h * 0.93 + bob)
        ..lineTo(w * (0.22 + i * 0.05) * side, h * 0.97 + bob)
        ..close();
      _fill(
        canvas,
        rock,
        theme,
        pose,
        0.5,
        const Color(0xFF5C4A22),
        const Color(0xFF241C0C),
      );
    }

    // 巨盾：举在身前（画面右侧）的圆形塔盾，带一圈铆钉环。
    final shieldC = Offset(w * 0.30, h * 0.50);
    final shieldR = w * 0.155;
    canvas.drawCircle(
      shieldC,
      shieldR,
      Paint()
        ..shader = ui.Gradient.radial(
          shieldC.translate(-shieldR * 0.3, -shieldR * 0.3),
          shieldR * 1.7,
          const [Color(0xFF8A6E33), Color(0xFF3D2E10), Color(0xFF1A1206)],
          const [0.0, 0.55, 1.0],
        ),
    );
    canvas.drawCircle(
      shieldC,
      shieldR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..color = theme.withValues(alpha: 0.75 * (1 - pose.dissolve)),
    );
    canvas.drawCircle(
      shieldC,
      shieldR * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.006
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    for (var i = 0; i < 8; i++) {
      final a = math.pi * 2 / 8 * i + t * 0.15;
      canvas.drawCircle(
        shieldC.translate(
          shieldR * 0.82 * math.cos(a),
          shieldR * 0.82 * math.sin(a),
        ),
        w * 0.011,
        Paint()..color = theme.withValues(alpha: 0.8 * (1 - pose.dissolve)),
      );
    }
    // 盾心的纹章：竖直的棱形槽。
    canvas.drawPath(
      Path()
        ..moveTo(shieldC.dx, shieldC.dy - shieldR * 0.4)
        ..lineTo(shieldC.dx + shieldR * 0.14, shieldC.dy)
        ..lineTo(shieldC.dx, shieldC.dy + shieldR * 0.4)
        ..lineTo(shieldC.dx - shieldR * 0.14, shieldC.dy)
        ..close(),
      Paint()..color = theme.withValues(alpha: 0.45 * (1 - pose.dissolve)),
    );

    // 躯干：上宽下略窄的石甲，两肩是凸出的甲块。
    final body = Path()
      ..moveTo(-w * 0.30, h * 0.30)
      ..quadraticBezierTo(-w * 0.36, h * 0.46, -w * 0.30, h * 0.66)
      ..quadraticBezierTo(-w * 0.26, h * 0.88, -w * 0.16, h * 0.90)
      ..lineTo(w * 0.16, h * 0.90)
      ..quadraticBezierTo(w * 0.26, h * 0.88, w * 0.30, h * 0.66)
      ..quadraticBezierTo(w * 0.36, h * 0.46, w * 0.30, h * 0.30)
      // 肩线与肩甲
      ..quadraticBezierTo(w * 0.22, h * 0.245, 0, h * 0.25)
      ..quadraticBezierTo(-w * 0.22, h * 0.245, -w * 0.30, h * 0.30)
      ..close();
    _fill(
      canvas,
      body,
      theme,
      pose,
      1.0,
      const Color(0xFF7A6230),
      const Color(0xFF241A0A),
    );

    // 双肩甲块
    for (final side in [-1.0, 1.0]) {
      final pad = Path()
        ..moveTo(w * 0.24 * side, h * 0.26)
        ..quadraticBezierTo(
          w * 0.40 * side,
          h * 0.27,
          w * 0.42 * side,
          h * 0.36,
        )
        ..quadraticBezierTo(
          w * 0.40 * side,
          h * 0.44,
          w * 0.30 * side,
          h * 0.44,
        )
        ..quadraticBezierTo(
          w * 0.22 * side,
          h * 0.40,
          w * 0.24 * side,
          h * 0.26,
        )
        ..close();
      _fill(
        canvas,
        pad,
        theme,
        pose,
        0.95,
        const Color(0xFF8A7038),
        const Color(0xFF2C2008),
      );
    }

    // 甲片缝：三道横缝让石甲有"块"的读感。
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.30);
    for (final y in [0.40, 0.54, 0.68]) {
      final width = w * (0.30 - (y - 0.40) * 0.22);
      canvas.drawLine(Offset(-width, h * y), Offset(width, h * y), seam);
    }

    // 头盔：矮方盔 + 一道横向发光缝眼。
    final helm = Path()
      ..moveTo(-w * 0.11, h * 0.245)
      ..lineTo(-w * 0.12, h * 0.14)
      ..quadraticBezierTo(0, h * 0.095, w * 0.12, h * 0.14)
      ..lineTo(w * 0.11, h * 0.245)
      ..close();
    _fill(
      canvas,
      helm,
      theme,
      pose,
      0.98,
      const Color(0xFF8A7038),
      const Color(0xFF2C2008),
    );
    // 盔顶脊线
    canvas.drawLine(
      Offset(0, h * 0.10),
      Offset(0, h * 0.20),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.014
        ..color = theme.withValues(alpha: 0.55 * (1 - pose.dissolve)),
    );
    final glow = 0.7 + pose.phase * 0.12 + (pose.enraged ? 0.35 : 0.0);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, h * 0.185),
        width: w * 0.17,
        height: h * 0.020,
      ),
      Paint()
        ..color = theme.withValues(alpha: glow * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, h * 0.185),
        width: w * 0.17,
        height: h * 0.010,
      ),
      Paint()..color = Color.lerp(theme, Colors.white, 0.6)!,
    );

    _paintCracks(canvas, w, h, pose);
  }

  // ============================================================ 影刃刺客

  /// 兜帽双刀客：瘦削的直立剪影，兜帽下只亮一只眼，身侧两道刀光，
  /// 肩后的飘带一直在动——静止时也在"猎"。
  static void _paintAssassin(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    // 肩后飘带：两条细长的丝带。
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final flutter = math.sin(t * 2.1 + i * 1.7) * w * 0.035;
      _fill(
        canvas,
        Path()
          ..moveTo(w * 0.06 * side, h * 0.30)
          ..quadraticBezierTo(
            w * 0.16 * side,
            h * 0.38 + flutter,
            w * 0.10 * side + flutter,
            h * 0.58,
          )
          ..quadraticBezierTo(
            w * 0.06 * side + flutter,
            h * 0.62,
            w * 0.03 * side + flutter * 0.5,
            h * 0.58,
          )
          ..quadraticBezierTo(
            w * 0.08 * side,
            h * 0.42,
            w * 0.02 * side,
            h * 0.31,
          )
          ..close(),
        theme,
        pose,
        0.55,
        const Color(0xFF241640),
        const Color(0xFF0C0618),
      );
    }

    // 斗篷身形：比魔女窄得多，下摆开衩，透出"轻"。
    final cloak = Path()
      ..moveTo(-w * 0.10, h * 0.28)
      ..quadraticBezierTo(-w * 0.20, h * 0.45, -w * 0.17, h * 0.66)
      ..quadraticBezierTo(-w * 0.15, h * 0.84, -w * 0.08, h * 0.92)
      // 开衩
      ..lineTo(-w * 0.035, h * 0.80)
      ..lineTo(0, h * 0.93)
      ..lineTo(w * 0.035, h * 0.80)
      ..lineTo(w * 0.08, h * 0.92)
      ..quadraticBezierTo(w * 0.15, h * 0.84, w * 0.17, h * 0.66)
      ..quadraticBezierTo(w * 0.20, h * 0.45, w * 0.10, h * 0.28)
      ..quadraticBezierTo(0, h * 0.245, -w * 0.10, h * 0.28)
      ..close();
    _fill(
      canvas,
      cloak,
      theme,
      pose,
      1.0,
      const Color(0xFF2E2150),
      const Color(0xFF0E0820),
    );

    // 兜帽头：上尖的帽形，帽檐里是纯黑的空洞。
    final hood = Path()
      ..moveTo(0, h * 0.075)
      ..quadraticBezierTo(w * 0.12, h * 0.115, w * 0.105, h * 0.235)
      ..quadraticBezierTo(w * 0.06, h * 0.27, 0, h * 0.268)
      ..quadraticBezierTo(-w * 0.06, h * 0.27, -w * 0.105, h * 0.235)
      ..quadraticBezierTo(-w * 0.12, h * 0.115, 0, h * 0.075)
      ..close();
    _fill(
      canvas,
      hood,
      theme,
      pose,
      0.95,
      const Color(0xFF241840),
      const Color(0xFF0A0518),
    );
    // 帽内阴影
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, h * 0.215),
        width: w * 0.145,
        height: h * 0.075,
      ),
      Paint()..color = const Color(0xFF050310).withValues(alpha: 0.9),
    );

    // 一只眼：刺客的凝视。另一只眼永远藏在阴影里。
    final blink = math.sin(t * 0.85) > 0.965 ? 0.12 : 1.0;
    final eye = Offset(w * 0.030, h * 0.212);
    // 亮度上限 1.0：相位与狂暴叠加后原本会算出 1.5 这种越界的 alpha。
    final eyeGlow = (0.8 + pose.phase * 0.1 + (pose.enraged ? 0.3 : 0.0)).clamp(
      0.0,
      1.0,
    );
    canvas.drawOval(
      Rect.fromCenter(center: eye, width: w * 0.040, height: h * 0.020 * blink),
      Paint()
        ..color = theme.withValues(alpha: eyeGlow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );
    canvas.drawOval(
      Rect.fromCenter(center: eye, width: w * 0.024, height: h * 0.012 * blink),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // 双刀：两道从肩侧斜向下方的刃光。
    for (final side in [-1.0, 1.0]) {
      final shiver = math.sin(t * 3.4 + (side > 0 ? 0.7 : 0)) * h * 0.006;
      final tip = Offset(w * 0.30 * side, h * (0.60 + shiver / h));
      final hilt = Offset(w * 0.115 * side, h * 0.33);
      final blade = Path()
        ..moveTo(hilt.dx + w * 0.014 * side, hilt.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - w * 0.022 * side, tip.dy - h * 0.018)
        ..lineTo(hilt.dx - w * 0.006 * side, hilt.dy + h * 0.02)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..shader = ui.Gradient.linear(hilt, tip, [
            const Color(0xFFC9B8E8).withValues(alpha: 0.9),
            Color.lerp(theme, Colors.white, 0.5)!.withValues(alpha: 0.55),
          ]),
      );
      // 刀柄
      canvas.drawLine(
        hilt.translate(-w * 0.02 * side, -h * 0.02),
        hilt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.014
          ..color = const Color(0xFF3A2C5C),
      );
    }
    _paintCracks(canvas, w, h, pose);
  }

  // ============================================================ 终焉之影

  /// 弯角魔王：几乎占满画布的巨大斗篷剪影，一对向内弯的月牙角，
  /// 胸口是一个缓缓旋转的吞噬漩涡——它"吃掉"的东西都进了那里。
  static void _paintWarlord(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    // 身后的碎星：几颗绕着它转的光点，衬托"吞噬一切"的体量。
    for (var i = 0; i < 7; i++) {
      final a = t * (0.22 + 0.03 * i) + i * 0.9;
      final rr = w * (0.42 + 0.04 * (i % 3));
      final p = Offset(
        rr * math.cos(a),
        h * 0.42 + h * 0.16 * math.sin(a * 1.4),
      );
      canvas.drawCircle(
        p,
        w * (0.005 + 0.003 * (i % 2)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * (1 - pose.dissolve)),
      );
    }

    // 巨大斗篷：下缘三段波浪，比其他角色的裙摆宽一倍。
    final cape = Path()
      ..moveTo(-w * 0.13, h * 0.24)
      ..quadraticBezierTo(-w * 0.34, h * 0.36, -w * 0.42, h * 0.60)
      ..quadraticBezierTo(-w * 0.46, h * 0.78, -w * 0.40, h * 0.94)
      // 下缘波浪
      ..quadraticBezierTo(-w * 0.28, h * 0.885, -w * 0.17, h * 0.93)
      ..quadraticBezierTo(-w * 0.06, h * 0.88, 0, h * 0.945)
      ..quadraticBezierTo(w * 0.06, h * 0.88, w * 0.17, h * 0.93)
      ..quadraticBezierTo(w * 0.28, h * 0.885, w * 0.40, h * 0.94)
      ..quadraticBezierTo(w * 0.46, h * 0.78, w * 0.42, h * 0.60)
      ..quadraticBezierTo(w * 0.34, h * 0.36, w * 0.13, h * 0.24)
      ..quadraticBezierTo(0, h * 0.20, -w * 0.13, h * 0.24)
      ..close();
    _fill(
      canvas,
      cape,
      theme,
      pose,
      1.0,
      const Color(0xFF3A1A55),
      const Color(0xFF0A0414),
    );

    // 斗篷内侧：比外层更深的内衬，拉开层次。
    final inner = Path()
      ..moveTo(-w * 0.10, h * 0.27)
      ..quadraticBezierTo(-w * 0.22, h * 0.45, -w * 0.20, h * 0.78)
      ..quadraticBezierTo(0, h * 0.86, w * 0.20, h * 0.78)
      ..quadraticBezierTo(w * 0.22, h * 0.45, w * 0.10, h * 0.27)
      ..close();
    canvas.drawPath(
      inner,
      Paint()..color = const Color(0xFF080310).withValues(alpha: 0.65),
    );

    // 头部：低伏的暗影，几乎融进斗篷，只露出轮廓。
    final head = Path()
      ..moveTo(-w * 0.105, h * 0.245)
      ..quadraticBezierTo(-w * 0.115, h * 0.13, 0, h * 0.105)
      ..quadraticBezierTo(w * 0.115, h * 0.13, w * 0.105, h * 0.245)
      ..close();
    _fill(
      canvas,
      head,
      theme,
      pose,
      0.95,
      const Color(0xFF2A1040),
      const Color(0xFF0A0414),
    );

    // 月牙双角：从头顶两侧向内弯——终焉的标志。
    for (final side in [-1.0, 1.0]) {
      final sway = math.sin(t * 1.1) * w * 0.004;
      _fill(
        canvas,
        Path()
          ..moveTo(w * 0.075 * side, h * 0.135)
          ..quadraticBezierTo(
            w * 0.22 * side,
            h * 0.10,
            w * 0.16 * side + sway,
            h * 0.028,
          )
          ..quadraticBezierTo(
            w * 0.14 * side + sway,
            h * 0.055,
            w * 0.09 * side,
            h * 0.088,
          )
          ..quadraticBezierTo(
            w * 0.055 * side,
            h * 0.115,
            w * 0.075 * side,
            h * 0.135,
          )
          ..close(),
        theme,
        pose,
        0.9,
        const Color(0xFF44206A),
        const Color(0xFF120720),
      );
    }

    // 三只眼：横排的细长发光缝，狂暴时更亮。
    final blink = math.sin(t * 0.85) > 0.965 ? 0.12 : 1.0;
    final eyeGlow = (0.75 + pose.phase * 0.12 + (pose.enraged ? 0.4 : 0.0))
        .clamp(0.0, 1.0);
    for (final dx in [-0.055, 0.0, 0.055]) {
      final p = Offset(w * dx, h * 0.175 + w * (dx.abs()) * 0.06);
      final ew = dx == 0 ? w * 0.052 : w * 0.038;
      canvas.drawRect(
        Rect.fromCenter(center: p, width: ew, height: h * 0.014 * blink),
        Paint()
          ..color = theme.withValues(alpha: eyeGlow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.010),
      );
      canvas.drawRect(
        Rect.fromCenter(center: p, width: ew * 0.55, height: h * 0.008 * blink),
        Paint()..color = Colors.white.withValues(alpha: 0.96),
      );
    }

    // 胸口吞噬漩涡：三层旋转的弧 + 中央暗核。
    final vortex = Offset(0, h * 0.44);
    final vr = w * 0.13;
    canvas.drawCircle(
      vortex,
      vr * 1.5,
      Paint()
        ..shader = ui.Gradient.radial(vortex, vr * 1.5, [
          theme.withValues(alpha: 0.30),
          Colors.transparent,
        ]),
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(
        theme,
        Colors.white,
        0.3,
      )!.withValues(alpha: 0.75 * (1 - pose.dissolve));
    for (var i = 0; i < 3; i++) {
      final r = vr * (0.45 + i * 0.30);
      final a0 = t * (0.9 - i * 0.25) + i * 2.1;
      canvas.drawArc(
        Rect.fromCenter(center: vortex, width: r * 2, height: r * 2),
        a0,
        math.pi * 1.25,
        false,
        arc..strokeWidth = w * (0.011 - i * 0.002),
      );
    }
    canvas.drawCircle(
      vortex,
      vr * 0.22,
      Paint()..color = const Color(0xFF03010A).withValues(alpha: 0.95),
    );
    _paintCracks(canvas, w, h, pose);
  }

  // ------------------------------------------------------------ 氛围

  static void _paintAura(
    Canvas canvas,
    Size size,
    Color theme,
    EnemyPose pose,
  ) {
    final intensity = 0.20 + pose.phase * 0.075 + (pose.enraged ? 0.16 : 0.0);
    final alpha = intensity * (1 - pose.dissolve);
    final center = Offset(size.width * 0.5, size.height * 0.55);
    final radius = size.width * (0.60 + pose.phase * 0.04);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            theme.withValues(alpha: alpha),
            theme.withValues(alpha: alpha * 0.28),
            Colors.transparent,
          ],
          const [0.0, 0.42, 1.0],
        ),
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
      canvas.drawPath(
        shard,
        Paint()..color = theme.withValues(alpha: 0.8 * (1 - pose.dissolve)),
      );
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
        ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
          top,
          bottom,
        ]),
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
            Color.lerp(
              theme,
              Colors.white,
              0.45,
            )!.withValues(alpha: 0.95 * layer),
            theme.withValues(alpha: 0.55 * layer),
            theme.withValues(alpha: 0.06 * layer),
          ],
          const [0.0, 0.45, 1.0],
        ),
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
        Paint()
          ..color = Colors.white.withValues(alpha: pose.hitFlash * 0.6 * layer),
      );
    }

    if (pose.dissolve > 0.01) {
      final rng = math.Random(bounds.hashCode);
      for (var i = 0; i < 22; i++) {
        final p = Offset(
          bounds.left + rng.nextDouble() * bounds.width,
          bounds.bottom -
              rng.nextDouble() * bounds.height * pose.dissolve * 1.5,
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
      ..quadraticBezierTo(
        -w * 0.150,
        h * (0.862 + hemWave / h),
        -w * 0.075,
        h * 0.895,
      )
      ..quadraticBezierTo(
        -w * 0.010 + sway,
        h * (0.925 + hemWave / h),
        w * 0.078,
        h * 0.893,
      )
      ..quadraticBezierTo(
        w * 0.155,
        h * (0.860 - hemWave / h),
        w * 0.268,
        h * _hemY,
      )
      ..quadraticBezierTo(w * 0.286, h * 0.855, w * 0.230, h * 0.79)
      ..quadraticBezierTo(w * 0.090, h * _hipY, w * 0.062, h * _waistY)
      ..quadraticBezierTo(w * 0.100, h * _bustY, w * 0.108, h * _shoulderY)
      // 肩线
      ..quadraticBezierTo(w * 0.055, h * 0.297, 0, h * 0.301)
      ..quadraticBezierTo(-w * 0.055, h * 0.297, -w * 0.108, h * _shoulderY)
      ..close();

    // 头部
    path.addPath(
      Path()..addOval(
        Rect.fromCenter(
          center: Offset(sway * 0.5, h * (_headTop + _eyeY) / 2 + h * 0.012),
          width: w * 0.132,
          height: h * 0.155,
        ),
      ),
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
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(w * 0.124 * side + sway, h * 0.652),
            width: w * 0.032,
            height: h * 0.028,
          ),
        ),
        Offset.zero,
      );
    }
    return path;
  }

  /// 身后的长发主体。
  static Path _buildHair(
    double w,
    double h,
    double t,
    EnemyPose pose, {
    required bool back,
  }) {
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
      Path()..addOval(
        Rect.fromCenter(
          center: Offset(0, h * 0.152),
          width: w * 0.152,
          height: h * 0.088,
        ),
      ),
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
  static void _paintDressShading(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
    final hem = h * _hemY;
    // 胸口到腰的高光
    final highlight = Path()
      ..moveTo(-w * 0.086, h * (_bustY - 0.03))
      ..quadraticBezierTo(
        -w * 0.040,
        h * _waistY,
        -w * 0.072,
        h * (_hipY + 0.03),
      )
      ..quadraticBezierTo(0, h * 0.655, w * 0.072, h * (_hipY + 0.03))
      ..quadraticBezierTo(
        w * 0.040,
        h * _waistY,
        w * 0.086,
        h * (_bustY - 0.03),
      )
      ..quadraticBezierTo(
        0,
        h * (_bustY - 0.065),
        -w * 0.086,
        h * (_bustY - 0.03),
      )
      ..close();
    canvas.drawPath(
      highlight,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * _bustY),
          Offset(0, h * _hipY),
          [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.0),
          ],
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
          [theme.withValues(alpha: 0.55), theme.withValues(alpha: 0.05)],
        ),
    );
  }

  /// 胸口的契约宝石，随相位变亮。
  static void _paintChestGem(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
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
    canvas.drawPath(
      gem,
      Paint()..color = Color.lerp(theme, Colors.white, 0.55)!,
    );
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
        ..shader = ui.Gradient.linear(
          faceRect.topCenter,
          faceRect.bottomCenter,
          const [Color(0xFFFBEFF4), Color(0xFFE0C2D4), Color(0xFFA9859F)],
          const [0.0, 0.45, 1.0],
        ),
    );

    final blink = math.sin(t * 0.85) > 0.965 ? 0.12 : 1.0;
    final glow = (0.65 + pose.phase * 0.12 + (pose.enraged ? 0.4 : 0.0)).clamp(
      0.0,
      1.0,
    );
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
        p += Offset(
          (rng.nextDouble() - 0.5) * w * 0.06,
          rng.nextDouble() * h * 0.045,
        );
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}
