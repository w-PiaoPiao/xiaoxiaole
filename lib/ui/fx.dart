import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/board.dart';
import '../engine/gem.dart';
import 'palette.dart';

/// 棋盘上一颗宝石的渲染状态。坐标单位是「格」，可以是小数（例如 -1.5 表示棋盘上方）。
class GemVisual {
  final int id;
  GemType type;
  SpecialKind special;

  double x;
  double y;

  double fromX;
  double fromY;
  double toX;
  double toY;

  /// 移动进度 0~1。
  double t;
  double duration;

  /// 出生动画进度 0~1（原地生成的强化宝石用）。
  double birth;
  bool animateBirth;

  double scale;
  double alpha;
  double glow;
  double flash;
  double spin;

  GemVisual({
    required this.id,
    required this.type,
    required this.special,
    required this.x,
    required this.y,
    required this.toX,
    required this.toY,
    this.fromX = 0,
    this.fromY = 0,
    this.t = 1,
    this.duration = 0.2,
    this.birth = 1,
    this.animateBirth = false,
    this.scale = 1,
    this.alpha = 1,
    this.glow = 0,
    this.flash = 0,
    this.spin = 0,
  });

  bool get moving => t < 1;

  bool get settled => t >= 1 && birth >= 1;
}

/// 正在消散的宝石。
class DyingGem {
  final double x;
  final double y;
  final GemType type;
  final SpecialKind special;
  double t = 0;
  final double duration;

  DyingGem({
    required this.x,
    required this.y,
    required this.type,
    required this.special,
    this.duration = 0.26,
  });
}

/// 棋盘空间的粒子。
class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final Color color;
  final double size;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.maxLife,
  }) : life = maxLife;
}

/// 棋盘空间的扩散圆环。
class Ring {
  final double x;
  final double y;
  final Color color;
  final double maxRadius;
  final double width;
  double t = 0;
  final double duration;

  Ring({
    required this.x,
    required this.y,
    required this.color,
    this.maxRadius = 2.2,
    this.width = 0.16,
    this.duration = 0.42,
  });
}

/// 棋盘上的组合提示文字（连击数、强化提示）。
class BoardLabel {
  final String text;
  final double x;
  final double y;
  final Color color;
  final double size;
  double t = 0;
  final double duration;

  BoardLabel({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    this.size = 34,
    this.duration = 0.95,
  });
}

/// 战斗区飘字。坐标是战斗区内的归一化坐标（0~1）。
class FloatText {
  final String text;
  final Color color;
  final double nx;
  final double ny;
  final double size;
  final bool outlined;
  double t = 0;
  final double duration;

  FloatText({
    required this.text,
    required this.color,
    required this.nx,
    required this.ny,
    this.size = 26,
    this.outlined = true,
    this.duration = 1.0,
  });
}

/// 必杀技的斩击特效进度。
class SlashFx {
  double t = 0;
  final double duration;
  final Color color;
  SlashFx({this.duration = 0.7, this.color = Palette.gold});
}

/// 所有动画与特效的统一驱动器。
///
/// 由 `GameScreen` 每帧调用 [tick]，把逻辑层的棋盘快照转换成位置、缩放、
/// 粒子等视觉状态；各个 CustomPainter 只负责按当前状态绘制。
class FxController extends ChangeNotifier {
  final Map<int, GemVisual> gems = {};
  final List<DyingGem> dying = [];
  final List<Particle> particles = [];
  final List<Ring> rings = [];
  final List<BoardLabel> labels = [];
  final List<FloatText> floats = [];

  SlashFx? slash;

  /// 屏幕震动强度（像素）。
  double shake = 0;

  /// 全局时间，用于宝石旋转等周期性动画。
  double time = 0;

  /// 敌方受击白闪。
  double enemyFlash = 0;

  /// 敌方出手前冲姿态。
  double enemyLunge = 0;

  /// 玩家受伤时的红色边缘闪烁。
  double playerFlash = 0;

  /// 敌人败北时的消散进度 0~1。
  double dissolve = 0;

  /// 消散动画的目标值，由 GameScreen 在胜负判定后设置。
  double dissolveTarget = 0;

  final math.Random _rng = math.Random();

  Completer<void>? _settle;

  /// 是否所有视觉元素都已落定（供自检使用）。
  bool get isSettled => _allSettled;

