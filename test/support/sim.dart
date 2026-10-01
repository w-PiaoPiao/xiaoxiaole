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
/// 与 `GameScreen` 对齐的三条：
///   1. 开局按关卡配置摆机关（`placeObstacles`）；
///   2. 进敌方回合前同步毒藤数量（`vineCount`）；
///   3. 玩家的棋盘规则（棱镜宗师 / 爆破工程 / 十字破空）注入 `resolveSwap`
///      与 `resolveUltimate`。
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
  // 肉鸽层：把别的资源接进护盾的联动牌。
  'overcrit', 'overflowGuard', 'thornGuard',
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

  const SimResult({
    required this.won,
    required this.lost,
    required this.turns,
    required this.playerHp,
    required this.enemyHp,
    required this.enemyAttacks,
  });
}

/// 用落子顾问完整推演一场战斗（一关或一波）。
SimResult fight(
  LevelDef level, {
  required int seed,
  PlayerProfile profile = Campaign.player,
  int? playerHp,
  FightStyle fightStyle = FightStyle.balanced,
  int maxTurns = 400,
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

  while (!battle.isOver && turns < maxTurns) {
    final move = advisor.suggest(board, battle);
    if (move == null) {
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
      battle.applyClear(
        step.counts,
        combo: step.combo,
        specialBonus: step.specialBonus,
      );
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
    // 毒藤每一株都在给敌人加码：与 GameScreen 同一口径（进敌方回合前同步）。
    battle.vineCount = board.countObstacles(ObstacleKind.vine);
    battle.endPlayerTurn();
    turns++;
  }

  return SimResult(
    won: battle.isWon,
    lost: battle.phase == BattlePhase.lost,
    turns: turns,
    playerHp: battle.playerHp,
    enemyHp: battle.enemyHp,
    enemyAttacks: battle.attackCount,
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
    final offer = UpgradePool.roll(profile: profile, taken: taken, rng: rng);
    if (offer.isNotEmpty) {
      final choice = offer[pickIndex(style, offer)];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
    }
    carryHp = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        result.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
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

  final Map<String, int> taken;
  final PlayerProfile profile;

  const EndlessResult({
    required this.fallenWave,
    required this.taken,
    required this.profile,
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
      return EndlessResult(fallenWave: wave, taken: taken, profile: profile);
    }

    final offer = UpgradePool.roll(
      profile: profile,
      taken: taken,
      rng: rng,
      depth: wave - 1,
      roguelike: true,
    );
    if (offer.isNotEmpty) {
      final choice = offer[pickIndex(style, offer)];
      profile = choice.apply(profile);
      taken[choice.id] = (taken[choice.id] ?? 0) + 1;
    }
    carryHp = math.min(
      profile.maxHp,
      math.max(
        (profile.maxHp * 0.5).round(),
        result.playerHp + (profile.maxHp * 0.25).round(),
      ),
    );
  }
  return EndlessResult(fallenWave: maxWave + 1, taken: taken, profile: profile);
}
