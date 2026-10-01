// 回合预警点（TurnPips）的语义对照图：把三种剩余回合数并排画出来，
// 确认「亮点」到底代表剩余回合还是已过回合——这是战斗里最关键的预警信息，
// 一眼看错就会误判敌人出手时机。
//
// 用法：flutter test tool/pips_preview.dart
// 产物：build/ui_preview/pips.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/battle.dart';
import 'package:gem_battle/engine/levels.dart';
import 'package:gem_battle/ui/hud.dart';
import 'package:gem_battle/ui/palette.dart';

void main() {
  testWidgets('回合点语义', (tester) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 400);
    addTearDown(tester.view.reset);

    final battle = BattleState(
      def: Campaign.levels.first.enemy,
      levelIndex: 0,
      playerHp: 300,
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Palette.bgDeep,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in [3, 2, 1])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TurnPips(
                            total: battle.def.turnsPerAttack,
                            remaining: t,
                            color: t == 1 ? Palette.danger : Palette.textDim,
                            danger: t == 1,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'turnsToAttack=$t',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui_preview/pips.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('已生成 build/ui_preview/pips.png');
  });
}
