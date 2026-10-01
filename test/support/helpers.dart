/// 测试通用的小工具：造档案、铺棋盘、挂机关。
///
/// 这些样板原本在 `roguelike_test` / `upgrade_test` / `obstacle_test` 里各存
/// 一份，改一处忘另一处就会出现"同一个棋盘在两个用例里表现不一样"。
library;

import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/upgrades.dart';

/// 造一份只包含指定强化的档案（叠加层数由 map 值决定）。
PlayerProfile profileWith(Map<String, int> taken) =>
    UpgradePool.profileFor(taken);

/// 铺一块 8x8 棋盘。
///
/// 每格两个字符（类型 `R/B/G/Y/P` + 强化标记 `.h/v/b/p`）。[overlay] 给出
/// 要覆盖的格子，其余格按 [fill] 铺——默认全黄（无现成三连，方便用例自己
/// 摆形状）。
BoardEngine boardOf(
  Map<int, String> overlay, {
  String Function(int index)? fill,
}) {
  final layout = <String>[];
  for (var y = 0; y < BoardEngine.rows; y++) {
    final line = StringBuffer();
    for (var x = 0; x < BoardEngine.cols; x++) {
      final index = y * BoardEngine.cols + x;
      line.write(overlay[index] ?? fill?.call(index) ?? 'Y.');
    }
    layout.add(line.toString());
  }
  return BoardEngine.fromLayout(layout, seed: 7);
}

/// 铺一块底色五彩的棋盘。
///
/// 有些用例需要"相邻两格颜色本来就不同"（例如验证被锁的宝石不能交换），
/// 全黄底会给不出这种对子。
BoardEngine boardOfMixed(Map<int, String> overlay) {
  const palette = ['R', 'B', 'G', 'Y', 'P'];
  return boardOf(
    overlay,
    fill: (index) {
      final x = index % BoardEngine.cols;
      final y = index ~/ BoardEngine.cols;
      return '${palette[(x + 2 * y) % palette.length]}.';
    },
  );
}

/// 给指定格附着机关（模拟关卡布置）。
void lockAt(BoardEngine board, int index, ObstacleKind kind) {
  board.cells[index]!.obstacle = kind;
}
