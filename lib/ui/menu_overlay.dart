import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../engine/levels.dart';
import '../engine/upgrades.dart';
import 'controls.dart';
import 'palette.dart';
import 'upgrade_art.dart';

/// 暂停菜单：进度概览、关卡选择（战役）、设置开关与常用操作。
///
/// 游戏本身没有实时压力（敌人按回合出手而不是按秒），所以"暂停"在这里
/// 等价于"打开菜单时输入被屏蔽"——棋盘与战斗都停在原地。
class MenuOverlay extends StatelessWidget {
  final AppSettings settings;
  final int currentLevel;
  final VoidCallback onResume;
  final void Function(int index) onSelectLevel;
  final VoidCallback onRestartLevel;
  final VoidCallback onHelp;

  /// 本局已经吃到的强化（id → 层数）。空表示还没开始成长。
  final Map<String, int> taken;

  /// 是否显示「选择关卡」：无尽模式没有关卡概念，隐藏这一块。
  final bool showLevelSelect;

  /// 当前模式的说明文字（如「战役」「无尽 · 第 7 波」），显示在标题旁。
  final String modeLabel;

  /// 清空全部强化、从头开始。
  final VoidCallback onNewRun;

  /// 上面那个按钮的文案。战役说「回到第一关」，无尽说「从第 1 波重来」——
  /// 无尽模式没有"关"，这句话交给调用方决定。
  final String restartLabel;

  /// 「重开当前进度」按钮的文案。战役说「重开本关」，无尽说「重开本波」。
  final String restartLevelLabel;

  /// 回到主菜单。空则不显示该按钮（预览 / 测试场景）。
  final VoidCallback? onExitToMenu;

  const MenuOverlay({
    super.key,
    required this.settings,
    required this.currentLevel,
    required this.onResume,
    required this.onSelectLevel,
    required this.onRestartLevel,
    required this.onHelp,
    required this.onNewRun,
    this.taken = const {},
    this.showLevelSelect = true,
    this.modeLabel = '战役',
    this.restartLabel = '重开一局',
    this.restartLevelLabel = '重开本关',
    this.onExitToMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // 点击面板外部继续游戏。
        onTap: onResume,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 32,
                ),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: Palette.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Palette.panelEdge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '暂停',
                            style: AppText.title.copyWith(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            modeLabel,
                            style: AppText.label.copyWith(
                              fontSize: 11,
                              color: Palette.gold.withValues(alpha: 0.85),
                            ),
                          ),
                          const Spacer(),
                          PanelCloseButton(onTap: onResume),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (taken.isNotEmpty) ...[
                        const Text('本局强化', style: AppText.label),
                        const SizedBox(height: 8),
                        _buildList(),
                        const SizedBox(height: 20),
                      ],
                      if (showLevelSelect) ...[
                        const Text('选择关卡', style: AppText.label),
                        const SizedBox(height: 8),
                        _levelGrid(),
                        const SizedBox(height: 20),
                      ],
                      const Text('设置', style: AppText.label),
                      const SizedBox(height: 6),
                      SettingsToggle(
                        label: '音效',
                        value: settings.sound,
                        onChanged: settings.setSound,
                      ),
                      SettingsToggle(
                        label: '震动反馈',
                        value: settings.haptics,
                        onChanged: settings.setHaptics,
                      ),
                      SettingsToggle(
                        label: '屏幕震动特效',
                        value: settings.screenShake,
                        onChanged: settings.setScreenShake,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: MenuButton(
                              label: '继续游戏',
                              primary: true,
                              onTap: onResume,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: MenuButton(
                              label: restartLevelLabel,
                              onTap: onRestartLevel,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MenuButton(label: '玩法说明', onTap: onHelp),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: MenuButton(
                              label: restartLabel,
                              onTap: onNewRun,
                            ),
                          ),
                          if (onExitToMenu != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: MenuButton(
                                label: '回到主菜单',
                                onTap: onExitToMenu!,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 本局强化清单：每一条都带着它自己的图标与层数。
  ///
  /// 这是玩家唯一能完整回顾 build 的地方——一眼扫过去就知道这一局走的是
  /// 暴击流还是护盾流。
  Widget _buildList() {
    final entries = taken.entries.toList()
      ..sort((a, b) {
        final ua = UpgradePool.byId(a.key);
        final ub = UpgradePool.byId(b.key);
        return (ua?.name ?? a.key).compareTo(ub?.name ?? b.key);
      });
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          if (UpgradePool.byId(entry.key) case final upgrade?)
            _UpgradeChip(upgrade: upgrade, stacks: entry.value),
      ],
    );
  }

  Widget _levelGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < Campaign.levels.length; i++)
          _LevelChip(
            index: i,
            name: Campaign.levels[i].name,
            stars: settings.starsOf(i),
            bestTurns: settings.turnsOf(i),
            unlocked: settings.isUnlocked(i),
            current: i == currentLevel,
            onTap: settings.isUnlocked(i) ? () => onSelectLevel(i) : null,
          ),
      ],
    );
  }
}

/// 强化清单里的一格：图标 + 名字 + 层数。
class _UpgradeChip extends StatelessWidget {
  final Upgrade upgrade;
  final int stacks;

  const _UpgradeChip({required this.upgrade, required this.stacks});

  @override
  Widget build(BuildContext context) {
    final color = Color(upgrade.themeColor);
    return Semantics(
      label: '${upgrade.name}，${upgrade.desc}${stacks > 1 ? '，$stacks 层' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 11, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CustomPaint(
                painter: _ChipGlyphPainter(upgrade.icon, color),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              upgrade.name,
              style: const TextStyle(
                color: Palette.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'x$stacks',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipGlyphPainter extends CustomPainter {
  final UpgradeIcon icon;
  final Color color;

  const _ChipGlyphPainter(this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    UpgradeArt.paint(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height),
      icon,
      color,
    );
  }

  @override
  bool shouldRepaint(covariant _ChipGlyphPainter old) =>
      old.icon != icon || old.color != color;
}

/// 星级文字：实心与空心的三格。
String _starsText(int stars) {
  final filled = List.filled(stars.clamp(0, 3), '★').join();
  final empty = List.filled((3 - stars).clamp(0, 3), '☆').join();
  return '$filled$empty';
}

/// 关卡入口：显示关卡序号与已获得的最佳星级；未解锁的置灰。
class _LevelChip extends StatelessWidget {
  final int index;
  final String name;
  final int stars;
  final int bestTurns;
  final bool unlocked;
  final bool current;
  final VoidCallback? onTap;

  const _LevelChip({
    required this.index,
    required this.name,
    required this.stars,
    required this.bestTurns,
    required this.unlocked,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = current ? Palette.gold : Palette.panelEdge;
    final label = unlocked
        ? '第${index + 1}关 ${_starsText(stars)}'
        : '第${index + 1}关 未解锁';
    final hint = unlocked && bestTurns > 0 ? '$name，最少 $bestTurns 回合' : name;
    return Semantics(
      button: true,
      enabled: unlocked,
      label: '$label，$hint',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.42,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: current
                  ? Palette.gold.withValues(alpha: 0.14)
                  : Palette.slotFill.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: accent, width: current ? 1.4 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第${index + 1}关',
                  style: AppText.number.copyWith(
                    fontSize: 12,
                    color: unlocked ? Palette.textPrimary : Palette.textDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked ? _starsText(stars) : '未解锁',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: stars > 0 ? Palette.gold : Palette.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
