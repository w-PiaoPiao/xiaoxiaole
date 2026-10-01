import 'dart:math';

import 'gem.dart';
import 'roguelike.dart';

/// 一次匹配形成的组合（可能由多条横/竖连线在拐角处合并而成）。
class MatchGroup {
  /// 组内所有格子下标。
  final Set<int> indices;

  final GemType type;

  /// 是否包含横向连线。
  final bool hasH;

  /// 是否包含纵向连线。
  final bool hasV;

  /// 组内最长连线的长度。
  final int maxRun;

  /// 生成强化宝石的位置。
  final int anchor;

  /// 该组应当生成的强化宝石类型。
  final SpecialKind spawn;

  const MatchGroup({
    required this.indices,
    required this.type,
    required this.hasH,
    required this.hasV,
    required this.maxRun,
    required this.anchor,
    required this.spawn,
  });
}

/// 连锁中的一步：一次「消除 → 生成强化宝石 → 下落补充」的完整结果。
class CascadeStep {
  /// 连锁序号，从 1 开始，越大代表连锁越深。
  final int combo;

  /// 本步被清除的宝石。
  final List<ClearedGem> cleared;

  /// 各色宝石的清除数量，用于战斗结算。
  final Map<GemType, int> counts;

  /// 本步生成的强化宝石。
  final List<SpecialSpawn> spawns;

  /// 本步引爆的强化宝石。
  final List<SpecialActivation> activations;

  /// 本步结束后整个棋盘的快照。
  final List<GemSnapshot> snapshot;

  /// 新出现宝石的纵向起始位置（单位：格，可为负数表示从棋盘上方落入）。
  final Map<int, double> spawnStartY;

  /// 强化宝石引爆带来的额外伤害。
  final int specialBonus;

  /// 本步被破除的机关（相邻消除或爆炸波及）。
  final List<ObstacleBreak> obstacleBreaks;

  const CascadeStep({
    required this.combo,
    required this.cleared,
    required this.counts,
    required this.spawns,
    required this.activations,
    required this.snapshot,
    required this.spawnStartY,
    required this.specialBonus,
    this.obstacleBreaks = const [],
  });

  /// 清除的宝石总数。
  int get totalCleared => cleared.length;
}

class _Run {
  final bool horizontal;
  final int fixed;
  final int from;
  final int to;

  const _Run(this.horizontal, this.fixed, this.from, this.to);

  int get length => to - from + 1;
}

/// 消消乐棋盘。
///
/// 棋盘是一个 `cols x rows` 的网格，`y` 越大越靠下。所有会改变棋盘的公开方法
/// （[resolveSwap]、[resolveUltimate]）都会返回一串 [CascadeStep]，
/// 调用方按顺序播放即可得到动画所需的全部信息。
class BoardEngine {
  static const int cols = 8;
  static const int rows = 8;

  static const List<GemType> palette = GemType.values;

  /// 棋盘格子，行优先存储，`index = y * cols + x`。`null` 表示空洞。
  final List<Gem?> cells = List<Gem?>.filled(cols * rows, null);

  final Random _rng;

  /// 机关布置专用的独立随机源。
  ///
  /// 机关位置不能与宝石补位共用随机源：否则"这一关摆几件机关"会连带
  /// 改变整条宝石序列，平衡报告里改机关数量的前后对比就失去了可比性。
  final Random _obstacleRng;

  int _nextId = 1;

  BoardEngine({int? seed})
    : _rng = Random(seed),
      _obstacleRng = Random(seed == null ? null : seed ^ 0x0B57AC1E);

  /// 仅用于测试：用固定棋盘构造。
  ///
  /// 每个格子可以是一位字符（`R/B/G/Y/P`，`.` 表示空），也可以是两位字符
  /// （第二位是强化类型：`.` 无、`h` 横向、`v` 纵向、`b` 爆裂、`p` 棱镜）。
  /// 每行的长度决定使用哪种写法。
  factory BoardEngine.fromLayout(List<String> layout, {int? seed}) {
    final board = BoardEngine(seed: seed ?? 1);
    for (var y = 0; y < rows && y < layout.length; y++) {
      final line = layout[y];
      final step = line.length >= cols * 2 ? 2 : 1;
      for (var x = 0; x < cols; x++) {
        final a = line.length > x * step ? line[x * step] : '.';
        final b = step == 2 && line.length > x * step + 1
            ? line[x * step + 1]
            : '.';
        final type = _typeFromChar(a);
        if (type == null) continue;
        board.cells[board.index(x, y)] = Gem(
          id: board._nextId++,
          type: type,
          special: _specialFromChar(b),
        );
      }
    }
    return board;
  }

