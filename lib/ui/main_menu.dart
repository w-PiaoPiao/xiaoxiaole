import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../engine/gem.dart';
import '../engine/levels.dart';
import 'controls.dart';
import 'help_panel.dart';
import 'palette.dart';
import 'game_screen.dart';
import 'gem_art.dart';
import 'sfx.dart';

/// 打开界面（主菜单）：选模式、继续上一局、设置与玩法说明。
///
/// 应用启动的第一个页面。从这里进入 [GameScreen] 的战役或无尽模式；
/// 游戏内随时可以「回到主菜单」，进行中的一局会被存进
/// [AppSettings.saveResume]，主菜单的「继续游戏」就能接着打。
class MainMenuScreen extends StatefulWidget {
  final AppSettings settings;
  final SfxController sfx;

  const MainMenuScreen({super.key, required this.settings, required this.sfx});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  bool _showSettings = false;
  bool _showHelp = false;
  bool _confirmReset = false;

  @override
  void initState() {
    super.initState();
    // 存档变化（清空进度、回到主菜单写入的新存档）都会刷新按钮状态。
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _enter(BuildContext context, GameScreen screen) {
    widget.sfx.spawnSpecial();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final resume = settings.resume;
    return Scaffold(
      backgroundColor: Palette.bgDeep,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tight = constraints.maxWidth < 380;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: tight ? 26 : 40,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _TitleBlock(),
                          SizedBox(height: tight ? 26 : 40),
                          if (resume != null)
                            _MenuTile(
                              label: '继续游戏',
                              sub: resume.mode == GameMode.campaign
                                  ? '战役 · ${_levelLabel(resume.level)}'
                                  : '无尽 · 第 ${resume.level + 1} 波',
                              primary: true,
                              onTap: () => _enter(
                                context,
                                GameScreen(
                                  settings: settings,
                                  sfx: widget.sfx,
                                  mode: resume.mode,
                                  resume: resume,
                                  onExitToMenu: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ),
                          _MenuTile(
                            label: '战役模式',
                            sub: settings.hasProgress
                                ? '六场战斗 · 已解锁第 ${settings.unlockedLevel + 1} 关'
                                : '六场战斗 · 从迷雾到终焉',
                            onTap: () => _enter(
                              context,
                              GameScreen(
                                settings: settings,
                                sfx: widget.sfx,
                                mode: GameMode.campaign,
                                onExitToMenu: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                          _MenuTile(
                            label: '无尽模式',
                            sub: settings.endlessBest > 0
                                ? '波次无限 · 最佳 ${settings.endlessBest} 波'
                                : '波次无限 · 敌人逐波增强',
                            onTap: () => _enter(
                              context,
                              GameScreen(
                                settings: settings,
                                sfx: widget.sfx,
                                mode: GameMode.endless,
                                onExitToMenu: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _MenuTile(
                                  label: '玩法说明',
                                  compact: true,
                                  onTap: () => setState(() {
                                    _showHelp = true;
                                    _confirmReset = false;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MenuTile(
                                  label: '设置',
                                  compact: true,
                                  onTap: () => setState(() {
                                    _showSettings = true;
                                    _confirmReset = false;
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Text(
                              '消除即攻击 · 布局即战术',
                              style: AppText.label.copyWith(
                                fontSize: 10.5,
                                color: Palette.textDim.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_showHelp) _helpOverlay(),
          if (_showSettings) _settingsOverlay(),
        ],
      ),
    );
  }

  String _levelLabel(int levelIndex) {
    if (levelIndex >= Campaign.levels.length) return '已通关';
    return '第 ${levelIndex + 1} 关';
  }

  // ------------------------------------------------------------------ 遮罩

  Widget _modalScaffold({required Widget child}) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _showSettings = false;
          _showHelp = false;
          _confirmReset = false;
        }),
        child: Container(
          color: Colors.black.withValues(alpha: 0.80),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _helpOverlay() {
    return _modalScaffold(
      child: HelpPanel(onClose: () => setState(() => _showHelp = false)),
    );
  }

  Widget _settingsOverlay() {
    final settings = widget.settings;
    return _modalScaffold(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.panelEdge),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('设置', style: AppText.title.copyWith(fontSize: 20)),
                const Spacer(),
                PanelCloseButton(onTap: () => setState(() => _showSettings = false)),
              ],
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 16),
            if (_confirmReset) ...[
              Text(
                '确定清空全部进度与进行中的一局吗？设置会保留。',
                style: AppText.label.copyWith(fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: MenuButton(
                      label: '清空',
                      height: 44,
                      fontSize: 13,
                      radius: 12,
                      onTap: () {
                        settings.resetProgress();
                        setState(() => _confirmReset = false);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MenuButton(
                      label: '取消',
                      height: 44,
                      fontSize: 13,
                      radius: 12,
                      onTap: () => setState(() => _confirmReset = false),
                    ),
                  ),
                ],
              ),
            ] else
              MenuButton(
                label: '清空全部进度',
                height: 44,
                fontSize: 13,
                radius: 12,
                onTap: () => setState(() => _confirmReset = true),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 装饰

/// 主菜单背景：深色渐变 + 缓慢漂浮的宝石剪影，全部程序化绘制。
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackdropPainter());
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = Palette.bgDeep);

    // 底部向上的金色微光，给标题一个视觉焦点。
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Palette.gold.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glow);

    // 一圈漂浮的宝石：位置由固定公式给出（不随机），每次进入界面都一样。
    // 只落在左右两条边缘带与上下边缘——中央是标题与按钮的区域，
    // 被一颗宝石压住标题字比没有装饰更难看。
    final gems = GemType.values;
    for (var i = 0; i < 14; i++) {
      final r1 = (i * 0.618) % 1;
      final band = i % 3;
      final x = switch (band) {
        0 => size.width * (0.05 + 0.09 * r1),
        1 => size.width * (0.86 + 0.09 * r1),
        _ => size.width * (0.20 + 0.60 * r1),
      };
      final y = size.height *
          (band == 2 ? (i.isEven ? 0.03 + 0.06 * r1 : 0.90 + 0.06 * r1) : 0.04 + 0.92 * ((i * 0.382) % 1));
      final s = 14.0 + 22.0 * ((i * 0.777) % 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(((i * 0.77) % 1 - 0.5) * 0.8);
      canvas.scale(s, s);
      GemArt.paint(
        canvas,
        const Rect.fromLTWH(-0.5, -0.5, 1, 1),
        gems[i % gems.length],
        SpecialKind.none,
        glow: 0.25,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

/// 标题区：游戏名 + 一排宝石装饰。
///
/// 宽度自适应：320 的小屏 + 系统大字体是主菜单最容易撑爆的组合，
/// 宝石与标题字号都按可用宽度缩放，极端组合下整体缩小而不是溢出。
class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final badge = ((w - 40) / 5).clamp(30.0, 48.0);
        final titleSize = (w / 6.2).clamp(26.0, 40.0);
        return Column(
          children: [
            SizedBox(
              height: badge + 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final type in GemType.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _GemBadge(type: type, size: badge, special: SpecialKind.none),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFFE9A8), Palette.gold, Color(0xFFC98A33)],
              ).createShader(bounds),
              child: Text(
                '裂隙消消乐',
                style: AppText.title.copyWith(
                  fontSize: titleSize,
                  letterSpacing: titleSize * 0.15,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'GEM BATTLE',
              style: AppText.label.copyWith(
                fontSize: 11,
                letterSpacing: 6,
                color: Palette.textDim.withValues(alpha: 0.8),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GemBadge extends StatelessWidget {
  final GemType type;
  final SpecialKind special;
  final double size;

  const _GemBadge({required this.type, required this.special, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: CustomPaint(painter: _GemBadgePainter(type, special)),
      ),
    );
  }
}

class _GemBadgePainter extends CustomPainter {
  final GemType type;
  final SpecialKind special;

  const _GemBadgePainter(this.type, this.special);

  @override
  void paint(Canvas canvas, Size size) {
    GemArt.paint(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height),
      type,
      special,
      glow: 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _GemBadgePainter old) =>
      old.type != type || old.special != special;
}

// ------------------------------------------------------------------ 控件

/// 主菜单的一格入口按钮：主文字 + 一行小字说明。
class _MenuTile extends StatelessWidget {
  final String label;
  final String? sub;
  final bool primary;
  final bool compact;
  final VoidCallback onTap;

  const _MenuTile({
    required this.label,
    required this.onTap,
    this.sub,
    this.primary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: sub == null ? label : '$label，$sub',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: compact ? 12 : 15,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: primary
                ? const LinearGradient(colors: [Palette.gold, Color(0xFFC98A33)])
                : null,
            color: primary ? null : Palette.panel.withValues(alpha: 0.85),
            border: Border.all(
              color: primary ? Palette.gold : Palette.panelEdge,
              width: primary ? 1.4 : 1,
            ),
            boxShadow: primary
                ? [BoxShadow(color: Palette.gold.withValues(alpha: 0.30), blurRadius: 22)]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.button.copyWith(
                        fontSize: compact ? 14.5 : 17,
                        color: primary ? const Color(0xFF2A1600) : Palette.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub!,
                        style: AppText.label.copyWith(
                          fontSize: 10.5,
                          color: primary
                              ? const Color(0xFF2A1600).withValues(alpha: 0.75)
                              : Palette.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: primary
                    ? const Color(0xFF2A1600).withValues(alpha: 0.8)
                    : Palette.textDim.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
