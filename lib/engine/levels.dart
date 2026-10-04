import 'gem.dart';
import 'roguelike.dart';

/// 敌方角色的行为原型。战役的十三位美少女各占一个，决定立绘分发与
/// 无尽模式的登场顺序；战斗机制由 [EnemyDef] 的字段与 [EnemyDef.skill]
/// 共同决定，原型本身不再携带数值。
enum EnemyArchetype {
  /// 妖精：森之报春，基础型，攻击间隔长、伤害中等。
  fairy,

  /// 圣女：举盾守望，拥有可再生护盾，需要用高爆发击穿。
  saint,

  /// 忍者：影巷追猎，攻击间隔短，压制力强。
  kunoichi,

  /// 魔女：血月织咒，会让玩家陷入治疗削弱与咒毒。
  witch,

  /// 魅魔：深渊当铺，血量低于阈值后狂暴，攻速与伤害提升。
  succubus,

  /// 月祭司：孤月女官，会偷走玩家的怒气。
  moonPriestess,

  /// 人鱼：沉船歌姬，护盾再生与自愈让长战越来越难。
  mermaid,

  /// 冰姬：不融雪庄，重击极重，会给自己结冰甲。
  frostMaiden,

  /// 吸血鬼：午夜沙龙，命中玩家即可回血。
  vampire,

  /// 傀儡师：镜楼缝影，会缠住玩家的护盾。
  puppeteer,

  /// 巫姬：永恒工坊，越打越强的机关造物。
  machina,

  /// 龙女：天巢公主，多管血，重击无视护盾。
  dragonPrincess,

  /// 观测者：裂隙尽头，吸血 + 咒毒的最终形态。
  voidWatcher,
}

/// 角色的专属技能。
///
/// 每位美少女除基础机制（出手节奏、护盾再生、吸血、狂暴……）外，还有一个
/// 只属于她的技能：每 [EnemyDef.skillEvery] 次敌方行动触发一次。技能的选择
/// 对应角色的性格与故事——妖精自愈、圣女结界、忍者分身、魔女下毒……
enum EnemySkillKind {
  /// 自愈：回复自身最大生命的 [EnemySkill.ratio]。
  sprout,

  /// 冰甲 / 圣壁：获得自身最大生命 [EnemySkill.ratio] 的护盾。
  barrier,

  /// 分身 / 血宴：追加一段 [EnemySkill.ratio] 倍攻击力的伤害。
  shadowStrike,

  /// 咒毒：玩家每回合损失 [EnemySkill.amount] 点生命，持续 [EnemySkill.turns] 回合。
  hex,

  /// 魅惑：夺走玩家当前护盾的 [EnemySkill.ratio]。
  charm,

  /// 月蚀：偷走玩家 [EnemySkill.amount] 点怒气。
  eclipse,

  /// 缠缚：玩家的护盾获取在 [EnemySkill.turns] 回合内减半。
  snare,

  /// 过载：攻击力永久提升 [EnemySkill.ratio]，可叠层（封顶 5 层）。
  surge,

  /// 龙威：本次攻击无视玩家的护盾。
  crush,
}

/// 一个专属技能的参数。
class EnemySkill {
  final String name;

  final EnemySkillKind kind;

  /// 自愈 / 护盾 / 追加攻击段 / 魅惑吸取 / 过载增攻的比例。
  final double ratio;

  /// 咒毒每回合伤害 / 月蚀偷取的怒气。
  final int amount;

  /// 咒毒与缠缚的持续回合数。
  final int turns;

  const EnemySkill({
    required this.name,
    required this.kind,
    this.ratio = 0,
    this.amount = 0,
    this.turns = 0,
  });
}

/// 关卡中一位敌方美少女的静态配置。
class EnemyDef {
  final String id;
  final String name;
  final String title;

  /// 出身与来历：开场卡上的一小段自白。
  final String story;

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

  /// 专属技能：每 [skillEvery] 次敌方行动触发一次。null 表示没有技能。
  final EnemySkill? skill;

  /// 多少次敌方行动触发一次 [skill]。
  final int skillEvery;

  /// 血条管数（形态数）。1 = 单管，打空就结束。
  ///
  /// 多管血不是"血更多"的同义词：每打空一管，敌人满血进入下一形态，
  /// 身上的易伤与护盾清零、出手倒计时重置，攻击还按 [phaseAttackGrowth]
  /// 逐管变强——玩家每打空一管都要把优势重新建立一遍，这才是它带来的
  /// 深度。总血量 = maxHp × phases。
  final int phases;

