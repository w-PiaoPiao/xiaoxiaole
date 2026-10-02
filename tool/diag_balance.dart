// ignore_for_file: avoid_print
//
// 收支台账：把一局的**收入与支出**摊开看——玩家每回合拿到多少护盾/治疗、
// 敌人每回合打掉多少、各色宝石的消除量、必杀频率。用法：
//
//     dart run tool/diag_balance.dart
//
// 它回答的是 `balance_report.dart` 答不了的那类问题："为什么这一关没有压力"
// 只看胜率是看不出来的——前一版报告里前四关的终局残血是 96%~100%，而真实
// 原因是**敌人每回合的输出（19~61）低于玩家的续航（42~71）**，净收支全为
// 正，玩家在打木桩。这份台账把那一列"净"直接打出来，失衡一眼可见。
//
// 改关卡数值时的用法：先看「净」是不是正的（正 = 玩家在打木桩），再看
// 「续航/回合」——它决定敌人 DPS 要提到多少才能形成压力。
import 'dart:math' as math;

import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';

class Stats {
  int damageDealt = 0;
  int shieldGained = 0;
  int healed = 0;
  int hpLost = 0;
  int enemyAttacks = 0;
  int enemyDamage = 0;
  int enemyHealed = 0;
  int turns = 0;
  int ultimates = 0;
  final Map<GemType, int> cleared = {for (final t in GemType.values) t: 0};
}

Stats run(
  LevelDef level, {
  required int seed,
  PlayerProfile profile = Campaign.player,
  FightingStyle style = FightingStyle.balanced,
}) {
  final board = BoardEngine(seed: seed)..reset();
  for (final entry in level.obstacles.entries) {
    board.placeObstacles(entry.key, entry.value);
  }
  final battle = BattleState(
    def: level.enemy,
    levelIndex: level.index,
    profile: profile,
    rng: math.Random(seed),
  );
  final advisor = style == FightingStyle.balanced
      ? const MoveAdvisor()
      : const MoveAdvisor(conservative: false);
  final s = Stats();
  var turns = 0;

  while (!battle.isOver && turns < 400) {
    final move = advisor.suggest(board, battle);
    if (move == null) {
      board.shuffleBoard();
      turns++;
      continue;
    }
    board.swapCells(move.a, move.b);
    for (final step in board.resolveSwap(
      move.a,
      move.b,
      rules: profile.boardRules,
    )) {
      for (final e in battle.applyClear(
        step.counts,
        combo: step.combo,
        specialBonus: step.specialBonus,
      )) {
        _tally(s, e);
      }
      step.counts.forEach((t, n) => s.cleared[t] = s.cleared[t]! + n);
    }
    if (battle.canCastUltimate) {
      s.ultimates++;
      for (final e in battle.castUltimate()) {
        _tally(s, e);
      }
      for (final step in board.resolveUltimate(
        board.index(BoardEngine.cols ~/ 2, BoardEngine.rows ~/ 2),
        rules: profile.boardRules,
      )) {
        for (final e in battle.applyClear(
          step.counts,
          combo: step.combo,
          specialBonus: step.specialBonus,
          multiplier: profile.ultimateMultiplier,
        )) {
          _tally(s, e);
        }
        step.counts.forEach((t, n) => s.cleared[t] = s.cleared[t]! + n);
      }
    }
    battle.vineCount = board.countObstacles(ObstacleKind.vine);
    for (final e in battle.endPlayerTurn()) {
      _tally(s, e);
    }
    turns++;
  }
  s.turns = turns;
  return s;
}

enum FightingStyle { balanced, berserk }

void _tally(Stats s, CombatEvent e) {
  switch (e.kind) {
    case CombatEventKind.playerDamage:
      s.damageDealt += e.amount;
    case CombatEventKind.shieldGain:
      s.shieldGained += e.amount;
    case CombatEventKind.heal:
      s.healed += e.amount;
    case CombatEventKind.enemyAttack:
      s.enemyAttacks++;
      s.enemyDamage += e.amount;
    case CombatEventKind.enemyDrain:
      s.enemyHealed += e.amount;
    default:
      // 被敌方护盾吃掉的伤害不计入"实际掉血"，其余事件与本报告无关。
      break;
  }
}

