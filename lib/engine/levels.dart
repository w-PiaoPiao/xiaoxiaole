import 'gem.dart';
import 'roguelike.dart';

/// 敌人的行为原型，决定它的攻击节奏与额外机制。
enum EnemyArchetype {
  /// 鬼火：基础型，攻击间隔长、伤害中等。
  wisp,

  /// 守卫：拥有可再生护盾，需要用高爆发击穿。
  guardian,

  /// 刺客：攻击间隔短，压制力强。
  assassin,

  /// 巫女：会让玩家陷入治疗削弱。
  witch,

  /// 魔女：血量低于阈值后狂暴，攻速与伤害提升。
  enchantress,

  /// 终焉：会吸取生命，越打越强。
  warlord,
}

/// 关卡中一个敌人的静态配置。
class EnemyDef {
  final String id;
  final String name;
  final String title;

  /// 战斗开始时的一句话。
  final String taunt;

  final EnemyArchetype archetype;

  final int maxHp;

  /// 每次攻击的基础伤害。
  final int attack;

  /// 每积累多少次玩家行动后出手。
  final int turnsPerAttack;

  /// 每 N 次攻击打出一次重击（重击会提前一回合预警）。
  final int heavyEvery;

  final double heavyMultiplier;

  /// 每个敌方回合回复的护盾。
  final int shieldRegen;

  /// 命中玩家时附加的「治疗削弱」回合数。
  final int healBlockTurns;

  /// 造成伤害后按比例回复自身生命（吸血）。
  final double drainRatio;

  /// 生命低于该比例时狂暴（0 表示不会狂暴）。
  final double enrageAt;

  /// 命中玩家时夺走的怒气（「汲魂」机制：打得越狠，必杀来得越慢）。
  final int rageDrain;

  /// 血条管数（形态数）。1 = 单管，打空就结束。
  ///
  /// 多管血不是"血更多"的同义词：每打空一管，敌人满血进入下一形态，
  /// 身上的易伤与护盾清零、出手倒计时重置，攻击还按 [phaseAttackGrowth]
  /// 逐管变强——玩家每打空一管都要把优势重新建立一遍，这才是它带来的
  /// 深度。总血量 = maxHp × phases。
  final int phases;

  /// 每进入下一形态，攻击力提升的比例（0.15 = 每管 +15%）。
  final double phaseAttackGrowth;

  /// 章节配色（用于光效）。
  final int themeColor;

  const EnemyDef({
    required this.id,
    required this.name,
    required this.title,
    required this.taunt,
    required this.archetype,
    required this.maxHp,
    required this.attack,
    required this.turnsPerAttack,
    required this.themeColor,
    this.heavyEvery = 4,
    this.heavyMultiplier = 1.8,
    this.shieldRegen = 0,
    this.healBlockTurns = 0,
    this.drainRatio = 0,
    this.enrageAt = 0,
    this.rageDrain = 0,
    this.phases = 1,
    this.phaseAttackGrowth = 0.15,
  });

  bool get enrages => enrageAt > 0;

  /// 多形态敌人（打空一管还有下一管）。
  bool get hasPhases => phases > 1;

  /// 总血量：所有形态加起来。[maxHp] 是**每管**的血量。
  int get totalHp => maxHp * phases;
}

/// 关卡定义：一个敌人 + 一句战场提示。
class LevelDef {
  final int index;
  final String name;
  final String subtitle;
  final EnemyDef enemy;

  /// 开局布置在棋盘上的机关（种类 → 数量）。空表示纯宝石棋盘。
  ///
  /// 机关是关卡的布置、不是敌人的技能：同一个关卡每次开局都摆同一套，
  /// 数量固定、位置随机（由棋盘自己的随机源决定，可复现）。
  final Map<ObstacleKind, int> obstacles;

  const LevelDef({
    required this.index,
    required this.name,
    required this.subtitle,
    required this.enemy,
    this.obstacles = const {},
  });
}

/// 玩家在一局中的成长参数。
///
/// 这是一个**不可变**值对象：一次挑战（campaign）从 [Campaign.player] 出发，
/// 每打完一关挑一条 [Upgrade]，用 [copyWith] 换出一份新的档案。战斗只读取它、
/// 从不修改它，因此跨关卡的成长不会反过来污染全局默认值。
class PlayerProfile {
  final int maxHp;
  final int redDamage;
  final int blueShield;
  final int greenHeal;
  final int yellowRage;
  final int purpleCurse;
  final int maxShield;
  final int maxRage;
  final int maxCurseStacks;
  final int ultimateCost;
  final int ultimateBonusDamage;
  final double ultimateMultiplier;

  /// 暴击概率。基础为 0——暴击是打强化才解锁的爽点，不该一开始就随机。
  final double critChance;

  /// 暴击伤害倍率。
  final double critMultiplier;

  /// 连锁倍率的上限（基础 2.5 倍）。
  final double comboCap;

