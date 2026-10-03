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

/// 用矢量图形直接画出十三位美少女。
///
/// 统一思路沿用旧的「深色剪影 + 主题色轮廓光」：一份共享的美少女身形
/// （发、脸、躯干、双臂、裙摆），每位角色通过配色、发型与一套专属的
/// 特色图层（翅膀、盾、刀、魔女帽、月环、鱼鳍、冰晶、披风、镜片、
/// 齿轮、龙角龙尾、星环）区分——剪影的骨相是同一个人，气质全靠
/// 「发色 + 头饰 + 标志物」表达，不依赖任何位图资源。
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

/// 发型：身后的发束形状。前发（刘海）全员共用。
enum _HairStyle {
  /// 长直/长卷：垂到裙摆的长发。
  long,

  /// 短发：发梢收在肩胛附近。
  short,

  /// 双马尾：后发收短，两条侧马尾另画。
  twin,

  /// 侧马尾：后发收短，一条高马尾垂在单侧。
  sideTail,
}

/// 一位角色的配色与发型。剪影是深色的，但"深"里也要有各自的倾向——
/// 发色是少女辨识度最高的部分，全员显式指定。
class _MaidenColors {
  final Color hairTop;
  final Color hairBottom;
  final Color dressTop;
  final Color dressBottom;
  final _HairStyle hair;

  const _MaidenColors(
    this.hairTop,
    this.hairBottom,
    this.dressTop,
    this.dressBottom, [
    this.hair = _HairStyle.long,
  ]);
}

