// 整屏 UI 预览：按真实手机尺寸渲染 GameScreen，把关键界面状态截成 PNG，
// 用来检查排版、层级与触控目标——不必反复在真机上抓图。
//
// 用法：flutter test tool/ui_preview.dart
// 产物：build/ui_preview/*.png
//
// 会同时在多种屏幕尺寸 / 字体缩放下渲染：任何溢出（RenderFlex overflow）
// 都会作为测试失败抛出，小屏适配问题因此能在提交前被发现。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/app_settings.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/board.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/engine/move_advisor.dart';
import 'package:gem_battle/ui/battle_view.dart';
import 'package:gem_battle/ui/board_view.dart';
import 'package:gem_battle/ui/game_screen.dart';
import 'package:gem_battle/ui/main_menu.dart';
import 'package:gem_battle/ui/sfx.dart';

import 'package:gem_battle/ui/paint_utils.dart';
import 'package:gem_battle/ui/palette.dart';

/// macOS 自带、含完整中文字形的字体。测试环境默认字体没有中文字形，
/// 不加载的话截图里全是方块，看不出真实排版。
const _cjkFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';

/// 复刻 main.dart 的应用外壳，保证预览与实际运行一致。
Widget _app({double textScale = 1.0}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'CJK',
      scaffoldBackgroundColor: Palette.bgDeep,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.gold,
        brightness: Brightness.dark,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      // 与 main.dart 一致：游戏 HUD 是固定比例的几何布局，字号上限 1.3 倍。
      child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
    ),
    home: const GameScreen(),
  );
}

/// 主菜单的外壳：与 [_app] 一致的主题与字号限幅，home 换成主菜单。
Widget _menuApp({double textScale = 1.0}) {
  final settings = AppSettings();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'CJK',
      scaffoldBackgroundColor: Palette.bgDeep,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.gold,
        brightness: Brightness.dark,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
    ),
    home: MainMenuScreen(settings: settings, sfx: SfxController()),
  );
}

class _Shot {
  final GlobalKey key = GlobalKey();
  final Widget child;

  _Shot(this.child);

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui_preview/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('已生成 build/ui_preview/$name.png');
  }
}

/// 设置一块虚拟屏幕。[logical] 为逻辑尺寸，[topInset] 为状态栏/刘海高度（逻辑像素）。
void _screen(WidgetTester tester, Size logical, {double topInset = 0, double dpr = 2.0}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
  tester.view.padding = FakeViewPadding(top: topInset * dpr);
  tester.view.viewPadding = FakeViewPadding(top: topInset * dpr);
  addTearDown(tester.view.reset);
}

