import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/engine/upgrades.dart';

void main() {
  group('无尽模式 · BOSS 生成', () {
    test('同一波次永远生成同一个 BOSS（确定性）', () {
      for (var wave = 1; wave <= 30; wave++) {
        final a = EndlessRoster.enemyFor(wave);
        final b = EndlessRoster.enemyFor(wave);
        expect(a.name, b.name);
        expect(a.maxHp, b.maxHp);
        expect(a.attack, b.attack);
        expect(a.shieldRegen, b.shieldRegen);
        expect(a.drainRatio, b.drainRatio);
        expect(a.rageDrain, b.rageDrain);
      }
    });

    test('波次越高越强：血量与攻击单调递增', () {
      for (var wave = 2; wave <= 30; wave++) {
        final prev = EndlessRoster.enemyFor(wave - 1);
        final cur = EndlessRoster.enemyFor(wave);
        expect(cur.maxHp, greaterThan(prev.maxHp), reason: '第 $wave 波');
        expect(cur.attack, greaterThan(prev.attack), reason: '第 $wave 波');
      }
    });

    test('原型按战役六战轮换登场', () {
      final firstCycle = [
        for (var wave = 1; wave <= 6; wave++) EndlessRoster.enemyFor(wave).archetype,
      ];
      expect(firstCycle, Campaign.levels.map((l) => l.enemy.archetype).toList());
      // 第二个循环从头再来，但强度已经抬上去了。
      expect(EndlessRoster.enemyFor(7).archetype, EndlessRoster.enemyFor(1).archetype);
      expect(EndlessRoster.enemyFor(7).maxHp,
          greaterThan(EndlessRoster.enemyFor(6).maxHp));
    });

    test('阶位前缀随波次出现', () {
      expect(EndlessRoster.enemyFor(1).name, '迷雾鬼火');
      expect(EndlessRoster.enemyFor(6).name, '终焉之影');
      expect(EndlessRoster.enemyFor(7).name, startsWith('重铸·'));
      expect(EndlessRoster.enemyFor(13).name, startsWith('灾变·'));
      expect(EndlessRoster.enemyFor(19).name, startsWith('终焉·'));
    });

    test('精英词条按台阶逐波增加且逐条生效', () {
      expect(EndlessRoster.modifierCount(3), 0);
      expect(EndlessRoster.modifierCount(4), 1);
      expect(EndlessRoster.modifierCount(7), 2);
      expect(EndlessRoster.modifierCount(16), 5, reason: '封顶 5 条');

      final w1 = EndlessRoster.enemyFor(1);
      final w4 = EndlessRoster.enemyFor(4);
      // 第 4 波的第一条词条是「坚壁」（护盾再生）。
      expect(w4.shieldRegen, greaterThan(w1.shieldRegen));

      // 词条逐条叠加：波次越高，同时带上的机制越多。汲魂词条让后期的
      // BOSS 会夺走怒气——这是「能力增强」而不只是「数字变大」的证明。
      final w16 = EndlessRoster.enemyFor(16);
      expect(w16.rageDrain, greaterThan(0));
      expect(w16.drainRatio, greaterThan(0));
      expect(w16.enrageAt, greaterThan(0));
    });

    test('levelFor 提供波次包装', () {
      final level = EndlessRoster.levelFor(5);
      expect(level.index, 4);
      expect(level.name, '第 5 波');
      expect(level.enemy.maxHp, EndlessRoster.enemyFor(5).maxHp);
    });
  });

  group('无尽模式 · 推演', () {
    /// 用落子顾问打无尽模式，返回倒下的波次（一直活着就返回 null）。
    int? simulateEndless({required int seed, int maxWave = 40}) {
      var profile = Campaign.player;
      var carryHp = profile.maxHp;
      final taken = <String, int>{};
      final rng = math.Random(seed * 104729);

      for (var wave = 1; wave <= maxWave; wave++) {
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
        if (!battle.isWon) return wave;
        expect(turns, lessThan(400), reason: '第 $wave 波超时未分出胜负');

        // 每过一波发三选一，按「输出优先」吃一条——这是无尽模式的真实玩法。
        final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
        if (offer.isNotEmpty) {
          final choice = offer.first;
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
      return null;
    }

    test('前几波对新手足够友好', () {
      // 无尽模式没有强化铺垫，第一波必须稳赢。
      for (var seed = 1; seed <= 8; seed++) {
        final fallen = simulateEndless(seed: seed);
        expect(fallen, isNot(1), reason: '第 1 波不该倒下（seed=$seed）');
        expect(fallen, isNot(2), reason: '第 2 波不该倒下（seed=$seed）');
      }
    });

    test('强度最终会压过玩家（跑不死的不叫无尽模式）', () {
      // 三个种子都不该撑过 40 波：指数成长的敌人必须追上线性成长的玩家。
      for (final seed in [1, 2, 3]) {
        final fallen = simulateEndless(seed: seed);
        expect(fallen, isNotNull, reason: 'seed=$seed 打穿了 40 波，敌人成长太慢');
        expect(fallen, greaterThan(3), reason: '但也不该死得太快');
      }
    });
  });
}
