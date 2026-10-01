/// 无尽模式的肉鸽（roguelike）机制：稀有度分层、棋盘规则修正与质变效果。
///
/// 这一层刻意与 [PlayerProfile] 的成长字段分开：成长是"数字变大"，肉鸽是
/// "规则变了"。混在一起会让「强化不会让玩家变得比出厂更弱」这条契约失去
/// 意义，而代价类强化（每回合自损、无法获得护盾）也需要一个**新增的负面
/// 机制**作为落点，而不是把玩家已经拿到的属性往回扣。
library;

/// 强化的稀有度。
///
/// 只影响出现概率与卡片外观，不改变效果本身——效果强弱由条目自己的数值
/// 决定，稀有度只是"这条牌有多难得"。
enum UpgradeRarity {
  /// 普通：线性成长，随时可能出现。
  common,

  /// 稀有：改变规则或把两种宝石接起来，有前置门槛。
  rare,

  /// 传说：整局的玩法都会围着它转。
  legendary,
}

/// 棋盘层规则的修正。
///
/// 棋盘引擎本身不认识玩家的 build——它只做消除演算，规则是硬编码的。
/// 这些开关是唯一的注入通道：**默认值等于现行规则**，所以不传规则的地方
/// 行为完全不变，既有的二十来处调用点一个都不用改。
class BoardRules {
  /// 棱镜额外清除的同色数量（0 = 只清一种，即现行规则）。
  final int prismExtraColors;

  /// 爆裂宝石的半径（1 = 3x3，2 = 5x5）。
  final int burstRadius;

  /// 破空宝石是否同时清除整行与整列。
  final bool lineBecomesCross;

  const BoardRules({
    this.prismExtraColors = 0,
    this.burstRadius = 1,
    this.lineBecomesCross = false,
  });

  static const BoardRules none = BoardRules();

  bool get isDefault =>
      prismExtraColors == 0 && burstRadius == 1 && !lineBecomesCross;

