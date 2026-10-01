// 应用图标生成器：直接复用游戏里的宝石矢量美术渲染启动图标，
// 保证图标与游戏内视觉一致。
//
// 用法：flutter test tool/icon_generator.dart
// 产物：android/app/src/main/res/mipmap-*/ic_launcher.png
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/ui/gem_art.dart';

const _bgDeep = Color(0xFF06040C);
const _bgMid = Color(0xFF241041);
const _gold = Color(0xFFFFC978);

class IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rounded = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.22),
    );

    canvas.save();
    canvas.clipRRect(rounded);

    // 深紫底 + 中心光晕
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bgMid, _bgDeep],
        ).createShader(rect),
    );
    final center = rect.center;
    canvas.drawCircle(
      center,
      size.width * 0.52,
      Paint()
        ..shader =
            RadialGradient(
              colors: [_gold.withValues(alpha: 0.30), Colors.transparent],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.width * 0.52),
            ),
    );

    // 底部的魔法阵弧线
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, size.height * 0.86),
        width: size.width * 0.76,
        height: size.width * 0.30,
      ),
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.02
        ..color = _gold.withValues(alpha: 0.55),
    );

    // 主宝石：烈焰菱形
    final gemSide = size.width * 0.56;
    GemArt.paint(
      canvas,
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - size.height * 0.03),
        width: gemSide,
        height: gemSide,
      ),
      GemType.red,
      SpecialKind.none,
      glow: 1.0,
    );

    // 两侧的小宝石，点出「消消乐」的三消感
    for (final entry in const [
      (GemType.blue, -0.30, 0.20),
      (GemType.yellow, 0.30, 0.18),
    ]) {
      final side = size.width * 0.20;
      GemArt.paint(
        canvas,
        Rect.fromCenter(
          center: Offset(
            center.dx + size.width * entry.$2,
            center.dy + size.height * entry.$3,
          ),
          width: side,
          height: side,
        ),
        entry.$1,
        SpecialKind.none,
        glow: 0.6,
      );
    }

    canvas.restore();

    // 描边
    canvas.drawRRect(
      rounded.deflate(size.width * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.024
        ..color = _gold.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> _writePng(WidgetTester tester, int px, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: px.toDouble(),
          height: px.toDouble(),
          child: CustomPaint(painter: IconPainter()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // 图片编码是真正的异步工作，必须放在 runAsync 里，否则测试时钟会把它卡住。
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // ignore: avoid_print
  print('已生成 $path (${px}x$px)');
}

void main() {
  const densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  for (final entry in densities.entries) {
    testWidgets('生成 ${entry.key} 图标', (tester) async {
      await _writePng(
        tester,
        entry.value,
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      );
    });
  }
}
