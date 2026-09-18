import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/game_screen.dart';
import 'ui/palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 竖屏单手游玩：锁定竖屏并进入沉浸式全屏。
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const GemBattleApp());
}

class GemBattleApp extends StatelessWidget {
  const GemBattleApp({super.key});

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
      home: const GameScreen(),
    );
  }
}
