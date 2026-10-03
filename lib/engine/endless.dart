import 'gem.dart';
import 'levels.dart';

/// 无尽模式：战役的十三位美少女按序轮换登场，数值与能力随波次单调增强。
///
/// 生成规则是**完全确定**的（同一个波次永远生成同一个 BOSS），没有随机数：
/// 这样平衡报告可以直接推演，测试也可以精确断言某个波次的强度。
///
/// 数值曲线刻意**只由波次决定**：生命按指数、攻击按线性增长，
/// 角色之间不设数值档位。否则轮换回低位角色的那一波会突然变简单，
/// 「越打越强」的承诺就被打破了——角色差异全部体现在机制上
/// （出手节奏、专属技能、护盾再生、吸血、狂暴、汲魂）。
class EndlessRoster {
  const EndlessRoster._();

  /// 第一波的基准数值。刻意定得比战役第一关略低：无尽模式没有强化铺垫的
  /// 热身，开局就该顺手。
  static const int _baseHp = 2400;

  static const int _baseAttack = 46;

  /// 每波的成长：
  ///  - 生命按指数增长，玩家的强化是线性的，跑得越远差距越大，
  ///    这是无尽模式「注定会输，看你能站多久」的数学根源；
  ///  - 攻击按线性增长，并被「单次伤害不超过最大生命 65%」封顶保护，
  ///    高波次不会变成一击必杀的抽奖。
  ///
  /// 生命增速定在 1.14 而不是更陡的 1.18：血量是复利，0.03 的差别到第
  /// 20 波就是 24% 的总血量。曲线陡了，多管血与精英词条辛苦搭出来的
  /// "台阶感"会被指数曲线提前掐死——玩家还没见到第 16 波的 4 管血，
  /// 就已经被单纯的数字压死了。
  static const double hpGrowth = 1.13;

  /// 攻击按线性增长。斜率不需要太陡——它的作用只是"每一波都更疼一点"，
  /// 真正决定一局能站多久的是 [attritionRamp] 这条时间曲线。给大了
  /// （实测 16）会把薄身板的输出流在前 12 波就掐死，而那本该是它积攒
  /// 伤害的阶段。
  static const int attackGrowth = 9;

  /// 消耗战惩罚：同一波内从第 100 个玩家回合起，每 12 回合伤害 +12%
  /// （起点与步进见 [BattleState.attritionStartTurn]）。
  ///
  /// 这是"打不动"的解药。玩家每回合的续航是有限的（实测强续航 build
  /// 约 100~150/回合），而出于封顶保护，敌人的单次伤害不能无限涨——两者
  /// 相抵，僵持战就会变成"玩家满血站着、敌人也不掉血"的无限平局：
  /// 推演里 8 局有 4 局磨满 400 回合仍未分出胜负，玩家血条和护盾都是满的。
  /// 把伤害接到时间轴上之后：输出跟不上的 build 会被越来越重的每一击磨死，
  /// 而打得快的 build 在 30 回合内就抬走对手，完全碰不到这条曲线——
  /// **输出第一次有了直接的生存价值**。
  ///
  /// 阈值刻意取得很晚（100 而非 40）：它是"僵持"的解药，不该变成对所有
  /// 慢节奏 build 的常规惩罚。实测阈值定在 40 时，保命流的中位会从 23 波
  /// 塌到 16 波——强续航 build 的每一波本来就要打 100 回合以上，惩罚变成了
  /// 常态；推后到 100 之后，两条路线（17 / 23 波）与最佳局（47 波）才同时
  /// 站得住。
  static const double attritionRamp = 0.12;

  /// 精英词条：从第 4 波开始每 3 波多带一条，BOSS 的「能力增强」不止是数字，
  /// 还会拿到战役模式里才能见到的机制（护盾再生、吸血、禁疗、狂暴、汲魂）。
  static const List<String> modifierIds = [
    'aegis', // 坚壁：护盾再生
    'thirst', // 嗜血：吸血
    'choke', // 窒息：禁疗
    'frenzy', // 狂性：残血狂暴
    'siphon', // 汲魂：夺走怒气
  ];

  /// 登场顺序：战役十三战的角色轮换，同一角色隔 13 波再登场时更强。
  static const List<String> _order = [
    'fairy',
    'saint',
    'kunoichi',
    'witch',
    'succubus',
    'moonPriestess',
    'mermaid',
    'frostMaiden',
    'vampire',
    'puppeteer',
    'machina',
    'dragonPrincess',
    'voidWatcher',
  ];

