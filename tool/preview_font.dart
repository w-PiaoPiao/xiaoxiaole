// 预览脚本共用的中文字体加载。
//
// CustomPaint 里的文字不经过 Widget 树、拿不到主题字体，而测试环境的默认
// 字体没有中文字形——不加载的话截图里全是实心方块，排版根本没法校对。
//
// 字体按平台探测常见路径，也可以用 `PREVIEW_FONT=/path/to/font.ttf` 指定；
// 一个都找不到时不报错：预览照常出图，只是画布文字变成方块——不该因为
// "这台机器没装字体"让整个预览脚本失败。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gem_battle/ui/paint_utils.dart';

/// 各平台常见的中文字体候选（按探测顺序）。
const _candidates = [
  // macOS
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/System/Library/Fonts/Hiragino Sans GB.ttc',
  // Linux
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
  // Windows
  'C:/Windows/Fonts/msyh.ttc',
  'C:/Windows/Fonts/simhei.ttf',
];

/// 加载预览用的中文字体族 `CJK`，并把它接到画布文字上。返回是否成功。
Future<bool> loadPreviewFont() async {
  final override = Platform.environment['PREVIEW_FONT'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    ..._candidates,
  ];
  for (final path in candidates) {
    if (!File(path).existsSync()) continue;
    try {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader('CJK')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      debugCanvasFontFamily = 'CJK';
      return true;
    } catch (_) {
      // 这个字体读不了就试下一个。
    }
  }
  stderr.writeln(
    '[preview] 没找到可用的中文字体，画布文字会显示成方块。'
    '可用 PREVIEW_FONT=/path/to/font.ttf 指定。',
  );
  return false;
}
