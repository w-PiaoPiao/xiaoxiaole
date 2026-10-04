import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';

BattleState newBattle(int level) =>
    BattleState(def: Campaign.levels[level].enemy, levelIndex: level);

void main() {
  final def = Campaign.levels[0].enemy;

  /// 构造一位带技能的测试角色。turnsPerAttack=1：每个玩家回合结束她就
  /// 出手一次，skillEvery 控制技能节奏，用例不必拖很多回合。
  EnemyDef skillBoss(
    EnemySkill skill, {
    int skillEvery = 2,
    int attack = 100,
    int phases = 1,
  }) => EnemyDef(
    id: 'test_skill',
    name: '试炼技能者',
    title: '无',
    story: '测试用的技能剪影。',
    taunt: '「看招。」',
    archetype: EnemyArchetype.moonPriestess,
    maxHp: 1000,
    attack: attack,
    turnsPerAttack: 1,
    skill: skill,
    skillEvery: skillEvery,
    phases: phases,
    themeColor: 0xFF9FD8FF,
  );

  /// 出厂 300 血撑不过三下 100 攻击——多回合的技能用例在每一步前
  /// 把玩家血补满，读数只关心技能本身，不关心玩家的死活。
  void revivePlayer(BattleState state) => state.playerHp = state.profile.maxHp;

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
      // 第五战的魅魔夜歌：攻击 170、每 3 次一记 1.8 倍重击 —— 重击会顶穿
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
      // 第一关妖精的攻击全部被护盾吸收
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
      // 卡梅拉（第九战）的「血宴」是吸血机制的正面教学。
      final drainDef = Campaign.levels[8].enemy;
      expect(drainDef.drainRatio, greaterThan(0), reason: '这一关必须带吸血，否则用例失去意义');
      final state = BattleState(def: drainDef, levelIndex: 8);
      state.enemyHp = drainDef.maxHp ~/ 2;
      final before = state.enemyHp;
      state.applyClear({GemType.red: 4}, combo: 1);
      final dealt = 4 * Campaign.player.redDamage;
      expect(state.enemyHp, greaterThan(before - dealt), reason: '吸血应该回补一部分生命');
      expect(state.enemyHp, lessThan(before), reason: '但总体仍要掉血');
    });

    test('吸血不会把被击杀的敌人救活', () {
      final drainDef = Campaign.levels[8].enemy;
      final state = BattleState(def: drainDef, levelIndex: 5);
      // 终战是多形态 BOSS：这一条守的是"最后一管被打空"，
      // 所以直接站到最后一管上，避免打着打着变成换形态。
      state.phaseIndex = drainDef.phases;
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
      // 先把血压到阈值上方一线，再补一击越过它。直接打 200 颗红宝石会
      // 打空整管——多形态的魔女会因此"换形态"，而不是"狂暴"。
      state.enemyHp = (bossDef.maxHp * bossDef.enrageAt).round() + 1;
      state.applyClear({GemType.red: 1}, combo: 1);
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
      state.enemyHp = (bossDef.maxHp * bossDef.enrageAt).round() + 1;
      state.applyClear({GemType.red: 1}, combo: 1);
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
      // 汲魂在战役里不再是某位角色的基础机制（凛月的「月蚀」走技能通道，
      // 无尽模式里它以精英词条登场）——这里构造一个带汲魂的敌人，
      // 守住结算口径本身。
      const wispDef = EnemyDef(
        id: 'test_siphon',
        name: '试炼汲魂者',
        title: '无',
        story: '测试用的汲魂剪影。',
        taunt: '「怒气也不错。」',
        archetype: EnemyArchetype.moonPriestess,
        maxHp: 1000,
        attack: 50,
        turnsPerAttack: 3,
        rageDrain: 8,
        themeColor: 0xFF9FD8FF,
      );

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
        // 比总血量：多形态 BOSS 的 maxHp 只是"每管"，单看会比前一关小。
        expect(cur.totalHp, greaterThan(prev.totalHp), reason: '第 ${i + 1} 关血量应更高');
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

  group('多管血 BOSS', () {
    const twoPhase = EnemyDef(
      id: 'test_boss',
      name: '试炼之影',
      title: '两管血',
      story: '测试用的两管血剪影。',
      taunt: '「再来一次。」',
      archetype: EnemyArchetype.voidWatcher,
      maxHp: 1000,
      phases: 2,
      attack: 100,
      turnsPerAttack: 3,
      themeColor: 0xFFB44BFF,
    );

    BattleState phaseBattle() => BattleState(def: twoPhase, levelIndex: 0);

    test('总血量按管数累加', () {
      expect(twoPhase.totalHp, 2000);
      expect(twoPhase.hasPhases, isTrue);
      expect(Campaign.levels.first.enemy.hasPhases, isFalse, reason: '单管敌人不受影响');
    });

    test('打空一管不判胜，而是满血进入下一形态', () {
      final state = phaseBattle();
      state.applyClear({GemType.purple: 6}, combo: 1); // 先铺满易伤
      expect(state.curseStacks, greaterThan(0));

      state.enemyHp = 10; // 只剩一丝血，下一击必破
      final events = state.applyClear({GemType.red: 3}, combo: 1);

      expect(state.isWon, isFalse, reason: '还有下一管，不算赢');
      expect(state.phaseIndex, 2);
      expect(state.enemyHp, twoPhase.maxHp, reason: '下一管从头满血');
      expect(state.curseStacks, 0, reason: '易伤清零：优势要重新建立');
      expect(
        state.turnsToAttack,
        twoPhase.turnsPerAttack,
        reason: '换形态给一个完整回合的喘息',
      );
      expect(
        events.map((e) => e.kind),
        contains(CombatEventKind.phaseChange),
        reason: 'UI 靠这条事件播转形态演出，不能只在日志里写',
      );
    });

    test('溢出的伤害不带入下一管', () {
      final state = phaseBattle();
      state.enemyHp = 10;
      // 这一击远超 10 点：多余的力量不会打到下一管身上。
      state.applyClear({GemType.red: 20}, combo: 1);
      expect(
        state.enemyHp,
        twoPhase.maxHp,
        reason: '否则一次攒好的爆发能连穿两三管，多形态的节奏全没了',
      );
    });

    test('最后一管打空才判胜', () {
      final state = phaseBattle();
      state.phaseIndex = 2;
      state.enemyHp = 10;
      state.applyClear({GemType.red: 3}, combo: 1);
      expect(state.isWon, isTrue);
      expect(state.enemyHp, 0);
      expect(state.phaseIndex, 2, reason: '不会再往上加形态');
    });

    test('形态越高，敌人出手越凶', () {
      final first = phaseBattle().incomingDamage;
      final second = phaseBattle()..phaseIndex = 2;
      expect(
        second.incomingDamage,
        greaterThan(first),
        reason: '每进入下一形态，攻击按 phaseAttackGrowth 提升',
      );
    });

    test('新形态的狂暴要重新判定', () {
      final state = phaseBattle();
      state.enraged = true;
      state.enemyHp = 10;
      state.applyClear({GemType.red: 3}, combo: 1);
      expect(state.enraged, isFalse, reason: '满血的下一管上"残血狂暴"不成立');
    });
  });

  group('专属技能', () {
    test('技能回合有预警，且预警包含影分身的追加段', () {
      final def = skillBoss(
        const EnemySkill(name: '影分身', kind: EnemySkillKind.shadowStrike, ratio: 0.5),
      );
      final state = BattleState(def: def, levelIndex: 0);
      // 第 1 次出手（attackCount=0 → 下一次是 1）不是技能回合。
      expect(state.nextAttackIsSkill, isFalse);
      expect(state.incomingDamage, 100);

      // 第 2 次出手是技能回合：预警 = 本体 100 + 分身 50。
      state.endPlayerTurn();
      expect(state.nextAttackIsSkill, isTrue);
      expect(state.incomingDamage, 150);
    });

    test('自愈技能回血但不超过上限', () {
      final def = skillBoss(
        const EnemySkill(name: '萌芽复苏', kind: EnemySkillKind.sprout, ratio: 0.07),
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.enemyHp = def.maxHp - 200;
      revivePlayer(state);
      state.endPlayerTurn(); // 第 1 次出手：普通攻击（敌人血量不变）
      expect(state.enemyHp, def.maxHp - 200);
      revivePlayer(state);
      state.endPlayerTurn(); // 第 2 次出手：技能回合，回复 70
      expect(state.enemyHp, def.maxHp - 130);
      // 打到残血再触发也不超过上限。
      state.enemyHp = def.maxHp - 10;
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyHp, def.maxHp);
    });

    test('结盾技能给敌方护盾，受每管血量三分之一封顶', () {
      final def = skillBoss(
        const EnemySkill(name: '圣光壁垒', kind: EnemySkillKind.barrier, ratio: 0.12),
      );
      final state = BattleState(def: def, levelIndex: 0);
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyShield, 120);
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyShield, 240);
    });

    test('咒毒按回合结算，毒可以致死', () {
      // 攻击力为 0 的试炼者：掉血只来自毒，读数干净。
      final def = skillBoss(
        const EnemySkill(name: '猩红咒毒', kind: EnemySkillKind.hex, amount: 30, turns: 3),
        attack: 0,
        skillEvery: 99,
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.poisonDamage = 30;
      state.poisonTurns = 2;
      state.endPlayerTurn();
      expect(state.playerHp, state.profile.maxHp - 30);
      expect(state.poisonTurns, 1);
      state.endPlayerTurn();
      expect(state.playerHp, state.profile.maxHp - 60);
      expect(state.poisonTurns, 0);
      state.endPlayerTurn();
      expect(state.playerHp, state.profile.maxHp - 60, reason: '毒结束后不再掉血');

      // 致死口径：毒的最后一跳能收走残血的玩家。
      final dying = BattleState(def: def, levelIndex: 0, playerHp: 25);
      dying.poisonDamage = 30;
      dying.poisonTurns = 2;
      dying.endPlayerTurn();
      expect(dying.phase, BattlePhase.lost, reason: '咒毒可以致死');
    });

    test('魅惑夺走玩家的护盾并化为己用', () {
      final def = skillBoss(
        const EnemySkill(name: '魅惑凝视', kind: EnemySkillKind.charm, ratio: 0.45),
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.shield = 300;
      revivePlayer(state);
      state.endPlayerTurn(); // 普通攻击被盾挡下：300 → 200
      expect(state.shield, 200);
      revivePlayer(state);
      state.endPlayerTurn(); // 技能回合：攻击再吃 100，再被夺走 100×0.45=45
      expect(state.shield, 55);
      expect(state.enemyShield, 45, reason: '被夺的护盾化为她的护盾');
    });

    test('月蚀偷走怒气', () {
      final def = skillBoss(
        const EnemySkill(name: '月蚀', kind: EnemySkillKind.eclipse, amount: 16),
      );
      final state = BattleState(def: def, levelIndex: 0)..rage = 50;
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.rage, 50, reason: '第 1 次出手不是技能回合');
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.rage, 34);
    });

    test('缠缚让护盾获取减半并逐回合衰减', () {
      // 攻击力为 0：她的攻击不会把护盾打掉，读数只反映结界本身；
      // skillEvery=3 让技能只在第 3 次出手触发，不会中途再缠一遍。
      final def = skillBoss(
        const EnemySkill(name: '丝线缠缚', kind: EnemySkillKind.snare, turns: 2),
        attack: 0,
        skillEvery: 3,
      );
      final state = BattleState(def: def, levelIndex: 0);
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn(); // 第 3 次出手：挂上 2 回合结界
      expect(state.wardWeakenTurns, 2);
      state.applyClear({GemType.blue: 2}, combo: 1);
      expect(state.shield, Campaign.player.blueShield, reason: '获取减半');

      revivePlayer(state);
      state.endPlayerTurn(); // 结界衰减到 1：仍然减半
      state.applyClear({GemType.blue: 2}, combo: 1);
      expect(
        state.shield,
        Campaign.player.blueShield * 2,
        reason: '结界还有 1 回合，半价继续生效',
      );

      revivePlayer(state);
      state.endPlayerTurn(); // 结界结束
      expect(state.wardWeakenTurns, 0);
      state.applyClear({GemType.blue: 2}, combo: 1);
      expect(state.shield, Campaign.player.blueShield * 4, reason: '恢复全价');
    });

    test('过载叠层提高攻击，换形态后清零', () {
      final def = skillBoss(
        const EnemySkill(name: '过载充能', kind: EnemySkillKind.surge, ratio: 0.09),
        phases: 2,
      );
      final state = BattleState(def: def, levelIndex: 0);
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyPowerStacks, 0);
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyPowerStacks, 1);
      // 每层 +9%：两层的预警按 100×1.18 判定。
      revivePlayer(state);
      state.endPlayerTurn();
      revivePlayer(state);
      state.endPlayerTurn();
      expect(state.enemyPowerStacks, 2);
      expect(state.incomingDamage, (100 * 1.18).round());

      // 换形态把叠层清零：与易伤/护盾同一条口径。
      state.enemyHp = 10;
      state.applyClear({GemType.red: 30}, combo: 1);
      expect(state.phaseIndex, 2, reason: '打空一管进入下一形态');
      expect(state.enemyPowerStacks, 0);
    });

    test('龙威贯穿无视护盾', () {
      final def = skillBoss(
        const EnemySkill(name: '龙威重压', kind: EnemySkillKind.crush),
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.shield = 500;
      revivePlayer(state);
      state.endPlayerTurn(); // 普通攻击被盾挡下
      expect(state.shield, 400);
      revivePlayer(state);
      state.endPlayerTurn(); // 技能回合：直接贯穿
      expect(state.shield, 400, reason: '护盾分毫未损');
      expect(state.playerHp, state.profile.maxHp - 100, reason: '这一击实打实落在血上');
    });

    test('十三位角色的技能定义各就各位', () {
      final skills = [
        for (final level in Campaign.levels)
          if (level.enemy.skill case final skill?) skill.kind,
      ];
      expect(skills.length, 13, reason: '每位美少女都有一个专属技能');
      // 复用机制是刻意的（9 种技能 13 个人），不做反向断言——将来
      // "13 人 13 技"是合理演进，不该被测试拦住。
      expect(skills.toSet().length, lessThan(13));
      // 终战与龙女必须带硬机制：贯穿与咒毒是她们人设的战斗面。
      expect(Campaign.levels[11].enemy.skill!.kind, EnemySkillKind.crush);
      expect(Campaign.levels[12].enemy.skill!.kind, EnemySkillKind.hex);
    });
  });

  group('消耗战（僵持）机制', () {
    EnemyDef attritionBoss({double ramp = 0.12, int attack = 10}) =>
        EnemyDef(
          id: 'test_attrition',
          name: '僵持试炼者',
          title: '无',
          story: '测试用的时间压力剪影。',
          taunt: '「时间站在我这边。」',
          archetype: EnemyArchetype.witch,
          maxHp: 999999,
          attack: attack,
          turnsPerAttack: 1,
          attritionRamp: ramp,
          themeColor: 0xFFB44BFF,
        );

    test('100 回合内预警与实伤都还没有惩罚', () {
      final state = BattleState(def: attritionBoss(), levelIndex: 0);
      state.playerTurns = BattleState.attritionStartTurn - 2;
      expect(state.incomingDamage, 10);
      state.endPlayerTurn();
      expect(Campaign.player.maxHp - state.playerHp, 10);
    });

    test('台阶跨越的那一击：预警按出手时刻推倍率，与实伤一致', () {
      // 玩家回合中 playerTurns=99：这一击落在本回合末（回合数先 ++ 到
      // 100 再结算敌人），倍率恰好在它身上跨过 1.0 → 1.12 的台阶。
      // 预警若按当前回合数推，会少报整整 12%——玩家按预警留的血
      // 正好被这一击收走。
      final state = BattleState(def: attritionBoss(), levelIndex: 0);
      state.playerTurns = BattleState.attritionStartTurn - 1;
      final predicted = state.incomingDamage;
      expect(predicted, (10 * 1.12).round());
      state.endPlayerTurn();
      expect(
        Campaign.player.maxHp - state.playerHp,
        predicted,
        reason: '预警写着多少，落下来就该是多少（含僵持台阶）',
      );
      expect(state.playerTurns, BattleState.attritionStartTurn);
    });

    test('僵持惩罚乘在封顶之后：能穿透受击上限', () {
      // 攻击 10 万：65% 封顶先把单次伤害按在 195，1.5 倍惩罚乘在封顶
      // 之后——实际掉血必须超过 65% 上限，否则"打不动"的对局又回来了。
      final state = BattleState(def: attritionBoss(ramp: 0.5, attack: 100000), levelIndex: 0);
      state.playerTurns = BattleState.attritionStartTurn; // 倍率 1.5
      final cap = (Campaign.player.maxHp * BattleState.singleHitCapRatio).round();
      state.endPlayerTurn();
      final lost = Campaign.player.maxHp - state.playerHp;
      expect(
        lost,
        greaterThan(cap),
        reason: '封顶保护的是"减伤前"的天花板，僵持惩罚要能穿过去',
      );
      expect(lost, lessThanOrEqualTo(Campaign.player.maxHp));
    });
  });

  group('多管血与结算边界', () {
    test('打空一管的那一击不会先闪假「狂暴」', () {
      // 破管瞬间 enemyHp==0，狂暴要在新形态满血下重新判定——否则
      // 事件流里先闪一条"狂暴"再播转形态，演出自相矛盾。
      const def = EnemyDef(
        id: 'test_phase_enrage',
        name: '破管试炼者',
        title: '无',
        story: '测试用的转形态剪影。',
        taunt: '「再来。」',
        archetype: EnemyArchetype.moonPriestess,
        maxHp: 100,
        phases: 2,
        attack: 100,
        turnsPerAttack: 1,
        enrageAt: 0.35,
        skill: EnemySkill(name: '自愈', kind: EnemySkillKind.sprout, ratio: 0.1),
        skillEvery: 99,
        themeColor: 0xFF9FD8FF,
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.enemyHp = 50;
      final events = state.applyClear({GemType.red: 60}, combo: 1);
      expect(
        events.where((e) => e.kind == CombatEventKind.enrage),
        isEmpty,
        reason: 'enemyHp==0 时狂暴判定必须让位给转形态',
      );
      expect(state.phaseIndex, 2);
      expect(state.enraged, isFalse);
    });

    test('荆棘反弹不能把败局翻成"同归于尽算赢"', () {
      // 玩家死于这一击时不再反弹："玩家先死判负"以 _enemyAct 末行的
      // playerHp 判定为权威，反弹（可能触发 _damageEnemy 置 won）排在
      // 它前面——没有 playerHp>0 守卫的话，行序一重排结局就会翻转。
      // 数值精心凑过：单次伤害被 65% 封顶按在 195 以内，盾 40 吸收 40、
      // 玩家只剩 150 血（掉 155 → 死），反弹的 40 恰好打死 40 血的敌人
      // ——修复前这就是一局"同归于尽算赢"。
      final profile = Campaign.player.copyWith(
        effects: Campaign.player.effects.copyWith(shieldReflect: 1.0),
      );
      const def = EnemyDef(
        id: 'test_thorns_fall',
        name: '荆棘试炼者',
        title: '无',
        story: '测试用的反弹剪影。',
        taunt: '「一起倒下吧。」',
        archetype: EnemyArchetype.moonPriestess,
        maxHp: 40,
        attack: 700,
        turnsPerAttack: 1,
        themeColor: 0xFF9FD8FF,
      );
      final state = BattleState(
        def: def,
        levelIndex: 0,
        profile: profile,
        playerHp: 150,
      );
      state.shield = 40;
      state.endPlayerTurn();
      expect(state.phase, BattlePhase.lost);
      expect(
        state.enemyHp,
        def.maxHp,
        reason: '人已经倒下，荆棘不再扎针',
      );
    });

    test('终战四管逐管变凶', () {
      final def = Campaign.levels[12].enemy;
      // 用厚血玩家把 65% 封顶抬出攻击力范围，否则形态递增会被封顶盖住。
      final profile = Campaign.player.copyWith(maxHp: 1000);
      final strikes = <int>[
        for (var phase = 1; phase <= def.phases; phase++)
          (BattleState(def: def, levelIndex: 12, profile: profile)
                ..phaseIndex = phase
                ..attackCount = 0 // 下一次出手（第 1 次）是普通攻击
              )
              .incomingDamage,
      ];
      expect(strikes.length, 4);
      expect(strikes[0], lessThan(strikes[1]));
      expect(strikes[1], lessThan(strikes[2]));
      expect(strikes[2], lessThan(strikes[3]),
          reason: '每管形态按 phaseAttackGrowth 递增，终战要越打越紧');
    });
  });

  group('专属技能边界', () {
    test('影分身追加段可以被护盾挡下', () {
      final def = skillBoss(
        const EnemySkill(name: '影分身', kind: EnemySkillKind.shadowStrike, ratio: 0.5),
        skillEvery: 1,
        attack: 100,
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.shield = 200;
      revivePlayer(state);
      state.endPlayerTurn(); // 主段 100 全挡，追加段 50 由剩余 100 挡下
      expect(state.shield, 50);
      expect(state.playerHp, state.profile.maxHp);
    });

    test('魅惑在玩家没有护盾时安静跳过', () {
      final def = skillBoss(
        const EnemySkill(name: '魅惑', kind: EnemySkillKind.charm, ratio: 0.5),
        skillEvery: 1,
        attack: 10,
      );
      final state = BattleState(def: def, levelIndex: 0);
      revivePlayer(state);
      final events = state.endPlayerTurn();
      expect(events.where((e) => e.kind == CombatEventKind.charm), isEmpty);
      expect(state.enemyShield, 0);
    });

    test('月蚀在玩家没有怒气时无可偷', () {
      final def = skillBoss(
        const EnemySkill(name: '月蚀', kind: EnemySkillKind.eclipse, amount: 20),
        skillEvery: 1,
        attack: 10,
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.rage = 0;
      revivePlayer(state);
      final events = state.endPlayerTurn();
      expect(events.where((e) => e.kind == CombatEventKind.rageDrain), isEmpty);
      expect(state.rage, 0);
    });

    test('咒毒重复命中按刷新处理：数值覆盖、回合重置', () {
      final def = skillBoss(
        const EnemySkill(name: '咒毒', kind: EnemySkillKind.hex, amount: 26, turns: 3),
        skillEvery: 1,
        attack: 10,
      );
      final state = BattleState(def: def, levelIndex: 0);
      state.poisonTurns = 1;
      state.poisonDamage = 5;
      revivePlayer(state);
      state.endPlayerTurn(); // 旧毒先 tick（1→0，扣 5），新毒覆盖
      expect(state.poisonDamage, 26);
      expect(state.poisonTurns, 3);
    });

    test('过载叠层封顶 5 层', () {
      final def = skillBoss(
        const EnemySkill(name: '过载', kind: EnemySkillKind.surge, ratio: 0.1),
        skillEvery: 1,
        attack: 10,
      );
      final state = BattleState(def: def, levelIndex: 0);
      for (var i = 0; i < 8; i++) {
        revivePlayer(state);
        state.endPlayerTurn();
      }
      expect(state.enemyPowerStacks, 5, reason: '封顶防止攻击被无限抬高');
    });

    test('冰甲/圣壁的护盾封顶为每管血的三分之一', () {
      final def = skillBoss(
        const EnemySkill(name: '圣壁', kind: EnemySkillKind.barrier, ratio: 0.5),
        skillEvery: 1,
        attack: 10,
      );
      final state = BattleState(def: def, levelIndex: 0);
      for (var i = 0; i < 3; i++) {
        revivePlayer(state);
        state.endPlayerTurn();
      }
      expect(state.enemyShield, def.maxHp ~/ 3);
    });

    test('龙女：重击与贯穿同回合叠加，护盾分毫不动', () {
      // 龙女 heavyEvery == skillEvery == 3：第 3 次出手既是 1.8 倍重击
      // 也是贯穿技能——两段倍率相乘还是独立生效？独立：重击倍率在外层，
      // 贯穿只决定"无视护盾"。
      final def = Campaign.levels[11].enemy;
      expect(def.heavyEvery, 3);
      expect(def.skill!.kind, EnemySkillKind.crush);
      final profile = Campaign.player.copyWith(maxHp: 1000);
      final state = BattleState(
        def: def,
        levelIndex: 11,
        profile: profile,
      );
      state.attackCount = def.heavyEvery - 1;
      final predicted = state.incomingDamage;
      expect(predicted, (def.attack * def.heavyMultiplier).round());
      state.shield = 99999;
      state.playerHp = profile.maxHp;
      state.turnsToAttack = 1; // 龙女 turnsPerAttack=3，直接推到出手
      state.endPlayerTurn();
      expect(state.shield, 99999, reason: '贯穿不吃护盾');
      expect(profile.maxHp - state.playerHp, predicted);
    });
  });
}
