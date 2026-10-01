import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/app_settings.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/items.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('凝滞', () {
    final def = Campaign.levels[0].enemy;

    test('把敌人的出手倒计时往后推一回合（危机关头的救命手段）', () {
      final state = BattleState(def: def, levelIndex: 0);
      state.turnsToAttack = 1; // 敌人即将出手——凝滞正是为这一刻准备的
      expect(state.delayEnemyAttack(), 1);
      expect(state.turnsToAttack, 2);

      // 再推一次就回到满格：上限是一个完整周期，推不出更长的空档。
      expect(state.delayEnemyAttack(), 1);
      expect(state.turnsToAttack, def.turnsPerAttack);
      expect(state.delayEnemyAttack(), 0, reason: '满格后不再叠加');

      // 照常推进：被推迟后，敌人要等满一个周期才出手。
      for (var i = 0; i < def.turnsPerAttack - 1; i++) {
        state.endPlayerTurn();
      }
      expect(state.attackCount, 0, reason: '被推迟了，敌人还没出手');
      state.endPlayerTurn();
      expect(state.attackCount, 1);
    });

    test('倒计时已满时不生效（这时道具不该被消耗）', () {
      final state = BattleState(def: def, levelIndex: 0);
      expect(state.turnsToAttack, def.turnsPerAttack);
      expect(state.delayEnemyAttack(), 0);
    });

    test('战斗结束后不再生效', () {
      final state = BattleState(def: def, levelIndex: 0);
      state.enemyHp = 0;
      state.phase = BattlePhase.won;
      expect(state.delayEnemyAttack(), 0);
    });
  });

  group('锤子与战斗结算', () {
    test('砸掉红宝石后伤害照常结算', () {
      final level = Campaign.levels[0];
      final board = BoardEngine(seed: 3)..reset();
      final battle = BattleState(def: level.enemy, levelIndex: 0);

      final redIndex = board.cells.indexWhere((g) => g?.type == GemType.red);
      expect(redIndex, isNot(-1));

      final steps = board.resolveSingleClear(redIndex);
      expect(steps, isNotEmpty);
      for (final step in steps) {
        battle.applyClear(
          step.counts,
          combo: step.combo,
          specialBonus: step.specialBonus,
        );
      }
      expect(
        level.enemy.maxHp - battle.enemyHp,
        greaterThanOrEqualTo(Campaign.player.redDamage),
      );
    });

    test('锤子清掉的机关按种类给出战斗反馈（祭坛 → 怒气）', () {
      final board = BoardEngine(seed: 5)..reset();
      final lockedIndex = board.cells.indexWhere(
        (g) => g != null && !g.isSpecial,
      );
      board.cells[lockedIndex]!.obstacle = ObstacleKind.altar;

      final battle = BattleState(def: Campaign.levels[0].enemy, levelIndex: 0);
      final steps = board.resolveSingleClear(lockedIndex);
      final breaks = [for (final s in steps) ...s.obstacleBreaks];
      expect(breaks.single.kind, ObstacleKind.altar);

      // GameScreen 把祭坛破除翻译成怒气；这里验证奖励接口本身。
      expect(battle.grantRage(20), 20);
    });
  });

  group('道具库存', () {
    test('补足到每样一个，且只补不削', () {
      final stocked = refillItems({'hammer': 3, 'shuffle': 0});
      expect(stocked['hammer'], 3, reason: '多出来的保持原样');
      expect(stocked['shuffle'], 1);
      expect(stocked['stall'], 1);
      expect(stocked.length, ItemKind.values.length);
    });
  });

  group('道具存档', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('道具库存写入后能原样读回', () async {
      final settings = AppSettings();
      await settings.load();
      settings.saveResume(
        const ResumeData(
          mode: GameMode.endless,
          level: 4,
          carryHp: 200,
          upgrades: {'blade': 1},
          items: {'hammer': 1, 'shuffle': 2, 'stall': 1},
        ),
      );

      final other = AppSettings();
      await other.load();
      final resume = other.resume!;
      expect(resume.items['hammer'], 1);
      expect(resume.items['shuffle'], 2);
      expect(resume.items['stall'], 1);
      expect(resume.upgrades['blade'], 1, reason: '强化不受影响');
    });

    test('旧存档没有 items 键时按空库存处理', () async {
      final payload = jsonEncode({
        'mode': 'campaign',
        'level': 2,
        'hp': 120,
        'upgrades': {'blade': 1},
      });
      SharedPreferences.setMockInitialValues({'progress.resume': payload});

      final settings = AppSettings();
      await settings.load();
      expect(settings.resume, isNotNull);
      expect(settings.resume!.items, isEmpty, reason: '开局会按默认补足');
      expect(settings.resume!.upgrades['blade'], 1);
    });

    test('损坏的道具数量被清洗（负数 / 字符串 / 超大数）', () async {
      final payload = jsonEncode({
        'mode': 'campaign',
        'level': 1,
        'hp': 100,
        'upgrades': <String, int>{},
        'items': {'hammer': -3, 'shuffle': 'many', 'stall': 999, 'ok': 2},
      });
      SharedPreferences.setMockInitialValues({'progress.resume': payload});

      final settings = AppSettings();
      await settings.load();
      final items = settings.resume!.items;
      expect(items.containsKey('hammer'), isFalse, reason: '负数丢弃');
      expect(items.containsKey('shuffle'), isFalse, reason: '类型不符丢弃');
      expect(items['stall'], 9, reason: '超大数夹到上限');
      expect(items['ok'], 2);
    });
  });
}
