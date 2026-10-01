/// 局内道具：不消耗回合的有限次支援手段。
///
/// 三件道具对应三种"紧要关头"：
///   - 锤子：某格挡着路 / 有机关要拆，直接点掉它（强化宝石会引爆，
///     机关会连壳带石一起砸碎）；
///   - 洗牌：布局太差、没有好步子，重排颜色（机关原样保留）；
///   - 凝滞：下一击挡不住了，把敌人的出手往后推一回合。
///
/// 道具**不消耗回合**（用完不推进敌人倒计时）——这是它们的价值所在；
/// 数量有限来平衡：每关 / 每波开局补足到各 [itemSupplyPerLevel] 个，
/// 用掉不累积、也不会清零。
library;

enum ItemKind {
  /// 锤子：点掉任意一格。
  hammer,

  /// 洗牌：重新排列棋盘。
  shuffle,

  /// 凝滞：敌方出手推迟一回合。
  stall,
}

extension ItemKindX on ItemKind {
  /// 存档与 UI 共用的标识。
  String get id => name;

  String get label => switch (this) {
    ItemKind.hammer => '锤子',
    ItemKind.shuffle => '洗牌',
    ItemKind.stall => '凝滞',
  };

  /// 卡片 / tooltip 上的一行说明。
  String get description => switch (this) {
    ItemKind.hammer => '点掉任意一格（机关连壳砸碎）',
    ItemKind.shuffle => '重新排列棋盘（机关保留）',
    ItemKind.stall => '敌方出手推迟 1 回合',
  };
}

/// 每次开局把道具补足到这个数量。用掉不累积、也不会清零。
const int itemSupplyPerLevel = 1;

/// 把一份库存补足到每样 [itemSupplyPerLevel] 个。
///
/// 只补不削：如果存档里带着更多（例如以后的强化牌发的），保持原样。
Map<String, int> refillItems(Map<String, int> current) {
  final out = <String, int>{};
  for (final kind in ItemKind.values) {
    final held = current[kind.id] ?? 0;
    out[kind.id] = held < itemSupplyPerLevel ? itemSupplyPerLevel : held;
  }
  return out;
}
