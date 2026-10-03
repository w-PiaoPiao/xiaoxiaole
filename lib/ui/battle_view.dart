import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/battle.dart';
import '../engine/gem.dart';
import '../engine/levels.dart';
import 'combat_art.dart';
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

  /// 右上角的两个入口。做成悬浮层而不是占位控件：标题行的高度不变，
  /// 下方留给角色的空间也就不受影响。
  final VoidCallback? onHelp;
  final VoidCallback? onMenu;

  const BattleView({
    super.key,
    required this.battle,
    required this.fx,
    required this.level,
    this.onHelp,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Color(level.enemy.themeColor);
    // 这个 widget 重建通常意味着战斗数值变了（血量、狂暴、易伤），而战斗区
    // 里的角色剪影直接依赖这些数值。它的重绘平时由 fx 的信号驱动，
    // 「减少动态效果」下那条路径会安静下来——这里补一次重绘，保证数值变化
    // 一定反映到画面上。
    fx.battleRepaint.ping();
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景渐变、光晕与暗角是静态的，单独一层，只在换关换色时重绘。
        CustomPaint(painter: _BattleBackdropPainter(theme: theme)),
        RepaintBoundary(
          child: CustomPaint(
            painter: _BattlePainter(battle: battle, fx: fx, theme: theme),
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
        if (onHelp != null || onMenu != null)
          Positioned(
            top: 0,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onHelp != null)
                    _HeaderButton(
                      icon: Icons.menu_book_outlined,
                      tooltip: '玩法说明',
                      onTap: onHelp!,
                    ),
                  if (onHelp != null && onMenu != null)
                    const SizedBox(width: 8),
                  if (onMenu != null)
                    _HeaderButton(
                      icon: Icons.tune,
                      tooltip: '菜单与设置',
                      onTap: onMenu!,
                    ),
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
            maxLines: 1,
          ),
        ),
        // 右侧这条留白是给悬浮的入口按钮的：状态标签已经从这一行挪走，
        // 无论敌人挂了多少 debuff 都不会再和按钮叠在一起。
        const SizedBox(width: 96),
      ],
    );
  }

  Widget _enemyBar(BuildContext context, Color theme) {
    final shieldRatio =
        battle.enemyShield / (battle.def.maxHp / 3).clamp(1, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: EnergyBar(
                value: battle.enemyHpRatio,
                shieldValue: shieldRatio,
                color: Palette.hpEnemy,
                height: 15,
                trailing: '${battle.enemyHp}',
                // 狂暴线：让"什么时候会变天"变成看得见的信息，而不是突然袭击。
                markers: battle.def.enrages
                    ? [battle.def.enrageAt]
                    : const [],
                semanticLabel: battle.def.hasPhases
                    ? '${battle.def.name} 第 ${battle.phaseIndex} 形态、'
                          '共 ${battle.def.phases} 形态，'
                          '生命 ${battle.enemyHp} / ${battle.def.maxHp}'
                    : '${battle.def.name} 生命 ${battle.enemyHp} / ${battle.def.maxHp}',
              ),
            ),
            // 多管血：血条后面挂一个 ×N 徽标，N 是**剩余**管数（含正在打的
            // 这一管）。打空一管时它立刻减 1、血条同时回满——玩家看到的是
            // "又一管被打掉了"，而不是一条空血条在那里等人来填。
            if (battle.phasesLeft > 1) ...[
              const SizedBox(width: 6),
              Tag(
                text: '×${battle.phasesLeft}',
                color: Palette.danger,
                dense: true,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // 状态标签原本挂在标题行右侧，会和右上角的按钮抢位置；
        // 挪到副标题这一行后既不会重叠，也不占额外高度。
        Row(
          children: [
            Flexible(
              child: Text(
                level.enemy.title,
                style: AppText.subtitle.copyWith(
                  color: theme.withValues(alpha: 0.85),
                ),
                maxLines: 1,
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
            if (battle.poisonTurns > 0)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Tag(text: '中毒', color: Color(0xFF7ACB6E), dense: true),
              ),
            if (battle.wardWeakenTurns > 0)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Tag(text: '结界', color: Color(0xFFC8A2E0), dense: true),
              ),
          ],
        ),
      ],
    );
  }

  Widget _turnRow(Color theme) {
    final danger = battle.dangerImminent;
    final color = danger ? Palette.danger : Palette.textDim;
    return Row(
      children: [
        // 只在敌方即将出手时，这排圆点才自己动起来。
        TurnPips(
          total: battle.def.turnsPerAttack,
          remaining: battle.turnsToAttack,
          color: color,
          danger: danger,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            danger ? '敌方即将出手' : '距离敌方行动 ${battle.turnsToAttack} 回合',
            style: AppText.label.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (danger)
          Tag(
            // 专属技能回合的预警直接报技能名：玩家提前一回合看到"她要亮
            // 什么本事"，就能决定是补盾、补血还是赶在落点前打断节奏。
            text: battle.nextAttackIsSkill
                ? '${battle.def.skill!.name} ${battle.incomingDamage}'
                : battle.nextAttackIsHeavy
                ? '重击 ${battle.incomingDamage}'
                : '攻击 ${battle.incomingDamage}',
            color: Palette.danger,
            dense: true,
          ),
      ],
    );
  }
}

