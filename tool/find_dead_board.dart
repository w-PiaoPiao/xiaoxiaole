// ignore_for_file: avoid_print
//
// 开发辅助脚本：搜索一块「没有任何现成消除、也没有可行操作」的棋盘，用于固定测试用例。
//
// 5 色 8x8 的随机棋盘几乎不可能真的无路可走，所以这里枚举结构化的周期图案
// `cell(x, y) = palette[(x + k * y) % m]`，从中找出真正死掉的棋盘。
//
// 用法：dart run tool/find_dead_board.dart
import 'package:gem_battle/engine/board.dart';

const palette = ['R', 'B', 'G', 'Y', 'P'];

List<String>? buildPattern(int m, int k, int offset) {
  final rows = <String>[];
  for (var y = 0; y < BoardEngine.rows; y++) {
    final buffer = StringBuffer();
    for (var x = 0; x < BoardEngine.cols; x++) {
      final idx = (x + k * y + offset) % m;
      if (idx >= palette.length) return null;
      buffer.write(palette[idx]);
    }
    rows.add(buffer.toString());
  }
  return rows;
}

void main() {
  for (var m = 2; m <= 5; m++) {
    for (var k = 1; k < m; k++) {
      for (var offset = 0; offset < m; offset++) {
        final rows = buildPattern(m, k, offset);
        if (rows == null) continue;
        final board = BoardEngine.fromLayout(rows);
        if (board.findMatches().isEmpty && !board.hasValidMove()) {
          print('=== 死棋盘: m=$m k=$k offset=$offset ===');
          for (final row in rows) {
            print("  '$row',");
          }
          return;
        }
      }
    }
  }
  print('未找到');
}
