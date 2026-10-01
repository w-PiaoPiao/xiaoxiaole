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

  /// 附着在这颗宝石上的机关（视觉层据此把冰壳 / 藤蔓 / 祭坛画在宝石上）。
  ObstacleKind? obstacle;

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
    this.obstacle,
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

/// 打击特效类型：不同宝石打出的攻击有各自的视觉语言，
/// 让玩家一眼看出"这一下是什么打的"。
enum StrikeKind {
  /// 红色 · 交叉双剑：两道剑气交叉斩过敌人
  sword,

  /// 黄色 · 闪电：从天而降的落雷
  lightning,

  /// 紫色 · 骷髅：诅咒印记烙在敌人身上
  curse,

  /// 绿色 · 十字：治疗十字与上升的光点（作用在玩家一侧）
  heal,

  /// 蓝色 · 盾牌：护盾成型（作用在玩家一侧）
  shield,

  /// 敌人命中玩家：红色爪痕划过玩家一侧
  enemyHit,
}

/// 一次打击特效。坐标是战斗区内的归一化坐标。
class StrikeFx {
  final StrikeKind kind;
  final double nx;
  final double ny;

  /// 强度 0.7~1.7，由这一次消除的宝石数量决定：消得越多，打得越狠。
  final double power;

  /// 用于生成稳定的随机形状（闪电走向等）。
  final int seed;

  double t = 0;
  final double duration;

  StrikeFx({
    required this.kind,
    required this.seed,
    this.nx = 0.5,
    this.ny = 0.52,
    this.power = 1.0,
    this.duration = 0.5,
  });
}

/// 必杀技「斩月」：一道月牙形剑气横贯战场。
class UltimateFx {
  double t = 0;
  final double duration;

  /// 月牙的起始角，每次释放略有不同，避免看腻。
  final double tilt;

  UltimateFx({this.duration = 0.85, this.tilt = 0});

  static double randomTilt(math.Random rng) => (rng.nextDouble() - 0.5) * 0.5;
}

/// 一个只能由持有者触发的重绘信号。
///
/// 棋盘只在真的"有东西在动"时才需要重画：宝石全部落定、没有粒子、没有选中
/// 脉冲时，整块棋盘是静止的——而玩家思考落点的时间占了一局里的大半。
class RepaintSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// 所有动画与特效的统一驱动器。
///
/// 由 `GameScreen` 每帧调用 [tick]，把逻辑层的棋盘快照转换成位置、缩放、
/// 粒子等视觉状态；各个 CustomPainter 只负责按当前状态绘制。
class FxController extends ChangeNotifier {
  /// 棋盘重绘信号：棋盘的 painter 监听它，而不是 [FxController] 本身。
  final RepaintSignal boardRepaint = RepaintSignal();

  /// 战斗区的重绘信号。
  ///
  /// 正常模式下浮尘一直在飘、敌人的剪影也在摆动，战斗区本来就该逐帧重绘；
  /// 但开了「减少动态效果」之后这两样都是静止的，这时只有真的发生动画
  /// （飘字、打击、白闪、消散）才需要重画——屏幕上大半时间没有动静，
  /// 能省下整块战斗区的逐帧绘制。
  final RepaintSignal battleRepaint = RepaintSignal();

  /// 由 BoardView 每帧告知：棋盘上是否有依赖时间的持续脉冲（选中的呼吸、
  /// 落子提示的闪烁）。有的话棋盘每帧都要重绘。
  bool boardPulse = false;

  bool _boardDirty = true;
  bool _battleDirty = true;

  final Map<int, GemVisual> gems = {};
  final List<DyingGem> dying = [];
  final List<Particle> particles = [];
  final List<Ring> rings = [];
  final List<BoardLabel> labels = [];
  final List<FloatText> floats = [];

  final List<StrikeFx> strikes = [];

  UltimateFx? ultimate;

  /// 命中定格剩余时间：>0 时时间几乎停住，制造打击停顿。
  double hitStop = 0;

