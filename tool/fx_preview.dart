// 战斗特效预览：把每种打击特效渲染成 PNG，用来校对观感。
//
// 直接在设备上抓帧很难命中 0.3~0.6 秒的特效，这个工具可以精确控制动画进度，
// 一次把所有阶段的形状打出来看。
//
// 用法：flutter test tool/fx_preview.dart
// 产物：build/fx_preview/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/ui/combat_art.dart';
import 'package:gem_battle/ui/enemy_art.dart';
import 'package:gem_battle/ui/fx.dart';
import 'package:gem_battle/ui/palette.dart';

const _size = Size(420, 380);

class _PreviewPainter extends CustomPainter {
  final List<StrikeFx> strikes;
  final UltimateFx? ultimate;

  /// 是否连角色一起画出来——按真实战斗区比例预览时开，用来确认构图。
  final bool withCharacter;

  const _PreviewPainter({
    this.strikes = const [],
    this.ultimate,
    this.withCharacter = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.bgTop, Palette.bgMid, Palette.bgDeep],
        ).createShader(rect),
    );

    if (withCharacter) {
      // 复刻游戏里的角色摆位：高度 0.84、宽高比 0.78、从 0.19 高度开始
      final charH = size.height * 0.84;
      final charW = charH * 0.78;
      canvas.save();
      canvas.translate((size.width - charW) / 2, size.height * 0.19);
      EnemyArt.paint(
        canvas,
        Size(charW, charH),
        const Color(0xFF57E0C8),
        const EnemyPose(time: 1.2, hpRatio: 0.6),
      );
      canvas.restore();
    }

    if (strikes.isNotEmpty) CombatArt.paintStrikes(canvas, size, strikes);
    if (ultimate != null) CombatArt.paintUltimate(canvas, size, ultimate!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  CustomPainter painter, {
  Size size = _size,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(painter: painter),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/fx_preview/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // ignore: avoid_print
  print('已生成 build/fx_preview/$name.png');
}

/// t 是动画进度字段，构造之后再设，方便精确预览某一帧。
StrikeFx fxAt(
  StrikeKind kind, {
  required int seed,
  required double t,
  double ny = 0.5,
  double power = 1.2,
}) => StrikeFx(kind: kind, seed: seed, ny: ny, power: power)..t = t;

void main() {
  final cases = <String, List<StrikeFx>>{
    'sword': [
      fxAt(StrikeKind.sword, seed: 11, t: 0.30, ny: 0.5, power: 1.4),
      fxAt(StrikeKind.sword, seed: 12, t: 0.55, ny: 0.5, power: 1.4),
      fxAt(StrikeKind.sword, seed: 13, t: 0.80, ny: 0.5, power: 1.4),
    ],
    'lightning': [
      fxAt(StrikeKind.lightning, seed: 21, t: 0.18, ny: 0.55, power: 1.3),
      fxAt(StrikeKind.lightning, seed: 22, t: 0.42, ny: 0.55, power: 1.3),
      fxAt(StrikeKind.lightning, seed: 23, t: 0.70, ny: 0.55, power: 1.3),
    ],
    'curse': [
      fxAt(StrikeKind.curse, seed: 31, t: 0.20, ny: 0.55, power: 1.2),
      fxAt(StrikeKind.curse, seed: 32, t: 0.50, ny: 0.55, power: 1.2),
      fxAt(StrikeKind.curse, seed: 33, t: 0.80, ny: 0.55, power: 1.2),
    ],
    'heal_shield': [
      fxAt(StrikeKind.heal, seed: 41, t: 0.45, ny: 0.85, power: 1.2),
      fxAt(StrikeKind.shield, seed: 42, t: 0.45, ny: 0.85, power: 1.2),
      fxAt(StrikeKind.enemyHit, seed: 43, t: 0.45, ny: 0.85, power: 1.3),
    ],
  };

  cases.forEach((name, list) {
    testWidgets('特效预览 $name', (tester) async {
      await _shot(tester, name, _PreviewPainter(strikes: list));
    });
  });

  // 按真实战斗区比例（1080x620）预览，确认特效与角色的构图关系
  testWidgets('实战构图预览', (tester) async {
    await _shot(
      tester,
      'scene_sword',
      _PreviewPainter(
        withCharacter: true,
        strikes: [
          fxAt(StrikeKind.sword, seed: 12, t: 0.55, ny: 0.52, power: 1.3),
        ],
      ),
      size: const Size(540, 310),
    );
    await _shot(
      tester,
      'scene_lightning',
      _PreviewPainter(
        withCharacter: true,
        strikes: [
          fxAt(StrikeKind.lightning, seed: 22, t: 0.45, ny: 0.5, power: 1.3),
        ],
      ),
      size: const Size(540, 310),
    );
    await _shot(
      tester,
      'scene_ultimate',
      _PreviewPainter(
        withCharacter: true,
        ultimate: UltimateFx(tilt: 0.1)..t = 0.5,
      ),
      size: const Size(540, 310),
    );
  });

  testWidgets('必杀·斩月 预览', (tester) async {
    await _shot(
      tester,
      'ultimate_a',
      _PreviewPainter(ultimate: UltimateFx(tilt: 0.1)..t = 0.30),
    );
    await _shot(
      tester,
      'ultimate_b',
      _PreviewPainter(ultimate: UltimateFx(tilt: 0.1)..t = 0.55),
    );
    await _shot(
      tester,
      'ultimate_c',
      _PreviewPainter(ultimate: UltimateFx(tilt: 0.1)..t = 0.78),
    );
  });
}