void _row(String label, Stats s, EnemyDef def) {
  final t = s.turns == 0 ? 1 : s.turns;
  String col(int value, [int width = 4]) =>
      (value ~/ t).toString().padLeft(width);
  final sustain = s.shieldGained + s.healed;
  final c = s.cleared;
  print(
    '$label'
    '回合 ${s.turns.toString().padLeft(3)}'
    '  输出/回合 ${col(s.damageDealt)}'
    '  吃伤/回合 ${col(s.enemyDamage)}'
    '  续航/回合 ${col(sustain)}'
    '  净 ${col(sustain - s.enemyDamage, 5)}'
    '  必杀 ${s.ultimates.toString().padLeft(2)}'
    '  敌出手 ${s.enemyAttacks.toString().padLeft(2)}'
    '  每管血 ${def.maxHp}',
  );
  print(
    '${''.padRight(label.length)}'
    '消除: 红${c[GemType.red]} 蓝${c[GemType.blue]} 绿${c[GemType.green]} '
    '黄${c[GemType.yellow]} 紫${c[GemType.purple]}'
    '   紫/回合 ${(c[GemType.purple]! / t).toStringAsFixed(2)}',
  );
}

void main() {
  const seeds = 10;
  print('=== 战役六关（出厂档案，正常打法均值） ===');
  for (var i = 0; i < Campaign.levels.length; i++) {
    final level = Campaign.levels[i];
    final total = Stats();
    for (var seed = 1; seed <= seeds; seed++) {
      final s = run(level, seed: seed);
      total.damageDealt += s.damageDealt;
      total.shieldGained += s.shieldGained;
      total.healed += s.healed;
      total.enemyDamage += s.enemyDamage;
      total.enemyAttacks += s.enemyAttacks;
      total.turns += s.turns;
      total.ultimates += s.ultimates;
      s.cleared.forEach((k, v) => total.cleared[k] = total.cleared[k]! + v);
    }
    final scaled = Stats()
      ..damageDealt = total.damageDealt ~/ seeds
      ..shieldGained = total.shieldGained ~/ seeds
      ..healed = total.healed ~/ seeds
      ..enemyDamage = total.enemyDamage ~/ seeds
      ..enemyAttacks = total.enemyAttacks ~/ seeds
      ..turns = total.turns ~/ seeds
      ..ultimates = total.ultimates ~/ seeds;
    total.cleared.forEach((k, v) => (scaled.cleared)[k] = v ~/ seeds);
    print('');
    print('第 ${i + 1} 关 · ${level.enemy.name}'
        '（总血 ${level.enemy.totalHp}，${level.enemy.phases} 管，'
        '攻击 ${level.enemy.attack}/${level.enemy.turnsPerAttack} 回合）');
    _row('  正常', scaled, level.enemy);
  }

  print('');
  print('=== 无尽模式逐波（出厂档案，正常打法） ===');
  for (final wave in [1, 3, 5, 8, 10, 12, 15, 18, 20, 25, 30]) {
    final level = EndlessRoster.levelFor(wave);
    final total = Stats();
    for (var seed = 1; seed <= 6; seed++) {
      final s = run(level, seed: seed);
      total.damageDealt += s.damageDealt;
      total.shieldGained += s.shieldGained;
      total.healed += s.healed;
      total.enemyDamage += s.enemyDamage;
      total.enemyAttacks += s.enemyAttacks;
      total.turns += s.turns;
      total.ultimates += s.ultimates;
      s.cleared.forEach((k, v) => total.cleared[k] = total.cleared[k]! + v);
    }
    final scaled = Stats()
      ..damageDealt = total.damageDealt ~/ 6
      ..shieldGained = total.shieldGained ~/ 6
      ..healed = total.healed ~/ 6
      ..enemyDamage = total.enemyDamage ~/ 6
      ..enemyAttacks = total.enemyAttacks ~/ 6
      ..turns = total.turns ~/ 6
      ..ultimates = total.ultimates ~/ 6;
    total.cleared.forEach((k, v) => (scaled.cleared)[k] = v ~/ 6);
    print('');
    print('第 $wave 波 · ${level.enemy.name}'
        '（总血 ${level.enemy.totalHp}，${level.enemy.phases} 管，'
        '攻击 ${level.enemy.attack}/${level.enemy.turnsPerAttack} 回合）');
    _row('  正常', scaled, level.enemy);
  }
}