  /// 敌人受击后仰强度 0~1。
  double enemyRecoil = 0;

  /// 屏幕震动强度（像素）。触发点传入的强度只表达相对轻重，落到这里之前
  /// 已经按 [_shakeScale] 收敛，且不会超过 [_shakeMax]。
  double shake = 0;

  /// 震屏相位时钟（秒）。故意不复用 [time]：命中定格会把 [time] 的推进速度
  /// 压到 1/10，共用的话抖动频率会从 ~13 Hz 掉到 1 Hz 出头，短促的"抖"
  /// 变成缓慢的"晃"——那比震动本身更晕。
  double _shakePhase = 0;

  /// 震屏强度到像素位移的换算系数。
  ///
  /// 调用点传的是"相对轻重"（必杀 26、连击 7~26、每次消除的伤害 5~17），
  /// 早期这张表被直接当像素用：连击时每一步都在刷新震动，棋盘一整局都在晃。
  /// 收敛到 0.38 后，最重的必杀约 10 像素（约半个格子），打击感还在，
  /// 又不会晃到看不清落点。
  static const double _shakeScale = 0.38;

  /// 震屏的像素上限。伤害类震动是 `3 + 伤害 × 0.03`，无尽模式后期伤害能到
  /// 几百上千，不封顶的话后面每一刀都会把屏幕打成筛子。
  static const double _shakeMax = 11;

  /// 震屏衰减速率（像素/秒）。原来 26——26 像素的必杀要晃满一秒；现在 62，
  /// 最重的一击约 0.16 秒收干净，是"顿一下"而不是"晃一阵"。
  static const double _shakeDecay = 62;

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

  /// 屏幕震动开关（设置里可关，系统的"减少动态效果"也会把它关掉）。
  bool allowShake = true;

  /// 白闪/红闪开关。光敏或前庭敏感的用户可以关掉，游戏逻辑不受影响。
  bool allowFlash = true;

  /// 系统开启了「减少动态效果」。除了震屏与闪光（由 [allowShake] /
  /// [allowFlash] 一并关掉），命中定格的全屏慢动作与粒子预算也要收敛——
  /// 它们才是整套演出里最"晃"的部分。
  bool reducedMotion = false;

  final math.Random _rng = math.Random();

