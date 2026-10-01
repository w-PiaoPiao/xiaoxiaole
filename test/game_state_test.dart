import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/app_settings.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/endless.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/upgrades.dart';
import 'package:gem_battle/ui/battle_view.dart';
import 'package:gem_battle/ui/board_view.dart';
import 'package:gem_battle/ui/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget.dart';

/// 一局的成长链路：吃强化、用道具、放必杀、恢复存档、重开一局。
///
/// 这几条都是"玩家点得到、但一帧不看就会静默坏掉"的路径——它们不涉及
/// 随机棋盘，只依赖 GameScreen 自己的状态机，所以可以直接把战斗置成
/// 想要的局面（例如敌人空血），再断言面板与状态的变化。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 起一局并跳过开场卡，返回这一局的战斗状态。
  Future<BattleState> pumpRun(
    WidgetTester tester, {
    required AppSettings settings,
    int startLevel = 0,
    GameMode mode = GameMode.campaign,
    ResumeData? resume,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          settings: settings,
          mode: mode,
          startLevel: startLevel,
          resume: resume,
        ),
      ),
    );
    await advance(tester, 3.0); // 等开场卡自动关闭
    return tester.widget<BattleView>(find.byType(BattleView)).battle;
  }

  /// 把这一局置成胜利，并等结算面板出现。
  Future<void> winRun(WidgetTester tester, BattleState battle) async {
    battle.enemyHp = 0;
    battle.phase = BattlePhase.won;
    await waitFor(tester, find.text('胜利'));
  }

  testWidgets('胜利后三选一：吃一张牌进入下一关，强化写进存档', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(tester, settings: settings);
    expect(battle.def.name, Campaign.levels[0].enemy.name);

    await winRun(tester, battle);
    expect(find.text('选择一项强化'), findsOneWidget, reason: '战役胜利要发三张牌');

    // 三张卡的名字都来自强化池；点第一张。
    final names = {for (final u in UpgradePool.all) u.name};
    final cards = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && names.contains(w.data),
    );
    expect(cards, findsNWidgets(3), reason: '应当正好三张候选');

    await tester.tap(cards.first);
    await advance(tester, 3.0);

    final next = tester.widget<BattleView>(find.byType(BattleView)).battle;
    expect(next.isOver, isFalse, reason: '吃过牌应当直接开下一关');
    expect(next.def.name, Campaign.levels[1].enemy.name);
    expect(settings.resume, isNotNull, reason: '换关要把进行中的一局写进存档');
    expect(settings.resume!.level, 1);
    expect(settings.resume!.upgrades.length, 1, reason: '刚吃的那张牌要跟着存档走');
  });

  testWidgets('凝滞：把敌方出手推后一回合，库存立刻写进存档', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(tester, settings: settings);

    // 倒计时先压到 1：满格时凝滞不生效，也不该消耗道具。
    battle.turnsToAttack = 1;
    await tester.pump();
    await tester.tap(find.text('凝滞'));
    await advance(tester, 0.3);

    expect(battle.turnsToAttack, 2, reason: '凝滞应当把倒计时推后一回合');
    expect(
      settings.resume!.items['stall'],
      0,
      reason: '用掉的道具必须立刻写档，否则重进游戏会"复活"',
    );
  });

  testWidgets('凝滞在倒计时满格时不消耗道具', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(tester, settings: settings);
    expect(battle.turnsToAttack, battle.def.turnsPerAttack, reason: '开局倒计时是满的');

    await tester.tap(find.text('凝滞'));
    await advance(tester, 0.3);

    expect(battle.turnsToAttack, battle.def.turnsPerAttack);
    expect(settings.resume!.items['stall'], 1, reason: '没推迟成功就不该扣道具');
  });

  testWidgets('必杀：进入瞄准后点棋盘落点，怒气清空并结算十字', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(tester, settings: settings);

    battle.rage = battle.ultimateCost;
    // 游戏里怒气是被结算流程 setState 刷新的；测试直接改状态后，用一次
    // 棋盘点击触发重建，必杀按钮才会从禁用变成可用。
    await tester.tapAt(tester.getCenter(find.byType(BoardView)));
    await advance(tester, 0.4);
    await tester.tap(find.text('斩月'));
    await advance(tester, 0.3);
    expect(find.text('取消'), findsOneWidget, reason: '点斩月应当进入瞄准态');

    final before = battle.enemyHp;
    await tester.tapAt(tester.getCenter(find.byType(BoardView)));
    // 必杀在动画开始之前就把怒气扣掉了；而落点的十字会顺带清掉黄宝石、
    // 再把怒气补回来（棋盘是随机的，补多少不可预测），所以趁结算还没发生
    // 先把"消耗"这件事断言掉。
    await tester.pump(const Duration(milliseconds: 16));
    expect(battle.rage, lessThan(battle.ultimateCost), reason: '必杀消耗怒气');

    await advance(tester, 4.0);
    expect(battle.enemyHp, lessThan(before), reason: '落点结算应当打到敌人');
    expect(find.text('取消'), findsNothing, reason: '放完必杀要退出瞄准态');
  });

  testWidgets('恢复存档：关卡、继承生命与剩余道具都还原', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(
      tester,
      settings: settings,
      mode: GameMode.endless,
      resume: const ResumeData(
        mode: GameMode.endless,
        level: 4,
        carryHp: 123,
        upgrades: {'blade': 2},
        items: {'hammer': 3},
      ),
    );

    expect(battle.def.name, EndlessRoster.enemyFor(5).name, reason: '接着第 5 波打');
    expect(battle.playerHp, 123, reason: '继承生命要原样带过来');
    expect(
      battle.profile.redDamage,
      greaterThan(Campaign.player.redDamage),
      reason: '存档里的强化要继续生效',
    );
    expect(find.text('x3'), findsOneWidget, reason: '剩余道具数量要还原');
  });

  testWidgets('重开一局：清空强化并回到第一关', (tester) async {
    final settings = AppSettings();
    await settings.load();
    final battle = await pumpRun(tester, settings: settings);
    await winRun(tester, battle);

    final names = {for (final u in UpgradePool.all) u.name};
    final cards = find.byWidgetPredicate(
      (w) => w is Text && w.data != null && names.contains(w.data),
    );
    await tester.tap(cards.first);
    await advance(tester, 3.0);
    expect(
      tester.widget<BattleView>(find.byType(BattleView)).battle.def.name,
      Campaign.levels[1].enemy.name,
    );

    // 打开暂停菜单 → 重开一局（清空强化）。
    await tester.tap(find.byTooltip('菜单与设置'));
    await advance(tester, 0.5);
    expect(find.text('暂停'), findsOneWidget);
    await tester.tap(find.text('重开一局（清空强化）'));
    await advance(tester, 3.0);

    final restarted = tester.widget<BattleView>(find.byType(BattleView)).battle;
    expect(restarted.def.name, Campaign.levels[0].enemy.name, reason: '回到第一关');
    expect(restarted.playerHp, restarted.profile.maxHp, reason: '满血重来');

    // 强化清空后，菜单里的按钮文案也会变回「回到第一关」。
    await tester.tap(find.byTooltip('菜单与设置'));
    await advance(tester, 0.5);
    expect(find.text('回到第一关'), findsOneWidget);
  });
}
