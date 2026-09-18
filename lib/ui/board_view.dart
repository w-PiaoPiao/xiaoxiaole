import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/board.dart';
import 'fx.dart';
import 'gem_art.dart';
import 'palette.dart';
import 'paint_utils.dart';

/// 棋盘视图：负责绘制 8x8 的宝石矩阵与全部棋盘特效，并处理点选/拖动交换。
class BoardView extends StatefulWidget {
  final BoardEngine board;
  final FxController fx;
  final int? selected;
  final bool enabled;

  /// 拖动或点击触发的交换请求。
  final void Function(int a, int b) onSwapRequest;
  final void Function(int index) onSelect;

  const BoardView({
    super.key,
    required this.board,
    required this.fx,
    required this.selected,
    required this.onSwapRequest,
    required this.onSelect,
    this.enabled = true,
  });

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  int? _dragFrom;
  bool _dragFired = false;

  int? _cellAt(Offset local, double cell) {
    final x = local.dx ~/ cell;
    final y = local.dy ~/ cell;
    if (x < 0 || x >= BoardEngine.cols || y < 0 || y >= BoardEngine.rows) return null;
    return y * BoardEngine.cols + x;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final cell = side / BoardEngine.cols;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (!widget.enabled) return;
                final index = _cellAt(details.localPosition, cell);
                if (index != null) widget.onSelect(index);
              },
              onPanStart: (details) {
                _dragFrom = _cellAt(details.localPosition, cell);
                _dragFired = false;
              },
              onPanUpdate: (details) {
                if (!widget.enabled || _dragFired || _dragFrom == null) return;
                final from = _dragFrom!;
                final center = Offset(
                  (from % BoardEngine.cols) * cell + cell / 2,
                  (from ~/ BoardEngine.cols) * cell + cell / 2,
                );
                final delta = details.localPosition - center;
                if (delta.distance < cell * 0.34) return;
                final int target;
                if (delta.dx.abs() > delta.dy.abs()) {
                  final nx = from % BoardEngine.cols + (delta.dx > 0 ? 1 : -1);
                  if (nx < 0 || nx >= BoardEngine.cols) return;
                  target = from + (delta.dx > 0 ? 1 : -1);
                } else {
                  final ny = from ~/ BoardEngine.cols + (delta.dy > 0 ? 1 : -1);
                  if (ny < 0 || ny >= BoardEngine.rows) return;
                  target = from + (delta.dy > 0 ? BoardEngine.cols : -BoardEngine.cols);
                }
                _dragFired = true;
                widget.onSwapRequest(from, target);
              },
              onPanEnd: (_) {
                _dragFrom = null;
                _dragFired = false;
              },
              onPanCancel: () {
                _dragFrom = null;
                _dragFired = false;
              },
              child: CustomPaint(
                painter: _BoardPainter(
                  board: widget.board,
                  fx: widget.fx,
                  selected: widget.selected,
                ),
                size: Size(side, side),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardPainter extends CustomPainter {
  final BoardEngine board;
  final FxController fx;
  final int? selected;

  _BoardPainter({required this.board, required this.fx, required this.selected})
      : super(repaint: fx);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / BoardEngine.cols;
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cell * 0.45),
    );