  static GemType? _typeFromChar(String c) {
    switch (c) {
      case 'R':
        return GemType.red;
      case 'B':
        return GemType.blue;
      case 'G':
        return GemType.green;
      case 'Y':
        return GemType.yellow;
      case 'P':
        return GemType.purple;
      default:
        return null;
    }
  }

  static SpecialKind _specialFromChar(String c) {
    switch (c) {
      case 'h':
        return SpecialKind.lineH;
      case 'v':
        return SpecialKind.lineV;
      case 'b':
        return SpecialKind.burst;
      case 'p':
        return SpecialKind.prism;
      default:
        return SpecialKind.none;
    }
  }

  int index(int x, int y) => y * cols + x;

  int xOf(int index) => index % cols;

  int yOf(int index) => index ~/ cols;

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;

  Gem? at(int x, int y) => inBounds(x, y) ? cells[index(x, y)] : null;

  Gem? gemAt(int index) =>
      index >= 0 && index < cells.length ? cells[index] : null;

  /// 两格是否上下/左右相邻。
  bool adjacent(int a, int b) {
    final ax = xOf(a), ay = yOf(a), bx = xOf(b), by = yOf(b);
    return (ax - bx).abs() + (ay - by).abs() == 1;
  }

  /// 四邻格（上下左右，越界的跳过）。
  Iterable<int> neighborsOf(int i) sync* {
    final x = xOf(i), y = yOf(i);
    if (x > 0) yield i - 1;
    if (x < cols - 1) yield i + 1;
    if (y > 0) yield i - cols;
    if (y < rows - 1) yield i + cols;
  }

  // ---------------------------------------------------------------- 初始填充

  /// 重新生成一个可玩的初始棋盘：没有现成的三连，且至少存在一步可行操作。
  void reset() {
    for (var attempt = 0; attempt < 300; attempt++) {
      _fillFresh();
      if (findMatches().isEmpty && hasValidMove()) return;
    }
  }

