// 像素级放大：把预览截图里的一小块区域放大若干倍另存，用来确认
// 缩略之下看不清的细节（字形、描边、可疑的杂点）。
//
// 用法：flutter test tool/zoom.dart --dart-define=SRC=build/ui_preview/xx.png
//      可选：--dart-define=X=180 --dart-define=Y=85 --dart-define=W=120
//            --dart-define=H=60 --dart-define=ZOOM=6
// 产物：build/ui_preview/zoom.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _src = String.fromEnvironment('SRC', defaultValue: 'build/ui_preview/13_max_text.png');
const _x = int.fromEnvironment('X', defaultValue: 0);
const _y = int.fromEnvironment('Y', defaultValue: 0);
const _w = int.fromEnvironment('W', defaultValue: 200);
const _h = int.fromEnvironment('H', defaultValue: 100);
const _zoom = int.fromEnvironment('ZOOM', defaultValue: 4);

void main() {
  testWidgets('放大局部', (tester) async {
    final bytes = File(_src).readAsBytesSync();
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      // 屏幕坐标以逻辑像素记录：预览图是 1:1 逻辑像素导出的，直接用即可。
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(_x.toDouble(), _y.toDouble(), _w.toDouble(), _h.toDouble()),
        Rect.fromLTWH(0, 0, (_w * _zoom).toDouble(), (_h * _zoom).toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage((_w * _zoom).round(), (_h * _zoom).round());
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui_preview/zoom.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('已生成 build/ui_preview/zoom.png  '
          '源图 ${image.width}x${image.height}  区域 ($_x,$_y,$_w,$_h) x$_zoom');
    });
  });
}