    // 底板
    canvas.drawRRect(
      panel,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Palette.panel.withValues(alpha: 0.96),
            Palette.slotFill.withValues(alpha: 0.98),
          ],
        ).createShader(panel.outerRect),
    );
    canvas.drawRRect(
      panel.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Palette.panelEdge.withValues(alpha: 0.9),
    );

    // 格子凹槽
    final slotPaint = Paint()..color = Palette.slotFill;
    final slotEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Palette.slotEdge.withValues(alpha: 0.85);
    for (var y = 0; y < BoardEngine.rows; y++) {
      for (var x = 0; x < BoardEngine.cols; x++) {
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell).deflate(cell * 0.045);
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.24));
        canvas.drawRRect(rr, slotPaint);
        canvas.drawRRect(rr, slotEdge);
      }
    }

    canvas.save();
    canvas.clipRRect(panel);

    // 选中格子
    final selectedIndex = selected;
    if (selectedIndex != null) {
      final sx = (selectedIndex % BoardEngine.cols) * cell;
      final sy = (selectedIndex ~/ BoardEngine.cols) * cell;
      final pulse = 0.5 + 0.5 * math.sin(fx.time * 7);
      final rect = Rect.fromLTWH(sx, sy, cell, cell).deflate(cell * 0.02);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.26)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.07
          ..color = Palette.gold.withValues(alpha: 0.55 + 0.35 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.05),
      );
    }

    // 宝石：按 y 排序，保证下落时的遮挡关系正确。
    //
    // 绘制以「引擎棋盘」为准：视觉层只是给宝石提供动画位置。已经落定的宝石
    // 一律画在它的目标格上，视觉层里缺失的宝石则直接按格子位置补画——
    // 这样无论动画时序出现什么意外，棋盘都不会出现空洞。
    final visuals = fx.gems.values.toList()
      ..sort((a, b) => a.y.compareTo(b.y));
    final drawn = <int>{};
    for (final gem in visuals) {
      drawn.add(gem.id);
      final settled = !gem.moving;
      _paintGem(
        canvas,
        cell,
        settled ? gem.toX : gem.x,
        settled ? gem.toY : gem.y,
        gem,
      );
    }

    // 兜底：引擎里有、视觉层没有的宝石，直接按目标格画出来
    for (var i = 0; i < board.cells.length; i++) {
      final gem = board.cells[i];
      if (gem == null || drawn.contains(gem.id)) continue;
      _paintGem(
        canvas,
        cell,
        (i % BoardEngine.cols).toDouble(),
        (i ~/ BoardEngine.cols).toDouble(),
        GemVisual(
          id: gem.id,
          type: gem.type,
          special: gem.special,
          x: 0,
          y: 0,
          toX: 0,
          toY: 0,
        ),
      );
    }

    // 正在消散的宝石
    for (final d in fx.dying) {
      final t = d.t;
      final rect = Rect.fromLTWH(d.x * cell, d.y * cell, cell, cell).deflate(cell * 0.10);
      GemArt.paint(
        canvas,
        rect,
        d.type,
        d.special,
        scale: 1.15 - 0.5 * t,
        alpha: (1 - t) * 0.9,
        flash: t < 0.35 ? 1 - t / 0.35 : 0,
        glow: 1 - t,
      );
    }

    // 圆环
    for (final ring in fx.rings) {
      final radius = ring.maxRadius * cell * Curves.easeOutCubic.transform(ring.t);
      canvas.drawCircle(
        Offset(ring.x * cell, ring.y * cell),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.width * cell * (1 - ring.t)
          ..color = ring.color.withValues(alpha: (1 - ring.t) * 0.75)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08),
      );
    }

    // 粒子
    for (final p in fx.particles) {
      final lifeRatio = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x * cell, p.y * cell),
        p.size * cell * lifeRatio,
        Paint()..color = p.color.withValues(alpha: lifeRatio * 0.9),
      );
    }

    canvas.restore();

    // 组合提示文字（画在裁剪之外，允许溢出一点）
    for (final label in fx.labels) {
      final t = Curves.easeOut.transform(label.t.clamp(0.0, 1.0));
      final pop = t < 0.25 ? Curves.easeOutBack.transform(t / 0.25) : 1.0;
      final alpha = label.t < 0.7 ? 1.0 : (1 - (label.t - 0.7) / 0.3);
      drawText(
        canvas,
        label.text,
        Offset(label.x * cell, label.y * cell - cell * 0.25 * t),
        TextStyle(
          color: label.color,
          fontSize: label.size,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
        alpha: alpha.clamp(0.0, 1.0),
        scale: pop,
        strokeColor: Colors.black.withValues(alpha: 0.65),
        strokeWidth: 5,
      );
    }
  }

  /// 画一颗宝石（含投影），位置以格为单位。
  void _paintGem(Canvas canvas, double cell, double gx, double gy, GemVisual gem) {
    final scale = gem.animateBirth && gem.birth < 1
        ? Curves.easeOutBack.transform(gem.birth).clamp(0.0, 1.4)
        : gem.scale;
    final rect = Rect.fromLTWH(gx * cell, gy * cell, cell, cell).deflate(cell * 0.10);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.bottom + cell * 0.05),
        width: rect.width * 0.62,
        height: rect.height * 0.2,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34 * gem.alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.07),
    );

    GemArt.paint(
      canvas,
      rect,
      gem.type,
      gem.special,
      scale: scale,
      alpha: gem.alpha,
      glow: gem.glow,
      spin: gem.spin,
      flash: gem.flash,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.fx != fx || oldDelegate.board != board;
}
