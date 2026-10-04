// 渲染性能基准：把各个 CustomPainter 在真实尺寸下逐帧绘制 + 光栅化，
// 测出每帧的毫秒数，用来量化优化前后的差异。
//
// 这台机器的测试环境是软件光栅化（SwiftShader 同源），CPU 侧的绘制与分配
// 开销会被放大，因此它适合做**相对比较**（优化前 vs 优化后），绝对值不代表
// 真机帧率——真机有 GPU，填充与模糊便宜得多，但对象分配与 Path 构建的
// 开销同样是实打实的。
//
// 用法：flutter test tool/perf_report.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/ui/battle_view.dart';
import 'package:gem_battle/ui/board_view.dart';
import 'package:gem_battle/ui/enemy_art.dart';
import 'package:gem_battle/ui/game_screen.dart';
import 'package:gem_battle/ui/paint_utils.dart';
import 'package:gem_battle/ui/palette.dart';

/// 逐帧绘制 [painter] 并光栅化，返回平均每帧耗时（毫秒）。
Future<double> _bench(
  WidgetTester tester,
  CustomPainter painter,
  Size size, {
  int frames = 120,
}) => _benchDraw(
  tester,
  (canvas, s) => painter.paint(canvas, s),
  size,
  frames: frames,
);

/// 逐帧执行一段绘制回调并光栅化，返回平均每帧耗时（毫秒）。
///
/// 单次测量受系统负载影响能差出 20%，所以跑 [rounds] 轮取每轮的最小值——
/// 最小值最接近"这台机器不被干扰时"的真实成本。
Future<double> _benchDraw(
  WidgetTester tester,
  void Function(Canvas canvas, Size size) draw,
  Size size, {
  int frames = 80,
  int rounds = 3,
}) async {
  final w = size.width.round().clamp(1, 4096);
  final h = size.height.round().clamp(1, 4096);
  var best = double.infinity;
  await tester.runAsync(() async {
    // 预热：让着色器与字体缓存就位。
    for (var i = 0; i < 10; i++) {
      final recorder = ui.PictureRecorder();
      draw(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      image.dispose();
      picture.dispose();
    }
    for (var round = 0; round < rounds; round++) {
      var totalUs = 0;
      for (var i = 0; i < frames; i++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final sw = Stopwatch()..start();
        draw(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(w, h);
        image.dispose();
        picture.dispose();
        sw.stop();
        totalUs += sw.elapsedMicroseconds;
      }
      best = math.min(best, totalUs / frames / 1000);
    }
  });
  return best;
}

/// 取某个视图下的第 [index] 个 CustomPaint 的画笔。
///
/// 棋盘与战斗区都拆成了「静态底层 + 动态层」两层，静态层只在尺寸/配色变化时
/// 重绘，因此每帧预算要看的是动态层——索引 1。
CustomPainter _painterOf(WidgetTester tester, Type view, {int index = 1}) {
  final finder = find.descendant(
    of: find.byType(view),
    matching: find.byType(CustomPaint),
  );
  final render = tester.renderObject<RenderCustomPaint>(finder.at(index));
  return render.painter!;
}

Size _painterSize(WidgetTester tester, Type view, {int index = 1}) {
  final finder = find.descendant(
    of: find.byType(view),
    matching: find.byType(CustomPaint),
  );
  return tester.renderObject<RenderCustomPaint>(finder.at(index)).size;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('渲染基准 · 字体 ${scale}x', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(411, 914);
      tester.view.padding = const FakeViewPadding(top: 47);
      tester.view.viewPadding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Palette.bgDeep,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: child!,
            ),
          ),
          home: const GameScreen(),
        ),
      );
      // 推进到棋盘落定、进入战斗。
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final board = _painterOf(tester, BoardView);
      final battle = _painterOf(tester, BattleView);
      final boardSize = _painterSize(tester, BoardView);
      final battleSize = _painterSize(tester, BattleView);

      final boardMs = await _bench(tester, board, boardSize);
      final battleMs = await _bench(tester, battle, battleSize);

      // 角色是战斗区里最重的一块：逐帧重建 5 个复杂 Path。
      final charH = battleSize.height * 0.82;
      final charSize = Size(charH * 0.78, charH);
      var clock = 0.0;
      final charMs = await _benchDraw(tester, (canvas, size) {
        clock += 1 / 60;
        EnemyArt.paint(
          canvas,
          size,
          const Color(0xFF57E0C8),
          EnemyPose(time: clock, hpRatio: 0.7),
        );
      }, charSize);

      // 飘字与连击标签：每次消除都会出现，走的是 TextPainter 布局 + 描边绘制。
      final floatMs = await _benchDraw(tester, (canvas, size) {
        drawText(
          canvas,
          '- 128',
          Offset(size.width * 0.5, size.height * 0.5),
          const TextStyle(
            color: Colors.red,
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
          alpha: 0.8,
          strokeColor: Colors.black,
          strokeWidth: 5,
        );
        drawText(
          canvas,
          '连击 x3',
          Offset(size.width * 0.5, size.height * 0.3),
          const TextStyle(
            color: Colors.amber,
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
          scale: 1.1,
          strokeColor: Colors.black,
          strokeWidth: 5,
        );
      }, const Size(411, 200));

      // ignore: avoid_print
      print(
        '[字体 ${scale}x] 棋盘 ${boardMs.toStringAsFixed(3)} ms/帧  '
        '战斗区 ${battleMs.toStringAsFixed(3)} ms/帧  '
        '（其中角色 ${charMs.toStringAsFixed(3)}）  '
        '飘字x2 ${floatMs.toStringAsFixed(3)} ms/帧  '
        '合计 ${(boardMs + battleMs + floatMs).toStringAsFixed(3)} ms/帧  '
        '(${boardSize.width.toInt()}x${boardSize.height.toInt()} + '
        '${battleSize.width.toInt()}x${battleSize.height.toInt()})',
      );

      // 不放硬阈值断言：这个环境是软件光栅化，绝对值不代表真机帧率，
      // 在慢机器上跑会假警报。它只负责把逐帧毫秒数打出来供**相对比较**
      // （优化前后各跑一次，看差值）——判断退化请用差值，不要用绝对值。
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
