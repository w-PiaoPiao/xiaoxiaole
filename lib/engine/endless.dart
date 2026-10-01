import 'gem.dart';
import 'levels.dart';

/// 无尽模式：BOSS 按 6 个原型轮换登场，数值与能力随波次单调增强。
///
/// 生成规则是**完全确定**的（同一个波次永远生成同一个 BOSS），没有随机数：
/// 这样平衡报告可以直接推演，测试也可以精确断言某个波次的强度。
///
/// 数值曲线刻意**只由波次决定**：生命按 1.18 的指数、攻击按线性增长，
/// 原型之间不设数值档位。否则轮换回低档原型的那一波会突然变简单，
/// 「越打越强」的承诺就被打破了——原型差异全部体现在机制上
/// （出手节奏、重击、护盾再生、吸血、狂暴、汲魂）。
class EndlessRoster {
  const EndlessRoster._();

  /// 第一波的基准数值。刻意定得比战役第一关略低：无尽模式没有强化铺垫的
  /// 热身，开局就该顺手。
  static const int _baseHp = 2400;

  static const int _baseAttack = 46;

  /// 每波的成长：
  ///  - 生命按指数增长（1.18 倍），玩家的强化是线性的，跑得越远差距越大，
  ///    这是无尽模式「注定会输，看你能站多久」的数学根源；
  ///  - 攻击按线性增长，并被「单次伤害不超过最大生命 65%」封顶保护，
  ///    高波次不会变成一击必杀的抽奖。
  static const double hpGrowth = 1.18;

  static const int attackGrowth = 9;

  /// 精英词条：从第 4 波开始每 3 波多带一条，BOSS 的「能力增强」不止是数字，
  /// 还会拿到战役模式里才能见到的机制（护盾再生、吸血、禁疗、狂暴、汲魂）。
  static const List<String> modifierIds = [
    'aegis', // 坚壁：护盾再生
    'thirst', // 嗜血：吸血
    'choke', // 窒息：禁疗
    'frenzy', // 狂性：残血狂暴
    'siphon', // 汲魂：夺走怒气
  ];

  /// BOSS 的登场顺序：战役六战的原型轮换，同一原型隔 6 波再登场时更强。
  static const List<String> _order = [
    'wisp',
    'guardian',
    'assassin',
    'witch',
    'enchantress',
    'warlord',
  ];

  /// 阶位前缀：名字的变化是玩家能直接读到的成长信号。
  static String _prefix(int wave) {
    if (wave >= 19) return '终焉·';
    if (wave >= 13) return '灾变·';
    if (wave >= 7) return '重铸·';
    return '';
  }

  /// 每个原型的机制形态（数值统一走全局曲线，这里只定义「怎么打」）。
  static EnemyDef _shape(String id) {
    switch (id) {
      case 'wisp':
        return const EnemyDef(
          id: 'wisp',
          name: '迷雾鬼火',
          title: '窃魂的低语',
          taunt: '「把你的怒火……留给我，好吗？」',
          archetype: EnemyArchetype.wisp,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 3,
          themeColor: 0xFF57E0C8,
        );
      case 'guardian':
        return const EnemyDef(
          id: 'guardian',
          name: '石甲守卫',
          title: '沉默的门扉',
          taunt: '「此路不通。」',
          archetype: EnemyArchetype.guardian,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 3,
          heavyEvery: 3,
          themeColor: 0xFFE0A94A,
        );
      case 'assassin':
        return const EnemyDef(
          id: 'assassin',
          name: '影刃刺客',
          title: '无声的追猎者',
          taunt: '「你眨眼的功夫，就够了。」',
          archetype: EnemyArchetype.assassin,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 2,
          heavyEvery: 3,
          heavyMultiplier: 2.0,
          themeColor: 0xFF9B7BE8,
        );
      case 'witch':
        return const EnemyDef(
          id: 'witch',
          name: '血月巫女',
          title: '织咒之人',
          taunt: '「你的伤口，不会再愈合了。」',
          archetype: EnemyArchetype.witch,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 3,
          shieldRegen: 20,
          themeColor: 0xFFE85A7A,
        );
      case 'enchantress':
        return const EnemyDef(
          id: 'enchantress',
          name: '深渊魔女',
          title: '契约的持有者',
          taunt: '「把心交给我，我就不疼了。」',
          archetype: EnemyArchetype.enchantress,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 3,
          heavyEvery: 3,
          shieldRegen: 30,
          themeColor: 0xFFFF4D6D,
        );
      case 'warlord':
      default:
        return const EnemyDef(
          id: 'warlord',
          name: '终焉之影',
          title: '吞噬一切的黑',
          taunt: '「你打赢的一切，都会成为我的一部分。」',
          archetype: EnemyArchetype.warlord,
          maxHp: _baseHp,
          attack: _baseAttack,
          turnsPerAttack: 2,
          heavyEvery: 3,
          heavyMultiplier: 1.7,
          shieldRegen: 20,
          themeColor: 0xFFB44BFF,
        );
    }
  }

  /// 生成第 [wave] 波（从 1 开始）的 BOSS。
  static EnemyDef enemyFor(int wave) {
    assert(wave >= 1);
    final shape = _shape(_order[(wave - 1) % _order.length]);
    final def = EnemyDef(
      id: shape.id,
      name: '${_prefix(wave)}${shape.name}',
      title: shape.title,
      taunt: shape.taunt,
      archetype: shape.archetype,
      maxHp: (_baseHp * _hpScale(wave - 1)).round(),
      attack: _baseAttack + attackGrowth * (wave - 1),
      turnsPerAttack: shape.turnsPerAttack,
      heavyEvery: shape.heavyEvery,
      heavyMultiplier: shape.heavyMultiplier,
      shieldRegen: shape.shieldRegen,
      themeColor: shape.themeColor,
    );

    // 精英词条按波次逐条叠上。词条是依次取用的（不随机），所以高波次的
    // BOSS 会同时带着多条机制，威胁是「台阶式」上升的。
    final count = modifierCount(wave);
    if (count == 0) return def;

    var shieldRegen = def.shieldRegen;
    var drain = 0.0;
    var healBlock = 0;
    var enrage = 0.0;
    var rageDrain = 0;
    for (var i = 0; i < count; i++) {
      switch (modifierIds[i % modifierIds.length]) {
        case 'aegis':
          shieldRegen += 24;
        case 'thirst':
          drain += 0.08;
        case 'choke':
          healBlock += 2;
        case 'frenzy':
          enrage = enrage > 0 ? enrage : 0.45;
        case 'siphon':
          rageDrain += 12;
      }
    }
    return EnemyDef(
      id: def.id,
      name: def.name,
      title: def.title,
      taunt: def.taunt,
      archetype: def.archetype,
      maxHp: def.maxHp,
      attack: def.attack,
      turnsPerAttack: def.turnsPerAttack,
      heavyEvery: def.heavyEvery,
      heavyMultiplier: def.heavyMultiplier,
      shieldRegen: shieldRegen,
      drainRatio: drain,
      healBlockTurns: healBlock,
      enrageAt: enrage,
      rageDrain: rageDrain,
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
