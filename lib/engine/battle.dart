import 'dart:math';

import 'gem.dart';
import 'levels.dart';

/// 战斗阶段。
enum BattlePhase { playing, won, lost }

/// 战斗事件类型，UI 依据它选择飘字颜色与图标。
enum CombatEventKind {
  /// 对敌人造成伤害。
  playerDamage,

  /// 敌人护盾吸收。
  enemyShield,

  /// 玩家获得护盾。
  shieldGain,

  /// 玩家治疗。
  heal,

  /// 治疗被削弱而损失的部分。
  healBlocked,

  /// 积攒怒气。
  rage,

  /// 施加易伤。
  curse,

  /// 强化宝石额外伤害。
  special,

  /// 敌人攻击玩家。[amount] 是这次攻击的原始伤害（护盾抵挡的部分另见
  /// [CombatEventKind.playerShield]），实际掉血为两者之差。
  enemyAttack,

  /// 玩家护盾吸收敌方伤害。
  playerShield,

  /// 敌人吸血。
  enemyDrain,

  /// 敌人获得护盾。
  enemyGuard,

  /// 敌人进入狂暴。
  enrage,

  /// 必杀技。
  ultimate,

  /// 提示文本。
  info,
}

/// 一条战斗反馈，UI 会把它转成飘字或日志。
class CombatEvent {
  final CombatEventKind kind;
  final int amount;
  final String? text;

  const CombatEvent(this.kind, this.amount, [this.text]);

  @override
  String toString() => 'CombatEvent(${kind.name}, $amount, ${text ?? ''})';
}

/// 一场战斗的完整状态。
///
/// 这里只做数值结算，不涉及任何动画：棋盘结算出每种宝石的消除数量后，
/// 调用 [applyClear] 即可得到该步的战斗反馈；玩家行动结束调用 [endPlayerTurn]
/// 推进敌方回合并获得敌方行动反馈。
class BattleState {
  final PlayerProfile profile;
  final EnemyDef def;
  final int levelIndex;

  int playerHp;
  int shield = 0;
  int rage = 0;

  /// 剩余的治疗削弱回合数。
  int healBlockTurns = 0;

  int enemyHp;
  int enemyShield = 0;

  /// 敌人身上的易伤层数与剩余回合。
  int curseStacks = 0;
  int curseTurns = 0;

  /// 距离敌人下次出手还有几个玩家回合。
  int turnsToAttack;

  /// 敌人已经出手的次数。
  int attackCount = 0;

  bool enraged = false;

  /// 玩家已经行动的回合数。
  int turn = 0;

  BattlePhase phase = BattlePhase.playing;

  /// 战斗日志，最新的在前面。
  final List<String> log = [];

  BattleState({
    required this.def,
    required this.levelIndex,
    this.profile = Campaign.player,
    int? playerHp,
  })  : playerHp = playerHp ?? Campaign.player.maxHp,
        enemyHp = def.maxHp,
        turnsToAttack = def.turnsPerAttack;

  bool get isOver => phase != BattlePhase.playing;

  bool get isWon => phase == BattlePhase.won;

  double get enemyHpRatio => (enemyHp / def.maxHp).clamp(0.0, 1.0);

  double get playerHpRatio => (playerHp / profile.maxHp).clamp(0.0, 1.0);

  bool get rageReady => rage >= profile.ultimateCost;

  /// 敌方单次攻击的伤害上限（相对玩家最大生命的比例）。
  static const double singleHitCapRatio = 0.55;

  /// 敌人的下一次攻击是否是重击。
  bool get nextAttackIsHeavy =>
      def.heavyEvery > 0 && (attackCount + 1) % def.heavyEvery == 0;

  /// 敌人下次出手的预计伤害（用于 UI 预警）。
  int get incomingDamage {
    var dmg = def.attack * (nextAttackIsHeavy ? def.heavyMultiplier : 1.0);
    if (enraged) dmg *= 1.5;
    return dmg.round();
  }

  /// 是否处于「敌人即将出手」的紧张状态。
  bool get dangerImminent => turnsToAttack <= 1;

