import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/ui/fx.dart';

/// 让视觉层推进若干帧，模拟真实渲染循环。
void advance(FxController fx, {double seconds = 1.2, double step = 1 / 60}) {
  var t = 0.0;
  while (t < seconds) {
    fx.tick(step);
    t += step;
  }
}

void main() {
  group('空洞兜底修复', () {
    test('正常情况下棋盘没有空洞', () {
      final board = BoardEngine(seed: 2)..reset();
      expect(board.countHoles(), 0);
    });

    test('兜底修复能补满人为制造的空洞', () {
      final board = BoardEngine(seed: 3)..reset();
      // 人为挖出 28 个洞，模拟「最坏情况」
      for (var i = 0; i < 28; i++) {
        board.cells[i] = null;
      }
      expect(board.countHoles(), 28);

      final starts = <int, double>{};
      final filled = board.refillHoles(spawnStartY: starts);
      expect(filled, 28);
      expect(board.countHoles(), 0);
      expect(starts.length, 28, reason: '补进来的宝石应当有入场位置');
      // 补进来的宝石都是有效颜色
      for (var i = 0; i < board.cells.length; i++) {
        expect(board.cells[i], isNotNull);
      }
    });
  });

  group('棋盘不变量', () {
    test('任何结算之后棋盘都不该出现空洞', () {
      const advisor = MoveAdvisor();
      for (var seed = 1; seed <= 6; seed++) {
        final board = BoardEngine(seed: seed)..reset();
        final battle = BattleState(def: Campaign.levels[0].enemy, levelIndex: 0);
        expect(board.countHoles(), 0, reason: 'seed=$seed 初始棋盘就不完整');

        for (var move = 0; move < 60 && !battle.isOver; move++) {
          final suggestion = advisor.suggest(board, battle);
          if (suggestion == null) {
            board.shuffleBoard();
            expect(board.countHoles(), 0, reason: 'seed=$seed 洗牌后出现空洞');
            continue;
          }
          board.swapCells(suggestion.a, suggestion.b);
          final steps = board.resolveSwap(suggestion.a, suggestion.b);
          for (final step in steps) {
            expect(board.countHoles(), 0,
                reason: 'seed=$seed move=$move combo=${step.combo} 结算后出现空洞');
            expect(step.snapshot.length, 64,
                reason: 'seed=$seed move=$move 快照不完整');
          }
          for (final step in steps) {
            battle.applyClear(step.counts, combo: step.combo, specialBonus: step.specialBonus);
          }
          if (battle.canCastUltimate) {
            battle.castUltimate();
            final ultimateSteps = board.resolveUltimate(board.index(4, 4));
            expect(ultimateSteps, isNotEmpty);
            expect(board.countHoles(), 0,
                reason: 'seed=$seed move=$move 必杀结算后出现空洞');
          }
          battle.endPlayerTurn();
        }
      }
    });

    test('快照必须与引擎棋盘逐格一致', () {
      const advisor = MoveAdvisor();
      for (var seed = 1; seed <= 8; seed++) {
        final board = BoardEngine(seed: seed)..reset();
        final battle = BattleState(def: Campaign.levels[1].enemy, levelIndex: 1);
        for (var move = 0; move < 120 && !battle.isOver; move++) {
          final suggestion = advisor.suggest(board, battle);
          if (suggestion == null) {
            board.shuffleBoard();
            continue;
          }
          board.swapCells(suggestion.a, suggestion.b);
          final steps = board.resolveSwap(suggestion.a, suggestion.b);
          if (steps.isNotEmpty) {
            final snapshot = steps.last.snapshot;
            expect(snapshot.length, 64);
            final byIndex = <int, int>{};
            for (final cell in snapshot) {
              expect(byIndex.containsKey(cell.index), isFalse,
                  reason: '快照里同一格出现两次: ${cell.index}');
              byIndex[cell.index] = cell.gemId;
            }
            for (var i = 0; i < board.cells.length; i++) {
              final gem = board.cells[i];
              expect(gem, isNotNull, reason: 'seed=$seed move=$move 引擎第 $i 格为空');
              expect(byIndex[i], gem!.id,
                  reason: 'seed=$seed move=$move 第 $i 格快照 id 与引擎不一致');
            }
          }
          for (final step in steps) {
            battle.applyClear(step.counts, combo: step.combo, specialBonus: step.specialBonus);
          }
          if (battle.canCastUltimate) {
            battle.castUltimate();
            final ultimateSteps = board.resolveUltimate(board.index(4, 4));
            for (final step in ultimateSteps) {
              expect(step.snapshot.length, 64);
            }
            expect(board.countHoles(), 0, reason: 'seed=$seed move=$move 必杀后出现空洞');
            // 快照与引擎逐格比对
            final last = ultimateSteps.last.snapshot;
            final byIndex = {for (final c in last) c.index: c.gemId};
            for (var i = 0; i < 64; i++) {
              expect(byIndex[i], board.cells[i]?.id,
                  reason: 'seed=$seed move=$move 必杀后第 $i 格不一致');
            }
          }
          battle.endPlayerTurn();
        }
      }
    });

    test('视觉层始终与引擎棋盘一致', () {
      const advisor = MoveAdvisor();
      for (var seed = 1; seed <= 4; seed++) {
        final board = BoardEngine(seed: seed)..reset();
        final battle = BattleState(def: Campaign.levels[0].enemy, levelIndex: 0);
        final fx = FxController();

        // 开局：所有宝石从上方落入
        fx.applySnapshot(board.snapshot());
        advance(fx);
        expect(fx.gems.length, 64, reason: 'seed=$seed 开局视觉层不完整');

        for (var move = 0; move < 40 && !battle.isOver; move++) {
          final suggestion = advisor.suggest(board, battle);
          if (suggestion == null) {
            board.shuffleBoard();
            fx.applySnapshot(board.snapshot());
            advance(fx);
            expect(fx.gems.length, 64, reason: 'seed=$seed 洗牌后视觉层不完整');
            continue;
          }

          // 交换动画
          board.swapCells(suggestion.a, suggestion.b);
          fx.applySnapshot(board.snapshot(), fallDuration: 0.16);
          advance(fx, seconds: 0.4);

          final steps = board.resolveSwap(suggestion.a, suggestion.b);
          for (final step in steps) {
            fx.beginClear(step.cleared);
            advance(fx, seconds: 0.3);
            fx.applySnapshot(
              step.snapshot,
              spawnStartY: step.spawnStartY,
              fallDuration: 0.30,
            );
            for (final step2 in steps) {
              battle.applyClear(step2.counts, combo: step2.combo, specialBonus: step2.specialBonus);
            }
            advance(fx, seconds: 1.5);

            final engineCount = board.cells.length - board.countHoles();
            expect(fx.gems.length, engineCount,
                reason: 'seed=$seed move=$move combo=${step.combo} 视觉层 ${fx.gems.length} '
                    '与引擎 $engineCount 不一致');
            expect(fx.dying, isEmpty, reason: 'seed=$seed move=$move 消散动画未结束');
          }
          battle.endPlayerTurn();
        }
      }
    });
  });
}
