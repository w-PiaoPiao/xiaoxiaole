import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/engine/upgrades.dart';

/// 「输出优先」的选牌集合（与 tool/balance_report.dart 的 damage 策略一致）。
const _endlessDamageIds = {
  'blade', 'crit', 'critDamage', 'special', 'combo', 'curse', 'desperate', 'ultimate',
  'bloodPact', 'ascetic', 'rageEngine',
  'crossStrike', 'demolition', 'prismMaster',
  'plague', 'eternalCombo', 'moonBlessing',
};

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
    ///
    /// 无尽模式启用肉鸽层：三选一按「输出优先」吃一条，跳过「苦修」这种
    /// 把护盾资源清零的陷阱牌——与 tool/balance_report.dart 的 damage 策略
    /// 同口径，波次窗口的校准数据也来自那份报告。
    int? simulateEndless({required int seed, int maxWave = 60}) {
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
          for (final step
              in board.resolveSwap(move.a, move.b, rules: profile.boardRules)) {
            battle.applyClear(step.counts, combo: step.combo, specialBonus: step.specialBonus);
          }
          if (battle.canCastUltimate) {
            battle.castUltimate();
            for (final step in board.resolveUltimate(
              board.index(BoardEngine.cols ~/ 2, BoardEngine.rows ~/ 2),
              rules: profile.boardRules,
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
        final offer = UpgradePool.roll(
          profile: profile,
          taken: taken,
          rng: rng,
          depth: wave - 1,
          roguelike: true,
        );
        if (offer.isNotEmpty) {
          final i = offer.indexWhere(
            (u) => _endlessDamageIds.contains(u.id) && u.id != 'ascetic',
          );
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
      return null;
    }

    test('前几波对新手足够友好', () {
      // 无尽模式没有强化铺垫，第一波必须稳赢。
      for (var seed = 1; seed <= 8; seed++) {
        final fallen = simulateEndless(seed: seed, maxWave: 40);
        expect(fallen, isNot(1), reason: '第 1 波不该倒下（seed=$seed）');
        expect(fallen, isNot(2), reason: '第 2 波不该倒下（seed=$seed）');
      }
    });

    test('强度最终会压过玩家，且肉鸽层让玩家走得更远', () {
      // 三个种子都该在 60 波内倒下：指数成长的敌人必须追上线性+质变的玩家。
      // 窗口按 balance_report 的 24 种子数据校准（damage 策略中位 17、
      // 基线 16）：中位明显低于 14 说明肉鸽层在拖后腿，超过 28 则说明
      // 敌人成长压不住了。
      final fallen = <int?>[
        for (final seed in [1, 2, 3]) simulateEndless(seed: seed),
      ];
      for (final wave in fallen) {
        expect(wave, isNotNull, reason: '有人打穿了 60 波，敌人成长太慢');
        expect(wave, greaterThan(3), reason: '但也不该死得太快');
      }
      final settled = fallen.whereType<int>().toList()..sort();
      final median = settled[1];
      expect(median, inExclusiveRange(13, 29),
          reason: '中位倒下波次 $median 偏离校准窗口 [14, 28]，'
              '肉鸽层的强度可能失衡');
      expect(settled.last, greaterThan(30),
          reason: '至少一个 build 应能走得很深——质变牌要把上限拉开');
    });
  });
}
