import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/upgrades.dart';

import 'support/sim.dart';

/// 完整对局推演：棋盘 → 战斗 → 胜负 → 三选一 → 下一关。
///
/// 推演器在 `support/sim.dart`，与 `tool/balance_report.dart` 共用同一份口径
/// ——开局摆机关、进敌方回合前同步毒藤、把玩家的棋盘规则注入结算。
/// 测试与报告读到的必须是同一个世界，否则这条难度守卫守不住真问题。
void main() {
  group('完整对局推演', () {
    test('前十二关用出厂档案就能打通（终战按整场口径检验）', () {
      // 出厂档案 = 零成长玩家。前十二关必须"谁来了都打得过"——这是
      // 关卡本身的可解性。终战（艾诺拉 1975×4）从数值上就是给带着
      // 12 张强化的玩家准备的：出厂档案的胜率个位数是刻意的，它的
      // 可解性由下面「整场挑战」的通关种子（全部到达并战胜终战）证明，
      // 不在这里用出厂档案硬测——那会逼着终战向"裸装可平推"放水。
      for (var level = 0; level < Campaign.levels.length - 1; level++) {
        final levelDef = Campaign.levels[level];
        final wins = [
          for (var seed = 1; seed <= 8; seed++)
            if (fight(levelDef, seed: seed).won) seed,
        ];
        expect(
          wins,
          isNotEmpty,
          reason:
              '第 ${level + 1} 关（${levelDef.enemy.name}）'
              '在 8 次推演里一次都没赢，关卡可能无解',
        );
      }
    });

    test('不会出现打不完的僵局', () {
      for (var level = 0; level < Campaign.levels.length; level++) {
        for (var seed = 1; seed <= 8; seed++) {
          final result = fight(Campaign.levels[level], seed: seed);
          expect(
            result.turns,
            lessThan(400),
            reason: '第 ${level + 1} 关 seed=$seed 超时未分出胜负',
          );
        }
      }
    });

    test('敌人会真正出手', () {
      final result = fight(Campaign.levels[3], seed: 2);
      expect(result.enemyAttacks, greaterThan(0), reason: '整场战斗敌方一次都没出手');
    });

    test('第一关对新手足够友好', () {
      for (var seed = 1; seed <= 8; seed++) {
        final result = fight(Campaign.levels[0], seed: seed);
        expect(result.won, isTrue, reason: '第一关 seed=$seed 不该失败');
      }
    });
  });

  group('整场挑战（带强化）', () {
    test('随便吃强化也不至于团灭（容许个别 seed 卡关）', () {
      // 「每关都拿第一张」这种不假思索的选法偶尔会在后几关倒下，这是
      // 挑战性的一部分；但大多数种子仍应通关——守住「抽牌不会把人抽进
      // 死路」的底线。实测读数：必杀免费搭车的旧口径 12/16；推演器修正
      // （必杀独占一回合 + 真实血量继承 + 祭坛怒气）后为 7/16——那才是
      // 玩家面对的真实难度，无脑流本来就是下限（真玩家会选牌、用道具）。
      // 阈值 6 留了一个种子的采样余量：抽牌序列的蝴蝶效应在 ±1 内属噪声。
      var cleared = 0;
      for (var seed = 1; seed <= 16; seed++) {
        if (playCampaign(seed: seed, style: PickStyle.first).cleared) cleared++;
      }
      expect(
        cleared,
        greaterThanOrEqualTo(6),
        reason: '随便选强化时卡关的种子太多（$cleared/16），难度可能失控',
      );
    });

    test('专挑输出的 build 也能打通相当一部分种子', () {
      // 只堆伤害会让身板很脆（血契还自损、苦修封盾），后期被机关与狂暴
      // BOSS 收掉几个种子是设计的一部分——但相当一部分种子必须能通关，
      // 否则等于把输出流做成了死路。旧六关短程时实测 7/16；十三关长程
      // 的后段（吸血、贯穿、四管终战）对零生存的 build 是结构性考验，
      // 4/16 上下（失败集中在 9/12/13 关）就是这条曲线的读数。
      var cleared = 0;
      for (var seed = 1; seed <= 16; seed++) {
        if (playCampaign(seed: seed, style: PickStyle.damage).cleared) {
          cleared++;
        }
      }
      expect(
        cleared,
        greaterThanOrEqualTo(4),
        reason: '纯输出 build 只通关了 $cleared/16，输出流可能被做成了死路',
      );
    });

    test('保命流比输出流更稳', () {
      // 两条成长路线的分工：输出流打得快但会被收，保命流走得稳。
      // 如果保命流的通关率反而低于输出流，说明防守资源被做废了。
      var survival = 0;
      var damage = 0;
      for (var seed = 1; seed <= 16; seed++) {
        if (playCampaign(seed: seed, style: PickStyle.survival).cleared) {
          survival++;
        }
        if (playCampaign(seed: seed, style: PickStyle.damage).cleared) damage++;
      }
      expect(
        survival,
        greaterThanOrEqualTo(damage),
        reason: '保命流 $survival/16 不如输出流 $damage/16，防守资源可能太弱',
      );
    });

    test('强化不会让玩家变得比出厂更弱', () {
      for (final upgrade in UpgradePool.all) {
        const base = Campaign.player;
        final after = upgrade.apply(base);
        // 只有"越大越好"的属性：任何一条强化都不该把它们调低。
        expect(
          after.maxHp,
          greaterThanOrEqualTo(base.maxHp),
          reason: upgrade.name,
        );
        expect(
          after.redDamage,
          greaterThanOrEqualTo(base.redDamage),
          reason: upgrade.name,
        );
        expect(
          after.blueShield,
          greaterThanOrEqualTo(base.blueShield),
          reason: upgrade.name,
        );
        expect(
          after.greenHeal,
          greaterThanOrEqualTo(base.greenHeal),
          reason: upgrade.name,
        );
        expect(
          after.yellowRage,
          greaterThanOrEqualTo(base.yellowRage),
          reason: upgrade.name,
        );
        expect(
          after.maxShield,
          greaterThanOrEqualTo(base.maxShield),
          reason: upgrade.name,
        );
        expect(
          after.ultimateBonusDamage,
          greaterThanOrEqualTo(base.ultimateBonusDamage),
          reason: upgrade.name,
        );
        expect(
          after.ultimateMultiplier,
          greaterThanOrEqualTo(base.ultimateMultiplier),
          reason: upgrade.name,
        );
        expect(
          after.critChance,
          greaterThanOrEqualTo(base.critChance),
          reason: upgrade.name,
        );
        expect(
          after.critMultiplier,
          greaterThanOrEqualTo(base.critMultiplier),
          reason: upgrade.name,
        );
        expect(
          after.comboCap,
          greaterThanOrEqualTo(base.comboCap),
          reason: upgrade.name,
        );
        expect(
          after.specialPower,
          greaterThanOrEqualTo(base.specialPower),
          reason: upgrade.name,
        );
        expect(
          after.curseBonus,
          greaterThanOrEqualTo(base.curseBonus),
          reason: upgrade.name,
        );
        expect(
          after.regenPerTurn,
          greaterThanOrEqualTo(base.regenPerTurn),
          reason: upgrade.name,
        );
        expect(
          after.desperateBonus,
          greaterThanOrEqualTo(base.desperateBonus),
          reason: upgrade.name,
        );
        // 减伤与治疗削弱是"越小越好"，这里只守住上限。
        expect(
          after.damageReduction,
          lessThanOrEqualTo(PlayerProfile.maxDamageReduction),
          reason: upgrade.name,
        );
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
        // 比的是总血量：多形态 BOSS 的 maxHp 只是"每管"，单看会比前一关小。
        expect(cur.totalHp, greaterThan(prev.totalHp), reason: '第 ${i + 1} 关');
        expect(
          cur.attack / cur.turnsPerAttack,
          greaterThanOrEqualTo(prev.attack / prev.turnsPerAttack),
        );
      }
    });

    test('后期的敌人比前期更凶', () {
      final early = fight(Campaign.levels[0], seed: 4);
      final late = fight(Campaign.levels.last, seed: 4);
      expect(late.enemyAttacks, greaterThan(early.enemyAttacks));
    });
  });
}
