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

/// 棋盘机关：附着在宝石上的障碍物。
///
/// 机关**跟着宝石走**（宝石下落时机关一起下落），而不是占住格子——
/// 这样棋盘永远没有空洞，重力、快照与视觉同步都不需要为机关开特例。
/// 被机关附着的宝石不能交换、不参与匹配，直到机关被相邻的消除破除。
enum ObstacleKind {
  /// 冰封：锁住宝石，相邻消除一次即破冰。纯棋盘压力。
  frost,

  /// 毒藤：锁住宝石，且每株让敌人攻击 +5%（见 BattleState.vineAttackBonus）。
  vine,

  /// 祭坛：锁住宝石，破除时立即为玩家蓄积怒气。
  altar,
}

extension ObstacleKindX on ObstacleKind {
  /// 给玩家看的一行说明。
  String get label => switch (this) {
    ObstacleKind.frost => '冰封',
    ObstacleKind.vine => '毒藤',
    ObstacleKind.altar => '祭坛',
  };
}

/// 棋盘上的一颗宝石。
///
/// [id] 在一局内保持稳定，动画层依靠它追踪宝石的位移与消散。
class Gem {
  final int id;

  GemType type;

  SpecialKind special;

  /// 附着在这颗宝石上的机关；null 表示普通宝石。
  ObstacleKind? obstacle;

  Gem({
    required this.id,
    required this.type,
    this.special = SpecialKind.none,
    this.obstacle,
  });

  bool get isSpecial => special.isSpecial;

  bool get locked => obstacle != null;

  @override
  String toString() =>
      'Gem#$id(${type.name}${special.isSpecial ? '/${special.name}' : ''}'
      '${obstacle != null ? '@${obstacle!.name}' : ''})';
}

/// 本步被破除的一个机关。
class ObstacleBreak {
  final int index;
  final ObstacleKind kind;

  const ObstacleBreak({required this.index, required this.kind});
}

/// 棋盘坐标，`x` 向右、`y` 向下，原点在左上角。
class Cell {
  final int x;
  final int y;

  const Cell(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.x == x && other.y == y;

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

  /// 附着在该宝石上的机关（视觉层据此绘制冰壳 / 藤蔓 / 祭坛）。
  final ObstacleKind? obstacle;

  const GemSnapshot({
    required this.index,
    required this.gemId,
    required this.type,
    required this.special,
    this.obstacle,
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

  const SpecialSpawn({
    required this.index,
    required this.kind,
    required this.type,
  });
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
