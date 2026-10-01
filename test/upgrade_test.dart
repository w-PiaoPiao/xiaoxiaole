import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/roguelike.dart';
import 'package:gem_battle/engine/upgrades.dart';

import 'support/helpers.dart';

void main() {
  group('强化系统', () {
    test('没有强化时档案就是出厂数值', () {
      final base = profileWith(const {});
      expect(base.redDamage, Campaign.player.redDamage);
      expect(base.critChance, 0, reason: '基础档案不该自带暴击，否则伤害不可复现');
      expect(base.comboCap, 2.5);
      expect(base.specialPower, 1.0);
      expect(base.curseBonus, 0.12);
    });

    test('强化会叠加，且不污染全局默认档案', () {
      final before = Campaign.player.redDamage;
      final profile = profileWith(const {'blade': 3, 'guard': 2});
      expect(profile.redDamage, before + 21);
      expect(profile.blueShield, Campaign.player.blueShield + 12);
      expect(profile.maxShield, Campaign.player.maxShield + 100);
      expect(Campaign.player.redDamage, before, reason: '出厂的全局档案必须保持原样');
    });

    test('未知 id 会被忽略而不是抛异常', () {
      // 存档格式变化时不应让游戏崩掉。
      final profile = profileWith(const {'blade': 1, '不存在的强化': 9});
      expect(profile.redDamage, Campaign.player.redDamage + 7);
    });

    test('抽取不会发出已经叠满的强化', () {
      final taken = {'blade': 6}; // blade 的上限就是 6
      final profile = profileWith(taken);
      for (var seed = 0; seed < 40; seed++) {
        final offered = UpgradePool.roll(
          profile: profile,
          taken: taken,
          rng: math.Random(seed),
        );
        expect(offered.any((u) => u.id == 'blade'), isFalse);
      }
    });

    test('前置不满足的强化不会出现', () {
      // 「致命一击」只有在已经有暴击率时才有意义。
      for (var seed = 0; seed < 40; seed++) {
        final offered = UpgradePool.roll(
          profile: Campaign.player,
          taken: const {},
          rng: math.Random(seed),
        );
        expect(offered.any((u) => u.id == 'critDamage'), isFalse);
        expect(
          offered.map((u) => u.id).toSet().length,
          offered.length,
          reason: '同一次抽取不该出现重复的牌',
        );
      }
    });

    test('拿到暴击率之后，「致命一击」才进入牌池', () {
      final profile = profileWith(const {'crit': 1});
      var seen = false;
      for (var seed = 0; seed < 60 && !seen; seed++) {
        final offered = UpgradePool.roll(
          profile: profile,
          taken: const {'crit': 1},
          rng: math.Random(seed),
        );
        seen = offered.any((u) => u.id == 'critDamage');
      }
      expect(seen, isTrue, reason: '满足前置后这张牌应当能抽到');
    });

    test('每次抽取都给出三张不同的牌', () {
      for (var seed = 0; seed < 30; seed++) {
        final offered = UpgradePool.roll(
          profile: Campaign.player,
          taken: const {},
          rng: math.Random(seed),
        );
        expect(offered.length, 3);
        expect(offered.map((u) => u.id).toSet().length, 3);
      }
    });

    test('全部强化叠满后不再发牌，而不是空转', () {
      final taken = {for (final u in UpgradePool.all) u.id: u.maxStacks};
      final offered = UpgradePool.roll(
        profile: UpgradePool.profileFor(taken),
        taken: taken,
        rng: math.Random(1),
      );
      expect(offered, isEmpty);
    });

    test('每条强化的数值都真的落到了档案上', () {
      // 逐条验证 apply 有实际效果：写错字段（比如加了却不生效）会在这里被抓住。
      for (final upgrade in UpgradePool.all) {
        const before = Campaign.player;
        final after = upgrade.apply(before);
        final changed =
            before.redDamage != after.redDamage ||
            before.blueShield != after.blueShield ||
            before.greenHeal != after.greenHeal ||
            before.yellowRage != after.yellowRage ||
            before.maxShield != after.maxShield ||
            before.maxHp != after.maxHp ||
            before.ultimateBonusDamage != after.ultimateBonusDamage ||
            before.ultimateMultiplier != after.ultimateMultiplier ||
            before.critChance != after.critChance ||
            before.critMultiplier != after.critMultiplier ||
            before.comboCap != after.comboCap ||
            before.specialPower != after.specialPower ||
            before.curseBonus != after.curseBonus ||
            before.regenPerTurn != after.regenPerTurn ||
            before.damageReduction != after.damageReduction ||
            before.desperateBonus != after.desperateBonus ||
            // 肉鸽质变（无尽模式）写在 effects 里：这里只查"有没有变"，
            // 具体数值行为由 roguelike_test.dart 逐条把关。
            before.effects != after.effects;
        expect(changed, isTrue, reason: '${upgrade.name} 没有改变任何属性');
      }
    });

    test('战役模式（不开肉鸽层）只发普通牌', () {
      // 质变与代价是无尽模式的风景：战役一共只有五次选择，把血契这类
      // 代价牌混进去只会把线性成长搅乱。
      for (var seed = 0; seed < 40; seed++) {
        final offered = UpgradePool.roll(
          profile: Campaign.player,
          taken: const {},
          rng: math.Random(seed),
        );
        expect(
          offered.where((u) => u.rarity != UpgradeRarity.common),
          isEmpty,
          reason: 'seed=$seed 的战役抽取里混进了非普通牌',
        );
      }
    });
  });

  group('强化在战斗里生效', () {
    final def = Campaign.levels[0].enemy;

    BattleState battleWith(Map<String, int> taken, {int? hp}) => BattleState(
      def: def,
      levelIndex: 0,
      profile: profileWith(taken),
      playerHp: hp,
      rng: math.Random(1),
    );

    test('烈焰精通提高红宝石伤害', () {
      final state = battleWith(const {'blade': 2});
      state.applyClear({GemType.red: 3}, combo: 1);
      final expected = 3 * (Campaign.player.redDamage + 14);
      expect(def.maxHp - state.enemyHp, expected);
    });

    test('暴击按倍率放大伤害', () {
      // critChance 拉满 → 必定暴击，结果是确定的。
      final state = battleWith(const {'crit': 20});
      final events = state.applyClear({GemType.red: 3}, combo: 1);
      expect(events.any((e) => e.kind == CombatEventKind.crit), isTrue);
      final expected =
          (3 * Campaign.player.redDamage * state.profile.critMultiplier)
              .round();
      expect(def.maxHp - state.enemyHp, expected);
    });

    test('没有暴击强化时永远不暴击', () {
      final state = battleWith(const {});
      for (var i = 0; i < 30; i++) {
        final events = state.applyClear({GemType.red: 1}, combo: 1);
        expect(events.any((e) => e.kind == CombatEventKind.crit), isFalse);
      }
    });

    test('无尽连击抬高连锁倍率的上限', () {
      final plain = battleWith(const {});
      expect(plain.comboMultiplier(99), 2.5);
      final boosted = battleWith(const {'combo': 2});
      expect(boosted.comboMultiplier(99), closeTo(3.3, 1e-9));
    });

    test('破军放大强化宝石的额外伤害', () {
      final state = battleWith(const {'special': 2}); // +90% → x1.9
      state.applyClear({}, combo: 1, specialBonus: 100);
      expect(def.maxHp - state.enemyHp, 190);
    });

    test('深咒提高每层易伤的价值', () {
      final state = battleWith(const {'curse': 3});
      state.applyClear({GemType.purple: 2}, combo: 1);
      final before = state.enemyHp;
      state.applyClear({GemType.red: 3}, combo: 1);
      // 两层易伤，每层按档案里的 curseBonus 加成。
      final expected =
          (3 * Campaign.player.redDamage * (1 + state.profile.curseBonus * 2))
              .round();
      expect(before - state.enemyHp, expected);
    });

    test('回春在每个回合开始回血', () {
      final state = battleWith(const {'regen': 2}, hp: 100); // 每回合 +12
      state.endPlayerTurn();
      expect(state.playerHp, 112);
    });

    test('回春不会超过生命上限', () {
      final state = battleWith(const {'regen': 2});
      state.playerHp = state.profile.maxHp - 3;
      state.endPlayerTurn();
      expect(state.playerHp, state.profile.maxHp);
    });

    test('硬化减少受到的伤害', () {
      final plain = BattleState(def: def, levelIndex: 0, playerHp: 300);
      final hard = BattleState(
        def: def,
        levelIndex: 0,
        playerHp: 300,
        profile: profileWith(const {'harden': 5}), // 40% 减免
      );
      for (var i = 0; i < def.turnsPerAttack; i++) {
        plain.endPlayerTurn();
        hard.endPlayerTurn();
      }
      expect(hard.playerHp, greaterThan(plain.playerHp));
      expect(300 - hard.playerHp, ((300 - plain.playerHp) * 0.6).round());
    });

    test('狂骨只在残血时提高伤害', () {
      final healthy = battleWith(const {'desperate': 1});
      healthy.applyClear({GemType.red: 3}, combo: 1);
      expect(def.maxHp - healthy.enemyHp, 3 * Campaign.player.redDamage);

      final low = battleWith(const {'desperate': 1}, hp: 60); // 300 的 20%，低于逆境线
      expect(low.desperate, isTrue);
      low.applyClear({GemType.red: 3}, combo: 1);
      final expected =
          (3 * Campaign.player.redDamage * (1 + low.profile.desperateBonus))
              .round();
      expect(def.maxHp - low.enemyHp, expected);
    });

    test('生命上限强化会抬高开局血量与单次受击上限', () {
      final state = BattleState(
        def: def,
        levelIndex: 0,
        profile: profileWith(const {'vitality': 2}),
      );
      expect(state.playerHp, Campaign.player.maxHp + 80);
      expect(state.profile.maxHp, Campaign.player.maxHp + 80);
    });
  });

  group('强化宝石组合技', () {
    // 27 = 第 3 行第 4 列，29 = 第 3 行第 6 列；都在棋盘中部，
    // 任何方向的范围都不会被边界裁掉。
    const a = 27;
    const b = 28;

    /// 交换 [a]、[b] 并结算，返回第一步。
    CascadeStep swapAndResolve(BoardEngine board) {
      board.swapCells(a, b);
      final steps = board.resolveSwap(a, b);
      expect(steps, isNotEmpty, reason: '强化宝石交换后必须产生结算步骤');
      return steps.first;
    }

    Set<int> rowsOf(Iterable<int> indices) => {
      for (final i in indices) i ~/ BoardEngine.cols,
    };
    Set<int> colsOf(Iterable<int> indices) => {
      for (final i in indices) i % BoardEngine.cols,
    };

    test('破空 + 破空 = 十字，清掉整行与整列', () {
      final step = swapAndResolve(boardOf({a: 'Rh', b: 'Rv'}));
      // 十字 = 第 3 行（8 格）+ 第 4 列（8 格）− 交叉点重复的 1 格。
      expect(step.cleared.length, 15);
      expect(
        {for (final c in step.cleared) c.index}.contains(a),
        isTrue,
        reason: '十字中心',
      );
      expect(step.activations.single.comboName, '十字破空');
      expect(
        step.activations.single.bonus,
        greaterThan(80),
        reason: '组合技的额外伤害要高于单颗爆裂（80）',
      );
    });

    test('爆裂 + 爆裂 = 以落点为中心的 5x5', () {
      final step = swapAndResolve(boardOf({a: 'Rb', b: 'Rb'}));
      final index = {for (final c in step.cleared) c.index};
      expect(index.length, 25);
      // 27 = (3,3)，因此范围是 x∈[1,5]、y∈[1,5]。
      for (var i = 0; i < 25; i++) {
        expect(
          index.contains(BoardEngine.cols * (1 + i ~/ 5) + 1 + i % 5),
          isTrue,
        );
      }
      expect(step.activations.single.comboName, '连环爆裂');
    });

    test('破空 + 爆裂 = 三整行 + 三整列的粗十字', () {
      final step = swapAndResolve(boardOf({a: 'Rh', b: 'Rb'}));
      final index = {for (final c in step.cleared) c.index};
      // 3 行 × 8 + 3 列 × 8 − 9 个交叉点。
      expect(index.length, 39);
      for (final y in [2, 3, 4]) {
        for (var x = 0; x < BoardEngine.cols; x++) {
          expect(
            index.contains(BoardEngine.cols * y + x),
            isTrue,
            reason: '第 $y 行应整行清空',
          );
        }
      }
      for (final x in [2, 3, 4]) {
        for (var y = 0; y < BoardEngine.rows; y++) {
          expect(
            index.contains(BoardEngine.cols * y + x),
            isTrue,
            reason: '第 $x 列应整列清空',
          );
        }
      }
      expect(step.activations.single.comboName, '破空爆裂');
    });

    test('棱镜 + 棱镜 = 清空整个棋盘', () {
      final step = swapAndResolve(boardOf({a: 'Rp', b: 'Rp'}));
      expect(step.cleared.length, BoardEngine.cols * BoardEngine.rows);
      expect(step.activations.single.comboName, '万象归一');
    });

    test('棱镜 + 破空：全场同色会铺开成它们所在的每一行与每一列', () {
      final step = swapAndResolve(
        boardOf({
          a: 'Rp',
          b: 'Rh',
          // 同色的宝石零散分布，让"铺开"的效果真正体现出来。
          8: 'R.',
          23: 'R.',
          56: 'R.',
        }),
      );
      final index = [for (final c in step.cleared) c.index];
      // 同行同列被整片带走：远比一条线（8 格）或十字（15 格）大。
      expect(index.length, greaterThan(30));
      expect(rowsOf(index).length, greaterThanOrEqualTo(4));
      expect(colsOf(index).length, greaterThanOrEqualTo(3));
      expect(step.activations.single.comboName, '同色风暴');
    });

    test('棱镜 + 爆裂：范围包含全场同色，也包含以棱镜为中心的 5x5', () {
      final step = swapAndResolve(
        boardOf({a: 'Rp', b: 'Rb', 0: 'R.', 63: 'R.'}),
      );
      final index = {for (final c in step.cleared) c.index};
      expect(step.activations.single.comboName, '棱镜爆裂');
      expect(index.contains(0), isTrue, reason: '全场同色');
      expect(index.contains(63), isTrue, reason: '全场同色');
      // 交换后棱镜落在 b = (4,3)，5x5 覆盖 x∈[2,6]、y∈[1,5]。
      expect(
        index.contains(BoardEngine.cols * 1 + 2),
        isTrue,
        reason: '5x5 的左上角',
      );
      expect(
        index.contains(BoardEngine.cols * 5 + 6),
        isTrue,
        reason: '5x5 的右下角',
      );
      expect(index.length, greaterThan(25));
    });

    test('两种组合技的额外伤害都远高于两颗单独引爆之和', () {
      final cross = swapAndResolve(boardOf({a: 'Rh', b: 'Rv'}))
          .activations
          .single
          .bonus;
      final storm = swapAndResolve(boardOf({a: 'Rp', b: 'Rh'}))
          .activations
          .single
          .bonus;
      final void_ = swapAndResolve(boardOf({a: 'Rp', b: 'Rp'}))
          .activations
          .single
          .bonus;
      // 单颗破空 40、单颗棱镜 150：两颗各炸一次是 80 / 190。
      expect(cross, greaterThan(80));
      expect(storm, greaterThan(190));
      expect(void_, greaterThan(storm));
    });

    test('组合技仍然会引爆范围内的其他强化宝石', () {
      // 十字清掉的那一行上放一颗爆裂：它必须跟着一起炸。
      final board = boardOf({a: 'Rh', b: 'Rv', 29: 'Rb'});
      final step = swapAndResolve(board);
      expect(step.activations.length, 2, reason: '组合技 + 被波及的爆裂');
      expect(
        step.activations.map((x) => x.comboName).whereType<String>(),
        contains('十字破空'),
      );
      // 十字 120 + 单颗爆裂 80。
      expect(step.specialBonus, 200);
    });

    test('单颗强化宝石依旧是各自引爆，不算组合', () {
      final board = boardOf({a: 'Rh', b: 'Y.'});
      final step = swapAndResolve(board);
      // 交换后强化宝石落到 b，被它自己引爆。
      expect(step.activations.single.comboName, isNull);
      expect(step.activations.single.bonus, 40, reason: '破空的单颗额外伤害');
    });

    test('每一种组合技结算后棋盘都是满的、也没有残留的三连', () {
      for (final pair in const [
        ['Rh', 'Rv'],
        ['Rp', 'Rp'],
        ['Rp', 'Rh'],
        ['Rp', 'Rb'],
        ['Rb', 'Rb'],
        ['Rh', 'Rb'],
        ['Rv', 'Rb'],
      ]) {
        final board = boardOf({a: pair[0], b: pair[1]});
        board.swapCells(a, b);
        board.resolveSwap(a, b);
        expect(board.countHoles(), 0, reason: '${pair[0]}+${pair[1]} 结算后留下了空洞');
        expect(
          board.findMatches(),
          isEmpty,
          reason: '${pair[0]}+${pair[1]} 结算完不该剩下现成的三连',
        );
      }
    });
  });
}
