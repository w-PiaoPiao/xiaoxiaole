// BOSS 造型预览：把六个原型剪影渲染到一张 PNG 上，逐一核对造型差异。
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

  testWidgets('六个原型的造型一览', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);

    const names = {
      EnemyArchetype.wisp: '迷雾鬼火',
      EnemyArchetype.guardian: '石甲守卫',
      EnemyArchetype.assassin: '影刃刺客',
      EnemyArchetype.witch: '血月巫女',
      EnemyArchetype.enchantress: '深渊魔女',
      EnemyArchetype.warlord: '终焉之影',
    };
    const colors = {
      EnemyArchetype.wisp: Color(0xFF57E0C8),
      EnemyArchetype.guardian: Color(0xFFE0A94A),
      EnemyArchetype.assassin: Color(0xFF9B7BE8),
      EnemyArchetype.witch: Color(0xFFE85A7A),
      EnemyArchetype.enchantress: Color(0xFFFF4D6D),
      EnemyArchetype.warlord: Color(0xFFB44BFF),
    };

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
                for (final archetype in EnemyArchetype.values)
                  Expanded(
                    child: Row(
                      children: [
                        // 无 child 的 CustomPaint 必须显式给 size，否则首帧
                        // 是零尺寸（EnemyArt 会安全跳过），截图里就是空的。
                        CustomPaint(
                          size: const Size(130, 150),
                          painter: _BossPainter(archetype, colors[archetype]!),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          names[archetype]!,
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
