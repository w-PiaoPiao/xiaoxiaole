/// 推演器：用落子顾问把「棋盘 → 战斗 → 胜负 → 三选一」整条链路跑通。
///
/// 这份实现同时服务两类使用者，**口径必须完全一致**：
///   - `test/simulation_test.dart`、`test/endless_test.dart`：难度回归守卫；
///   - `tool/balance_report.dart`：数值平衡报告。
///
/// 曾经两边各写一份，测试那份漏掉了机关与毒藤加成，于是"守卫守住的世界"
/// 比玩家真正面对的世界简单——机关带来的难度回归它抓不到。口径统一到
/// 这里之后，改一处两边都跟着变。
///
/// 与 `GameScreen` 对齐的五条：
///   1. 开局按关卡配置摆机关（`placeObstacles`）；
///   2. 进敌方回合前同步毒藤数量（`vineCount`）；
///   3. 玩家的棋盘规则（棱镜宗师 / 爆破工程 / 十字破空）注入 `resolveSwap`
///      与 `resolveUltimate`；
///   4. **必杀独占一回合**（选了斩月就不能再交换，敌方倒计时照常推进），
///      且破除祭坛立刻补怒气（`altarRageReward`）；
///   5. 过关血量继承先用**旧档案** maxHp 算 50% 保底 + 25% 回补，吃牌后
///      把上限增量当场补满（`_takeUpgrade` 的 grown 补偿）。
library;

import 'dart:math' as math;

import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/engine/upgrades.dart';

/// 战斗风格。
enum FightStyle {
  /// 会看情况防守的正常打法。
  balanced,

  /// 只顾输出的莽夫打法，用来检验「不防守会不会付出代价」。
  berserk,
}

/// 选强化的策略。
enum PickStyle {
  /// 关关都拿第一张（等价于随机 build）。
  first,

  /// 只认输出：能加伤害就加伤害。
  damage,

  /// 怂一点：优先保命。
  survival,
}

/// 「输出优先」会主动吃下的强化。
const damageIds = {
  'blade',
  'crit',
  'critDamage',
  'special',
  'combo',
  'curse',
  'desperate',
  'ultimate',
  // 肉鸽层：直接把伤害抬起来的牌。
  'bloodPact', 'ascetic', 'rageEngine', 'executioner',
  // 棋盘质变本质上是"同样的手数打出更多消除"，也算输出。
  'crossStrike', 'demolition', 'prismMaster',
  'plague', 'eternalCombo', 'moonBlessing',
};

/// 「保命优先」会主动吃下的强化。
const survivalIds = {
  'guard', 'harden', 'heal', 'regen', 'vitality',
  // 肉鸽层：把别的资源接进护盾的联动牌，以及专门垫身板的生存牌。
  'overcrit', 'overflowGuard', 'thornGuard',
  'mountainHeart', 'aegisWall', 'unbroken',
};

const _balancedAdvisor = MoveAdvisor();
const _berserkAdvisor = MoveAdvisor(conservative: false);

/// 按策略从三张候选里挑一张。
int pickIndex(PickStyle style, List<Upgrade> offer) {
  switch (style) {
    case PickStyle.first:
      return 0;
    case PickStyle.damage:
      // 「苦修」对输出流是陷阱：+90% 红伤的代价是把输出流顺手的护盾
      // 资源整个清零。会读卡的输出玩家会绕开它，血契这种纯买卖才拿。
      final i = offer.indexWhere(
        (u) => damageIds.contains(u.id) && u.id != 'ascetic',
      );
      return i >= 0 ? i : 0;
    case PickStyle.survival:
      // 保命玩家会读卡面：带代价的牌（自损、封盾）直接跳过，宁可拿别的。
      final safe = [
        for (final u in offer)
          if (!u.isCostly) u,
      ];
      final pool = safe.isNotEmpty ? safe : offer;
      final i = pool.indexWhere((u) => survivalIds.contains(u.id));
      return offer.indexOf(i >= 0 ? pool[i] : pool.first);
  }
}

/// 一次战斗推演的结果。
class SimResult {
  final bool won;
  final bool lost;
  final int turns;
  final int playerHp;
  final int enemyHp;
  final int enemyAttacks;

  /// 整场战斗里玩家的**最低生命比例**。
  ///
  /// 只看打完剩多少血会掩盖过程：玩家掉到三成再补回满血，与全程不掉血
  /// 的终局读数完全一样，但两者的压力天差地别。这一项才是"这一关有没有
  /// 威胁"的直接读数，也是关卡数值校准的主指标。
  final double minHpRatio;

  const SimResult({
    required this.won,
    required this.lost,
    required this.turns,
    required this.playerHp,
    required this.enemyHp,
    required this.enemyAttacks,
    this.minHpRatio = 1.0,
  });
}

