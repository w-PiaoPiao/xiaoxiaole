import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/ui/battle_view.dart';
import 'package:gem_battle/ui/game_screen.dart';
import 'package:gem_battle/ui/hud.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget.dart';

/// 一局的流程状态机：这里守的是"玩家永远有路可走"。
///
/// 结算面板上的「关卡选择」会把面板收起来、换成暂停菜单；如果关掉菜单后
/// 不把结算面板放回来，玩家就会卡在一个没有出口的状态里——棋盘因为
/// `battle.isOver` 完全不可点，兜底逻辑又被一次性锁挡住，屏幕上什么都没有。
///
/// 这里不去真打一局：棋盘是随机的，落子顾问在残血时还会优先治疗，
/// "打到战败"本身就成了碰运气。直接把战斗置成败北，走的是同一条
/// 兜底巡检 → 结算 → 菜单的路径，断言却能稳定复现。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 起一局，并把这一局置成已经输掉的样子。
  Future<void> pumpLostRun(WidgetTester tester, {int level = 5}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: GameScreen(startLevel: level)));
    await advance(tester, 3.0); // 等开场卡自动关闭

    final battle = tester.widget<BattleView>(find.byType(BattleView)).battle;
    battle.playerHp = 0;
    battle.phase = BattlePhase.lost;
    await waitFor(tester, find.text('败北'));
  }

  testWidgets('结算面板点「关卡选择」再关掉菜单，结算面板会回来', (tester) async {
    await pumpLostRun(tester);
    expect(find.text('败北'), findsOneWidget, reason: '空转巡检应该把结算面板补上');

    // 结算 → 关卡选择 → 暂停菜单 → 继续游戏
    await tester.tap(find.text('关卡选择'));
    await advance(tester, 0.8);
    expect(find.text('暂停'), findsOneWidget, reason: '「关卡选择」应该打开暂停菜单');

    await tester.tap(find.text('继续游戏'));
    await advance(tester, 0.8);

    expect(
      find.text('败北'),
      findsOneWidget,
      reason: '关掉菜单必须回到结算面板，否则玩家卡在既没有面板、棋盘又点不动的状态',
    );
  });

  testWidgets('战败结算面板给出重试、回第一关与关卡选择', (tester) async {
    await pumpLostRun(tester);

    expect(find.text('重试本关'), findsOneWidget);
    expect(find.text('回到第一关'), findsOneWidget);
    expect(find.text('关卡选择'), findsOneWidget);
    // 没有 onExitToMenu 时不该出现"回到主菜单"（预览 / 测试场景）。
    expect(find.text('回到主菜单'), findsNothing);
  });

  testWidgets('重试本关会重新开一局，棋盘恢复可玩', (tester) async {
    await pumpLostRun(tester);

    await tester.tap(find.text('重试本关'));
    await advance(tester, 3.0);

    final battle = tester.widget<BattleView>(find.byType(BattleView)).battle;
    expect(battle.isOver, isFalse, reason: '重试后应该是一局全新的战斗');
    expect(battle.playerHp, greaterThan(0));
    expect(find.text('败北'), findsNothing);
  });

  testWidgets('震屏起落不重建战斗区子树（血条不重播填充动画）', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(startLevel: 0)),
    );
    await advance(tester, 3.0); // 等开场卡自动关闭

    final fx = tester.widget<BattleView>(find.byType(BattleView)).fx;
    final barBefore = tester.element(find.byType(EnergyBar).first);

    // 走一遍"消除 → 震屏 → 衰减归零"：这正是每次移动都会发生的路径。
    // 曾经震屏是有无切换 widget 类型的（Transform ↔ 原始子树），归零那
    // 一刻整棵子树被重建，血条的 TweenAnimationBuilder 从 0 重播一遍，
    // 看起来就是每次移动 HUD 都在从左往右重刷。
    fx.shakeBy(26);
    await advance(tester, 0.6);

    final barAfter = tester.element(find.byType(EnergyBar).first);
    expect(
      identical(barBefore, barAfter),
      isTrue,
      reason: '震屏起落不该重建战斗区：重建会让血条/回合点动画从头再播',
    );
  });

  testWidgets('多管血 BOSS 的血条旁显示剩余管数', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 第 5 关的深渊魔女是三管血。
    await tester.pumpWidget(const MaterialApp(home: GameScreen(startLevel: 4)));
    await advance(tester, 3.0);

    expect(
      find.text('×3'),
      findsOneWidget,
      reason: '血条后面要挂 ×N 徽标，N 是剩余管数',
    );
  });

  testWidgets('单管敌人不显示 ×N 徽标', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(startLevel: 0)));
    await advance(tester, 3.0);

    expect(
      find.textContaining('×'),
      findsNothing,
      reason: '普通敌人不该出现多管血标记',
    );
  });
}
