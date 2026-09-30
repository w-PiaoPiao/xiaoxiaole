import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gem_battle/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 每个用例都用独立的 mock 存储隔离。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('继续游戏存档', () {
    test('写入后能原样读回（战役）', () async {
      final settings = AppSettings();
      await settings.load();
      settings.saveResume(const ResumeData(
        mode: GameMode.campaign,
        level: 3,
        carryHp: 187,
        upgrades: {'blade': 2, 'crit': 1},
      ));

      final other = AppSettings();
      await other.load();
      final resume = other.resume;
      expect(resume, isNotNull);
      expect(resume!.mode, GameMode.campaign);
      expect(resume.level, 3);
      expect(resume.carryHp, 187);
      expect(resume.upgrades['blade'], 2);
      expect(resume.upgrades['crit'], 1);
    });

    test('写入后能原样读回（无尽 + 多层强化）', () async {
      final settings = AppSettings();
      await settings.load();
      settings.saveResume(const ResumeData(
        mode: GameMode.endless,
        level: 8,
        carryHp: 210,
        upgrades: {'regen': 3},
      ));

      final other = AppSettings();
      await other.load();
      final resume = other.resume!;
      expect(resume.mode, GameMode.endless);
      expect(resume.level, 8);
      expect(resume.upgrades['regen'], 3);
    });

    test('覆盖写入时旧的强化层会被清掉', () async {
      final settings = AppSettings();
      await settings.load();
      settings.saveResume(const ResumeData(
        mode: GameMode.campaign,
        level: 2,
        carryHp: 300,
        upgrades: {'blade': 5},
      ));
      settings.saveResume(const ResumeData(
        mode: GameMode.campaign,
        level: 3,
        carryHp: 280,
        upgrades: {'crit': 1},
      ));

      final other = AppSettings();
      await other.load();
      final resume = other.resume!;
      expect(resume.upgrades.containsKey('blade'), isFalse,
          reason: '重开后旧的强化不该残留');
      expect(resume.upgrades['crit'], 1);
    });

    test('clearResume 之后 resume 为空', () async {
      final settings = AppSettings();
      await settings.load();
      settings.saveResume(const ResumeData(
        mode: GameMode.endless,
        level: 1,
        carryHp: 300,
        upgrades: {},
      ));
      expect(settings.resume, isNotNull);
      settings.clearResume();

      final other = AppSettings();
      await other.load();
      expect(other.resume, isNull);
    });
  });

  group('读档容错', () {
    test('键的类型与预期不符时回落到默认值，不抛异常', () async {
      // 旧版本写法不同、或存档被外部工具改坏时，这些键可能不是预期类型。
      // shared_preferences 的强类型 getter 是直接强转的，一旦抛异常就会
      // 顺着 load() 冒到 main()，应用直接起不来。
      SharedPreferences.setMockInitialValues({
        'settings.sound': 'yes',
        'settings.screenShake': 1,
        'progress.unlockedLevel': 'many',
        'progress.endlessBest': 3.7,
      });

      final settings = AppSettings();
      await settings.load();

      expect(settings.sound, isTrue, reason: '类型不符 → 用默认值');
      expect(settings.screenShake, isTrue);
      expect(settings.unlockedLevel, 0);
      expect(settings.endlessBest, 0);
    });

    test('关卡号为负的 resume 整个作废', () async {
      SharedPreferences.setMockInitialValues({
        'progress.resume': jsonEncode({
          'mode': 'campaign',
          'level': -3,
          'hp': 120,
          'upgrades': <String, int>{},
        }),
      });

      final settings = AppSettings();
      await settings.load();

      expect(settings.resume, isNull, reason: '宁可当作没有存档，也不能开局就崩');
    });

    test('resume 里的异常数值被夹到合法范围', () async {
      SharedPreferences.setMockInitialValues({
        'progress.resume': jsonEncode({
          'mode': 'endless',
          'level': 4,
          'hp': -50,
          'upgrades': {'blade': -1, 'crit': 999, 'bogus': 'x'},
        }),
      });

      final settings = AppSettings();
      await settings.load();

      final resume = settings.resume!;
      expect(resume.carryHp, 0, reason: '负数生命归零，由上层换成满血开局');
      expect(resume.upgrades.containsKey('blade'), isFalse, reason: '层数 <= 0 的条目丢弃');
      expect(resume.upgrades['crit'], 99, reason: '层数上限夹到 99');
      expect(resume.upgrades.containsKey('bogus'), isFalse, reason: '非整数层数丢弃');
    });

    test('损坏的 JSON 不挡住启动，其余设置照常读出', () async {
      SharedPreferences.setMockInitialValues({
        'progress.resume': '{ 这不是 JSON',
        'settings.sound': false,
      });

      final settings = AppSettings();
      await settings.load();

      expect(settings.resume, isNull);
      expect(settings.sound, isFalse, reason: '一条存档坏掉不该连累其它设置');
    });

    test('旧版散键格式的存档仍能读出来', () async {
      SharedPreferences.setMockInitialValues({
        'progress.resume.mode': 'campaign',
        'progress.resume.level': 2,
        'progress.resume.hp': 210,
        'progress.resume.upgrade.blade': 2,
      });

      final settings = AppSettings();
      await settings.load();

      final resume = settings.resume;
      expect(resume, isNotNull);
      expect(resume!.level, 2);
      expect(resume.carryHp, 210);
      expect(resume.upgrades['blade'], 2);
    });

    test('写入新格式后会清掉旧散键，不会新旧两份并存', () async {
      SharedPreferences.setMockInitialValues({
        'progress.resume.mode': 'campaign',
        'progress.resume.level': 2,
        'progress.resume.upgrade.blade': 3,
      });

      final settings = AppSettings();
      await settings.load();
      settings.saveResume(const ResumeData(
        mode: GameMode.campaign,
        level: 1,
        carryHp: 300,
        upgrades: {'crit': 1},
      ));
      // 写盘是异步的（而且不阻塞调用方），把事件队列排空后再检查磁盘状态。
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().any((key) => key.startsWith('progress.resume.')),
        isFalse,
        reason: '旧格式的散键要清干净',
      );

      final other = AppSettings();
      await other.load();
      expect(other.resume!.level, 1);
      expect(other.resume!.upgrades.keys, ['crit']);
    });
  });

  group('无尽最佳纪录', () {
    test('只保留最高的波次', () async {
      final settings = AppSettings();
      await settings.load();
      settings.recordEndless(7);
      settings.recordEndless(4);
      settings.recordEndless(9);

      final other = AppSettings();
      await other.load();
      expect(other.endlessBest, 9);
    });

    test('清空进度会同时清掉纪录与继续存档', () async {
      final settings = AppSettings();
      await settings.load();
      settings.recordEndless(12);
      settings.saveResume(const ResumeData(
        mode: GameMode.endless,
        level: 3,
        carryHp: 260,
        upgrades: {'crit': 2},
      ));
      settings.resetProgress();

      final other = AppSettings();
      await other.load();
      expect(other.endlessBest, 0);
      expect(other.resume, isNull);
      expect(other.hasProgress, isFalse);
    });
  });
}
