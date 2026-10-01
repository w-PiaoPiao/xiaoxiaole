import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/levels.dart';

import 'support/sim.dart';

/// 无尽模式的推演守卫。
///
/// 推演器在 `support/sim.dart`，与 `tool/balance_report.dart` 共用同一份口径：
/// **开局按波次摆机关、进敌方回合前同步毒藤、注入玩家的棋盘规则**。
/// 这一条以前只在报告里做，测试那份漏掉了机关——守卫守住的世界比玩家
/// 真正面对的世界简单，机关带来的难度回归它抓不到。
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
        for (var wave = 1; wave <= 6; wave++)
          EndlessRoster.enemyFor(wave).archetype,
      ];
      expect(
        firstCycle,
        Campaign.levels.map((l) => l.enemy.archetype).toList(),
      );
      // 第二个循环从头再来，但强度已经抬上去了。
      expect(
        EndlessRoster.enemyFor(7).archetype,
        EndlessRoster.enemyFor(1).archetype,
      );
      expect(
        EndlessRoster.enemyFor(7).maxHp,
        greaterThan(EndlessRoster.enemyFor(6).maxHp),
      );
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
    test('前两波对新手足够友好', () {
      // 只跑到第 3 波就停：这条用例只关心"开头别劝退新手"。
      for (var seed = 1; seed <= 8; seed++) {
        final fallen = playEndless(seed: seed, maxWave: 3).fallenWave;
        expect(fallen, greaterThan(2), reason: '前两波不该倒下（seed=$seed）');
      }
    });

    test('强度最终会压过玩家，且肉鸽层让玩家走得更远', () {
      // 12 个种子的中位通过波数，按 tool/balance_report.dart 的 24 种子数据
      // 校准（含机关口径：中位 20.5、p25 14、p75 39，观测范围 11~55）。
      //
      // 种子之间的方差很大，所以这里守的是**数量级失衡**：中位掉到 12 以下
      // 说明肉鸽层在拖后腿，涨到 36 以上说明敌人成长压不住了。
      final fallen = [
        for (final seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
          playEndless(seed: seed).fallenWave,
      ];
      for (final wave in fallen) {
        expect(
          wave,
          lessThanOrEqualTo(60),
          reason: '有人打穿了 60 波，敌人成长太慢（当前观测上界约 55 波）',
        );
        expect(wave, greaterThan(3), reason: '但也不该死得太快');
      }
      final cleared = [for (final wave in fallen) wave - 1]..sort();
      final median = (cleared[5] + cleared[6]) / 2;
      expect(
        median,
        inInclusiveRange(12, 36),
        reason:
            '中位通过波数 $median 偏离校准窗口 [12, 36]，'
            '肉鸽层的强度可能失衡',
      );
      expect(
        cleared.last,
        greaterThan(30),
        reason: '至少一个 build 应能走得很深——质变牌要把上限拉开',
      );
    });
  });
}
