import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';

import 'support/helpers.dart';

int ix(int x, int y) => y * BoardEngine.cols + x;

/// 无三连的底棋盘，每格两个字符（类型 + 强化标记），可覆盖成普通或强化宝石。
/// 底色是五彩的：有几条用例需要"相邻两格本来就不同色"的对子。
BoardEngine boardOf(Map<int, String> overlay) => boardOfMixed(overlay);

void main() {
  group('机关的基本行为', () {
    test('被机关锁住的宝石不参与匹配', () {
      final board = boardOf({ix(0, 0): 'R.', ix(1, 0): 'R.', ix(2, 0): 'R.'});
      expect(board.findMatches(), isNotEmpty);
      lockAt(board, ix(1, 0), ObstacleKind.frost);
      expect(board.findMatches(), isEmpty, reason: '冰封打断这条三连');
    });

    test('机关不能被跨越：两侧同色也凑不成三连', () {
      final board = boardOf({
        ix(0, 0): 'R.',
        ix(1, 0): 'R.',
        ix(2, 0): 'R.',
        ix(3, 0): 'R.',
      });
      // 锁住中间一格：左边 1 格、右边 2 格，都不够三连。
      lockAt(board, ix(1, 0), ObstacleKind.vine);
      expect(board.findMatches(), isEmpty);
    });

    test('被锁住的宝石不能交换', () {
      final board = boardOf({});
      // 找一个相邻且颜色不同的对子（交换本来合法与否不重要，锁住后必须为 false）。
      final a = ix(0, 0), b = ix(1, 0);
      board.cells[b]!.type = board.cells[a]!.type == GemType.red
          ? GemType.blue
          : GemType.red;
      lockAt(board, a, ObstacleKind.frost);
      expect(board.canSwap(a, b), isFalse);
    });

    test('快照带上机关信息，且机关跟着宝石下落', () {
      final board = boardOf({});
      final lockedIndex = ix(3, 3);
      lockAt(board, lockedIndex, ObstacleKind.altar);
      final lockedId = board.cells[lockedIndex]!.id;

      final snap = board.snapshot();
      expect(snap.length, BoardEngine.cols * BoardEngine.rows);
      final entry = snap.singleWhere((s) => s.gemId == lockedId);
      expect(entry.obstacle, ObstacleKind.altar, reason: '快照必须带上机关');

      // 锤子清掉下方一格触发重力：机关宝石应当带着机关一起下落。
      final hammer = board.resolveSingleClear(ix(3, 7));
      expect(hammer, isNotEmpty);
      final moved = board.cells.where((g) => g?.id == lockedId).toList();
      expect(moved.length, 1, reason: '机关宝石仍在棋盘上');
      expect(moved.single!.obstacle, ObstacleKind.altar, reason: '下落不脱掉机关');
      expect(board.countHoles(), 0);
    });

    test('布置机关：数量正确，不覆盖强化宝石', () {
      final board = boardOf({ix(0, 0): 'Rh'})..reset();
      final placed = board.placeObstacles(ObstacleKind.frost, 3);
      expect(placed, 3);
      expect(board.countObstacles(ObstacleKind.frost), 3);
      expect(board.cells[ix(0, 0)]?.obstacle, isNull, reason: '强化宝石不挂机关');
    });

    test('克隆棋盘保留机关', () {
      final board = boardOf({});
      lockAt(board, ix(2, 2), ObstacleKind.frost);
      lockAt(board, ix(5, 6), ObstacleKind.vine);
      final copy = board.clone();
      expect(copy.countObstacles(ObstacleKind.frost), 1);
      expect(copy.countObstacles(ObstacleKind.vine), 1);
      expect(copy.obstacleAt(ix(2, 2)), ObstacleKind.frost);
      expect(copy.obstacleAt(ix(5, 6)), ObstacleKind.vine);
      expect(copy.cells[ix(2, 2)]!.locked, isTrue, reason: '克隆体也要能识别锁格');
    });

    test('克隆盘的匹配判定与真实盘一致（落子顾问据此推演）', () {
      final board = boardOf({ix(0, 0): 'R.', ix(1, 0): 'R.', ix(2, 0): 'R.'});
      lockAt(board, ix(1, 0), ObstacleKind.frost);
      expect(board.findMatches(), isEmpty);
      // 克隆盘漏掉机关时会在这里冒出假三连，顾问随后会给出一步在真实
      // 棋盘上根本走不出的建议——这正是这条用例守着的东西。
      expect(board.clone().findMatches(), isEmpty, reason: '克隆盘必须和真实盘一样看得见机关');
    });
  });

  group('破除机关', () {
    test('相邻消除破除机关，宝石保留（已被重力带走）', () {
      final board = boardOf({
        ix(0, 0): 'R.',
        ix(1, 0): 'R.',
        ix(2, 0): 'G.',
        ix(3, 0): 'R.',
        ix(4, 0): 'R.',
      });
      final lockedIndex = ix(1, 1);
      lockAt(board, lockedIndex, ObstacleKind.vine);
      final lockedId = board.cells[lockedIndex]!.id;

      // 交换 (2,0) 与 (3,0)：行首凑成 R R R 三连。
      board.swapCells(ix(2, 0), ix(3, 0));
      final steps = board.resolveSwap(ix(2, 0), ix(3, 0));
      expect(steps, isNotEmpty);

      final breaks = [for (final s in steps) ...s.obstacleBreaks];
      expect(breaks.map((b) => b.index), contains(lockedIndex));
      expect(breaks.first.kind, ObstacleKind.vine);

      final alive = board.cells.where((g) => g?.id == lockedId).toList();
      expect(alive.length, 1, reason: '破除机关不该连带清掉宝石');
      expect(alive.single!.obstacle, isNull, reason: '机关已经破除');
      expect(board.countObstacles(ObstacleKind.vine), 0);
      expect(board.countHoles(), 0);
    });

    test('强化宝石的爆炸波及也会破除机关', () {
      final board = boardOf({ix(3, 3): 'Rb', ix(3, 4): 'Y.'});
      lockAt(board, ix(4, 4), ObstacleKind.frost); // 在 3x3 波及范围内
      board.swapCells(ix(3, 3), ix(3, 4));
      final steps = board.resolveSwap(ix(3, 3), ix(3, 4));
      final breaks = [for (final s in steps) ...s.obstacleBreaks];
      expect(breaks.map((b) => b.index), contains(ix(4, 4)));
    });

    test('棋盘安静时机关不会自己消失', () {
      final board = boardOf({ix(0, 0): 'R.', ix(1, 0): 'R.', ix(2, 0): 'R.'});
      lockAt(board, ix(5, 5), ObstacleKind.altar);
      // 清掉一条与机关不相邻的三连。
      final steps = board.resolveSwap(ix(0, 0), ix(1, 0)); // 不构成交换也没关系：直接结算既有三连
      expect(steps, isNotEmpty);
      final breaks = [for (final s in steps) ...s.obstacleBreaks];
      expect(breaks, isEmpty, reason: '不相邻的消除不该破除机关');
      expect(board.obstacleAt(ix(5, 5)), ObstacleKind.altar);
    });

    test('洗牌保留机关', () {
      final board = boardOf({});
      lockAt(board, ix(2, 2), ObstacleKind.vine);
      lockAt(board, ix(5, 6), ObstacleKind.frost);
      final vineId = board.cells[ix(2, 2)]!.id;
      board.shuffleBoard();
      expect(board.countObstacles(ObstacleKind.vine), 1);
      expect(board.countObstacles(ObstacleKind.frost), 1);
      final still = board.cells.where((g) => g?.id == vineId).toList();
      expect(still.length, 1);
      expect(still.single!.obstacle, ObstacleKind.vine);
      expect(board.countHoles(), 0);
    });
  });

  group('锤子（引擎入口）', () {
    test('点普通宝石：清掉它并结算连锁', () {
      final board = boardOf({});
      final steps = board.resolveSingleClear(ix(3, 3));
      expect(steps, isNotEmpty);
      expect(steps.first.cleared.single.index, ix(3, 3));
      expect(steps.first.combo, 1);
    });

    test('点机关宝石：连机关一起砸掉', () {
      final board = boardOf({});
      lockAt(board, ix(3, 3), ObstacleKind.frost);
      final steps = board.resolveSingleClear(ix(3, 3));
      expect(steps.first.obstacleBreaks.single.index, ix(3, 3));
      expect(steps.first.obstacleBreaks.single.kind, ObstacleKind.frost);
      expect(steps.first.cleared.single.index, ix(3, 3));
      expect(board.countObstacles(ObstacleKind.frost), 0);
    });

    test('点强化宝石：直接引爆它的范围', () {
      final board = boardOf({ix(3, 3): 'Rb'});
      final steps = board.resolveSingleClear(ix(3, 3));
      final cleared = {for (final c in steps.first.cleared) c.index};
      expect(cleared, contains(ix(3, 3)));
      expect(steps.first.activations.single.kind, SpecialKind.burst);
      expect(cleared.length, greaterThanOrEqualTo(9), reason: '爆裂范围 3x3');
    });

    test('点空洞不会结算（防御性）', () {
      final board = boardOf({});
      board.cells[ix(0, 0)] = null;
      expect(board.resolveSingleClear(ix(0, 0)), isEmpty);
      expect(board.resolveSingleClear(-1), isEmpty);
      expect(board.resolveSingleClear(999), isEmpty);
    });
  });

  group('机关与战斗绑定', () {
    final def = Campaign.levels[0].enemy;

    BattleState battleWith({int vines = 0}) =>
        BattleState(def: def, levelIndex: 0)..vineCount = vines;

    test('毒藤让敌人攻击变重，预警与实伤一致', () {
      final plain = battleWith();
      final vined = battleWith(vines: 2);
      expect(plain.incomingDamage, def.attack);
      expect(
        vined.incomingDamage,
        (def.attack * 1.10).round(),
        reason: '两株毒藤 = 攻击 +10%',
      );

      for (var i = 0; i < def.turnsPerAttack; i++) {
        vined.endPlayerTurn();
      }
      expect(
        Campaign.player.maxHp - vined.playerHp,
        vined.incomingDamage,
        reason: '预警是多少，落下来就该是多少',
      );
    });

    test('毒藤清掉后加成立刻失效', () {
      final state = battleWith(vines: 3);
      expect(state.incomingDamage, greaterThan(def.attack));
      state.vineCount = 0;
      expect(state.incomingDamage, def.attack);
    });

    test('祭坛奖励：grantRage 受怒气上限约束', () {
      final state = battleWith();
      expect(state.grantRage(20), 20);
      state.rage = state.profile.maxRage - 5;
      expect(state.grantRage(20), 5, reason: '只涨得下 5 点');
      expect(state.rage, state.profile.maxRage);
    });
  });

  group('无尽模式的机关配置', () {
    test('前 3 波没有机关，第 4 波起出现', () {
      for (final wave in [1, 2, 3]) {
        expect(EndlessRoster.obstaclesFor(wave), isEmpty, reason: 'wave=$wave');
      }
      expect(EndlessRoster.obstaclesFor(4), isNotEmpty);
    });

    test('机关数量随波次单调增加并封顶，毒藤不超过 3 株', () {
      int total(int wave) =>
          EndlessRoster.obstaclesFor(wave).values.fold(0, (a, b) => a + b);
      expect(total(7), greaterThan(total(4)));
      expect(total(13), greaterThan(total(7)));
      expect(total(40), total(13), reason: '封顶后不再增加');
      for (var wave = 1; wave <= 60; wave++) {
        final vines = EndlessRoster.obstaclesFor(wave)[ObstacleKind.vine] ?? 0;
        expect(vines, lessThanOrEqualTo(3), reason: 'wave=$wave 毒藤过多');
      }
    });

    test('关卡包装把机关带进 LevelDef', () {
      expect(EndlessRoster.levelFor(4).obstacles, isNotEmpty);
      expect(EndlessRoster.levelFor(1).obstacles, isEmpty);
      // 战役后期关卡也配了机关。
      expect(Campaign.levels[2].obstacles, isNotEmpty);
      expect(Campaign.levels[5].obstacles, isNotEmpty);
    });
  });
}