  /// 每进入下一形态，攻击力提升的比例（0.15 = 每管 +15%）。
  final double phaseAttackGrowth;

  /// 消耗战惩罚：同一波内从 [BattleState.attritionStartTurn] 个玩家回合起，
  /// 每 [BattleState.attritionEveryTurns] 回合攻击力提升的比例。0 = 关闭。
  ///
  /// 它管的是"僵持"：输出跟不上的 build 不会被一刀砍死，但会被越来越重的
  /// 每一击磨死。没有它，无尽模式的终局会退化成"玩家满血站着、敌人也不掉
  /// 血"的无限平局（详见 [BattleState.incomingHitCapRatio] 与
  /// [EndlessRoster.attritionRamp]）。战役不启用：短局的紧张感来自封顶，
  /// 不需要一条时间轴。
  final double attritionRamp;

  /// 章节配色（用于光效）。
  final int themeColor;

  const EnemyDef({
    required this.id,
    required this.name,
    required this.title,
    required this.story,
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
    this.skill,
    this.skillEvery = 4,
    this.phases = 1,
    this.phaseAttackGrowth = 0.15,
    this.attritionRamp = 0,
  });

  bool get enrages => enrageAt > 0;

  /// 多形态敌人（打空一管还有下一管）。
  bool get hasPhases => phases > 1;

  /// 总血量：所有形态加起来。[maxHp] 是**每管**的血量。
  int get totalHp => maxHp * phases;
}

/// 关卡定义：一位美少女 + 一句战场提示。
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

/// 十三位美少女 + 裂隙尽头的观测者。
///
/// 十三关是一条完整的巡礼：前六位（妖精到魅魔）是老六关的重塑，难度
/// 平缓爬升；第七位起进入"各有专精"的中段——人鱼的长战、冰姬的重击、
/// 吸血鬼的续航，每位都逼玩家换一种解法；第十二位起进入多管血与组合
/// 机制，最终在观测者面前收束。玩家 12 次三选一的成长对应敌人从 2600
/// 到 3900×2 / 1725×4 的曲线，整体口径用 tool/balance_report.dart 校准。
class Campaign {
  static const PlayerProfile player = PlayerProfile();

