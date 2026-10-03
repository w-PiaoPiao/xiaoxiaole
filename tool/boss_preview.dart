// BOSS 造型预览：把十三位美少女的立绘渲染到一张 PNG 上，逐一核对造型差异。
//
// 用法：flutter test tool/boss_preview.dart
// 产物：build/boss_preview/bosses.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/ui/enemy_art.dart';

import 'preview_font.dart';

void main() {
  setUpAll(() async {
    await loadPreviewFont();
  });

  testWidgets('十三位美少女的造型一览', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);

    final maidens = [
      for (final level in Campaign.levels) level.enemy,
    ];

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'CJK', brightness: Brightness.dark),
          home: Scaffold(
            backgroundColor: const Color(0xFF0E0818),
            body: Column(
              children: [
                for (final def in maidens)
                  Expanded(
                    child: Row(
                      children: [
                        // 无 child 的 CustomPaint 必须显式给 size，否则首帧
                        // 是零尺寸（EnemyArt 会安全跳过），截图里就是空的。
                        CustomPaint(
                          size: const Size(130, 150),
                          painter: _BossPainter(
                            def.archetype,
                            Color(def.themeColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          def.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/boss_preview/bosses.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('已生成 build/boss_preview/bosses.png');
  });
}

class _BossPainter extends CustomPainter {
  final EnemyArchetype archetype;
  final Color theme;

  const _BossPainter(this.archetype, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    EnemyArt.paint(
      canvas,
      Size(size.height * 0.78, size.height * 0.86),
      theme,
      const EnemyPose(time: 0.6, hpRatio: 1.0),
      archetype: archetype,
    );
  }

  @override
  bool shouldRepaint(covariant _BossPainter old) => old.archetype != archetype;
}