/// 结算一步清除：伤害 + 祭坛怒气。交换与必杀两条路径共用，
/// 保证祭坛奖励不会被任何一条路径漏掉。
void _settleStep(
  BattleState battle,
  CascadeStep step,
  double multiplier, {
  void Function(CombatEvent event)? onEvent,
  void Function(CascadeStep step)? onStep,
}) {
  onStep?.call(step);
  for (final e in battle.applyClear(
    step.counts,
    combo: step.combo,
    specialBonus: step.specialBonus,
    multiplier: multiplier,
  )) {
    onEvent?.call(e);
  }
  // 祭坛：破一座补一口怒气——GameScreen 的连锁结算就是这么做的。
  // 漏掉它的话，带祭坛的关卡（战役 5 关、无尽 wave≥6 的 3 的倍数波）
  // 会系统性少放必杀，难度被高估。
  for (final brk in step.obstacleBreaks) {
    if (brk.kind == ObstacleKind.altar) {
      battle.grantRage(BattleState.altarRageReward);
    }
  }
}

/// 回合收尾：同步毒藤 → 推进敌方回合。与 GameScreen 的 `_finishTurn` 同一口径。
void _finishSimTurn(
  BattleState battle,
  BoardEngine board, {
  void Function(CombatEvent event)? onEvent,
}) {
  // 毒藤每一株都在给敌人加码：进敌方回合前同步一次数量。
  battle.vineCount = board.countObstacles(ObstacleKind.vine);
  for (final e in battle.endPlayerTurn()) {
    onEvent?.call(e);
  }
}

/// 用落子顾问完整推演一场战斗（一关或一波）。
///
/// [onEvent] / [onStep] 是可选的观测口：`tool/diag_balance.dart` 靠它们
/// 拿到逐事件的收支台账，而不必自己复制一条推演循环（复制版本曾与这里
/// 漂移——测试那份漏了机关，"守卫守住的世界"比玩家面对的简单）。
SimResult fight(
  LevelDef level, {
  required int seed,
  PlayerProfile profile = Campaign.player,
  int? playerHp,
  FightStyle fightStyle = FightStyle.balanced,
  int maxTurns = 400,
  void Function(CombatEvent event)? onEvent,
  void Function(CascadeStep step)? onStep,
}) {
  final board = BoardEngine(seed: seed)..reset();
  for (final entry in level.obstacles.entries) {
    board.placeObstacles(entry.key, entry.value);
  }
  final battle = BattleState(
    def: level.enemy,
    levelIndex: level.index,
    profile: profile,
    playerHp: playerHp,
    rng: math.Random(seed),
  );
  final advisor = fightStyle == FightStyle.balanced
      ? _balancedAdvisor
      : _berserkAdvisor;
  var turns = 0;
  var minHp = battle.playerHp;

  while (!battle.isOver && turns < maxTurns) {
    // 必杀独占一回合：与 GameScreen 一致，选了斩月就不能再交换——
    // 施放本身就是一次行动，敌方倒计时照常推进。让必杀免费搭在交换
    // 回合上的话，推演玩家的 DPS 会系统性偏高，所有校准窗口全部失真。
    if (battle.canCastUltimate) {
      for (final e in battle.castUltimate()) {
        onEvent?.call(e);
      }
      for (final step in board.resolveUltimate(
        board.index(BoardEngine.cols ~/ 2, BoardEngine.rows ~/ 2),
        rules: profile.boardRules,
      )) {
        _settleStep(
          battle,
          step,
          profile.ultimateMultiplier,
          onEvent: onEvent,
          onStep: onStep,
        );
      }
      _finishSimTurn(battle, board, onEvent: onEvent);
      // 每回合的血量低点只可能出现在敌方行动之后，这里取一次就够。
      if (battle.playerHp < minHp) minHp = battle.playerHp;
      turns++;
      continue;
    }
    final move = advisor.suggest(board, battle);
    if (move == null) {
      // 与真实游戏对齐：无解重排发生在上一回合末（敌方已行动过），
      // 洗牌本身不消耗玩家回合——洗完继续找步，不推进敌方。
      board.shuffleBoard();
      turns++;
      continue;
    }
    board.swapCells(move.a, move.b);
    for (final step in board.resolveSwap(
      move.a,
      move.b,
      rules: profile.boardRules,
    )) {
      _settleStep(battle, step, 1.0, onEvent: onEvent, onStep: onStep);
    }
    _finishSimTurn(battle, board, onEvent: onEvent);
    // 每回合的血量低点只可能出现在敌方行动之后，这里取一次就够。
    if (battle.playerHp < minHp) minHp = battle.playerHp;
    turns++;
  }

  return SimResult(
    won: battle.isWon,
    lost: battle.phase == BattlePhase.lost,
    turns: turns,
    playerHp: battle.playerHp,
    enemyHp: battle.enemyHp,
    enemyAttacks: battle.attackCount,
    minHpRatio: profile.maxHp <= 0
        ? 1.0
        : (minHp / profile.maxHp).clamp(0.0, 1.0),
  );
}

/// 一关的战果（整场挑战里逐关记录）。
class LevelResult {
  final SimResult battle;

  /// 这一关开始时的生命上限（残血比例要拿它当分母）。
  final int maxHp;

  const LevelResult({required this.battle, required this.maxHp});
}

/// 整场挑战的结果。
class CampaignResult {
  final bool cleared;

  /// 卡住的关卡索引；通关时为 -1。
  final int failedAt;

