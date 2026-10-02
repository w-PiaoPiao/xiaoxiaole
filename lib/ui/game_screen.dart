import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_settings.dart';
import '../engine/battle.dart';
import '../engine/board.dart';
import '../engine/endless.dart';
import '../engine/gem.dart';
import '../engine/items.dart';
import '../engine/levels.dart';
import '../engine/move_advisor.dart';
import '../engine/roguelike.dart';
import '../engine/upgrades.dart';
import 'battle_view.dart';
import 'board_view.dart';
import 'fx.dart';
import 'help_panel.dart';
import 'hud.dart';
import 'item_art.dart';
import 'menu_overlay.dart';
import 'palette.dart';
import 'sfx.dart';
import 'upgrade_art.dart';

/// 一局游戏的总控：串起棋盘结算、战斗数值与全部动画时序。
///
/// 一个 [GameScreen] 承载一局：战役打完六关进通关结算；无尽模式波次
/// 无限、敌人逐波增强，直到玩家倒下。进入时从第一关（或恢复存档）开始。
class GameScreen extends StatefulWidget {
  /// 设置与存档。不传则内部自建一份（用于预览与测试，不落盘）。
  final AppSettings? settings;

  /// 音效与触感。不传则内部自建一份。
  final SfxController? sfx;

  /// 游戏模式：战役（六关）或无尽（波次无限）。
  final GameMode mode;

  /// 起始的关卡索引（战役）或波次 - 1（无尽）。
  final int startLevel;

  /// 恢复存档。非空时优先于 [startLevel]：关卡、强化与继承生命全部还原。
  final ResumeData? resume;

  /// 回到主菜单。空表示这是根页面（预览 / 测试），菜单里不出现该入口。
  final VoidCallback? onExitToMenu;