  Completer<void>? _settle;

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
    await completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_settle, completer)) _settle = null;
      },
    );
  }

  // ------------------------------------------------------------------ 每帧推进

  void tick(double dt) {
    // 命中定格：命中瞬间把时间放慢到 1/10，形成"顿一下"的打击感。
    // 注意先用真实 dt 扣减，否则定格永远退不掉。
    //
    // 震屏的衰减与相位走 realDt：定格放慢的是画面动画，震屏跟着慢下来只会
    // 把短促的抖动拖成缓慢的摇摆。
    final realDt = dt;
    if (reducedMotion) {
      hitStop = 0;
    } else if (hitStop > 0) {
      hitStop = math.max(0, hitStop - dt);
      dt *= 0.1;
    }
    time += dt;
    _shakePhase += realDt;
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
      // 棱镜的彩色环一直在转；开了「减少动态效果」就让它停下来，
      // 棋盘随之下面的 _computeBoardDirty 一起回到"静止不重绘"。
      if (!reducedMotion) gem.spin += dt * 1.6;
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

    for (final strike in strikes) {
      strike.t = math.min(1, strike.t + dt / strike.duration);
    }
    strikes.removeWhere((s) => s.t >= 1);

    final ult = ultimate;
    if (ult != null) {
      ult.t = math.min(1, ult.t + dt / ult.duration);
      if (ult.t >= 1) ultimate = null;
    }

    enemyFlash = math.max(0, enemyFlash - dt * 2.6);
    enemyLunge = math.max(0, enemyLunge - dt * 1.6);
    enemyRecoil = math.max(0, enemyRecoil - dt * 3.4);
    playerFlash = math.max(0, playerFlash - dt * 2.2);
    if (dissolveTarget > dissolve) {
      dissolve = math.min(dissolveTarget, dissolve + dt * 0.7);
    } else {
      dissolve = dissolveTarget;
    }
    shake = math.max(0, shake - realDt * _shakeDecay);

    if (_settle != null && _allSettled) {
      final completer = _settle;
      _settle = null;
      completer!.complete();
    }

    // 棋盘该不该重画：这一帧在动，或者上一帧还在动（动画刚停的那一帧也要
    // 把最终位置画出来）。
    final dirty = _computeBoardDirty();
    if (dirty || _boardDirty) boardRepaint.ping();
    _boardDirty = dirty;

    final battleDirty = _computeBattleDirty();
    if (battleDirty || _battleDirty) battleRepaint.ping();
    _battleDirty = battleDirty;

    notifyListeners();
  }

  /// 战斗区是否需要重绘。
  ///
  /// 正常模式直接返回 true：浮尘与敌人剪影都是持续动画，逐帧重绘是必要的。
  /// 「减少动态效果」把它们停下来之后，才只剩这些真正的动画事件。
  bool _computeBattleDirty() {
    if (!reducedMotion) return true;
    return floats.isNotEmpty ||
        strikes.isNotEmpty ||
        ultimate != null ||
        enemyFlash > 0.01 ||
        enemyLunge > 0.01 ||
        enemyRecoil > 0.01 ||
        playerFlash > 0.01 ||
        dissolve > 0.01 ||
        dissolveTarget > 0.01;
  }

  /// 棋盘上是否还有正在变化的东西。
  bool _computeBoardDirty() {
    if (boardPulse) return true;
    if (dying.isNotEmpty ||
        particles.isNotEmpty ||
        rings.isNotEmpty ||
        labels.isNotEmpty) {
      return true;
    }
    for (final gem in gems.values) {
      if (gem.moving || gem.birth < 1 || gem.glow > 0.01 || gem.flash > 0.01) {
        return true;
      }
      // 棱镜的彩色环一直在转，所以棋盘每帧都得重画——除非玩家开了
      // 「减少动态效果」，那时环是静止的（见 tick），棋盘也就安静了。
      if (gem.special == SpecialKind.prism && !reducedMotion) return true;
    }
    return false;
  }

  /// 震屏偏移（像素）。用两个不同频率的正弦合成，比纯随机更"有力"，
  /// 也不会因为随机抖动显得噪。
  ///
  /// 频率约 13 Hz / 18 Hz：原来 16 / 22 Hz 配大幅度时整个界面会糊成一片，
  /// 降下来才看得清是"棋盘在顿"而不是"屏幕在嗡"。
  Offset get shakeOffset {
    if (shake <= 0.05) return Offset.zero;
    final t = _shakePhase * 60;
    return Offset(math.sin(t * 1.35) * shake, math.cos(t * 1.85) * shake * 0.6);
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
          obstacle: cell.obstacle,
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
        existing.obstacle = cell.obstacle;
        if ((existing.toX - gx).abs() > 0.001 ||
            (existing.toY - gy).abs() > 0.001) {
          final distance = (existing.y - gy).abs();
          existing.fromX = existing.x;
          existing.fromY = existing.y;
          existing.toX = gx;
          existing.toY = gy;
          existing.t = 0;
          existing.duration = (fallDuration * (0.45 + distance * 0.16)).clamp(
            0.14,
            0.55,
          );
        }
      }
    }

    gems.removeWhere((id, _) => !alive.contains(id));
  }

  /// 播放一批宝石的消散效果。
  void beginClear(List<ClearedGem> cleared) {
    // 一次清掉几十颗（组合技、棱镜）时按颗数削减粒子预算。
    // 每颗都炸满的话，39 颗就是近 300 个粒子 + 39 个圆环，一帧光画圆就要
    // 好几毫秒；而且命中定格会把时间放慢到 1/10，粒子在屏幕上留得更久，
    // 峰值还会更高。少几颗碎屑肉眼看不出来，掉帧看得出来。
    var perGem = switch (cleared.length) {
      > 28 => 3,
      > 16 => 5,
      _ => 7,
    };
    // 「减少动态效果」下再砍一半：爆发粒子是屏幕上变化最剧烈的东西。
    if (reducedMotion) perGem = math.max(1, perGem ~/ 2);
    for (final c in cleared) {
      final visual = gems[c.gemId];
      final gx = visual?.x ?? (c.index % BoardEngine.cols).toDouble();
      final gy = visual?.y ?? (c.index ~/ BoardEngine.cols).toDouble();
      dying.add(DyingGem(x: gx, y: gy, type: c.type, special: c.special));
      gems.remove(c.gemId);
      _burstAt(gx, gy, c.type, c.special, budget: perGem);
    }
  }

  /// 机关被破除时的碎裂反馈：一圈同色涟漪 + 少量碎屑。
  ///
  /// 机关对应的颜色取自 Palette 里已经存在的语义色（冰=护盾蓝、
  /// 藤=生命绿、祭坛=金色），不再引入一套新的色板。
  void crackObstacle(int index, ObstacleKind kind) {
    final gx = (index % BoardEngine.cols).toDouble();
    final gy = (index ~/ BoardEngine.cols).toDouble();
    final color = switch (kind) {
      ObstacleKind.frost => Palette.shield,
      ObstacleKind.vine => Palette.hpPlayer,
      ObstacleKind.altar => Palette.gold,
    };
    final budget = reducedMotion ? 2 : 5;
    for (var i = 0; i < budget; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 1.0 + _rng.nextDouble() * 2.2;
      particles.add(
        Particle(
          x: gx + 0.5,
          y: gy + 0.5,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed - 0.9,
          color: i.isEven ? color : Colors.white,
          size: 0.04 + _rng.nextDouble() * 0.05,
          maxLife: 0.30 + _rng.nextDouble() * 0.25,
        ),
      );
    }
    rings.add(
      Ring(
        x: gx + 0.5,
        y: gy + 0.5,
        color: color,
        maxRadius: 1.1,
        duration: 0.34,
      ),
    );
  }

  void _burstAt(
    double gx,
    double gy,
    GemType type,
    SpecialKind special, {
    int budget = 7,
  }) {
    final color = Palette.gem(type);
    final count = special == SpecialKind.none ? budget : budget * 2;
    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 1.4 + _rng.nextDouble() * 3.0;
      particles.add(
        Particle(
          x: gx + 0.5,
          y: gy + 0.5,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed - 1.2,
          color: i.isEven ? color : Colors.white,
          size: 0.05 + _rng.nextDouble() * 0.07,
          maxLife: 0.35 + _rng.nextDouble() * 0.35,
        ),
      );
    }
    rings.add(
      Ring(
        x: gx + 0.5,
        y: gy + 0.5,
        color: color,
        maxRadius: special == SpecialKind.none ? 1.0 : 2.6,
        duration: special == SpecialKind.none ? 0.34 : 0.55,
      ),
    );
  }

  /// 强化宝石引爆时的额外表现。
  void playActivation(SpecialActivation activation) {
    final gx = (activation.index % BoardEngine.cols).toDouble();
    final gy = (activation.index ~/ BoardEngine.cols).toDouble();
    final color = Palette.gem(activation.type);
    rings.add(
      Ring(
        x: gx + 0.5,
        y: gy + 0.5,
        color: Colors.white,
        // 冲击波的大小跟着实际清除范围走：单颗破空是 8 格、组合技的十字是
        // 15 格、同色风暴能到 50 格以上，用同一个半径就分不出轻重了。
        maxRadius: activation.kind == SpecialKind.prism
            ? 7.0
            : (2.0 + activation.area.length * 0.16).clamp(2.6, 6.5),
        width: 0.26,
        duration: 0.5,
      ),
    );
    for (final index in activation.area) {
      if (index == activation.index) continue;
      final x = (index % BoardEngine.cols).toDouble() + 0.5;
      final y = (index ~/ BoardEngine.cols).toDouble() + 0.5;
      particles.add(
        Particle(
          x: x,
          y: y,
          vx: (_rng.nextDouble() - 0.5) * 2,
          vy: -1 - _rng.nextDouble() * 2,
          color: color,
          size: 0.06,
          maxLife: 0.4,
        ),
      );
    }
  }

  void addLabel(
    String text,
    double gx,
    double gy,
    Color color, {
    double size = 34,
  }) {
    labels.add(BoardLabel(text: text, x: gx, y: gy, color: color, size: size));
  }

  /// 触发一次震屏。[amount] 是相对强度（必杀 26 最重、非法交换 5 最轻），
  /// 实际位移按 [_shakeScale] 收敛并封顶在 [_shakeMax]。
  void shakeBy(double amount) {
    if (!allowShake) return;
    shake = math.max(shake, math.min(amount * _shakeScale, _shakeMax));
  }

  void lunge() {
    enemyLunge = 1;
  }

  void addFloat(
    String text,
    Color color, {
    double nx = 0.5,
    double ny = 0.4,
    double size = 26,
  }) {
    floats.add(
      FloatText(
        text: text,
        color: color,
        nx: nx + (_rng.nextDouble() - 0.5) * 0.10,
        ny: ny + (_rng.nextDouble() - 0.5) * 0.05,
        size: size,
      ),
    );
  }

  /// 打出一次打击特效。[count] 是这次消除的宝石数量，决定力度。
  void addStrike(
    StrikeKind kind, {
    int count = 3,
    double nx = 0.5,
    double ny = 0.52,
  }) {
    strikes.add(
      StrikeFx(
        kind: kind,
        seed: _rng.nextInt(1 << 20),
        nx: nx + (_rng.nextDouble() - 0.5) * 0.06,
        ny: ny + (_rng.nextDouble() - 0.5) * 0.04,
        power: (0.72 + count * 0.085).clamp(0.72, 1.7),
        duration: switch (kind) {
          StrikeKind.lightning => 0.34,
          StrikeKind.sword => 0.46,
          StrikeKind.curse => 0.62,
          StrikeKind.heal => 0.7,
          StrikeKind.shield => 0.6,
          StrikeKind.enemyHit => 0.5,
        },
      ),
    );
  }

  /// 命中：白闪 + 后仰 + 定格。[damage] 越大打得越重。
  ///
  /// [crit] 为 true 时把这一次的演出整体加重——暴击的意义就在于
  /// "和普通一击明显不一样"，只多跳个数字是不够的。
  void hitImpact({required int damage, bool crit = false}) {
    final weight = (0.55 + damage / 220).clamp(0.55, 1.5);
    hitStop = math.max(hitStop, (crit ? 0.11 : 0.05) * weight);
    enemyRecoil = math.min(1.0, enemyRecoil + (crit ? 0.9 : 0.55) * weight);
    if (allowFlash) enemyFlash = 1;
  }

  void triggerUltimate() {
    ultimate = UltimateFx(tilt: UltimateFx.randomTilt(_rng));
    hitStop = math.max(hitStop, 0.09);
    enemyRecoil = 1;
    if (allowFlash) enemyFlash = 1;
  }

  /// 重开一局时清空所有视觉状态。
  void reset() {
    gems.clear();
    dying.clear();
    particles.clear();
    rings.clear();
    labels.clear();
    floats.clear();
    ultimate = null;
    strikes.clear();
    hitStop = 0;
    enemyRecoil = 0;
    shake = 0;
    _shakePhase = 0;
    enemyFlash = 0;
    enemyLunge = 0;
    playerFlash = 0;
    dissolve = 0;
    dissolveTarget = 0;
  }
}
