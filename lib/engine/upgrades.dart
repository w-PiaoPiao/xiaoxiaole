import 'dart:math' as math;

import 'levels.dart';

/// 强化卡片的图标。
///
/// 前五个直接复用宝石图标——玩家在一局里已经把它们和「伤害 / 护盾 / 治疗 /
/// 怒气 / 易伤」绑在一起了，强化卡再学一套符号纯属浪费。剩下几个是宝石之外
/// 的新概念（连锁、暴击、逆境、必杀），才需要自己的形状。
enum UpgradeIcon {
  /// 交叉双剑 · 与烈焰宝石同源。
  sword,

  /// 盾牌 · 与寒霜宝石同源。
  shield,

  /// 十字 · 与生机宝石同源。
  cross,

  /// 闪电 · 与雷霆宝石同源。
  bolt,

  /// 骷髅 · 与诅咒宝石同源。
  skull,

  /// 星爆 · 爆发式的一次性增强。
  burst,

  /// 连环箭头 · 连锁相关。
  chain,

  /// 心 · 持续回复。
  heart,

  /// 月牙 · 必杀「斩月」。
  moon,
}

/// 一条可选的强化。
///
/// 强化是**纯数据 + 一个纯函数**：`apply` 把当前档案换算成新的档案，不改任何
/// 全局状态。因此三选一的候选、已选列表都可以脱离 UI 单独测试。
class Upgrade {
  final String id;
  final String name;

  /// 一句话说明它加什么，直接印在卡片上。
  final String desc;

  final UpgradeIcon icon;

  /// 卡片配色（0xAARRGGBB）。与 `EnemyDef.themeColor` 用同一种写法，
  /// 这样引擎层依然不依赖 Flutter。
  final int themeColor;

  /// 最多可以叠几次。
  final int maxStacks;

  /// 抽取权重，越大越常出现。
  final int weight;

  final PlayerProfile Function(PlayerProfile profile) apply;

  /// 出现的前置条件（例如「暴击倍率」要先有暴击率才有意义）。
  final bool Function(PlayerProfile profile)? available;

  const Upgrade({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.themeColor,
    required this.apply,
    this.maxStacks = 5,
    this.weight = 8,
    this.available,
  });
}

/// 全部强化与「打完一关发三张牌」的抽取逻辑。
class UpgradePool {
  const UpgradePool._();