  /// 阶位前缀：名字的变化是玩家能直接读到的成长信号。
  static String _prefix(int wave) {
    if (wave >= 19) return '终焉·';
    if (wave >= 13) return '灾变·';
    if (wave >= 7) return '重铸·';
    return '';
  }

  /// 从战役里取角色的机制模板（数值会被本波曲线覆盖）。
  ///
  /// 无尽与战役共用同一份角色定义：出手节奏、专属技能、护盾再生这些
  /// 「怎么打」的字段全在这里继承，避免两处维护一份人设。
  static EnemyDef _template(String id) =>
      Campaign.levels.firstWhere((level) => level.enemy.id == id).enemy;

  /// 技能的回复部分按 [_recoveryScale] 缩放；其余技能原样继承。
  static EnemySkill? _scaleSkill(EnemySkill? skill) {
    if (skill == null) return null;
    switch (skill.kind) {
      case EnemySkillKind.sprout:
      case EnemySkillKind.barrier:
        return EnemySkill(
          name: skill.name,
          kind: skill.kind,
          ratio: skill.ratio * _recoveryScale,
          amount: skill.amount,
          turns: skill.turns,
        );
      default:
        return skill;
    }
  }

  /// 多形态：第 10 波起 3 管血、第 17 波起 4 管。
  ///
  /// 管数给得比战役更密（战役是 2~4 管）：无尽的血量本来就在指数上涨，
  /// 每管必须压得足够小，玩家的一次连锁才能把血条打掉一大截。
  /// 每管血量按 [_phaseHpFactor] 打折，总量与单管曲线持平或略高。
  static int phasesFor(int wave) {
    if (wave >= 17) return 4;
    if (wave >= 10) return 3;
    return 1;
  }

  /// 每管血量相对单管曲线的折扣。
  ///
  /// 总血量 = 每管 × 管数：3 管时约 1.0 倍、4 管时约 1.2 倍。多形态本身
  /// 已经带来「溢出浪费 + 每管优势清零重来」的额外消耗，总血量再翻倍就
  /// 没人跑得远了。
  static const Map<int, double> _phaseHpFactor = {
    1: 1.0,
    2: 0.5,
    3: 0.33,
    4: 0.3,
  };

  /// 回复类机制的缩放系数。
  ///
  /// 角色模板里的吸血、护盾再生与自愈/结盾技能是按**战役后期**的血量
  /// （6600~7800）标定的；无尽前十几波的 BOSS 血量只有 2400~9000，同样
  /// 的比例等于把"回复"放大了三倍——实测吸血鬼在 3 管血下每波白拿
  /// 2000+ 回血，中位波次从 20 塌到 12。伤害类机制（毒、偷怒、缠缚、
  /// 贯穿）是绝对值或比例，不需要缩放。
  static const double _recoveryScale = 0.55;