  /// 连锁序号对应的伤害倍率，最高 2.5 倍。
  double comboMultiplier(int combo) => min(1 + 0.25 * (combo - 1), 2.5);

  // ------------------------------------------------------------ 玩家行动结算

  /// 结算一次棋盘消除带来的全部效果。
  ///
  /// [counts] 是这一步清除的各色宝石数量，[combo] 为连锁序号。
  List<CombatEvent> applyClear(
    Map<GemType, int> counts, {
    required int combo,
    int specialBonus = 0,
    double multiplier = 1.0,
  }) {
    if (isOver) return const [];
    final events = <CombatEvent>[];

    final comboMul = comboMultiplier(combo);
    final curseMul = 1 + 0.12 * curseStacks;

    final reds = counts[GemType.red] ?? 0;
    if (reds > 0) {
      final raw = reds * profile.redDamage * comboMul * curseMul * multiplier;
      _damageEnemy(raw.round(), events);
    }

    final bonus = (specialBonus * multiplier).round();
    if (bonus > 0) {
      _damageEnemy(bonus, events);
      events.add(CombatEvent(CombatEventKind.special, bonus));
    }

    final blues = counts[GemType.blue] ?? 0;
    if (blues > 0) {
      final gain = (blues * profile.blueShield * multiplier).round();
      final before = shield;
      shield = min(profile.maxShield, shield + gain);
      final actual = shield - before;
      if (actual > 0) events.add(CombatEvent(CombatEventKind.shieldGain, actual));
    }

    final greens = counts[GemType.green] ?? 0;
    if (greens > 0) {
      var healAmount = (greens * profile.greenHeal * multiplier).round();
      if (healBlockTurns > 0) {
        final blocked = (healAmount * 0.5).round();
        healAmount -= blocked;
        if (blocked > 0) {
          events.add(CombatEvent(CombatEventKind.healBlocked, blocked));
        }
      }
      final before = playerHp;
      playerHp = min(profile.maxHp, playerHp + healAmount);
      final actual = playerHp - before;
      if (actual > 0) events.add(CombatEvent(CombatEventKind.heal, actual));
    }

    final yellows = counts[GemType.yellow] ?? 0;
    if (yellows > 0) {
      final gain = (yellows * profile.yellowRage * multiplier).round();
      final before = rage;
      rage = min(profile.maxRage, rage + gain);
      final actual = rage - before;
      if (actual > 0) events.add(CombatEvent(CombatEventKind.rage, actual));
    }

    final purples = counts[GemType.purple] ?? 0;
    if (purples > 0) {
      final gain = (purples * profile.purpleCurse * multiplier).round();
      final before = curseStacks;
      curseStacks = min(profile.maxCurseStacks, curseStacks + gain);
      curseTurns = 3;
      final actual = curseStacks - before;
      if (actual > 0) events.add(CombatEvent(CombatEventKind.curse, actual));
    }

    return events;
  }

  void _damageEnemy(int amount, List<CombatEvent> events) {
    if (amount <= 0 || isOver) return;
    var remaining = amount;

    if (enemyShield > 0) {
      final absorbed = min(enemyShield, remaining);
      enemyShield -= absorbed;
      remaining -= absorbed;
      events.add(CombatEvent(CombatEventKind.enemyShield, absorbed));
    }
    var dealt = 0;
    if (remaining > 0) {
      final before = enemyHp;
      enemyHp = max(0, enemyHp - remaining);
      dealt = before - enemyHp;
      events.add(CombatEvent(CombatEventKind.playerDamage, remaining));
      log.insert(0, '造成 $remaining 点伤害');
    }

    // 吸血只结算「真正扣掉的血量」，而且致命一击不会再回血——
    // 否则高吸血敌人会把已经打空的血又补回来，变成永远打不死的僵局。
    if (def.drainRatio > 0 && dealt > 0 && enemyHp > 0) {
      final drain = (dealt * def.drainRatio).round();
      if (drain > 0) {
        final before = enemyHp;
        enemyHp = min(def.maxHp, enemyHp + drain);
        final actual = enemyHp - before;
        if (actual > 0) events.add(CombatEvent(CombatEventKind.enemyDrain, actual));
      }
    }

    _checkEnrage(events);

    if (enemyHp <= 0) {
      enemyHp = 0;
      phase = BattlePhase.won;
      log.insert(0, '${def.name} 被击败了');
    }
  }