  bool get _allSettled {
    if (gems.values.any((g) => g.moving || g.birth < 1)) return false;
    if (dying.isNotEmpty) return false;
    return true;
  }

  /// 等待所有宝石落位。
  ///
  /// 带超时兜底：万一某个动画因为意外永远落不了位，也不能把玩家的操作
  /// 永久锁死（棋盘绘制本身以引擎为准，所以即使提前放行也不会出现空洞）。
  Future<void> settle({Duration timeout = const Duration(seconds: 3)}) async {
    if (_allSettled) return;
    final completer = _settle ??= Completer<void>();
    await completer.future.timeout(timeout, onTimeout: () {
      if (identical(_settle, completer)) _settle = null;
    });
  }

  // ------------------------------------------------------------------ 每帧推进

  void tick(double dt) {
    time += dt;
    for (final gem in gems.values) {
      if (gem.t < 1) {
        gem.t = math.min(1, gem.t + dt / gem.duration);
        final e = _easeOutCubic(gem.t);
        gem.x = gem.fromX + (gem.toX - gem.fromX) * e;
        gem.y = gem.fromY + (gem.toY - gem.fromY) * e;
      }
      if (gem.birth < 1) {
        gem.birth = math.min(1, gem.birth + dt / 0.24);
      }
      gem.glow = math.max(0, gem.glow - dt * 2.4);
      gem.flash = math.max(0, gem.flash - dt * 3.6);
      gem.spin += dt * 1.6;
    }

    for (final d in dying) {
      d.t = math.min(1, d.t + dt / d.duration);
    }
    dying.removeWhere((d) => d.t >= 1);

    for (final p in particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += dt * 6.5;
      p.vx *= 0.98;
    }
    particles.removeWhere((p) => p.life <= 0);

    for (final r in rings) {
      r.t = math.min(1, r.t + dt / r.duration);
    }
    rings.removeWhere((r) => r.t >= 1);

    for (final l in labels) {
      l.t = math.min(1, l.t + dt / l.duration);
    }
    labels.removeWhere((l) => l.t >= 1);

    for (final f in floats) {
      f.t = math.min(1, f.t + dt / f.duration);
    }
    floats.removeWhere((f) => f.t >= 1);

    final s = slash;
    if (s != null) {
      s.t = math.min(1, s.t + dt / s.duration);
      if (s.t >= 1) slash = null;
    }

    enemyFlash = math.max(0, enemyFlash - dt * 2.6);
    enemyLunge = math.max(0, enemyLunge - dt * 1.6);
    playerFlash = math.max(0, playerFlash - dt * 2.2);
    if (dissolveTarget > dissolve) {
      dissolve = math.min(dissolveTarget, dissolve + dt * 0.7);
    } else {
      dissolve = dissolveTarget;
    }
    shake = math.max(0, shake - dt * 26);

    if (_settle != null && _allSettled) {
      final completer = _settle;
      _settle = null;
      completer!.complete();
    }
    notifyListeners();
  }

  static double _easeOutCubic(double t) {
    final u = 1 - t;
    return 1 - u * u * u;
  }

  // ------------------------------------------------------------------ 棋盘同步

  /// 把视觉状态对齐到引擎快照。
  ///
  /// [spawnStartY] 里给出的宝石会从棋盘上方落入；起始位置与目标位置重合的
  /// 新宝石（也就是原地生成的强化宝石）会播放「诞生」缩放动画。
  void applySnapshot(
    List<GemSnapshot> snapshot, {
    Map<int, double> spawnStartY = const {},
    double fallDuration = 0.30,
  }) {
    final alive = <int>{};
    for (final cell in snapshot) {
      alive.add(cell.gemId);
      final gx = (cell.index % BoardEngine.cols).toDouble();
      final gy = (cell.index ~/ BoardEngine.cols).toDouble();
      final existing = gems[cell.gemId];
      if (existing == null) {
        final startY = spawnStartY[cell.gemId];
        final inPlace = startY != null && (startY - gy).abs() < 0.01;
        final fromY = inPlace ? gy : (startY ?? gy - 2.0);
        final distance = (gy - fromY).abs();
        gems[cell.gemId] = GemVisual(
          id: cell.gemId,
          type: cell.type,
          special: cell.special,
          x: gx,
          y: fromY,
          fromX: gx,
          fromY: fromY,
          toX: gx,
          toY: gy,
          t: 0,
          duration: (fallDuration * (0.55 + distance * 0.18)).clamp(0.16, 0.62),
          birth: inPlace ? 0 : 1,
          animateBirth: inPlace,
          scale: 1,
          glow: inPlace ? 1 : 0,
        );
      } else {
        existing.type = cell.type;
        existing.special = cell.special;
        if ((existing.toX - gx).abs() > 0.001 ||
            (existing.toY - gy).abs() > 0.001) {
          final distance = (existing.y - gy).abs();
          existing.fromX = existing.x;
          existing.fromY = existing.y;
          existing.toX = gx;
          existing.toY = gy;
          existing.t = 0;
          existing.duration =
              (fallDuration * (0.45 + distance * 0.16)).clamp(0.14, 0.55);
        }
      }
    }

    gems.removeWhere((id, _) => !alive.contains(id));
  }

