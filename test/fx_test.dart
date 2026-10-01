// 特效控制器的行为测试：这些状态直接决定"画面上有没有东西在动"，
// 出问题时表现就是"棋盘卡住不动"或者"白白每帧重绘"。
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/ui/fx.dart';
import 'package:gem_battle/ui/palette.dart';

/// 造一颗位于 [index] 的普通宝石快照。
GemSnapshot _snap(int index, int id) => GemSnapshot(
  index: index,
  gemId: id,
  type: GemType.red,
  special: SpecialKind.none,
);

void main() {
  test('一次清掉几十颗时粒子数量有上限', () {
    // 组合技（棱镜 + 棱镜、同色风暴）能一次清掉三四十颗。每颗都炸满的话
    // 一帧要画近三百个圆，再加上命中定格把粒子留得更久，峰值还会更高。
    // 这里守住"清得越多、每颗分到的粒子越少"这条预算规则。
    const total = 39;
    final fx = FxController();
    fx.applySnapshot([for (var i = 0; i < total; i++) _snap(i, i + 1)]);
    fx.beginClear([
      for (var i = 0; i < total; i++)
        ClearedGem(
          index: i,
          gemId: i + 1,
          type: GemType.red,
          special: SpecialKind.none,
        ),
    ]);
    expect(
      fx.particles.length,
      lessThanOrEqualTo(total * 3),
      reason: '清 39 颗时每颗的粒子数应当被压到 3 个',
    );
    expect(fx.particles, isNotEmpty, reason: '但也不能一颗都不炸');

    // 小规模消除仍然按每颗 7 个粒子，手感不变。
    final small = FxController();
    small.applySnapshot([for (var i = 0; i < 3; i++) _snap(i, i + 1)]);
    small.beginClear([
      for (var i = 0; i < 3; i++)
        ClearedGem(
          index: i,
          gemId: i + 1,
          type: GemType.red,
          special: SpecialKind.none,
        ),
    ]);
    expect(small.particles.length, 21);
  });

  test('落定后棋盘不再重绘，动画期间逐帧重绘', () {
    final fx = FxController();
    var pings = 0;
    fx.boardRepaint.addListener(() => pings++);

    // 空棋盘：第一帧会把初始状态画出来，之后必须彻底安静。
    for (var i = 0; i < 30; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, lessThanOrEqualTo(1), reason: '棋盘静止时不该逐帧重绘');

    // 让宝石动起来：每一帧都应该触发重绘。
    fx.applySnapshot(
      [
        const GemSnapshot(
          index: 0,
          gemId: 1,
          type: GemType.red,
          special: SpecialKind.none,
        ),
      ],
      spawnStartY: const {1: -2},
      fallDuration: 0.4,
    );
    pings = 0;
    for (var i = 0; i < 12; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, greaterThanOrEqualTo(11), reason: '宝石下落时必须逐帧重绘');

    // 等它彻底落定，再开始数：之后最多补画一帧，其余帧必须安静。
    for (var i = 0; i < 60; i++) {
      fx.tick(1 / 60);
    }
    expect(fx.gems.values.every((g) => !g.moving), isTrue, reason: '宝石应当已经落定');
    pings = 0;
    for (var i = 0; i < 90; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, lessThanOrEqualTo(1), reason: '落定后只允许补画最后一帧');
  });

  test('选中脉冲期间保持逐帧重绘', () {
    final fx = FxController();
    var pings = 0;
    fx.boardRepaint.addListener(() => pings++);
    fx.boardPulse = true;
    for (var i = 0; i < 10; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, 10);
  });

  test('粒子与消散动画结束后停止重绘', () {
    final fx = FxController();
    fx.beginClear(const [
      ClearedGem(
        index: 0,
        gemId: 1,
        type: GemType.blue,
        special: SpecialKind.none,
      ),
    ]);
    var pings = 0;
    fx.boardRepaint.addListener(() => pings++);

    // 动画期间必须逐帧重绘（碎屑要真的在动）。
    for (var i = 0; i < 6; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, greaterThanOrEqualTo(5), reason: '粒子活着的时候棋盘要跟着动');

    // 等粒子与消散全部结束，再开始数：之后最多补画最后一帧。
    for (var i = 0; i < 120; i++) {
      fx.tick(1 / 60);
    }
    expect(fx.particles, isEmpty);
    expect(fx.dying, isEmpty);
    pings = 0;
    for (var i = 0; i < 60; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, lessThanOrEqualTo(1), reason: '粒子与消散结束后不该继续逐帧重绘');
  });

  test('「减少动态效果」下棱镜停转，棋盘回到静止不重绘', () {
    final fx = FxController();
    // 棱镜的彩色环一直在转：只要它在场，棋盘就必须逐帧重绘。
    fx.applySnapshot(const [
      GemSnapshot(
        index: 0,
        gemId: 1,
        type: GemType.red,
        special: SpecialKind.prism,
      ),
    ]);
    for (var i = 0; i < 90; i++) {
      fx.tick(1 / 60); // 先让它落定
    }

    var pings = 0;
    fx.boardRepaint.addListener(() => pings++);
    for (var i = 0; i < 30; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, greaterThan(25), reason: '彩色环在转，棋盘应当逐帧重绘');

    // 打开「减少动态效果」：环停下来，棋盘不该再逐帧重绘。
    fx.reducedMotion = true;
    for (var i = 0; i < 3; i++) {
      fx.tick(1 / 60); // 让状态切换的那几帧过去
    }
    pings = 0;
    for (var i = 0; i < 30; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, lessThanOrEqualTo(1), reason: '环停了，棋盘就该安静下来');
  });

  test('战斗区：正常模式逐帧重绘，「减少动态效果」下安静下来', () {
    final fx = FxController();
    var pings = 0;
    fx.battleRepaint.addListener(() => pings++);

    for (var i = 0; i < 20; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, greaterThanOrEqualTo(20), reason: '浮尘与角色摆动是持续动画，战斗区本来就该逐帧重绘');

    fx.reducedMotion = true;
    for (var i = 0; i < 3; i++) {
      fx.tick(1 / 60); // 让模式切换的那几帧过去
    }
    pings = 0;
    for (var i = 0; i < 30; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, lessThanOrEqualTo(1), reason: '没有动画时战斗区应当安静下来');

    // 一旦真的有动画（飘字），立刻恢复逐帧重绘。
    fx.addFloat('+10', Palette.hpPlayer);
    pings = 0;
    for (var i = 0; i < 10; i++) {
      fx.tick(1 / 60);
    }
    expect(pings, greaterThanOrEqualTo(9), reason: '飘字期间必须逐帧重绘');
  });

  test('震屏偏移真的会动，且归零后完全静止', () {
    final fx = FxController();
    expect(fx.shakeOffset, Offset.zero, reason: '没受击时不应该有偏移');

    fx.shakeBy(20);
    var moved = false;
    final first = fx.shakeOffset;
    for (var i = 0; i < 5; i++) {
      fx.tick(1 / 60);
      if (fx.shakeOffset != first) moved = true;
    }
    expect(moved, isTrue, reason: '震屏期间偏移必须逐帧变化，否则等于没有震');

    // 衰减到 0 之后偏移归零。
    for (var i = 0; i < 120; i++) {
      fx.tick(1 / 60);
    }
    expect(fx.shake, 0);
    expect(fx.shakeOffset, Offset.zero);
  });

  test('关掉震屏后 shakeBy 不再产生偏移', () {
    final fx = FxController()..allowShake = false;
    fx.shakeBy(30);
    expect(fx.shake, 0);
    expect(fx.shakeOffset, Offset.zero);
  });
}
