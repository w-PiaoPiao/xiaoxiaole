import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'ui/main_menu.dart';
import 'ui/palette.dart';
import 'ui/sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // build/布局异常的兜底画面：默认的灰底红字与深色游戏格格不入，也没有
  // 任何出路。给一个主题一致的深色页——战斗流程内部的容错已经很完备，
  // 这一层只管兜住框架级异常。
  ErrorWidget.builder = (details) => DecoratedBox(
    decoration: const BoxDecoration(color: Palette.bgDeep),
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Text(
          '画面出了点问题，请退出重进。\n\n${details.exceptionAsString()}',
          style: const TextStyle(color: Palette.textDim, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
  // 竖屏单手游玩：锁定竖屏并进入沉浸式全屏。
  //
  // 刻意不 await：平台通道偶尔失败（模拟器、桌面调试环境）不该拦下启动，
  // 用 unawaited 明确交代"这是有意放手的"，而不是漏写。
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

  // 设置与音效都先加载好再进游戏：首帧就能读到存档，音效也不会缺头几秒。
  final settings = AppSettings();
  final sfx = SfxController();
  await Future.wait([settings.load(), sfx.load()]);
  // 存档里的开关要落到音效层：游戏内的同步发生在 GameScreen 里，主菜单
  // 这条路径没人管——静音设置下点主菜单按钮照样会响。
  sfx.soundEnabled = settings.sound;
  sfx.hapticsEnabled = settings.haptics;

  runApp(GemBattleApp(settings: settings, sfx: sfx));
}

class GemBattleApp extends StatelessWidget {
  final AppSettings settings;
  final SfxController sfx;

  const GemBattleApp({super.key, required this.settings, required this.sfx});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '裂隙消消乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bgDeep,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.gold,
          brightness: Brightness.dark,
        ),
      ),
      // 游戏里的棋盘是固定比例的几何布局，字号无上限地放大会直接把 HUD 撑破；
      // 限幅到 1.3 倍，既照顾了"我就想字大一点"的需求，也不会破坏排版。
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: MainMenuScreen(settings: settings, sfx: sfx),
    );
  }
}
