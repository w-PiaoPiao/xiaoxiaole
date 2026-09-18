// ignore_for_file: avoid_print
//
// 数值平衡报告：用简单 AI 把每一关各推演若干次，打印胜率与平均回合数，
// 用来判断难度曲线是否合理。用法：dart run tool/balance_report.dart
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';

/// 推演风格。
enum Style {
  /// 会看情况防守的正常打法。
  balanced,

  /// 只顾输出的莽夫打法。
  berserk,
}

final _balanced = MoveAdvisor();
final _berserk = MoveAdvisor(conservative: false);

Map<String, dynamic> simulate(int levelIndex, {required int seed, required Style style}) {
  final level = Campaign.levels[levelIndex];
  final board = BoardEngine(seed: seed)..reset();
  final battle = BattleState(def: level.enemy, levelIndex: levelIndex);
  var turns = 0;
  const maxTurns = 400;

  while (!battle.isOver && turns < maxTurns) {
    final move = (style == Style.balanced ? _balanced : _berserk).suggest(board, battle);
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

  return {
    'won': battle.isWon,
    'lost': battle.phase == BattlePhase.lost,
    'turns': turns,
    'hp': battle.playerHp,
    'enemyHp': battle.enemyHp,
    'attacks': battle.attackCount,
  };
}

void main() {
  const seeds = 14;
  print('关卡 敌人        血量  正常:胜/负/僵  回合  我方残血     莽夫:胜/负  回合  莽夫残血  敌出手  正常局敌残');
  for (var level = 0; level < Campaign.levels.length; level++) {
    final def = Campaign.levels[level].enemy;
    var bw = 0, bl = 0, bt = 0, bturns = 0, bEnemyLeft = 0.0, bu = 0, bul = 0;
    var bHp = 0, bBerserkHp = 0, bTurns = 0, bAttacks = 0;
    for (var seed = 1; seed <= seeds; seed++) {
      final a = simulate(level, seed: seed, style: Style.balanced);
      if (a['won'] as bool) {
        bw++;
      } else if (a['lost'] as bool) {
        bl++;
      } else {
        bt++;
      }
      bturns += a['turns'] as int;
      bEnemyLeft += (a['enemyHp'] as int) / def.maxHp * 100;
      bHp += a['hp'] as int;

      final b = simulate(level, seed: seed, style: Style.berserk);
      if (b['won'] as bool) {
        bu++;
      } else {
        bul++;
      }
      bTurns += b['turns'] as int;
      bBerserkHp += b['hp'] as int;
      bAttacks += b['attacks'] as int;
    }
    print(
      '${(level + 1).toString().padRight(5)}'
      '${def.name.padRight(12)}'
      '${def.maxHp.toString().padRight(6)}'
      '${'$bw/$bl/$bt'.padRight(13)}'
      '${(bturns / seeds).toStringAsFixed(1).padRight(5)}'
      '${'${(bHp / seeds).round()}/300'.padRight(11)}'
      '${'$bu/$bul'.padRight(11)}'
      '${(bTurns / seeds).toStringAsFixed(1).padRight(6)}'
      '${'${(bBerserkHp / seeds).round()}/300'.padRight(9)}'
      '${(bAttacks / seeds).toStringAsFixed(1).padRight(9)}'
      '${(bEnemyLeft / seeds).toStringAsFixed(0)}%',
    );
  }
}