  BoardRules copyWith({
    int? prismExtraColors,
    int? burstRadius,
    bool? lineBecomesCross,
  }) {
    return BoardRules(
      prismExtraColors: prismExtraColors ?? this.prismExtraColors,
      burstRadius: burstRadius ?? this.burstRadius,
      lineBecomesCross: lineBecomesCross ?? this.lineBecomesCross,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BoardRules &&
      other.prismExtraColors == prismExtraColors &&
      other.burstRadius == burstRadius &&
      other.lineBecomesCross == lineBecomesCross;

  @override
  int get hashCode => Object.hash(prismExtraColors, burstRadius, lineBecomesCross);
}

/// 战斗层的肉鸽质变与代价。
///
/// 全部字段都是"开关或系数"，默认值等于没有这回事——[none] 必须与出厂档案
/// 完全等价。值相等（`==`）是硬要求：`Upgrade.apply` 的测试会拿它判断
/// "这条强化到底改没改档案"。
class RoguelikeEffects {
  /// 全局伤害倍率（「血契」用它把"全部伤害 +50%"一次说清，而不是逐个
  /// 乘法去改红宝石 / 强化宝石 / 必杀的公式）。
  final double damageMul;

  /// 连锁基础倍率的加成（「永动连锁」让连锁从一开始就更值钱）。
  final double comboBaseBonus;

  /// 暴击伤害转为护盾的比例（「过量暴击」）。
  final double critToShield;

  /// 治疗溢出上限的部分转为护盾的比例（「溢流护盾」）。
  final double healOverflowToShield;

  /// 护盾吸收的伤害反弹给敌人的比例（「荆棘壁垒」）。
  final double shieldReflect;

  /// 怒气满后每点溢出怒气造成的伤害（「过载引擎」）。
  final double rageOverflowDamage;

  /// 每层易伤对强化宝石伤害的加成（「瘟疫」）。
  final double curseToSpecialPower;

  /// 易伤是否永续：每回合只衰减 1 层，而不是直接清零（「瘟疫」）。
  final bool cursePersists;

  /// 斩杀线：敌人生命低于该比例时触发 [executeBonus]（「处决者」）。
  final double executeThreshold;

  /// 斩杀阶段的伤害加成。
  final double executeBonus;

  /// 每回合自损的生命（「血契」）。可以致死——这是它的代价。
  final int selfDamagePerTurn;

  /// 护盾获取的倍率（0 = 完全无法获得护盾，「苦修」）。
  final double shieldGainMul;

  /// 每回合自动获得的怒气（「月华」）。
  final int ragePerTurn;

  /// 必杀消耗的倍率（0.6 = 少花 40% 怒气，「月华」）。
  final double ultimateCostMul;

  /// 棋盘层规则（棱镜多清一色、5x5 爆裂、破空成十字）。
  final BoardRules boardRules;

  const RoguelikeEffects({
    this.damageMul = 1,
    this.comboBaseBonus = 0,
    this.critToShield = 0,
    this.healOverflowToShield = 0,
    this.shieldReflect = 0,
    this.rageOverflowDamage = 0,
    this.curseToSpecialPower = 0,
    this.cursePersists = false,
    this.executeThreshold = 0,
    this.executeBonus = 0,
    this.selfDamagePerTurn = 0,
    this.shieldGainMul = 1,
    this.ragePerTurn = 0,
    this.ultimateCostMul = 1,
    this.boardRules = BoardRules.none,
  });

  static const RoguelikeEffects none = RoguelikeEffects();

  bool get isDefault => this == none;

  RoguelikeEffects copyWith({
    double? damageMul,
    double? comboBaseBonus,
    double? critToShield,
    double? healOverflowToShield,
    double? shieldReflect,
    double? rageOverflowDamage,
    double? curseToSpecialPower,
    bool? cursePersists,
    double? executeThreshold,
    double? executeBonus,
    int? selfDamagePerTurn,
    double? shieldGainMul,
    int? ragePerTurn,
    double? ultimateCostMul,
    BoardRules? boardRules,
  }) {
    return RoguelikeEffects(
      damageMul: damageMul ?? this.damageMul,
      comboBaseBonus: comboBaseBonus ?? this.comboBaseBonus,
      critToShield: critToShield ?? this.critToShield,
      healOverflowToShield: healOverflowToShield ?? this.healOverflowToShield,
      shieldReflect: shieldReflect ?? this.shieldReflect,
      rageOverflowDamage: rageOverflowDamage ?? this.rageOverflowDamage,
      curseToSpecialPower: curseToSpecialPower ?? this.curseToSpecialPower,
      cursePersists: cursePersists ?? this.cursePersists,
      executeThreshold: executeThreshold ?? this.executeThreshold,
      executeBonus: executeBonus ?? this.executeBonus,
      selfDamagePerTurn: selfDamagePerTurn ?? this.selfDamagePerTurn,
      shieldGainMul: shieldGainMul ?? this.shieldGainMul,
      ragePerTurn: ragePerTurn ?? this.ragePerTurn,
      ultimateCostMul: ultimateCostMul ?? this.ultimateCostMul,
      boardRules: boardRules ?? this.boardRules,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoguelikeEffects &&
      other.damageMul == damageMul &&
      other.comboBaseBonus == comboBaseBonus &&
      other.critToShield == critToShield &&
      other.healOverflowToShield == healOverflowToShield &&
      other.shieldReflect == shieldReflect &&
      other.rageOverflowDamage == rageOverflowDamage &&
      other.curseToSpecialPower == curseToSpecialPower &&
      other.cursePersists == cursePersists &&
      other.executeThreshold == executeThreshold &&
      other.executeBonus == executeBonus &&
      other.selfDamagePerTurn == selfDamagePerTurn &&
      other.shieldGainMul == shieldGainMul &&
      other.ragePerTurn == ragePerTurn &&
      other.ultimateCostMul == ultimateCostMul &&
      other.boardRules == boardRules;

  @override
  int get hashCode => Object.hash(
        damageMul,
        comboBaseBonus,
        critToShield,
        healOverflowToShield,
        shieldReflect,
        rageOverflowDamage,
        curseToSpecialPower,
        cursePersists,
        executeThreshold,
        executeBonus,
        selfDamagePerTurn,
        shieldGainMul,
        ragePerTurn,
        ultimateCostMul,
        boardRules,
      );
}