  /// 播放一批宝石的消散效果。
  void beginClear(List<ClearedGem> cleared) {
    for (final c in cleared) {
      final visual = gems[c.gemId];
      final gx = visual?.x ?? (c.index % BoardEngine.cols).toDouble();
      final gy = visual?.y ?? (c.index ~/ BoardEngine.cols).toDouble();
      dying.add(DyingGem(
        x: gx,
        y: gy,
        type: c.type,
        special: c.special,
      ));
      gems.remove(c.gemId);
      _burstAt(gx, gy, c.type, c.special);
    }
  }

  void _burstAt(double gx, double gy, GemType type, SpecialKind special) {
    final color = Palette.gem(type);
    final count = special == SpecialKind.none ? 7 : 14;
    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 1.4 + _rng.nextDouble() * 3.0;
      particles.add(Particle(
        x: gx + 0.5,
        y: gy + 0.5,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 1.2,
        color: i.isEven ? color : Colors.white,
        size: 0.05 + _rng.nextDouble() * 0.07,
        maxLife: 0.35 + _rng.nextDouble() * 0.35,
      ));
    }
    rings.add(Ring(
      x: gx + 0.5,
      y: gy + 0.5,
      color: color,
      maxRadius: special == SpecialKind.none ? 1.0 : 2.6,
      duration: special == SpecialKind.none ? 0.34 : 0.55,
    ));
  }

  /// 强化宝石引爆时的额外表现。
  void playActivation(SpecialActivation activation) {
    final gx = (activation.index % BoardEngine.cols).toDouble();
    final gy = (activation.index ~/ BoardEngine.cols).toDouble();
    final color = Palette.gem(activation.type);
    rings.add(Ring(
      x: gx + 0.5,
      y: gy + 0.5,
      color: Colors.white,
      maxRadius: activation.kind == SpecialKind.prism ? 7.0 : 3.4,
      width: 0.26,
      duration: 0.5,
    ));
    for (final index in activation.area) {
      if (index == activation.index) continue;
      final x = (index % BoardEngine.cols).toDouble() + 0.5;
      final y = (index ~/ BoardEngine.cols).toDouble() + 0.5;
      particles.add(Particle(
        x: x,
        y: y,
        vx: (_rng.nextDouble() - 0.5) * 2,
        vy: -1 - _rng.nextDouble() * 2,
        color: color,
        size: 0.06,
        maxLife: 0.4,
      ));
    }
  }

  void addLabel(String text, double gx, double gy, Color color, {double size = 34}) {
    labels.add(BoardLabel(text: text, x: gx, y: gy, color: color, size: size));
  }

  void shakeBy(double amount) {
    shake = math.max(shake, amount);
  }

  void flashEnemy() {
    enemyFlash = 1;
  }

  void lunge() {
    enemyLunge = 1;
  }

  void addFloat(String text, Color color, {double nx = 0.5, double ny = 0.4, double size = 26}) {
    floats.add(FloatText(
      text: text,
      color: color,
      nx: nx + (_rng.nextDouble() - 0.5) * 0.10,
      ny: ny + (_rng.nextDouble() - 0.5) * 0.05,
      size: size,
    ));
  }

  void triggerSlash() {
    slash = SlashFx();
  }

  /// 重开一局时清空所有视觉状态。
  void reset() {
    gems.clear();
    dying.clear();
    particles.clear();
    rings.clear();
    labels.clear();
    floats.clear();
    slash = null;
    shake = 0;
    enemyFlash = 0;
    enemyLunge = 0;
    playerFlash = 0;
    dissolve = 0;
    dissolveTarget = 0;
  }
}
