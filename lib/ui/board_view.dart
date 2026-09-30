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

  /// 手指刚按下（或开始拖动）的格子，用来给一次操作一个即时的视觉回应。
  final void Function(int index)? onPress;

  /// 建议操作的落点（由落子顾问给出），两个格子会以金色脉冲标出。
  final int? hintA;
  final int? hintB;

  /// 必杀瞄准模式：手指按住哪一格，就把整行整列的清除范围预览出来。
  final bool aimingUltimate;

  const BoardView({
    super.key,
    required this.board,
    required this.fx,
    required this.selected,
    required this.onSwapRequest,
    required this.onSelect,
    this.onPress,
    this.hintA,
    this.hintB,
    this.aimingUltimate = false,
    this.enabled = true,
  });

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  int? _dragFrom;
  bool _dragFired = false;

  /// 手指按下的位置（局部坐标）。拖动方向以它为原点。
  Offset? _dragOrigin;

  /// 当前被手指压住的格子（点击或拖动都算），绘制时给一点高亮。
  int? _pressed;

  int? _cellAt(Offset local, double cell) {
    final x = local.dx ~/ cell;
    final y = local.dy ~/ cell;
    if (x < 0 || x >= BoardEngine.cols || y < 0 || y >= BoardEngine.rows) return null;
    return y * BoardEngine.cols + x;
  }

  void _setPressed(int? index) {
    if (_pressed == index) return;
    setState(() => _pressed = index);
  }

  @override
  Widget build(BuildContext context) {
    // 棋盘用独立的绘制信号（见 FxController.boardRepaint）：没有东西在动时
    // 它一帧都不重画。外层套 RepaintBoundary，这样战斗区那侧的逐帧重绘
    // 不会把棋盘一起拖下水。
    widget.fx.boardPulse = widget.selected != null ||
        widget.hintA != null ||
        widget.hintB != null ||
        widget.aimingUltimate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final cell = side / BoardEngine.cols;
        return Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: side,
              height: side,
              child: Semantics(
                label: '宝石棋盘，${BoardEngine.rows} 行 ${BoardEngine.cols} 列',
                hint: '点击相邻的两颗宝石交换位置，或直接拖动其中一颗',
                container: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (!widget.enabled) return;
                    _setPressed(_cellAt(details.localPosition, cell));
                  },
                  onTapUp: (details) {
                    // 先清掉按下高亮再判 enabled：两者之间 enabled 可能被翻掉
                    // （另一根手指触发了交换），那时直接 return 会让高亮永久
                    // 卡在那一格上。
                    _setPressed(null);
                    if (!widget.enabled) return;
                    final index = _cellAt(details.localPosition, cell);
                    if (index != null) widget.onSelect(index);
                  },
                  onTapCancel: () => _setPressed(null),
                  onPanDown: (details) {
                    // 记下真实的按下点：拖动方向必须以它为原点。若改用格子
                    // 中心，手指从格子边缘按下时（偏移可达半格）这个初始偏移
                    // 会被算进方向判定，垂直拖可能被判成水平换。
                    _dragOrigin = details.localPosition;
                  },
                  onPanStart: (details) {
                    if (!widget.enabled) return;
                    _dragFrom = _cellAt(details.localPosition, cell);
                    _dragFired = false;
                    _setPressed(_dragFrom);
                  },
                  onPanUpdate: (details) {
                    if (!widget.enabled) return;
                    // 瞄准时拖动只是在移动准星：跟着手指更新预览，
                    // 不交换任何宝石（松手才落点）。
                    if (widget.aimingUltimate) {
                      _setPressed(_cellAt(details.localPosition, cell));
                      return;
                    }
                    if (_dragFired || _dragFrom == null) return;
                    final from = _dragFrom!;
                    final origin = _dragOrigin ?? details.localPosition;
                    final delta = details.localPosition - origin;
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
                    _setPressed(null);
                    widget.onSwapRequest(from, target);
                  },
                  onPanEnd: (_) {
                    final aim = _pressed;
                    _dragFrom = null;
                    _dragFired = false;
                    _dragOrigin = null;
                    _setPressed(null);
                    // 拖动瞄准后松手即落点：比"拖到位再点一下"顺手得多。
                    if (widget.aimingUltimate && aim != null) {
                      widget.onSelect(aim);
                    }
                  },
                  onPanCancel: () {
                    _dragFrom = null;
                    _dragFired = false;
                    _dragOrigin = null;
                    _setPressed(null);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 底板与 64 个凹槽是完全静态的，单独一层，只在尺寸变化时重绘。
                      // 改造前它们跟着宝石一起每帧重画，一帧要画 128 个圆角矩形。
                      CustomPaint(painter: _BoardBackdropPainter()),
                      CustomPaint(
                        painter: _BoardPainter(
                          board: widget.board,
                          fx: widget.fx,
                          selected: widget.selected,
                          pressed: _pressed,
                          hintA: widget.hintA,
                          hintB: widget.hintB,
                          aimingUltimate: widget.aimingUltimate,
                        ),
                        size: Size(side, side),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 棋盘的静态底层：底板与 64 个凹槽。内容与动画无关，因此永不重绘。
class _BoardBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / BoardEngine.cols;
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cell * 0.45),
    );

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

    final slotPaint = Paint()..color = Palette.slotFill;
    final slotEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Palette.slotEdge.withValues(alpha: 0.85);
    final radius = Radius.circular(cell * 0.24);
    for (var y = 0; y < BoardEngine.rows; y++) {
      for (var x = 0; x < BoardEngine.cols; x++) {
        final rect = Rect.fromLTWH(x * cell, y * cell, cell, cell).deflate(cell * 0.045);
        final rr = RRect.fromRectAndRadius(rect, radius);
        canvas.drawRRect(rr, slotPaint);
        canvas.drawRRect(rr, slotEdge);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardBackdropPainter oldDelegate) => false;
}

class _BoardPainter extends CustomPainter {
  final BoardEngine board;
  final FxController fx;
  final int? selected;
  final int? pressed;
  final int? hintA;
  final int? hintB;
  final bool aimingUltimate;

  /// 排序用的复用缓冲：每帧只是排序，不再分配新列表。
  final List<GemVisual> _sorted = [];
  final Set<int> _drawn = {};

  /// 复用的画笔。棋盘每帧最多要画 64 颗宝石的投影 + 十几个高亮块，
  /// 逐个 new Paint 是纯粹的分配浪费。
  final Paint _shadow = Paint();
  final Paint _fill = Paint();

  _BoardPainter({
    required this.board,
    required this.fx,
    required this.selected,
    required this.pressed,
    required this.hintA,
    required this.hintB,
    this.aimingUltimate = false,
  }) : super(repaint: fx.boardRepaint);

  /// 单个格子的圆角矩形。
  RRect _cellRR(double cell, int index, double deflate) {
    final x = (index % BoardEngine.cols) * cell;
    final y = (index ~/ BoardEngine.cols) * cell;
    return RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, cell, cell).deflate(deflate),
      Radius.circular(cell * 0.26),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / BoardEngine.cols;
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cell * 0.45),
    );

    canvas.save();
    canvas.clipRRect(panel);

    // 按下/选中/提示的画笔共用一份，逐次改颜色即可。
    final stroke = Paint()..style = PaintingStyle.stroke;

    // 按下的格子：给一次操作一个即时回应，不必等交换结果。
    if (pressed != null) {
      canvas.drawRRect(
        _cellRR(cell, pressed!, cell * 0.04),
        _fill..color = Colors.white.withValues(alpha: 0.10),
      );
    }

    // 选中的格子：亮金色描边
    final selectedIndex = selected;
    final selectedGemId =
        selectedIndex == null ? null : board.cells[selectedIndex]?.id;
    if (selectedIndex != null) {
      final pulse = 0.5 + 0.5 * math.sin(fx.time * 7);
      canvas.drawRRect(
        _cellRR(cell, selectedIndex, cell * 0.02),
        stroke
          ..strokeWidth = cell * 0.07
          ..color = Palette.gold.withValues(alpha: 0.55 + 0.35 * pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.05),
      );
      stroke.maskFilter = null;
    }

    // 宝石：按 y 排序，保证下落时的遮挡关系正确。
    //
    // 绘制以「引擎棋盘」为准：视觉层只是给宝石提供动画位置。已经落定的宝石
    // 一律画在它的目标格上，视觉层里缺失的宝石则直接按格子位置补画——
    // 这样无论动画时序出现什么意外，棋盘都不会出现空洞。
    _sorted
      ..clear()
      ..addAll(fx.gems.values)
      ..sort((a, b) => a.y.compareTo(b.y));
    _drawn.clear();
    for (final gem in _sorted) {
      _drawn.add(gem.id);
      final settled = !gem.moving;
      _paintGem(
        canvas,
        cell,
        settled ? gem.toX : gem.x,
        settled ? gem.toY : gem.y,
        gem,
        lifted: gem.id == selectedGemId,
      );
    }

    // 兜底：引擎里有、视觉层没有的宝石，直接按目标格画出来
    for (var i = 0; i < board.cells.length; i++) {
      final gem = board.cells[i];
      if (gem == null || _drawn.contains(gem.id)) continue;
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
        lifted: gem.id == selectedGemId,
      );
    }

    // 必杀瞄准：把「整行 + 整列」的清除范围整个点亮，手指移到哪就预览到哪。
    // 玩家要能看见自己要清掉什么，才谈得上"自选落点"。
    if (aimingUltimate) {
      final aim = pressed ?? selected;
      if (aim != null) {
        final cx = aim % BoardEngine.cols;
        final cy = aim ~/ BoardEngine.cols;
        final pulse = 0.5 + 0.5 * math.sin(fx.time * 8);
        final fill = _fill..color = Palette.gold.withValues(alpha: 0.17 + 0.13 * pulse);
        for (var x = 0; x < BoardEngine.cols; x++) {
          canvas.drawRRect(_cellRR(cell, board.index(x, cy), cell * 0.045), fill);
        }
        for (var y = 0; y < BoardEngine.rows; y++) {
          canvas.drawRRect(_cellRR(cell, board.index(cx, y), cell * 0.045), fill);
        }
        // 十字的外沿描一圈亮金，落点那一格再加一层实心高亮。
        final edge = stroke
          ..strokeWidth = cell * 0.055
          ..color = Palette.gold.withValues(alpha: 0.45 + 0.35 * pulse);
        for (var x = 0; x < BoardEngine.cols; x++) {
          final rr = _cellRR(cell, board.index(x, cy), cell * 0.03);
          canvas.drawLine(
            Offset(rr.left, rr.top),
            Offset(rr.right, rr.top),
            edge,
          );
          canvas.drawLine(
            Offset(rr.left, rr.bottom),
            Offset(rr.right, rr.bottom),
            edge,
          );
        }
        for (var y = 0; y < BoardEngine.rows; y++) {
          final rr = _cellRR(cell, board.index(cx, y), cell * 0.03);
          canvas.drawLine(Offset(rr.left, rr.top), Offset(rr.left, rr.bottom), edge);
          canvas.drawLine(Offset(rr.right, rr.top), Offset(rr.right, rr.bottom), edge);
        }
        canvas.drawRRect(
          _cellRR(cell, aim, cell * 0.02),
          _fill..color = Palette.gold.withValues(alpha: 0.26 + 0.16 * pulse),
        );
        canvas.drawRRect(
          _cellRR(cell, aim, cell * 0.02),
          stroke
            ..strokeWidth = cell * 0.09
            ..color = Palette.gold,
        );
      }
    }

    // 建议落点：画在宝石之上，用金色边框 + 淡金底把两颗宝石整个框出来。
    // 画在下层时只露出格子边缘的一圈，在密集的棋盘上几乎看不见。
    if (!aimingUltimate && (hintA != null || hintB != null)) {
      final pulse = 0.5 + 0.5 * math.sin(fx.time * 6);
      _paintHint(canvas, cell, stroke, hintA, pulse);
      _paintHint(canvas, cell, stroke, hintB, pulse);
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

    // 圆环与粒子：共用一个画笔，避免每个元素都 new 一个 Paint。
    final dot = Paint();
    for (final ring in fx.rings) {
      final radius = ring.maxRadius * cell * Curves.easeOutCubic.transform(ring.t);
      canvas.drawCircle(
        Offset(ring.x * cell, ring.y * cell),
        radius,
        stroke
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08)
          ..strokeWidth = ring.width * cell * (1 - ring.t)
          ..color = ring.color.withValues(alpha: (1 - ring.t) * 0.75),
      );
      stroke.maskFilter = null;
    }

    for (final p in fx.particles) {
      final lifeRatio = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x * cell, p.y * cell),
        p.size * cell * lifeRatio,
        dot..color = p.color.withValues(alpha: lifeRatio * 0.9),
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

  /// 一格「建议落点」的高亮。
  void _paintHint(Canvas canvas, double cell, Paint stroke, int? index, double pulse) {
    if (index == null) return;
    final rr = _cellRR(cell, index, cell * 0.02);
    canvas.drawRRect(
      rr,
      _fill..color = Palette.gold.withValues(alpha: 0.12 + 0.10 * pulse),
    );
    canvas.drawRRect(
      rr,
      stroke
        ..strokeWidth = cell * 0.09
        ..color = Palette.gold.withValues(alpha: 0.55 + 0.45 * pulse),
    );
    canvas.drawRRect(
      rr.deflate(cell * 0.05),
      stroke
        ..strokeWidth = cell * 0.14
        ..color = Palette.gold.withValues(alpha: 0.22 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.09),
    );
    stroke.maskFilter = null;
  }

  /// 画一颗宝石（含投影），位置以格为单位。
  ///
  /// [lifted] 为 true 表示这颗正被选中：放大一点并抬起，让"选中了哪一颗"
  /// 在一屏密集的宝石里一眼可辨。
  void _paintGem(Canvas canvas, double cell, double gx, double gy, GemVisual gem, {bool lifted = false}) {
    final baseScale = gem.animateBirth && gem.birth < 1
        ? Curves.easeOutBack.transform(gem.birth).clamp(0.0, 1.4)
        : gem.scale;
    final breathe = lifted ? 1 + 0.02 * math.sin(fx.time * 7) : 1.0;
    final scale = baseScale * (lifted ? 1.12 * breathe : 1.0);
    final dy = lifted ? -0.035 : 0.0;
    final rect = Rect.fromLTWH(gx * cell, (gy + dy) * cell, cell, cell).deflate(cell * 0.10);

    // 投影刻意不用 MaskFilter：每帧 64 颗宝石各一次模糊，在软件渲染的
    // 模拟器上会把帧率打到个位数，得不偿失。
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.bottom + cell * (lifted ? 0.085 : 0.035)),
        width: rect.width * (lifted ? 0.78 : 0.70),
        height: rect.height * 0.16,
      ),
      _shadow..color = Colors.black.withValues(alpha: 0.26 * gem.alpha),
    );

    GemArt.paint(
      canvas,
      rect,
      gem.type,
      gem.special,
      scale: scale,
      alpha: gem.alpha,
      glow: lifted ? math.max(gem.glow, 0.45) : gem.glow,
      spin: gem.spin,
      flash: gem.flash,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.pressed != pressed ||
      oldDelegate.hintA != hintA ||
      oldDelegate.hintB != hintB ||
      oldDelegate.aimingUltimate != aimingUltimate ||
      oldDelegate.fx != fx ||
      oldDelegate.board != board;
}
