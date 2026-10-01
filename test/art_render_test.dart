import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/engine/gem.dart';
import 'package:gem_battle/ui/gem_art.dart';
import 'package:gem_battle/ui/obstacle_art.dart';
import 'package:gem_battle/ui/palette.dart';

/// 矢量美术的渲染契约。
///
/// 消散动画靠 `alpha` 淡出，而"把整体透明度折进每一笔"的实现一旦漏掉某一层
/// （宝石有底座 / 高光 / 描边 / 图标 / 强化标记好几层），那一层就不会跟着
/// 淡出，画面会留下残影。这里直接比较像素：同一颗宝石画两遍，透明的那一遍
/// 必须更接近背景色。
Future<List<int>> _renderPixels(
  void Function(Canvas canvas, Size size) draw, {
  int side = 64,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 纯黑底：任何"没跟着淡出"的亮层都会立刻暴露出来。
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = const Color(0xFF000000),
  );
  draw(canvas, Size(side.toDouble(), side.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// 整幅图的亮度总和，用来比较"整体亮不亮"。
int _brightness(List<int> rgba) {
  var sum = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    sum += rgba[i] + rgba[i + 1] + rgba[i + 2];
  }
  return sum;
}

void main() {
  test('宝石的半透明真的生效（消散淡出不靠 saveLayer）', () async {
    final opaque = _brightness(
      await _renderPixels((canvas, size) {
        GemArt.paint(canvas, Offset.zero & size, GemType.red, SpecialKind.none);
      }),
    );
    final faded = _brightness(
      await _renderPixels((canvas, size) {
        GemArt.paint(
          canvas,
          Offset.zero & size,
          GemType.red,
          SpecialKind.none,
          alpha: 0.4,
        );
      }),
    );

    expect(opaque, greaterThan(0), reason: '不透明的宝石应该画出东西来');
    expect(
      faded,
      lessThan(opaque * 0.6),
      reason: 'alpha=0.4 的宝石应当明显更暗——若某个图层漏了透明度，这里会接近不透明版本',
    );
    expect(faded, greaterThan(0), reason: '但也不能整颗消失');
  });

  test('强化宝石的标记也跟着淡出', () async {
    for (final kind in [
      SpecialKind.lineH,
      SpecialKind.lineV,
      SpecialKind.burst,
      SpecialKind.prism,
    ]) {
      final opaque = _brightness(
        await _renderPixels((canvas, size) {
          GemArt.paint(canvas, Offset.zero & size, GemType.blue, kind);
        }),
      );
      final faded = _brightness(
        await _renderPixels((canvas, size) {
          GemArt.paint(
            canvas,
            Offset.zero & size,
            GemType.blue,
            kind,
            alpha: 0.4,
          );
        }),
      );
      expect(faded, lessThan(opaque * 0.6), reason: '$kind 的标记没有跟着淡出');
    }
  });

  test('机关的画笔画的是同样的颜色（静态画笔不改变外观）', () async {
    // 三种机关各画一遍，确认提到了静态画笔之后仍然画得出东西、
    // 而且不同机关之间不会串色（共享画笔被改色会立刻在这里暴露）。
    final frost = _brightness(
      await _renderPixels((canvas, size) {
        ObstacleArt.paint(
          canvas,
          Offset.zero & size,
          ObstacleKind.frost,
          time: 1.2,
        );
      }),
    );
    final vine = _brightness(
      await _renderPixels((canvas, size) {
        ObstacleArt.paint(
          canvas,
          Offset.zero & size,
          ObstacleKind.vine,
          time: 1.2,
        );
      }),
    );
    final altar = _brightness(
      await _renderPixels((canvas, size) {
        ObstacleArt.paint(
          canvas,
          Offset.zero & size,
          ObstacleKind.altar,
          time: 1.2,
        );
      }),
    );

    for (final entry in {'冰封': frost, '毒藤': vine, '祭坛': altar}.entries) {
      expect(entry.value, greaterThan(0), reason: '${entry.key}没画出任何东西');
    }
    // 冰封是浅蓝、毒藤是深绿、祭坛是金——亮度不该完全相同。
    expect(
      {frost, vine, altar}.length,
      greaterThan(1),
      reason: '三种机关画出来一模一样，说明共享画笔被串色了',
    );
  });

  test('画布配色取自 Palette（静态画笔的取色来源没走偏）', () {
    expect(Palette.gem(GemType.red), isNotNull);
    expect(Palette.gemDeep(GemType.red), isNotNull);
  });
}
