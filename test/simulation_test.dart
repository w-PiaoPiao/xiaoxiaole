import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';

/// 一次完整对局的结果。
class SimResult {
  final bool won;
  final bool lost;
  final int turns;
  final int playerHp;
  final int enemyHp;
  final int enemyAttacks;

  const SimResult({
    required this.won,
    required this.lost,
    required this.turns,
    required this.playerHp,
    required this.enemyHp,
    required this.enemyAttacks,
  });
}

/// 用落子顾问完整推演一关，跑通「棋盘 → 战斗 → 胜负」整条链路。
///
/// [reckless] 为 true 时只追求输出、完全不防守，用来检验「不防守会不会付出代价」。
SimResult simulateLevel(
  int levelIndex, {
  required int seed,
  bool reckless = false,
  int maxTurns = 400,
}) {
  final level = Campaign.levels[levelIndex];
  final board = BoardEngine(seed: seed)..reset();
  final battle = BattleState(def: level.enemy, levelIndex: levelIndex);
  final advisor = MoveAdvisor(conservative: !reckless);
  var turns = 0;

  while (!battle.isOver && turns < maxTurns) {
    final move = advisor.suggest(board, battle);
    if (move == null) {
      board.shuffleBoard();
      turns++;
      continue;
    }

    board.swapCells(move.a, move.b);
    for (final step in board.resolveSwap(move.a, move.b)) {
      battle.applyClear(step.counts, combo: step.combo, specialBonus: step.specialBonus);
    }

    if (battle.canCastUltimate) {
      battle.castUltimate();
      for (final step in board.resolveUltimate(
        board.index(BoardEngine.cols ~/ 2, BoardEngine.rows ~/ 2),
      )) {
        battle.applyClear(
          step.counts,
          combo: step.combo,
          specialBonus: step.specialBonus,
          multiplier: Campaign.player.ultimateMultiplier,
        );
      }
    }

    battle.endPlayerTurn();
    turns++;
  }

  return SimResult(
    won: battle.isWon,
    lost: battle.phase == BattlePhase.lost,
    turns: turns,
    playerHp: battle.playerHp,
    enemyHp: battle.enemyHp,
    enemyAttacks: battle.attackCount,
  );
}

void main() {
  group('完整对局推演', () {
    test('六个关卡都可以被打通', () {
      for (var level = 0; level < Campaign.levels.length; level++) {
        final wins = [
          for (var seed = 1; seed <= 8; seed++)
            if (simulateLevel(level, seed: seed).won) seed,
        ];
        expect(wins, isNotEmpty,
            reason: '第 ${level + 1} 关（${Campaign.levels[level].enemy.name}）'
                '在 8 次推演里一次都没赢，关卡可能无解');
      }
    });

    test('不会出现打不完的僵局', () {
      for (var level = 0; level < Campaign.levels.length; level++) {
        for (var seed = 1; seed <= 8; seed++) {
          final result = simulateLevel(level, seed: seed);
          expect(result.turns, lessThan(400),
              reason: '第 ${level + 1} 关 seed=$seed 超时未分出胜负');
        }
      }
    });

    test('敌人会真正出手', () {
      final result = simulateLevel(3, seed: 2);
      expect(result.enemyAttacks, greaterThan(0), reason: '整场战斗敌方一次都没出手');
    });

    test('第一关对新手足够友好', () {
      for (var seed = 1; seed <= 8; seed++) {
        final result = simulateLevel(0, seed: seed);
        expect(result.won, isTrue, reason: '第一关 seed=$seed 不该失败');
      }
    });
  });

  group('难度曲线', () {
    test('敌人血量与威胁逐关递增', () {
      for (var i = 1; i < Campaign.levels.length; i++) {
        final prev = Campaign.levels[i - 1].enemy;
        final cur = Campaign.levels[i].enemy;
        expect(cur.maxHp, greaterThan(prev.maxHp));
        expect(cur.attack / cur.turnsPerAttack,
            greaterThanOrEqualTo(prev.attack / prev.turnsPerAttack));
      }
    });

    test('后期的敌人比前期更凶', () {
      final early = simulateLevel(0, seed: 4);
      final late = simulateLevel(Campaign.levels.length - 1, seed: 4);
      expect(late.enemyAttacks, greaterThan(early.enemyAttacks));
    });
  });
}
