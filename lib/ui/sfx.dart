import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// 音效与触感反馈的统一入口。
///
/// 设计原则：**任何一次反馈都不能影响游戏本身**。音频插件在测试环境、
/// 无声设备或解码失败时不保证成功，因此所有调用都是"尽力而为"，
/// 异常一律吞掉；触感同样如此。
class SfxController {
  /// 音频资源预加载是否已完成。未完成时 [play] 直接跳过，避免卡顿。
  bool _ready = false;

  /// 测试环境不加载音频插件：既没有声音，也能避免 MissingPluginException。
  bool get _audioAllowed => !Platform.environment.containsKey('FLUTTER_TEST');

  bool soundEnabled = true;
  bool hapticsEnabled = true;

  /// 每种音效轮转使用的播放器池：同一音效连续触发时不被自己打断。
  final Map<String, List<AudioPlayer>> _pools = {};
  final Map<String, int> _cursor = {};

  static const _poolSize = 3;

  static const List<String> _sources = [
    'clear1', 'clear2', 'clear3', 'special', 'burst',
    'hit', 'crit', 'hurt', 'ultimate', 'win', 'lose',
  ];

  /// 预加载全部音效。在 `main()` 里 await，之后 [play] 才是即时的。
  Future<void> load() async {
    if (!_audioAllowed) return;
    // 全部播放器并行创建：串行 await 三十次会让启动明显卡一下。
    await Future.wait(_sources.map((name) async {
      final players = await Future.wait(
        List.generate(_poolSize, (_) => _createPlayer(name)),
      );
      _pools[name] = players;
      _cursor[name] = 0;
    }));
    _ready = true;
  }

  Future<AudioPlayer> _createPlayer(String name) async {
    final player = AudioPlayer();
    try {
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(0.85);
      await player.setSource(AssetSource('sfx/$name.wav'));
    } catch (_) {
      // 预加载失败就让这颗播放器保持静默，不影响其余音效。
    }
    return player;
  }

  Future<void> dispose() async {
    for (final players in _pools.values) {
      for (final p in players) {
        try {
          await p.dispose();
        } catch (_) {}
      }
    }
    _pools.clear();
    _ready = false;
  }

  /// 播放一个音效。同一音效在池中轮转，连续触发不会互相打断。
  void play(String name, {double volume = 0.85}) {
    if (!soundEnabled || !_ready) return;
    final players = _pools[name];
    if (players == null || players.isEmpty) return;
    final index = (_cursor[name] ?? 0) % players.length;
    _cursor[name] = index + 1;
    final player = players[index];
    // 不 await：音频调用绝不能阻塞游戏循环。
    () async {
      try {
        await player.stop();
        await player.setVolume(volume);
        await player.resume();
      } catch (_) {}
    }();
  }

  // ---------------------------------------------------------------- 触感

  void _haptic(Future<void> Function() action) {
    if (!hapticsEnabled) return;
    action().catchError((_) {});
  }

  /// 轻点：选中宝石、切换选项。
  void tap() => _haptic(HapticFeedback.selectionClick);

  /// 一次消除落定。
  void pop() => _haptic(HapticFeedback.lightImpact);

  /// 打击命中，越重越强。
  void impact({double weight = 1}) {
    if (weight >= 1.15) {
      _haptic(HapticFeedback.heavyImpact);
    } else {
      _haptic(HapticFeedback.mediumImpact);
    }
  }

  /// 无效操作（非法交换）。
  void reject() => _haptic(HapticFeedback.vibrate);

  // ---------------------------------------------------- 语义化的游戏事件

  /// 消除：连击越高音阶越高、手感越强。
  void combo(int combo) {
    final step = combo.clamp(1, 3);
    play('clear$step', volume: 0.8);
    if (step == 1) {
      pop();
    } else {
      impact(weight: 1 + step * 0.05);
    }
  }

  void spawnSpecial() => play('special');

  void activateSpecial() {
    play('burst');
    impact(weight: 1.2);
  }

  void enemyHit({required int damage}) {
    play('hit', volume: damage > 200 ? 0.95 : 0.78);
    impact(weight: damage / 200);
  }

  /// 暴击：比普通命中更亮、更重的一记。
  void crit() {
    play('crit', volume: 0.95);
    _haptic(HapticFeedback.heavyImpact);
  }

  void playerHurt() {
    play('hurt');
    _haptic(HapticFeedback.heavyImpact);
  }

  void castUltimate() {
    play('ultimate');
    _haptic(HapticFeedback.heavyImpact);
  }

  void victory() => play('win');
  void defeat() => play('lose');
}