  static const List<LevelDef> levels = [
    // ---------------------------------------------------------------- 第一战
    // 妖精：教学关。她唯一会做的事就是偶尔给自己回一点血——教玩家认识
    // "有的敌人会自愈，打得慢就打不死"。
    LevelDef(
      index: 0,
      name: '第一战',
      subtitle: '迷雾之森',
      enemy: EnemyDef(
        id: 'fairy',
        name: '茉黎',
        title: '报春的妖精',
        story: '迷雾森林的守誓妖精。千年来她向每一位闯入者收取"路费"——'
            '一点怒火、一缕执念。她早已忘记自己守护的是什么，'
            '只是不想承认：她可能已经被遗忘了。',
        taunt: '「迷雾后面藏着什么呢？走近一点，我帮你保密。」',
        archetype: EnemyArchetype.fairy,
        maxHp: 2600,
        attack: 76,
        turnsPerAttack: 3,
        skill: EnemySkill(
          name: '萌芽复苏',
          kind: EnemySkillKind.sprout,
          ratio: 0.07,
        ),
        skillEvery: 4,
        themeColor: 0xFF57E0C8,
      ),
    ),
    // ---------------------------------------------------------------- 第二战
    // 圣女：护盾再生让低爆发输出变成打木桩——教玩家"要么攒一发大的，
    // 要么先把盾磨穿"。
    LevelDef(
      index: 1,
      name: '第二战',
      subtitle: '白塔之门',
      enemy: EnemyDef(
        id: 'saint',
        name: '瑟兰',
        title: '白塔的守望者',
        story: '白塔的祈祷官，以石垒塔、以盾守门。她挡下的从来不是恶意，'
            '而是"不确定性"。直到某天有人告诉她：门外的新芽，'
            '比塔里的圣像更需要光。',
        taunt: '「在此止步。门外的事，交给明天。」',
        archetype: EnemyArchetype.saint,
        maxHp: 3600,
        attack: 128,
        turnsPerAttack: 3,
        shieldRegen: 42,
        heavyEvery: 3,
        skill: EnemySkill(
          name: '圣光壁垒',
          kind: EnemySkillKind.barrier,
          ratio: 0.12,
        ),
        skillEvery: 4,
        themeColor: 0xFFE0A94A,
      ),
    ),
    // ---------------------------------------------------------------- 第三战
    // 忍者：出手最快的角色。分身技能让"下一次出手"永远比预警写得更痛。
    LevelDef(
      index: 2,
      name: '第三战',
      subtitle: '影巷月夜',
      enemy: EnemyDef(
        id: 'kunoichi',
        name: '绯雨',
        title: '影巷的追猎者',
        story: '月夜巷弄里最快的一柄刀，受雇于"看不见的委托人"。'
            '她的猎杀清单上有自己的名字——而她一直没敢去看最后一行。',
        taunt: '「别眨眼——我说的是你，不是我。」',
        archetype: EnemyArchetype.kunoichi,
        maxHp: 4400,
        attack: 98,
        turnsPerAttack: 2,
        heavyEvery: 4,
        heavyMultiplier: 1.85,
        skill: EnemySkill(
          name: '影分身',
          kind: EnemySkillKind.shadowStrike,
          ratio: 0.5,
        ),
        skillEvery: 4,
        themeColor: 0xFF9B7BE8,
      ),
      // 忍者出手快，两块冰封专门打断连招节奏：先破冰还是先输出，得选。
      obstacles: {ObstacleKind.frost: 2},
    ),
    // ---------------------------------------------------------------- 第四战
    // 魔女：禁疗 + 咒毒双重侵蚀。绿宝石不再是万能药。
    LevelDef(
      index: 3,
      name: '第四战',
      subtitle: '血月低语',
      enemy: EnemyDef(
        id: 'witch',
        name: '薇尔',
        title: '血月的织咒人',
        story: '每逢血月，她便为村庄"接生诅咒"：替人把疼痛缝进布偶，'
            '代价是自己也数不清缝掉了什么。她说伤口不愈合不是恶意——'
            '只是舍不得让你好起来。',
        taunt: '「你的伤口，由我来收藏。」',
        archetype: EnemyArchetype.witch,
        maxHp: 5300,
        attack: 154,
        turnsPerAttack: 3,
        healBlockTurns: 4,
        shieldRegen: 20,
        skill: EnemySkill(
          name: '猩红咒毒',
          kind: EnemySkillKind.hex,
          amount: 20,
          turns: 3,
        ),
        skillEvery: 4,
        themeColor: 0xFFE85A7A,
      ),
      // 禁疗 + 咒毒已经把压力叠起来了，机关只放一株毒藤压节奏。
      obstacles: {ObstacleKind.vine: 1},
    ),
    // ---------------------------------------------------------------- 第五战
    // 魅魔：三管血 + 魅惑夺盾。教玩家认识多形态——打空一管不算赢。
    LevelDef(
      index: 4,
      name: '第五战',
      subtitle: '深渊当铺',
      enemy: EnemyDef(
        id: 'succubus',
        name: '夜歌',
        title: '深渊的契约持有人',
        story: '在深渊边缘开当铺的魅魔，专收"不要的心"。契约只有一行：'
            '把心交给我，我就不疼了。她把收回的心挂满店墙，'
            '等一个永远不来的赎回者。',
        taunt: '「把心交给我，我就不疼了。」',
        archetype: EnemyArchetype.succubus,
        // 三管血：魅魔是第一个会"死而复生"的敌人。每管刻意压小，
        // 让一次布好的连锁就能打掉血条的一大截（消减要看得见）。
        maxHp: 1870,
        phases: 3,
        attack: 170,
        turnsPerAttack: 3,
        heavyEvery: 3,
        shieldRegen: 26,
        enrageAt: 0.4,
        skill: EnemySkill(
          name: '魅惑凝视',
          kind: EnemySkillKind.charm,
          ratio: 0.45,
        ),
        skillEvery: 4,
        themeColor: 0xFFFF4D6D,
      ),
      // 两株毒藤让魅魔的攻击更重，残血狂暴阶段会非常危险。
      obstacles: {ObstacleKind.frost: 1, ObstacleKind.vine: 2},
    ),
    // ---------------------------------------------------------------- 第六战
    // 月祭司：偷怒气的正面教学。必杀被她一勺一勺端走——黄宝石要省着用。
    LevelDef(
      index: 5,
      name: '第六战',
      subtitle: '孤月祭坛',
      enemy: EnemyDef(
        id: 'moonPriestess',
        name: '凛月',
        title: '孤月的女官',
        story: '月宫最后一任司香女官，负责在满月夜把人间的祈愿烧给月亮。'
            '月亮早已熄灭，她把没人收走的祈愿叠成一座塔，'
            '仍一夜一夜地烧。',
        taunt: '「祈愿太多了，借你的怒火一用。」',
        archetype: EnemyArchetype.moonPriestess,
        maxHp: 5800,
        attack: 176,
        turnsPerAttack: 3,
        heavyEvery: 3,
        skill: EnemySkill(
          name: '月蚀',
          kind: EnemySkillKind.eclipse,
          amount: 16,
        ),
        skillEvery: 4,
        themeColor: 0xFF9FD8FF,
      ),
      // 她偷怒气，祭坛补给怒气：补给线上的攻防战。
      obstacles: {ObstacleKind.altar: 1},
    ),
    // ---------------------------------------------------------------- 第七战
    // 人鱼：自愈 + 护盾再生的"长战"型。输出不够就永远沉在海里。
    LevelDef(
      index: 6,
      name: '第七战',
      subtitle: '沉船之湾',
      enemy: EnemyDef(
        id: 'mermaid',
        name: '琳',
        title: '沉船的歌姬',
        story: '沉船湾的歌姬，为每一位溺亡者唱最后一支歌。'
            '海面漂来的东西她都收进珊瑚匣——包括那封永远寄不出去的信。',
        taunt: '「听歌吧，海底不挤。」',
        archetype: EnemyArchetype.mermaid,
        maxHp: 6200,
        attack: 182,
        turnsPerAttack: 3,
        heavyEvery: 4,
        shieldRegen: 24,
        skill: EnemySkill(
          name: '深海之拥',
          kind: EnemySkillKind.sprout,
          ratio: 0.09,
        ),
        skillEvery: 4,
        themeColor: 0xFF4FC3E8,
      ),
      obstacles: {ObstacleKind.vine: 2},
    ),
    // ---------------------------------------------------------------- 第八战
    // 冰姬：单次伤害的巅峰。预警数字第一次变得比玩家的半血还高。
    LevelDef(
      index: 7,
      name: '第八战',
      subtitle: '不融雪庄',
      enemy: EnemyDef(
        id: 'frostMaiden',
        name: '艾丝特',
        title: '不融雪的女伯爵',
        story: '被诅咒"领地永不入春"的年轻女伯爵。她把城堡每一扇窗都钉死，'
            '怕春天进来后发现——这里其实什么都没有。',
        taunt: '「这里的雪，从来不为谁停。」',
        archetype: EnemyArchetype.frostMaiden,
        maxHp: 6500,
        attack: 188,
        turnsPerAttack: 3,
        heavyEvery: 3,
        heavyMultiplier: 1.9,
        skill: EnemySkill(
          name: '极寒冰甲',
          kind: EnemySkillKind.barrier,
          ratio: 0.12,
        ),
        skillEvery: 3,
        themeColor: 0xFF8FD0F0,
      ),
      obstacles: {ObstacleKind.frost: 2},
    ),
    // ---------------------------------------------------------------- 第九战
    // 吸血鬼：打了就回。她的血条是"借"玩家的——拖得越久越还不清。
    LevelDef(
      index: 8,
      name: '第九战',
      subtitle: '午夜歌剧院',
      enemy: EnemyDef(
        id: 'vampire',
        name: '卡梅拉',
        title: '绯色的夜宴主人',
        story: '在废弃歌剧院开午夜沙龙的古老血族。她说自己早就不渴了——'
            '她收藏的是"临终前最珍视的那一口"。侍者名单上画满了划痕。',
        taunt: '「入席吧，你看起来正好七分熟。」',
        archetype: EnemyArchetype.vampire,
        maxHp: 6600,
        attack: 196,
        turnsPerAttack: 3,
        heavyEvery: 4,
        drainRatio: 0.20,
        skill: EnemySkill(
          name: '血宴',
          kind: EnemySkillKind.shadowStrike,
          ratio: 0.5,
        ),
        skillEvery: 4,
        themeColor: 0xFFC0395E,
      ),
      // 吸血鬼的续航靠"命中"，一株祭坛给玩家攒出斩月的翻盘窗口。
      obstacles: {ObstacleKind.altar: 1},
    ),
    // ---------------------------------------------------------------- 第十战
    // 傀儡师：缠住玩家的护盾。蓝宝石流在她面前要改打输出。
    LevelDef(
      index: 9,
      name: '第十战',
      subtitle: '镜楼缝影',
      enemy: EnemyDef(
        id: 'puppeteer',
        name: '铃兰',
        title: '镜楼的缝偶人',
        story: '镜楼里的缝偶师，替人偶缝上"客人想要的脸"。'
            '她做的第一只人偶是自己的影子——后来影子先于她，'
            '学会了离开。',
        taunt: '「别动，线才刚缠上你的手腕。」',
        archetype: EnemyArchetype.puppeteer,
        maxHp: 7400,
        attack: 202,
        turnsPerAttack: 3,
        heavyEvery: 4,
        shieldRegen: 26,
        skill: EnemySkill(
          name: '丝线缠缚',
          kind: EnemySkillKind.snare,
          turns: 3,
        ),
        skillEvery: 4,
        themeColor: 0xFFC8A2E0,
      ),
      // 结界压护盾，毒藤压生命，冰封压节奏——三面网只留一条活路：快。
      obstacles: {ObstacleKind.frost: 1, ObstacleKind.vine: 2},
    ),
    // -------------------------------------------------------------- 第十一战
    // 巫姬：越打越强。教玩家"输出流也要看时间"——拖久了她的每一击都更重。
    LevelDef(
      index: 10,
      name: '第十一战',
      subtitle: '永恒工坊',
      enemy: EnemyDef(
        id: 'machina',
        name: '希尔薇',
        title: '永恒工坊的巫姬',
        story: '工匠之城最后一具仍在运转的机关巫姬。城倾覆那天她获得自由，'
            '却把"守城"的指令当成了心愿——工坊塌一次她修一次，'
            '一修就是四百年。',
        taunt: '「检测到入侵。防御协议，永远在线。」',
        archetype: EnemyArchetype.machina,
        maxHp: 7600,
        attack: 204,
        turnsPerAttack: 3,
        heavyEvery: 4,
        shieldRegen: 26,
        skill: EnemySkill(
          name: '过载充能',
          kind: EnemySkillKind.surge,
          ratio: 0.09,
        ),
        skillEvery: 4,
        themeColor: 0xFF7FE0D0,
      ),
      obstacles: {ObstacleKind.frost: 2, ObstacleKind.altar: 1},
    ),
    // -------------------------------------------------------------- 第十二战
    // 龙女：两管血 + 无视护盾的龙威。护盾流的天花板被她一爪子掀掉。
    LevelDef(
      index: 11,
      name: '第十二战',
      subtitle: '龙脊天巢',
      enemy: EnemyDef(
        id: 'dragonPrincess',
        name: '绫羽',
        title: '龙脊天巢的公主',
        story: '龙脊山巅的末代龙裔公主。她把族人的鳞甲一片片嵌回王座，'
            '相信总有一天王座会重新睁眼。她是最年轻的守陵人，'
            '也是最寂寞的火种。',
        taunt: '「王座在等火种。你，恰好会发光。」',
        archetype: EnemyArchetype.dragonPrincess,
        maxHp: 3900,
        phases: 2,
        attack: 218,
        turnsPerAttack: 3,
        heavyEvery: 3,
        enrageAt: 0.4,
        skill: EnemySkill(name: '龙威重压', kind: EnemySkillKind.crush),
        skillEvery: 3,
        themeColor: 0xFFFF8A5C,
      ),
      obstacles: {ObstacleKind.vine: 2, ObstacleKind.altar: 1},
    ),
    // ------------------------------------------------------------------ 终战
    // 观测者：四管血 + 吸血 + 咒毒。前面十二位的一切能力，都在她身上
    // 留下一页——终局的"终"是形态的四次递进。
    LevelDef(
      index: 12,
      name: '终战',
      subtitle: '裂隙尽头',
      enemy: EnemyDef(
        id: 'voidWatcher',
        name: '艾诺拉',
        title: '裂隙尽头的观测者',
        story: '世界的裂隙尽头坐着一位观测者。她记录每一位打赢十三扇门的'
            '挑战者，再把他们打赢的一切收进书里。这本书写满的那天，'
            '故事就会重新开始——她在等一个能让最后一页留白的人。',
        taunt: '「你打赢的一切，都会成为我的一部分。」',
        archetype: EnemyArchetype.voidWatcher,
        // 终战 1975×4:每管血刻意压小让消减看得见,总血 7900 仍压过
        // 上一关——十三关的总血量曲线保持单调,这是玩家可感知的
        // "这一关比上一关更厚"。攻击 204 是按"必杀独占一回合"的真实
        // 推演口径校准的（推演器修正前必杀免费搭在交换回合上,把终战
        // 的压力整个掩盖了）:出厂档案约 4/14,整场三流的卡点不再
        // 系统性堆在终战。
        maxHp: 1975,
        phases: 4,
        attack: 204,
        turnsPerAttack: 2,
        heavyEvery: 3,
        heavyMultiplier: 1.7,
        drainRatio: 0.22,
        shieldRegen: 20,
        enrageAt: 0.35,
        skill: EnemySkill(
          name: '星噬',
          kind: EnemySkillKind.hex,
          amount: 26,
          turns: 3,
        ),
        skillEvery: 3,
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
