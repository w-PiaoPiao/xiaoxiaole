// ignore_for_file: avoid_print
//
// 数值平衡报告：用简单 AI 把每一关各推演若干次，打印胜率与平均回合数，
// 用来判断难度曲线是否合理。用法：dart run tool/balance_report.dart
//
// 报告分三段：
//   1. 单关推演——出厂档案打一关，用来校准每一关本身的难度；
//   2. 整场挑战——从第一关连打到最后一关，每赢一关按策略吃掉一条强化。
//      这一段才是玩家真实经历的曲线：三选一让玩家越打越猛，
//      "最后一关还剩多少血"就是难度手感的直接读数；
//   3. 无尽模式——肉鸽层开启后的倒下波次分布。
//
// 推演逻辑本身在 `test/support/sim.dart`：测试与报告共用同一份口径
// （摆机关、同步毒藤、注入玩家的棋盘规则），否则"守卫守住的世界"会
// 和玩家真正面对的世界对不上。
import 'dart:math' as math;

import 'package:gem_battle/engine/levels.dart';

import '../test/support/sim.dart';

void _singleLevelReport(int seeds) {
  // 「最低血」是这里最重要的一列：只看打完剩多少血会掩盖过程——玩家掉到
  // 三成再补回满血，与全程不掉血的终局读数一样，但压力天差地别。前一版
  // 报告只有终局残血，于是"前四关敌人每回合输出低于玩家续航"这个失衡
  // 一直没被发现（净收支全为正，玩家在打木桩）。
  print(
    '关卡 敌人          总血  正常:胜/负/僵  回合  终局残血   最低血(均/最差)   '
    '莽夫:胜/负  回合  莽夫残血  敌出手',
  );
  for (var level = 0; level < Campaign.levels.length; level++) {
    final def = Campaign.levels[level].enemy;
    var bw = 0, bl = 0, bt = 0, bturns = 0, bu = 0, bul = 0;
    var bHp = 0, bBerserkHp = 0, bTurns = 0, bAttacks = 0;
    var bMinSum = 0.0, bMinWorst = 1.0;
    for (var seed = 1; seed <= seeds; seed++) {
      final a = fight(Campaign.levels[level], seed: seed);
      if (a.won) {
        bw++;
      } else if (a.lost) {
        bl++;
      } else {
        bt++;
      }
      bturns += a.turns;
      bHp += a.playerHp;
      bMinSum += a.minHpRatio;
      if (a.minHpRatio < bMinWorst) bMinWorst = a.minHpRatio;

      final b = fight(
        Campaign.levels[level],
        seed: seed,
        fightStyle: FightStyle.berserk,
      );
      if (b.won) {
        bu++;
      } else {
        bul++;
      }
      bTurns += b.turns;
      bBerserkHp += b.playerHp;
      bAttacks += b.enemyAttacks;
    }
    final maxHp = Campaign.player.maxHp;
    // 血量列打 totalHp：多管 BOSS 打"每管"值的话，曲线会看起来"越往后越脆"
    // （第 5 关 1870 < 第 1 关 2600），纯视觉误导。
    final hpLabel = def.phases > 1
        ? '${def.totalHp}×${def.phases}'
        : '${def.totalHp}';
    print(
      '${(level + 1).toString().padRight(5)}'
      '${def.name.padRight(12)}'
      '${hpLabel.padRight(10)}'
      '${'$bw/$bl/$bt'.padRight(13)}'
      '${(bturns / seeds).toStringAsFixed(1).padRight(5)}'
      '${'${(bHp / seeds).round()}/$maxHp'.padRight(11)}'
      '${'${(bMinSum / seeds * 100).round()}%/${(bMinWorst * 100).round()}%'.padRight(17)}'
      '${'$bu/$bul'.padRight(11)}'
      '${(bTurns / seeds).toStringAsFixed(1).padRight(6)}'
      '${'${(bBerserkHp / seeds).round()}/$maxHp'.padRight(9)}'
      '${(bAttacks / seeds).toStringAsFixed(1).padRight(9)}',
    );
  }
}

void _campaignReport(int rounds) {
  print('');
  print('整场挑战（每赢一关吃一条强化，生命按 50% 保底续到下一关）');
  print('策略    通关  第1关残血  第3关残血  终关残血  终关回合  未过卡在  典型 build');
  print('             （残血两列按全部种子均摊：没活到那一关记 0——这一列同时'
      '编码了到达率，失败越早均值越低是口径使然，不是那一关变脆了）');
  for (final style in PickStyle.values) {
    var cleared = 0;
    var hp1 = 0.0, hp3 = 0.0, hpLast = 0.0, turnsLast = 0.0;
    final failedAt = <int>[];
    Map<String, int> sample = const {};
    for (var seed = 1; seed <= rounds; seed++) {
      final result = playCampaign(seed: seed, style: style);
      if (result.cleared) {
        cleared++;
        final last = result.levels.last;
        hpLast += last.battle.playerHp / last.maxHp;
        turnsLast += last.battle.turns;
      } else {
        failedAt.add(result.failedAt + 1);
      }
      if (result.levels.isNotEmpty) {
        final first = result.levels.first;
        hp1 += first.battle.playerHp / first.maxHp;
      }
      if (result.levels.length > 2) {
        final third = result.levels[2];
        hp3 += third.battle.playerHp / third.maxHp;
      }
      sample = result.taken;
    }
    final build =
        (sample.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(4)
            .map((e) => '${e.key}x${e.value}')
            .join(' ');
    print(
      '${style.name.padRight(8)}'
      '${'$cleared/$rounds'.padRight(6)}'
      '${'${(hp1 / rounds * 100).round()}%'.padRight(11)}'
      '${'${(hp3 / rounds * 100).round()}%'.padRight(11)}'
      '${'${(hpLast / rounds * 100).round()}%'.padRight(10)}'
      '${(turnsLast / math.max(1, cleared)).toStringAsFixed(1).padRight(10)}'
      '${(failedAt.isEmpty ? '-' : failedAt.join(',')).padRight(10)}'
      '$build',
    );
  }
}

void _endlessReport(int rounds) {
  print('');
  print('无尽模式（肉鸽层开启：稀有度随波次上升 + 每 3 波保底稀有）');
  print('策略        最差  中位  最佳   典型 build');
  for (final style in [PickStyle.damage, PickStyle.survival]) {
    final fallen = <int>[];
    Map<String, int> sample = const {};
    for (var seed = 1; seed <= rounds; seed++) {
      final result = playEndless(seed: seed, style: style);
      fallen.add(result.fallenWave);
      sample = result.taken;
    }
    final sorted = [...fallen]..sort();
    final best = sorted.last - 1;
    final median = sorted[rounds ~/ 2] - 1;
    final worst = sorted.first - 1;
    final build =
        (sample.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(4)
            .map((e) => '${e.key}x${e.value}')
            .join(' ');
    print(
      '${style.name.padRight(12)}'
      '${worst.toString().padRight(6)}'
      '${median.toString().padRight(6)}'
      '${best.toString().padRight(7)}'
      '$build',
    );
    print('  各局通过波数: ${fallen.map((w) => w - 1).join(', ')}');
  }
}

void main() {
  _singleLevelReport(14);
  _campaignReport(10);
  _endlessReport(24);
}
