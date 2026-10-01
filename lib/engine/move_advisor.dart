import 'board.dart';
import 'battle.dart';
import 'gem.dart';

/// 一步操作建议。
class MoveSuggestion {
  final int a;
  final int b;

  /// 评分，越高越推荐。
  final double score;

  const MoveSuggestion(this.a, this.b, this.score);
}

/// 落子顾问：会推演每一个合法交换的后续连锁，按当前局势给出最值得走的一步。
///
/// 两个用途：给玩家「提示」，以及让自动化推演（数值平衡报告、回归测试）有对手。
class MoveAdvisor {
  /// 需要的宝石权重。
  final bool conservative;

  const MoveAdvisor({this.conservative = true});

  MoveSuggestion? suggest(BoardEngine board, BattleState battle) {
    if (battle.isOver) return null;

    // 局势判断
    final lethal = battle.playerHp - battle.shield <= battle.incomingDamage;
    final finishing = battle.enemyHpRatio < 0.08;
    final threatened = battle.turnsToAttack <= 1;
    final safe = battle.playerHpRatio > 0.6 && battle.shield > battle.incomingDamage;

    MoveSuggestion? best;

    for (var i = 0; i < board.cells.length; i++) {
      final x = i % BoardEngine.cols;
      final y = i ~/ BoardEngine.cols;
      for (final j in <int>[
        if (x + 1 < BoardEngine.cols) i + 1,
        if (y + 1 < BoardEngine.rows) i + BoardEngine.cols,
      ]) {
        if (!board.canSwap(i, j)) continue;

        final probe = board.clone();
        probe.swapCells(i, j);
        // 推演必须带上玩家的棋盘规则（棱镜多清一色、破空成十字……），
        // 否则提示的价值会被低估，顾问会漏掉真正的妙手。
        final steps = probe.resolveSwap(i, j, rules: battle.profile.boardRules);
        if (steps.isEmpty) continue;

        final counts = <GemType, int>{};
        var bonus = 0;
        for (final step in steps) {
          step.counts.forEach((type, n) => counts[type] = (counts[type] ?? 0) + n);
          bonus += step.specialBonus;
        }

        final score = _score(
          counts: counts,
          bonus: bonus,
          chain: steps.length,
          lethal: lethal,
          finishing: finishing,
          threatened: threatened,
          safe: safe,
        );
        if (best == null || score > best.score) {
          best = MoveSuggestion(i, j, score);
        }
      }
    }
    return best;
  }

  double _score({
    required Map<GemType, int> counts,
    required int bonus,
    required int chain,
    required bool lethal,
    required bool finishing,
    required bool threatened,
    required bool safe,
  }) {
    final red = (counts[GemType.red] ?? 0).toDouble();
    final blue = (counts[GemType.blue] ?? 0).toDouble();
    final green = (counts[GemType.green] ?? 0).toDouble();
    final yellow = (counts[GemType.yellow] ?? 0).toDouble();
    final purple = (counts[GemType.purple] ?? 0).toDouble();

    // 莽夫模式：完全不考虑防守，用来检验「不防守会不会死」。
    if (!conservative) {
      return red * 3 + bonus * 0.02 + chain * 0.5;
    }

    // 收尾阶段只认伤害，避免出现「打得死却一直补血」的僵局。
    if (finishing) {
      return red * 10 + bonus * 0.05 + chain;
    }

    // 会被一击打死：优先保命
    if (lethal) {
      return green * 7 + blue * 5 + red * 1.2 + bonus * 0.02;
    }

    final defenseWeight = threatened && !safe ? 1.0 : 0.28;
    var score = 0.0;
    score += red * 3.2;
    score += bonus * 0.02;
    score += blue * 3.0 * defenseWeight;
    score += green * 2.6 * defenseWeight;
    score += yellow * 1.4;
    score += purple * 1.7;
    score += chain * 1.5;
    return score;
  }
}
