import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

/// 通用的能量条：支持「掉血残影」与叠加的护盾段，数值变化时平滑过渡。
class EnergyBar extends StatelessWidget {
  final double value;

  /// 护盾占比（叠加在血条之上）。
  final double shieldValue;

  final Color color;
  final double height;
  final String? trailing;
  final String? leading;
  final bool flip;

  const EnergyBar({
    super.key,
    required this.value,
    required this.color,
    this.shieldValue = 0,
    this.height = 14,
    this.trailing,
    this.leading,
    this.flip = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: v),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: shieldValue.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 260),
          builder: (context, shield, _) {
            return _Bar(
              value: animated,
              shield: shield,
              color: color,
              height: height,
              trailing: trailing,
              leading: leading,
              flip: flip,
            );
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double shield;
  final Color color;
  final double height;
  final String? trailing;
  final String? leading;
  final bool flip;

  const _Bar({
    required this.value,
    required this.shield,
    required this.color,
    required this.height,
    required this.trailing,
    required this.leading,
    required this.flip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          Text(leading!, style: AppText.label),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _BarPainter(
                value: value,
                shield: shield,
                color: color,
                flip: flip,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: AppText.number),
        ],
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final double value;
  final double shield;
  final Color color;
  final bool flip;

  _BarPainter({
    required this.value,
    required this.shield,
    required this.color,
    required this.flip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * 0.42;
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(full, Radius.circular(radius));

    // 底槽
    canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rr.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Palette.panelEdge.withValues(alpha: 0.9),
    );

    final barWidth = size.width * value;
    if (barWidth > 1) {
      final barRect = Rect.fromLTWH(
        flip ? size.width - barWidth : 0,
        0,
        barWidth,
        size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, Radius.circular(radius)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.white, 0.45)!,
              color,
              Color.lerp(color, Colors.black, 0.35)!,
            ],
          ).createShader(barRect),
      );
      // 顶部高光
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barRect.left, 1, barRect.width, size.height * 0.32),
          Radius.circular(radius),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );
    }

    // 护盾：从右向左叠加
    if (shield > 0.001) {
      final shieldWidth = size.width * shield.clamp(0.0, 1.0);
      final shieldRect = Rect.fromLTWH(
        flip ? 0 : size.width - shieldWidth,
        0,
        shieldWidth,
        size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(shieldRect, Radius.circular(radius)),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Palette.shield.withValues(alpha: 0.85),
              Palette.shield.withValues(alpha: 0.45),
            ],
          ).createShader(shieldRect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(shieldRect.deflate(1), Radius.circular(radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.value != value || old.shield != shield || old.color != color;
}

/// 小标签（避免与 Material 的 Chip 重名）。
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool dense;

  const Tag({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 9,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 主行动按钮（必杀技）。
class ActionButton extends StatelessWidget {
  final String label;
  final String? hint;
  final bool enabled;
  final double progress;
  final Color color;
  final VoidCallback onTap;

  const ActionButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.progress,
    required this.onTap,
    this.hint,
    this.color = Palette.rage,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: enabled
                ? [color.withValues(alpha: 0.95), color.withValues(alpha: 0.55)]
                : [Palette.panel, Palette.panel],
          ),
          border: Border.all(
            color: enabled ? Colors.white.withValues(alpha: 0.85) : Palette.panelEdge,
            width: enabled ? 1.6 : 1,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.button.copyWith(
                color: enabled ? const Color(0xFF241300) : Palette.textDim,
                fontSize: 14,
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF241300).withValues(alpha: 0.75)
                      : Palette.textDim.withValues(alpha: 0.8),
                  fontSize: 9.5,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 回合倒计时的小圆点，让玩家一眼看出敌人还有几回合出手。
class TurnPips extends StatelessWidget {
  final int total;
  final int remaining;
  final Color color;
  final bool danger;

  /// 动画相位，由调用方传入随时间递增的值来实现呼吸效果。
  final double phase;

  const TurnPips({
    super.key,
    required this.total,
    required this.remaining,
    required this.color,
    this.danger = false,
    this.phase = 0,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = danger ? 0.6 + 0.4 * math.sin(phase * 8) : 1.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < remaining
                    ? color.withValues(alpha: 0.25)
                    : color.withValues(alpha: (danger ? pulse : 0.95).clamp(0.0, 1.0)),
                border: Border.all(
                  color: color.withValues(alpha: 0.7),
                  width: 1,
                ),
                boxShadow: i >= remaining
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.7),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
