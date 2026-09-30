// ignore_for_file: avoid_print
//
// 数值平衡报告：用简单 AI 把每一关各推演若干次，打印胜率与平均回合数，
// 用来判断难度曲线是否合理。用法：dart run tool/balance_report.dart
//
// 报告分两段：
//   1. 单关推演——出厂档案打一关，用来校准每一关本身的难度；
//   2. 整场挑战——从第一关连打到最后一关，每赢一关按策略吃掉一条强化。
//      这一段才是玩家真实经历的曲线：三选一让玩家越打越猛，
//      "最后一关还剩多少血"就是难度手感的直接读数。
import 'dart:math' as math;

import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/engine/upgrades.dart';

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

// ------------------------------------------------------------ 整场挑战推演

/// 选强化的策略。
enum PickStyle {
  /// 关关都拿第一张（等价于随机 build）。
  first,

  /// 只认输出：能加伤害就加伤害。
  damage,

  /// 怂一点：优先保命。
  survival,
}

const _damageIds = {'blade', 'crit', 'critDamage', 'special', 'combo', 'curse', 'desperate', 'ultimate'};
const _survivalIds = {'guard', 'harden', 'heal', 'regen', 'vitality'};

int _pickIndex(PickStyle style, List<Upgrade> offer) {
  switch (style) {
    case PickStyle.first:
      return 0;
    case PickStyle.damage:
      final i = offer.indexWhere((u) => _damageIds.contains(u.id));
      return i >= 0 ? i : 0;
    case PickStyle.survival:
      final i = offer.indexWhere((u) => _survivalIds.contains(u.id));
      return i >= 0 ? i : 0;
  }
}

/// 从第一关连打到最后一关，返回每一关的（回合数、残血、是否拿下）与最终 build。
Map<String, dynamic> simulateCampaign({
  required int seed,
  required PickStyle style,
}) {
  var profile = Campaign.player;
  var carryHp = profile.maxHp;
  final taken = <String, int>{};
  final rng = math.Random(seed * 7919);
  final perLevel = <Map<String, dynamic>>[];

  for (var level = 0; level < Campaign.levels.length; level++) {
    final def = Campaign.levels[level].enemy;
    final board = BoardEngine(seed: seed * 31 + level)..reset();
    final battle = BattleState(
      def: def,
      levelIndex: level,
      profile: profile,
      playerHp: carryHp,
      rng: math.Random(seed + level),
    );
    var turns = 0;
    while (!battle.isOver && turns < 400) {
      final move = _balanced.suggest(board, battle);
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
            multiplier: profile.ultimateMultiplier,
          );
        }
      }
      battle.endPlayerTurn();
      turns++;
    }

    perLevel.add({
      'turns': turns,
      'hp': battle.playerHp,
      'maxHp': profile.maxHp,
      'won': battle.isWon,
      'enemyLeft': battle.enemyHp,
    });
    if (!battle.isWon) {
      return {'cleared': false, 'failedAt': level, 'levels': perLevel, 'taken': taken};
    }

    // 过关奖励：抽三张、按策略吃一张，再按 GameScreen 的公式继承生命。
    final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
    if (offer.isNotEmpty) {
      final choice = offer[_pickIndex(style, offer)];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
    }
    carryHp = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        battle.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
  }
  return {'cleared': true, 'levels': perLevel, 'taken': taken, 'profile': profile};
}

void _campaignReport(int rounds) {
  print('');
  print('整场挑战（每赢一关吃一条强化，生命按 50% 保底续到下一关）');
  print('策略    通关  第1关残血  第3关残血  终关残血  终关回合  未过卡在  典型 build');
  for (final style in PickStyle.values) {
    var cleared = 0;
    var hp1 = 0.0, hp3 = 0.0, hpLast = 0.0, turnsLast = 0.0;
    final failedAt = <int>[];
    Map<String, int> sample = const {};
    for (var seed = 1; seed <= rounds; seed++) {
      final result = simulateCampaign(seed: seed, style: style);
      final levels = result['levels'] as List<Map<String, dynamic>>;
      if (result['cleared'] as bool) {
        cleared++;
        hpLast +=
            (levels[5]['hp'] as int) / (levels[5]['maxHp'] as int);
        turnsLast += levels[5]['turns'] as int;
      } else {
        failedAt.add((result['failedAt'] as int) + 1);
      }
      if (levels.isNotEmpty) {
        hp1 += (levels[0]['hp'] as int) / (levels[0]['maxHp'] as int);
      }
      if (levels.length > 2) {
        hp3 += (levels[2]['hp'] as int) / (levels[2]['maxHp'] as int);
      }
      sample = (result['taken'] as Map<String, int>);
    }
    final build = (sample.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((e) => '${e.key}x${e.value}')
        .join(' ');
    print(
      '${style.name.padRight(8)}'
      '${'$cleared/$rounds'.padRight(6)}'
      '${'${(hp1 / rounds * 100).round()}%'.padRight(11)}'
      '${'${(hp3 / rounds * 100).round()}%'.padRight(11)}'
      '${'${(hpLast / rounds * 100).round()}%'.padRight(10)}'
      '${(turnsLast / math.max(1, cleared)).toStringAsFixed(1).padRight(10)}'
      '${(failedAt.isEmpty ? '-' : failedAt.join(',')).padRight(10)}'
      '$build',
    );
  }
}

// ------------------------------------------------------------ 无尽模式推演

/// 打无尽模式直到倒下，返回倒下的波次（即通过波数 + 1）。
int simulateEndless({required int seed}) {
  var profile = Campaign.player;
  var carryHp = profile.maxHp;
  final taken = <String, int>{};
  final rng = math.Random(seed * 104729);

  for (var wave = 1; wave <= 60; wave++) {
    final board = BoardEngine(seed: seed * 31 + wave)..reset();
    final battle = BattleState(
      def: EndlessRoster.enemyFor(wave),
      levelIndex: wave - 1,
      profile: profile,
      playerHp: carryHp,
      rng: math.Random(seed + wave),
    );
    var turns = 0;
    while (!battle.isOver && turns < 400) {
      final move = _balanced.suggest(board, battle);
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
            multiplier: profile.ultimateMultiplier,
          );
        }
      }
      battle.endPlayerTurn();
      turns++;
    }
    if (!battle.isWon) return wave;

    final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
    if (offer.isNotEmpty) {
      // 输出优先：无尽模式里活命靠的是把敌人更快打死。
      final i = offer.indexWhere((u) => _damageIds.contains(u.id));
      final choice = offer[i >= 0 ? i : 0];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
    }
    carryHp = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        battle.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
  }
  return 61;
}

void _endlessReport(int rounds) {
  print('');
  print('无尽模式（输出优先的 build，每过一波吃一条强化）');
  final fallen = <int>[];
  for (var seed = 1; seed <= rounds; seed++) {
    fallen.add(simulateEndless(seed: seed));
  }
  fallen.sort();
  final best = fallen.last - 1;
  final median = fallen[rounds ~/ 2] - 1;
  final worst = fallen.first - 1;
  print('种子数 $rounds · 最差 $worst 波 · 中位 $median 波 · 最佳 $best 波');
  print('各局通过波数: ${fallen.map((w) => w - 1).join(', ')}');
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

  _campaignReport(10);
  _endlessReport(8);
}