  /// 逐关战果（失败时只到卡住的那一关）。
  final List<LevelResult> levels;

  final Map<String, int> taken;
  final PlayerProfile profile;

  const CampaignResult({
    required this.cleared,
    required this.failedAt,
    required this.levels,
    required this.taken,
    required this.profile,
  });
}

/// 从第一关连打到最后一关：每赢一关按 [style] 吃一条强化，
/// 生命按 GameScreen 的公式（50% 保底 + 25% 回补）续到下一关。
CampaignResult playCampaign({
  required int seed,
  PickStyle style = PickStyle.first,
  FightStyle fightStyle = FightStyle.balanced,
}) {
  var profile = Campaign.player;
  var carryHp = profile.maxHp;
  final taken = <String, int>{};
  final rng = math.Random(seed * 7919);
  final levels = <LevelResult>[];

  for (var level = 0; level < Campaign.levels.length; level++) {
    final def = Campaign.levels[level];
    final result = fight(
      def,
      seed: seed * 31 + level,
      profile: profile,
      playerHp: carryHp,
      fightStyle: fightStyle,
    );
    levels.add(LevelResult(battle: result, maxHp: profile.maxHp));
    if (!result.won) {
      return CampaignResult(
        cleared: false,
        failedAt: level,
        levels: levels,
        taken: taken,
        profile: profile,
      );
    }

    // 过关奖励：抽三张、按策略吃一张（战役模式不启用稀有度分层）。
    // 血量继承与 GameScreen 同口径：先按**旧档案**的 maxHp 算「50% 保底 +
    // 25% 回补」（`_handleBattleEnd`），吃牌后再把上限增量当场补满
    // （`_takeUpgrade` 的 grown 补偿）。先 apply 再按新档案整体重算的话，
    // 拿生命上限牌的 build（山岳之躯/生命洪流）会被少算约 0.75×增量，
    // 保命流被系统性低估。
    final carried = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        result.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
    final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
    if (offer.isNotEmpty) {
      final before = profile;
      final choice = offer[pickIndex(style, offer)];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
      final grown = profile.maxHp - before.maxHp;
      carryHp = (carried + math.max(0, grown)).clamp(1, profile.maxHp).toInt();
    } else {
      carryHp = carried;
    }
  }
  return CampaignResult(
    cleared: true,
    failedAt: -1,
    levels: levels,
    taken: taken,
    profile: profile,
  );
}

/// 无尽模式推演的结果。
class EndlessResult {
  /// 倒下的波次（从 1 开始）；打穿 [maxWave] 时返回 maxWave + 1。
  final int fallenWave;

  /// 倒下的那一波是不是"打不动"——血没掉完，但回合数先耗尽。
  ///
  /// 它必须永远是 false。无尽模式的承诺是"与敌人赛跑，站到站不住为止"；
  /// 而"打不动"意味着玩家满血满盾、敌人也不掉血地磨到超时——那不是失败，
  /// 是卡住。守住这一条，就守住了 [EndlessRoster.attritionRamp] 存在的意义。
  final bool timedOut;

  final Map<String, int> taken;
  final PlayerProfile profile;

  const EndlessResult({
    required this.fallenWave,
    required this.taken,
    required this.profile,
    this.timedOut = false,
  });

  /// 通过的波数（倒下的那一波不算通过）。
  int get wavesCleared => fallenWave - 1;
}

/// 打无尽模式直到倒下。
///
/// 无尽模式启用肉鸽层：三选一带稀有度分层与保底，棋盘质变也会真正
/// 注入 `resolveSwap`——否则推演读到的强度比玩家实际体验的弱。
EndlessResult playEndless({
  required int seed,
  PickStyle style = PickStyle.damage,
  int maxWave = 60,
}) {
  var profile = Campaign.player;
  var carryHp = profile.maxHp;
  final taken = <String, int>{};
  final rng = math.Random(seed * 104729);

  for (var wave = 1; wave <= maxWave; wave++) {
    final level = EndlessRoster.levelFor(wave);
    final result = fight(
      level,
      seed: seed * 31 + wave,
      profile: profile,
      playerHp: carryHp,
    );
    if (!result.won) {
      return EndlessResult(
        fallenWave: wave,
        taken: taken,
        profile: profile,
        // 血没掉完却先耗尽了回合：这一局是"磨死"的，不是"打死"的。
        timedOut: !result.lost,
      );
    }

    // 血量继承与 GameScreen 同口径（旧档案算保底 → 吃牌 → grown 补满），
    // 详见 [playCampaign] 内的说明。
    final carried = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        result.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
    final offer = UpgradePool.roll(
      profile: profile,
      taken: taken,
      rng: rng,
      depth: wave - 1,
      roguelike: true,
    );
    if (offer.isNotEmpty) {
      final before = profile;
      final choice = offer[pickIndex(style, offer)];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
      final grown = profile.maxHp - before.maxHp;
      carryHp = (carried + math.max(0, grown)).clamp(1, profile.maxHp).toInt();
    } else {
      carryHp = carried;
    }
  }
  return EndlessResult(fallenWave: maxWave + 1, taken: taken, profile: profile);
}