  /// 强化宝石额外伤害的倍率。
  final double specialPower;

  /// 每一层易伤提供的伤害加成（基础 12%）。
  final double curseBonus;

  /// 每个玩家回合开始时回复的生命。
  final int regenPerTurn;

  /// 受到的伤害减免比例。
  final double damageReduction;

  /// 生命低于 [desperateThreshold] 时的伤害加成。
  final double desperateBonus;

  /// 无尽模式的肉鸽质变与代价。
  ///
  /// 与上面那些"数字更大"的成长字段分开存放：这里装的是**规则改变**
  /// （暴击顺带产盾、易伤不再清零）与**新增的负面机制**（每回合自损）。
  /// 出厂档案的 [RoguelikeEffects.none] 与没有强化时完全等价。
  final RoguelikeEffects effects;

  const PlayerProfile({
    this.maxHp = 300,
    this.redDamage = 26,
    this.blueShield = 13,
    this.greenHeal = 21,
    // 每颗黄宝石的怒气。这个数字直接决定必杀「斩月」的出场频率：
    // 9 点时推演里一局能放 4.7 次（每 2.75 回合就要"选斩月再选落点"
    // 一次，节奏被打断得七零八落）；4 点时降到 2.3 次，必杀回到
    // "攒出来的大招"该有的份量。改这个数请用 tool 里的推演口径复核。
    this.yellowRage = 4,
    this.purpleCurse = 1,
    this.maxShield = 250,
    this.maxRage = 100,
    this.maxCurseStacks = 6,
    this.ultimateCost = 100,
    this.ultimateBonusDamage = 150,
    this.ultimateMultiplier = 1.6,
    this.critChance = 0,
    this.critMultiplier = 2.0,
    this.comboCap = 2.5,
    this.specialPower = 1.0,
    this.curseBonus = 0.12,
    this.regenPerTurn = 0,
    this.damageReduction = 0,
    this.desperateBonus = 0,
    this.effects = RoguelikeEffects.none,
  });

  /// 棋盘层规则（棱镜多清一色、5x5 爆裂、破空成十字）。棋盘引擎不认识档案，
  /// 由调用方把它显式传进 `resolveSwap` / `resolveUltimate`。
  BoardRules get boardRules => effects.boardRules;

  /// 生命低于这个比例时进入「逆境」，触发 [desperateBonus]。
  static const double desperateThreshold = 0.4;

  /// 减伤的上限：再厚的强化也不能变成完全免伤。
  static const double maxDamageReduction = 0.6;

  PlayerProfile copyWith({
    int? maxHp,
    int? redDamage,
    int? blueShield,
    int? greenHeal,
    int? yellowRage,
    int? purpleCurse,
    int? maxShield,
    int? maxRage,
    int? maxCurseStacks,
    int? ultimateCost,
    int? ultimateBonusDamage,
    double? ultimateMultiplier,
    double? critChance,
    double? critMultiplier,
    double? comboCap,
    double? specialPower,
    double? curseBonus,
    int? regenPerTurn,
    double? damageReduction,
    double? desperateBonus,
    RoguelikeEffects? effects,
  }) {
    return PlayerProfile(
      maxHp: maxHp ?? this.maxHp,
      redDamage: redDamage ?? this.redDamage,
      blueShield: blueShield ?? this.blueShield,
      greenHeal: greenHeal ?? this.greenHeal,
      yellowRage: yellowRage ?? this.yellowRage,
      purpleCurse: purpleCurse ?? this.purpleCurse,
      maxShield: maxShield ?? this.maxShield,
      maxRage: maxRage ?? this.maxRage,
      maxCurseStacks: maxCurseStacks ?? this.maxCurseStacks,
      ultimateCost: ultimateCost ?? this.ultimateCost,
      ultimateBonusDamage: ultimateBonusDamage ?? this.ultimateBonusDamage,
      ultimateMultiplier: ultimateMultiplier ?? this.ultimateMultiplier,
      critChance: critChance ?? this.critChance,
      critMultiplier: critMultiplier ?? this.critMultiplier,
      comboCap: comboCap ?? this.comboCap,
      specialPower: specialPower ?? this.specialPower,
      curseBonus: curseBonus ?? this.curseBonus,
      regenPerTurn: regenPerTurn ?? this.regenPerTurn,
      damageReduction: damageReduction ?? this.damageReduction,
      desperateBonus: desperateBonus ?? this.desperateBonus,
      effects: effects ?? this.effects,
    );
  }
}

/// 五个关卡 + 终局 BOSS。
class Campaign {
  static const PlayerProfile player = PlayerProfile();

