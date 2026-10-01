import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';

/// 生成一个保证没有任何三连的底棋盘：`cell(x, y) = palette[(x + 2y) % 5]`。
/// 横向每格颜色都不同，纵向每次下移颜色位移 2，因此永远凑不出三连。
List<String> blankLayout() {
  const palette = ['R', 'B', 'G', 'Y', 'P'];
  return [
    for (var y = 0; y < BoardEngine.rows; y++)
      [for (var x = 0; x < BoardEngine.cols; x++) palette[(x + 2 * y) % 5]]
          .join(),
  ];
}

/// 在底棋盘上按坐标涂色，写法比手写整行清晰得多。
List<String> layoutWith(Map<int, String> patches) {
  final grid = [for (final row in blankLayout()) row.split('')];
  patches.forEach((index, color) {
    grid[index ~/ BoardEngine.cols][index % BoardEngine.cols] = color;
  });
  return [for (final row in grid) row.join()];
}

int ix(int x, int y) => y * BoardEngine.cols + x;

int countColor(BoardEngine board, GemType type) =>
    board.cells.where((g) => g?.type == type).length;

void main() {
  group('初始棋盘', () {
    test('不会出现现成的三连，并且至少有一步可走', () {
      for (var seed = 0; seed < 25; seed++) {
        final board = BoardEngine(seed: seed)..reset();
        expect(board.findMatches(), isEmpty, reason: 'seed=$seed 不应有现成消除');
        expect(board.hasValidMove(), isTrue, reason: 'seed=$seed 应有可行操作');
        expect(
          board.cells.where((g) => g == null),
          isEmpty,
          reason: '初始棋盘不应有空洞',
        );
      }
    });
  });

  group('匹配检测', () {
    test('识别横向三连', () {
      final board = BoardEngine.fromLayout(
        layoutWith({ix(0, 0): 'R', ix(1, 0): 'R', ix(2, 0): 'R'}),
      );
      final matches = board.findMatches();
      expect(matches.length, 1);
      expect(matches.single.type, GemType.red);
      expect(matches.single.indices.length, 3);
      expect(matches.single.hasH, isTrue);
      expect(matches.single.hasV, isFalse);
      expect(matches.single.spawn, SpecialKind.none);
    });

    test('识别纵向三连', () {
      final board = BoardEngine.fromLayout(
        layoutWith({ix(0, 0): 'R', ix(0, 1): 'R', ix(0, 2): 'R'}),
      );
      final matches = board.findMatches();
      expect(matches.length, 1);
      expect(matches.single.hasV, isTrue);
      expect(matches.single.hasH, isFalse);
      expect(matches.single.indices.length, 3);
    });

    test('横向四连会生成横向强化宝石', () {
      final board = BoardEngine.fromLayout(
        layoutWith({
          ix(0, 0): 'R',
          ix(1, 0): 'R',
          ix(2, 0): 'R',
          ix(3, 0): 'R',
        }),
      );
      final matches = board.findMatches();
      expect(matches.length, 1);
      expect(matches.single.maxRun, 4);
      expect(matches.single.spawn, SpecialKind.lineH);
    });

    test('纵向四连会生成纵向强化宝石', () {
      final board = BoardEngine.fromLayout(
        layoutWith({
          ix(0, 0): 'R',
          ix(0, 1): 'R',
          ix(0, 2): 'R',
          ix(0, 3): 'R',
        }),
      );
      expect(board.findMatches().single.spawn, SpecialKind.lineV);
    });

    test('五连会生成棱镜', () {
      final board = BoardEngine.fromLayout(
        layoutWith({
          ix(0, 0): 'R',
          ix(1, 0): 'R',
          ix(2, 0): 'R',
          ix(3, 0): 'R',
          ix(4, 0): 'R',
          ix(5, 0): 'Y',
        }),
      );
      final matches = board.findMatches();
      expect(matches.length, 1);
      expect(matches.single.maxRun, 5);
      expect(matches.single.spawn, SpecialKind.prism);
    });

    test('L 形会合并成一组并生成爆裂宝石', () {
      final board = BoardEngine.fromLayout(
        layoutWith({
          ix(0, 0): 'R',
          ix(1, 0): 'R',
          ix(2, 0): 'R',
          ix(0, 1): 'R',
          ix(0, 2): 'R',
        }),
      );
      final matches = board.findMatches();
      expect(matches.length, 1, reason: 'L 形应合并为一组');
      expect(matches.single.indices.length, 5);
      expect(matches.single.hasH, isTrue);
      expect(matches.single.hasV, isTrue);
      expect(matches.single.spawn, SpecialKind.burst);
    });
  });

  group('交换与结算', () {
    /// 底棋盘上构造一步「蓝色三连」：交换 (2,0) 与 (2,1) 后第 0 行变成 BBB。
    BoardEngine swapBoard() => BoardEngine.fromLayout(
      layoutWith({ix(0, 0): 'B', ix(1, 0): 'B', ix(2, 0): 'R', ix(2, 1): 'B'}),
    );

    test('能形成消除的相邻交换是合法的，不相邻则非法', () {
      final board = swapBoard();
      expect(board.canSwap(ix(2, 0), ix(2, 1)), isTrue);
      expect(board.canSwap(ix(0, 0), ix(7, 7)), isFalse, reason: '不相邻');
      expect(
        board.canSwap(ix(0, 0), ix(1, 0)),
        isFalse,
        reason: '交换后无法形成消除，应判定非法',
      );
    });

    test('交换后结算出正确的消除数量', () {
      final board = swapBoard();
      final a = ix(2, 0), b = ix(2, 1);
      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);

      expect(steps, isNotEmpty);
      expect(steps.first.combo, 1);
      expect(steps.first.counts[GemType.blue], 3);
      expect(steps.first.cleared.length, 3);
    });

    test('消除后上方宝石下落并补满棋盘', () {
      final board = swapBoard();
      final a = ix(2, 0), b = ix(2, 1);
      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);

      expect(board.cells.where((g) => g == null), isEmpty, reason: '结算后棋盘应补满');
      expect(steps.last.snapshot.length, BoardEngine.cols * BoardEngine.rows);
    });

    test('连锁序号依次递增', () {
      final board = BoardEngine(seed: 7)..reset();
      // 找一个合法交换并结算，验证 combo 从 1 开始连续递增。
      var found = false;
      for (var i = 0; i < board.cells.length && !found; i++) {
        final x = i % BoardEngine.cols, y = i ~/ BoardEngine.cols;
        for (final j in [
          if (x + 1 < BoardEngine.cols) i + 1,
          if (y + 1 < BoardEngine.rows) i + BoardEngine.cols,
        ]) {
          if (!board.canSwap(i, j)) continue;
          board.swapCells(i, j);
          final steps = board.resolveSwap(i, j);
          for (var k = 0; k < steps.length; k++) {
            expect(steps[k].combo, k + 1);
          }
          expect(steps.length, greaterThanOrEqualTo(1));
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: '随机棋盘上应能找到合法交换');
    });
  });

  group('强化宝石', () {
    test('交换横线宝石会引爆整行', () {
      final board = BoardEngine.fromLayout(blankLayout());
      board.cells[ix(3, 3)] = Gem(
        id: 9001,
        type: GemType.red,
        special: SpecialKind.lineH,
      );
      final a = ix(3, 3), b = ix(4, 3);
      expect(board.canSwap(a, b), isTrue);

      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);

      expect(steps.first.activations.single.kind, SpecialKind.lineH);
      expect(
        steps.first.cleared.length,
        BoardEngine.cols,
        reason: '整行 8 格全部清除',
      );
      expect(steps.first.counts[GemType.red], 2, reason: '该行只有 2 颗是红色');
    });

    test('交换爆裂宝石会清除 3x3', () {
      final board = BoardEngine.fromLayout(blankLayout());
      board.cells[ix(3, 3)] = Gem(
        id: 9002,
        type: GemType.blue,
        special: SpecialKind.burst,
      );
      final a = ix(3, 3), b = ix(4, 3);

      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);

      expect(steps.first.activations.single.kind, SpecialKind.burst);
      expect(steps.first.cleared.length, 9, reason: '3x3 共 9 格');
    });

    test('棱镜与普通宝石交换会清除全场同色', () {
      final board = BoardEngine.fromLayout(blankLayout());
      board.cells[ix(0, 0)] = Gem(
        id: 9003,
        type: GemType.red,
        special: SpecialKind.prism,
      );
      final greenBefore = countColor(board, GemType.green);
      expect(greenBefore, greaterThan(3));

      final a = ix(0, 0), b = ix(0, 1); // (0,1) 是绿色
      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);

      expect(steps.first.activations.single.kind, SpecialKind.prism);
      expect(
        steps.first.counts[GemType.green],
        greenBefore,
        reason: '棱镜应清除全场所有绿色宝石',
      );
    });

    test('必杀技十字清除', () {
      final board = BoardEngine.fromLayout(blankLayout());
      final steps = board.resolveUltimate(ix(4, 4));
      expect(
        steps.first.cleared.length,
        BoardEngine.cols + BoardEngine.rows - 1,
      );
    });
  });

  group('可行性与洗牌', () {
    /// 三色周期图案 `cell(x, y) = 'RBG'[(x + y) % 3]`：任何相邻交换都凑不出三连。
    /// （5 色 8x8 的随机棋盘几乎不可能真的无路可走，所以这里用结构化图案来验证判定逻辑。）
    List<String> deadLayout() {
      const colors = ['R', 'B', 'G'];
      return [
        for (var y = 0; y < BoardEngine.rows; y++)
          [for (var x = 0; x < BoardEngine.cols; x++) colors[(x + y) % 3]]
              .join(),
      ];
    }

    test('识别出无路可走的棋盘', () {
      final board = BoardEngine.fromLayout(deadLayout());
      expect(board.findMatches(), isEmpty);
      expect(board.hasValidMove(), isFalse);
    });

    test('洗牌后恢复成可玩状态', () {
      final board = BoardEngine.fromLayout(deadLayout());
      board.shuffleBoard();
      expect(board.findMatches(), isEmpty);
      expect(board.hasValidMove(), isTrue);
      expect(board.cells.where((g) => g == null), isEmpty);
    });
  });
}