  const GameScreen({
    super.key,
    this.settings,
    this.sfx,
    this.mode = GameMode.campaign,
    this.startLevel = 0,
    this.resume,
    this.onExitToMenu,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final FxController fx;
  late final AppSettings settings;
  late final SfxController sfx;
  late BoardEngine board;
  late BattleState battle;
  late int _levelIndex;

  /// 本 State 是否自建了音效控制器（预览 / 测试路径）：自建的由自己释放。
  bool _ownsSfx = false;

  /// 关卡运行世代号：[_startLevel] 每调用一次就自增。
  ///
  /// 一次交换/必杀会 await 一整串连锁动画，中途玩家完全可以从菜单选关或
  /// 重开——那时 `board`、`battle` 已经被换成新一局的实例，旧协程若继续
  /// 跑下去，就会把旧棋盘的结算打到新关卡身上。所有长协程在恢复执行时
  /// 都要先确认"这局还是我那一局"。
  int _runId = 0;

  /// 玩家跨关卡继承的生命。
  int _carryHp = Campaign.player.maxHp;

  /// 本局（一次挑战）已经吃到的强化：id → 叠了几层。
  final Map<String, int> _taken = {};

  /// 当前生效的属性档案 = 初始档案 + 全部强化。关卡之间只有它变化。
  PlayerProfile _profile = Campaign.player;

  /// 胜利后待选的三张强化牌。空表示当前没有待选。
  List<Upgrade> _offer = const [];

  /// 抽强化用的随机源（按局独立，测试与预览可以换成固定种子）。
  final math.Random _runRng = math.Random();

  int? _selected;
  bool _busy = false;
  bool _showIntro = true;
  bool _showResult = false;
  bool _showHelp = false;
  bool _showMenu = false;
  bool _campaignClear = false;
  int _turnsThisLevel = 0;

  /// 必杀是否处于「选择落点」状态：此时棋盘上每一次点击都是落点。
  bool _aimingUltimate = false;

  /// 道具是否处于「选择落点」状态（锤子）：与必杀互斥。
  bool _aimingItem = false;

  /// 本局剩余的道具（道具 id → 数量）。每关开局补足，用掉不累积。
  final Map<String, int> _items = {};

  /// 本关统计：结算面板用来给出评价。
  int _maxCombo = 0;
  int _totalDamage = 0;

  /// 落子提示高亮的两个格子。
  int? _hintA;
  int? _hintB;
  Timer? _hintTimer;

  Duration _lastTick = Duration.zero;
  double _sinceCheck = 0;
  double _busyElapsed = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    fx = FxController();
    final providedSettings = widget.settings;
    if (providedSettings != null) {
      settings = providedSettings;
    } else {
      settings = AppSettings();
      unawaited(settings.load());
    }
    final providedSfx = widget.sfx;
    if (providedSfx != null) {
      sfx = providedSfx;
    } else {
      sfx = SfxController();
      _ownsSfx = true;
      unawaited(sfx.load());
    }
    settings.addListener(_applySettings);
    // 注意：这里不能立刻应用设置——_applySettings 要读 MediaQuery，
    // 那在 initState 里还不允许。交给紧随其后的 didChangeDependencies。
    _ticker = createTicker(_onTick)..start();

    // 恢复存档优先：把上一局进行中的关卡、强化与继承生命原样还原。
    final resume = widget.resume;
    if (resume != null) {
      _levelIndex = _clampLevel(resume.level);
      _taken.addAll(resume.upgrades);
      _items.addAll(resume.items);
      _profile = UpgradePool.profileFor(_taken);
      // 生命缺失（旧存档或损坏值）时按满血开局，而不是 1 血被秒。
      _carryHp = resume.carryHp > 0
          ? resume.carryHp.clamp(1, _profile.maxHp)
          : _profile.maxHp;
    } else {
      _levelIndex = widget.startLevel;
    }
    _startLevel(_levelIndex, persistResume: false);
    // 首局的存档要等第一帧之后再写：saveResume 会 notifyListeners，而监听者
    // _applySettings 要读 MediaQuery——initState 还没走完时读不到。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _persistResume();
    });
  }

  /// 把存档里的关卡号夹进当前模式的合法范围。
  ///
  /// 存档可能来自旧版本或已被改坏（例如战役只有六关却写着 99），这里必须
  /// 兜住——否则 `Campaign.levels[_levelIndex]` 会在开局瞬间 RangeError。
  int _clampLevel(int level) {
    if (level < 0) return 0;
    if (widget.mode == GameMode.campaign) {
      final maxIndex = Campaign.levels.length - 1;
      return level > maxIndex ? maxIndex : level;
    }
    return level;
  }

  void _persistResume() {
    settings.saveResume(
      ResumeData(
        mode: widget.mode,
        level: _levelIndex,
        carryHp: _carryHp,
        upgrades: Map.of(_taken),
        items: Map.of(_items),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _hintTimer?.cancel();
    settings.removeListener(_applySettings);
    _ticker.dispose();
    fx.dispose();
    // 自建的音效控制器要自己收尾：一套池子是 11 种音效 × 3 个播放器，
    // 预览/测试进程反复进出 GameScreen 会一路累积。
    if (_ownsSfx) unawaited(sfx.dispose());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applySettings();
  }

  /// 把设置（以及系统的"减少动态效果"）同步到特效层与音效层。
  void _applySettings() {
    sfx.soundEnabled = settings.sound;
    sfx.hapticsEnabled = settings.haptics;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    fx.allowShake = settings.screenShake && !reduceMotion;
    fx.allowFlash = !reduceMotion;
    fx.reducedMotion = reduceMotion;
    // 暂停菜单里的设置开关值来自本 State 的 build：改完必须重建，否则开关
    // 不会变色，再点一次也仍然发出同一个旧值（看起来就像开关坏了）。
    _refresh();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    // 上限放到 0.12 秒：低帧率设备上动画仍能跟上真实时间。钳得太死会让
    // 动画时间以远低于真实时间的速度流逝，连锁看起来就像卡住了。
    final scaled = dt.clamp(0.0, 0.12);
    fx.tick(scaled);

    // 定局兜底：胜负已定却迟迟没弹出结算（长连锁、低帧率都可能把序列拖住），
    // 直接补结算并放开操作。只在 battle.isOver 时生效，不可能打断正常对局。
    if (_busy) {
      // 用钳制后的时间累加：从后台切回来时 dt 可能有好几秒，未钳制会和
      // 上面"动画以真实时间流逝"的假设打架，直接顶穿兜底阈值。
      _busyElapsed += scaled;
      if (_busyElapsed > 6.0 && battle.isOver) {
        _busyElapsed = 0;
        _busy = false;
        unawaited(_handleBattleEnd(_runId));
        _ensureVisualSync('定局兜底');
        _refresh();
      }
    } else {
      _busyElapsed = 0;
    }

    // 空闲时每秒自检一次：
    //  - 战斗已经结束却没弹出结算面板（任何原因漏结算），立刻补上，绝不把玩家
    //    留在"敌人空血但什么也没发生"的状态里；
    //  - 否则巡检视觉层，发现与引擎脱节就记录现场并重画。
    if (!_busy && !_showIntro && !_showResult) {
      _sinceCheck += dt;
      if (_sinceCheck >= 1.0) {
        _sinceCheck = 0;
        if (battle.isOver) {
          unawaited(_handleBattleEnd(_runId));
        } else {
          _ensureVisualSync('空闲巡检');
        }
      }
    }
  }

  // ------------------------------------------------------------------ 关卡流程

  /// 当前关卡的包装：战役走固定配置，无尽按波次生成。
  LevelDef get _currentLevel => widget.mode == GameMode.campaign
      ? Campaign.levels[_levelIndex]
      : EndlessRoster.levelFor(_levelIndex + 1);

  void _startLevel(int index, {bool persistResume = true}) {
    // 换局：世代号自增，仍在飞的旧协程会在下一次检查点安静退出。
    _runId++;
    _levelIndex = index;
    final level = _currentLevel;
    board = BoardEngine()..reset();
    // 本关的机关：关卡配置决定种类与数量，位置由棋盘自己的随机源决定
    // （同一个种子永远得到同一张棋盘，平衡报告与测试都能复现）。
    for (final entry in level.obstacles.entries) {
      board.placeObstacles(entry.key, entry.value);
    }
    // 道具每关补足（用掉不累积、也不会清零）。
    final restocked = refillItems(_items);
    _items
      ..clear()
      ..addAll(restocked);
    battle = BattleState(
      def: level.enemy,
      levelIndex: index,
      profile: _profile,
      playerHp: _carryHp.clamp(1, _profile.maxHp),
    );
    _selected = null;
    _busy = false;
    _busyElapsed = 0;
    _showResult = false;
    _showIntro = true;
    _showMenu = false;
    _campaignClear = false;
    _turnsThisLevel = 0;
    _maxCombo = 0;
    _totalDamage = 0;
    _endResolved = false;
    _aimingUltimate = false;
    _aimingItem = false;
    // 上一关留下的三张候选牌必须清掉：从菜单直接跳关时，上一关的牌
    // 不该跟过来（否则会变成"给第 2 关发第 1 关的奖励"）。
    _offer = const [];
    _clearHint();
    fx.reset();
    _seedBoardAnimation();
    // 每开一关都把「进行中的一局」写进存档：中途杀掉应用，主菜单的
    // 「继续游戏」也能从这里接着打（无尽模式同样适用）。
    if (persistResume) _persistResume();
    _refresh();
    // 开场卡停留一会儿后自动进入战斗（可以点击提前跳过）。
    // 用世代号而不是关卡号做身份：同一关在 2 秒内重开时，旧定时器必须失效。
    final run = _runId;
    unawaited(
      _pause(2.0).then((_) {
        if (_disposed || run != _runId) return;
        if (!_showIntro) return; // 玩家已经手动跳过
        setState(() => _showIntro = false);
      }),
    );
  }

  /// 开局时让宝石从棋盘上方依次落入。
  void _seedBoardAnimation() {
    final snapshot = board.snapshot();
    final starts = <int, double>{
      for (final cell in snapshot)
        cell.gemId: -1.0 - (BoardEngine.rows - cell.index ~/ BoardEngine.cols),
    };
    fx.applySnapshot(snapshot, spawnStartY: starts, fallDuration: 0.55);
  }

  /// 视觉层自检：渲染中的宝石必须与引擎棋盘一一对应。
  ///
  /// 一旦发现不一致，先打印现场（debug 构建），再按引擎状态重画一遍，
  /// 保证无论什么原因导致的脱节都不会让棋盘卡在半途。
  void _ensureVisualSync(String where) {
    // 先兜住最底层的情况：引擎棋盘本身不该有空洞，真出现就补上并记录。
    final holes = board.countHoles();
    if (holes > 0) {
      board.refillHoles();
      if (kDebugMode) {
        debugPrint(
          '⚠️ 引擎棋盘出现 $holes 个空洞[$where]，已补全（这属于不该发生的情况，'
          '请把这条日志连同操作步骤一并反馈）',
        );
      }
    }

    final snapshot = board.snapshot();
    final expected = {for (final cell in snapshot) cell.gemId};
    final actual = fx.gems.keys.toSet();

    // 逐颗比对：数量、身份、目标坐标三者都要对上。
    final misplaced = <String>[];
    for (final cell in snapshot) {
      final visual = fx.gems[cell.gemId];
      if (visual == null) continue;
      final gx = (cell.index % BoardEngine.cols).toDouble();
      final gy = (cell.index ~/ BoardEngine.cols).toDouble();
      final brokenPosition =
          !visual.x.isFinite ||
          !visual.y.isFinite ||
          (!visual.moving && (visual.x - gx).abs() > 0.01);
      if ((visual.toX - gx).abs() > 0.01 ||
          (visual.toY - gy).abs() > 0.01 ||
          brokenPosition) {
        if (misplaced.length < 4) {
          misplaced.add(
            '#${cell.gemId}→格${cell.index} 目标(${visual.toX},${visual.toY}) '
            '当前(${visual.x.toStringAsFixed(2)},${visual.y.toStringAsFixed(2)}) t=${visual.t.toStringAsFixed(2)}',
          );
        }
      }
    }

    if (expected.length == actual.length &&
        expected.containsAll(actual) &&
        misplaced.isEmpty) {
      return;
    }

    // release 构建不再写这些排查日志：它们只在调试时需要，而 debugPrint
    // 在发布包里依然会输出（真机日志里刷屏、也白费一点开销）。
    if (kDebugMode) {
      final visuals = fx.gems.values.toList();
      final outside = visuals
          .where((g) => g.y < 0 || g.y > BoardEngine.rows - 1)
          .length;
      final broken = visuals
          .where((g) => !g.x.isFinite || !g.y.isFinite)
          .length;
      final missing = expected.difference(actual);
      debugPrint(
        '⚠️ 视觉层脱节[$where] 引擎=${expected.length} 视觉=${actual.length} '
        '缺失=${missing.length} 多余=${actual.difference(expected).length} '
        '目标错位=${misplaced.length} 画在棋盘外=$outside 坐标异常=$broken '
        '移动中=${visuals.where((g) => g.moving).length} 消散中=${fx.dying.length} busy=$_busy'
        '${misplaced.isEmpty ? '' : '\n   ${misplaced.join('\n   ')}'}',
      );
    }
    fx.applySnapshot(snapshot);
  }

  /// 战斗数值是可变对象，动画序列结束后必须主动触发一次重建，
  /// 否则 HUD 上的血量/回合数会停留在旧值。
  void _refresh() {
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _pause(double seconds) async {
    await Future<void>.delayed(
      Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  // ------------------------------------------------------------------ 玩家输入

  /// 打开菜单/说明等遮罩时，棋盘输入一律屏蔽。
  bool get _inputBlocked =>
      _busy ||
      battle.isOver ||
      _showIntro ||
      _showResult ||
      _showMenu ||
      _showHelp;

  void _onSelect(int index) {
    // 瞄准态优先：点哪儿就在哪儿落地。
    //  - 道具（锤子）：砸掉这一格；
    //  - 必杀：这是玩家自己的决定，也是「攒了半天怒气，终于能打在最好的
    //    位置上」的那份主动权。
    if (_aimingItem) {
      unawaited(_useHammer(index));
      return;
    }
    if (_aimingUltimate) {
      unawaited(_fireUltimate(index));
      return;
    }
    if (_inputBlocked) return;
    _clearHint();
    sfx.tap();
    final current = _selected;
    if (current == null) {
      setState(() => _selected = index);
      return;
    }
    if (current == index) {
      setState(() => _selected = null);
      return;
    }
    if (board.adjacent(current, index)) {
      setState(() => _selected = null);
      unawaited(_attemptSwap(current, index));
      return;
    }
    setState(() => _selected = index);
  }

  void _onSwapRequest(int a, int b) {
    // 瞄准期间拖动不算交换：那只是在移动手指，不该把棋盘搅乱。
    if (_inputBlocked || _aimingUltimate || _aimingItem) return;
    _clearHint();
    setState(() => _selected = null);
    unawaited(_attemptSwap(a, b));
  }

  Future<void> _attemptSwap(int a, int b) async {
    if (_busy) return;
    if (!board.canSwap(a, b)) {
      // 非法交换：轻微抖动提示
      fx.shakeBy(5);
      sfx.reject();
      setState(() => _selected = null);
      return;
    }
    _busy = true;
    // 选中的金框必须经 setState 消失：只改字段的话父级不会重建，
    // BoardView 拿到的还是旧的 selected，金框会一直挂在交换动画上。
    setState(() => _selected = null);
    // 捕获这一局的棋盘与战斗。await 期间玩家仍可能从菜单换关，那时字段
    // 已经指向新一局的实例，旧协程必须就地退出。
    final run = _runId;
    final engine = board;
    final state = battle;
    // try/finally 兜住：无论中途发生什么，都一定会把 _busy 放掉，
    // 绝不能让玩家被永久锁住操作。
    try {
      engine.swapCells(a, b);
      fx.applySnapshot(engine.snapshot(), fallDuration: 0.16);
      await _pause(0.15);
      if (_disposed || run != _runId) return;

      // 玩家的棋盘规则（棱镜宗师 / 爆破工程 / 十字破空）在这里注入：
      // 棋盘引擎本身不认识 build，规则是显式传进去的。
      final steps = engine.resolveSwap(a, b, rules: state.profile.boardRules);
      if (steps.isEmpty) {
        engine.swapCells(a, b);
        fx.applySnapshot(engine.snapshot(), fallDuration: 0.16);
        await _pause(0.16);
        sfx.reject();
        return;
      }

      _turnsThisLevel++;
      await _playSteps(run, engine, state, steps);
      await _finishTurn(run, engine, state);
    } finally {
      // 只有"还是这一局"才放开封锁：旧协程的收尾不能把新一局的 _busy
      // 提前清掉（那会打开一次并发输入窗口）。
      if (!_disposed && run == _runId) {
        _busy = false;
        _ensureVisualSync('交换结算');
        _refresh();
      }
    }
  }

  /// 点「斩月」：第一次点是进入选落点状态，再点一次是取消。
  ///
  /// 必杀固定在棋盘正中央也能用，但把落点交给玩家之后，它就从一个"到点就按"
  /// 的按钮变成了一次真正的决策——瞄准哪里，取决于棋盘上哪种颜色堆得最多。
  void _armUltimate() {
    if (_busy || !battle.canCastUltimate) return;
    if (_aimingUltimate) {
      setState(() => _aimingUltimate = false);
      return;
    }
    sfx.tap();
    _clearHint();
    setState(() {
      _aimingUltimate = true;
      _aimingItem = false;
      _selected = null;
    });
  }

  Future<void> _fireUltimate(int centerIndex) async {
    if (_busy || !battle.canCastUltimate) return;
    _busy = true;
    _aimingUltimate = false;
    _clearHint();
    setState(() => _selected = null);
    final run = _runId;
    final engine = board;
    final state = battle;
    try {
      sfx.castUltimate();
      final events = state.castUltimate();
      fx.triggerUltimate();
      fx.lunge();
      fx.shakeBy(26);
      _presentEnemyEvents(events);
      await _pause(0.5);
      if (_disposed || run != _runId) return;

      // 与普通交换一样带上玩家的棋盘规则：连锁里被波及的强化宝石
      // 也要按 build 引爆（「爆破工程」的必杀同样是 5x5）。
      final steps = engine.resolveUltimate(
        centerIndex,
        rules: state.profile.boardRules,
      );
      // 倍率取自这一局的档案：换局后 _profile 可能已经变了。
      await _playSteps(
        run,
        engine,
        state,
        steps,
        multiplier: state.profile.ultimateMultiplier,
      );
      await _finishTurn(run, engine, state);
    } finally {
      if (!_disposed && run == _runId) {
        _busy = false;
        _ensureVisualSync('必杀结算');
        _refresh();
      }
    }
  }

  // ------------------------------------------------------------------ 道具

  /// 「临门一脚」：敌人下一击挡不住、手里还有道具——道具栏该闪起来了。
  ///
  /// 这是被行业反复验证的"救场时机"：提示要在玩家真正需要的那一刻出现，
  /// 而不是一直挂着，否则就变成了需要无视的噪音。
  bool get _itemRescueMoment {
    if (battle.isOver || !battle.dangerImminent) return false;
    if (!_items.values.any((n) => n > 0)) return false;
    return battle.incomingDamage >= battle.playerHp + battle.shield;
  }

  /// 道具栏的总入口。
  void _useItem(ItemKind kind) {
    switch (kind) {
      case ItemKind.hammer:
        _armHammer();
      case ItemKind.shuffle:
        unawaited(_useShuffle());
      case ItemKind.stall:
        _useStall();
    }
  }

  /// 点锤子：进入 / 退出「选择落点」状态。
  void _armHammer() {
    if (_busy || battle.isOver) return;
    if ((_items[ItemKind.hammer.id] ?? 0) <= 0) return;
    if (_aimingItem) {
      setState(() => _aimingItem = false);
      return;
    }
    sfx.tap();
    _clearHint();
    setState(() {
      _aimingItem = true;
      _aimingUltimate = false;
      _selected = null;
    });
  }

  /// 锤子落点：砸掉这一格（机关连壳砸碎），随后照常结算连锁。
  ///
  /// 道具**不消耗回合**：砸完不推进敌人的出手倒计时——这正是它们"救场"的
  /// 意义所在，数量有限来平衡。
  Future<void> _useHammer(int index) async {
    if (_busy || !_aimingItem) return;
    if (board.cells[index] == null) return;
    _items[ItemKind.hammer.id] = math.max(
      0,
      (_items[ItemKind.hammer.id] ?? 1) - 1,
    );
    // 道具是「继续游戏」存档的一部分：用掉之后立刻写档，否则中途退出重进
    // 会把已经砸掉的锤子又变回来。
    _persistResume();
    _busy = true;
    setState(() {
      _aimingItem = false;
      _selected = null;
    });
    final run = _runId;
    final engine = board;
    final state = battle;
    try {
      sfx.spawnSpecial();
      fx.addLabel(
        '锤击',
        (index % BoardEngine.cols) + 0.5,
        (index ~/ BoardEngine.cols) - 0.15,
        Palette.gold,
        size: 22,
      );
      fx.shakeBy(9);
      final steps = engine.resolveSingleClear(
        index,
        rules: state.profile.boardRules,
      );
      if (steps.isEmpty) return;
      await _playSteps(run, engine, state, steps);
      await _afterItemUse(run, engine, state);
    } finally {
      if (!_disposed && run == _runId) {
        _busy = false;
        _ensureVisualSync('道具结算');
        _refresh();
      }
    }
  }

  /// 洗牌：重排棋盘颜色（机关原样保留）。
  Future<void> _useShuffle() async {
    if (_busy || battle.isOver) return;
    if ((_items[ItemKind.shuffle.id] ?? 0) <= 0) return;
    _items[ItemKind.shuffle.id] = math.max(
      0,
      (_items[ItemKind.shuffle.id] ?? 1) - 1,
    );
    _persistResume();
    _busy = true;
    final run = _runId;
    final engine = board;
    final state = battle;
    try {
      sfx.spawnSpecial();
      fx.shakeBy(7);
      engine.shuffleBoard();
      fx.applySnapshot(engine.snapshot(), fallDuration: 0.35);
      fx.addLabel(
        '洗牌',
        BoardEngine.cols / 2,
        BoardEngine.rows / 2,
        Palette.shield,
        size: 26,
      );
      await fx.settle();
      if (_disposed || run != _runId) return;
      await _afterItemUse(run, engine, state);
    } finally {
      if (!_disposed && run == _runId) {
        _busy = false;
        _ensureVisualSync('洗牌');
        _refresh();
      }
    }
  }

  /// 凝滞：把敌人的出手往后推一回合。倒计时已满时不消耗道具。
  void _useStall() {
    if (_busy || battle.isOver) return;
    if ((_items[ItemKind.stall.id] ?? 0) <= 0) return;
    final delayed = battle.delayEnemyAttack();
    if (delayed == 0) {
      sfx.reject();
      _refresh();
      return;
    }
    _items[ItemKind.stall.id] = math.max(
      0,
      (_items[ItemKind.stall.id] ?? 1) - 1,
    );
    _persistResume();
    sfx.tap();
    fx.addFloat('敌方延后 1 回合', Palette.shield, ny: 0.30, size: 24);
    _refresh();
  }

  /// 道具用完之后的收尾：不推进敌人回合，只处理胜负与无解重排。
  Future<void> _afterItemUse(
    int run,
    BoardEngine engine,
    BattleState state,
  ) async {
    if (_disposed || run != _runId) return;
    if (state.isOver) {
      await _handleBattleEnd(run);
      return;
    }
    if (!engine.hasValidMove()) {
      engine.shuffleBoard();
      fx.applySnapshot(engine.snapshot(), fallDuration: 0.35);
      fx.addLabel(
        '重新排列',
        BoardEngine.cols / 2,
        BoardEngine.rows / 2,
        Palette.shield,
        size: 26,
      );
      await fx.settle();
      _refresh();
    }
  }

  /// 让落子顾问推演一步，把建议的两个格子高亮出来。
  void _requestHint() {
    if (_inputBlocked || _aimingUltimate || _aimingItem) return;
    final suggestion = const MoveAdvisor().suggest(board, battle);
    if (suggestion == null) return;
    sfx.tap();
    _hintTimer?.cancel();
    setState(() {
      _hintA = suggestion.a;
      _hintB = suggestion.b;
    });
    _hintTimer = Timer(const Duration(milliseconds: 2800), _clearHint);
  }

  void _clearHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    if (_hintA == null && _hintB == null) return;
    if (!mounted || _disposed) return;
    setState(() {
      _hintA = null;
      _hintB = null;
    });
  }

  // ------------------------------------------------------------------ 结算时序

  /// 逐步演出一次连锁。
  ///
  /// [run]、[board]、[battle] 由调用方捕获后传入：这一串 await 可能跨越
  /// 玩家的"从菜单换关"，字段 `board`/`battle` 那时已经指向新一局了。
  Future<void> _playSteps(
    int run,
    BoardEngine board,
    BattleState battle,
    List<CascadeStep> steps, {
    double multiplier = 1.0,
  }) async {
    for (final step in steps) {
      if (_disposed || run != _runId) return;
      // 胜负已定（例如击杀 BOSS 的那一下带出的后续连锁）：动画提速，
      // 让玩家尽快看到结算，而不是干等一段已经无关紧要的连锁演完。
      final pace = battle.isOver ? 0.3 : 1.0;

      if (step.activations.isNotEmpty) {
        for (final activation in step.activations) {
          fx.playActivation(activation);
        }
        sfx.activateSpecial();
        fx.shakeBy(5 + step.activations.length * 2.0);
      }

      fx.beginClear(step.cleared);
      sfx.combo(step.combo);
      _maxCombo = math.max(_maxCombo, step.combo);

      // 组合技：两颗强化宝石换在一起时把名字报出来，并额外炸一下屏幕。
      for (final activation in step.activations) {
        final name = activation.comboName;
        if (name == null) continue;
        fx.addLabel(
          name,
          BoardEngine.cols / 2,
          BoardEngine.rows / 2 - 0.6,
          Palette.gold,
          size: 42,
        );
        fx.shakeBy(20);
      }

      if (step.combo >= 2) {
        final tier = _comboTier(step.combo);
        fx.addLabel(
          tier.text,
          BoardEngine.cols / 2,
          BoardEngine.rows / 2,
          tier.color,
          size: tier.size,
        );
        // 连击越深，飘字越大、屏幕抖得越狠——连胜的势头要看得见。
        fx.shakeBy(tier.shake);
      }
      await _pause(0.12 * pace);

      fx.applySnapshot(
        step.snapshot,
        spawnStartY: step.spawnStartY,
        fallDuration: 0.30,
      );
      // 刚落位这一刻，视觉层必须与快照完全对齐（可能有宝石还在下落途中）。
      assert(() {
        if (fx.gems.length != step.snapshot.length) {
          debugPrint(
            '⚠️ 快照未完整落到视觉层: 快照=${step.snapshot.length} '
            '视觉=${fx.gems.length} combo=${step.combo} '
            '移除数=${step.cleared.length} 生成数=${step.spawns.length}',
          );
        }
        return true;
      }());

      // 机关破除：碎裂环 + 飘字；祭坛额外把怒气补给塞给玩家。
      if (step.obstacleBreaks.isNotEmpty) {
        sfx.impact(weight: 0.9);
        for (final brk in step.obstacleBreaks) {
          fx.crackObstacle(brk.index, brk.kind);
          if (brk.kind == ObstacleKind.altar) {
            final gained = battle.grantRage(BattleState.altarRageReward);
            if (gained > 0) {
              fx.addFloat(
                '祭坛 +$gained 怒气',
                Palette.gold,
                nx: _laneRight,
                ny: 0.90,
                size: 20,
              );
            }
          }
        }
      }

      // 先按宝石类型打出对应的攻击演出，再结算伤害——先看到"打出去"，
      // 再看到"打中了"，节奏比数字直接跳出来有打击感得多。
      _presentStepStrikes(step);
      final events = battle.applyClear(
        step.counts,
        combo: step.combo,
        specialBonus: step.specialBonus,
        multiplier: multiplier,
      );
      if (events.any((e) => e.kind == CombatEventKind.playerDamage)) {
        await _pause(0.09 * pace);
      }
      _presentEnemyEvents(events);
      _presentPlayerEvents(events);
      _refresh();

      if (step.spawns.isNotEmpty) {
        sfx.spawnSpecial();
        for (final spawn in step.spawns) {
          fx.addLabel(
            switch (spawn.kind) {
              SpecialKind.lineH || SpecialKind.lineV => '破空',
              SpecialKind.burst => '爆裂',
              SpecialKind.prism => '棱镜',
              SpecialKind.none => '',
            },
            (spawn.index % BoardEngine.cols).toDouble() + 0.5,
            (spawn.index ~/ BoardEngine.cols).toDouble() - 0.1,
            Palette.gem(spawn.type),
            size: 22,
          );
        }
      }

      // 等宝石落位，但给一个很短的上限：动画只是表现，引擎那边早已算完，
      // 绝不能让一段长连锁把玩家晾在那里。
      await fx.settle(timeout: Duration(milliseconds: (420 * pace).round()));
      if (_disposed || run != _runId) return;
      await _pause(0.04 * pace);
    }
  }

  /// 玩家行动结束 → 敌方回合 → 无解重排。同样带世代号。
  Future<void> _finishTurn(
    int run,
    BoardEngine board,
    BattleState battle,
  ) async {
    if (_disposed || run != _runId) return;
    // 棋盘上的毒藤每一株都在给敌人加码：进敌方回合前同步一次数量，
    // 被清掉的藤蔓从下一击起就不再算数。
    battle.vineCount = board.countObstacles(ObstacleKind.vine);
    if (battle.isOver) {
      await _handleBattleEnd(run);
      return;
    }

    final events = battle.endPlayerTurn();
    final incoming = events.where((e) => e.kind == CombatEventKind.enemyAttack);
    if (incoming.isNotEmpty) {
      fx.lunge();
      await _pause(0.20);
      if (_disposed || run != _runId) return;
      // 敌人出手：爪痕落在玩家一侧 + 全屏震动 + 边缘红闪
      final hit = incoming.first.amount;
      fx.addStrike(StrikeKind.enemyHit, count: hit ~/ 20, ny: 0.86, nx: 0.5);
      fx.hitStop = 0.06;
      fx.shakeBy(20);
      fx.playerFlash = fx.allowFlash ? 1 : 0;
      sfx.playerHurt();
      _presentPlayerEvents(events);
      await _pause(0.30);
      if (_disposed || run != _runId) return;
    } else {
      _presentPlayerEvents(events);
    }

    _refresh();
    if (battle.isOver) {
      await _handleBattleEnd(run);
      return;
    }

    if (!board.hasValidMove()) {
      board.shuffleBoard();
      fx.applySnapshot(board.snapshot(), fallDuration: 0.35);
      fx.addLabel(
        '重新排列',
        BoardEngine.cols / 2,
        BoardEngine.rows / 2,
        Palette.shield,
        size: 26,
      );
      await fx.settle();
      _refresh();
    }
  }

  /// 结算一次胜负。带一次性保护：重复调用只会执行一次。
  bool _endResolved = false;

  Future<void> _handleBattleEnd(int run) async {
    if (_endResolved) return;
    if (_disposed || run != _runId) return;
    _endResolved = true;
    _aimingUltimate = false;
    _aimingItem = false;
    final campaign = widget.mode == GameMode.campaign;
    if (battle.isWon) {
      // 过关奖励：血量按「最大生命的 50%」保底后再补 25%。
      // 打得越干净、进下一关越有余裕，但保底刻意压在半血——
      // 上一关的失误应当带一点代价过去，战役才有连续的紧张感。
      _carryHp = math.min(
        _profile.maxHp,
        math.max(
          (_profile.maxHp * 0.5).round(),
          battle.playerHp + (_profile.maxHp * 0.25).round(),
        ),
      );
      fx.dissolveTarget = 1;
      fx.shakeBy(16);
      sfx.victory();
      await _pause(1.0);
    } else {
      // 输了从满血重来，但**保留已经拿到的强化**——重试的难度不该比第一次更高。
      _carryHp = _profile.maxHp;
      fx.playerFlash = fx.allowFlash ? 1 : 0;
      fx.shakeBy(20);
      sfx.defeat();
      await _pause(0.5);
    }
    if (_disposed || run != _runId) return;

    // 记录战绩：战役解锁下一关并保存星级；无尽写下最佳波次。
    if (battle.isWon) {
      if (campaign) {
        settings.recordClear(
          levelIndex: _levelIndex,
          stars: _starsEarned,
          turns: _turnsThisLevel,
          levelCount: Campaign.levels.length,
        );
      } else {
        settings.recordEndless(_levelIndex + 1);
      }
    }

    final lastLevel = campaign && _levelIndex >= Campaign.levels.length - 1;
    // 打到「终局」的局（战役通关、任何模式战败）不再算进行中：主菜单的
    // 「继续游戏」随之消失。战败仍可当场重试，重开会重新写入存档。
    if (!battle.isWon || lastLevel) {
      settings.clearResume();
    }

    // 通关一关发三张强化牌：这是"越打越猛"的全部来源。无尽模式每波都发，
    // 与逐波增强的敌人保持同一条成长赛道。
    final offer = battle.isWon && !lastLevel
        ? UpgradePool.roll(
            profile: _profile,
            taken: _taken,
            rng: _runRng,
            depth: _levelIndex,
            // 肉鸽层只在无尽模式启用：战役一共只有五次选择机会，稀有度分层
            // 与质变牌都来不及展开，反而会把那条紧凑的成长线搅乱。
            roguelike: !campaign,
          )
        : const <Upgrade>[];

    setState(() {
      _campaignClear = battle.isWon && lastLevel;
      _offer = offer;
      _showResult = true;
    });
  }

  /// 吃掉一张强化牌并进入下一关。
  void _takeUpgrade(Upgrade upgrade) {
    // 双指同帧点击会让回调触发两次（重建之前旧的命中树还在）：第二次直接
    // 忽略，否则同一个强化会叠两层、还会一次跳过两关。
    if (!_offer.contains(upgrade)) return;
    sfx.spawnSpecial();
    final before = _profile;
    _profile = upgrade.apply(_profile);
    _taken[upgrade.id] = (_taken[upgrade.id] ?? 0) + 1;
    // 生命上限长出来的部分当场补满，不然"上限 +40"看起来像没生效。
    final grown = _profile.maxHp - before.maxHp;
    if (grown > 0) _carryHp += grown;
    _carryHp = _carryHp.clamp(1, _profile.maxHp);
    _offer = const [];
    _startLevel(_levelIndex + 1);
  }

  /// 剩余生命越多星级越高。1 星保底，3 星要求几乎满血通关。
  int get _starsEarned {
    if (!battle.isWon) return 0;
    final ratio = battle.playerHp / _profile.maxHp;
    if (ratio >= 0.8) return 3;
    if (ratio >= 0.5) return 2;
    return 1;
  }

  // ------------------------------------------------------------------ 飘字

  /// 按这一步消除的宝石种类打出对应的攻击演出。
  void _presentStepStrikes(CascadeStep step) {
    final counts = step.counts;
    final reds = counts[GemType.red] ?? 0;
    final yellows = counts[GemType.yellow] ?? 0;
    final purples = counts[GemType.purple] ?? 0;
    final greens = counts[GemType.green] ?? 0;
    final blues = counts[GemType.blue] ?? 0;

    if (reds > 0) {
      fx.addStrike(StrikeKind.sword, count: reds, ny: 0.52);
    }
    if (yellows > 0) {
      fx.addStrike(StrikeKind.lightning, count: yellows, ny: 0.50);
    }
    if (purples > 0) {
      fx.addStrike(StrikeKind.curse, count: purples, ny: 0.58);
    }
    // 玩家一侧的特效放在战斗区偏下的位置，留出空间不被下边缘裁掉
    if (greens > 0) {
      fx.addStrike(StrikeKind.heal, count: greens, ny: 0.82);
    }
    if (blues > 0) {
      fx.addStrike(StrikeKind.shield, count: blues, ny: 0.84);
    }
  }

  /// 玩家一侧飘字的左右两条分道。
  ///
  /// 一次连锁会同时产出治疗 / 护盾 / 怒气 / 易伤 好几条飘字，全挤在中轴线上
  /// 会糊成一团看不清。左右分列 + 上下错开之后，四条同时出现也互不遮挡。
  static const double _laneLeft = 0.27;
  static const double _laneRight = 0.73;

  /// 连锁的分级反馈：越深的连锁，字越大、颜色越烫、屏幕抖得越狠。
  ///
  /// 只在 2 连以上出现——1 连是常态，每次都弹字很快就会变成噪音。
  static _ComboTier _comboTier(int combo) {
    if (combo >= 8) {
      return _ComboTier('无双 x$combo', const Color(0xFFFFE9A8), 52, 26);
    }
    if (combo >= 6) {
      return _ComboTier('暴走 x$combo', Palette.danger, 46, 20);
    }
    if (combo >= 4) {
      return _ComboTier('强袭 x$combo', const Color(0xFFFF9A4D), 40, 14);
    }
    return _ComboTier('连击 x$combo', Palette.gold, 32 + (combo - 2) * 2.0, 7);
  }

  void _presentEnemyEvents(List<CombatEvent> events) {
    // 只统计 playerDamage。强化宝石的额外伤害在引擎里已经算进这笔伤害
    // （applyClear 先 _damageEnemy、再补一条 special 事件做标记），
    // 把 special 也加进来会让每一次引爆都虚报一遍伤害，连击越深偏得越多。
    final damage = events
        .where((e) => e.kind == CombatEventKind.playerDamage)
        .fold(0, (sum, e) => sum + e.amount);
    final crit = events.any((e) => e.kind == CombatEventKind.crit);
    if (damage > 0) {
      _totalDamage += damage;
      fx.hitImpact(damage: damage, crit: crit);
      fx.addFloat(
        crit ? '暴击 - $damage' : '- $damage',
        crit ? Palette.gold : Palette.hpEnemy,
        ny: crit ? 0.42 : 0.50,
        size: crit ? 46 : 34,
      );
      fx.shakeBy((3 + damage * 0.03) * (crit ? 2.2 : 1));
      if (crit) {
        // 暴击单独再来一层演出：定格更久 + 一条金色斩击轨迹。
        sfx.crit();
        fx.addStrike(StrikeKind.sword, count: 8, ny: 0.50);
      } else {
        sfx.enemyHit(damage: damage);
      }
    }
    final blocked = events
        .where((e) => e.kind == CombatEventKind.enemyShield)
        .fold(0, (sum, e) => sum + e.amount);
    if (blocked > 0) {
      fx.addFloat(
        '护盾抵挡 $blocked',
        Palette.shield,
        nx: 0.50,
        ny: 0.36,
        size: 17,
      );
    }
    final drain = events
        .where((e) => e.kind == CombatEventKind.enemyDrain)
        .fold(0, (sum, e) => sum + e.amount);
    if (drain > 0) {
      fx.addFloat(
        '吸血 +$drain',
        const Color(0xFFB44BFF),
        nx: 0.76,
        ny: 0.50,
        size: 18,
      );
    }
    if (events.any((e) => e.kind == CombatEventKind.enrage)) {
      fx.addFloat('狂暴', Palette.danger, nx: 0.50, ny: 0.30, size: 30);
      fx.shakeBy(14);
    }
    if (events.any((e) => e.kind == CombatEventKind.ultimate)) {
      fx.addFloat('斩月', Palette.gold, nx: 0.50, ny: 0.33, size: 40);
    }
    // 打空一管血：这是和"打赢"同级的里程碑，演出必须明确区分——大字报
    // 出第几形态 + 一记重震 + 白闪，血条同时从空回满（就是"它又站起来了"）。
    for (final e in events) {
      if (e.kind != CombatEventKind.phaseChange) continue;
      fx.addFloat(
        e.text ?? '第 ${e.amount} 形态',
        Palette.danger,
        nx: 0.50,
        ny: 0.28,
        size: 44,
      );
      fx.shakeBy(22);
      if (fx.allowFlash) fx.enemyFlash = 1;
      sfx.crit();
    }
  }

  void _presentPlayerEvents(List<CombatEvent> events) {
    for (final e in events) {
      switch (e.kind) {
        case CombatEventKind.heal:
          fx.addFloat(
            e.text == '回春' ? '回春 +${e.amount}' : '+${e.amount}',
            Palette.hpPlayer,
            nx: _laneLeft,
            ny: 0.82,
            size: 22,
          );
        case CombatEventKind.shieldGain:
          fx.addFloat(
            '+${e.amount} 护盾',
            Palette.shield,
            nx: _laneLeft,
            ny: 0.90,
            size: 20,
          );
        case CombatEventKind.rage:
          fx.addFloat(
            '怒气 +${e.amount}',
            Palette.rage,
            nx: _laneRight,
            ny: 0.90,
            size: 17,
          );
        case CombatEventKind.curse:
          fx.addFloat(
            '易伤 +${e.amount}',
            Palette.gem(GemType.purple),
            nx: _laneRight,
            ny: 0.82,
            size: 19,
          );
        case CombatEventKind.healBlocked:
          fx.addFloat(
            '治疗 -${e.amount}',
            const Color(0xFFE85A7A),
            nx: _laneRight,
            ny: 0.74,
            size: 17,
          );
        case CombatEventKind.selfBleed:
          // 代价类强化的自损：让玩家每次都被提醒"这份力量是买来的"。
          fx.addFloat(
            '代价 -${e.amount}',
            const Color(0xFFFF3B5C),
            nx: _laneRight,
            ny: 0.70,
            size: 18,
          );
        case CombatEventKind.rageDrain:
          fx.addFloat(
            '怒气 -${e.amount}',
            const Color(0xFF57E0C8),
            nx: _laneRight,
            ny: 0.74,
            size: 17,
          );
        case CombatEventKind.enemyAttack:
          fx.addFloat(
            e.text == '重击' ? '重击 -${e.amount}' : '-${e.amount}',
            Palette.danger,
            nx: 0.50,
            ny: 0.84,
            size: e.text == '重击' ? 34 : 28,
          );
        case CombatEventKind.playerShield:
          fx.addFloat(
            '护盾抵挡 ${e.amount}',
            Palette.shield,
            nx: 0.50,
            ny: 0.95,
            size: 18,
          );
        case CombatEventKind.enemyGuard:
          fx.addFloat(
            '敌方护盾 +${e.amount}',
            const Color(0xFFE0A94A),
            nx: 0.50,
            ny: 0.60,
            size: 16,
          );
        case CombatEventKind.info:
          // 机制提示走战场中央：目前有"治疗被削弱"与无尽模式的"僵持"。
          // 它们没有数字、只有一句话，但对玩家的决策很重要——尤其"僵持"，
          // 它解释了为什么接下来的预警数字会一直变大。
          if (e.text != null) {
            fx.addFloat(e.text!, Palette.danger, nx: 0.50, ny: 0.66, size: 20);
          }
        default:
          break;
      }
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final level = _currentLevel;
    return Scaffold(
      backgroundColor: Palette.bgDeep,
      body: Stack(
        children: [
          // 震屏：整块战斗区 + 棋盘跟着抖（遮罩层不抖，否则面板会跟着晃）。
          // 子树的绘制有各自的 RepaintBoundary，所以这里每帧只是更新一次
          // 合成变换，不会把两边的绘制重新跑一遍。
          //
          // 这层 Transform 必须**恒定挂着**：一旦写成"不震的时候直接返回
          // 子树"，每次震动结束（几乎每次消除都会有）widget 类型就从
          // Transform 切回 Column，整棵子树被重建——血条的填充动画、回合
          // 圆点的脉冲都会从 0 重播一遍，看起来就是每次移动都在"重刷"。
          // offset 为 Offset.zero 时这层等于空操作。
          AnimatedBuilder(
            animation: fx,
            builder: (context, child) =>
                Transform.translate(offset: fx.shakeOffset, child: child),
            child: Column(
              children: [
                Expanded(
                  flex: 46,
                  child: BattleView(
                    battle: battle,
                    fx: fx,
                    level: level,
                    // 打开任何遮罩都先退出必杀瞄准：否则关掉面板回来时
                    // 还停在瞄准态，玩家会以为自己的操作被吞了。
                    onHelp: () => setState(() {
                      _showMenu = false;
                      _showHelp = true;
                      _aimingUltimate = false;
                      _aimingItem = false;
                    }),
                    onMenu: () => setState(() {
                      _showHelp = false;
                      _showMenu = true;
                      _aimingUltimate = false;
                      _aimingItem = false;
                    }),
                  ),
                ),
                _playerStrip(),
                _itemBar(),
                Expanded(
                  flex: 54,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: BoardView(
                      board: board,
                      fx: fx,
                      selected: _selected,
                      hintA: _hintA,
                      hintB: _hintB,
                      enabled: !_inputBlocked,
                      aimingUltimate: _aimingUltimate,
                      itemTargeting: _aimingItem,
                      onSelect: _onSelect,
                      onSwapRequest: _onSwapRequest,
                      onPress: (_) => sfx.tap(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showIntro) _introCard(level),
          if (_showResult) _resultOverlay(level),
          if (_showMenu) _menuOverlay(),
          if (_showHelp) _helpOverlay(),
        ],
      ),
    );
  }

  /// 道具栏：三件一次性支援道具。
  ///
  /// 放在状态条与棋盘之间的独立一栏，而不是挤进状态条那一行——320 像素的
  /// 小屏上，那一行已经被血条、徽章、提示与必杀按钮占满了。
  Widget _itemBar() {
    final rescue = _itemRescueMoment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          for (final kind in ItemKind.values) ...[
            if (kind != ItemKind.values.first) const SizedBox(width: 8),
            Expanded(child: _itemButton(kind, rescue: rescue)),
          ],
        ],
      ),
    );
  }

  Widget _itemButton(ItemKind kind, {required bool rescue}) {
    final count = _items[kind.id] ?? 0;
    final enabled = count > 0 && !_inputBlocked && !battle.isOver;
    final active = kind == ItemKind.hammer && _aimingItem;
    // 危机关头（下一击挡不住）闪起来的是"能救命的那几件"——这里让整栏
    // 都用危险色描边，玩家一眼就知道该看这里。
    final highlight = active || rescue;
    final accent = active ? Palette.gold : Palette.danger;
    final tight = MediaQuery.sizeOf(context).width < 380;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${kind.label}，${kind.description}，剩余 $count 个',
      child: GestureDetector(
        onTap: enabled ? () => _useItem(kind) : null,
        child: Tooltip(
          message: '${kind.label} · ${kind.description}',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: active
                  ? Palette.gold.withValues(alpha: 0.18)
                  : Palette.slotFill.withValues(alpha: 0.75),
              border: Border.all(
                color: highlight
                    ? accent.withValues(alpha: enabled ? 0.95 : 0.4)
                    : Palette.panelEdge,
                width: highlight ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(
                    painter: _ItemGlyphPainter(
                      kind: kind,
                      color: enabled
                          ? Palette.textPrimary
                          : Palette.textDim.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                if (!tight) ...[
                  const SizedBox(width: 5),
                  Text(
                    kind.label,
                    style: AppText.label.copyWith(
                      fontSize: 11,
                      color: enabled
                          ? Palette.textPrimary
                          : Palette.textDim.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                const SizedBox(width: 5),
                Text(
                  'x$count',
                  style: AppText.number.copyWith(
                    fontSize: 12,
                    color: enabled
                        ? Palette.gold
                        : Palette.textDim.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerStrip() {
    final profile = _profile;
    final hasShield = battle.shield > 0;
    // 测量点是整屏宽度（不是容器内宽），这样阈值读起来就是屏幕宽度：
    // 320 的小屏走紧凑文案，常见竖屏（≥390）保持完整文案。
    return LayoutBuilder(
      builder: (context, outer) {
        // 320 像素的小屏 + 系统大字体时，两侧的按钮已经吃掉大半个宽度，
        // 血条只剩不到 50 像素。一旦挂上护盾，文案再长一点就会把这一行挤爆
        // （实测溢出 2.3 像素），所以窄屏改用紧凑写法：
        // 「300/300+40」→「300+40」、「18/100」→「18」。
        // 上限在入场卡与结算面板里都交代过，省掉不影响理解。
        final tight = outer.maxWidth < 380;
        final hpText = switch ((tight, hasShield)) {
          (true, true) => '${battle.playerHp}+${battle.shield}',
          (true, false) => '${battle.playerHp}',
          (false, true) =>
            '${battle.playerHp}/${profile.maxHp}+${battle.shield}',
          (false, false) => '${battle.playerHp}/${profile.maxHp}',
        };
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          decoration: BoxDecoration(
            color: Palette.panel.withValues(alpha: 0.92),
            border: const Border(
              top: BorderSide(color: Palette.panelEdge, width: 1),
              bottom: BorderSide(color: Palette.panelEdge, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EnergyBar(
                      value: battle.playerHpRatio,
                      // 护盾直接画在血条上（叠加段），省掉一个独立标签的位置，
                      // 小屏上才放得下"提示"按钮。
                      shieldValue: hasShield
                          ? battle.shield / profile.maxShield
                          : 0,
                      color: Palette.hpPlayer,
                      leading: '生命',
                      trailing: hpText,
                      height: 14,
                      semanticLabel:
                          '生命 ${battle.playerHp} / ${profile.maxHp}'
                          '${hasShield ? '，护盾 ${battle.shield}' : ''}',
                    ),
                    const SizedBox(height: 6),
                    EnergyBar(
                      // 分母用实际消耗：拿到「月华」之后 60 点怒气就能放必杀，
                      // 进度条与文案也要跟着变，否则玩家看不出这张牌在起作用。
                      value: (battle.rage / battle.ultimateCost).clamp(
                        0.0,
                        1.0,
                      ),
                      color: Palette.rage,
                      leading: '怒气',
                      trailing: battle.rageReady
                          ? '就绪'
                          : (tight
                                ? '${battle.rage}'
                                : '${battle.rage}/${battle.ultimateCost}'),
                      height: 10,
                      semanticLabel:
                          '怒气 ${battle.rage} / ${battle.ultimateCost}',
                    ),
                  ],
                ),
              ),
              // 本局吃到多少强化，一眼看得见——"我变强了"这件事本身就该被展示。
              if (_taken.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildBadge(tight: tight),
              ],
              const SizedBox(width: 8),
              Semantics(
                button: true,
                enabled: !_inputBlocked && !_aimingUltimate,
                label: '提示下一步怎么走',
                child: GestureDetector(
                  onTap: _requestHint,
                  child: Tooltip(
                    message: '提示',
                    child: Container(
                      width: tight ? 38 : 44,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Palette.slotFill.withValues(alpha: 0.75),
                        border: Border.all(color: Palette.panelEdge),
                      ),
                      child: Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: _aimingUltimate
                            ? Palette.textDim.withValues(alpha: 0.4)
                            : Palette.textDim,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 数值变化本来就会触发一次 setState，这里不需要监听每帧的 fx。
              ActionButton(
                label: _aimingUltimate ? '取消' : '斩月',
                hint: _aimingUltimate
                    ? '点击棋盘落点'
                    : (battle.rageReady
                          ? '自选落点'
                          : '怒气 ${battle.rage}/${battle.ultimateCost}'),
                enabled: battle.rageReady && !_busy && !battle.isOver,
                color: _aimingUltimate ? Palette.danger : Palette.rage,
                onTap: _armUltimate,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 状态条右侧的强化计数徽章。点开菜单可以看到完整清单。
  Widget _buildBadge({bool tight = false}) {
    final stacks = _taken.values.fold<int>(0, (sum, n) => sum + n);
    return Semantics(
      label: '本局已获得 $stacks 层强化',
      excludeSemantics: true,
      child: Container(
        width: tight ? 32 : 38,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Palette.gold.withValues(alpha: 0.14),
          border: Border.all(color: Palette.gold.withValues(alpha: 0.55)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 15, color: Palette.gold),
            const SizedBox(height: 1),
            Text(
              '$stacks',
              style: AppText.number.copyWith(fontSize: 11, color: Palette.gold),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 遮罩层

  Widget _introCard(LevelDef level) {
    return Positioned.fill(
      // 点任意处跳过：连续挑战时不必每关都干等两秒。
      child: GestureDetector(
        onTap: () {
          if (_showIntro) setState(() => _showIntro = false);
        },
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform.scale(
                scale: 0.85 + 0.15 * v,
                child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 26,
                ),
                decoration: BoxDecoration(
                  color: Palette.panel.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Palette.panelEdge),
                  boxShadow: [
                    BoxShadow(
                      color: Color(level.enemy.themeColor)
                          .withValues(alpha: 0.28),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(level.name, style: AppText.subtitle),
                    const SizedBox(height: 10),
                    Text(
                      level.enemy.name,
                      style: AppText.title.copyWith(
                        fontSize: 32,
                        color: Color(level.enemy.themeColor),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      level.enemy.taunt,
                      style: AppText.label.copyWith(fontSize: 13, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '回合 ${level.enemy.turnsPerAttack} · 出手 ${level.enemy.attack}',
                      style: AppText.label,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '点击任意处开始',
                      style: AppText.label.copyWith(
                        fontSize: 11,
                        color: Palette.gold.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuOverlay() {
    return MenuOverlay(
      settings: settings,
      currentLevel: _levelIndex,
      taken: Map.of(_taken),
      showLevelSelect: widget.mode == GameMode.campaign,
      modeLabel: widget.mode == GameMode.campaign
          ? '战役'
          : '无尽 · 第 ${_levelIndex + 1} 波',
      // 无尽模式里没有「关」：同一个按钮要说成「从第 1 波重来」。
      restartLabel: widget.mode == GameMode.campaign
          ? (_taken.isEmpty ? '回到第一关' : '重开一局（清空强化）')
          : '从第 1 波重来',
      restartLevelLabel: widget.mode == GameMode.campaign ? '重开本关' : '重开本波',
      onResume: () => setState(() {
        _showMenu = false;
        // 从结算面板点"关卡选择"再关掉菜单时要回到结算：这一局已经结束
        // （battle.isOver 让棋盘不可操作），而 _endResolved 又会挡掉兜底
        // 重算——不把面板放回来，玩家就卡在"棋盘点不动、又没有任何按钮"。
        if (_endResolved && battle.isOver) _showResult = true;
      }),
      onSelectLevel: (index) {
        setState(() => _showMenu = false);
        _startLevel(index);
      },
      onRestartLevel: () {
        setState(() => _showMenu = false);
        _startLevel(_levelIndex);
      },
      onHelp: () => setState(() {
        _showMenu = false;
        _showHelp = true;
      }),
      onNewRun: () {
        setState(() => _showMenu = false);
        _restartCampaign();
      },
      onExitToMenu: widget.onExitToMenu,
    );
  }

  Widget _resultOverlay(LevelDef level) {
    final won = battle.isWon;
    final endless = widget.mode == GameMode.endless;
    final lastLevel = !endless && _levelIndex >= Campaign.levels.length - 1;
    // 三选一是肉鸽的招牌时刻：小屏上把标题与间距收紧一档，让三张牌
    // 一屏全见，而不是要滚动才能看到第三张。没有牌可选的结算不受影响。
    final tightOffer =
        _offer.isNotEmpty && MediaQuery.sizeOf(context).width < 380;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.84),
        child: Center(
          // 结算内容有自己的底板：直接压在棋盘上时分不清哪行字属于面板。
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
            decoration: BoxDecoration(
              color: Palette.panel.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Palette.panelEdge),
              boxShadow: [
                BoxShadow(
                  color: (won ? Palette.gold : Palette.danger).withValues(
                    alpha: 0.18,
                  ),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: tightOffer ? 16 : 26,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    won
                        ? (_campaignClear ? '通关' : '胜利')
                        : (endless ? '终局' : '败北'),
                    style: AppText.title.copyWith(
                      fontSize: tightOffer ? 34 : 44,
                      color: won ? Palette.gold : Palette.danger,
                      letterSpacing: 8,
                    ),
                  ),
                  SizedBox(height: tightOffer ? 4 : 10),
                  if (won) _starRow(),
                  SizedBox(height: tightOffer ? 4 : 10),
                  Text(
                    won
                        ? (_campaignClear
                              ? '你击碎了最后的黑'
                              : endless
                              ? '${level.enemy.name} 已被击退'
                              : '${level.enemy.name} 已被击败')
                        : (endless ? '倒在第 ${_levelIndex + 1} 波' : '再来一次'),
                    style: AppText.label.copyWith(
                      fontSize: tightOffer ? 12 : 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tightOffer ? 10 : 22),
                  // 有强化可选时把战绩压成两行：三张强化卡才是这一屏的主角，
                  // 320 像素的小屏上给它们腾出空间，免得要滚动才看得全。
                  if (_offer.isNotEmpty)
                    Text(
                      '连击 x$_maxCombo · 总伤害 $_totalDamage\n'
                      '$_turnsThisLevel 回合 · 剩余生命 ${battle.playerHp}',
                      style: AppText.label.copyWith(
                        fontSize: 12,
                        height: tightOffer ? 1.45 : 1.9,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else ...[
                    if (won) _statRow('最大连击', 'x$_maxCombo'),
                    if (won) _statRow('总伤害', '$_totalDamage'),
                    _statRow('回合数', '$_turnsThisLevel'),
                    _statRow('剩余生命', '${battle.playerHp}'),
                  ],
                  if (won) ...[
                    const SizedBox(height: 6),
                    if (endless)
                      Text(
                        '最佳 ${settings.endlessBest} 波',
                        style: AppText.label.copyWith(fontSize: 11),
                      )
                    else
                      Text(
                        '最佳 ${settings.starsOf(_levelIndex)} 星 · '
                        '${settings.turnsOf(_levelIndex)} 回合',
                        style: AppText.label.copyWith(fontSize: 11),
                      ),
                  ],
                  SizedBox(height: tightOffer ? 10 : 22),
                  // 胜利且还有下一关：这里不是"继续"按钮，而是三选一。
                  // 每一次选择都会跟着玩家走进下一关，这是全局唯一的成长曲线。
                  if (_offer.isNotEmpty)
                    _upgradePicker()
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (won && lastLevel)
                          _primaryButton('重新开始', _restartCampaign),
                        // 无尽模式连强化池都叠满了，这一波之后没有牌可发——
                        // 但路必须留着，否则玩家只能退到主菜单重打当前波。
                        if (won && endless && _offer.isEmpty)
                          _primaryButton(
                            '继续下一波',
                            () => _startLevel(_levelIndex + 1),
                          ),
                        if (!won && endless) ...[
                          _primaryButton('再来一局', _restartCampaign),
                        ],
                        if (!won && !endless) ...[
                          _primaryButton(
                            '重试本关',
                            () => _startLevel(_levelIndex),
                          ),
                          _ghostButton('回到第一关', _restartCampaign),
                        ],
                        // 空断言在这里会炸：预览 / 测试里的 GameScreen 是根
                        // 页面，本来就没有"回到主菜单"这个去处。
                        if (widget.onExitToMenu != null)
                          _ghostButton('回到主菜单', widget.onExitToMenu!),
                        if (!endless)
                          _ghostButton(
                            '关卡选择',
                            () => setState(() {
                              _showResult = false;
                              _showMenu = true;
                            }),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _upgradePicker() {
    final total = _taken.values.fold<int>(0, (sum, n) => sum + n);
    // 320 宽的窄屏上，三张卡 + 标题 + 脚注要塞进不到 200 像素：卡片在这里
    // 收紧一档（更小的图标与内边距、更紧的行距），尽量让三张牌一屏看全。
    final tight = MediaQuery.sizeOf(context).width < 380;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: Palette.gold),
            const SizedBox(width: 6),
            Text(
              '选择一项强化',
              style: AppText.label.copyWith(color: Palette.gold, fontSize: 12),
            ),
            const Spacer(),
            if (total > 0)
              Text(
                '已有 $total 层',
                style: AppText.label.copyWith(fontSize: 10.5),
              ),
          ],
        ),
        SizedBox(height: tight ? 7 : 10),
        for (final upgrade in _offer) _upgradeCard(upgrade, tight: tight),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '选中的强化会一直带到最后一关',
            style: AppText.label.copyWith(fontSize: 10.5),
          ),
        ),
      ],
    );
  }

  /// 稀有度标签。
  ///
  /// 稀有度刻意不占用新的色相——卡片的颜色已经在说"这条牌属于哪个流派"
  /// 了，再叠一层色相语义只会打架。这里改用"文字 + 金/紫罗兰"这套中性标识。
  Widget _rarityTag(UpgradeRarity rarity, {required bool tight}) {
    final legendary = rarity == UpgradeRarity.legendary;
    final color = legendary ? Palette.gold : const Color(0xFFB9A6FF);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: tight ? 3 : 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        legendary ? '传说' : '稀有',
        style: TextStyle(
          color: color,
          fontSize: tight ? 8 : 9,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _upgradeCard(Upgrade upgrade, {required bool tight}) {
    final color = Color(upgrade.themeColor);
    final stacks = _taken[upgrade.id] ?? 0;
    final legendary = upgrade.rarity == UpgradeRarity.legendary;
    final rare = upgrade.rarity != UpgradeRarity.common;
    final iconSide = tight ? 30.0 : 38.0;
    return Padding(
      padding: EdgeInsets.only(bottom: tight ? 6 : 9),
      child: Semantics(
        button: true,
        label: '${upgrade.name}，${upgrade.desc}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => _takeUpgrade(upgrade),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              tight ? 9 : 11,
              tight ? 7 : 10,
              tight ? 10 : 12,
              tight ? 7 : 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.20),
                  color.withValues(alpha: 0.06),
                ],
              ),
              // 稀有度靠"描边更重、光晕更强"表达：一眼能看出这张牌不一样，
              // 又不会和功能配色抢意思。
              border: Border.all(
                color: color.withValues(alpha: rare ? 0.95 : 0.62),
                width: legendary ? 2.2 : (rare ? 1.7 : 1.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(
                    alpha: legendary ? 0.42 : (rare ? 0.30 : 0.22),
                  ),
                  blurRadius: legendary ? 22 : (rare ? 18 : 16),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: iconSide,
                  height: iconSide,
                  // 图标本身是静态的，加一层 RepaintBoundary 免得跟着面板一起重绘。
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _UpgradeGlyphPainter(upgrade.icon, color),
                    ),
                  ),
                ),
                SizedBox(width: tight ? 8 : 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (rare) ...[
                            _rarityTag(upgrade.rarity, tight: tight),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              upgrade.name,
                              style: AppText.button.copyWith(
                                fontSize: tight ? 13 : 15,
                                color: Palette.textPrimary,
                                letterSpacing: 1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (stacks > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '已有 x$stacks',
                              style: AppText.label.copyWith(
                                fontSize: 10,
                                color: color,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 代价型强化用一个小红点 + 红字提示：不额外占一行，
                          // 但玩家一眼就知道"这条不是白拿的"。
                          if (upgrade.isCostly) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 3.5),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Palette.danger,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              upgrade.desc,
                              style: AppText.label.copyWith(
                                fontSize: tight ? 10.5 : 11.5,
                                height: 1.3,
                                color: upgrade.isCostly
                                    ? const Color(0xFFFF8095)
                                    : Palette.textPrimary.withValues(
                                        alpha: 0.82,
                                      ),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: color.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _starRow() {
    final stars = _starsEarned;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 34,
              color: i < stars ? Palette.gold : Palette.panelEdge,
            ),
          ),
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: AppText.label,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 88,
            child: Text(value, style: AppText.number.copyWith(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        sfx.tap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Palette.gold, Color(0xFFC98A33)],
          ),
          boxShadow: [
            BoxShadow(
              color: Palette.gold.withValues(alpha: 0.45),
              blurRadius: 18,
            ),
          ],
        ),
        child: Text(
          label,
          style: AppText.button.copyWith(color: const Color(0xFF2A1600)),
        ),
      ),
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        sfx.tap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.panelEdge),
        ),
        child: Text(
          label,
          style: AppText.button.copyWith(color: Palette.textDim),
        ),
      ),
    );
  }

  /// 重开一局：清空全部强化，从第一关重新来过。
  void _restartCampaign() {
    _taken.clear();
    _offer = const [];
    _profile = Campaign.player;
    _carryHp = _profile.maxHp;
    _startLevel(0);
  }

  Widget _helpOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showHelp = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.80),
          child: Center(
            child: HelpPanel(onClose: () => setState(() => _showHelp = false)),
          ),
        ),
      ),
    );
  }
}

/// 道具栏上的图标。绘制逻辑在 [ItemArt] 里，这里只做一层画家适配。
class _ItemGlyphPainter extends CustomPainter {
  final ItemKind kind;
  final Color color;

  const _ItemGlyphPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    ItemArt.paint(canvas, Offset.zero & size, kind, color);
  }

  @override
  bool shouldRepaint(covariant _ItemGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

/// 强化卡片上的图标。绘制逻辑在 [UpgradeArt] 里，这里只做一层画家适配。
class _UpgradeGlyphPainter extends CustomPainter {
  final UpgradeIcon icon;
  final Color color;

  const _UpgradeGlyphPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    UpgradeArt.paint(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height),
      icon,
      color,
      glow: 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant _UpgradeGlyphPainter old) =>
      old.icon != icon || old.color != color;
}

/// 一档连锁反馈的样式。
class _ComboTier {
  final String text;
  final Color color;
  final double size;
  final double shake;

  const _ComboTier(this.text, this.color, this.size, this.shake);
}
