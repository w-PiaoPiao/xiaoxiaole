import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/gem.dart';
import '../engine/upgrades.dart';
import 'gem_art.dart';
import 'palette.dart';

/// 强化卡片的图标美术。
///
/// 五个图标直接复用宝石的形状（双剑 / 盾牌 / 十字 / 闪电 / 骷髅）——玩家在
/// 一局里已经把它们和五种效果绑在一起了；只有宝石之外的新概念（连锁、暴击、
/// 回复、必杀）才需要新画。底座沿用宝石那块八边切角牌，让强化卡片看起来
/// 和棋盘上的东西是同一个世界的。
class UpgradeArt {
  const UpgradeArt._();

  /// 底座：与宝石共用的八边切角形状。
  static Path get _tile => GemArt.tilePath;

  static final Map<UpgradeIcon, GemType> _gemIcon = {
    UpgradeIcon.sword: GemType.red,
    UpgradeIcon.shield: GemType.blue,
    UpgradeIcon.cross: GemType.green,
    UpgradeIcon.bolt: GemType.yellow,
    UpgradeIcon.skull: GemType.purple,
  };

  /// 图标路径一次构建、长期复用。卡片本身没有逐帧动画，但每次 rebuild 都
  /// 重画一遍 Path.combine 与十几个顶点也没有意义。
  static final Map<UpgradeIcon, Path> _glyphs = {
    for (final icon in UpgradeIcon.values) icon: _buildGlyph(icon),
  };