  /// 生成第 [wave] 波（从 1 开始）的 BOSS。
  static EnemyDef enemyFor(int wave) {
    assert(wave >= 1);
    final shape = _template(_order[(wave - 1) % _order.length]);
    final phases = phasesFor(wave);
    final hpFactor = _phaseHpFactor[phases] ?? 1.0;
    final skill = _scaleSkill(shape.skill);
    var def = EnemyDef(
      id: shape.id,
      name: '${_prefix(wave)}${shape.name}',
      title: shape.title,
      story: shape.story,
      taunt: shape.taunt,
      archetype: shape.archetype,
      maxHp: (_baseHp * _hpScale(wave - 1) * hpFactor).round(),
      phases: phases,
      attack: _baseAttack + attackGrowth * (wave - 1),
      turnsPerAttack: shape.turnsPerAttack,
      heavyEvery: shape.heavyEvery,
      heavyMultiplier: shape.heavyMultiplier,
      shieldRegen: (shape.shieldRegen * _recoveryScale).round(),
      healBlockTurns: shape.healBlockTurns,
      drainRatio: shape.drainRatio * _recoveryScale,
      enrageAt: shape.enrageAt,
      rageDrain: shape.rageDrain,
      skill: skill,
      skillEvery: shape.skillEvery,
      attritionRamp: attritionRamp,
      themeColor: shape.themeColor,
    );

    // 精英词条按波次逐条叠上。词条是依次取用的（不随机），所以高波次的
    // BOSS 会同时带着多条机制，威胁是「台阶式」上升的。
    final count = modifierCount(wave);
    if (count == 0) return def;

    var shieldRegen = def.shieldRegen;
    var drain = def.drainRatio;
    var healBlock = def.healBlockTurns;
    var enrage = def.enrageAt;
    var rageDrain = def.rageDrain;
    for (var i = 0; i < count; i++) {
      switch (modifierIds[i % modifierIds.length]) {
        case 'aegis':
          shieldRegen += 24;
        case 'thirst':
          // 自带吸血的角色不再叠词条——0.24 + 0.08 的乘法叠加会把
          // 三管血的夜宴变成"每打 1000 回 210"的墙，damage 流会成批
          // 撞死在第 9~12 波。词条额度直接让给"没有这条机制"的波。
          if (drain > 0) continue;
          drain += 0.08;
        case 'choke':
          // 禁疗词条每条 +1 回合：+2 起步对靠治疗的生存流是灭顶的
          // （四条词条就是常驻禁疗），对不靠治疗的输出流又是白给的
          // 死亡加速——两个方向都会把中位压塌，+1 是两个流派都能忍的档。
          healBlock += 1;
        case 'frenzy':
          enrage = enrage > 0 ? enrage : 0.45;
        case 'siphon':
          if (rageDrain > 0) continue;
          rageDrain += 12;
      }
    }
    return def = EnemyDef(
      id: def.id,
      name: def.name,
      title: def.title,
      story: def.story,
      taunt: def.taunt,
      archetype: def.archetype,
      maxHp: def.maxHp,
      phases: def.phases,
      attack: def.attack,
      turnsPerAttack: def.turnsPerAttack,
      heavyEvery: def.heavyEvery,
      heavyMultiplier: def.heavyMultiplier,
      shieldRegen: shieldRegen,
      healBlockTurns: healBlock,
      drainRatio: drain,
      enrageAt: enrage,
      rageDrain: rageDrain,
      skill: def.skill,
      skillEvery: def.skillEvery,
      attritionRamp: def.attritionRamp,
      themeColor: def.themeColor,
    );
  }

  /// 第 [wave] 波（从 1 开始）的机关配置。
  ///
  /// 与精英词条同步：第 4 波起每 3 波多一件机关（冰封与毒藤交替），封顶
  /// 4 件；毒藤最多 3 株（攻击加成 +15% 是设计上限）。祭坛从第 6 波起每
  /// 3 波出现一次——那是留给玩家的怒气补给，和毒藤的压力对冲。
  static Map<ObstacleKind, int> obstaclesFor(int wave) {
    if (wave < 4) return const {};
    final total = ((wave - 1) ~/ 3).clamp(0, 4);
    var frost = 0;
    var vine = 0;
    for (var i = 0; i < total; i++) {
      if (i.isEven) {
        frost++;
      } else {
        vine++;
      }
    }
    if (vine > 3) {
      frost += vine - 3;
      vine = 3;
    }
    final altar = wave >= 6 && wave % 3 == 0 ? 1 : 0;
    return {
      if (frost > 0) ObstacleKind.frost: frost,
      if (vine > 0) ObstacleKind.vine: vine,
      if (altar > 0) ObstacleKind.altar: altar,
    };
  }

  /// 第 [wave] 波（从 1 开始）的关卡包装，供开场卡 / 结算面板直接使用。
  static LevelDef levelFor(int wave) {
    return LevelDef(
      index: wave - 1,
      name: '第 $wave 波',
      subtitle: '无尽回廊',
      enemy: enemyFor(wave),
      obstacles: obstaclesFor(wave),
    );
  }

  static double _hpScale(int wavesElapsed) {
    var scale = 1.0;
    for (var i = 0; i < wavesElapsed; i++) {
      scale *= hpGrowth;
    }
    return scale;
  }

  /// 第 [wave] 波带几条精英词条：第 4 波起每 3 波 +1 条，封顶 5 条。
  static int modifierCount(int wave) {
    if (wave < 4) return 0;
    return ((wave - 1) ~/ 3).clamp(0, modifierIds.length);
  }
}