  void _checkEnrage(List<CombatEvent> events) {
    if (!def.enrages || enraged) return;
    if (enemyHp / def.maxHp <= def.enrageAt) {
      enraged = true;
      events.add(const CombatEvent(CombatEventKind.enrage, 0, '狂暴'));
      log.insert(0, '${def.name} 陷入狂暴！');
    }
  }

  /// 必杀技是否可用。
  bool get canCastUltimate => !isOver && rageReady;

  /// 释放必杀技：消耗全部怒气并给予一次性额外伤害。
  ///
  /// 棋盘上的十字清除由调用方通过 `BoardEngine.resolveUltimate` 完成，
  /// 并用 [PlayerProfile.ultimateMultiplier] 作为倍率再次调用 [applyClear]。
  List<CombatEvent> castUltimate() {
    if (!canCastUltimate) return const [];
    rage = 0;
    final events = <CombatEvent>[
      const CombatEvent(CombatEventKind.ultimate, 0, '斩月'),
    ];
    log.insert(0, '释放必杀 · 斩月');
    _damageEnemy(profile.ultimateBonusDamage, events);
    return events;
  }

  // ------------------------------------------------------------ 敌方回合

  /// 玩家行动结束，推进敌方回合。
  List<CombatEvent> endPlayerTurn() {
    if (isOver) return const [];
    turn++;

    final events = <CombatEvent>[];

    if (curseTurns > 0) {
      curseTurns--;
      if (curseTurns <= 0) {
        curseStacks = 0;
      }
    }
    if (healBlockTurns > 0) healBlockTurns--;

    turnsToAttack--;
    if (turnsToAttack <= 0) {
      events.addAll(_enemyAct());
    }
    return events;
  }

  List<CombatEvent> _enemyAct() {
    final events = <CombatEvent>[];
    attackCount++;

    final isHeavy = def.heavyEvery > 0 && attackCount % def.heavyEvery == 0;
    var raw = def.attack * (isHeavy ? def.heavyMultiplier : 1.0);
    if (enraged) raw *= 1.5;

    // 单次伤害不超过玩家最大生命的一定比例：狂暴 + 重击叠加时不至于一击必杀，
    // 玩家永远有操作空间。
    final cap = (profile.maxHp * singleHitCapRatio).round();
    if (raw > cap) raw = cap.toDouble();
    final total = raw.round();

    var absorbed = 0;
    if (shield > 0) {
      absorbed = min(shield, total);
      shield -= absorbed;
    }
    final loss = total - absorbed;
    playerHp = max(0, playerHp - loss);
    // 即使被护盾完全挡下也要产生事件，UI 需要播放挨打反馈。
    events.add(CombatEvent(
      CombatEventKind.enemyAttack,
      total,
      isHeavy ? '重击' : null,
    ));
    if (absorbed > 0) {
      events.add(CombatEvent(CombatEventKind.playerShield, absorbed));
    }
    log.insert(0, '${def.name} ${isHeavy ? '重击' : '攻击'} · 受到 $total 点伤害'
        '${absorbed > 0 ? '（护盾抵挡 $absorbed）' : ''}');

    if (def.healBlockTurns > 0) {
      healBlockTurns = max(healBlockTurns, def.healBlockTurns);
      events.add(const CombatEvent(CombatEventKind.info, 0, '治疗被削弱'));
      log.insert(0, '你被诅咒：治疗效果减半');
    }

    if (def.shieldRegen > 0) {
      final before = enemyShield;
      enemyShield = min(def.maxHp ~/ 3, enemyShield + def.shieldRegen);
      final actual = enemyShield - before;
      if (actual > 0) events.add(CombatEvent(CombatEventKind.enemyGuard, actual));
    }

    turnsToAttack = enraged ? max(2, def.turnsPerAttack - 1) : def.turnsPerAttack;

    if (playerHp <= 0) {
      playerHp = 0;
      phase = BattlePhase.lost;
      log.insert(0, '你倒下了……');
    }
    return events;
  }
}
