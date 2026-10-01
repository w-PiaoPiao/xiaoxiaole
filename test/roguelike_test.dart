import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/roguelike.dart';
import 'package:gem_battle/engine/upgrades.dart';

/// 造一份只包含指定强化的档案（叠加层数由 map 值决定）。
PlayerProfile profileWith(Map<String, int> taken) => UpgradePool.profileFor(taken);

void main() {
  group('肉鸽数据结构', () {
    test('出厂档案的 effects 与 none 完全等价', () {
      expect(Campaign.player.effects, RoguelikeEffects.none);
      expect(Campaign.player.effects.isDefault, isTrue);
      expect(Campaign.player.boardRules, BoardRules.none);
    });

    test('copyWith 只动指定字段，值相等可用', () {
      const base = RoguelikeEffects.none;
      final changed = base.copyWith(critToShield: 0.5, selfDamagePerTurn: 5);
      expect(changed.critToShield, 0.5);
      expect(changed.selfDamagePerTurn, 5);
      expect(changed.damageMul, 1, reason: '其余字段保持默认');
      expect(changed, isNot(equals(base)));
      expect(changed.copyWith(critToShield: 0, selfDamagePerTurn: 0), base);
    });

    test('BoardRules 默认值就是现行规则', () {
      expect(BoardRules.none.isDefault, isTrue);
      expect(
        const BoardRules(prismExtraColors: 1).isDefault,
        isFalse,
      );
      expect(
        const BoardRules(prismExtraColors: 1).copyWith(prismExtraColors: 0),
        BoardRules.none,
      );
    });

    test('档案 copyWith 保留已有的 effects', () {
      final withPact = profileWith(const {'bloodPact': 1});
      final grown = withPact.copyWith(redDamage: withPact.redDamage + 7);
      expect(grown.effects, withPact.effects, reason: '普通成长不该动肉鸽层');
    });
  });

  group('稀有度与抽取', () {
    test('新增 12 条牌 = 9 稀有 + 3 传说，普通牌仍是 14 条', () {
      final byRarity = <UpgradeRarity, int>{};
      for (final u in UpgradePool.all) {
        byRarity[u.rarity] = (byRarity[u.rarity] ?? 0) + 1;
      }
      expect(byRarity[UpgradeRarity.common], 14);
      expect(byRarity[UpgradeRarity.rare], 9);
      expect(byRarity[UpgradeRarity.legendary], 3);
    });

    test('新牌都标记了正确的稀有度', () {
      const rareIds = [
        'overcrit', 'overflowGuard', 'thornGuard', 'rageEngine',
        'prismMaster', 'demolition', 'crossStrike', 'bloodPact', 'ascetic',
      ];
      const legendaryIds = ['plague', 'eternalCombo', 'moonBlessing'];
      for (final id in rareIds) {
        expect(UpgradePool.byId(id)!.rarity, UpgradeRarity.rare, reason: id);
      }
      for (final id in legendaryIds) {
        expect(UpgradePool.byId(id)!.rarity, UpgradeRarity.legendary, reason: id);
      }
      expect(UpgradePool.byId('bloodPact')!.isCostly, isTrue);
      expect(UpgradePool.byId('ascetic')!.isCostly, isTrue);
    });

    test('第 3 波起每 3 波保底一张稀有以上', () {
      // depth=2 即第 3 波：把保底波跑上 200 次，几乎每次三选一里都该有
      // 稀有（随机本身就能出，保底把"全普通"的缺口补上）。
      var withRare = 0;
      const rolls = 200;
      for (var seed = 0; seed < rolls; seed++) {
        final offer = UpgradePool.roll(
          profile: Campaign.player,
          taken: const {},
          rng: math.Random(seed),
          depth: 2,
          roguelike: true,
        );
        if (offer.any((u) => u.rarity != UpgradeRarity.common)) withRare++;
      }
      expect(withRare / rolls, greaterThan(0.8),
          reason: '保底波的三选一里稀有占比异常低（$withRare/$rolls）');
    });

    test('保底在稀有池抽空时退到传说', () {
      // 稀有牌全部叠满、传说门槛全部满足：候选池只剩普通 + 传说。
      // 这时的保底波不该出现"三张全普通"——只要池里还有质变牌，就该发出来。
      final taken = {
        for (final u in UpgradePool.all)
          if (u.rarity == UpgradeRarity.rare) u.id: u.maxStacks,
      };
      final ready = profileWith(const {'curse': 5, 'combo': 2, 'ultimate': 1});
      for (var seed = 0; seed < 200; seed++) {
        final offer = UpgradePool.roll(
          profile: ready,
          taken: taken,
          rng: math.Random(seed),
          depth: 2,
          roguelike: true,
        );
        expect(offer, isNotEmpty, reason: 'seed=$seed');
        expect(
          offer.any((u) => u.rarity != UpgradeRarity.common),
          isTrue,
          reason: '稀有池抽空后保底应退到传说（seed=$seed）',
        );
      }
    });

    test('前两波没有保底（铺底期允许全普通）', () {
      // depth=0：所有候选都是普通时（把稀有牌全部叠满排除掉），
      // 三张必须是普通——保底不该提前到开局。
      final taken = {
        for (final u in UpgradePool.all)
          if (u.rarity != UpgradeRarity.common) u.id: u.maxStacks,
      };
      final offer = UpgradePool.roll(
        profile: Campaign.player,
        taken: taken,
        rng: math.Random(7),
        depth: 0,
        roguelike: true,
      );
      expect(offer.every((u) => u.rarity == UpgradeRarity.common), isTrue);
    });

    test('稀有度权重随波次上升', () {
      double rareRatio(int depth) {
        var rare = 0;
        const rolls = 300;
        for (var seed = 0; seed < rolls; seed++) {
          final offer = UpgradePool.roll(
            profile: Campaign.player,
            taken: const {},
            rng: math.Random(seed * 7 + depth),
            depth: depth,
            roguelike: true,
          );
          if (offer.any((u) => u.rarity != UpgradeRarity.common)) rare++;
        }
        return rare / rolls;
      }

      expect(rareRatio(20), greaterThan(rareRatio(0)),
          reason: '走得越深，质变牌越该露面');
    });

    test('前置只决定出现与否：门槛以下的牌不进候选', () {
      // 「过量暴击」需要暴击率 ≥ 16%（锐锋两层）。
      for (var seed = 0; seed < 60; seed++) {
        final offer = UpgradePool.roll(
          profile: Campaign.player,
          taken: const {},
          rng: math.Random(seed),
          depth: 20,
          roguelike: true,
        );
        expect(offer.any((u) => u.id == 'overcrit'), isFalse,
            reason: '没有暴击率时不应出现（seed=$seed）');
      }
      final ready = profileWith(const {'crit': 2});
      var seen = false;
      for (var seed = 0; seed < 120 && !seen; seed++) {
        final offer = UpgradePool.roll(
          profile: ready,
          taken: const {},
          rng: math.Random(seed),
          depth: 20,
          roguelike: true,
        );
        seen = offer.any((u) => u.id == 'overcrit');
      }
      expect(seen, isTrue, reason: '满足门槛后这张牌应当能抽到');
    });
  });

  group('肉鸽在战斗里生效', () {
    final def = Campaign.levels[0].enemy;

    BattleState battleWith(PlayerProfile profile, {int? hp, int? rngSeed}) =>
        BattleState(
          def: def,
          levelIndex: 0,
          profile: profile,
          playerHp: hp,
          rng: math.Random(rngSeed ?? 1),
        );

    test('过量暴击：暴击伤害的 50% 结成护盾', () {
      final profile = profileWith(const {'crit': 20, 'overcrit': 1});
      var sawCrit = false;
      for (var i = 0; i < 40 && !sawCrit; i++) {
        final state = battleWith(profile, rngSeed: i);
        final events = state.applyClear({GemType.red: 3}, combo: 1);
        if (!events.any((e) => e.kind == CombatEventKind.crit)) continue;
        sawCrit = true;
        // 3 × 26 × 2.0（暴击）＝ 156，其中 50% 应当变成护盾。
        expect(def.maxHp - state.enemyHp, 156);
        expect(state.shield, 78);
      }
      expect(sawCrit, isTrue, reason: '40 次里该出暴击');
    });

    test('溢流护盾：治疗溢出上限的部分转为护盾', () {
      final profile = profileWith(const {'overflowGuard': 1});
      final state = battleWith(profile, hp: Campaign.player.maxHp - 10);
      // 5 颗绿 × 21 ＝ 105 点治疗，缺口只有 10 → 溢出 95，一半结成护盾。
      state.applyClear({GemType.green: 5}, combo: 1);
      expect(state.playerHp, Campaign.player.maxHp);
      expect(state.shield, 48);
    });

    test('荆棘壁垒：护盾扛下的伤害 30% 反弹', () {
      final profile = profileWith(const {'guard': 1, 'thornGuard': 1});
      final state = battleWith(profile);
      state.shield = state.profile.maxShield; // 300
      // 第一关敌人每 3 回合打 62：护盾全吃，反弹 round(62 × 0.3) = 19。
      for (var i = 0; i < def.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(state.playerHp, Campaign.player.maxHp, reason: '盾应该扛下全部伤害');
      expect(def.maxHp - state.enemyHp, 19);
    });

    test('过载引擎：溢出的怒气按 1:3 转为伤害', () {
      final profile = profileWith(const {'rage': 2, 'rageEngine': 1});
      final state = battleWith(profile);
      state.rage = state.profile.maxRage - 1; // 99
      // 2 颗黄 × 17（蓄能两层后）＝ 34 点怒气，只装得下 1 点
      // → 溢出 33 × 3 ＝ 99 伤害。
      state.applyClear({GemType.yellow: 2}, combo: 1);
      expect(state.rage, state.profile.maxRage);
      expect(def.maxHp - state.enemyHp, 99);
    });

    test('血契：全部伤害 +50%，每回合自损 5 点', () {
      final profile = profileWith(const {'bloodPact': 1});
      final state = battleWith(profile);
      state.applyClear({GemType.red: 3}, combo: 1);
      expect(def.maxHp - state.enemyHp, (3 * 26 * 1.5).round());

      state.endPlayerTurn();
      expect(state.playerHp, Campaign.player.maxHp - 5,
          reason: '回合开始时血契收息（第一关敌人本回合不出手）');
    });

    test('血契的自损可以致死', () {
      final profile = profileWith(const {'bloodPact': 1});
      final state = battleWith(profile, hp: 4);
      state.endPlayerTurn();
      expect(state.phase, BattlePhase.lost);
      expect(state.playerHp, 0);
      expect(state.enemyHp, def.maxHp, reason: '倒下后轮不到敌人出手');
    });

    test('苦修：红伤 ×1.9、暴击率 +10%、护盾获取归零', () {
      final profile = profileWith(const {'ascetic': 1});
      expect(profile.redDamage, (26 * 1.9).round());
      expect(profile.critChance, closeTo(0.10, 1e-9));

      final state = battleWith(profile);
      state.applyClear({GemType.blue: 3}, combo: 1);
      expect(state.shield, 0, reason: '代价：蓝宝石不再结盾');

      final plain = battleWith(Campaign.player);
      plain.applyClear({GemType.blue: 3}, combo: 1);
      expect(plain.shield, 3 * Campaign.player.blueShield);
    });

    test('苦修让所有护盾来源归零（溢流 / 暴击转盾也绕不过）', () {
      // 苦修 + 溢流护盾：治满后的溢出不再结成护盾。
      final healer = profileWith(const {'ascetic': 1, 'overflowGuard': 1});
      final overflowed = battleWith(healer, hp: Campaign.player.maxHp - 10);
      overflowed.applyClear({GemType.green: 5}, combo: 1);
      expect(overflowed.playerHp, Campaign.player.maxHp);
      expect(overflowed.shield, 0,
          reason: '「无法获得护盾」要覆盖溢流转盾这条路径');

      // 苦修自带 +10% 暴击，配一张锐锋（+8%）就够「过量暴击」的门槛。
      final critter = profileWith(const {'ascetic': 1, 'crit': 1, 'overcrit': 1});
      var sawCrit = false;
      for (var i = 0; i < 80 && !sawCrit; i++) {
        final state = battleWith(critter, rngSeed: i);
        final events = state.applyClear({GemType.red: 3}, combo: 1);
        if (!events.any((e) => e.kind == CombatEventKind.crit)) continue;
        sawCrit = true;
        expect(state.shield, 0,
            reason: '「无法获得护盾」要覆盖暴击转盾这条路径');
      }
      expect(sawCrit, isTrue, reason: '80 次里该出暴击');
    });

    test('瘟疫：易伤永续（每回合只掉一层）且每层强化宝石伤害 +18%', () {
      final profile = profileWith(const {'curse': 2, 'plague': 1});
      expect(profile.curseBonus, closeTo(0.20, 1e-9), reason: '前置门槛');

      final state = battleWith(profile);
      state.applyClear({GemType.purple: 3}, combo: 1);
      expect(state.curseStacks, 3);
      // 100 点强化宝石额外伤害 ×（1 + 0.18 × 3）＝ 154。
      state.applyClear({}, combo: 1, specialBonus: 100);
      expect(def.maxHp - state.enemyHp, 154);

      // 3 回合后对照组（无瘟疫）易伤已清零，瘟疫还剩 2 层。
      for (var i = 0; i < 3; i++) {
        state.endPlayerTurn();
      }
      expect(state.curseStacks, 2, reason: '每回合只腐烂一层');

      final plain = battleWith(profileWith(const {'curse': 2}));
      plain.applyClear({GemType.purple: 3}, combo: 1);
      for (var i = 0; i < 3; i++) {
        plain.endPlayerTurn();
      }
      expect(plain.curseStacks, 0);
    });

    test('永动连锁：连锁上限 5.0、起步倍率 +0.15', () {
      final profile = profileWith(const {'combo': 2, 'eternalCombo': 1});
      final state = battleWith(profile);
      expect(state.comboMultiplier(1), closeTo(1.15, 1e-9));
      expect(state.comboMultiplier(99), 5.0);
    });

    test('月华：必杀消耗 -40%、每回合自动 +12 怒气', () {
      final profile = profileWith(const {'ultimate': 1, 'moonBlessing': 1});
      final state = battleWith(profile);
      expect(state.ultimateCost, 60, reason: '100 × 0.6');

      state.rage = 90;
      expect(state.rageReady, isTrue, reason: '90 ≥ 60 就绪');
      final enemyHpBefore = state.enemyHp;
      state.castUltimate();
      expect(state.rage, 30, reason: '只扣实际消耗，不清零');
      expect(state.enemyHp, enemyHpBefore - 240, reason: '斩月·极一层后的额外伤害');

      // 第一关敌人每 3 回合才出手，第一回合的怒气不会被夺走。
      state.endPlayerTurn();
      expect(state.rage, 42);
    });
  });

  group('棋盘规则质变', () {
    // 27 = 第 3 行第 4 列，28 = 第 3 行第 5 列：都在棋盘中部，范围不会被边界裁掉。
    const a = 27;
    const b = 28;

    BoardEngine boardOf(Map<int, String> overlay) {
      final layout = <String>[];
      for (var y = 0; y < BoardEngine.rows; y++) {
        final line = StringBuffer();
        for (var x = 0; x < BoardEngine.cols; x++) {
          line.write(overlay[y * BoardEngine.cols + x] ?? 'Y.');
        }
        layout.add(line.toString());
      }
      return BoardEngine.fromLayout(layout, seed: 7);
    }

    Set<int> clearedOf(BoardEngine board, int from, int to, BoardRules rules) {
      board.swapCells(from, to);
      final steps = board.resolveSwap(from, to, rules: rules);
      expect(steps, isNotEmpty);
      return {for (final c in steps.first.cleared) c.index};
    }

    test('棱镜宗师：额外清除场上最多的一种颜色', () {
      // 交换后棱镜落在 b=(4,3)，单颗棱镜清的是**交换对象**的颜色——
      // 这是棱镜的既有设计，规则只在其上追加。底色黄、撒三颗互不相邻的
      // 蓝：默认规则动不了蓝，宗师把蓝一并带走。
      const blues = [0, 23, 45];
      final board = boardOf({
        for (final i in blues) i: 'B.',
        a: 'Rp',
      });
      final cleared = clearedOf(board, a, b, const BoardRules(prismExtraColors: 1));
      expect(cleared.length, BoardEngine.cols * BoardEngine.rows,
          reason: '黄(交换对象) + 蓝(场上最多的其他色) + 棱镜自己 = 全场');
      for (final i in blues) {
        expect(cleared.contains(i), isTrue, reason: '蓝宝石 $i 应被额外清掉');
      }

      final plain = boardOf({
        for (final i in blues) i: 'B.',
        a: 'Rp',
      });
      final plainCleared = clearedOf(plain, a, b, BoardRules.none);
      expect(plainCleared.length, 61, reason: '60 黄 + 棱镜自己，默认规则不碰蓝');
      for (final i in blues) {
        expect(plainCleared.contains(i), isFalse, reason: '蓝宝石 $i 不该被默认棱镜清掉');
      }
    });

    test('爆破工程：爆裂宝石范围 3x3 → 5x5', () {
      // 交换后爆裂落在 b=(4,3)：5x5 覆盖 x∈[2,6]、y∈[1,5]。
      final board = boardOf({a: 'Rb', b: 'Y.'});
      final cleared = clearedOf(board, a, b, const BoardRules(burstRadius: 2));
      expect(cleared.length, 25);
      expect(cleared.contains(BoardEngine.cols * 1 + 2), isTrue, reason: '左上角');
      expect(cleared.contains(BoardEngine.cols * 5 + 6), isTrue, reason: '右下角');

      final plain = boardOf({a: 'Rb', b: 'Y.'});
      expect(clearedOf(plain, a, b, BoardRules.none).length, 9, reason: '默认 3x3');
    });

    test('十字破空：破空宝石同时清除整行与整列', () {
      // 交换后破空落在 b=(4,3)：行 y=3 与列 x=4 一起清。
      final board = boardOf({a: 'Rh', b: 'Y.'});
      final cleared = clearedOf(board, a, b, BoardRules(lineBecomesCross: true));
      expect(cleared.length, 15, reason: '8 + 8 − 1 交叉点');
      expect(cleared.contains(4), isTrue, reason: '第 4 列');
      expect(cleared.contains(BoardEngine.cols * 3), isTrue, reason: '第 3 行');

      final plain = boardOf({a: 'Rh', b: 'Y.'});
      expect(clearedOf(plain, a, b, BoardRules.none).length, 8, reason: '默认只清一行');
    });

    test('组合技不被规则叠加：十字破空组合依旧 15 格', () {
      // 「十字破空」强化的是单颗破空；两颗破空的组合技已经自成十字，
      // 再叠一次只会让规则牌贬值。
      final board = boardOf({a: 'Rh', b: 'Rv'});
      final cleared = clearedOf(board, a, b, BoardRules(lineBecomesCross: true));
      expect(cleared.length, 15);
    });
  });
}
