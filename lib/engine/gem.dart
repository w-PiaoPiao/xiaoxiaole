/// 宝石与棋盘的基础数据结构。这一层是纯 Dart，不依赖 Flutter，便于单元测试。
library;

/// 宝石颜色，每种颜色对应一种战斗效果。
enum GemType {
  /// 烈焰：对敌人造成伤害。
  red,

  /// 寒霜：为玩家积累护盾。
  blue,

  /// 生机：恢复玩家生命。
  green,

  /// 雷霆：积累怒气，用于释放必杀。
  yellow,

  /// 诅咒：使敌人陷入易伤状态。
  purple,
}

/// 强化宝石（由 4 连 / 5 连 / 拐角消除生成）。
enum SpecialKind {
  /// 普通宝石。
  none,

  /// 横向：清除整行。
  lineH,

  /// 纵向：清除整列。
  lineV,

  /// 爆裂：清除周围 3x3。
  burst,

  /// 棱镜：清除全场同色宝石。
  prism,
}

extension SpecialKindX on SpecialKind {
  bool get isSpecial => this != SpecialKind.none;
}

/// 棋盘上的一颗宝石。
///
/// [id] 在一局内保持稳定，动画层依靠它追踪宝石的位移与消散。
class Gem {
  final int id;

  GemType type;

  SpecialKind special;

  Gem({required this.id, required this.type, this.special = SpecialKind.none});

  bool get isSpecial => special.isSpecial;

  @override
  String toString() => 'Gem#$id(${type.name}${special.isSpecial ? '/${special.name}' : ''})';
}

/// 棋盘坐标，`x` 向右、`y` 向下，原点在左上角。
class Cell {
  final int x;
  final int y;

  const Cell(this.x, this.y);

  @override
  bool operator ==(Object other) => other is Cell && other.x == x && other.y == y;

  @override
  int get hashCode => x * 31 + y;

  @override
  String toString() => '($x,$y)';
}

/// 棋盘上某个格子的快照，供动画层还原画面。
class GemSnapshot {
  final int index;
  final int gemId;
  final GemType type;
  final SpecialKind special;

  const GemSnapshot({
    required this.index,
    required this.gemId,
    required this.type,
    required this.special,
  });
}

/// 本步被清除的一颗宝石。
class ClearedGem {
  final int index;
  final int gemId;
  final GemType type;
  final SpecialKind special;

  const ClearedGem({
    required this.index,
    required this.gemId,
    required this.type,
    required this.special,
  });
}

/// 本步新生成的强化宝石。
class SpecialSpawn {
  final int index;
  final SpecialKind kind;
  final GemType type;

  const SpecialSpawn({required this.index, required this.kind, required this.type});
}

/// 本步被引爆的强化宝石。
class SpecialActivation {
  final int index;
  final SpecialKind kind;
  final GemType type;

  /// 该强化宝石影响的格子范围。
  final List<int> area;

  /// 这次引爆带来的额外伤害。
  ///
  /// 普通引爆按种类取值；两颗强化宝石换到一起时会给出远高于「两个单独引爆
  /// 之和」的数字——玩家布好局的回报全在这里。
  final int bonus;

  /// 组合技的名字（普通引爆为 null）。UI 用它弹一条提示，
  /// 告诉玩家"刚才那一下是个大家伙"。
  final String? comboName;

  const SpecialActivation({
    required this.index,
    required this.kind,
    required this.type,
    required this.area,
    this.bonus = 0,
    this.comboName,
  });
}
