import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/ui/board_view.dart';
import 'package:gem_battle/ui/fx.dart';

/// 棋盘的手势判定：这里守的是「拖动方向以按下点为原点」这条规则。
///
/// 曾经的做法是拿**格子中心**当原点算方向，于是手指按在格子边缘按下时，
/// 这个初始偏移会被算进方向判定——垂直拖可能被判成水平换，而交换一旦
/// 合法就直接结算，玩家没有撤销的机会。
void main() {
  // 格子取 100 像素：pan 的起步阈值是 kTouchSlop * 2 = 36，位移必须大于它
  // 才会进入拖动；同时又要小于一格，才不会被 onPanStart 判定成"从另一格
  // 开始拖"。两个约束之间需要足够的余量。
  const cell = 100.0;
  const nudge = 45.0;

  /// 棋盘在视口里的左上角。手势 API 收的是全局坐标，而用例里描述的都是
  /// 棋盘内的位置，这里统一换算。
  late Offset boardOrigin;

  /// 铺一块 8x8 的棋盘，返回记录交换请求的列表。
  Future<List<List<int>>> pumpBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final swaps = <List<int>>[];
    final board = BoardEngine(seed: 7)..reset();
    final fx = FxController();
    addTearDown(fx.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cell * BoardEngine.cols,
            height: cell * BoardEngine.rows,
            child: BoardView(
              board: board,
              fx: fx,
              selected: null,
              onSelect: (_) {},
              onSwapRequest: (a, b) => swaps.add([a, b]),
            ),
          ),
        ),
      ),
    ));
    boardOrigin = tester.getTopLeft(find.byType(BoardView));
    return swaps;
  }

  /// 从棋盘内的 [start] 按下并拖动 [delta] 后松手。
  ///
  /// 分几段移动，而不是一次到位：真实手指会产生一串 move 事件，而一次性
  /// 移动到位会让识别器在"已经跨过半个格子"之后才开始拖动。
  Future<void> drag(WidgetTester tester, Offset start, Offset delta) async {
    const steps = 6;
    final gesture = await tester.startGesture(boardOrigin + start);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // 第 3 行第 1 列（下标 16）的中心、右缘与下缘，供用例复用。
  const center16 = Offset(cell * 0.5, cell * 2.5);

  testWidgets('从格子中心向上拖 → 与上一格交换', (tester) async {
    final swaps = await pumpBoard(tester);
    await drag(tester, center16, const Offset(0, -nudge));

    expect(swaps, hasLength(1));
    expect(swaps.single, [16, 8]);
  });

  testWidgets('从格子中心向右拖 → 与右侧一格交换', (tester) async {
    final swaps = await pumpBoard(tester);
    await drag(tester, center16, const Offset(nudge, 0));

    expect(swaps, hasLength(1));
    expect(swaps.single, [16, 17]);
  });

  testWidgets('按住格子右缘向上拖，仍然判成纵向交换', (tester) async {
    final swaps = await pumpBoard(tester);
    // 按下点压在格子最右侧：以格子中心为原点时，(48, -45) 的水平分量更大，
    // 会被误判成"向右换"。
    final start = Offset(center16.dx + cell * 0.48, center16.dy);
    await drag(tester, start, const Offset(0, -nudge));

    expect(swaps, hasLength(1), reason: '应该发生一次交换');
    expect(swaps.single, [16, 8], reason: '方向由"按下点 → 当前点"决定，是纵向');
  });

  testWidgets('按住格子下缘向左拖，仍然判成横向交换', (tester) async {
    final swaps = await pumpBoard(tester);
    // 下标 17（第 3 行第 2 列），向左拖不会越出棋盘；按下点压在这一格下缘。
    final start = Offset(cell * 1.5, cell * 2.5 + cell * 0.48);
    await drag(tester, start, const Offset(-nudge, 0));

    expect(swaps, hasLength(1));
    expect(swaps.single, [17, 16], reason: '方向由"按下点 → 当前点"决定，是横向');
  });

  testWidgets('拖出棋盘边界时不发起交换', (tester) async {
    final swaps = await pumpBoard(tester);
    // 下标 0 在最左上角，向上拖没有可交换的目标。
    await drag(tester, const Offset(cell * 0.5, cell * 0.5), const Offset(0, -nudge));

    expect(swaps, isEmpty);
  });
}
