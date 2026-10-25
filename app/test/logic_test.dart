import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/content.dart';
import 'package:super_mom/logic.dart';
import 'package:super_mom/models.dart';

const prayers = DayPrayerTimes(6 * 60 + 20, {
  Prayer.fajr: 5 * 60 + 10,
  Prayer.dhuhr: 12 * 60 + 8,
  Prayer.asr: 15 * 60 + 20,
  Prayer.maghrib: 17 * 60 + 52,
  Prayer.isha: 19 * 60 + 10,
});

void main() {
  late List<RoutineTask> routine;
  late Kid kid;

  setUp(() {
    routine = defaultRoutine();
    kid = Kid(id: 'a', name: 'Aisha', age: 10);
  });

  RoutineTask task(String id) => routine.firstWhere((t) => t.id == id);

  test('salah windows follow prayer times', () {
    expect(windowOf(task('fajr'), prayers).start, 5 * 60 + 10);
    expect(windowOf(task('fajr'), prayers).end, 6 * 60 + 20); // until sunrise
    expect(windowOf(task('asr'), prayers).end, 17 * 60 + 52); // until Maghrib
  });

  test('kids can tick only while the window is open', () {
    final hw = task('homework'); // 3:30 pm – 6:30 pm
    expect(kidCanToggle(kid, hw, 3, 3, 15 * 60, prayers), isFalse);
    expect(kidCanToggle(kid, hw, 3, 3, 16 * 60, prayers), isTrue);
    expect(kidCanToggle(kid, hw, 3, 3, 19 * 60, prayers), isFalse);
    expect(statusOf(kid, hw, 3, 3, 19 * 60, prayers), TaskStatus.missed);
    expect(
      statusOf(kid, hw, 2, 3, 12 * 60, prayers),
      TaskStatus.missed,
    ); // yesterday
  });

  test('kids cannot untick something Mom marked', () {
    final hw = task('homework');
    kid.checks[Kid.key(3, hw.id)] = DoneBy.mom;
    expect(kidCanToggle(kid, hw, 3, 3, 16 * 60, prayers), isFalse);
    kid.checks[Kid.key(3, hw.id)] = DoneBy.kid;
    expect(kidCanToggle(kid, hw, 3, 3, 16 * 60, prayers), isTrue);
  });

  test('stars: 2 for a full day, minus time-outs, capped at 10', () {
    for (var d = 1; d <= 5; d++) {
      for (final t in tasksFor(kid, routine, d, prayers)) {
        kid.checks[Kid.key(d, t.id)] = DoneBy.kid;
      }
    }
    final full = weekScore(kid, routine, 6, prayers);
    expect(full.earned, 10);
    expect(full.bonus, 2); // Monday and Thursday fasts
    expect(full.total, 10);

    kid.timeouts.addAll([
      TimeOut(weekday: 1, minute: 0, reason: 'x'),
      TimeOut(weekday: 2, minute: 0, reason: 'x'),
      TimeOut(weekday: 3, minute: 0, reason: 'x'),
    ]);
    expect(weekScore(kid, routine, 6, prayers).total, 9); // 10 + 2 − 3
  });

  test('a day at 60% earns one star, below that none', () {
    final list = tasksFor(
      kid,
      routine,
      1,
      prayers,
    ).where((t) => !t.bonus).toList();
    final sixty = (list.length * 0.6).ceil();
    for (final t in list.take(sixty)) {
      kid.checks[Kid.key(1, t.id)] = DoneBy.kid;
    }
    expect(dayStars(kid, routine, 1, 2, prayers), 1);
    kid.checks.remove(Kid.key(1, list.first.id));
    expect(dayStars(kid, routine, 1, 2, prayers), 0);
  });

  test('exam mode keeps only study, salah, Quran, sleep and morning tasks', () {
    kid.examMode = true;
    final cats = tasksFor(
      kid,
      routine,
      2,
      prayers,
    ).map((t) => t.category).toSet();
    expect(cats.contains(TaskCategory.chores), isFalse);
    expect(cats.contains(TaskCategory.screen), isFalse);
    expect(cats.contains(TaskCategory.study), isTrue);
  });

  test('weekend belongs to the week that just ended', () {
    expect(weekIdFor(DateTime(2026, 10, 24)), '20261019'); // Saturday
    expect(
      weekIdFor(DateTime(2026, 10, 25, 23, 59)),
      '20261019',
    ); // Sunday night
    expect(weekIdFor(DateTime(2026, 10, 26)), '20261026'); // Monday: new week
  });

  test('family and kid data survive saving and loading', () {
    kid.checks['3:homework'] = DoneBy.mom;
    kid.timeouts.add(TimeOut(weekday: 3, minute: 600, reason: 'Not listening'));
    kid.rewards.add(Reward('Zoo', 9));
    final f = FamilyData(
      id: 'fam',
      parents: ['mom'],
      prayer: PrayerSettings(),
      kids: [kid],
      routine: routine,
      weekId: '20261019',
      prayerWindows: {'20261019': List.filled(10, 5)},
    );
    final back = FamilyData.fromDoc('fam', f.toDoc(), []);
    expect(back.routine.length, routine.length);
    expect(back.routine.firstWhere((t) => t.id == 'fajr').prayer, Prayer.fajr);
    expect(back.prayerWindows['20261019']!.length, 10);

    // Profile and week are stored in separate documents.
    final profile = kid.profileJson();
    expect(profile.containsKey('checks'), isFalse);
    final loaded = Kid.fromJson({...profile, 'id': kid.id})
      ..applyWeek({
        'checks': {'3:homework': 'mom'},
        'timeouts': [kid.timeouts.first.toJson()],
        'wishIndex': 0,
      });
    expect(loaded.checks['3:homework'], DoneBy.mom);
    expect(loaded.timeouts.first.reason, 'Not listening');
    expect(loaded.rewards.first.name, 'Zoo');
    expect(loaded.wishIndex, 0);
  });

  test('week and day keys match the security rules', () {
    expect(ymdKey(DateTime(2026, 1, 5)), '20260105');
    expect(formatWeekId('20261019'), '19 Oct 2026');
  });
}
