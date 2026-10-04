// ignore_for_file: avoid_print
//
// 收支台账：把一局的**收入与支出**摊开看——玩家每回合拿到多少护盾/治疗、
// 敌人每回合打掉多少、各色宝石的消除量、必杀频率。用法：
//
//     dart run tool/diag_balance.dart
//
// 它回答的是 `balance_report.dart` 答不了的那类问题："为什么这一关没有压力"
// 只看胜率是看不出来的——前一版报告里前四关的终局残血是 96%~100%，而真实
// 原因是**敌人每回合的输出（19~61）低于玩家的续航（42~71）**，净收支全为
// 正，玩家在打木桩。这份台账把那一列"净"直接打出来，失衡一眼可见。
//
// 改关卡数值时的用法：先看「净」是不是正的（正 = 玩家在打木桩），再看
// 「续航/回合」——它决定敌人 DPS 要提到多少才能形成压力。
//
// 推演本身走 `test/support/sim.dart` 的 [fight]（事件经 onEvent/onStep 回调
// 汇入台账）。**这里不允许再出现一份手写推演循环**：历史上两边各写一份，
// 工具那份漏了机关同步，台账里的世界比玩家面对的简单——口径永远只改一处。
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';

import '../test/support/sim.dart';

class Stats {
  int damageDealt = 0;
  int shieldGained = 0;
  int healed = 0;
  int hpLost = 0;
  int enemyAttacks = 0;
  int enemyDamage = 0;
  int enemyHealed = 0;
  int turns = 0;
  int ultimates = 0;
  final Map<GemType, int> cleared = {for (final t in GemType.values) t: 0};
}

/// 推演一局并把逐事件/逐步的账目汇入 [Stats]。
Stats run(
  LevelDef level, {
  required int seed,
  PlayerProfile profile = Campaign.player,
  FightStyle style = FightStyle.balanced,
}) {
  final s = Stats();
  final result = fight(
    level,
    seed: seed,
    profile: profile,
    fightStyle: style,
    onEvent: (e) => _tally(s, e),
    onStep: (step) =>
        step.counts.forEach((t, n) => s.cleared[t] = s.cleared[t]! + n),
  );
  s.turns = result.turns;
  return s;
}

void _tally(Stats s, CombatEvent e) {
  switch (e.kind) {
    case CombatEventKind.playerDamage:
      s.damageDealt += e.amount;
    case CombatEventKind.shieldGain:
      s.shieldGained += e.amount;
    case CombatEventKind.heal:
      s.healed += e.amount;
    case CombatEventKind.ultimate:
      s.ultimates++;
    case CombatEventKind.enemyAttack:
      s.enemyAttacks++;
      s.enemyDamage += e.amount;
    case CombatEventKind.enemyDrain:
      s.enemyHealed += e.amount;
    default:
      // 被敌方护盾吃掉的伤害不计入"实际掉血"，其余事件与本报告无关。
      break;
  }
}

void _row(String label, Stats s, EnemyDef def) {
  final t = s.turns == 0 ? 1 : s.turns;
  String col(int value, [int width = 4]) =>
      (value ~/ t).toString().padLeft(width);
  final sustain = s.shieldGained + s.healed;
  final c = s.cleared;
  print(
    '$label'
    '回合 ${s.turns.toString().padLeft(3)}'
    '  输出/回合 ${col(s.damageDealt)}'
    '  吃伤/回合 ${col(s.enemyDamage)}'
    '  续航/回合 ${col(sustain)}'
    '  净 ${col(sustain - s.enemyDamage, 5)}'
    '  必杀 ${s.ultimates.toString().padLeft(2)}'
    '  敌出手 ${s.enemyAttacks.toString().padLeft(2)}'
    '  每管血 ${def.maxHp}',
  );
  print(
    '${''.padRight(label.length)}'
    '消除: 红${c[GemType.red]} 蓝${c[GemType.blue]} 绿${c[GemType.green]} '
    '黄${c[GemType.yellow]} 紫${c[GemType.purple]}'
    '   紫/回合 ${(c[GemType.purple]! / t).toStringAsFixed(2)}',
  );
}

/// 把逐种子台账平均成一份（整除近似，足够看趋势）。
Stats _average(List<Stats> runs) {
  final n = runs.length;
  final scaled = Stats();
  for (final s in runs) {
    scaled.damageDealt += s.damageDealt;
    scaled.shieldGained += s.shieldGained;
    scaled.healed += s.healed;
    scaled.enemyDamage += s.enemyDamage;
    scaled.enemyAttacks += s.enemyAttacks;
    scaled.turns += s.turns;
    scaled.ultimates += s.ultimates;
    s.cleared.forEach((k, v) => scaled.cleared[k] = scaled.cleared[k]! + v);
  }
  scaled.damageDealt = scaled.damageDealt ~/ n;
  scaled.shieldGained = scaled.shieldGained ~/ n;
  scaled.healed = scaled.healed ~/ n;
  scaled.enemyDamage = scaled.enemyDamage ~/ n;
  scaled.enemyAttacks = scaled.enemyAttacks ~/ n;
  scaled.turns = scaled.turns ~/ n;
  scaled.ultimates = scaled.ultimates ~/ n;
  for (final k in GemType.values) {
    scaled.cleared[k] = (scaled.cleared[k] ?? 0) ~/ n;
  }
  return scaled;
}

void main() {
  const seeds = 10;
  print('=== 战役十三关（出厂档案，正常打法均值） ===');
  for (var i = 0; i < Campaign.levels.length; i++) {
    final level = Campaign.levels[i];
    final runs = [
      for (var seed = 1; seed <= seeds; seed++) run(level, seed: seed),
    ];
    print('');
    print('第 ${i + 1} 关 · ${level.enemy.name}'
        '（总血 ${level.enemy.totalHp}，${level.enemy.phases} 管，'
        '攻击 ${level.enemy.attack}/${level.enemy.turnsPerAttack} 回合）');
    _row('  正常', _average(runs), level.enemy);
  }

  print('');
  print('=== 无尽模式逐波（出厂档案，正常打法） ===');
  for (final wave in [1, 3, 5, 8, 10, 12, 15, 18, 20, 25, 30]) {
    final level = EndlessRoster.levelFor(wave);
    final runs = [
      for (var seed = 1; seed <= 6; seed++) run(level, seed: seed),
    ];
    print('');
    print('第 $wave 波 · ${level.enemy.name}'
        '（总血 ${level.enemy.totalHp}，${level.enemy.phases} 管，'
        '攻击 ${level.enemy.attack}/${level.enemy.turnsPerAttack} 回合）');
    _row('  正常', _average(runs), level.enemy);
  }
}
