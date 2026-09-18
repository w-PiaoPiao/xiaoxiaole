import 'gem.dart';

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
  });

  bool get enrages => enrageAt > 0;
}

/// 关卡定义：一个敌人 + 一句战场提示。
class LevelDef {
  final int index;
  final String name;
  final String subtitle;
  final EnemyDef enemy;

  const LevelDef({
    required this.index,
    required this.name,
    required this.subtitle,
    required this.enemy,
  });
}

/// 玩家在一局中的成长参数（目前全局固定，便于后续做升级系统）。
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

  const PlayerProfile({
    this.maxHp = 300,
    this.redDamage = 26,
    this.blueShield = 20,
    this.greenHeal = 28,
    this.yellowRage = 9,
    this.purpleCurse = 1,
    this.maxShield = 250,
    this.maxRage = 100,
    this.maxCurseStacks = 6,
    this.ultimateCost = 100,
    this.ultimateBonusDamage = 150,
    this.ultimateMultiplier = 1.6,
  });
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
        title: '徘徊的残念',
        taunt: '「又一个闯入者……陪我玩会儿吧。」',
        archetype: EnemyArchetype.wisp,
        maxHp: 2200,
        attack: 40,
        turnsPerAttack: 3,
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
        maxHp: 2800,
        attack: 66,
        turnsPerAttack: 3,
        shieldRegen: 34,
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
        maxHp: 3200,
        attack: 72,
        turnsPerAttack: 2,
        heavyEvery: 3,
        heavyMultiplier: 2.0,
        themeColor: 0xFF9B7BE8,
      ),
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
        maxHp: 3600,
        attack: 112,
        turnsPerAttack: 3,
        healBlockTurns: 3,
        shieldRegen: 20,
        themeColor: 0xFFE85A7A,
      ),
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
        maxHp: 4000,
        attack: 130,
        turnsPerAttack: 3,
        heavyEvery: 3,
        shieldRegen: 30,
        enrageAt: 0.4,
        themeColor: 0xFFFF4D6D,
      ),
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
        maxHp: 4400,
        attack: 126,
        turnsPerAttack: 2,
        heavyEvery: 3,
        heavyMultiplier: 1.7,
        drainRatio: 0.18,
        shieldRegen: 20,
        enrageAt: 0.35,
        themeColor: 0xFFB44BFF,
      ),
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
