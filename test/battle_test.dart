import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';

BattleState newBattle(int level) =>
    BattleState(def: Campaign.levels[level].enemy, levelIndex: level);

void main() {
  final def = Campaign.levels[0].enemy;

  group('宝石效果', () {
    test('红色宝石按基础伤害与连击倍率扣血', () {
      final state = newBattle(0);
      state.applyClear({GemType.red: 3}, combo: 1);
      expect(state.enemyHp, def.maxHp - 3 * Campaign.player.redDamage);

      final state2 = newBattle(0);
      state2.applyClear({GemType.red: 3}, combo: 2);
      final expected = (3 * Campaign.player.redDamage * 1.25).round();
      expect(state2.enemyHp, def.maxHp - expected);
    });

    test('连击倍率有上限', () {
      final state = newBattle(0);
      state.applyClear({GemType.red: 1}, combo: 99);
      final capped = (Campaign.player.redDamage * 2.5).round();
      expect(state.enemyHp, def.maxHp - capped);
    });

    test('蓝色宝石积累护盾且不超过上限', () {
      final state = newBattle(0);
      state.applyClear({GemType.blue: 3}, combo: 1);
      expect(state.shield, 3 * Campaign.player.blueShield);

      state.applyClear({GemType.blue: 40}, combo: 1);
      expect(state.shield, Campaign.player.maxShield);
    });

    test('绿色宝石治疗且不超过最大生命', () {
      final hurt = BattleState(def: def, levelIndex: 0, playerHp: 100);
      hurt.applyClear({GemType.green: 3}, combo: 1);
      expect(hurt.playerHp, 100 + 3 * Campaign.player.greenHeal);

      hurt.applyClear({GemType.green: 40}, combo: 1);
      expect(hurt.playerHp, Campaign.player.maxHp);
    });

    test('治疗被削弱时回复量减半', () {
      final state = BattleState(def: def, levelIndex: 0, playerHp: 100);
      state.healBlockTurns = 2;
      state.applyClear({GemType.green: 4}, combo: 1);
      final full = 4 * Campaign.player.greenHeal;
      expect(state.playerHp, 100 + (full - (full * 0.5).round()));
    });

    test('黄色宝石积累怒气且不超过上限', () {
      final state = newBattle(0);
      state.applyClear({GemType.yellow: 3}, combo: 1);
      expect(state.rage, 3 * Campaign.player.yellowRage);
      expect(state.rageReady, isFalse);

      state.applyClear({GemType.yellow: 30}, combo: 1);
      expect(state.rage, Campaign.player.maxRage);
      expect(state.rageReady, isTrue);
    });

    test('紫色宝石施加易伤并提高后续伤害', () {
      final state = newBattle(0);
      state.applyClear({GemType.purple: 2}, combo: 1);
      expect(state.curseStacks, 2);
      expect(state.curseTurns, 3);

      final before = state.enemyHp;
      state.applyClear({GemType.red: 3}, combo: 1);
      final expected = (3 * Campaign.player.redDamage * 1.24).round();
      expect(before - state.enemyHp, expected);
    });

    test('易伤层数有上限', () {
      final state = newBattle(0);
      state.applyClear({GemType.purple: 99}, combo: 1);
      expect(state.curseStacks, Campaign.player.maxCurseStacks);
    });

    test('强化宝石额外伤害会单独结算', () {
      final state = newBattle(0);
      final events = state.applyClear(
        {GemType.red: 3},
        combo: 1,
        specialBonus: 80,
      );
      expect(events.any((e) => e.kind == CombatEventKind.special), isTrue);
      expect(state.enemyHp, def.maxHp - 3 * Campaign.player.redDamage - 80);
    });

    test('强化宝石的额外伤害只算一笔：playerDamage 事件之和等于实际掉血', () {
      // UI 的伤害飘字与结算面板的「总伤害」只统计 playerDamage——它必须
      // 等于真正扣掉的血量。special 事件是"这一下有强化加成"的标记，
      // 它的数值已经包含在 playerDamage 里了，再累加一遍就会虚报。
      final state = newBattle(0);
      final events = state.applyClear(
        {GemType.red: 3},
        combo: 1,
        specialBonus: 80,
      );
      final dealt = events
          .where((e) => e.kind == CombatEventKind.playerDamage)
          .fold<int>(0, (sum, e) => sum + e.amount);
      expect(dealt, def.maxHp - state.enemyHp);
    });

    test('击杀那一击只记实际扣掉的血，溢出的伤害不算数', () {
      // 敌人只剩 10 血而这一下能打 104：事件与飘字该报 10。
      // 若按"打出的伤害"上报，击杀时会凭空多出一大截，结算面板的总伤害
      // 也随之虚高。
      final state = newBattle(0);
      state.enemyHp = 10;
      final events = state.applyClear({GemType.red: 4}, combo: 1);
      final dealt = events
          .where((e) => e.kind == CombatEventKind.playerDamage)
          .fold<int>(0, (sum, e) => sum + e.amount);
      expect(dealt, 10);
      expect(state.phase, BattlePhase.won);
    });
  });

  group('敌方攻击预警', () {
    test('重击被单次伤害上限截断，预警与实际伤害完全一致', () {
      // 第五关的魔女：攻击 170、每 3 次一记 1.8 倍重击 —— 重击本身会顶穿
      // 「单次伤害不超过最大生命 65%」的封顶，预警必须按封顶后的值报。
      final state = BattleState(def: Campaign.levels[4].enemy, levelIndex: 4);
      state.attackCount = 2; // 下一次（第 3 次）就是重击
      expect(state.nextAttackIsHeavy, isTrue);

      final predicted = state.incomingDamage;
      expect(
        predicted,
        (Campaign.player.maxHp * BattleState.singleHitCapRatio).round(),
      );

      for (var i = 0; i < state.def.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(
        Campaign.player.maxHp - state.playerHp,
        predicted,
        reason: '预警写着多少，落下来就该是多少',
      );
    });

    test('「硬化」减伤同样计入预警', () {
      final profile = Campaign.player.copyWith(damageReduction: 0.4);
      final state = BattleState(
        def: Campaign.levels[1].enemy,
        levelIndex: 1,
        profile: profile,
      );
      state.attackCount = 2; // 守卫每 3 次重击一次，下一次正好是第 3 次
      expect(state.nextAttackIsHeavy, isTrue);

      final predicted = state.incomingDamage;
      expect(predicted, (Campaign.levels[1].enemy.attack * 1.8 * 0.6).round());

      for (var i = 0; i < state.def.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(profile.maxHp - state.playerHp, predicted);
    });
  });

  group('敌方回合', () {
    test('到达攻击回合时出手，护盾优先抵挡', () {
      final state = newBattle(0);
      state.shield = 100;

      for (var i = 0; i < def.turnsPerAttack - 1; i++) {
        final events = state.endPlayerTurn();
        expect(
          events.any((e) => e.kind == CombatEventKind.enemyAttack),
          isFalse,
          reason: '还没到出手回合',
        );
        expect(state.playerHp, Campaign.player.maxHp);
      }

      final events = state.endPlayerTurn();
      expect(events.any((e) => e.kind == CombatEventKind.enemyAttack), isTrue);
      // 第一关的攻击（62 点）全部被 100 点护盾吸收
      expect(state.shield, 100 - def.attack);
      expect(state.playerHp, Campaign.player.maxHp);
      expect(state.turnsToAttack, def.turnsPerAttack, reason: '攻击后重新计时');
    });

    test('护盾不足时溢出伤害打到生命', () {
      final state = BattleState(def: def, levelIndex: 0);
      state.shield = 10;
      for (var i = 0; i < def.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(state.playerHp, Campaign.player.maxHp - (def.attack - 10));
    });

    test('易伤会在若干回合后消失', () {
      final state = newBattle(0);
      state.applyClear({GemType.purple: 3}, combo: 1);
      expect(state.curseStacks, 3);
      for (var i = 0; i < 3; i++) {
        state.endPlayerTurn();
      }
      expect(state.curseStacks, 0);
    });

    test('重击会打出更高伤害', () {
      final heavyDef = Campaign.levels[1].enemy;
      expect(heavyDef.heavyEvery, 3);
      final state = BattleState(def: heavyDef, levelIndex: 1);

      var heavyHits = 0;
      for (var round = 0; round < heavyDef.turnsPerAttack * 3; round++) {
        final events = state.endPlayerTurn();
        for (final e in events) {
          if (e.kind == CombatEventKind.enemyAttack && e.text == '重击') {
            heavyHits++;
          }
        }
      }
      expect(heavyHits, 1, reason: '三轮里应出现一次重击');
    });

    test('重击前会提前预警', () {
      final state = BattleState(def: Campaign.levels[1].enemy, levelIndex: 1);
      expect(state.nextAttackIsHeavy, isFalse, reason: '第 1 次攻击不是重击');
      state.attackCount = 2;
      expect(state.nextAttackIsHeavy, isTrue, reason: '第 3 次攻击是重击');
    });

    test('吸血型敌人造成伤害后回复自身', () {
      final drainDef = Campaign.levels[5].enemy;
      final state = BattleState(def: drainDef, levelIndex: 5);
      state.enemyHp = drainDef.maxHp ~/ 2;
      final before = state.enemyHp;
      state.applyClear({GemType.red: 4}, combo: 1);
      final dealt = 4 * Campaign.player.redDamage;
      expect(state.enemyHp, greaterThan(before - dealt), reason: '吸血应该回补一部分生命');
      expect(state.enemyHp, lessThan(before), reason: '但总体仍要掉血');
    });

    test('吸血不会把被击杀的敌人救活', () {
      final drainDef = Campaign.levels[5].enemy;
      final state = BattleState(def: drainDef, levelIndex: 5);
      state.enemyHp = 10;
      state.applyClear({GemType.red: 4}, combo: 1);
      expect(state.phase, BattlePhase.won, reason: '致命一击吸血后不该复活');
      expect(state.enemyHp, 0);
    });

    test('单次伤害有上限，狂暴重击也不会一击必杀', () {
      final bossDef = Campaign.levels[5].enemy;
      final state = BattleState(def: bossDef, levelIndex: 5);
      state.enraged = true;
      state.turnsToAttack = 1;
      state.attackCount = bossDef.heavyEvery - 1; // 下一击是重击
      state.endPlayerTurn();

      final cap = (Campaign.player.maxHp * BattleState.singleHitCapRatio)
          .round();
      final lost = Campaign.player.maxHp - state.playerHp + state.shield;
      expect(lost, lessThanOrEqualTo(cap));
      expect(state.playerHp, greaterThan(0), reason: '不该被一击打死');
    });

    test('敌人护盾会再生并吸收伤害', () {
      final guardDef = Campaign.levels[1].enemy;
      final state = BattleState(def: guardDef, levelIndex: 1);
      for (var i = 0; i < guardDef.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(state.enemyShield, guardDef.shieldRegen);

      final before = state.enemyHp;
      state.applyClear({GemType.red: 3}, combo: 1);
      final damage = 3 * Campaign.player.redDamage;
      expect(state.enemyShield, 0, reason: '护盾应被打光');
      expect(
        state.enemyHp,
        before - (damage - guardDef.shieldRegen),
        reason: '这一击只有超出护盾的部分能打到血量',
      );
    });

    test('狂暴会在血量低于阈值时触发', () {
      final bossDef = Campaign.levels[4].enemy;
      final state = BattleState(def: bossDef, levelIndex: 4);
      expect(state.enraged, isFalse);
      state.applyClear({GemType.red: 200}, combo: 1);
      expect(state.enraged, isTrue);
      expect(
        state.enemyHp / bossDef.maxHp,
        lessThanOrEqualTo(bossDef.enrageAt),
      );
    });

    test('狂暴后出手更快：间隔缩短一回合但不低于 2', () {
      final bossDef = Campaign.levels[4].enemy;
      expect(
        bossDef.turnsPerAttack,
        greaterThan(2),
        reason: '这关要能看出提速，别选 2 回合的敌人',
      );
      final state = BattleState(def: bossDef, levelIndex: 4);
      state.applyClear({GemType.red: 200}, combo: 1);
      expect(state.enraged, isTrue);

      for (var i = 0; i < bossDef.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(
        state.turnsToAttack,
        math.max(2, bossDef.turnsPerAttack - 1),
        reason: '狂暴后倒计时不再回到原本的间隔',
      );
    });

    test('汲魂：命中时夺走怒气，但不会夺走玩家没有的', () {
      // 第一关的鬼火就带汲魂，是玩家见到的第一个敌方机制。
      final wispDef = Campaign.levels[0].enemy;
      expect(wispDef.rageDrain, greaterThan(0), reason: '这一关必须带汲魂，否则用例失去意义');

      final rich = BattleState(def: wispDef, levelIndex: 0)..rage = 30;
      for (var i = 0; i < wispDef.turnsPerAttack; i++) {
        rich.endPlayerTurn();
      }
      expect(rich.rage, 30 - wispDef.rageDrain);

      final poor = BattleState(def: wispDef, levelIndex: 0)..rage = 3;
      for (var i = 0; i < wispDef.turnsPerAttack; i++) {
        poor.endPlayerTurn();
      }
      expect(poor.rage, 0, reason: '只夺走手里有的那几点');
    });

    test('禁疗：命中后治疗减半并挂上回合数，且逐回合递减', () {
      final witchDef = Campaign.levels[3].enemy;
      expect(witchDef.healBlockTurns, greaterThan(0), reason: '巫女必须带禁疗');

      final state = BattleState(def: witchDef, levelIndex: 3);
      expect(state.healBlockTurns, 0);
      for (var i = 0; i < witchDef.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(state.healBlockTurns, witchDef.healBlockTurns, reason: '命中后挂上禁疗');

      // 禁疗期间治疗只剩一半。
      final before = state.playerHp;
      state.applyClear({GemType.green: 4}, combo: 1);
      final full = 4 * Campaign.player.greenHeal;
      expect(state.playerHp - before, full - (full * 0.5).round());

      // 每过一个回合消耗一层（敌人下次出手会重新挂满）。
      final turnsLeft = state.healBlockTurns;
      state.endPlayerTurn();
      expect(state.healBlockTurns, turnsLeft - 1);
    });
  });

  group('胜负与必杀', () {
    test('敌人生命归零判定胜利', () {
      final state = newBattle(0);
      state.applyClear({GemType.red: 200}, combo: 1, specialBonus: 500);
      expect(state.phase, BattlePhase.won);
      expect(state.isWon, isTrue);
      expect(state.enemyHp, 0);
      expect(
        state.applyClear({GemType.red: 3}, combo: 1),
        isEmpty,
        reason: '结束后不再结算',
      );
    });

    test('玩家生命归零判定失败', () {
      final state = BattleState(def: def, levelIndex: 0, playerHp: 20);
      for (var i = 0; i < def.turnsPerAttack; i++) {
        state.endPlayerTurn();
      }
      expect(state.phase, BattlePhase.lost);
      expect(state.playerHp, 0);
    });

    test('怒气未满无法释放必杀', () {
      final state = newBattle(0);
      expect(state.canCastUltimate, isFalse);
      expect(state.castUltimate(), isEmpty);
    });

    test('必杀消耗全部怒气并造成额外伤害', () {
      final state = newBattle(0);
      state.applyClear({GemType.yellow: 30}, combo: 1);
      expect(state.canCastUltimate, isTrue);

      final before = state.enemyHp;
      final events = state.castUltimate();
      expect(state.rage, 0);
      expect(events.any((e) => e.kind == CombatEventKind.ultimate), isTrue);
      expect(before - state.enemyHp, Campaign.player.ultimateBonusDamage);
    });

    test('必杀期间的十字清除按倍率结算', () {
      final state = newBattle(0);
      state.applyClear({GemType.yellow: 30}, combo: 1);
      state.castUltimate();
      final before = state.enemyHp;
      state.applyClear(
        {GemType.red: 4},
        combo: 1,
        multiplier: Campaign.player.ultimateMultiplier,
      );
      final expected =
          (4 * Campaign.player.redDamage * Campaign.player.ultimateMultiplier)
              .round();
      expect(before - state.enemyHp, expected);
    });
  });

  group('关卡数据', () {
    test('关卡难度递增：血量更高、每回合威胁更大', () {
      for (var i = 1; i < Campaign.levels.length; i++) {
        final prev = Campaign.levels[i - 1].enemy;
        final cur = Campaign.levels[i].enemy;
        expect(cur.maxHp, greaterThan(prev.maxHp), reason: '第 ${i + 1} 关血量应更高');
        final prevThreat = prev.attack / prev.turnsPerAttack;
        final curThreat = cur.attack / cur.turnsPerAttack;
        expect(
          curThreat,
          greaterThanOrEqualTo(prevThreat),
          reason: '第 ${i + 1} 关每回合威胁不应低于上一关',
        );
      }
    });

    test('敌人出手间隔至少 2 回合，玩家总有反应余地', () {
      for (final level in Campaign.levels) {
        expect(
          level.enemy.turnsPerAttack,
          greaterThanOrEqualTo(2),
          reason: '${level.enemy.name} 出手太频繁',
        );
      }
    });

    test('玩家永远不会被单次攻击直接秒杀', () {
      for (final level in Campaign.levels) {
        final def = level.enemy;
        var raw = def.attack * def.heavyMultiplier * 1.5; // 最坏情况：狂暴重击
        final cap = Campaign.player.maxHp * BattleState.singleHitCapRatio;
        expect(
          raw > cap ? cap : raw,
          lessThan(Campaign.player.maxHp.toDouble()),
          reason: '${def.name} 的一击上限不应超过玩家满血',
        );
      }
    });
  });
}
