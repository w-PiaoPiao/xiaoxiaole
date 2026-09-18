import 'package:flutter/material.dart';

import '../engine/gem.dart';

/// 全局配色：深夜紫 + 金饰的暗黑幻想基调。
class Palette {
  const Palette._();

  static const Color bgDeep = Color(0xFF06040C);
  static const Color bgMid = Color(0xFF140B24);
  static const Color bgTop = Color(0xFF2A1240);

  static const Color panel = Color(0xFF150C28);
  static const Color panelEdge = Color(0xFF3B2465);
  static const Color slotFill = Color(0xFF0E0819);
  static const Color slotEdge = Color(0xFF241640);

  static const Color gold = Color(0xFFFFC978);
  static const Color goldDim = Color(0xFF8A6A3A);

  static const Color textPrimary = Color(0xFFF4EEFF);
  static const Color textDim = Color(0xFF9C8FC4);

  static const Color hpPlayer = Color(0xFF54E39A);
  static const Color hpEnemy = Color(0xFFFF4569);
  static const Color shield = Color(0xFF5FC8FF);
  static const Color rage = Color(0xFFFFD34D);
  static const Color danger = Color(0xFFFF3B5C);

  /// 宝石主色（亮部）。
  static const Map<GemType, Color> gemLight = {
    GemType.red: Color(0xFFE8445C),
    GemType.blue: Color(0xFF3FA8E8),
    GemType.green: Color(0xFF33C071),
    GemType.yellow: Color(0xFFF0B01F),
    GemType.purple: Color(0xFF9E5CE8),
  };

  /// 宝石暗部，用于渐变的下缘。
  static const Map<GemType, Color> gemDark = {
    GemType.red: Color(0xFF8E0C26),
    GemType.blue: Color(0xFF0E3E70),
    GemType.green: Color(0xFF0C5730),
    GemType.yellow: Color(0xFF7A4A05),
    GemType.purple: Color(0xFF4A1580),
  };

  static Color gem(GemType type) => gemLight[type]!;

  static Color gemDeep(GemType type) => gemDark[type]!;
}

/// 常用文本样式。
class AppText {
  const AppText._();

  static const TextStyle title = TextStyle(
    color: Palette.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: 2,
  );

  static const TextStyle enemyName = TextStyle(
    color: Palette.textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );

  static const TextStyle subtitle = TextStyle(
    color: Palette.textDim,
    fontSize: 11,
    letterSpacing: 3,
  );

  static const TextStyle label = TextStyle(
    color: Palette.textDim,
    fontSize: 11,
    letterSpacing: 1.2,
  );

  static const TextStyle number = TextStyle(
    color: Palette.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle button = TextStyle(
    color: Palette.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 2,
  );
}
