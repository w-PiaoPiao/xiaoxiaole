import 'dart:math' as math;

import 'levels.dart';
import 'roguelike.dart';

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

  /// 水滴 · 溢流护盾：把溢出来的治疗结成护盾。
  droplet,

  /// 荆棘 · 荆棘壁垒：被护盾扛下的伤害扎回去。
  thorn,

  /// 齿轮 · 过载引擎：把溢出的怒气烧成伤害。
  gear,

  /// 三叉 · 棱镜宗师：一次清掉更多颜色。
  trident,

  /// 十字准星 · 十字破空：整行与整列一起清。
  crosshair,

  /// 血滴 · 血契：以血换力。
  blood,
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

  /// 稀有度。只影响抽取概率与卡片外观——效果强弱由条目自己的数值决定。
  /// 战役模式不启用分层（见 [UpgradePool.roll]）。
  final UpgradeRarity rarity;

  /// 是否"有代价"：卡片会额外标一行提醒玩家这条牌不是白拿的。
  final bool isCostly;

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
    this.rarity = UpgradeRarity.common,
    this.isCostly = false,
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
      apply: (p) =>
          p.copyWith(critChance: (p.critChance + 0.08).clamp(0.0, 0.8)),
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
      apply: (p) =>
          p.copyWith(blueShield: p.blueShield + 6, maxShield: p.maxShield + 50),
    ),
    Upgrade(
      id: 'harden',
      name: '硬化',
      desc: '受到的伤害 -8%',
      icon: UpgradeIcon.shield,
      themeColor: 0xFF5FC8FF,
      maxStacks: 4,
      weight: 6,
      available: (p) =>
          p.damageReduction < PlayerProfile.maxDamageReduction - 0.001,
      apply: (p) => p.copyWith(
        damageReduction: (p.damageReduction + 0.08).clamp(
          0.0,
          PlayerProfile.maxDamageReduction,
        ),
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
      desc: '黄宝石怒气 +2',
      icon: UpgradeIcon.bolt,
      themeColor: 0xFFF0B01F,
      maxStacks: 5,
      weight: 8,
      // +2 而不是 +4：怒气的基数是每颗 4 点，+4 等于单层就把必杀频率
      // 翻一倍——池子里唯一一条单层收益 +100% 的牌，而且它抢的是「必杀
      // 是攒出来的大招」这条节奏底线（见 PlayerProfile.yellowRage 的注释）。
      // +2 与「铁壁」的 +6/13 同档（+50%/层），满层 3.5 倍。
      apply: (p) => p.copyWith(yellowRage: p.yellowRage + 2),
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

    // ================================================== 肉鸽层（无尽模式）
    //
    // 下面这一批不再堆数字，而是**改规则**：把两种宝石接起来、让棋盘行为
    // 变形、或者用明确的代价换一份夸张的收益。它们只在无尽模式出现
    // （见 [UpgradePool.roll] 的 roguelike 开关），并且大多需要先有对应的
    // build 铺垫才有资格被抽到——这让每一局的成长方向在中期就分岔了。

    // ------------------------------------------------------ 稀有 · 生存型
    // 多管血 BOSS 逐击变凶之后，"活下去"本身成了一条独立的成长路线：
    // 这两张牌不和输出抢位置，专门把身板垫厚——总血量与总护盾是唯二
    // 每次受击都要先挡在玩家前面的东西。
    Upgrade(
      id: 'mountainHeart',
      name: '山岳之躯',
      desc: '生命上限 +110（当场补满）',
      icon: UpgradeIcon.heart,
      themeColor: 0xFF7CE0B0,
      rarity: UpgradeRarity.rare,
      maxStacks: 2,
      weight: 8,
      apply: (p) => p.copyWith(maxHp: p.maxHp + 110),
    ),
    Upgrade(
      id: 'aegisWall',
      name: '圣盾壁垒',
      desc: '护盾上限 +140，蓝宝石护盾 +4',
      icon: UpgradeIcon.shield,
      themeColor: 0xFF3FA8E8,
      rarity: UpgradeRarity.rare,
      maxStacks: 2,
      weight: 8,
      apply: (p) => p.copyWith(
        maxShield: p.maxShield + 140,
        blueShield: p.blueShield + 4,
      ),
    ),

    // ------------------------------------------------------ 稀有 · 联动型
    Upgrade(
      id: 'overcrit',
      name: '过量暴击',
      desc: '暴击伤害的 50% 一并结成护盾',
      icon: UpgradeIcon.burst,
      themeColor: 0xFFFF8A5C,
      rarity: UpgradeRarity.rare,
      maxStacks: 2,
      weight: 7,
      // 没有暴击率的时候这张牌等于空过。
      available: (p) => p.critChance >= 0.16,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          critToShield: (p.effects.critToShield + 0.5).clamp(0.0, 1.0),
        ),
      ),
    ),
    Upgrade(
      id: 'overflowGuard',
      name: '溢流护盾',
      desc: '治疗溢出上限的部分转为护盾',
      icon: UpgradeIcon.droplet,
      themeColor: 0xFF7CE0B0,
      rarity: UpgradeRarity.rare,
      maxStacks: 2,
      weight: 7,
      available: (p) => p.greenHeal >= 30,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          healOverflowToShield: (p.effects.healOverflowToShield + 0.5).clamp(
            0.0,
            1.0,
          ),
        ),
      ),
    ),
    Upgrade(
      id: 'thornGuard',
      name: '荆棘壁垒',
      desc: '护盾扛下的伤害 30% 反弹给敌人',
      icon: UpgradeIcon.thorn,
      themeColor: 0xFF5FC8FF,
      rarity: UpgradeRarity.rare,
      // 两层封顶：反弹到 60% 就到头了——再高就是"挨打即反击"的永动机，
      // 生存流会无脑躺赢。
      maxStacks: 2,
      weight: 7,
      available: (p) => p.maxShield >= 300,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          shieldReflect: (p.effects.shieldReflect + 0.30).clamp(0.0, 0.6),
        ),
      ),
    ),
    Upgrade(
      id: 'rageEngine',
      name: '过载引擎',
      desc: '溢出的怒气转为伤害（每点 +3）',
      icon: UpgradeIcon.gear,
      themeColor: 0xFFF0B01F,
      rarity: UpgradeRarity.rare,
      maxStacks: 2,
      weight: 7,
      // 门槛 10 = 基础 4 + 三层「蓄能」：yellowRage 的全部来源就这两处
      // （上限 14），这张牌只在玩家真的把怒气机制铺起来之后才有意义。
      // 曾经的门槛 17 是 yellowRage=9 时代定的（9+10=19 可达），削到 4
      // 之后没跟着改，结果成了永远抽不到的死牌——改门槛前先核对这条
      // 前置链，测试里有可达性元测试守着。
      available: (p) => p.yellowRage >= 10,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          rageOverflowDamage: (p.effects.rageOverflowDamage + 3).clamp(0.0, 6),
        ),
      ),
    ),
    Upgrade(
      id: 'executioner',
      name: '处决者',
      desc: '敌人生命低于 35% 时，红宝石伤害 +60%',
      icon: UpgradeIcon.crosshair,
      themeColor: 0xFFFF6B4D,
      rarity: UpgradeRarity.rare,
      // 不给叠层：两层就把斩杀期变成 2.2 倍，残血反打的设计初衷会变成
      // "谁先摸到残血谁赢"的单边碾压。
      maxStacks: 1,
      weight: 7,
      // 需要红宝石伤害的铺垫，否则这张牌只是给一条本来就打不动的线锦上添花。
      available: (p) => p.redDamage >= 40,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(executeThreshold: 0.35, executeBonus: 0.6),
      ),
    ),

    // -------------------------------------------------- 稀有 · 棋盘质变
    Upgrade(
      id: 'prismMaster',
      name: '棱镜宗师',
      desc: '棱镜额外清除一种颜色',
      icon: UpgradeIcon.trident,
      themeColor: 0xFFC08CFF,
      rarity: UpgradeRarity.rare,
      maxStacks: 1,
      weight: 6,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          boardRules: p.effects.boardRules.copyWith(
            prismExtraColors: p.effects.boardRules.prismExtraColors + 1,
          ),
        ),
      ),
    ),
    Upgrade(
      id: 'demolition',
      name: '爆破工程',
      desc: '爆裂宝石范围扩大到 5x5',
      icon: UpgradeIcon.burst,
      themeColor: 0xFFFF9A4D,
      rarity: UpgradeRarity.rare,
      maxStacks: 1,
      weight: 6,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          boardRules: p.effects.boardRules.copyWith(
            burstRadius: p.effects.boardRules.burstRadius + 1,
          ),
        ),
      ),
    ),
    Upgrade(
      id: 'crossStrike',
      name: '十字破空',
      desc: '破空宝石同时清除整行与整列',
      icon: UpgradeIcon.crosshair,
      themeColor: 0xFFFFD34D,
      rarity: UpgradeRarity.rare,
      maxStacks: 1,
      weight: 6,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          boardRules: p.effects.boardRules.copyWith(lineBecomesCross: true),
        ),
      ),
    ),

    // -------------------------------------------------- 稀有 · 代价型
    Upgrade(
      id: 'bloodPact',
      name: '血契',
      desc: '全部伤害 +50% · 每回合自损 5 点生命',
      icon: UpgradeIcon.blood,
      themeColor: 0xFFFF3B5C,
      rarity: UpgradeRarity.rare,
      // 不给叠层：+100% 伤害配 -10 血/回合会把"高张力"变成纯粹的死亡倒计时。
      maxStacks: 1,
      weight: 8,
      isCostly: true,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          damageMul: p.effects.damageMul + 0.5,
          selfDamagePerTurn: p.effects.selfDamagePerTurn + 5,
        ),
      ),
    ),
    Upgrade(
      id: 'ascetic',
      name: '苦修',
      desc: '红宝石伤害 +90%、暴击率 +10% · 无法获得护盾',
      icon: UpgradeIcon.skull,
      themeColor: 0xFF9C8FC4,
      rarity: UpgradeRarity.rare,
      maxStacks: 1,
      weight: 7,
      isCostly: true,
      // 只递给已经投入护盾流的玩家：对没有护盾的人，"无法获得护盾"毫无
      // 代价，+90% 红伤就成了白给的输出。基础档案 maxShield=250，
      // 超过它才说明真的拿过盾牌。
      available: (p) => p.maxShield > 250,
      apply: (p) => p.copyWith(
        redDamage: (p.redDamage * 1.9).round(),
        critChance: (p.critChance + 0.10).clamp(0.0, 0.8),
        effects: p.effects.copyWith(shieldGainMul: 0),
      ),
    ),

    // ------------------------------------------------------------ 传说
    Upgrade(
      id: 'plague',
      name: '瘟疫',
      desc: '易伤每回合只掉一层 · 每层使强化宝石伤害 +18%',
      icon: UpgradeIcon.skull,
      themeColor: 0xFF9E5CE8,
      rarity: UpgradeRarity.legendary,
      maxStacks: 1,
      weight: 6,
      available: (p) => p.curseBonus >= 0.20,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          cursePersists: true,
          curseToSpecialPower: p.effects.curseToSpecialPower + 0.18,
        ),
      ),
    ),
    Upgrade(
      id: 'eternalCombo',
      name: '永动连锁',
      desc: '连锁倍率上限提升到 5.0，起步倍率 +0.15',
      icon: UpgradeIcon.chain,
      themeColor: 0xFFFFC978,
      rarity: UpgradeRarity.legendary,
      maxStacks: 1,
      weight: 6,
      available: (p) => p.comboCap >= 3.3,
      apply: (p) => p.copyWith(
        comboCap: 5.0,
        effects: p.effects.copyWith(
          comboBaseBonus: p.effects.comboBaseBonus + 0.15,
        ),
      ),
    ),
    Upgrade(
      id: 'moonBlessing',
      name: '月华',
      desc: '必杀消耗 -40% · 每回合自动 +12 怒气',
      icon: UpgradeIcon.moon,
      themeColor: 0xFFFFD34D,
      rarity: UpgradeRarity.legendary,
      maxStacks: 1,
      weight: 6,
      available: (p) => p.ultimateBonusDamage >= 240,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(
          ultimateCostMul: 0.6,
          ragePerTurn: p.effects.ragePerTurn + 12,
        ),
      ),
    ),
    Upgrade(
      id: 'unbroken',
      name: '不屈',
      desc: '单次受到的伤害不超过最大生命的 40%（僵持惩罚可以突破）',
      icon: UpgradeIcon.cross,
      themeColor: 0xFF5FC8FF,
      rarity: UpgradeRarity.legendary,
      maxStacks: 1,
      weight: 6,
      // 这是"不被一刀秒"的直接解：默认封顶是 65%（两击致死），压到 40%
      // 之后至少能挨三下。要求先有一点生存投入——没有任何身板时它救不了
      // 你，40% 照样打得动；它是一条生存路线的质变，不是通用的免死金牌。
      available: (p) =>
          p.maxHp >= 340 || p.maxShield >= 300 || p.damageReduction > 0.05,
      apply: (p) => p.copyWith(
        effects: p.effects.copyWith(hitCapRatio: 0.4),
      ),
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
  ///
  /// [depth] 是当前进度（无尽模式传波次 - 1）。它只影响**稀有度的权重**：
  /// 走得越深，稀有与传说越容易露面。这是肉鸽的节奏——前期用普通牌铺底，
  /// 后期让质变牌把 build 推向夸张的高度。
  ///
  /// [roguelike] 打开后才启用肉鸽层：稀有度分层、保底，以及全部非普通牌。
  /// 战役默认关闭（十三关共 12 次选择，次数上已经够分层展开）——是否
  /// 把肉鸽层开放给战役是独立的数值决策，动它之前先跑
  /// `tool/balance_report.dart` 对比三流通关率，别只看"次数够了"。
  static List<Upgrade> roll({
    required PlayerProfile profile,
    required Map<String, int> taken,
    required math.Random rng,
    int count = 3,
    int depth = 0,
    bool roguelike = false,
  }) {
    final candidates = <Upgrade>[
      for (final u in all)
        if ((taken[u.id] ?? 0) < u.maxStacks &&
            (u.available?.call(profile) ?? true) &&
            (roguelike || u.rarity == UpgradeRarity.common))
          u,
    ];
    if (candidates.isEmpty) return const [];

    final picked = <Upgrade>[];
    while (picked.length < count && candidates.isNotEmpty) {
      final total = candidates.fold<int>(
        0,
        (sum, u) => sum + _weightOf(u, depth, roguelike),
      );
      var ticket = rng.nextInt(total < 1 ? 1 : total);
      var chosen = candidates.length - 1;
      for (var i = 0; i < candidates.length; i++) {
        ticket -= _weightOf(candidates[i], depth, roguelike);
        if (ticket < 0) {
          chosen = i;
          break;
        }
      }
      picked.add(candidates.removeAt(chosen));
    }

    // 保底：走得够深时，每 3 波（第 3、6、9……波）至少要有一张稀有以上。
    // 没有这条规则，运气差的玩家可能连着几波都摸不到任何质变，
    // "越打越有花样"的承诺就断了。
    final guaranteedWave = roguelike && depth >= 2 && (depth + 1) % 3 == 0;
    if (guaranteedWave &&
        picked.length == count &&
        picked.every((u) => u.rarity == UpgradeRarity.common)) {
      // 稀有池抽空（全叠满）时退到传说——"稀有以上"的承诺不能因为
      // 某一边抽空就落空，只要池里还剩任何质变牌就该发出来。
      final fallback =
          _pickByRarity(candidates, UpgradeRarity.rare, rng) ??
          _pickByRarity(candidates, UpgradeRarity.legendary, rng);
      if (fallback != null) picked[picked.length - 1] = fallback;
    }
    return picked;
  }

  /// 单条强化的实际抽取权重。
  ///
  /// 战役（[roguelike] 为 false）就是它自己的权重，与改造前逐字一致；
  /// 无尽模式按稀有度加成，加成随 [depth] 增长到封顶。普通牌也乘一个基数，
  /// 否则"稀有度加成"会把权重尺度拉乱，稀有反而比普通还常见。
  static int _weightOf(Upgrade u, int depth, bool roguelike) {
    if (!roguelike) return u.weight;
    final d = depth < 0 ? 0 : depth;
    return switch (u.rarity) {
      UpgradeRarity.common => u.weight * 10,
      UpgradeRarity.rare => u.weight * (6 + math.min(d, 20) * 8 ~/ 5),
      UpgradeRarity.legendary => u.weight * (3 + math.min(d, 24) * 3 ~/ 2),
    };
  }

  /// 从候选里按权重挑一张指定稀有度的牌；没有就返回 null。
  static Upgrade? _pickByRarity(
    List<Upgrade> pool,
    UpgradeRarity rarity,
    math.Random rng,
  ) {
    final matches = [
      for (final u in pool)
        if (u.rarity == rarity) u,
    ];
    if (matches.isEmpty) return null;
    final total = matches.fold<int>(0, (sum, u) => sum + u.weight);
    var ticket = rng.nextInt(total < 1 ? 1 : total);
    for (final u in matches) {
      ticket -= u.weight;
      if (ticket < 0) return u;
    }
    return matches.last;
  }
}