/// 标题行右侧的小圆角按钮。比 Material 默认的 48 更贴合战斗区，
/// 但仍保留 [IconButton] 的 tooltip 与读屏语义。
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      color: Palette.textDim,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        backgroundColor: Palette.panel.withValues(alpha: 0.78),
        side: const BorderSide(color: Palette.panelEdge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}

/// 战斗区的静态背景：渐变、主题光晕与暗角。与动画无关，只在换关时重绘。
class _BattleBackdropPainter extends CustomPainter {
  final Color theme;

  _BattleBackdropPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
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
    final glowRadius = rect.width * 0.78;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            theme.withValues(alpha: 0.30),
            theme.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
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

  @override
  bool shouldRepaint(covariant _BattleBackdropPainter oldDelegate) =>
      oldDelegate.theme != theme;
}

/// 浮尘的静态参数：位置与速度只取决于序号，构建一次即可。
class _Mote {
  final double r1;
  final double r2;
  final double speed;

  const _Mote(this.r1, this.r2, this.speed);
}

class _BattlePainter extends CustomPainter {
  final BattleState battle;
  final FxController fx;
  final Color theme;

  _BattlePainter({required this.battle, required this.fx, required this.theme})
    : super(repaint: fx.battleRepaint);

  static double _noise(int i) {
    final v = math.sin(i * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// 预先算好每颗浮尘的随机量，避免每帧重复计算同样的三角函数。
  static final List<_Mote> _motes = List.generate(34, (i) {
    final r1 = _noise(i * 3 + 1);
    final r2 = _noise(i * 7 + 5);
    return _Mote(r1, r2, 0.012 + r1 * 0.03);
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintMotes(canvas, size);
    _paintCharacter(canvas, size);
    CombatArt.paintStrikes(canvas, size, fx.strikes);
    if (fx.ultimate != null) {
      CombatArt.paintUltimate(canvas, size, fx.ultimate!);
    }
    _paintFloats(canvas, size);
  }

  void _paintMotes(Canvas canvas, Size size) {
    final dot = Paint();
    // 浮尘的基色只取决于主题色，先在循环外算好；整个战斗区每帧都在重绘，
    // 循环里的 34 次 lerp 与 withValues 都是白花的。
    final base = Color.lerp(theme, Colors.white, 0.4)!;
    final fade = 1 - fx.dissolve * 0.5;
    // 「减少动态效果」下浮尘不再飘：它们本来是屏幕上唯一"永远在动"的东西，
    // 对前庭敏感的用户来说正是该收敛的部分。
    final time = fx.reducedMotion ? 0.0 : fx.time;
    for (var i = 0; i < _motes.length; i++) {
      final mote = _motes[i];
      // Dart 对 double 的 % 是欧几里得取模，结果恒非负，不必再补一次。
      final y = (mote.r2 - time * mote.speed) % 1.0;
      final x = mote.r1 * size.width + math.sin(time * 0.5 + i) * 10;
      final alpha = (0.10 + 0.30 * mote.r1) * fade;
      // 几十颗浮尘逐个模糊在软件渲染下太贵，用淡淡的圆点即可
      canvas.drawCircle(
        Offset(x, y * size.height),
        1.0 + mote.r1 * 2.1,
        dot..color = base.withValues(alpha: alpha * 0.75),
      );
    }
  }

  void _paintCharacter(Canvas canvas, Size size) {
    // 角色尽量占满舞台，同时把头顶让给上方的血条、状态标签与回合提示。
    final charH = size.height * 0.82;
    final charW = charH * 0.78;
    final box = Rect.fromLTWH(
      (size.width - charW) / 2,
      size.height * 0.20,
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
        recoil: fx.enemyRecoil,
        enraged: battle.enraged,
        dissolve: fx.dissolve,
      ),
      archetype: battle.def.archetype,
    );
    canvas.restore();
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