class EnemyArt {
  const EnemyArt._();

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
    EnemyArchetype archetype = EnemyArchetype.voidWatcher,
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
    // 二十来层填充（本体、发丝、面部、配饰、裂纹……），漏掉任何一层都会
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
      _paintMaiden(canvas, w, h, t, theme, pose, archetype);
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
    _paintMaiden(canvas, w, h, _quantize(t), theme, pose, archetype);
    _cachedSilhouette = recorder.endRecording();
    _cachedKey = key;
    return _cachedSilhouette!;
  }

  // ============================================================ 美少女框架

  static _MaidenColors _colorsFor(EnemyArchetype archetype) {
    switch (archetype) {
      case EnemyArchetype.fairy:
        return const _MaidenColors(
          Color(0xFF2E8C7A),
          Color(0xFF0E3A32),
          Color(0xFF3E6E4C),
          Color(0xFF12241A),
          _HairStyle.short,
        );
      case EnemyArchetype.saint:
        return const _MaidenColors(
          Color(0xFFE8C878),
          Color(0xFF8A6A2E),
          Color(0xFFEFE4C8),
          Color(0xFF9A8A5C),
        );
      case EnemyArchetype.kunoichi:
        return const _MaidenColors(
          Color(0xFF7A58C0),
          Color(0xFF241640),
          Color(0xFF2E2840),
          Color(0xFF0E0A1A),
          _HairStyle.sideTail,
        );
      case EnemyArchetype.witch:
        return const _MaidenColors(
          Color(0xFFB03A52),
          Color(0xFF3A0E1C),
          Color(0xFF401826),
          Color(0xFF140A10),
          _HairStyle.short,
        );
      case EnemyArchetype.succubus:
        return const _MaidenColors(
          Color(0xFFE8E4F0),
          Color(0xFF8A80A0),
          Color(0xFF5A1836),
          Color(0xFF180814),
        );
      case EnemyArchetype.moonPriestess:
        return const _MaidenColors(
          Color(0xFF3A3450),
          Color(0xFF12102A),
          Color(0xFFE8E6F0),
          Color(0xFF9A96B8),
        );
      case EnemyArchetype.mermaid:
        return const _MaidenColors(
          Color(0xFF3AA8C8),
          Color(0xFF0C3A4C),
          Color(0xFF2E88A8),
          Color(0xFF0A2C3C),
        );
      case EnemyArchetype.frostMaiden:
        return const _MaidenColors(
          Color(0xFFD8ECF8),
          Color(0xFF6A9AC0),
          Color(0xFFE8F2F8),
          Color(0xFF96BFD8),
        );
      case EnemyArchetype.vampire:
        return const _MaidenColors(
          Color(0xFF28182A),
          Color(0xFF0C060E),
          Color(0xFF4A1A2A),
          Color(0xFF140810),
        );
      case EnemyArchetype.puppeteer:
        return const _MaidenColors(
          Color(0xFFC8A2E0),
          Color(0xFF5A4080),
          Color(0xFF4A3A60),
          Color(0xFF161024),
          _HairStyle.twin,
        );
      case EnemyArchetype.machina:
        return const _MaidenColors(
          Color(0xFFD8E8E4),
          Color(0xFF6A9A90),
          Color(0xFF3A6A60),
          Color(0xFF0C2020),
          _HairStyle.short,
        );
      case EnemyArchetype.dragonPrincess:
        return const _MaidenColors(
          Color(0xFFE87A4A),
          Color(0xFF7A2A10),
          Color(0xFF8A4A20),
          Color(0xFF26100A),
          _HairStyle.sideTail,
        );
      case EnemyArchetype.voidWatcher:
        return const _MaidenColors(
          Color(0xFFE8E0F4),
          Color(0xFF7A6AA0),
          Color(0xFF3A1A55),
          Color(0xFF08040F),
        );
    }
  }

  /// 美少女的分层绘制：身后特色 → 后发 → 躯干裙装 → 手臂 → 胸饰 →
  /// 前发 → 面部 → 裂纹 → 前景特色。
  static void _paintMaiden(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    final c = _colorsFor(archetype);

    _paintBackFeature(canvas, w, h, t, theme, pose, archetype);

    _fill(
      canvas,
      _buildHair(w, h, t, pose, style: c.hair),
      theme,
      pose,
      0.62,
      c.hairTop,
      c.hairBottom,
    );
    // 双马尾单独成层：马尾比底发更自由，摆幅也更大。
    if (c.hair == _HairStyle.twin) {
      _fill(
        canvas,
        _buildTwinTails(w, h, t, pose),
        theme,
        pose,
        0.66,
        c.hairTop,
        c.hairBottom,
      );
    }
    _fill(
      canvas,
      _buildBody(w, h, t),
      theme,
      pose,
      1.0,
      c.dressTop,
      c.dressBottom,
    );
    _paintDressShading(canvas, w, h, theme, pose);
    _fill(
      canvas,
      _buildArms(w, h, t),
      theme,
      pose,
      0.96,
      Color.lerp(c.dressTop, Colors.black, 0.25)!,
      Color.lerp(c.dressBottom, Colors.black, 0.3)!,
    );
    _paintChestGem(canvas, w, h, theme, pose);
    _fill(
      canvas,
      _buildFrontHair(w, h, t, pose, style: c.hair),
      theme,
      pose,
      0.88,
      Color.lerp(c.hairTop, Colors.white, 0.06)!,
      Color.lerp(c.hairBottom, Colors.black, 0.2)!,
    );

    _paintFace(canvas, w, h, theme, pose, t);
    _paintCracks(canvas, w, h, pose);
    _paintFrontFeature(canvas, w, h, t, theme, pose, archetype);
  }

  // ------------------------------------------------------------ 身形构建

  /// 躯干 + 头部 + 脖颈。
  static Path _buildBody(double w, double h, double t) {
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
  static Path _buildArms(double w, double h, double t) {
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

  /// 身后的长发。[style] 决定发束的形状与长度。
  static Path _buildHair(
    double w,
    double h,
    double t,
    EnemyPose pose, {
    _HairStyle style = _HairStyle.long,
  }) {
    final flutter = 0.010 + pose.phase * 0.004;
    // 短发系（含马尾底发）只画到肩胛附近的长度的束。
    final bottom = switch (style) {
      _HairStyle.long => 0.80,
      _HairStyle.twin || _HairStyle.sideTail => 0.42,
      _ => 0.52,
    };
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      final wave = math.sin(t * 1.5 + (side > 0 ? 0.9 : 0)) * h * flutter;
      final wave2 = math.sin(t * 1.05 + (side > 0 ? 2.1 : 1.3)) * h * flutter;
      final wave3 = math.sin(t * 1.8 + side) * h * flutter * 0.7;
      path.addPath(
        Path()
          ..moveTo(w * 0.046 * side, h * 0.115)
          ..quadraticBezierTo(
            w * 0.140 * side,
            h * 0.20 + wave,
            w * 0.150 * side,
            h * (0.20 + bottom * 0.30) + wave2,
          )
          ..quadraticBezierTo(
            w * 0.140 * side,
            h * (bottom - 0.18) + wave,
            w * 0.104 * side,
            h * bottom + wave2 * 1.6,
          )
          ..quadraticBezierTo(
            w * 0.126 * side,
            h * (bottom - 0.22) + wave3,
            w * 0.112 * side,
            h * 0.38 + wave3,
          )
          ..quadraticBezierTo(
            w * 0.098 * side,
            h * 0.21 + wave3,
            w * 0.016 * side,
            h * 0.145,
          )
          ..close(),
        Offset.zero,
      );
    }
    if (style == _HairStyle.sideTail) {
      // 单侧高马尾：从头顶右侧甩出的一条长束。
      final sway = math.sin(t * 1.6) * h * flutter * 1.4;
      path.addPath(
        Path()
          ..moveTo(w * 0.052, h * 0.10)
          ..quadraticBezierTo(w * 0.16, h * 0.16 + sway, w * 0.185, h * 0.42)
          ..quadraticBezierTo(
            w * 0.19,
            h * 0.66,
            w * 0.135,
            h * 0.82 + sway * 1.6,
          )
          ..quadraticBezierTo(
            w * 0.10,
            h * 0.62,
            w * 0.10,
            h * 0.36 + sway,
          )
          ..quadraticBezierTo(w * 0.095, h * 0.18, w * 0.052, h * 0.10)
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  /// 双马尾（铃兰）：两条带弧度的侧马尾，随呼吸轻摆。
  static Path _buildTwinTails(double w, double h, double t, EnemyPose pose) {
    final flutter = 0.012 + pose.phase * 0.005;
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      final wave = math.sin(t * 1.7 + (side > 0 ? 1.1 : 0)) * h * flutter;
      path.addPath(
        Path()
          ..moveTo(w * 0.096 * side, h * 0.13)
          ..quadraticBezierTo(
            w * 0.205 * side,
            h * 0.22 + wave,
            w * 0.185 * side,
            h * 0.50,
          )
          ..quadraticBezierTo(
            w * 0.170 * side,
            h * 0.76,
            w * 0.125 * side,
            h * 0.86 + wave * 1.6,
          )
          ..quadraticBezierTo(
            w * 0.115 * side,
            h * 0.62,
            w * 0.128 * side,
            h * 0.40,
          )
          ..quadraticBezierTo(
            w * 0.135 * side,
            h * 0.20,
            w * 0.096 * side,
            h * 0.13,
          )
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  /// 贴着脸颊的刘海，让头部有层次。
  static Path _buildFrontHair(
    double w,
    double h,
    double t,
    EnemyPose pose, {
    _HairStyle style = _HairStyle.long,
  }) {
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
            h * (style == _HairStyle.short ? 0.42 : 0.50),
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

  /// 小恶魔角（魅魔）。
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
            h * 0.062,
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

  /// 龙角（绫羽）：更长的后弯角，从头顶两侧向斜后上方伸出。
  static Path _buildDragonHorns(double w, double h, double t) {
    final sway = math.sin(t * 1.2) * w * 0.006;
    final path = Path();
    for (final side in [-1.0, 1.0]) {
      path.addPath(
        Path()
          ..moveTo(w * 0.048 * side, h * 0.135)
          ..quadraticBezierTo(
            w * 0.145 * side,
            h * 0.085,
            w * 0.185 * side + sway,
            h * 0.012,
          )
          ..quadraticBezierTo(
            w * 0.150 * side + sway,
            h * 0.058,
            w * 0.082 * side,
            h * 0.108,
          )
          ..close(),
        Offset.zero,
      );
    }
    return path;
  }

  /// 龙尾（绫羽）：从裙摆后探出的带鳞长尾，尾尖随呼吸摆动。
  static Path _buildDragonTail(double w, double h, double t) {
    final sway = math.sin(t * 1.1) * w * 0.015;
    return Path()
      ..moveTo(-w * 0.10, h * 0.72)
      ..quadraticBezierTo(-w * 0.30, h * 0.80, -w * 0.34 + sway, h * 0.62)
      ..quadraticBezierTo(-w * 0.36 + sway, h * 0.50, -w * 0.30 + sway, h * 0.44)
      ..quadraticBezierTo(-w * 0.28 + sway, h * 0.56, -w * 0.24, h * 0.66)
      ..quadraticBezierTo(-w * 0.20, h * 0.76, -w * 0.08, h * 0.76)
      ..close();
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

  // ============================================================ 特色图层

  /// 身后的特色图层：翅膀、月环、披风、齿轮、龙尾……
  static void _paintBackFeature(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    switch (archetype) {
      case EnemyArchetype.fairy:
        _paintFairyWings(canvas, w, h, t, theme, pose);
      case EnemyArchetype.kunoichi:
        _paintAfterimages(canvas, w, h, t, theme, pose);
      case EnemyArchetype.witch:
        _paintDolls(canvas, w, h, t, theme, pose);
      case EnemyArchetype.succubus:
        _paintTendrils(canvas, w, h, t, pose);
        _paintBatWings(canvas, w, h, t, theme, pose, big: false);
      case EnemyArchetype.moonPriestess:
        _paintMoonDisc(canvas, w, h, t, theme, pose);
      case EnemyArchetype.mermaid:
        _paintBubbles(canvas, w, h, t, theme, pose);
      case EnemyArchetype.frostMaiden:
        _paintIceSpikes(canvas, w, h, t, theme, pose);
        _paintSnowfall(canvas, w, h, t, theme, pose);
      case EnemyArchetype.vampire:
        _paintBatWings(canvas, w, h, t, theme, pose, big: true);
      case EnemyArchetype.puppeteer:
        _paintMirrors(canvas, w, h, t, theme, pose);
      case EnemyArchetype.machina:
        _paintGearHalo(canvas, w, h, t, theme, pose);
      case EnemyArchetype.dragonPrincess:
        _fill(
          canvas,
          _buildDragonTail(w, h, t),
          theme,
          pose,
          0.7,
          const Color(0xFF7A3A18),
          const Color(0xFF260C06),
        );
        _paintFireFeathers(canvas, w, h, t, theme, pose);
      case EnemyArchetype.voidWatcher:
        _paintStarRing(canvas, w, h, t, theme, pose);
      case EnemyArchetype.saint:
        break; // 圣女的标志（塔盾）在前景层
    }
  }

  /// 前景的特色图层：武器、帽子、灯、丝线……
  static void _paintFrontFeature(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
    EnemyArchetype archetype,
  ) {
    switch (archetype) {
      case EnemyArchetype.fairy:
        _paintEars(canvas, w, h, theme, pose);
        _paintPetals(canvas, w, h, t, theme, pose);
      case EnemyArchetype.saint:
        _paintTowerShield(canvas, w, h, t, theme, pose);
        _paintHalo(canvas, w, h, t, theme, pose);
      case EnemyArchetype.kunoichi:
        _paintTwinBlades(canvas, w, h, t, theme, pose);
      case EnemyArchetype.witch:
        _paintWitchHat(canvas, w, h, t, theme, pose);
      case EnemyArchetype.succubus:
        _fill(canvas, _buildHorns(w, h, t), theme, pose, 0.9,
            const Color(0xFF4A1830), const Color(0xFF180814));
      case EnemyArchetype.moonPriestess:
        _paintShrineRibbons(canvas, w, h, t, theme, pose);
        _paintLanterns(canvas, w, h, t, theme, pose);
      case EnemyArchetype.mermaid:
        _paintEars(canvas, w, h, theme, pose);
        _paintShellPin(canvas, w, h, theme, pose);
      case EnemyArchetype.frostMaiden:
        _paintIceCrown(canvas, w, h, t, theme, pose);
      case EnemyArchetype.vampire:
        _paintGoblet(canvas, w, h, t, theme, pose);
      case EnemyArchetype.puppeteer:
        _paintScissors(canvas, w, h, t, theme, pose);
        _paintThreads(canvas, w, h, t, theme, pose);
      case EnemyArchetype.machina:
        _paintVisor(canvas, w, h, theme, pose);
      case EnemyArchetype.dragonPrincess:
        _fill(canvas, _buildDragonHorns(w, h, t), theme, pose, 0.9,
            const Color(0xFF9A5A28), const Color(0xFF33140A));
        _paintScaleShoulders(canvas, w, h, theme, pose);
      case EnemyArchetype.voidWatcher:
        _paintVortex(canvas, w, h, t, theme, pose);
    }
  }

  // ---------------- 身后系 ----------------

  /// 妖精的半透明薄翅：两对椭圆瓣，随时间轻轻开合。
  static void _paintFairyWings(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final open = 1 + math.sin(t * 2.2) * 0.08;
    for (final side in [-1.0, 1.0]) {
      for (final layer in [0, 1]) {
        final len = layer == 0 ? 0.30 : 0.22;
        final lift = layer == 0 ? 0.30 : 0.06;
        final path = Path()
          ..moveTo(w * 0.05 * side, h * 0.34)
          ..quadraticBezierTo(
            w * (0.14 + len * 0.9) * side * open,
            h * (0.34 - lift) * (layer == 0 ? 1.0 : 0.7),
            w * (0.10 + len) * side * open,
            h * (0.36 - lift * 1.5),
          )
          ..quadraticBezierTo(
            w * (0.12 + len * 0.6) * side * open,
            h * 0.42,
            w * 0.05 * side,
            h * 0.40,
          )
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(w * 0.05 * side, h * 0.30),
              Offset(w * (0.10 + len) * side * open, h * 0.42),
              [
                theme.withValues(alpha: 0.34 * (1 - pose.dissolve)),
                Colors.white.withValues(alpha: 0.10 * (1 - pose.dissolve)),
              ],
            ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = theme.withValues(alpha: 0.5 * (1 - pose.dissolve)),
        );
      }
    }
  }

  /// 忍者的残影：身侧两道斜向的半透明衣袖弧，静止时也在"分身"。
  static void _paintAfterimages(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final drift = math.sin(t * 1.9 + i * 2.1) * w * 0.012;
      final path = Path()
        ..moveTo(w * 0.10 * side, h * 0.32)
        ..quadraticBezierTo(
          w * (0.20 + i * 0.04) * side + drift,
          h * 0.48,
          w * (0.16 + i * 0.05) * side + drift,
          h * 0.68,
        )
        ..quadraticBezierTo(
          w * (0.12 + i * 0.04) * side + drift,
          h * 0.62,
          w * 0.06 * side,
          h * 0.44,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(w * 0.10 * side, h * 0.32),
            Offset(w * 0.16 * side + drift, h * 0.68),
            [
              theme.withValues(alpha: 0.20 * (1 - pose.dissolve)),
              Colors.transparent,
            ],
          ),
      );
    }
  }

  /// 魔女悬浮的布偶与针：她替人缝住疼痛的见证。
  static void _paintDolls(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final bob = math.sin(t * 1.4 + i * 2.4) * h * 0.012;
      final cx = w * 0.30 * side;
      final cy = h * (0.52 + i * 0.12) + bob;
      final s = w * 0.035;
      final doll = Path()
        ..moveTo(cx, cy - s * 1.1)
        ..quadraticBezierTo(cx + s, cy - s * 0.6, cx + s * 0.7, cy + s * 0.8)
        ..lineTo(cx, cy + s * 1.3)
        ..lineTo(cx - s * 0.7, cy + s * 0.8)
        ..quadraticBezierTo(cx - s, cy - s * 0.6, cx, cy - s * 1.1)
        ..close();
      canvas.drawPath(
        doll,
        Paint()
          ..color = const Color(0xFF2A0E18).withValues(alpha: 0.92)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
      canvas.drawCircle(
        Offset(cx, cy - s * 0.5),
        s * 0.30,
        Paint()..color = theme.withValues(alpha: 0.5 * (1 - pose.dissolve)),
      );
      // 一根缝针斜插
      canvas.drawLine(
        Offset(cx - s * 1.1, cy + s * 0.4),
        Offset(cx + s * 0.9, cy - s * 0.9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.4 * (1 - pose.dissolve)),
      );
    }
  }

  /// 魅魔肩后的深渊触须：细长的锥形曲线，随呼吸缓慢摆动。
  static void _paintTendrils(
    Canvas canvas,
    double w,
    double h,
    double t,
    EnemyPose pose,
  ) {
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
    _fill(
      canvas,
      path,
      Colors.white,
      pose,
      0.55,
      const Color(0xFF2A0F1E),
      const Color(0xFF0D0410),
    );
  }

  /// 蝙蝠翅：魅魔的小翅与吸血鬼的披风大翅共用骨架。
  static void _paintBatWings(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose, {
    required bool big,
  }) {
    final span = big ? 0.42 : 0.30;
    final lift = big ? 0.20 : 0.14;
    for (final side in [-1.0, 1.0]) {
      final flap = math.sin(t * 1.7 + (side > 0 ? 0.8 : 0)) * 0.05;
      final top = Path()
        ..moveTo(w * 0.06 * side, h * 0.34)
        ..quadraticBezierTo(
          w * (0.20 + span * 0.5) * side,
          h * (0.30 - lift - flap),
          w * span * 1.6 * side,
          h * (0.38 - lift * 1.4 - flap),
        )
        // 膜的下缘两个内凹扇边
        ..quadraticBezierTo(
          w * span * 1.15 * side,
          h * 0.42,
          w * span * 1.05 * side,
          h * (0.40 - lift * 0.4),
        )
        ..quadraticBezierTo(
          w * span * 0.75 * side,
          h * 0.46,
          w * span * 0.62 * side,
          h * (0.44 - lift * 0.2),
        )
        ..quadraticBezierTo(
          w * span * 0.38 * side,
          h * 0.48,
          w * 0.06 * side,
          h * 0.44,
        )
        ..close();
      canvas.drawPath(
        top,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(w * 0.06 * side, h * 0.30),
            Offset(w * span * 1.5 * side, h * 0.44),
            [
              Color.lerp(theme, Colors.white, 0.25)!
                  .withValues(alpha: 0.30 * (1 - pose.dissolve)),
              const Color(0xFF180A20).withValues(alpha: 0.92),
            ],
          ),
      );
      canvas.drawPath(
        top,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = theme.withValues(alpha: 0.55 * (1 - pose.dissolve)),
      );
    }
  }

  /// 月祭司的圆月：身后一轮缓缓呼吸的满月。
  static void _paintMoonDisc(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(0, h * 0.26);
    final r = w * (0.30 + math.sin(t * 0.8) * 0.008);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.15, [
          theme.withValues(alpha: 0.30 * (1 - pose.dissolve)),
          theme.withValues(alpha: 0.08 * (1 - pose.dissolve)),
          Colors.transparent,
        ], const [0.0, 0.5, 1.0]),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..color = Color.lerp(theme, Colors.white, 0.4)!
            .withValues(alpha: 0.20 * (1 - pose.dissolve)),
    );
    // 月面暗斑
    canvas.drawCircle(
      c.translate(-r * 0.2, -r * 0.12),
      r * 0.12,
      Paint()..color = theme.withValues(alpha: 0.14 * (1 - pose.dissolve)),
    );
    canvas.drawCircle(
      c.translate(r * 0.16, r * 0.2),
      r * 0.08,
      Paint()..color = theme.withValues(alpha: 0.12 * (1 - pose.dissolve)),
    );
  }

  /// 人鱼的水泡：从裙摆两侧升起的一串气泡。
  static void _paintBubbles(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 7; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final phase = (t * 0.35 + i * 0.37) % 1.0;
      final y = h * (0.86 - phase * 0.55);
      final x =
          w * (0.22 + 0.10 * (i % 3)) * side + math.sin(t * 1.3 + i) * w * 0.02;
      final r = w * (0.008 + 0.006 * (i % 2)) * (1 - phase * 0.3);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = theme.withValues(alpha: 0.5 * (1 - pose.dissolve)),
      );
      canvas.drawCircle(
        Offset(x - r * 0.3, y - r * 0.3),
        r * 0.24,
        Paint()..color = Colors.white.withValues(alpha: 0.35 * (1 - pose.dissolve)),
      );
    }
  }

  /// 冰姬脚下的冰棱：一簇向上的尖锥，随相位更锋利。
  static void _paintIceSpikes(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final glint = math.sin(t * 1.8) * 0.15;
    for (var i = 0; i < 5; i++) {
      final x = (i - 2) * w * 0.115;
      final height = h * (0.10 + 0.05 * (i.isEven ? 1 : 0) + pose.phase * 0.012);
      final path = Path()
        ..moveTo(x - w * 0.035, h * 0.96)
        ..lineTo(x + w * 0.012, h * (0.96 - height / h))
        ..lineTo(x + w * 0.035, h * 0.96)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, h * 0.96 - height),
            Offset(x, h * 0.96),
            [
              Color.lerp(theme, Colors.white, 0.5)!
                  .withValues(alpha: (0.55 + glint) * (1 - pose.dissolve)),
              const Color(0xFF14303E).withValues(alpha: 0.85),
            ],
          ),
      );
    }
  }

  /// 冰姬的落雪：几片慢速飘落的雪晶。
  static void _paintSnowfall(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 6; i++) {
      final phase = (t * 0.14 + i * 0.31) % 1.0;
      final y = h * (phase * 1.1 - 0.05);
      final x = w * (0.14 + 0.14 * (i % 5)) + math.sin(t * 0.9 + i) * w * 0.02;
      canvas.drawCircle(
        Offset(x, y),
        1.1 + (i % 2) * 0.8,
        Paint()..color = Colors.white.withValues(alpha: 0.5 * (1 - pose.dissolve)),
      );
    }
  }

  /// 傀儡师环绕的镜片：旋转的菱形碎片。
  static void _paintMirrors(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 4; i++) {
      final a = t * 0.5 + i * math.pi / 2;
      final p = Offset(
        w * 0.40 * math.cos(a),
        h * 0.42 + h * 0.20 * math.sin(a * 1.2),
      );
      final s = w * 0.030;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + math.pi / 4);
      final shard = Path()
        ..moveTo(0, -s * 1.5)
        ..lineTo(s * 0.7, 0)
        ..lineTo(0, s * 1.5)
        ..lineTo(-s * 0.7, 0)
        ..close();
      canvas.drawPath(
        shard,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, -s * 1.5),
            Offset(0, s * 1.5),
            [
              Colors.white.withValues(alpha: 0.30 * (1 - pose.dissolve)),
              theme.withValues(alpha: 0.18 * (1 - pose.dissolve)),
            ],
          ),
      );
      canvas.drawPath(
        shard,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = theme.withValues(alpha: 0.6 * (1 - pose.dissolve)),
      );
      canvas.restore();
    }
  }

  /// 巫姬背后的齿轮光环：一圈慢转的齿 + 中央细环。
  static void _paintGearHalo(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(0, h * 0.30);
    final r = w * 0.30;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 0.35);
    final tooth = Paint()
      ..color = theme.withValues(alpha: 0.42 * (1 - pose.dissolve));
    for (var i = 0; i < 12; i++) {
      final a = math.pi * 2 / 12 * i;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(r * math.cos(a), r * math.sin(a)),
          width: w * 0.045,
          height: w * 0.016,
        ),
        tooth,
      );
    }
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.014
        ..color = theme.withValues(alpha: 0.35 * (1 - pose.dissolve)),
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      r * 0.70,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.16 * (1 - pose.dissolve)),
    );
  }

  /// 龙女环绕的火羽：几片上飘的赤色羽屑。
  static void _paintFireFeathers(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 6; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final phase = (t * 0.22 + i * 0.29) % 1.0;
      final y = h * (0.72 - phase * 0.5);
      final x = w * (0.26 + 0.06 * (i % 3)) * side + math.sin(t + i) * w * 0.02;
      final s = w * 0.016;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(t * 1.2 + i) * 0.6);
      final feather = Path()
        ..moveTo(0, -s * 2)
        ..quadraticBezierTo(s, 0, 0, s * 2)
        ..quadraticBezierTo(-s, 0, 0, -s * 2)
        ..close();
      canvas.drawPath(
        feather,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, -s * 2),
            Offset(0, s * 2),
            [
              Color.lerp(theme, Colors.yellow, 0.35)!
                  .withValues(alpha: 0.6 * (1 - phase) * (1 - pose.dissolve)),
              theme.withValues(alpha: 0.15 * (1 - phase)),
            ],
          ),
      );
      canvas.restore();
    }
  }

  /// 观测者的星环：身后一道倾斜的椭圆环 + 环上的碎星。
  static void _paintStarRing(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    // 碎星
    for (var i = 0; i < 7; i++) {
      final a = t * (0.22 + 0.03 * i) + i * 0.9;
      final rr = w * (0.42 + 0.04 * (i % 3));
      final p = Offset(
        rr * math.cos(a),
        h * 0.40 + h * 0.15 * math.sin(a * 1.4),
      );
      canvas.drawCircle(
        p,
        w * (0.005 + 0.003 * (i % 2)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * (1 - pose.dissolve)),
      );
    }
    // 倾斜星环
    canvas.save();
    canvas.translate(0, h * 0.40);
    canvas.rotate(-0.30);
    canvas.scale(1.0, 0.30);
    canvas.drawCircle(
      Offset.zero,
      w * 0.40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.010
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [
            theme.withValues(alpha: 0.7 * (1 - pose.dissolve)),
            Colors.transparent,
            theme.withValues(alpha: 0.4 * (1 - pose.dissolve)),
          ],
          const [0.0, 0.6, 1.0],
          TileMode.repeated,
        ),
    );
    canvas.restore();
  }

  // ---------------- 前景系 ----------------

  /// 妖精与真珠的尖耳（fairy / mermaid 共用）。
  static void _paintEars(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
    for (final side in [-1.0, 1.0]) {
      _fill(
        canvas,
        Path()
          ..moveTo(w * 0.058 * side, h * 0.165)
          ..lineTo(w * 0.115 * side, h * 0.125)
          ..lineTo(w * 0.062 * side, h * 0.215)
          ..close(),
        theme,
        pose,
        0.95,
        const Color(0xFFFBEFF4),
        const Color(0xFFB090A4),
      );
    }
  }

  /// 妖精环绕的花瓣。
  static void _paintPetals(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 5; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final phase = (t * 0.18 + i * 0.41) % 1.0;
      final y = h * (0.30 + phase * 0.55);
      final x = w * (0.30 + 0.05 * (i % 3)) * side + math.sin(t + i * 2) * w * 0.015;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (0.8 + i * 0.2) + i);
      final petal = Path()
        ..moveTo(0, -w * 0.014)
        ..quadraticBezierTo(w * 0.011, 0, 0, w * 0.014)
        ..quadraticBezierTo(-w * 0.011, 0, 0, -w * 0.014)
        ..close();
      canvas.drawPath(
        petal,
        Paint()..color = theme.withValues(alpha: 0.65 * (1 - phase) * (1 - pose.dissolve)),
      );
      canvas.restore();
    }
  }

  /// 圣女的塔盾：举在身前的圆形塔盾，带一圈旋转的光点环。
  static void _paintTowerShield(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final shieldC = Offset(w * 0.30, h * 0.52);
    final shieldR = w * 0.155;
    canvas.drawCircle(
      shieldC,
      shieldR,
      Paint()
        ..shader = ui.Gradient.radial(
          shieldC.translate(-shieldR * 0.3, -shieldR * 0.3),
          shieldR * 1.7,
          const [Color(0xFFEFE4C8), Color(0xFF9A8A5C), Color(0xFF3A3220)],
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
        ..color = Colors.white.withValues(alpha: 0.2),
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
    // 盾心的圣纹：竖直的十字槽。
    canvas.drawPath(
      Path()
        ..moveTo(shieldC.dx - shieldR * 0.1, shieldC.dy - shieldR * 0.42)
        ..lineTo(shieldC.dx + shieldR * 0.1, shieldC.dy - shieldR * 0.42)
        ..lineTo(shieldC.dx + shieldR * 0.1, shieldC.dy - shieldR * 0.1)
        ..lineTo(shieldC.dx + shieldR * 0.38, shieldC.dy - shieldR * 0.1)
        ..lineTo(shieldC.dx + shieldR * 0.38, shieldC.dy + shieldR * 0.1)
        ..lineTo(shieldC.dx + shieldR * 0.1, shieldC.dy + shieldR * 0.1)
        ..lineTo(shieldC.dx + shieldR * 0.1, shieldC.dy + shieldR * 0.42)
        ..lineTo(shieldC.dx - shieldR * 0.1, shieldC.dy + shieldR * 0.42)
        ..lineTo(shieldC.dx - shieldR * 0.1, shieldC.dy + shieldR * 0.1)
        ..lineTo(shieldC.dx - shieldR * 0.38, shieldC.dy + shieldR * 0.1)
        ..lineTo(shieldC.dx - shieldR * 0.38, shieldC.dy - shieldR * 0.1)
        ..lineTo(shieldC.dx - shieldR * 0.1, shieldC.dy - shieldR * 0.1)
        ..close(),
      Paint()..color = theme.withValues(alpha: 0.45 * (1 - pose.dissolve)),
    );
  }

  /// 圣女头顶的光环。
  static void _paintHalo(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(0, h * 0.075);
    final r = w * 0.105;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1.0, 0.30);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.014
        ..color = Color.lerp(theme, Colors.white, 0.4)!
            .withValues(alpha: 0.75 * (1 - pose.dissolve))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
    );
    canvas.restore();
    final pulse = 0.5 + 0.2 * math.sin(t * 2.0);
    canvas.drawCircle(
      c,
      r * 1.15,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.4, [
          Colors.white.withValues(alpha: 0.10 * pulse * (1 - pose.dissolve)),
          Colors.transparent,
        ]),
    );
  }

  /// 忍者的双刀：两道从肩侧斜向下方的刃光。
  static void _paintTwinBlades(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
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
            const Color(0xFFD8D0E8).withValues(alpha: 0.9),
            Color.lerp(theme, Colors.white, 0.5)!.withValues(alpha: 0.55),
          ]),
      );
      canvas.drawLine(
        hilt.translate(-w * 0.02 * side, -h * 0.02),
        hilt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.014
          ..color = const Color(0xFF3A2C5C),
      );
    }
  }

  /// 魔女的宽檐帽：斜戴在头顶。
  static void _paintWitchHat(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final sway = math.sin(t * 1.2) * w * 0.008;
    // 宽檐
    final brim = Path()
      ..moveTo(-w * 0.24, h * 0.115 + sway)
      ..quadraticBezierTo(0, h * 0.155, w * 0.24, h * 0.115 + sway)
      ..quadraticBezierTo(w * 0.10, h * 0.085, 0, h * 0.098)
      ..quadraticBezierTo(-w * 0.10, h * 0.085, -w * 0.24, h * 0.115 + sway)
      ..close();
    // 帽身：向后弯的尖锥
    final cone = Path()
      ..moveTo(-w * 0.105, h * 0.105)
      ..quadraticBezierTo(-w * 0.10, h * 0.02, -w * 0.02, h * 0.0)
      ..quadraticBezierTo(w * 0.10, h * 0.045, w * 0.105, h * 0.105)
      ..close();
    _fill(canvas, cone, theme, pose, 0.98, const Color(0xFF4A1A2A),
        const Color(0xFF180810));
    canvas.drawPath(
      brim,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.08),
          Offset(0, h * 0.16),
          [
            const Color(0xFF5A2236),
            const Color(0xFF1A0A12),
          ],
        ),
    );
    // 帽带与扣
    canvas.drawLine(
      Offset(-w * 0.095, h * 0.098),
      Offset(w * 0.095, h * 0.098),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.016
        ..color = theme.withValues(alpha: 0.8 * (1 - pose.dissolve)),
    );
    canvas.drawCircle(
      Offset(w * 0.02, h * 0.098),
      w * 0.014,
      Paint()..color = theme.withValues(alpha: 0.9 * (1 - pose.dissolve)),
    );
  }

  /// 月祭司的纸垂与祭灯。
  static void _paintShrineRibbons(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (final side in [-1.0, 1.0]) {
      final flutter = math.sin(t * 2.0 + (side > 0 ? 1.4 : 0)) * w * 0.02;
      final x = w * 0.145 * side;
      final path = Path()
        ..moveTo(x, h * 0.30)
        ..quadraticBezierTo(
          x + flutter * 0.6,
          h * 0.44,
          x + flutter,
          h * 0.58,
        )
        ..lineTo(x + flutter * 0.8 + w * 0.022, h * 0.57)
        ..quadraticBezierTo(
          x + w * 0.018,
          h * 0.42,
          x + w * 0.020,
          h * 0.30,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75 * (1 - pose.dissolve)),
      );
    }
  }

  static void _paintLanterns(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final bob = math.sin(t * 1.3 + i * 2.0) * h * 0.012;
      final c = Offset(w * 0.33 * side, h * (0.42 + i * 0.06) + bob);
      final s = w * 0.026;
      canvas.drawCircle(
        c,
        s * 1.8,
        Paint()
          ..shader = ui.Gradient.radial(c, s * 1.8, [
            theme.withValues(alpha: 0.35 * (1 - pose.dissolve)),
            Colors.transparent,
          ]),
      );
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s * 1.2)
          ..lineTo(c.dx + s, c.dy)
          ..lineTo(c.dx, c.dy + s * 1.2)
          ..lineTo(c.dx - s, c.dy)
          ..close(),
        Paint()..color = Color.lerp(theme, Colors.white, 0.3)!,
      );
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s * 1.2)
          ..lineTo(c.dx + s, c.dy)
          ..lineTo(c.dx, c.dy + s * 1.2)
          ..lineTo(c.dx - s, c.dy)
          ..close(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.5 * (1 - pose.dissolve)),
      );
    }
  }

  /// 人鱼的贝壳发饰。
  static void _paintShellPin(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(-w * 0.052, h * 0.135);
    final s = w * 0.024;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + s)
        ..quadraticBezierTo(c.dx - s, c.dy, c.dx, c.dy - s)
        ..quadraticBezierTo(c.dx + s, c.dy, c.dx, c.dy + s)
        ..close(),
      Paint()..color = Color.lerp(theme, Colors.white, 0.35)!,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy + s),
      Offset(c.dx, c.dy - s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.6 * (1 - pose.dissolve)),
    );
  }

  /// 冰姬头上的雪晶冠。
  static void _paintIceCrown(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final glint = 0.55 + 0.25 * math.sin(t * 2.2);
    for (var i = 0; i < 5; i++) {
      final x = (i - 2) * w * 0.038;
      final tipY = h * (0.115 - 0.035 * (1 - (i - 2).abs() / 2));
      final path = Path()
        ..moveTo(x - w * 0.014, h * 0.128)
        ..lineTo(x, tipY)
        ..lineTo(x + w * 0.014, h * 0.128)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, tipY),
            Offset(x, h * 0.128),
            [
              Colors.white.withValues(alpha: glint * (1 - pose.dissolve)),
              Color.lerp(theme, Colors.white, 0.3)!
                  .withValues(alpha: 0.75 * (1 - pose.dissolve)),
            ],
          ),
      );
    }
  }

  /// 吸血鬼的悬浮酒杯：杯里的那口"收藏"。
  static void _paintGoblet(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(w * 0.26, h * 0.56 + math.sin(t * 1.4) * h * 0.008);
    final s = w * 0.030;
    // 杯身
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - s, c.dy - s * 1.1)
        ..quadraticBezierTo(c.dx - s * 0.9, c.dy + s * 0.5, c.dx, c.dy + s * 0.5)
        ..quadraticBezierTo(c.dx + s * 0.9, c.dy + s * 0.5, c.dx + s, c.dy - s * 1.1)
        ..close(),
      Paint()
        ..color = const Color(0xFF1A0A12).withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );
    // 杯里的血
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - s * 0.82, c.dy - s * 0.72)
        ..quadraticBezierTo(
          c.dx - s * 0.72,
          c.dy + s * 0.2,
          c.dx,
          c.dy + s * 0.28,
        )
        ..quadraticBezierTo(
          c.dx + s * 0.72,
          c.dy + s * 0.2,
          c.dx + s * 0.82,
          c.dy - s * 0.72,
        )
        ..close(),
      Paint()..color = theme.withValues(alpha: 0.85 * (1 - pose.dissolve)),
    );
    // 杯柄与底座
    canvas.drawLine(
      Offset(c.dx, c.dy + s * 0.5),
      Offset(c.dx, c.dy + s * 1.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.4 * (1 - pose.dissolve)),
    );
    canvas.drawLine(
      Offset(c.dx - s * 0.5, c.dy + s * 1.1),
      Offset(c.dx + s * 0.5, c.dy + s * 1.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.4 * (1 - pose.dissolve)),
    );
  }

  /// 傀儡师手持的大剪刀。
  static void _paintScissors(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final c = Offset(w * 0.17, h * 0.60);
    final s = w * 0.055;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.5 + math.sin(t * 1.5) * 0.05);
    // 两片刃
    for (final side in [-1.0, 1.0]) {
      final blade = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(s * 0.5 * side, -s * 1.2, 0, -s * 2.1)
        ..quadraticBezierTo(s * 0.12 * side, -s * 1.2, 0, 0)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, -s * 2.1),
            [
              Colors.white.withValues(alpha: 0.85 * (1 - pose.dissolve)),
              Color.lerp(theme, Colors.white, 0.5)!
                  .withValues(alpha: 0.6 * (1 - pose.dissolve)),
            ],
          ),
      );
      // 指环
      canvas.drawCircle(
        Offset(s * 0.30 * side, s * 0.8),
        s * 0.38,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.2
          ..color = theme.withValues(alpha: 0.8 * (1 - pose.dissolve)),
      );
    }
    // 轴
    canvas.drawCircle(
      Offset.zero,
      s * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.8 * (1 - pose.dissolve)),
    );
    canvas.restore();
  }

  /// 傀儡师的丝线：从指尖延向画布边缘的几道细弧。
  static void _paintThreads(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
    final thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.30 * (1 - pose.dissolve));
    for (var i = 0; i < 3; i++) {
      final side = i == 1 ? 1.0 : -1.0;
      final sway = math.sin(t * 1.6 + i * 1.9) * w * 0.015;
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.115 * side, h * 0.645)
          ..quadraticBezierTo(
            w * (0.30 + i * 0.06) * side + sway,
            h * (0.70 + i * 0.03),
            w * (0.52 + i * 0.10) * side,
            h * (0.60 + i * 0.06) + sway,
          ),
        thread,
      );
    }
  }

  /// 巫姬额前的单边护目镜。
  static void _paintVisor(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.010
      ..color = const Color(0xFF2A4440);
    canvas.save();
    canvas.translate(0, h * 0.150);
    canvas.scale(1.0, 0.42);
    canvas.drawCircle(Offset.zero, w * 0.072, band);
    canvas.restore();
    final lensC = Offset(-w * 0.048, h * 0.150);
    canvas.drawCircle(
      lensC,
      w * 0.030,
      Paint()
        ..color = theme.withValues(alpha: 0.55 * (1 - pose.dissolve))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008),
    );
    canvas.drawCircle(
      lensC,
      w * 0.026,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.7 * (1 - pose.dissolve)),
    );
    canvas.drawCircle(
      lensC.translate(-w * 0.008, -w * 0.008),
      w * 0.006,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * (1 - pose.dissolve)),
    );
  }

  /// 龙女的鳞肩甲：两片叠瓦状的鳞甲覆在肩头。
  static void _paintScaleShoulders(
    Canvas canvas,
    double w,
    double h,
    Color theme,
    EnemyPose pose,
  ) {
    for (final side in [-1.0, 1.0]) {
      for (var row = 0; row < 2; row++) {
        final y = h * (0.315 + row * 0.045);
        final x0 = w * (0.10 + row * 0.01) * side;
        final scale = Path()
          ..moveTo(x0, y)
          ..quadraticBezierTo(
            w * (0.19 - row * 0.01) * side,
            y - h * 0.05,
            w * 0.24 * side,
            y + h * 0.012,
          )
          ..quadraticBezierTo(w * 0.16 * side, y + h * 0.04, x0, y)
          ..close();
        canvas.drawPath(
          scale,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(x0, y - h * 0.05),
              Offset(x0, y + h * 0.04),
              [
                Color.lerp(theme, Colors.white, 0.2)!
                    .withValues(alpha: 0.8 * (1 - pose.dissolve)),
                const Color(0xFF33140A).withValues(alpha: 0.9),
              ],
            ),
        );
      }
    }
  }

  /// 观测者胸口的吞噬漩涡：三层旋转的弧 + 中央暗核。
  static void _paintVortex(
    Canvas canvas,
    double w,
    double h,
    double t,
    Color theme,
    EnemyPose pose,
  ) {
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
}
