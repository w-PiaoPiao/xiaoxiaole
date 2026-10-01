import 'package:flutter/material.dart';

import 'palette.dart';

/// 主菜单与暂停菜单共用的基础控件。
///
/// 这几个控件原本在 main_menu.dart 与 menu_overlay.dart 里各存一份，
/// 改一处忘另一处就会出现"两个菜单里的同名按钮长得不一样"。收到这里之后
/// 依赖方向也正过来了——主菜单不必再 import 暂停菜单的文件才能用设置开关。

/// 设置开关行。
class SettingsToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: '$label，${value ? '已开启' : '已关闭'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Text(
                label,
                style: AppText.label.copyWith(
                  fontSize: 13,
                  color: Palette.textPrimary,
                ),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 46,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: value
                      ? Palette.gold.withValues(alpha: 0.85)
                      : Palette.slotFill,
                  border: Border.all(
                    color: value ? Palette.gold : Palette.panelEdge,
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? const Color(0xFF2A1600) : Palette.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 菜单里的通用按钮。
///
/// 主菜单的设置面板用小一号（[height] 44 / 字号 13 / 圆角 12），暂停菜单用
/// 默认的 48 / 14 / 13——这些尺寸差异是刻意的，所以留着参数而不是强行统一。
class MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final double height;
  final double fontSize;
  final double radius;

  const MenuButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.height = 48,
    this.fontSize = 14,
    this.radius = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: primary
                ? const LinearGradient(
                    colors: [Palette.gold, Color(0xFFC98A33)],
                  )
                : null,
            color: primary ? null : Palette.slotFill.withValues(alpha: 0.7),
            border: Border.all(
              color: primary ? Palette.gold : Palette.panelEdge,
            ),
          ),
          child: Text(
            label,
            style: AppText.button.copyWith(
              fontSize: fontSize,
              color: primary ? const Color(0xFF2A1600) : Palette.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// 面板右上角的关闭按钮。
class PanelCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const PanelCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.close, size: 18),
      tooltip: '关闭',
      color: Palette.textDim,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      style: IconButton.styleFrom(
        backgroundColor: Palette.panel.withValues(alpha: 0.9),
        side: const BorderSide(color: Palette.panelEdge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
