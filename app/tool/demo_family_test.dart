// Writes a demo family as JSON for store screenshots (store/screenshots.js).
// Run: OUT=/tmp/demo.json flutter test tool/demo_family_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/content.dart';
import 'package:super_mom/models.dart';

void main() {
  test('demo family', () {
    final routine = defaultRoutine();
    final aisha = Kid(
      id: 'aisha',
      name: 'Aisha',
      age: 10,
      theme: 'rose',
      surahName: "Al-'Asr (103)",
      ayahDone: 2,
      ayahTotal: 3,
      rewards: [
        Reward('Picnic at the lake park', 10),
        Reward('Trampoline park', 10),
        Reward('Pick Friday dinner', 8),
        Reward('Extra 30 min weekend play', 5),
      ],
    );
    final yusuf = Kid(
      id: 'yusuf',
      name: 'Yusuf',
      age: 7,
      theme: 'galaxy',
      surahName: 'Al-Ikhlas (112)',
      ayahDone: 3,
      ayahTotal: 4,
      rewards: [
        Reward('Science museum', 10),
        Reward('Ice-cream trip', 8),
        Reward('New colouring book', 5),
      ],
    );

    // Week of Monday 26 Oct 2026; screenshots are taken on Wednesday at 4:35 pm.
    Map<String, String> days(
      Kid k,
      List<int> ds, {
      List<String> skip = const [],
    }) => {
      for (final d in ds)
        for (final t in routine)
          if (t.appliesTo(k.id, d) && !skip.contains(t.id)) '$d:${t.id}': 'kid',
    };
    final aishaChecks = {
      ...days(aisha, [1]),
      ...days(aisha, [2], skip: ['screen']),
      '1:s_quran': 'kid',
      '2:s_quran': 'kid',
      for (final id in ['wake', 'fajr', 'bag', 'breakfast', 'dhuhr', 'asr'])
        '3:$id': 'kid',
      '3:s_maths': 'kid',
    };
    final yusufChecks = {
      ...days(yusuf, [1], skip: ['room', 'revise']),
      ...days(yusuf, [2], skip: ['screen', 'veg', 'revise', 'quran']),
      for (final id in ['wake', 'bag', 'breakfast', 'dhuhr']) '3:$id': 'kid',
    };

    final school = [
      SchoolItem(
        id: 's_maths',
        kidId: 'aisha',
        kind: SchoolKind.homework,
        title: 'Fractions worksheet',
        subject: 'Maths',
        dueYmd: '20261029',
        fromYmd: '20261028',
        toYmd: '20261028',
      ),
      SchoolItem(
        id: 's_science',
        kidId: 'aisha',
        kind: SchoolKind.test,
        title: 'Plants and seeds',
        subject: 'Science',
        dueYmd: '20261030',
        fromYmd: '20261029',
        toYmd: '20261029',
      ),
      SchoolItem(
        id: 's_quran',
        kidId: 'aisha',
        kind: SchoolKind.event,
        title: "School Qur'an recitation",
        dueYmd: '20261102',
        fromYmd: '20261021',
        toYmd: '20261030',
        startMin: 17 * 60,
        endMin: 19 * 60,
        practiceTarget: 10,
        practiceDone: 4,
      ),
      SchoolItem(
        id: 's_spelling',
        kidId: 'yusuf',
        kind: SchoolKind.event,
        title: 'Spelling bee',
        dueYmd: '20261106',
      ),
    ];

    final family = FamilyData(
      id: 'demo',
      parents: ['PARENT_UID'],
      prayer: PrayerSettings(),
      kids: [],
      routine: routine,
      weekId: '20261026',
      tzOffsetMin: 240,
      schoolItems: school,
      history: [
        WeekSummary('20261019', {'Aisha': 9, 'Yusuf': 7}),
      ],
    );
    final out = {
      'family': family.toDoc(),
      'kids': {
        for (final k in [aisha, yusuf]) k.id: k.profileJson(),
      },
      'weeks': {
        '20261026_aisha': {
          'kidId': 'aisha',
          'weekId': '20261026',
          'checks': aishaChecks,
          'timeouts': [],
          'wishIndex': 3,
        },
        '20261026_yusuf': {
          'kidId': 'yusuf',
          'weekId': '20261026',
          'checks': yusufChecks,
          'timeouts': [
            TimeOut(
              weekday: 2,
              minute: 18 * 60 + 5,
              reason: 'Screen time without asking',
            ).toJson(),
          ],
        },
      },
    };
    File(Platform.environment['OUT']!).writeAsStringSync(jsonEncode(out));
  });
}
