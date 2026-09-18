import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/battle.dart';
import '../engine/gem.dart';
import '../engine/levels.dart';
import 'enemy_art.dart';
import 'fx.dart';
import 'hud.dart';
import 'palette.dart';
import 'paint_utils.dart';

/// 屏幕上方 40% 左右的「战斗反馈区」：敌方角色舞台 + 血条 + 回合预警 + 飘字特效。
class BattleView extends StatelessWidget {
  final BattleState battle;
  final FxController fx;
  final LevelDef level;

  const BattleView({
    super.key,
    required this.battle,
    required this.fx,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Color(level.enemy.themeColor);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _BattlePainter(
              battle: battle,
              fx: fx,
              theme: theme,
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, theme),
                const SizedBox(height: 8),
                _enemyBar(context, theme),
                const SizedBox(height: 7),
                _turnRow(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, Color theme) {
    return Row(
      children: [
        Tag(text: level.name, color: Palette.gold, dense: true),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            level.enemy.name,
            style: AppText.enemyName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (battle.enraged)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Tag(text: '狂暴', color: Palette.danger, dense: true),
          ),
        if (battle.curseStacks > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tag(
              text: '易伤 x${battle.curseStacks}',
              color: Palette.gem(GemType.purple),
              dense: true,
            ),
          ),
        if (battle.healBlockTurns > 0)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Tag(text: '禁疗', color: Color(0xFFE85A7A), dense: true),
          ),
      ],
    );
  }

  Widget _enemyBar(BuildContext context, Color theme) {
    final shieldRatio = battle.enemyShield / (battle.def.maxHp / 3).clamp(1, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: EnergyBar(
                value: battle.enemyHpRatio,
                shieldValue: shieldRatio,
                color: Palette.hpEnemy,
                height: 15,
                trailing: '${battle.enemyHp}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          level.enemy.title,
          style: AppText.subtitle.copyWith(color: theme.withValues(alpha: 0.85)),
        ),
      ],
    );
  }

  Widget _turnRow(Color theme) {
    final danger = battle.dangerImminent;
    final color = danger ? Palette.danger : Palette.textDim;
    return Row(
      children: [
        AnimatedBuilder(
          animation: fx,
          builder: (context, _) => TurnPips(
            total: battle.def.turnsPerAttack,
            remaining: battle.turnsToAttack,
            color: color,
            danger: danger,
            phase: fx.time,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          danger ? '敌方即将出手' : '距离敌方行动 ${battle.turnsToAttack} 回合',
          style: AppText.label.copyWith(color: color),
        ),
        const Spacer(),
        if (danger)
          Tag(
            text: battle.nextAttackIsHeavy ? '重击 ${battle.incomingDamage}' : '攻击 ${battle.incomingDamage}',
            color: Palette.danger,
            dense: true,
          ),
      ],
    );
  }
}

class _BattlePainter extends CustomPainter {
  final BattleState battle;
  final FxController fx;
  final Color theme;

  _BattlePainter({
    required this.battle,
    required this.fx,
    required this.theme,
  }) : super(repaint: fx);

  static double _noise(int i) {
    final v = math.sin(i * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintBackground(canvas, rect);
    _paintMotes(canvas, size);
    _paintCharacter(canvas, size);
    _paintSlash(canvas, size);
    _paintFloats(canvas, size);
  }

  void _paintBackground(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.bgTop, Palette.bgMid, Palette.bgDeep],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    final glowCenter = Offset(rect.width * 0.5, rect.height * 0.58);
    canvas.drawCircle(
      glowCenter,
      rect.width * 0.78,
      Paint()
        ..shader = RadialGradient(
          colors: [
            theme.withValues(alpha: 0.30),
            theme.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: rect.width * 0.78)),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
          stops: const [0.5, 1.0],
        ).createShader(rect),
    );
  }

  void _paintMotes(Canvas canvas, Size size) {
    for (var i = 0; i < 34; i++) {
      final r1 = _noise(i * 3 + 1);
      final r2 = _noise(i * 7 + 5);
      final speed = 0.012 + r1 * 0.03;
      var y = (r2 - fx.time * speed) % 1.0;
      if (y < 0) y += 1.0;
      final x = r1 * size.width + math.sin(fx.time * 0.5 + i) * 10;
      final alpha = (0.10 + 0.30 * r1) * (1 - fx.dissolve * 0.5);
      // 几十颗浮尘逐个模糊在软件渲染下太贵，用淡淡的圆点即可
      canvas.drawCircle(
        Offset(x, y * size.height),
        1.0 + r1 * 2.1,
        Paint()
          ..color = Color.lerp(theme, Colors.white, 0.4)!.withValues(alpha: alpha * 0.75),
      );
    }
  }

  void _paintCharacter(Canvas canvas, Size size) {
    // 角色尽量占满舞台，同时把头顶让给上方的血条与回合提示。
    final charH = size.height * 0.84;
    final charW = charH * 0.78;
    final box = Rect.fromLTWH(
      (size.width - charW) / 2,
      size.height * 0.19,
      charW,
      charH,
    );
    canvas.save();
    canvas.translate(box.left, box.top);
    EnemyArt.paint(
      canvas,
      Size(charW, charH),
      theme,
      EnemyPose(
        time: fx.time,
        hpRatio: battle.enemyHpRatio,
        hitFlash: fx.enemyFlash,
        lunge: fx.enemyLunge,
        enraged: battle.enraged,
        dissolve: fx.dissolve,
      ),
    );
    canvas.restore();
  }

  void _paintSlash(Canvas canvas, Size size) {
    final slash = fx.slash;
    if (slash == null) return;
    final t = slash.t;
    for (var i = 0; i < 3; i++) {
      final delay = i * 0.10;
      final local = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final alpha = math.sin(local * math.pi);
      final x = -size.width * 0.4 + local * size.width * 1.8;
      final start = Offset(x - size.width * 0.25, size.height);
      final end = Offset(x + size.width * 0.25, size.height * 0.05);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = size.width * 0.11
          ..strokeCap = StrokeCap.round
          ..color = slash.color.withValues(alpha: alpha * 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05),
      );
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = size.width * 0.02
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: alpha * 0.95),
      );
    }
  }

  void _paintFloats(Canvas canvas, Size size) {
    for (final f in fx.floats) {
      final t = f.t;
      final rise = Curves.easeOutCubic.transform(t) * size.height * 0.11;
      final alpha = t < 0.68 ? 1.0 : (1 - (t - 0.68) / 0.32);
      final pop = t < 0.18
          ? Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0))
          : 1.0;
      drawText(
        canvas,
        f.text,
        Offset(f.nx * size.width, f.ny * size.height - rise),
        TextStyle(
          color: f.color,
          fontSize: f.size,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        alpha: alpha.clamp(0.0, 1.0),
        scale: pop,
        strokeColor: Colors.black.withValues(alpha: 0.75),
        strokeWidth: 5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BattlePainter oldDelegate) =>
      oldDelegate.battle != battle || oldDelegate.theme != theme;
}
