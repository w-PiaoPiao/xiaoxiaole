import 'package:flutter/material.dart';

import '../engine/gem.dart';
import '../engine/levels.dart';
import 'gem_art.dart';
import 'palette.dart';

/// 玩法说明面板的内容组件（宝石图例 + 规则段落）。
///
/// 游戏内的暂停菜单和主菜单都会打开它：内容是纯布局，
/// 由调用方决定挂在全屏遮罩还是路由页面上。
class HelpPanel extends StatelessWidget {
  /// 右上角关闭按钮的回调。空时按钮隐藏（依赖调用方的遮罩点击关闭）。
  final VoidCallback? onClose;

  const HelpPanel({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 吞掉面板自身区域的点击：调用方普遍用「点面板外关闭」，而面板本身
      // 是可滚动的——不拦这一下，玩家想停住惯性滚动都会把面板关掉，
      // 与面板底部「点击面板外关闭」的说明正好相反。
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Palette.panelEdge),
        ),
        // 小屏 + 大字体时内容会超过一屏，必须能滚动，否则后面的
        // 玩法说明永远看不到。
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('玩法说明', style: AppText.title.copyWith(fontSize: 18)),
                  const Spacer(),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '关闭',
                      color: Palette.textDim,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      style: IconButton.styleFrom(
                        backgroundColor: Palette.panel.withValues(alpha: 0.9),
                        side: const BorderSide(color: Palette.panelEdge),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final type in GemType.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniGem(type),
                      const SizedBox(width: 12),
                      // 说明文字必须可伸缩：写死宽度在窄屏或大字体下会溢出。
                      Expanded(
                        child: Text(
                          gemEffectLabel(type),
                          style: AppText.label.copyWith(
                            fontSize: 12.5,
                            height: 1.5,
                            color: Palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              ...paragraphs.map(
                (paragraph) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text(
                    '· $paragraph',
                    style: AppText.label.copyWith(fontSize: 11.5, height: 1.7),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  '点击面板外关闭',
                  style: AppText.label.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniGem(GemType type) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(painter: _MiniGemPainter(type)),
    );
  }

  /// 玩法说明的段落。逐条列出以便自动换行——硬编码 `\n` 在窄屏上会折得参差不齐。
  static final List<String> paragraphs = [
    '三连消除；四连生成破空宝石（清除整行或整列），五连生成棱镜（清空全场同色），拐角消除生成爆裂宝石（清除 3x3）。与强化宝石交换可以直接引爆它。',
    '两颗强化宝石换到一起会打出组合技，范围远大于各炸各的：破空+破空＝十字，破空+爆裂＝三行三列，'
        '爆裂+爆裂＝5x5，棱镜+破空＝全场同色铺成整行整列，棱镜+棱镜＝清空全场。',
    '怒气满 ${Campaign.player.maxRage} 后点「斩月」进入瞄准，再点棋盘任意格决定落点：'
        '整行带整列一起清掉。落点选得好不好，差别很大。',
    '每打赢一关可以从三张强化里挑一张，它会一直带到最后一关。暴击、连锁上限、生命上限这些'
        '都只从强化里来——想打得爽就得先攒 build。',
    '注意敌方行动回合，及时用护盾与治疗抵挡；血量低于狂暴线的敌人会变强。迷雾鬼火命中还会夺走怒气。',
    '无尽模式里敌人每波都更强，从第 4 波起还会带上精英词条（护盾再生、吸血、禁疗、狂暴、汲魂）。'
        '卡住时可以点状态条上的灯泡按钮，让系统推荐一步。',
  ];
}

/// 帮助面板里的宝石图标，直接复用棋盘上的宝石美术。
class _MiniGemPainter extends CustomPainter {
  final GemType type;

  const _MiniGemPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    GemArt.paint(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height),
      type,
      SpecialKind.none,
      glow: 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGemPainter oldDelegate) => oldDelegate.type != type;
}