  /// 画一枚强化图标。[rect] 是正方形区域，[color] 是主题色。
  static void paint(
    Canvas canvas,
    Rect rect,
    UpgradeIcon icon,
    Color color, {
    double glow = 0.0,
  }) {
    final side = rect.width;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(side, side);

    if (glow > 0.01) {
      canvas.drawPath(
        _tile,
        Paint()
          ..color = color.withValues(alpha: (0.55 * glow).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 0.16),
      );
    }

    // 底座：暗色底 + 主题色描边，让卡片上的图标有"实体感"。
    canvas.drawPath(
      _tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Palette.slotFill, color, 0.34)!,
            Color.lerp(Palette.slotFill, color, 0.10)!,
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 1, 1)),
    );
    canvas.drawPath(
      _tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.055
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.85),
    );

    final glyph = _glyphPath(icon);
    final fill = Paint()..color = Color.lerp(color, Colors.white, 0.55)!;

    canvas.save();
    canvas.translate(0.2, 0.19);
    canvas.scale(0.6, 0.6);
    // 先描一圈暗边：图标压在中低亮度的底座上时，没有这一圈会糊成一块。
    canvas.drawPath(
      glyph,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.11
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawPath(glyph, fill);
    if (icon == UpgradeIcon.skull) {
      // 骷髅要靠"挖空"才认得出来，否则只是一块圆角白板。
      final hole = Paint()..color = Color.lerp(Palette.slotFill, color, 0.12)!;
      for (final p in GemArt.skullHoles) {
        canvas.drawPath(p, hole);
      }
    }
    canvas.restore();

    canvas.restore();
  }

  static Path _glyphPath(UpgradeIcon icon) => _glyphs[icon]!;

  static Path _buildGlyph(UpgradeIcon icon) {
    final gem = _gemIcon[icon];
    if (gem != null) return GemArt.iconPath(gem);
    return switch (icon) {
      UpgradeIcon.burst => _star(),
      UpgradeIcon.chain => _chain(),
      UpgradeIcon.heart => _heart(),
      UpgradeIcon.moon => _crescent(),
      UpgradeIcon.droplet => _droplet(),
      UpgradeIcon.thorn => _thorn(),
      UpgradeIcon.gear => _gear(),
      UpgradeIcon.trident => _trident(),
      UpgradeIcon.crosshair => _crosshair(),
      UpgradeIcon.blood => _bloodDrop(),
      // 前五个图标已由 _gemIcon 覆盖，这里只是兜底。
      UpgradeIcon.sword ||
      UpgradeIcon.shield ||
      UpgradeIcon.cross ||
      UpgradeIcon.bolt ||
      UpgradeIcon.skull => _star(),
    };
  }

  /// 八角星爆：一次性的大爆发。
  static Path _star() {
    final p = Path();
    const points = 8;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? 0.50 : 0.20;
      final a = -math.pi / 2 + i * math.pi / points;
      final x = 0.5 + math.cos(a) * r;
      final y = 0.5 + math.sin(a) * r;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  }

  /// 三个首尾相接的箭头，构成一个循环——连锁。
  static Path _chain() {
    final p = Path();
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / 3;
      final c = Offset(0.5 + math.cos(a) * 0.28, 0.5 + math.sin(a) * 0.28);
      p.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 0.30, height: 0.30),
          const Radius.circular(0.09),
        ),
      );
    }
    // 中间的实心菱形把三个环串起来
    p.addPath(
      Path()
        ..moveTo(0.5, 0.36)
        ..lineTo(0.64, 0.5)
        ..lineTo(0.5, 0.64)
        ..lineTo(0.36, 0.5)
        ..close(),
      Offset.zero,
    );
    return p;
  }

  static Path _heart() {
    return Path()
      ..moveTo(0.5, 0.92)
      ..cubicTo(0.06, 0.60, 0.06, 0.26, 0.28, 0.15)
      ..cubicTo(0.41, 0.08, 0.50, 0.18, 0.50, 0.26)
      ..cubicTo(0.50, 0.18, 0.59, 0.08, 0.72, 0.15)
      ..cubicTo(0.94, 0.26, 0.94, 0.60, 0.5, 0.92)
      ..close();
  }

  /// 月牙：必杀「斩月」的标志。
  static Path _crescent() {
    final outer = Path()
      ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.46));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(center: const Offset(0.70, 0.42), radius: 0.42),
      );
    return Path.combine(PathOperation.difference, outer, inner);
  }

  /// 水滴：上尖下圆。「溢流护盾」把治不下的那部分收在这里。
  static Path _droplet() {
    return Path()
      ..moveTo(0.5, 0.06)
      ..cubicTo(0.74, 0.36, 0.90, 0.55, 0.90, 0.68)
      ..cubicTo(0.90, 0.86, 0.72, 0.96, 0.50, 0.96)
      ..cubicTo(0.28, 0.96, 0.10, 0.86, 0.10, 0.68)
      ..cubicTo(0.10, 0.55, 0.26, 0.36, 0.50, 0.06)
      ..close();
  }

  /// 荆棘：一圈尖刺围着核心。被护盾扛下的伤害从这里扎回去。
  static Path _thorn() {
    final p = Path()
      ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.24));
    const spikes = 8;
    for (var i = 0; i < spikes; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / spikes;
      final tip = Offset(0.5 + math.cos(a) * 0.48, 0.5 + math.sin(a) * 0.48);
      final left = Offset(
        0.5 + math.cos(a - 0.20) * 0.26,
        0.5 + math.sin(a - 0.20) * 0.26,
      );
      final right = Offset(
        0.5 + math.cos(a + 0.20) * 0.26,
        0.5 + math.sin(a + 0.20) * 0.26,
      );
      p
        ..moveTo(left.dx, left.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
    }
    return p;
  }

  /// 齿轮：过载的引擎。中间挖空，用 evenOdd 让孔真的透出来。
  static Path _gear() {
    final p = Path()..fillType = PathFillType.evenOdd;
    p.addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.26));
    const teeth = 8;
    for (var i = 0; i < teeth; i++) {
      final a = i * math.pi * 2 / teeth;
      final c = Offset(0.5 + math.cos(a) * 0.42, 0.5 + math.sin(a) * 0.42);
      p.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 0.20, height: 0.20),
          const Radius.circular(0.05),
        ),
      );
    }
    p.addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.13));
    return p;
  }

  /// 三叉：一次戳中不止一种颜色——「棱镜宗师」。
  static Path _trident() {
    final p = Path();
    for (final dx in [-0.26, 0.0, 0.26]) {
      p.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0.5 + dx, 0.34),
            width: 0.10,
            height: 0.56,
          ),
          const Radius.circular(0.04),
        ),
      );
    }
    p.addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(0.18, 0.50, 0.82, 0.60),
        const Radius.circular(0.04),
      ),
    );
    p.addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(0.44, 0.58, 0.56, 0.94),
        const Radius.circular(0.04),
      ),
    );
    return p;
  }

  /// 十字准星：破空宝石升级成"整行 + 整列"。
  static Path _crosshair() {
    final p = Path();
    const arm = 0.10; // 线宽的一半
    const reach = 0.46;
    const gap = 0.16; // 中心留空的半径
    p.addRect(
      const Rect.fromLTRB(0.5 - arm, 0.5 - reach, 0.5 + arm, 0.5 - gap),
    );
    p.addRect(
      const Rect.fromLTRB(0.5 - arm, 0.5 + gap, 0.5 + arm, 0.5 + reach),
    );
    p.addRect(
      const Rect.fromLTRB(0.5 - reach, 0.5 - arm, 0.5 - gap, 0.5 + arm),
    );
    p.addRect(
      const Rect.fromLTRB(0.5 + gap, 0.5 - arm, 0.5 + reach, 0.5 + arm),
    );
    p.addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.09));
    return p;
  }

  /// 血滴：倒置的水滴（血是往下滴的），与「溢流护盾」的正立水滴区分开。
  static Path _bloodDrop() {
    return Path()
      ..moveTo(0.5, 0.94)
      ..cubicTo(0.26, 0.64, 0.10, 0.45, 0.10, 0.32)
      ..cubicTo(0.10, 0.14, 0.28, 0.04, 0.50, 0.04)
      ..cubicTo(0.72, 0.04, 0.90, 0.14, 0.90, 0.32)
      ..cubicTo(0.90, 0.45, 0.74, 0.64, 0.50, 0.94)
      ..close();
  }
}