  static const List<LevelDef> levels = [
    LevelDef(
      index: 0,
      name: '第一战',
      subtitle: '迷雾中的低语',
      enemy: EnemyDef(
        id: 'wisp',
        name: '迷雾鬼火',
        title: '窃魂的低语',
        taunt: '「把你的怒火……留给我，好吗？」',
        archetype: EnemyArchetype.wisp,
        maxHp: 2600,
        attack: 62,
        turnsPerAttack: 3,
        rageDrain: 8,
        themeColor: 0xFF57E0C8,
      ),
    ),
    LevelDef(
      index: 1,
      name: '第二战',
      subtitle: '不动之壁',
      enemy: EnemyDef(
        id: 'guardian',
        name: '石甲守卫',
        title: '沉默的门扉',
        taunt: '「此路不通。」',
        archetype: EnemyArchetype.guardian,
        maxHp: 3600,
        attack: 118,
        turnsPerAttack: 3,
        shieldRegen: 42,
        heavyEvery: 3,
        themeColor: 0xFFE0A94A,
      ),
    ),
    LevelDef(
      index: 2,
      name: '第三战',
      subtitle: '影中之刃',
      enemy: EnemyDef(
        id: 'assassin',
        name: '影刃刺客',
        title: '无声的追猎者',
        taunt: '「你眨眼的功夫，就够了。」',
        archetype: EnemyArchetype.assassin,
        maxHp: 4400,
        attack: 106,
        turnsPerAttack: 2,
        heavyEvery: 3,
        heavyMultiplier: 2.0,
        themeColor: 0xFF9B7BE8,
      ),
      // 刺客出手快，两块冰封专门打断连招节奏：先破冰还是先输出，得选。
      obstacles: {ObstacleKind.frost: 2},
    ),
    LevelDef(
      index: 3,
      name: '第四战',
      subtitle: '血月的诅咒',
      enemy: EnemyDef(
        id: 'witch',
        name: '血月巫女',
        title: '织咒之人',
        taunt: '「你的伤口，不会再愈合了。」',
        archetype: EnemyArchetype.witch,
        maxHp: 5300,
        attack: 162,
        turnsPerAttack: 3,
        healBlockTurns: 4,
        shieldRegen: 20,
        themeColor: 0xFFE85A7A,
      ),
      // 巫女禁疗，再用一株毒藤逼玩家在"补血"和"清藤"之间排队。
      // 冰封只放一块：这一关已经有禁疗加毒藤，机关再堆就把压力叠死了。
      obstacles: {ObstacleKind.frost: 1, ObstacleKind.vine: 1},
    ),
    LevelDef(
      index: 4,
      name: '第五战',
      subtitle: '深渊的诱惑',
      enemy: EnemyDef(
        id: 'enchantress',
        name: '深渊魔女',
        title: '契约的持有者',
        taunt: '「把心交给我，我就不疼了。」',
        archetype: EnemyArchetype.enchantress,
        // 三管血：魔女是第一个会"死而复生"的敌人，教玩家认识多形态——
        // 打空一管不算赢，易伤清零、她更凶地站起来。每管刻意压小，
        // 让一次布好的连锁就能打掉血条的一大截（消减要看得见）。
        maxHp: 1870,
        phases: 3,
        attack: 170,
        turnsPerAttack: 3,
        heavyEvery: 3,
        shieldRegen: 30,
        enrageAt: 0.4,
        themeColor: 0xFFFF4D6D,
      ),
      // 两株毒藤让魔女的攻击更重，残血狂暴阶段会非常危险。
      obstacles: {ObstacleKind.frost: 1, ObstacleKind.vine: 2},
    ),
    LevelDef(
      index: 5,
      name: '终战',
      subtitle: '终焉之影',
      enemy: EnemyDef(
        id: 'warlord',
        name: '终焉之影',
        title: '吞噬一切的黑',
        taunt: '「你打赢的一切，都会成为我的一部分。」',
        archetype: EnemyArchetype.warlord,
        // 四管血的最终战：每打空一管都要重新铺易伤、重新排节奏，
        // 而它每醒一次都更凶——终局的"终"是形态的四次递进。
        maxHp: 1725,
        phases: 4,
        attack: 158,
        turnsPerAttack: 2,
        heavyEvery: 3,
        heavyMultiplier: 1.7,
        drainRatio: 0.22,
        shieldRegen: 20,
        enrageAt: 0.35,
        themeColor: 0xFFB44BFF,
      ),
      // 终战：一株毒藤压着吸血与狂暴的节奏，祭坛是留给玩家的怒气补给。
      obstacles: {ObstacleKind.vine: 1, ObstacleKind.altar: 1},
    ),
  ];
}

/// 宝石效果的中文说明，用于图例展示。
///
/// 括号里是和宝石图标对应的图形，方便玩家把「看到的符号」和「效果」直接挂钩。
String gemEffectLabel(GemType type) {
  switch (type) {
    case GemType.red:
      return '交叉双剑 · 对敌人造成伤害';
    case GemType.blue:
      return '盾牌 · 为自己积累护盾';
    case GemType.green:
      return '十字 · 恢复生命';
    case GemType.yellow:
      return '闪电 · 积攒怒气';
    case GemType.purple:
      return '骷髅 · 让敌人陷入易伤';
  }
}
