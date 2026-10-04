/// widget 测试的通用驱动。
///
/// `game_flow_test` 与 `game_state_test` 原本各写一份，两份一模一样——
/// 时序细节（每帧只能推进 0.12 秒）只该在一个地方说明。
library;

import 'package:flutter_test/flutter_test.dart';

/// 逐帧推进：`GameScreen` 把每帧 dt 截到 0.12 秒，一次 pump 一大段时间
/// 只会走 0.12 秒，所以按 100ms 逐帧推进。
Future<void> advance(WidgetTester tester, double seconds) async {
  final steps = (seconds / 0.1).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 推进到 [finder] 出现为止（最多等 [timeout] 秒）。
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  double timeout = 10,
}) async {
  final steps = (timeout / 0.1).ceil();
  for (var i = 0; i < steps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  // 静默返回会让失败延迟到后面的某个 expect，报出来的原因是"找不到文本"
  // 而不是"等了 $timeout 秒没等到"——当场失败并把目标写清楚。
  fail('waitFor 超时（$timeout 秒）：未等到 ${finder.describeMatch(Plurality.one)}');
}