  static final List<Upgrade> all = [
    Upgrade(
      id: 'blade',
      name: '烈焰精通',
      desc: '红宝石伤害 +7',
      icon: UpgradeIcon.sword,
      themeColor: 0xFFE8445C,
      maxStacks: 6,
      weight: 10,
      apply: (p) => p.copyWith(redDamage: p.redDamage + 7),
    ),
    Upgrade(
      id: 'crit',
      name: '锐锋',
      desc: '暴击率 +8%',
      icon: UpgradeIcon.sword,
      themeColor: 0xFFFF8A5C,
      maxStacks: 6,
      weight: 9,
      apply: (p) => p.copyWith(critChance: (p.critChance + 0.08).clamp(0.0, 0.8)),
    ),
    Upgrade(
      id: 'critDamage',
      name: '致命一击',
      desc: '暴击伤害倍率 +0.6',
      icon: UpgradeIcon.burst,
      themeColor: 0xFFFF4D6D,
      maxStacks: 4,
      weight: 7,
      // 没有暴击率的时候这张牌等于空过，不该出现在候选里。
      available: (p) => p.critChance > 0,
      apply: (p) => p.copyWith(critMultiplier: p.critMultiplier + 0.6),
    ),
    Upgrade(
      id: 'special',
      name: '破军',
      desc: '强化宝石伤害 +45%',
      icon: UpgradeIcon.burst,
      themeColor: 0xFFE0A94A,
      maxStacks: 4,
      weight: 7,
      apply: (p) => p.copyWith(specialPower: p.specialPower + 0.45),
    ),
    Upgrade(
      id: 'combo',
      name: '无尽连击',
      desc: '连锁倍率上限 +0.4',
      icon: UpgradeIcon.chain,
      themeColor: 0xFFFFC978,
      maxStacks: 3,
      weight: 6,
      apply: (p) => p.copyWith(comboCap: p.comboCap + 0.4),
    ),
    Upgrade(
      id: 'guard',
      name: '铁壁',
      desc: '蓝宝石护盾 +6，护盾上限 +50',
      icon: UpgradeIcon.shield,
      themeColor: 0xFF3FA8E8,
      maxStacks: 6,
      weight: 9,
      apply: (p) => p.copyWith(
        blueShield: p.blueShield + 6,
        maxShield: p.maxShield + 50,
      ),
    ),
    Upgrade(
      id: 'harden',
      name: '硬化',
      desc: '受到的伤害 -8%',
      icon: UpgradeIcon.shield,
      themeColor: 0xFF5FC8FF,
      maxStacks: 4,
      weight: 6,
      available: (p) => p.damageReduction < PlayerProfile.maxDamageReduction - 0.001,
      apply: (p) => p.copyWith(
        damageReduction: (p.damageReduction + 0.08)
            .clamp(0.0, PlayerProfile.maxDamageReduction),
      ),
    ),
    Upgrade(
      id: 'vitality',
      name: '生命洪流',
      desc: '生命上限 +40（当场补满）',
      icon: UpgradeIcon.cross,
      themeColor: 0xFF7CE0B0,
      maxStacks: 4,
      weight: 7,
      apply: (p) => p.copyWith(maxHp: p.maxHp + 40),
    ),
    Upgrade(
      id: 'heal',
      name: '生命之泉',
      desc: '绿宝石治疗 +9',
      icon: UpgradeIcon.cross,
      themeColor: 0xFF33C071,
      maxStacks: 5,
      weight: 9,
      apply: (p) => p.copyWith(greenHeal: p.greenHeal + 9),
    ),
    Upgrade(
      id: 'regen',
      name: '回春',
      desc: '每回合开始回复 6 点生命',
      icon: UpgradeIcon.heart,
      themeColor: 0xFF54E39A,
      maxStacks: 5,
      weight: 8,
      apply: (p) => p.copyWith(regenPerTurn: p.regenPerTurn + 6),
    ),
    Upgrade(
      id: 'rage',
      name: '蓄能',
      desc: '黄宝石怒气 +4',
      icon: UpgradeIcon.bolt,
      themeColor: 0xFFF0B01F,
      maxStacks: 5,
      weight: 8,
      apply: (p) => p.copyWith(yellowRage: p.yellowRage + 4),
    ),
    Upgrade(
      id: 'ultimate',
      name: '斩月·极',
      desc: '必杀额外伤害 +90，结算倍率 +0.1',
      icon: UpgradeIcon.moon,
      themeColor: 0xFFFFD34D,
      maxStacks: 4,
      weight: 7,
      apply: (p) => p.copyWith(
        ultimateBonusDamage: p.ultimateBonusDamage + 90,
        ultimateMultiplier: p.ultimateMultiplier + 0.1,
      ),
    ),
    Upgrade(
      id: 'curse',
      name: '深咒',
      desc: '每层易伤加成 +4%',
      icon: UpgradeIcon.skull,
      themeColor: 0xFF9E5CE8,
      maxStacks: 5,
      weight: 8,
      apply: (p) => p.copyWith(curseBonus: p.curseBonus + 0.04),
    ),
    Upgrade(
      id: 'desperate',
      name: '狂骨',
      desc: '生命低于 40% 时伤害 +30%',
      icon: UpgradeIcon.burst,
      themeColor: 0xFFFF3B5C,
      maxStacks: 3,
      weight: 5,
      apply: (p) => p.copyWith(desperateBonus: p.desperateBonus + 0.30),
    ),
  ];

  static Upgrade? byId(String id) {
    for (final u in all) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// 把「已获得的强化」换算成当前生效的档案。
  static PlayerProfile profileFor(Map<String, int> taken) {
    var profile = Campaign.player;
    taken.forEach((id, stacks) {
      final upgrade = byId(id);
      if (upgrade == null) return;
      for (var i = 0; i < stacks; i++) {
        profile = upgrade.apply(profile);
      }
    });
    return profile;
  }

  /// 抽 [count] 张候选牌：按权重随机、不重复，并过滤掉已经叠满或前置不满足的。
  static List<Upgrade> roll({
    required PlayerProfile profile,
    required Map<String, int> taken,
    required math.Random rng,
    int count = 3,
  }) {
    final candidates = <Upgrade>[
      for (final u in all)
        if ((taken[u.id] ?? 0) < u.maxStacks && (u.available?.call(profile) ?? true)) u,
    ];
    final picked = <Upgrade>[];
    while (picked.length < count && candidates.isNotEmpty) {
      final total = candidates.fold<int>(0, (sum, u) => sum + u.weight);
      var ticket = rng.nextInt(total < 1 ? 1 : total);
      var chosen = candidates.length - 1;
      for (var i = 0; i < candidates.length; i++) {
        ticket -= candidates[i].weight;
        if (ticket < 0) {
          chosen = i;
          break;
        }
      }
      picked.add(candidates.removeAt(chosen));
    }
    return picked;
  }
}