  void _fillFresh() {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final banned = <GemType>{};
        final left1 = at(x - 1, y), left2 = at(x - 2, y);
        if (left1 != null && left2 != null && left1.type == left2.type) {
          banned.add(left1.type);
        }
        final up1 = at(x, y - 1), up2 = at(x, y - 2);
        if (up1 != null && up2 != null && up1.type == up2.type) {
          banned.add(up1.type);
        }
        final choices = palette.where((t) => !banned.contains(t)).toList();
        cells[index(x, y)] = Gem(
          id: _nextId++,
          type: choices[_rng.nextInt(choices.length)],
        );
      }
    }
  }

  // ---------------------------------------------------------------- 查找匹配

  /// 找出当前棋盘上所有可消除的组合。
  List<MatchGroup> findMatches() {
    final runs = _collectRuns();
    if (runs.isEmpty) return const [];

    final parent = List<int>.generate(cells.length, (i) => i);
    int find(int a) {
      var root = a;
      while (parent[root] != root) {
        parent[root] = parent[parent[root]];
        root = parent[root];
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    for (final run in runs) {
      final first = _runIndex(run, 0);
      for (var k = 1; k < run.length; k++) {
        union(first, _runIndex(run, k));
      }
    }

    final byRoot = <int, List<_Run>>{};
    for (final run in runs) {
      byRoot.putIfAbsent(find(_runIndex(run, 0)), () => <_Run>[]).add(run);
    }

    final groups = <MatchGroup>[];
    byRoot.forEach((_, groupRuns) {
      final indices = <int>{};
      for (final run in groupRuns) {
        for (var k = 0; k < run.length; k++) {
          indices.add(_runIndex(run, k));
        }
      }
      final hasH = groupRuns.any((r) => r.horizontal);
      final hasV = groupRuns.any((r) => !r.horizontal);
      final maxRun = groupRuns.map((r) => r.length).reduce(max);
      final type = cells[indices.first]!.type;

      final SpecialKind spawn;
      if (hasH && hasV) {
        spawn = SpecialKind.burst;
      } else if (maxRun >= 5) {
        spawn = SpecialKind.prism;
      } else if (maxRun == 4) {
        final four = groupRuns.firstWhere((r) => r.length == 4);
        spawn = four.horizontal ? SpecialKind.lineH : SpecialKind.lineV;
      } else {
        spawn = SpecialKind.none;
      }

      groups.add(
        MatchGroup(
          indices: indices,
          type: type,
          hasH: hasH,
          hasV: hasV,
          maxRun: maxRun,
          anchor: _pickAnchor(groupRuns, indices, hasH, hasV),
          spawn: spawn,
        ),
      );
    });

    return groups;
  }

  List<_Run> _collectRuns() {
    final runs = <_Run>[];
    for (var y = 0; y < rows; y++) {
      var x = 0;
      while (x < cols) {
        final gem = cells[index(x, y)];
        // 被机关附着的宝石不参与匹配，也不能被跨越。
        if (gem == null || gem.locked) {
          x++;
          continue;
        }
        var end = x;
        while (end + 1 < cols) {
          final next = cells[index(end + 1, y)];
          if (next == null || next.locked || next.type != gem.type) break;
          end++;
        }
        if (end - x + 1 >= 3) runs.add(_Run(true, y, x, end));
        x = end + 1;
      }
    }
    for (var x = 0; x < cols; x++) {
      var y = 0;
      while (y < rows) {
        final gem = cells[index(x, y)];
        if (gem == null || gem.locked) {
          y++;
          continue;
        }
        var end = y;
        while (end + 1 < rows) {
          final next = cells[index(x, end + 1)];
          if (next == null || next.locked || next.type != gem.type) break;
          end++;
        }
        if (end - y + 1 >= 3) runs.add(_Run(false, x, y, end));
        y = end + 1;
      }
    }
    return runs;
  }

  int _runIndex(_Run run, int offset) {
    final pos = run.from + offset;
    return run.horizontal ? index(pos, run.fixed) : index(run.fixed, pos);
  }

  int _pickAnchor(List<_Run> runs, Set<int> indices, bool hasH, bool hasV) {
    if (hasH && hasV) {
      final hCells = <int>{};
      final vCells = <int>{};
      for (final run in runs) {
        for (var k = 0; k < run.length; k++) {
          (run.horizontal ? hCells : vCells).add(_runIndex(run, k));
        }
      }
      final cross = hCells.intersection(vCells);
      if (cross.isNotEmpty) return cross.first;
    }
    final longest = runs.reduce((a, b) => a.length >= b.length ? a : b);
    return _runIndex(longest, longest.length ~/ 2);
  }

  // ---------------------------------------------------------------- 交换

  /// 判断两格能否交换：必须相邻，且交换后能形成消除（强化宝石有两条例外）。
  ///
  /// 强化宝石不再"一换就炸"：和普通宝石一样，**换出一个消除才会生效**。
  /// 只有两种情况与匹配无关——棱镜没有颜色、参与不了匹配，与任意相邻宝石
  /// 交换都是它的用法（清除对方那一种颜色）；两颗强化宝石换到一起是组合技。
  ///
  /// 被机关附着的宝石不能交换——要先用相邻消除（或锤子）把机关破掉。
  bool canSwap(int a, int b) {
    if (!adjacent(a, b)) return false;
    final ga = cells[a], gb = cells[b];
    if (ga == null || gb == null) return false;
    if (ga.locked || gb.locked) return false;
    // 棱镜是唯一"总能换"的单颗强化宝石。
    if (ga.special == SpecialKind.prism || gb.special == SpecialKind.prism) {
      return true;
    }
    // 两颗强化宝石换到一起 = 组合技，不需要匹配。
    if (ga.isSpecial && gb.isSpecial) return true;
    if (ga.type == gb.type) return false;
    return _swapCreatesMatch(a, b);
  }

  bool _swapCreatesMatch(int a, int b) {
    final ga = cells[a], gb = cells[b];
    cells[a] = gb;
    cells[b] = ga;
    final ok = _hasAnyRun();
    cells[a] = ga;
    cells[b] = gb;
    return ok;
  }

  /// 交换两格中的宝石（不校验合法性）。
  void swapCells(int a, int b) {
    final tmp = cells[a];
    cells[a] = cells[b];
    cells[b] = tmp;
  }

  bool _hasAnyRun() {
    for (var y = 0; y < rows; y++) {
      var run = 1;
      for (var x = 1; x < cols; x++) {
        final prev = cells[index(x - 1, y)], cur = cells[index(x, y)];
        if (cur != null &&
            prev != null &&
            !cur.locked &&
            !prev.locked &&
            cur.type == prev.type) {
          run++;
          if (run >= 3) return true;
        } else {
          run = 1;
        }
      }
    }
    for (var x = 0; x < cols; x++) {
      var run = 1;
      for (var y = 1; y < rows; y++) {
        final prev = cells[index(x, y - 1)], cur = cells[index(x, y)];
        if (cur != null &&
            prev != null &&
            !cur.locked &&
            !prev.locked &&
            cur.type == prev.type) {
          run++;
          if (run >= 3) return true;
        } else {
          run = 1;
        }
      }
    }
    return false;
  }

  /// 是否还存在可行的操作。
  bool hasValidMove() {
    for (var i = 0; i < cells.length; i++) {
      final gem = cells[i];
      if (gem == null || gem.locked) continue;
      if (gem.isSpecial) return true;
      final x = xOf(i), y = yOf(i);
      if (x + 1 < cols && canSwap(i, i + 1)) return true;
      if (y + 1 < rows && canSwap(i, i + cols)) return true;
    }
    return false;
  }

  /// 打乱棋盘直到既没有现成消除、又存在可行操作。
  ///
  /// 被机关附着的宝石原样保留（机关是关卡的布置，不该被洗牌冲掉）——
  /// 失败时会保留机关重排颜色，而不是整盘重建。
  void shuffleBoard() {
    for (var attempt = 0; attempt < 120; attempt++) {
      final gems = <Gem>[for (final g in cells) ?g];
      final movable = [
        for (final g in gems)
          if (!g.isSpecial && !g.locked) g,
      ];
      final types = [for (final g in movable) g.type]..shuffle(_rng);
      for (var i = 0; i < movable.length; i++) {
        movable[i].type = types[i];
      }
      if (findMatches().isEmpty && hasValidMove()) return;
    }
    // 兜底：整盘重铺，并把机关按原位重新附着（机关是关卡的布置，不能丢）。
    final kept = <int, ObstacleKind>{
      for (var i = 0; i < cells.length; i++) i: ?cells[i]?.obstacle,
    };
    reset();
    for (final entry in kept.entries) {
      cells[entry.key]?.obstacle = entry.value;
    }
  }

  // ---------------------------------------------------------------- 机关

  /// 指定格上的机关（没有则为 null）。
  ObstacleKind? obstacleAt(int index) => cells[index]?.obstacle;

  /// 场上某种机关的数量。
  int countObstacles(ObstacleKind kind) {
    var count = 0;
    for (final gem in cells) {
      if (gem?.obstacle == kind) count++;
    }
    return count;
  }

  /// 开局布置机关：随机挑选普通宝石附着。返回实际布置的数量。
  ///
  /// 用机关专属的随机源（见 [_obstacleRng]），所以同一个种子永远得到同一套
  /// 机关位置，且**不扰动宝石序列**——平衡报告与测试都能复现、能对比。
  int placeObstacles(ObstacleKind kind, int count) {
    var placed = 0;
    for (var guard = 0; placed < count && guard < 600; guard++) {
      final i = _obstacleRng.nextInt(cells.length);
      final gem = cells[i];
      if (gem == null || gem.locked || gem.isSpecial) continue;
      gem.obstacle = kind;
      placed++;
    }
    return placed;
  }

  // ---------------------------------------------------------------- 结算

  /// 交换后结算整个连锁。调用前需要先执行 [swapCells]。
  ///
  /// [a]、[b] 是本次交换的两格，用于决定强化宝石的生成位置。
  /// [rules] 是玩家 build 对棋盘规则的改写（「棱镜宗师」「爆破工程」
  /// 「十字破空」）。默认值等于现行规则，因此不传的地方行为完全不变。
  List<CascadeStep> resolveSwap(
    int a,
    int b, {
    BoardRules rules = BoardRules.none,
  }) {
    final steps = <CascadeStep>[];

    // 两颗强化宝石换到一起触发**组合技**，效果远大于各炸各的；棱镜与任意
    // 宝石交换都会立即引爆（它没有颜色，匹配链遇不到它）。
    //
    // 其余的强化宝石不在这里处理：它们和普通宝石一样，必须先换出一个消除，
    // 才会在下面的匹配链里被引爆（[_buildStep] 会引爆清除范围内的强化宝石）。
    final merged = _swapCombo(a, b, rules);
    final triggers = <SpecialActivation>[];
    final seed = <int>{};
    if (merged != null) {
      seed.addAll([a, b]);
      triggers.add(merged);
    } else {
      for (final i in [a, b]) {
        final gem = cells[i];
        if (gem == null || gem.special != SpecialKind.prism) continue;
        final partner = i == a ? b : a;
        seed.add(i);
        triggers.add(
          SpecialActivation(
            index: i,
            kind: gem.special,
            type: gem.type,
            area: _activationArea(
              i,
              gem.special,
              gem.type,
              prismType: cells[partner]?.type ?? gem.type,
              rules: rules,
            ),
            bonus: _bonusFor(gem.special),
          ),
        );
      }
    }

    var combo = 1;
    if (triggers.isNotEmpty) {
      steps.add(
        _buildStep(
          combo: combo,
          seedClear: seed,
          seedActivations: triggers,
          spawns: const [],
          // 组合技已经把两颗宝石的意义一起算进范围了，**两颗都要抑制**：
          // 它们都已经"用掉"了，谁也不能再按单颗效果炸一遍，否则就又变回
          // "各炸各的"。（只抑制其中一颗时，另一颗会额外炸出自己的范围。）
          suppress: merged != null ? {a, b} : const {},
          rules: rules,
        ),
      );
      combo++;
    }

    _resolveMatchChain(steps, combo, preferred: {a, b}, rules: rules);
    return steps;
  }

  /// 锤子：直接清除指定的一格（不走匹配判定），随后照常结算连锁。
  ///
  /// 这正是"玩家主动引爆"：目标格若是强化宝石会被引爆，若附着机关则连机关
  /// 一起砸碎（冰壳、藤蔓、祭坛与宝石同时消失）；清完之后继续结算正常的连锁，
  /// 所以落点选得好依然能带出一串连击。
  List<CascadeStep> resolveSingleClear(
    int index, {
    BoardRules rules = BoardRules.none,
  }) {
    if (index < 0 || index >= cells.length || cells[index] == null) {
      return const [];
    }
    final steps = <CascadeStep>[
      _buildStep(
        combo: 1,
        seedClear: {index},
        seedActivations: const [],
        spawns: const [],
        rules: rules,
      ),
    ];
    _resolveMatchChain(steps, 2, rules: rules);
    return steps;
  }

  /// 反复结算「匹配 → 生成强化宝石 → 下落补充」，直到棋盘安静下来。
  ///
  /// [preferred] 只在第一轮生效：交换/落点优先的地方把强化宝石生成在玩家
  /// 刚操作过的位置，之后的连锁不再有这个偏好。
  void _resolveMatchChain(
    List<CascadeStep> steps,
    int startCombo, {
    Set<int> preferred = const {},
    BoardRules rules = BoardRules.none,
  }) {
    var combo = startCombo;
    var anchors = preferred;
    while (true) {
      final groups = findMatches();
      if (groups.isEmpty) break;
      final spawns = <SpecialSpawn>[
        for (final g in groups)
          if (g.spawn != SpecialKind.none)
            SpecialSpawn(index: g.anchor, kind: g.spawn, type: g.type),
      ];
      final seedClear = <int>{};
      for (final g in groups) {
        seedClear.addAll(g.indices);
      }
      steps.add(
        _buildStep(
          combo: combo,
          seedClear: seedClear,
          seedActivations: const [],
          spawns: spawns,
          preferredAnchors: _preferredAnchors(groups, anchors),
          rules: rules,
        ),
      );
      combo++;
      anchors = const {};
    }
  }

  // ------------------------------------------------------------ 强化宝石组合技

  /// 两颗强化宝石换到一起时的合并效果。返回 null 表示不构成组合。
  ///
  /// 这是消消乐最"炸"的一刻：单颗引爆只清一条线，两颗叠在一起能清掉大半个
  /// 棋盘。规则刻意做得符合直觉——
  ///
  /// | 组合 | 效果 |
  /// | --- | --- |
  /// | 破空 + 破空 | 十字（整行 + 整列） |
  /// | 破空 + 爆裂 | 三行 + 三列的粗十字 |
  /// | 爆裂 + 爆裂 | 5x5 |
  /// | 棱镜 + 破空 | 全场同色，并清掉它们所在的每一行与每一列 |
  /// | 棱镜 + 爆裂 | 全场同色 + 5x5 |
  /// | 棱镜 + 棱镜 | 清空整个棋盘 |
  SpecialActivation? _swapCombo(int a, int b, BoardRules rules) {
    final ga = cells[a], gb = cells[b];
    if (ga == null || gb == null) return null;
    if (!ga.isSpecial || !gb.isSpecial) return null;

    final isPrism =
        ga.special == SpecialKind.prism && gb.special == SpecialKind.prism;
    if (isPrism) {
      return SpecialActivation(
        index: a,
        kind: SpecialKind.prism,
        type: ga.type,
        area: [for (var i = 0; i < cells.length; i++) i],
        bonus: 600,
        comboName: '万象归一',
      );
    }

    final prismGem = ga.special == SpecialKind.prism
        ? ga
        : (gb.special == SpecialKind.prism ? gb : null);
    if (prismGem != null) {
      final other = identical(prismGem, ga) ? gb : ga;
      final prismIndex = identical(prismGem, ga) ? a : b;
      final sameColor = _colorArea(prismGem.type);
      final List<int> extra;
      final String name;
      final int bonus;
      if (other.special == SpecialKind.lineH ||
          other.special == SpecialKind.lineV) {
        // 经典「同色风暴」：全场同色，加上它们铺开的每一行与每一列。
        extra = _linesThrough(sameColor);
        name = '同色风暴';
        bonus = 400;
      } else {
        // 含爆裂的组合技跟着「爆破工程」一起放大：半径 1+rules.burstRadius，
        // 默认（rules 为空）就是原来的 5x5。
        extra = _boxArea(prismIndex, 1 + rules.burstRadius);
        name = '棱镜爆裂';
        bonus = 320;
      }
      return SpecialActivation(
        index: prismIndex,
        kind: SpecialKind.prism,
        type: prismGem.type,
        area: {...sameColor, ...extra}.toList(),
        bonus: bonus,
        comboName: name,
      );
    }

    final aLine =
        ga.special == SpecialKind.lineH || ga.special == SpecialKind.lineV;
    final bLine =
        gb.special == SpecialKind.lineH || gb.special == SpecialKind.lineV;
    if (aLine && bLine) {
      return SpecialActivation(
        index: a,
        kind: ga.special,
        type: ga.type,
        area: _crossArea(a),
        bonus: 120,
        comboName: '十字破空',
      );
    }
    if (aLine != bLine) {
      return SpecialActivation(
        index: a,
        kind: ga.special,
        type: ga.type,
        area: _thickCrossArea(a),
        bonus: 200,
        comboName: '破空爆裂',
      );
    }
    return SpecialActivation(
      index: a,
      kind: SpecialKind.burst,
      type: ga.type,
      area: _boxArea(a, 1 + rules.burstRadius),
      bonus: 240,
      comboName: '连环爆裂',
    );
  }

  List<int> _colorArea(GemType type) => [
    for (var i = 0; i < cells.length; i++)
      if (cells[i]?.type == type) i,
  ];

  List<int> _crossArea(int index) => {
    for (var x = 0; x < cols; x++) this.index(x, yOf(index)),
    for (var y = 0; y < rows; y++) this.index(xOf(index), y),
  }.toList();

  /// 以 [index] 为中心的三行三列（去掉超出边界的部分）。
  List<int> _thickCrossArea(int index) {
    final cx = xOf(index), cy = yOf(index);
    return {
      for (var dy = -1; dy <= 1; dy++)
        if (cy + dy >= 0 && cy + dy < rows)
          for (var x = 0; x < cols; x++) this.index(x, cy + dy),
      for (var dx = -1; dx <= 1; dx++)
        if (cx + dx >= 0 && cx + dx < cols)
          for (var y = 0; y < rows; y++) this.index(cx + dx, y),
    }.toList();
  }

  /// 以 [index] 为中心、边长 `2*radius+1` 的方形区域。
  List<int> _boxArea(int index, int radius) {
    final cx = xOf(index), cy = yOf(index);
    return [
      for (var dy = -radius; dy <= radius; dy++)
        for (var dx = -radius; dx <= radius; dx++)
          if (inBounds(cx + dx, cy + dy)) this.index(cx + dx, cy + dy),
    ];
  }

  /// 覆盖 [indices] 中每一个格子所在的整行与整列。
  List<int> _linesThrough(Iterable<int> indices) {
    final rows = <int>{};
    final cols = <int>{};
    for (final i in indices) {
      rows.add(yOf(i));
      cols.add(xOf(i));
    }
    return [
      for (var y = 0; y < BoardEngine.rows; y++)
        for (var x = 0; x < BoardEngine.cols; x++)
          if (rows.contains(y) || cols.contains(x)) index(x, y),
    ];
  }

  /// 在每组里挑出更贴近玩家落点的位置放置强化宝石。
  ///
  /// 组内可能同时包含交换的两格（拐角消除时），取离默认生成点最近的那一个：
  /// 强化宝石落在玩家手指刚经过的地方，比随便取一个更符合"这是我造出来的"。
  Map<int, int> _preferredAnchors(List<MatchGroup> groups, Set<int> preferred) {
    final result = <int, int>{};
    if (preferred.isEmpty) return result;
    for (final g in groups) {
      final hit = preferred.where(g.indices.contains);
      if (hit.isEmpty) continue;
      final anchorX = xOf(g.anchor), anchorY = yOf(g.anchor);
      var best = hit.first;
      var bestDistance = 1 << 30;
      for (final candidate in hit) {
        final distance =
            (xOf(candidate) - anchorX).abs() + (yOf(candidate) - anchorY).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = candidate;
        }
      }
      result[g.anchor] = best;
    }
    return result;
  }

  /// 必杀技：以 [centerIndex] 为中心清除整行与整列，随后照常结算连锁。
  ///
  /// [rules] 与 [resolveSwap] 的同名参数一致：连锁里被波及的强化宝石按
  /// 玩家的棋盘规则引爆（「爆破工程」的必杀同样是 5x5）。
  List<CascadeStep> resolveUltimate(
    int centerIndex, {
    BoardRules rules = BoardRules.none,
  }) {
    final steps = <CascadeStep>[];
    final cx = xOf(centerIndex), cy = yOf(centerIndex);
    final seed = <int>{
      for (var x = 0; x < cols; x++) index(x, cy),
      for (var y = 0; y < rows; y++) index(cx, y),
    };
    steps.add(
      _buildStep(
        combo: 1,
        seedClear: seed,
        seedActivations: const [],
        spawns: const [],
        rules: rules,
      ),
    );

    _resolveMatchChain(steps, 2, rules: rules);
    return steps;
  }

  CascadeStep _buildStep({
    required int combo,
    required Set<int> seedClear,
    required List<SpecialActivation> seedActivations,
    required List<SpecialSpawn> spawns,
    Map<int, int> preferredAnchors = const {},
    Set<int> suppress = const {},
    BoardRules rules = BoardRules.none,
  }) {
    final toClear = <int>{...seedClear};
    // 交换直接触发的强化宝石：其影响范围要一并纳入清除。
    for (final activation in seedActivations) {
      toClear.addAll(activation.area);
    }
    final activations = <SpecialActivation>[...seedActivations];
    final activated = <int>{
      for (final a in seedActivations) a.index,
      ...suppress,
    };
    final queued = <int>{...activated};
    final queue = <int>[];

    for (final i in toClear) {
      final gem = cells[i];
      if (gem != null && gem.isSpecial && !activated.contains(i)) {
        queue.add(i);
        queued.add(i);
      }
    }

    // 引爆链：强化宝石被清除时会波及周围，可能继续引爆别的强化宝石。
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      if (!activated.add(i)) continue;
      final gem = cells[i];
      if (gem == null) continue;
      final area = _activationArea(i, gem.special, gem.type, rules: rules);
      activations.add(
        SpecialActivation(
          index: i,
          kind: gem.special,
          type: gem.type,
          area: area,
          bonus: _bonusFor(gem.special),
        ),
      );
      for (final j in area) {
        if (j == i) continue;
        toClear.add(j);
        final other = cells[j];
        if (other != null &&
            other.isSpecial &&
            !activated.contains(j) &&
            !queued.contains(j)) {
          queue.add(j);
          queued.add(j);
        }
      }
    }

    // 玩家落点优先：把强化宝石生成在刚操作过的位置。
    final spawns2 = <SpecialSpawn>[];
    for (final s in spawns) {
      final better = preferredAnchors[s.index];
      if (better != null && toClear.contains(better)) {
        spawns2.add(SpecialSpawn(index: better, kind: s.kind, type: s.type));
      } else {
        spawns2.add(s);
      }
    }

    // 机关破除：本次清除范围内的任何一格，连同它的四邻，附着的机关都会
    // 被打碎（强化宝石的爆炸波及同理）。机关只是附着物——破掉之后宝石
    // 显形；如果那一格本身不在清除范围内，宝石会完好地留在棋盘上，
    // 成为玩家可以立刻使用的资源。
    final breaks = <ObstacleBreak>[];
    final touched = <int>{};
    for (final i in toClear) {
      touched.add(i);
      touched.addAll(neighborsOf(i));
    }
    for (final j in touched) {
      final gem = cells[j];
      final kind = gem?.obstacle;
      if (kind == null) continue;
      gem!.obstacle = null;
      breaks.add(ObstacleBreak(index: j, kind: kind));
    }

    final cleared = <ClearedGem>[];
    final counts = <GemType, int>{};
    for (final i in toClear) {
      final gem = cells[i];
      if (gem == null) continue;
      cleared.add(
        ClearedGem(
          index: i,
          gemId: gem.id,
          type: gem.type,
          special: gem.special,
        ),
      );
      counts[gem.type] = (counts[gem.type] ?? 0) + 1;
      cells[i] = null;
    }

    final spawnStartY = <int, double>{};
    for (final s in spawns2) {
      final gem = Gem(id: _nextId++, type: s.type, special: s.kind);
      cells[s.index] = gem;
      spawnStartY[gem.id] = yOf(s.index).toDouble();
    }

    _applyGravity(spawnStartY);

    return CascadeStep(
      combo: combo,
      cleared: cleared,
      counts: counts,
      spawns: spawns2,
      activations: activations,
      snapshot: snapshot(),
      spawnStartY: spawnStartY,
      specialBonus: activations.fold(0, (sum, a) => sum + a.bonus),
      obstacleBreaks: breaks,
    );
  }

  static int _bonusFor(SpecialKind kind) {
    switch (kind) {
      case SpecialKind.lineH:
      case SpecialKind.lineV:
        return 40;
      case SpecialKind.burst:
        return 80;
      case SpecialKind.prism:
        return 150;
      case SpecialKind.none:
        return 0;
    }
  }

  List<int> _activationArea(
    int index,
    SpecialKind kind,
    GemType type, {
    GemType? prismType,
    BoardRules rules = BoardRules.none,
  }) {
    final x = xOf(index), y = yOf(index);
    switch (kind) {
      case SpecialKind.lineH:
      case SpecialKind.lineV:
        final row = [for (var xx = 0; xx < cols; xx++) this.index(xx, y)];
        final column = [for (var yy = 0; yy < rows; yy++) this.index(x, yy)];
        // 默认路径与改造前逐字等价；只有拿到「十字破空」时才合并行列。
        if (!rules.lineBecomesCross) {
          return kind == SpecialKind.lineH ? row : column;
        }
        return {...row, ...column}.toList();
      case SpecialKind.burst:
        // 半径 1 就是 3x3；「爆破工程」把它抬到 2（5x5）。
        final r = rules.burstRadius;
        return [
          for (var dy = -r; dy <= r; dy++)
            for (var dx = -r; dx <= r; dx++)
              if (inBounds(x + dx, y + dy)) this.index(x + dx, y + dy),
        ];
      case SpecialKind.prism:
        final targets = <GemType>{prismType ?? type};
        // 「棱镜宗师」：再拖上棋盘上堆得最多的那几种颜色。
        for (var i = 0; i < rules.prismExtraColors; i++) {
          final extra = _mostCommonTypeExcluding(targets);
          if (extra == null) break;
          targets.add(extra);
        }
        return [
          for (var i = 0; i < cells.length; i++)
            if (targets.contains(cells[i]?.type)) i,
        ];
      case SpecialKind.none:
        return const [];
    }
  }

  /// 棋盘上数量最多、且不在 [excluded] 里的颜色；没有可选的就返回 null。
  ///
  /// 「棱镜宗师」用它挑要额外清除的颜色——总是清当前堆得最多的那种，
  /// 收益直观、可预期，不会让玩家觉得"这一下清得莫名其妙"。
  GemType? _mostCommonTypeExcluding(Set<GemType> excluded) {
    final counts = <GemType, int>{};
    for (final gem in cells) {
      final type = gem?.type;
      if (type == null || excluded.contains(type)) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }
    GemType? best;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// 消除后让上方宝石落下，并从顶部补足新宝石。
  void _applyGravity(Map<int, double> spawnStartY) {
    for (var x = 0; x < cols; x++) {
      var writeY = rows - 1;
      for (var y = rows - 1; y >= 0; y--) {
        final gem = cells[index(x, y)];
        if (gem == null) continue;
        if (writeY != y) {
          cells[index(x, writeY)] = gem;
          cells[index(x, y)] = null;
        }
        writeY--;
      }
      var above = 1;
      for (var y = writeY; y >= 0; y--) {
        final gem = Gem(
          id: _nextId++,
          type: palette[_rng.nextInt(palette.length)],
        );
        cells[index(x, y)] = gem;
        spawnStartY[gem.id] = -above.toDouble();
        above++;
      }
    }
  }

  /// 当前棋盘的快照。
  List<GemSnapshot> snapshot() {
    final out = <GemSnapshot>[];
    for (var i = 0; i < cells.length; i++) {
      final gem = cells[i];
      if (gem == null) continue;
      out.add(
        GemSnapshot(
          index: i,
          gemId: gem.id,
          type: gem.type,
          special: gem.special,
          obstacle: gem.obstacle,
        ),
      );
    }
    return out;
  }

  /// 当前棋盘上的空洞数量。正常情况下永远是 0。
  int countHoles() {
    var holes = 0;
    for (final gem in cells) {
      if (gem == null) holes++;
    }
    return holes;
  }

  /// 兜底修复：给所有空洞补上新宝石。
  ///
  /// 结算流程保证棋盘每步之后都是满的（有测试守着），这个方法只是最后一道
  /// 保险——真出现意外时，宁可补几颗普通宝石，也不能让棋盘留下空洞。
  int refillHoles({Map<int, double>? spawnStartY}) {
    var filled = 0;
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] != null) continue;
      final gem = Gem(
        id: _nextId++,
        type: palette[_rng.nextInt(palette.length)],
      );
      cells[i] = gem;
      spawnStartY?[gem.id] = (i ~/ cols).toDouble() - 2.0;
      filled++;
    }
    return filled;
  }

  /// 复制一份棋盘，用于「推演这步会怎样」而不影响真实棋盘。
  ///
  /// 机关必须一起复制：落子顾问就是在克隆盘上推演的，漏掉机关会让它以为
  /// 被冰封/毒藤锁住的格子还能参与匹配，从而推荐一步在真实棋盘上根本走不出
  /// 的"妙手"（带机关的关卡里提示会整片失真）。
  BoardEngine clone() {
    final copy = BoardEngine(seed: _rng.nextInt(1 << 30));
    for (var i = 0; i < cells.length; i++) {
      final gem = cells[i];
      if (gem != null) {
        copy.cells[i] = Gem(
          id: gem.id,
          type: gem.type,
          special: gem.special,
          obstacle: gem.obstacle,
        );
      }
    }
    copy._nextId = _nextId;
    return copy;
  }
}
