import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置与进度存档。
///
/// 持久化是"尽力而为"的：插件在测试环境或异常情况下不可用时，全部退化为
/// 内存中的默认值，游戏照常可玩（不因为存不上档而崩）。读档同样是容错的——
/// 任何一个键的类型与预期不符（旧版本写法不同、存档被外部改坏）都只让那
/// 一项回落默认值，绝不会把启动流程一起拖垮。
class AppSettings extends ChangeNotifier {
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kScreenShake = 'settings.screenShake';
  static const _kUnlocked = 'progress.unlockedLevel';
  static const _kStarsPrefix = 'progress.stars.';
  static const _kTurnsPrefix = 'progress.turns.';
  static const _kEndlessBest = 'progress.endlessBest';

  /// 「继续游戏」存档：战役与无尽**各占一个槽**，每槽整局状态序列化成
  /// 一个 JSON 字符串。
  ///
  /// 单键写入是为了**自洽**：分开写 mode / level / 强化时，中途被杀会留下
  /// "新关卡 + 旧强化"这类半截组合，恢复出来的 build 与退出时并不一致。
  /// 曾经整个游戏只有单个槽：从无尽切去战役随便开一局，无尽进度就被
  /// 静默覆盖、不可恢复——分槽之后两边互不干扰，`resume` 取较新的那个。
  static const _kResume = 'progress.resume';
  static const _kResumeCampaign = 'progress.resume.campaign';
  static const _kResumeEndless = 'progress.resume.endless';

  // 旧版（散键）格式，仅用于读档兼容与清理，不再写入。
  static const _kResumeMode = 'progress.resume.mode';
  static const _kResumeLevel = 'progress.resume.level';
  static const _kResumeHp = 'progress.resume.hp';
  static const _kResumeUpgradesPrefix = 'progress.resume.upgrade.';

  /// 强化层数的合法上限：挡住损坏存档里"叠 10 万层"这类数值。
  static const int _maxUpgradeStacks = 99;

  /// 道具库存的合法上限：挡住损坏存档里"带 99 个锤子"这类数值。
  static const int _maxItemCount = 9;

  SharedPreferences? _prefs;

  bool _sound = true;
  bool _haptics = true;
  bool _screenShake = true;

  /// 已解锁的最高关卡索引（0 表示只解锁了第一关）。
  int _unlockedLevel = 0;

  /// 无尽模式的最佳波次（0 表示还没玩过）。
  int _endlessBest = 0;

  /// 每关的最佳战绩。
  final Map<int, int> bestStars = {};
  final Map<int, int> bestTurns = {};

  bool get sound => _sound;
  bool get haptics => _haptics;
  bool get screenShake => _screenShake;
  int get unlockedLevel => _unlockedLevel;
  int get endlessBest => _endlessBest;

  /// 进行中的对局，按模式分槽（见 [_kResumeCampaign] 的说明）。
  ResumeData? _resumeCampaign;
  ResumeData? _resumeEndless;

  /// 进行中的一局（主菜单的「继续游戏」）：两个模式槽里**较新**的那个。
  /// null 表示没有可继续的对局。
  ResumeData? get resume {
    final c = _resumeCampaign;
    final e = _resumeEndless;
    if (c == null) return e;
    if (e == null) return c;
    return e.savedAt >= c.savedAt ? e : c;
  }

  /// 某个模式的进行中对局。null 表示该模式没有可继续的对局。
  ResumeData? resumeFor(GameMode mode) =>
      mode == GameMode.endless ? _resumeEndless : _resumeCampaign;

  void _setResume(GameMode mode, ResumeData? data) {
    if (mode == GameMode.endless) {
      _resumeEndless = data;
    } else {
      _resumeCampaign = data;
    }
  }

  int starsOf(int levelIndex) => bestStars[levelIndex] ?? 0;
  int turnsOf(int levelIndex) => bestTurns[levelIndex] ?? 0;

  bool isUnlocked(int levelIndex) => levelIndex <= _unlockedLevel;

