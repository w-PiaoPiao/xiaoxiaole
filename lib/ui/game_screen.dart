import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/battle.dart';
import '../engine/board.dart';
import '../engine/gem.dart';
import '../engine/levels.dart';
import 'battle_view.dart';
import 'board_view.dart';
import 'fx.dart';
import 'gem_art.dart';
import 'hud.dart';
import 'palette.dart';

/// 一局游戏的总控：串起棋盘结算、战斗数值与全部动画时序。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final FxController fx;
  late BoardEngine board;
  late BattleState battle;
  late int _levelIndex;

  /// 玩家跨关卡继承的生命。
  int _carryHp = Campaign.player.maxHp;

  int? _selected;
  bool _busy = false;
  bool _showIntro = true;
  bool _showResult = false;
  bool _showHelp = false;
  bool _campaignClear = false;
  int _turnsThisLevel = 0;

  Duration _lastTick = Duration.zero;
  double _sinceCheck = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    fx = FxController();
    _ticker = createTicker(_onTick)..start();
    _startLevel(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    fx.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    fx.tick(dt.clamp(0.0, 0.05));

    // 空闲时每秒自检一次：
    //  - 战斗已经结束却没弹出结算面板（任何原因漏结算），立刻补上，绝不把玩家
    //    留在"敌人空血但什么也没发生"的状态里；
    //  - 否则巡检视觉层，发现与引擎脱节就记录现场并重画。
    if (!_busy && !_showIntro && !_showResult) {
      _sinceCheck += dt;
      if (_sinceCheck >= 1.0) {
        _sinceCheck = 0;
        if (battle.isOver) {
          _handleBattleEnd();
        } else {
          _ensureVisualSync('空闲巡检');
        }
      }
    }
  }

  // ------------------------------------------------------------------ 关卡流程

  void _startLevel(int index) {
    _levelIndex = index;
    final level = Campaign.levels[index];
    board = BoardEngine()..reset();
    battle = BattleState(
      def: level.enemy,
      levelIndex: index,
      playerHp: _carryHp,
    );
    _selected = null;
    _busy = false;
    _showResult = false;
    _showIntro = true;
    _campaignClear = false;
    _turnsThisLevel = 0;
    _endResolved = false;
    fx.reset();
    _seedBoardAnimation();
    _refresh();
    // 开场卡停留一会儿后自动进入战斗。
    _pause(2.0).then((_) {
      if (_disposed || _levelIndex != index) return;
      setState(() => _showIntro = false);
    });
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
        debugPrint('⚠️ 引擎棋盘出现 $holes 个空洞[$where]，已补全（这属于不该发生的情况，'
            '请把这条日志连同操作步骤一并反馈）');
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
      final brokenPosition = !visual.x.isFinite ||
          !visual.y.isFinite ||
          (!visual.moving && (visual.x - gx).abs() > 0.01);
      if ((visual.toX - gx).abs() > 0.01 ||
          (visual.toY - gy).abs() > 0.01 ||
          brokenPosition) {
        if (misplaced.length < 4) {
          misplaced.add('#${cell.gemId}→格${cell.index} 目标(${visual.toX},${visual.toY}) '
              '当前(${visual.x.toStringAsFixed(2)},${visual.y.toStringAsFixed(2)}) t=${visual.t.toStringAsFixed(2)}');
        }
      }
    }

    if (expected.length == actual.length &&
        expected.containsAll(actual) &&
        misplaced.isEmpty) {
      return;
    }

    {
      final visuals = fx.gems.values.toList();
      final outside = visuals.where((g) => g.y < 0 || g.y > BoardEngine.rows - 1).length;
      final broken = visuals.where((g) => !g.x.isFinite || !g.y.isFinite).length;
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

  void _onSelect(int index) {
    if (_busy || battle.isOver || _showIntro || _showResult) return;
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
      _selected = null;
      _attemptSwap(current, index);
      return;
    }
    setState(() => _selected = index);
  }

  void _onSwapRequest(int a, int b) {
    if (_busy || battle.isOver || _showIntro || _showResult) return;
    _selected = null;
    _attemptSwap(a, b);
  }

  Future<void> _attemptSwap(int a, int b) async {
    if (_busy) return;
    if (!board.canSwap(a, b)) {
      // 非法交换：轻微抖动提示
      fx.shakeBy(5);
      setState(() => _selected = null);
      return;
    }
    _busy = true;
    setState(() => _selected = null);
    // try/finally 兜住：无论中途发生什么，都一定会把 _busy 放掉，
    // 绝不能让玩家被永久锁住操作。
    try {
      board.swapCells(a, b);
      fx.applySnapshot(board.snapshot(), fallDuration: 0.16);
      await _pause(0.15);

      final steps = board.resolveSwap(a, b);
      if (steps.isEmpty) {
        board.swapCells(a, b);
        fx.applySnapshot(board.snapshot(), fallDuration: 0.16);
        await _pause(0.16);
        return;
      }

      _turnsThisLevel++;
      await _playSteps(steps);
      await _finishTurn();
    } finally {
      if (!_disposed) {
        _busy = false;
        _ensureVisualSync('交换结算');
        _refresh();
      }
    }
  }

  Future<void> _castUltimate() async {
    if (_busy || !battle.canCastUltimate) return;
    _busy = true;
    setState(() => _selected = null);
    try {
    final events = battle.castUltimate();
    fx.triggerSlash();
    fx.lunge();
    fx.shakeBy(24);
    fx.flashEnemy();
    _presentEnemyEvents(events);
    await _pause(0.42);

    final steps = board.resolveUltimate(board.index(BoardEngine.cols ~/ 2, BoardEngine.rows ~/ 2));
    await _playSteps(steps, multiplier: Campaign.player.ultimateMultiplier);
    await _finishTurn();
    } finally {
      if (!_disposed) {
        _busy = false;
        _ensureVisualSync('必杀结算');
        _refresh();
      }
    }
  }

  // ------------------------------------------------------------------ 结算时序

  Future<void> _playSteps(List<CascadeStep> steps, {double multiplier = 1.0}) async {
    for (final step in steps) {
      if (_disposed) return;

      if (step.activations.isNotEmpty) {
        for (final activation in step.activations) {
          fx.playActivation(activation);
        }
        fx.shakeBy(5 + step.activations.length * 2.0);
      }

      fx.beginClear(step.cleared);
      if (step.combo >= 2) {
        fx.addLabel(
          '连击 x${step.combo}',
          BoardEngine.cols / 2,
          BoardEngine.rows / 2,
          Palette.gold,
          size: 32,
        );
      }
      await _pause(0.12);

      fx.applySnapshot(
        step.snapshot,
        spawnStartY: step.spawnStartY,
        fallDuration: 0.30,
      );
      // 刚落位这一刻，视觉层必须与快照完全对齐（可能有宝石还在下落途中）。
      assert(() {
        if (fx.gems.length != step.snapshot.length) {
          debugPrint('⚠️ 快照未完整落到视觉层: 快照=${step.snapshot.length} '
              '视觉=${fx.gems.length} combo=${step.combo} '
              '移除数=${step.cleared.length} 生成数=${step.spawns.length}');
        }
        return true;
      }());

      final events = battle.applyClear(
        step.counts,
        combo: step.combo,
        specialBonus: step.specialBonus,
        multiplier: multiplier,
      );
      _presentEnemyEvents(events);
      _presentPlayerEvents(events);
      _refresh();

      if (step.spawns.isNotEmpty) {
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

      await fx.settle();
      if (_disposed) return;
      await _pause(0.04);
    }
  }

  Future<void> _finishTurn() async {
    if (battle.isOver) {
      await _handleBattleEnd();
      return;
    }

    final events = battle.endPlayerTurn();
    final incoming = events.where((e) => e.kind == CombatEventKind.enemyAttack);
    if (incoming.isNotEmpty) {
      fx.lunge();
      await _pause(0.20);
      fx.shakeBy(18);
      fx.playerFlash = 1;
      _presentPlayerEvents(events);
      await _pause(0.30);
    } else {
      _presentPlayerEvents(events);
    }

    _refresh();
    if (battle.isOver) {
      await _handleBattleEnd();
      return;
    }

    if (!board.hasValidMove()) {
      board.shuffleBoard();
      fx.applySnapshot(board.snapshot(), fallDuration: 0.35);
      fx.addLabel('重新排列', BoardEngine.cols / 2, BoardEngine.rows / 2, Palette.shield, size: 26);
      await fx.settle();
      _refresh();
    }
  }

  /// 结算一次胜负。带一次性保护：重复调用只会执行一次。
  bool _endResolved = false;

  Future<void> _handleBattleEnd() async {
    if (_endResolved) return;
    _endResolved = true;
    if (battle.isWon) {
      _carryHp = math.min(
        Campaign.player.maxHp,
        math.max(
          (Campaign.player.maxHp * 0.6).round(),
          battle.playerHp + (Campaign.player.maxHp * 0.35).round(),
        ),
      );
      fx.dissolveTarget = 1;
      fx.shakeBy(16);
      await _pause(1.0);
    } else {
      _carryHp = Campaign.player.maxHp;
      fx.playerFlash = 1;
      fx.shakeBy(20);
      await _pause(0.5);
    }
    if (_disposed) return;
    setState(() {
      _campaignClear = battle.isWon && _levelIndex >= Campaign.levels.length - 1;
      _showResult = true;
    });
  }

  // ------------------------------------------------------------------ 飘字

  void _presentEnemyEvents(List<CombatEvent> events) {
    final damage = events
        .where((e) => e.kind == CombatEventKind.playerDamage || e.kind == CombatEventKind.special)
        .fold(0, (sum, e) => sum + e.amount);
    if (damage > 0) {
      fx.flashEnemy();
      fx.addFloat('- $damage', Palette.hpEnemy, ny: 0.50, size: 34);
      fx.shakeBy(3 + damage * 0.03);
    }
    final blocked = events
        .where((e) => e.kind == CombatEventKind.enemyShield)
        .fold(0, (sum, e) => sum + e.amount);
    if (blocked > 0) {
      fx.addFloat('护盾抵挡 $blocked', Palette.shield, ny: 0.44, size: 17);
    }
    final drain = events
        .where((e) => e.kind == CombatEventKind.enemyDrain)
        .fold(0, (sum, e) => sum + e.amount);
    if (drain > 0) {
      fx.addFloat('吸血 +$drain', const Color(0xFFB44BFF), ny: 0.58, size: 18);
    }
    if (events.any((e) => e.kind == CombatEventKind.enrage)) {
      fx.addFloat('狂暴', Palette.danger, ny: 0.40, size: 30);
      fx.shakeBy(14);
    }
    if (events.any((e) => e.kind == CombatEventKind.ultimate)) {
      fx.addFloat('斩月', Palette.gold, ny: 0.38, size: 40);
    }
  }

  void _presentPlayerEvents(List<CombatEvent> events) {
    for (final e in events) {
      switch (e.kind) {
        case CombatEventKind.heal:
          fx.addFloat('+${e.amount}', Palette.hpPlayer, ny: 0.93, size: 22);
        case CombatEventKind.shieldGain:
          fx.addFloat('+${e.amount} 护盾', Palette.shield, ny: 0.97, size: 20);
        case CombatEventKind.rage:
          fx.addFloat('怒气 +${e.amount}', Palette.rage, ny: 1.00, size: 17);
        case CombatEventKind.curse:
          fx.addFloat('易伤 +${e.amount}', Palette.gem(GemType.purple), ny: 0.90, size: 19);
        case CombatEventKind.healBlocked:
          fx.addFloat('治疗 -${e.amount}', const Color(0xFFE85A7A), ny: 0.86, size: 17);
        case CombatEventKind.enemyAttack:
          fx.addFloat(
            e.text == '重击' ? '重击 -${e.amount}' : '-${e.amount}',
            Palette.danger,
            ny: 0.88,
            size: e.text == '重击' ? 34 : 28,
          );
        case CombatEventKind.playerShield:
          fx.addFloat('护盾抵挡 ${e.amount}', Palette.shield, ny: 0.94, size: 18);
        case CombatEventKind.enemyGuard:
          fx.addFloat('敌方护盾 +${e.amount}', const Color(0xFFE0A94A), ny: 0.60, size: 16);
        default:
          break;
      }
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final level = Campaign.levels[_levelIndex];
    return Scaffold(
      backgroundColor: Palette.bgDeep,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 46,
                child: BattleView(battle: battle, fx: fx, level: level),
              ),
              _playerStrip(),
              Expanded(
                flex: 54,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: BoardView(
                    board: board,
                    fx: fx,
                    selected: _selected,
                    enabled: !_busy && !battle.isOver && !_showIntro && !_showResult,
                    onSelect: _onSelect,
                    onSwapRequest: _onSwapRequest,
                  ),
                ),
              ),
            ],
          ),
          if (_showIntro) _introCard(level),
          if (_showResult) _resultOverlay(level),
          if (_showHelp) _helpOverlay(),
          Positioned(
            top: 0,
            right: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => setState(() => _showHelp = !_showHelp),
                icon: const Icon(Icons.help_outline, color: Palette.textDim, size: 20),
                tooltip: '玩法说明',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerStrip() {
    final profile = Campaign.player;
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
                  color: Palette.hpPlayer,
                  leading: '生命',
                  trailing: '${battle.playerHp}/${profile.maxHp}',
                  height: 14,
                ),
                const SizedBox(height: 6),
                EnergyBar(
                  value: battle.rage / profile.maxRage,
                  color: Palette.rage,
                  leading: '怒气',
                  trailing: battle.rageReady ? '就绪' : '${battle.rage}',
                  height: 10,
                ),
              ],
            ),
          ),
          if (battle.shield > 0) ...[
            const SizedBox(width: 10),
            Tag(
              text: '护盾 ${battle.shield}',
              color: Palette.shield,
              icon: Icons.shield,
              dense: true,
            ),
          ],
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: fx,
            builder: (context, _) => ActionButton(
              label: '斩月',
              hint: battle.rageReady ? '斩杀全场' : '怒气 ${battle.rage}/100',
              enabled: battle.rageReady && !_busy && !battle.isOver,
              progress: battle.rage / profile.maxRage,
              onTap: _castUltimate,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 遮罩层

  Widget _introCard(LevelDef level) {
    return Positioned.fill(
      child: IgnorePointer(
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
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 26),
                decoration: BoxDecoration(
                  color: Palette.panel.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Palette.panelEdge),
                  boxShadow: [
                    BoxShadow(
                      color: Color(level.enemy.themeColor).withValues(alpha: 0.28),
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
                  ),
                  const SizedBox(height: 12),
                  Text(
                    level.enemy.taunt,
                    style: AppText.label.copyWith(fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 22),
                  Text('回合 ${level.enemy.turnsPerAttack} · 出手 ${level.enemy.attack}',
                      style: AppText.label),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultOverlay(LevelDef level) {
    final won = battle.isWon;
    final lastLevel = _levelIndex >= Campaign.levels.length - 1;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? (_campaignClear ? '通关' : '胜利') : '败北',
                style: AppText.title.copyWith(
                  fontSize: 44,
                  color: won ? Palette.gold : Palette.danger,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                won
                    ? (_campaignClear ? '你击碎了最后的黑' : '${level.enemy.name} 已被击败')
                    : '再来一次',
                style: AppText.label.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 26),
              _statRow('回合数', '$_turnsThisLevel'),
              _statRow('剩余生命', '${battle.playerHp}'),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (won && !lastLevel)
                    _primaryButton('进入下一关', () => _startLevel(_levelIndex + 1)),
                  if (won && lastLevel)
                    _primaryButton('重新开始', () => _restartCampaign()),
                  if (!won) ...[
                    _primaryButton('重试本关', () => _startLevel(_levelIndex)),
                    const SizedBox(width: 12),
                    _ghostButton('回到第一关', () => _restartCampaign()),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
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
            child: Text(label, style: AppText.label, textAlign: TextAlign.right),
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
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Palette.gold, Color(0xFFC98A33)]),
          boxShadow: [
            BoxShadow(color: Palette.gold.withValues(alpha: 0.45), blurRadius: 18),
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
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.panelEdge),
        ),
        child: Text(label, style: AppText.button.copyWith(color: Palette.textDim)),
      ),
    );
  }

  void _restartCampaign() {
    _carryHp = Campaign.player.maxHp;
    _startLevel(0);
  }

  Widget _helpOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showHelp = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Palette.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Palette.panelEdge),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('玩法说明', style: AppText.title.copyWith(fontSize: 18)),
                  const SizedBox(height: 14),
                  for (final type in GemType.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          _miniGem(type),
                          const SizedBox(width: 12),
                          Text(
                            gemEffectLabel(type),
                            style: AppText.label.copyWith(
                              fontSize: 12.5,
                              color: Palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    '· 三连消除，四连生成破空宝石（整行/整列），五连生成棱镜（清空同色），\n'
                    '  拐角消除生成爆裂宝石（3x3）。\n'
                    '· 与强化宝石交换可以直接引爆它。\n'
                    '· 怒气满 100 可释放必杀「斩月」：十字清除并按倍率结算。\n'
                    '· 注意敌方行动回合，及时用护盾与治疗抵挡。',
                    style: AppText.label.copyWith(fontSize: 11.5, height: 1.75),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text('点击任意处关闭', style: AppText.label.copyWith(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniGem(GemType type) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(painter: _MiniGemPainter(type)),
    );
  }
}

/// 帮助面板里的宝石图标，直接复用棋盘上的宝石美术。
class _MiniGemPainter extends CustomPainter {
  final GemType type;

  const _MiniGemPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    GemArt.paint(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height),
      type,
      SpecialKind.none,
      glow: 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGemPainter oldDelegate) => oldDelegate.type != type;
}
