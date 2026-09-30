import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/engine/upgrades.dart';

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

  group('整场挑战（带强化）', () {
    /// 从第一关连打到最后一关：每赢一关按 [pick] 吃一条强化，
    /// 生命按 GameScreen 的公式续到下一关。返回卡在哪一关（通关则返回 -1）。
    int playCampaign(int seed, int Function(List<Upgrade> offer) pick) {
      var profile = Campaign.player;
      var carryHp = profile.maxHp;
      final taken = <String, int>{};
      final rng = math.Random(seed * 7919);

      for (var level = 0; level < Campaign.levels.length; level++) {
        final board = BoardEngine(seed: seed * 31 + level)..reset();
        final battle = BattleState(
          def: Campaign.levels[level].enemy,
          levelIndex: level,
          profile: profile,
          playerHp: carryHp,
          rng: math.Random(seed + level),
        );
        var turns = 0;
        while (!battle.isOver && turns < 400) {
          final move = const MoveAdvisor().suggest(board, battle);
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
        if (!battle.isWon) return level;

        final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
        if (offer.isNotEmpty) {
          final choice = offer[pick(offer)];
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
      return -1;
    }

    test('随便吃强化也不至于团灭（容许个别 seed 卡关）', () {
      // 难度上调后「每关都拿第一张」这种不假思索的选法偶尔会在 5/6 关倒下，
      // 这是挑战性的一部分；但 6 个 seed 里大多数仍应通关——守住
      // 「抽牌不会把人抽进死路」的底线。
      var cleared = 0;
      for (var seed = 1; seed <= 6; seed++) {
        if (playCampaign(seed, (offer) => 0) == -1) cleared++;
      }
      expect(cleared, greaterThanOrEqualTo(5),
          reason: '随便选强化时有太多 seed 卡关（$cleared/6），难度可能失控');
    });

    test('专挑输出的 build 也能打穿全部六关', () {
      // 只堆伤害会让身板很脆，这条用例守着"极端 build 不至于卡死"。
      const damageIds = {'blade', 'crit', 'critDamage', 'special', 'combo', 'curse', 'desperate'};
      for (var seed = 1; seed <= 6; seed++) {
        expect(
          playCampaign(seed, (offer) {
            final i = offer.indexWhere((u) => damageIds.contains(u.id));
            return i >= 0 ? i : 0;
          }),
          -1,
          reason: '纯输出 build 在 seed=$seed 下卡关了',
        );
      }
    });

    test('强化不会让玩家变得比出厂更弱', () {
      for (final upgrade in UpgradePool.all) {
        final base = Campaign.player;
        final after = upgrade.apply(base);
        // 只有"越大越好"的属性：任何一条强化都不该把它们调低。
        expect(after.maxHp, greaterThanOrEqualTo(base.maxHp), reason: upgrade.name);
        expect(after.redDamage, greaterThanOrEqualTo(base.redDamage), reason: upgrade.name);
        expect(after.blueShield, greaterThanOrEqualTo(base.blueShield), reason: upgrade.name);
        expect(after.greenHeal, greaterThanOrEqualTo(base.greenHeal), reason: upgrade.name);
        expect(after.yellowRage, greaterThanOrEqualTo(base.yellowRage), reason: upgrade.name);
        expect(after.maxShield, greaterThanOrEqualTo(base.maxShield), reason: upgrade.name);
        expect(after.ultimateBonusDamage, greaterThanOrEqualTo(base.ultimateBonusDamage),
            reason: upgrade.name);
        expect(after.ultimateMultiplier, greaterThanOrEqualTo(base.ultimateMultiplier),
            reason: upgrade.name);
        expect(after.critChance, greaterThanOrEqualTo(base.critChance), reason: upgrade.name);
        expect(after.critMultiplier, greaterThanOrEqualTo(base.critMultiplier), reason: upgrade.name);
        expect(after.comboCap, greaterThanOrEqualTo(base.comboCap), reason: upgrade.name);
        expect(after.specialPower, greaterThanOrEqualTo(base.specialPower), reason: upgrade.name);
        expect(after.curseBonus, greaterThanOrEqualTo(base.curseBonus), reason: upgrade.name);
        expect(after.regenPerTurn, greaterThanOrEqualTo(base.regenPerTurn), reason: upgrade.name);
        expect(after.desperateBonus, greaterThanOrEqualTo(base.desperateBonus), reason: upgrade.name);
        // 减伤与治疗削弱是"越小越好"，这里只守住上限。
        expect(after.damageReduction, lessThanOrEqualTo(PlayerProfile.maxDamageReduction),
            reason: upgrade.name);
      }
    });

    test('减伤不会被任何叠法顶到完全免伤', () {
      final stacked = UpgradePool.profileFor(const {'harden': 99});
      expect(stacked.damageReduction, PlayerProfile.maxDamageReduction);
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