  /// 是否已经通关过至少一关（用来决定要不要展示关卡选择）。
  bool get hasProgress =>
      _unlockedLevel > 0 || bestStars.isNotEmpty || _endlessBest > 0;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
      return;
    }
    final p = _prefs!;
    try {
      _sound = _bool(p, _kSound, true);
      _haptics = _bool(p, _kHaptics, true);
      _screenShake = _bool(p, _kScreenShake, true);
      _unlockedLevel = _nonNegative(_int(p, _kUnlocked, 0));
      _endlessBest = _nonNegative(_int(p, _kEndlessBest, 0));
      _resumeCampaign = null;
      _resumeEndless = null;
      _readResume(p);
      for (final key in p.getKeys()) {
        if (key.startsWith(_kStarsPrefix)) {
          final index = int.tryParse(key.substring(_kStarsPrefix.length));
          if (index != null && index >= 0) {
            bestStars[index] = _nonNegative(_int(p, key, 0));
          }
        } else if (key.startsWith(_kTurnsPrefix)) {
          final index = int.tryParse(key.substring(_kTurnsPrefix.length));
          if (index != null && index >= 0) {
            bestTurns[index] = _nonNegative(_int(p, key, 0));
          }
        }
      }
    } catch (_) {
      // 读到一半失手：保留已经读出来的部分，其余留在默认值。
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ 容错读取

  /// 按实际类型取值：键存在但类型不符（例如旧版把开关存成了字符串）时
  /// 用回默认值，而不是让 `as bool` 抛异常。shared_preferences 的强类型
  /// getter 是直接强转的，这里必须自己判类型。
  static bool _bool(SharedPreferences p, String key, bool fallback) {
    final value = p.get(key);
    return value is bool ? value : fallback;
  }

  static int _int(SharedPreferences p, String key, int fallback) {
    final value = p.get(key);
    return value is int ? value : fallback;
  }

  static String? _string(SharedPreferences p, String key) {
    final value = p.get(key);
    return value is String ? value : null;
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  /// 把「强化 id → 层数」洗成可用的形式：非法条目直接丢弃。
  static Map<String, int> _sanitizeUpgrades(Object? raw) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is! String || key.isEmpty || value is! int || value <= 0) {
          return;
        }
        out[key] = value.clamp(1, _maxUpgradeStacks);
      });
    }
    return out;
  }

  /// 把「道具 id → 数量」洗成可用的形式：非法条目直接丢弃。
  static Map<String, int> _sanitizeItems(Object? raw) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is! String || key.isEmpty || value is! int || value <= 0) {
          return;
        }
        out[key] = value.clamp(1, _maxItemCount);
      });
    }
    return out;
  }

  /// 读档：旧单键（迁移进对应模式的槽）→ 新双槽 → 旧散键（更老版本兜底）。
  void _readResume(SharedPreferences p) {
    final legacy = _decodeResume(_string(p, _kResume));
    if (legacy != null) {
      _setResume(legacy.mode, legacy);
    }
    final campaign = _decodeResume(_string(p, _kResumeCampaign));
    if (campaign != null) _setResume(GameMode.campaign, campaign);
    final endless = _decodeResume(_string(p, _kResumeEndless));
    if (endless != null) _setResume(GameMode.endless, endless);

    if (_resumeCampaign != null || _resumeEndless != null) return;

    // 旧版（散键）格式兜底：老存档也能继续打。
    final mode = _string(p, _kResumeMode);
    final level = _int(p, _kResumeLevel, -1);
    if (mode == null || level < 0) return;
    final upgrades = <String, int>{};
    for (final key in p.getKeys()) {
      if (!key.startsWith(_kResumeUpgradesPrefix)) continue;
      final id = key.substring(_kResumeUpgradesPrefix.length);
      final stacks = _int(p, key, 0);
      if (id.isNotEmpty && stacks > 0) {
        upgrades[id] = stacks.clamp(1, _maxUpgradeStacks);
      }
    }
    _setResume(
      mode == 'endless' ? GameMode.endless : GameMode.campaign,
      ResumeData(
        mode: mode == 'endless' ? GameMode.endless : GameMode.campaign,
        level: level,
        carryHp: _nonNegative(_int(p, _kResumeHp, 0)),
        upgrades: upgrades,
      ),
    );
  }

  /// 解析一槽的 JSON；损坏或字段不合法时返回 null（当作没有这局存档）。
  ResumeData? _decodeResume(String? packed) {
    if (packed == null) return null;
    try {
      final decoded = jsonDecode(packed);
      if (decoded is Map) {
        final level = decoded['level'];
        // level 越界（十三关之外）留给上层按模式夹取，这里只挡负数
        // ——读档层不认识 Campaign，不该替它做范围判断。
        if (level is int && level >= 0) {
          final hp = decoded['hp'];
          final savedAt = decoded['savedAt'];
          return ResumeData(
            mode: decoded['mode'] == 'endless'
                ? GameMode.endless
                : GameMode.campaign,
            level: level,
            carryHp: hp is int ? _nonNegative(hp) : 0,
            upgrades: _sanitizeUpgrades(decoded['upgrades']),
            // 旧存档没有 items 键：当作空库存，开局时按默认发放。
            items: _sanitizeItems(decoded['items']),
            savedAt: savedAt is int ? savedAt : 0,
          );
        }
      }
    } catch (_) {
      // JSON 坏了：当作没有这局存档，不让它挡住启动。
    }
    return null;
  }

  // ------------------------------------------------------------ 写入

  /// 写盘。所有写入都是"尽力而为"：
  ///  - 插件不可用（`_prefs == null`）时静默跳过；
  ///  - 写入抛出的同步异常与**异步写盘失败**都被吞掉，不产生未处理的
  ///    Future 异常（在测试环境里那会直接判失败）。
  void _persist(Future<void> Function(SharedPreferences p) write) {
    final p = _prefs;
    if (p == null) return;
    try {
      unawaited(write(p).catchError((Object _) {}));
    } catch (_) {}
  }

  /// 清掉旧格式的散键（新格式写入后调用，避免新旧两份存档并存）。
  static Future<void> _removeLegacyResumeKeys(SharedPreferences p) async {
    for (final key in p.getKeys().toList()) {
      if (key == _kResumeMode ||
          key == _kResumeLevel ||
          key == _kResumeHp ||
          key.startsWith(_kResumeUpgradesPrefix)) {
        await p.remove(key);
      }
    }
  }

  void setSound(bool value) {
    if (_sound == value) return;
    _sound = value;
    _persist((p) => p.setBool(_kSound, value));
    notifyListeners();
  }

  void setHaptics(bool value) {
    if (_haptics == value) return;
    _haptics = value;
    _persist((p) => p.setBool(_kHaptics, value));
    notifyListeners();
  }

  void setScreenShake(bool value) {
    if (_screenShake == value) return;
    _screenShake = value;
    _persist((p) => p.setBool(_kScreenShake, value));
    notifyListeners();
  }

  /// 通关一关：解锁下一关并记录最佳战绩。
  void recordClear({
    required int levelIndex,
    required int stars,
    required int turns,
    required int levelCount,
  }) {
    var changed = false;
    if (stars > (bestStars[levelIndex] ?? 0)) {
      bestStars[levelIndex] = stars;
      _persist((p) => p.setInt('$_kStarsPrefix$levelIndex', stars));
      changed = true;
    }
    final best = bestTurns[levelIndex];
    if (best == null || turns < best) {
      bestTurns[levelIndex] = turns;
      _persist((p) => p.setInt('$_kTurnsPrefix$levelIndex', turns));
      changed = true;
    }
    final next = levelIndex + 1;
    if (next < levelCount && next > _unlockedLevel) {
      _unlockedLevel = next;
      _persist((p) => p.setInt(_kUnlocked, next));
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// 记录无尽模式的最佳波次。
  void recordEndless(int wave) {
    if (wave <= _endlessBest) return;
    _endlessBest = wave;
    _persist((p) => p.setInt(_kEndlessBest, wave));
    notifyListeners();
  }

  /// 写下进行中的一局，供主菜单的「继续游戏」恢复。
  ///
  /// 写入 [data.mode] 对应的槽，另一边的进度原样保留。
  void saveResume(ResumeData data) {
    // 同一毫秒内连续写两个槽（测试/快速操作）会让「取较新」的平局判定
    // 不稳定：保证新写入的时间戳严格大于另一槽，后写的永远赢。
    var now = DateTime.now().millisecondsSinceEpoch;
    final opposite = resumeFor(
      data.mode == GameMode.endless ? GameMode.campaign : GameMode.endless,
    );
    if (opposite != null && now <= opposite.savedAt) {
      now = opposite.savedAt + 1;
    }
    final stamped = ResumeData(
      mode: data.mode,
      level: data.level,
      carryHp: data.carryHp,
      upgrades: data.upgrades,
      items: data.items,
      savedAt: now,
    );
    _setResume(data.mode, stamped);
    _persist((p) async {
      await p.setString(
        data.mode == GameMode.endless ? _kResumeEndless : _kResumeCampaign,
        jsonEncode({
          'mode': data.mode == GameMode.endless ? 'endless' : 'campaign',
          'level': data.level,
          'hp': data.carryHp,
          'upgrades': data.upgrades,
          'items': data.items,
          // 分槽后用时间戳决定「继续游戏」恢复哪一槽；旧档没有这个字段，
          // 读作 0（输给任何新写入）。
          'savedAt': now,
        }),
      );
      // 单槽时代的旧键：新格式落盘后删掉，避免复活已被覆盖的进度。
      await p.remove(_kResume);
      await _removeLegacyResumeKeys(p);
    });
    notifyListeners();
  }

  /// 清掉「继续游戏」存档（一局打完 / 从头开始时调用）。
  ///
  /// [mode] 为空时全清；指定模式则只清该模式的槽——战败或重开不该把
  /// 另一个模式挂起的对局一起抹掉。
  void clearResume({GameMode? mode}) {
    if (mode == null) {
      if (_resumeCampaign == null && _resumeEndless == null) return;
      _resumeCampaign = null;
      _resumeEndless = null;
      _persist((p) async {
        await p.remove(_kResume);
        await p.remove(_kResumeCampaign);
        await p.remove(_kResumeEndless);
        await _removeLegacyResumeKeys(p);
      });
      notifyListeners();
      return;
    }
    if (resumeFor(mode) == null) return;
    _setResume(mode, null);
    _persist((p) async {
      await p.remove(
        mode == GameMode.endless ? _kResumeEndless : _kResumeCampaign,
      );
    });
    notifyListeners();
  }

  /// 清空进度（保留设置）。
  void resetProgress() {
    bestStars.clear();
    bestTurns.clear();
    _unlockedLevel = 0;
    _endlessBest = 0;
    _resumeCampaign = null;
    _resumeEndless = null;
    _persist((p) async {
      for (final key in p.getKeys().toList()) {
        if (key.startsWith(_kStarsPrefix) ||
            key.startsWith(_kTurnsPrefix) ||
            key == _kEndlessBest) {
          await p.remove(key);
        }
      }
      await p.remove(_kResume);
      await p.remove(_kResumeCampaign);
      await p.remove(_kResumeEndless);
      await _removeLegacyResumeKeys(p);
      await p.setInt(_kUnlocked, 0);
    });
    notifyListeners();
  }
}

/// 游戏模式。
enum GameMode { campaign, endless }

/// 「继续游戏」的存档：恢复一局进行中的战斗所需的全部状态。
class ResumeData {
  final GameMode mode;

  /// 战役关卡索引（0 起）或无尽波次 - 1。
  final int level;

  /// 跨关卡继承的生命。
  final int carryHp;

  /// 本局已拿的强化（id → 层数）。
  final Map<String, int> upgrades;

  /// 本局剩余的道具（道具 id → 数量）。旧存档缺这一项时按空处理，
  /// 开局会按默认数量补足。
  final Map<String, int> items;

  /// 写入时刻（epoch 毫秒）。分槽后「继续游戏」取两个槽里较新的那个；
  /// 旧档没有这个字段，读作 0（输给任何新写入）。
  final int savedAt;

  const ResumeData({
    required this.mode,
    required this.level,
    required this.carryHp,
    required this.upgrades,
    this.items = const {},
    this.savedAt = 0,
  });
}
