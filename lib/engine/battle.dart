import 'dart:math';

import 'gem.dart';
import 'levels.dart';
import 'roguelike.dart';

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

  /// 这一下打出了暴击（单独一条事件，UI 用它加一次强调演出）。
  crit,

  /// 代价类强化在回合开始时的自损（「血契」）。UI 用它提示代价正在生效。
  selfBleed,

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

  /// 敌人夺走玩家怒气（汲魂类机制）。
  rageDrain,

  /// 必杀技。
  ultimate,

  /// 敌人打空一管血、进入下一形态（多管血 BOSS）。
  phaseChange,

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

  /// 当前正在打第几管血（从 1 开始）。单管敌人恒为 1。
  int phaseIndex = 1;

  /// 这一场总共几管血。
  int get phasesTotal => def.phases;

  /// 还剩下几管（含正在打的那一管）。
  int get phasesLeft => phasesTotal - phaseIndex + 1;

  /// 打空这一管之后还有下一管。
  bool get hasNextPhase => phaseIndex < phasesTotal;

  /// 敌人身上的易伤层数与剩余回合。
  int curseStacks = 0;
  int curseTurns = 0;

  /// 距离敌人下次出手还有几个玩家回合。
  int turnsToAttack;

  /// 敌人已经出手的次数。
  int attackCount = 0;

  /// 本场战斗已经结束的玩家回合数。
  ///
  /// 只服务于消耗战惩罚（[EnemyDef.attritionRamp]）：它按时间轴给敌人加压，
  /// 让"打不动"的僵持对局最终能分出胜负，而不是双方都不掉血地磨到超时。
  int playerTurns = 0;

  /// 棋盘上的毒藤数量：每株让敌人的攻击 +[vineAttackBonus]。
  ///
  /// 战斗层不认识棋盘，这个值由 GameScreen 在每个回合开始前从棋盘同步进来；
  /// 毒藤被清掉后下一回合就会自动失效。
  int vineCount = 0;

  /// 每株毒藤给敌人的攻击加成。
  static const double vineAttackBonus = 0.05;

  /// 祭坛被破除时立刻塞给玩家的怒气（清障即收益）。
  static const int altarRageReward = 20;

  bool enraged = false;

  BattlePhase phase = BattlePhase.playing;

  /// 战斗日志，最新的在前面。
  final List<String> log = [];

  /// 暴击判定用的随机源。测试可以传入固定种子，让"这一下是否暴击"可复现。
  final Random rng;

  BattleState({
    required this.def,
    required this.levelIndex,
    PlayerProfile? profile,
    int? playerHp,
    Random? rng,
  }) : profile = profile ?? Campaign.player,
       rng = rng ?? Random(),
       // 不带 playerHp 时按**这一局的档案**满血开局：强化过的档案上限更高，
       // 这里若写死 Campaign.player 就会在换关时把成长吞掉。
       playerHp = playerHp ?? (profile ?? Campaign.player).maxHp,
       enemyHp = def.maxHp,
       turnsToAttack = def.turnsPerAttack;

  bool get isOver => phase != BattlePhase.playing;

  bool get isWon => phase == BattlePhase.won;

  double get enemyHpRatio => (enemyHp / def.maxHp).clamp(0.0, 1.0);

  double get playerHpRatio => (playerHp / profile.maxHp).clamp(0.0, 1.0);

  /// 肉鸽质变与代价（无尽模式的强化写入这里）。
  RoguelikeEffects get fx => profile.effects;

  /// 释放必杀需要的怒气（「月华」会打折）。
  int get ultimateCost => (profile.ultimateCost * fx.ultimateCostMul)
      .round()
      .clamp(1, profile.maxRage);

  bool get rageReady => rage >= ultimateCost;

  /// 敌方单次攻击的伤害上限（相对玩家最大生命的比例）。
  ///
  /// 0.65：重击（顶满封顶）大约打掉六成半血——够痛，逼玩家认真对待预警，
  /// 但两连重击依然留一条命；普通攻击都设计在封顶之下，倍率才有意义。
  ///
  /// 「不屈」会把它压到 0.4，那是"不被一击秒杀"的直接解。
  static const double singleHitCapRatio = 0.65;

  /// 敌人的下一次攻击是否是重击。
  bool get nextAttackIsHeavy =>
      def.heavyEvery > 0 && (attackCount + 1) % def.heavyEvery == 0;

  /// 敌人下次出手的预计伤害（用于 UI 预警与落子顾问的生死判断）。
  ///
  /// 与 [_enemyAct] 共用 [_predictAttackDamage]：减伤与单次伤害封顶都要
  /// 算进来，否则预警是个永远偏大的数字，玩家按它决定补血还是补盾就会
  /// 误判（重击在封顶下能差出上百点）。
  int get incomingDamage => _predictAttackDamage(nextAttackIsHeavy);

  /// 本次攻击的预测伤害，[isHeavy] 决定是否按重击计算。
  ///
  /// 顺序是刻意的：「硬化」减伤在封顶**之前**结算——上限保护的是玩家能
  /// 承受的最大一击，不该被减伤绕过。
  int _predictAttackDamage(bool isHeavy) {
    var raw = def.attack * (isHeavy ? def.heavyMultiplier : 1.0);
    // 形态递增：每打空一管血，敌人的下一次出手就更凶一档。预警算的是
    // 「下一次」的伤害，所以这里的形态系数必须和 [_enemyAct] 用的是同一个。
    if (phaseIndex > 1) {
      raw *= 1 + def.phaseAttackGrowth * (phaseIndex - 1);
    }
    if (enraged) raw *= 1.5;
    // 毒藤：缠在棋盘上的藤蔓每一株都在给敌人加码，清掉才停。
    if (vineCount > 0) raw *= 1 + vineCount * vineAttackBonus;
    if (profile.damageReduction > 0) raw *= 1 - profile.damageReduction;
    final capRatio = fx.hitCapRatio > 0 ? fx.hitCapRatio : singleHitCapRatio;
    final cap = (profile.maxHp * capRatio).round();
    if (raw > cap) raw = cap.toDouble();
    // 消耗战惩罚**在封顶之后**结算，这是刻意的：封顶是个绝对天花板，
    // 乘在它前面的系数（攻击成长、狂暴、毒藤、僵持惩罚）超过天花板后
    // 全部作废——实测把惩罚放在封顶前，"打不动"的对局依然能满血磨到
    // 400 回合。僵持越久、上限保护越挡不住，才是这条曲线该有的样子。
    raw *= _attritionMul;
    return raw.round();
  }

  /// 消耗战惩罚的起点（第几个玩家回合开始加压）与步进。
  ///
  /// 100 回合、每 12 回合 +12%：正常的一波在 20~30 回合内结束，打得动的
  /// build 根本碰不到它；僵住的局（实测能磨到 200~400 回合）会被它逐步
  /// 收掉——既保住"输出流靠手速换生存"的价值，也让无尽模式不会停在
  /// "双方都不掉血"的无限平局上。阈值刻意取得很晚：它是"僵持"的解药，
  /// 不该变成对所有慢节奏 build 的常规惩罚。
  static const int attritionStartTurn = 100;
  static const int attritionEveryTurns = 12;

  /// 消耗战惩罚的当前倍率（没有僵持就是 1.0）。
  double get _attritionMul {
    if (def.attritionRamp <= 0 || playerTurns < attritionStartTurn) return 1.0;
    final steps =
        (playerTurns - attritionStartTurn) ~/ attritionEveryTurns + 1;
    return 1 + def.attritionRamp * steps;
  }

  /// 是否处于「敌人即将出手」的紧张状态。
  bool get dangerImminent => turnsToAttack <= 1;

  /// 连锁序号对应的伤害倍率。上限默认 2.5 倍，「无尽连击」会把它抬高；
  /// 「永动连锁」连起步倍率一起抬。
  double comboMultiplier(int combo) =>
      min(1 + fx.comboBaseBonus + 0.25 * (combo - 1), profile.comboCap);

  /// 是否处于「逆境」（残血）。残血时「狂骨」类强化会提高伤害。
  bool get desperate => playerHpRatio < PlayerProfile.desperateThreshold;

  double get _desperateMul => profile.desperateBonus > 0 && desperate
      ? 1 + profile.desperateBonus
      : 1.0;

  /// 掷一次暴击。返回伤害倍率（未暴击就是 1.0）。
  ///
  /// 只有暴击率大于 0 时才消耗随机数——基础档案永远不暴击，
  /// 于是"没打过暴击强化"的对局仍然是完全确定的。
  double _rollCrit(List<CombatEvent> events) {
    if (profile.critChance <= 0) return 1.0;
    if (rng.nextDouble() >= profile.critChance) return 1.0;
    events.add(const CombatEvent(CombatEventKind.crit, 0, '暴击'));
    return profile.critMultiplier;
  }

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
    final curseMul = 1 + profile.curseBonus * curseStacks;
    final desperateMul = _desperateMul;
    // 「处决者」：残血的敌人挨得更疼。
    final executeMul =
        fx.executeThreshold > 0 && enemyHpRatio < fx.executeThreshold
        ? 1 + fx.executeBonus
        : 1.0;

    final reds = counts[GemType.red] ?? 0;
    if (reds > 0) {
      final crit = _rollCrit(events);
      final raw =
          reds *
          profile.redDamage *
          comboMul *
          curseMul *
          multiplier *
          desperateMul *
          executeMul *
          fx.damageMul *
          crit;
      final dealt = raw.round();
      _damageEnemy(dealt, events);
      // 「过量暴击」：这一下暴击溢出的力量，顺手结成了护盾。
      if (crit > 1.0 && fx.critToShield > 0) {
        _gainShield((dealt * fx.critToShield).round(), events);
      }
    }

    // 「瘟疫」：每一层易伤都让强化宝石打得更狠。
    final bonus =
        (specialBonus *
                multiplier *
                profile.specialPower *
                fx.damageMul *
                (1 + fx.curseToSpecialPower * curseStacks))
            .round();
    if (bonus > 0) {
      final crit = _rollCrit(events);
      _damageEnemy((bonus * crit).round(), events);
      events.add(CombatEvent(CombatEventKind.special, bonus));
    }

    final blues = counts[GemType.blue] ?? 0;
    if (blues > 0) {
      final gain = (blues * profile.blueShield * multiplier).round();
      _gainShield(gain, events);
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
      // 「溢流护盾」：治满之后溢出来的那部分，转成护盾。
      final overflow = healAmount - actual;
      if (overflow > 0 && fx.healOverflowToShield > 0) {
        _gainShield((overflow * fx.healOverflowToShield).round(), events);
      }
    }

    final yellows = counts[GemType.yellow] ?? 0;
    if (yellows > 0) {
      final gain = (yellows * profile.yellowRage * multiplier).round();
      final actual = _addRage(gain);
      if (actual > 0) events.add(CombatEvent(CombatEventKind.rage, actual));
      // 「过载引擎」：怒气满了还在攒的那部分，直接烧成伤害。
      final overflow = gain - actual;
      if (overflow > 0 && fx.rageOverflowDamage > 0) {
        final dealt = (overflow * fx.rageOverflowDamage).round();
        if (dealt > 0) _damageEnemy(dealt, events);
      }
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

  /// 获得护盾。所有护盾来源都走这里——上限与「苦修」的归零只在这一处生效，
  /// 免得某条新路径绕过代价。
  void _gainShield(int amount, List<CombatEvent> events) {
    // 「苦修」的代价在这一层统一执行：蓝宝石、暴击转盾、溢流转盾都绕不过去。
    final scaled = (amount * fx.shieldGainMul).round();
    if (scaled <= 0) return;
    final before = shield;
    shield = min(profile.maxShield, shield + scaled);
    final actual = shield - before;
    if (actual > 0) events.add(CombatEvent(CombatEventKind.shieldGain, actual));
  }

  /// 积攒怒气，返回实际涨上去的点数（涨不动的溢出部分交给调用方处理）。
  int _addRage(int amount) {
    if (amount <= 0) return 0;
    final before = rage;
    rage = min(profile.maxRage, rage + amount);
    return rage - before;
  }

  /// 把伤害打到敌人身上（先吃护盾，再扣血，最后结算吸血与狂暴）。
  ///
  /// 暴击不在这里掷骰——它是「这一下打出多少伤害」的一部分，由 [`_rollCrit`]
  /// 在上游决定，并往同一批事件里塞一条 [CombatEventKind.crit] 供 UI 演出。
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
      // 事件与日志都记「实际扣掉的血」：敌人残血时超出的那部分不算伤害，
      // 否则 UI 的飘字与结算面板的「总伤害」会把溢出值算进去，击杀那一击
      // 虚高一截（battle_test 里那条"等于实际掉血"的用例守的就是这条）。
      if (dealt > 0) {
        events.add(CombatEvent(CombatEventKind.playerDamage, dealt));
        log.insert(0, '造成 $dealt 点伤害');
      }
    }

    // 吸血只结算「真正扣掉的血量」，而且致命一击不会再回血——
    // 否则高吸血敌人会把已经打空的血又补回来，变成永远打不死的僵局。
    if (def.drainRatio > 0 && dealt > 0 && enemyHp > 0) {
      final drain = (dealt * def.drainRatio).round();
      if (drain > 0) {
        final before = enemyHp;
        enemyHp = min(def.maxHp, enemyHp + drain);
        final actual = enemyHp - before;
        if (actual > 0) {
          events.add(CombatEvent(CombatEventKind.enemyDrain, actual));
        }
      }
    }

    _checkEnrage(events);

    if (enemyHp <= 0) {
      if (hasNextPhase) {
        _advancePhase(events);
      } else {
        enemyHp = 0;
        phase = BattlePhase.won;
        log.insert(0, '${def.name} 被击败了');
      }
    }
  }

  /// 打空一管血：敌人满血进入下一形态。
  ///
  /// 三条口径是刻意的：
  ///   1. **溢出的伤害不带入下一管**——每一管都要实打实打空，否则一次
  ///      攒好的爆发就能连穿两三管，多形态的节奏和压力全没了；
  ///   2. **易伤与护盾清零**——打空一管是把优势清零重来，而不是把领先
  ///      带过去；玩家得重新铺易伤，这就是多管血带来的深度；
  ///   3. **出手倒计时重置**——换形态给一个完整的回合喘息，否则刚打空
  ///      一管下一击就落下来，付出与回报完全脱节。
  void _advancePhase(List<CombatEvent> events) {
    phaseIndex++;
    enemyHp = def.maxHp;
    enemyShield = 0;
    curseStacks = 0;
    curseTurns = 0;
    // 新形态的狂暴要重新判定：残血狂暴在满血的下一管上不成立。
    enraged = false;
    turnsToAttack = def.turnsPerAttack;
    events.add(
      CombatEvent(
        CombatEventKind.phaseChange,
        phaseIndex,
        '第 $phaseIndex 形态',
      ),
    );
    log.insert(0, '${def.name} 进入第 $phaseIndex 形态');
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
    // 「月华」之后消耗会打折，所以扣的是 ultimateCost 而不是档案里的原价。
    rage = max(0, rage - ultimateCost);
    final events = <CombatEvent>[
      const CombatEvent(CombatEventKind.ultimate, 0, '斩月'),
    ];
    log.insert(0, '释放必杀 · 斩月');
    // 必杀也吃暴击与逆境加成：攒了半天的怒气打出一次大数字，正是它该有的份量。
    final crit = _rollCrit(events);
    _damageEnemy(
      (profile.ultimateBonusDamage * crit * _desperateMul * fx.damageMul)
          .round(),
      events,
    );
    return events;
  }

  // ------------------------------------------------------------ 道具支援

  /// 祭坛被破除的奖励：直接蓄积怒气。返回实际涨上去的点数。
  int grantRage(int amount) {
    if (isOver) return 0;
    return _addRage(amount);
  }

  /// 凝滞：把敌人的出手倒计时往后推。返回实际推迟的回合数。
  ///
  /// 倒计时已经满格时返回 0——那种情况下道具不该被消耗，UI 会拦下来。
  int delayEnemyAttack([int turns = 1]) {
    if (isOver) return 0;
    final before = turnsToAttack;
    turnsToAttack = min(def.turnsPerAttack, turnsToAttack + turns);
    final actual = turnsToAttack - before;
    if (actual > 0) log.insert(0, '敌方行动被延缓 $actual 回合');
    return actual;
  }

  // ------------------------------------------------------------ 敌方回合

  /// 玩家行动结束，推进敌方回合。
  List<CombatEvent> endPlayerTurn() {
    if (isOver) return const [];

    final events = <CombatEvent>[];

    // 「回春」：新回合开始时先回一口血，再轮到敌人（也可能因此救命）。
    if (profile.regenPerTurn > 0 && playerHp > 0) {
      final before = playerHp;
      playerHp = min(profile.maxHp, playerHp + profile.regenPerTurn);
      final actual = playerHp - before;
      if (actual > 0) {
        events.add(CombatEvent(CombatEventKind.heal, actual, '回春'));
      }
    }

    // 「月华」：每回合自动蓄怒，必杀从此变成常规手段而不是奢侈品。
    if (fx.ragePerTurn > 0 && playerHp > 0) {
      final actual = _addRage(fx.ragePerTurn);
      if (actual > 0) {
        events.add(CombatEvent(CombatEventKind.rage, actual, '月华'));
      }
    }

    // 「血契」：力量是拿自己的血换的，每回合先收利息再轮到敌人。
    // 这一下可以致死——那是选择它时就已经写好的代价。
    if (fx.selfDamagePerTurn > 0 && playerHp > 0) {
      playerHp = max(0, playerHp - fx.selfDamagePerTurn);
      events.add(
        CombatEvent(CombatEventKind.selfBleed, fx.selfDamagePerTurn, '血契'),
      );
      log.insert(0, '血契夺走了 ${fx.selfDamagePerTurn} 点生命');
      if (playerHp <= 0) {
        phase = BattlePhase.lost;
        log.insert(0, '你倒下了……');
        return events;
      }
    }

    if (curseTurns > 0) {
      curseTurns--;
      if (curseTurns <= 0) {
        if (fx.cursePersists) {
          // 「瘟疫」：易伤不再一次性消失，而是每回合腐烂掉一层。
          curseStacks = max(0, curseStacks - 1);
          curseTurns = curseStacks > 0 ? 1 : 0;
        } else {
          curseStacks = 0;
        }
      }
    }
    if (healBlockTurns > 0) healBlockTurns--;

    // 消耗战惩罚的时钟：在敌人结算"这一击"之前先记上本回合，
    // 于是同一回合的预警与实际伤害读到的是同一个倍率。
    playerTurns++;
    // 惩罚生效的第一回合给一条明确提示：接下来的预警数字会一直变大，
    // 玩家该知道那不是错觉。强续航 build 的一波本来就常有 60 回合以上，
    // 这条曲线对它们不是罕见事件。
    if (def.attritionRamp > 0 && playerTurns == attritionStartTurn) {
      events.add(const CombatEvent(CombatEventKind.info, 0, '僵持：攻势增强'));
      log.insert(0, '僵持太久，${def.name} 的每一击都变得更重');
    }
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
    // 与 UI 预警走同一个函数：屏幕上写着多少，落下来就是多少。
    final total = _predictAttackDamage(isHeavy);

    var absorbed = 0;
    if (shield > 0) {
      absorbed = min(shield, total);
      shield -= absorbed;
    }
    final loss = total - absorbed;
    playerHp = max(0, playerHp - loss);
    // 即使被护盾完全挡下也要产生事件，UI 需要播放挨打反馈。
    events.add(
      CombatEvent(CombatEventKind.enemyAttack, total, isHeavy ? '重击' : null),
    );
    if (absorbed > 0) {
      events.add(CombatEvent(CombatEventKind.playerShield, absorbed));
    }

    // 「荆棘壁垒」：被护盾扛下来的伤害，有一部分会扎回敌人身上。
    if (absorbed > 0 && fx.shieldReflect > 0) {
      final reflected = (absorbed * fx.shieldReflect).round();
      if (reflected > 0) {
        log.insert(0, '荆棘反弹 $reflected 点伤害');
        _damageEnemy(reflected, events);
      }
    }
    log.insert(
      0,
      '${def.name} ${isHeavy ? '重击' : '攻击'} · 受到 $total 点伤害'
      '${absorbed > 0 ? '（护盾抵挡 $absorbed）' : ''}',
    );

    if (def.healBlockTurns > 0) {
      healBlockTurns = max(healBlockTurns, def.healBlockTurns);
      events.add(const CombatEvent(CombatEventKind.info, 0, '治疗被削弱'));
      log.insert(0, '你被诅咒：治疗效果减半');
    }

    // 「汲魂」：命中时夺走怒气。必杀是玩家唯一的翻盘点数，被抽走的那几个
    // 回合就是这类敌人真正的威胁——哪怕伤害本身不痛。
    if (def.rageDrain > 0 && rage > 0) {
      final stolen = min(rage, def.rageDrain);
      rage -= stolen;
      events.add(CombatEvent(CombatEventKind.rageDrain, stolen));
      log.insert(0, '${def.name} 夺走了 $stolen 点怒气');
    }

    if (def.shieldRegen > 0) {
      final before = enemyShield;
      enemyShield = min(def.maxHp ~/ 3, enemyShield + def.shieldRegen);
      final actual = enemyShield - before;
      if (actual > 0) {
        events.add(CombatEvent(CombatEventKind.enemyGuard, actual));
      }
    }

    turnsToAttack = enraged
        ? max(2, def.turnsPerAttack - 1)
        : def.turnsPerAttack;

    if (playerHp <= 0) {
      playerHp = 0;
      phase = BattlePhase.lost;
      log.insert(0, '你倒下了……');
    }
    return events;
  }
}