/// 分步推进时间：GameScreen 把每帧 dt 截到 0.12 秒以防低帧率下动画失真，
/// 一次 pump 一大段时间只会走 0.12 秒，因此这里按 100ms 逐帧推进。
Future<void> _advance(WidgetTester tester, double seconds) async {
  final steps = (seconds / 0.1).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 把还在跑的动画与定时器彻底放干净。
///
/// 测试结束时会检查"是否还有定时器在等"——一段长连锁（尤其必杀清十字带出的
/// 连环）可以在最后几帧里不断排出新的延时，最后一张截图之后必须留足时间
/// 让它们全部跑完，否则会以 "A Timer is still pending" 收场。
Future<void> _quiet(WidgetTester tester) async {
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 棋盘拆成了「静态底层 + 动态层」两个 CustomPaint，取第一个即可
/// （两者尺寸位置完全一致）。
Rect _boardRect(WidgetTester tester) => tester.getRect(
      find.descendant(of: find.byType(BoardView), matching: find.byType(CustomPaint)).first,
    );

Offset _cellCenter(Rect board, int index) {
  final cell = board.width / BoardEngine.cols;
  return board.topLeft +
      Offset(
        ((index % BoardEngine.cols) + 0.5) * cell,
        ((index ~/ BoardEngine.cols) + 0.5) * cell,
      );
}

/// 棋盘上所有相邻格子对，用于自动试玩。
List<List<int>> _adjacentPairs() {
  final pairs = <List<int>>[];
  for (var y = 0; y < BoardEngine.rows; y++) {
    for (var x = 0; x < BoardEngine.cols; x++) {
      final i = y * BoardEngine.cols + x;
      if (x + 1 < BoardEngine.cols) pairs.add([i, i + 1]);
      if (y + 1 < BoardEngine.rows) pairs.add([i, i + BoardEngine.cols]);
    }
  }
  return pairs;
}

bool _gameEnded() =>
    find.text('败北').evaluate().isNotEmpty ||
    find.text('胜利').evaluate().isNotEmpty ||
    find.text('通关').evaluate().isNotEmpty;

/// 棋盘与战斗状态都是 widget 的公开字段，预览可以直接读出来下棋。
///
/// `_playUntilEnd` 那样乱试只能验证"乱点不会崩"，走不到"打赢之后"的界面；
/// 有了这两个入口就能用落子顾问真的把一关打穿，于是三选一强化面板、
/// 关卡结算这些只在胜利后出现的界面也能被截图检查。
BoardEngine _liveBoard(WidgetTester tester) =>
    tester.widget<BoardView>(find.byType(BoardView)).board;

BattleState _liveBattle(WidgetTester tester) =>
    tester.widget<BattleView>(find.byType(BattleView)).battle;

/// 用落子顾问推演着打，直到分出胜负或步数用尽。
Future<bool> _playToWin(WidgetTester tester, {int maxMoves = 40}) async {
  for (var i = 0; i < maxMoves; i++) {
    if (_gameEnded()) return true;
    final battle = _liveBattle(tester);
    if (battle.isOver) break;
    final move = const MoveAdvisor().suggest(_liveBoard(tester), battle);
    if (move == null) break;
    final board = _boardRect(tester);
    await tester.tapAt(_cellCenter(board, move.a));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(_cellCenter(board, move.b));
    // 每手给足时间：长连锁的动画能拖到好几秒，等不够就会出现
    // "上一手还没结算完就开始点下一手"，点击被吞掉、选中态从此错位。
    await _advance(tester, 5.0);
  }
  // 胜负刚定的时候结算面板还在入场（胜利有 1 秒的演出停顿），
  // 这里必须再等一会儿，否则会把"已经打完了"当成"没打完"。
  for (var i = 0; i < 12 && !_gameEnded(); i++) {
    await _advance(tester, 0.5);
  }
  return _gameEnded();
}

/// 依次尝试每个相邻交换，直到分出胜负。返回是否成功走到结算画面。
///
/// 每轮会遍历棋盘上全部 112 个相邻对，其中只有十来个能真正成三连，
/// 因此要走到结算（玩家阵亡或击杀敌人）需要相当多轮。
Future<bool> _playUntilEnd(WidgetTester tester, {int maxAttempts = 300}) async {
  final pairs = _adjacentPairs();
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (_gameEnded()) return true;
    final board = _boardRect(tester);
    final pair = pairs[attempt % pairs.length];
    await tester.tapAt(_cellCenter(board, pair[0]));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(_cellCenter(board, pair[1]));
    await _advance(tester, 2.2);
  }
  return _gameEnded();
}

void main() {
  setUpAll(() async {
    final bytes = File(_cjkFontPath).readAsBytesSync();
    final loader = FontLoader('CJK')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    // 画布上的文字（连击提示、伤害飘字、强化宝石的名字）不带 fontFamily，
    // 测试环境会落到一个"所有字形都是方块"的默认字体上。把默认字体族指到
    // 刚注册的这个，截图里才看得见这些文字。
    debugCanvasFontFamily = 'CJK';
  });

  // Pixel 7 一类的常见竖屏：411 x 914 逻辑像素，顶部刘海 47。
  const pixel = Size(411, 914);

  testWidgets('入场卡', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.6);
    await shot.capture(tester, '01_intro');
    await _advance(tester, 3.0);
  });

  testWidgets('战斗主画面', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await shot.capture(tester, '02_battle');

    // 选中一颗宝石，看看选中态的高亮是否够明显。
    await tester.tapAt(_cellCenter(_boardRect(tester), 27));
    await _advance(tester, 0.4);
    await shot.capture(tester, '03_selected');
    await _advance(tester, 3.0);
  });

  testWidgets('玩法说明', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await tester.tap(find.byTooltip('玩法说明'));
    await _advance(tester, 0.4);
    await shot.capture(tester, '04_help');
    await _advance(tester, 1.0);
  });

  testWidgets('菜单与设置', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await tester.tap(find.byTooltip('菜单与设置'));
    await _advance(tester, 0.5);
    await shot.capture(tester, '05_menu');
    await _advance(tester, 1.0);
  });

  testWidgets('落子提示高亮', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await tester.tap(find.byTooltip('提示'));
    await _advance(tester, 0.5);
    await shot.capture(tester, '06_hint');
    await _advance(tester, 1.0);
  });

  testWidgets('对战中带状态标签（易伤/狂暴）', (tester) async {
    // 打上几十手，让敌人挂上 debuff，验证状态标签与右上角按钮不再重叠。
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await _playUntilEnd(tester, maxAttempts: 30);
    await shot.capture(tester, '07_debuffs');
    await _advance(tester, 1.0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('触控目标几何', (tester) async {
    _screen(tester, pixel, topInset: 47);
    await tester.pumpWidget(_app());
    await _advance(tester, 3.0);

    final help = tester.getRect(find.byTooltip('玩法说明'));
    final menu = tester.getRect(find.byTooltip('菜单与设置'));
    // 状态标签挂在副标题那一行（用第 1 关的副标题文字定位这一行）。
    final subtitle = tester.getRect(
      find.descendant(
        of: find.byType(BattleView),
        matching: find.text(Campaign.levels.first.enemy.title),
      ),
    );
    final hint = tester.getRect(find.byTooltip('提示'));
    final board = _boardRect(tester);
    // 标签排在副标题行右端，一直顶到内容区右边界。
    final tagStrip = Rect.fromLTRB(
      subtitle.left,
      subtitle.top,
      tester.view.physicalSize.width / tester.view.devicePixelRatio - 16,
      subtitle.bottom,
    );

    void report(String name, Rect r) {
      // ignore: avoid_print
      print('$name: ${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)} @ '
          'x[${r.left.toStringAsFixed(0)},${r.right.toStringAsFixed(0)}] '
          'y[${r.top.toStringAsFixed(0)},${r.bottom.toStringAsFixed(0)}]');
    }

    report('帮助按钮', help);
    report('菜单按钮', menu);
    report('提示按钮', hint);
    report('状态标签所在行', tagStrip);
    report('棋盘格子', Rect.fromLTWH(0, 0, board.width / BoardEngine.cols, board.width / BoardEngine.cols));

    final overlap = help.overlaps(tagStrip) || menu.overlaps(tagStrip);
    // ignore: avoid_print
    print(overlap ? '✗ 状态标签与右上角按钮仍然重叠' : '✓ 状态标签与右上角按钮互不重叠');
    expect(overlap, isFalse, reason: '狂暴/易伤/禁疗标签不能和右上角按钮叠在一起');
    await _advance(tester, 1.0);
  });

  testWidgets('自动试玩到结算', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    final ended = await _playUntilEnd(tester);
    // ignore: avoid_print
    print(ended ? '已走到结算画面' : '试玩结束但未分出胜负');
    await shot.capture(tester, '08_result');
    await _advance(tester, 1.0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('胜利后的三选一强化', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    // 把敌人血量压到几手之内能打死：这个预览要的是"赢下之后"的界面，
    // 让顾问从头打完整关既慢又依赖随机棋盘，会变成 flaky 测试。
    // 胜利判定、结算、抽牌仍然全部走真实路径。
    _liveBattle(tester).enemyHp = 300;
    final won = await _playToWin(tester, maxMoves: 30);
    expect(won, isTrue, reason: '落子顾问应该能收掉残血的敌人，否则这个预览就截不到强化面板');
    await shot.capture(tester, '15_upgrade_choice');

    // 吃掉一张牌 → 进入第二关；此时菜单里应当列出本局的强化。
    // 注意要等下一关的入场卡自己退场（2 秒），否则它会把菜单按钮盖住。
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await _advance(tester, 3.0);
    await tester.tap(find.byTooltip('菜单与设置'));
    await _advance(tester, 0.5);
    await shot.capture(tester, '16_menu_run');
    await _quiet(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('必杀自选落点', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);

    // 直接充满怒气（预览要的是界面状态，不是靠打出来）。
    _liveBattle(tester).rage = Campaign.player.maxRage;
    final board = _boardRect(tester);
    // 点一下棋盘触发重建，按钮才会亮起来。
    await tester.tapAt(_cellCenter(board, 27));
    await _advance(tester, 0.3);
    await tester.tap(find.text('斩月'));
    await _advance(tester, 0.3);

    // 按住某一格：整行整列的清除范围应当被点亮。
    final gesture = await tester.startGesture(_cellCenter(board, 19));
    await _advance(tester, 0.4);
    await shot.capture(tester, '17_ultimate_aim');
    await gesture.up();
    await _quiet(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('强化宝石组合技的演出', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);

    // 直接在引擎上摆两颗相邻的强化宝石，再像玩家那样把它们换到一起。
    // 组合技是这一版最重的演出，值得单独截一帧来校对。
    const a = 27;
    const b = 28;
    final board = _liveBoard(tester);
    board.cells[a] = Gem(id: 9001, type: GemType.red, special: SpecialKind.lineH);
    board.cells[b] = Gem(id: 9002, type: GemType.red, special: SpecialKind.lineV);

    final rect = _boardRect(tester);
    await tester.tapAt(_cellCenter(rect, a));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(_cellCenter(rect, b));
    await _advance(tester, 0.45);
    await shot.capture(tester, '18_combo');
    await _quiet(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('小屏 + 最大字体 · 三选一强化', (tester) async {
    // 结算面板 + 三张强化卡是最容易在小屏上撑爆的一屏。
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app(textScale: 2.0));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);

    // 全程顶着最坏情况的 HUD：护盾拉满（生命文案最长）。状态条就是在这个
    // 组合下被挤出过 2.3 像素，所以这一屏要一直保持在这个状态上。
    final battle = _liveBattle(tester);
    battle.shield = Campaign.player.maxShield;
    battle.enemyHp = 300;
    final won = await _playToWin(tester, maxMoves: 30);
    expect(won, isTrue, reason: '收不掉残血敌人，这一屏就截不到');
    await shot.capture(tester, '19_small_upgrade');
    await _quiet(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('小屏 + 大字体', (tester) async {
    // iPhone SE 一代尺寸，且系统字体放大 1.5 倍：最容易被撑爆的组合。
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app(textScale: 1.5));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await shot.capture(tester, '09_small_main');
    await _advance(tester, 1.0);
  });

  testWidgets('小屏 + 大字体 · 玩法说明', (tester) async {
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app(textScale: 1.5));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await tester.tap(find.byTooltip('玩法说明'));
    await _advance(tester, 0.4);
    await shot.capture(tester, '10_small_help');
    await _advance(tester, 1.0);
  });

  testWidgets('小屏 + 大字体 · 入场卡', (tester) async {
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app(textScale: 1.5));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.6);
    await shot.capture(tester, '11_small_intro');
    await _advance(tester, 3.0);
  });

  testWidgets('小屏 + 默认字体', (tester) async {
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await shot.capture(tester, '12_small_default');
    await _advance(tester, 1.0);
  });

  testWidgets('小屏 + 最大字体（系统无障碍上限 2.0）', (tester) async {
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_app(textScale: 2.0));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await shot.capture(tester, '13_max_text');
    await _advance(tester, 1.0);
  });

  testWidgets('平板尺寸', (tester) async {
    _screen(tester, const Size(768, 1024), topInset: 24, dpr: 1.5);
    final shot = _Shot(_app());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);
    await shot.capture(tester, '14_tablet');
    await _advance(tester, 1.0);
  });

  testWidgets('主菜单', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_menuApp());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.5);
    await shot.capture(tester, '20_main_menu');
    await _advance(tester, 0.5);
  });

  testWidgets('主菜单 · 设置弹层（含清空进度确认）', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_menuApp());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.5);
    await tester.tap(find.text('设置'));
    await _advance(tester, 0.4);
    await tester.tap(find.text('清空全部进度'));
    await _advance(tester, 0.4);
    await shot.capture(tester, '21_menu_settings');
    await _advance(tester, 0.5);
  });

  testWidgets('主菜单 · 玩法说明', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(_menuApp());
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.5);
    await tester.tap(find.text('玩法说明'));
    await _advance(tester, 0.4);
    await shot.capture(tester, '22_menu_help');
    await _advance(tester, 0.5);
  });

  testWidgets('无尽模式 · 入场卡与战斗', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'CJK',
          scaffoldBackgroundColor: Palette.bgDeep,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Palette.gold,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child!,
        ),
        home: GameScreen(settings: AppSettings(), sfx: SfxController(), mode: GameMode.endless),
      ),
    );
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.6);
    await shot.capture(tester, '23_endless_intro');
    await _advance(tester, 3.0);
    await shot.capture(tester, '24_endless_battle');
    await _advance(tester, 1.0);
  });

  testWidgets('无尽模式 · 肉鸽三选一（稀有度视觉）', (tester) async {
    _screen(tester, pixel, topInset: 47);
    final shot = _Shot(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'CJK',
          scaffoldBackgroundColor: Palette.bgDeep,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Palette.gold,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child!,
        ),
        home: GameScreen(
          settings: AppSettings(),
          sfx: SfxController(),
          mode: GameMode.endless,
          // 第 3 波：打完这一波发牌时 depth=2，正是"每 3 波保底稀有"的
          // 保底波——三选一里必然出现稀有牌，角标视觉因此可以被稳定截到。
          startLevel: 2,
        ),
      ),
    );
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 3.0);

    _liveBattle(tester).enemyHp = 300;
    final won = await _playToWin(tester, maxMoves: 30);
    expect(won, isTrue, reason: '收不掉残血的第三波 BOSS，就截不到肉鸽三选一');
    expect(find.text('稀有'), findsWidgets,
        reason: '保底波的三选一必须含稀有牌，否则这张预览没有覆盖到角标视觉');
    await shot.capture(tester, '26_endless_upgrade');
    await _quiet(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('小屏主菜单（320 宽 + 大字体）', (tester) async {
    _screen(tester, const Size(320, 568), topInset: 20);
    final shot = _Shot(_menuApp(textScale: 1.5));
    await tester.pumpWidget(RepaintBoundary(key: shot.key, child: shot.child));
    await _advance(tester, 0.5);
    await shot.capture(tester, '25_small_menu');
    await _advance(tester, 0.5);
  });
}
