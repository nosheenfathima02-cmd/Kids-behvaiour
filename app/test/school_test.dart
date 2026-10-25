import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/classroom.dart';
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

SchoolItem homework(String id, String day, {String kid = 'a'}) => SchoolItem(
  id: id,
  kidId: kid,
  kind: SchoolKind.homework,
  title: 'Worksheet',
  subject: 'Maths',
  dueYmd: day,
  fromYmd: day,
  toYmd: day,
);

void main() {
  // Week of Monday 26 Oct 2026.
  const week = '20261026';

  test('homework is done the school day before it is due', () {
    final wed = DateTime(2026, 10, 26);
    expect(
      ymdKey(defaultWorkDay(DateTime(2026, 10, 28), wed)),
      '20261027',
    ); // due Wed -> Tue
    expect(
      ymdKey(defaultWorkDay(DateTime(2026, 11, 2), wed)),
      '20261030',
    ); // due Mon -> Fri
    expect(
      ymdKey(defaultWorkDay(DateTime(2026, 10, 26, 9), wed)),
      '20261026',
    ); // due today -> today
    expect(
      ymdKey(defaultWorkDay(DateTime(2026, 10, 27), DateTime(2026, 10, 27))),
      '20261027',
    ); // never in the past
  });

  test('school items become tasks only on their days, for their child', () {
    final items = [
      homework('s_1', '20261027'),
      homework('s_2', '20261103'), // next week
      SchoolItem(
        id: 's_3',
        kidId: 'a',
        kind: SchoolKind.event,
        title: 'Recitation',
        dueYmd: '20261030',
        fromYmd: '20261021',
        toYmd: '20261029',
      ),
      SchoolItem(
        id: 's_4',
        kidId: 'a',
        kind: SchoolKind.test,
        title: 'Quiz',
        dueYmd: '20261029',
      ), // reminder only
    ];
    final tasks = schoolTasks(items, week);
    expect(tasks.map((t) => t.id), ['s_1', 's_3']);
    expect(tasks.first.weekdays, [2]);
    expect(tasks.first.kidIds, ['a']);
    expect(tasks.first.title, 'Homework (Maths): Worksheet');
    expect(tasks[1].weekdays, [
      1,
      2,
      3,
      4,
    ]); // practice Mon–Thu, competition Friday
  });

  test('homework counts towards the day like any other task', () {
    final kid = Kid(id: 'a', name: 'Aisha', age: 10);
    final routine = defaultRoutine();
    final all = [
      ...routine,
      ...schoolTasks([homework('s_1', '20261027')], week),
    ];
    final tuesday = tasksFor(
      kid,
      all,
      2,
      prayers,
    ).where((t) => !t.bonus).toList();
    final wednesday = tasksFor(
      kid,
      all,
      3,
      prayers,
    ).where((t) => !t.bonus).toList();
    expect(tuesday.length, wednesday.length + 1);
    expect(tuesday.any((t) => t.id == 's_1'), isTrue);
    // Only the homework done: far below 60%, no stars; everything done: 2 stars.
    kid.checks[Kid.key(2, 's_1')] = DoneBy.kid;
    expect(dayStars(kid, all, 2, 3, prayers), 0);
    for (final t in tuesday) {
      kid.checks[Kid.key(2, t.id)] = DoneBy.kid;
    }
    expect(dayStars(kid, all, 2, 3, prayers), 2);
    // Another child does not get Aisha's homework.
    expect(
      tasksFor(
        Kid(id: 'b', name: 'Yusuf', age: 7),
        all,
        2,
        prayers,
      ).any((t) => t.id == 's_1'),
      isFalse,
    );
  });

  test('competition practice ticks are counted', () {
    final kid = Kid(id: 'a', name: 'Aisha', age: 10);
    final ev = SchoolItem(
      id: 's_ev',
      kidId: 'a',
      kind: SchoolKind.event,
      title: 'Spelling bee',
      dueYmd: '20261030',
    );
    kid.checks['1:s_ev'] = DoneBy.kid;
    kid.checks['3:s_ev'] = DoneBy.mom;
    kid.checks['3:homework'] = DoneBy.kid;
    expect(practiceTicksThisWeek(kid, ev), 2);
  });

  test('school items survive saving and loading', () {
    final item = SchoolItem(
      id: 's_x',
      kidId: 'a',
      kind: SchoolKind.event,
      title: "Qur'an competition",
      dueYmd: '20261030',
      fromYmd: '20261026',
      toYmd: '20261029',
      practiceTarget: 10,
      practiceDone: 3,
    );
    final back = SchoolItem.fromJson(item.toJson());
    expect(back.kind, SchoolKind.event);
    expect(back.practiceDone, 3);
    expect(back.hasTask, isTrue);
  });

  group('Google Classroom', () {
    final now = DateTime(2026, 10, 26, 16);
    final response = {
      'courseWork': [
        {
          'courseId': '111',
          'id': 'cw1',
          'title': 'Fractions worksheet',
          'dueDate': {'year': 2026, 'month': 10, 'day': 28},
          'alternateLink': 'https://classroom.google.com/c/111/a/cw1',
        },
        {
          'courseId': '111',
          'id': 'cw2',
          'title': 'Chapter 4 Quiz',
          'dueDate': {'year': 2026, 'month': 10, 'day': 30},
          'dueTime': {'hours': 8},
        },
        {
          'courseId': '111',
          'id': 'cw3',
          'title': 'Handed in already',
          'dueDate': {'year': 2026, 'month': 10, 'day': 29},
        },
        {'courseId': '111', 'id': 'cw4', 'title': 'No due date'},
        {
          'courseId': '111',
          'id': 'cw5',
          'title': 'Old',
          'dueDate': {'year': 2026, 'month': 10, 'day': 1},
        },
        {
          'courseId': '111',
          'id': 'cw6',
          'title': 'Far away',
          'dueDate': {'year': 2026, 'month': 12, 'day': 1},
        },
      ],
    };

    test('keeps upcoming work that is not handed in', () {
      final work = parseCourseWork(response, 'Maths 5B', {'cw3'}, now);
      expect(work.map((w) => w.workId), ['cw1', 'cw2']);
      expect(work.first.courseName, 'Maths 5B');
      expect(work[1].looksLikeTest, isTrue);
      expect(work.first.looksLikeTest, isFalse);
    });

    test('becomes homework on the day before, with a stable id', () {
      final work = parseCourseWork(response, 'Maths 5B', {}, now);
      final item = schoolItemFor(work.first, 'a', now);
      expect(item.id, 's_cw_111_cw1');
      expect(item.kind, SchoolKind.homework);
      expect(item.dueYmd, '20261028');
      expect(item.fromYmd, '20261027');
      expect(item.source, 'classroom');
      expect(schoolItemFor(work[1], 'a', now).kind, SchoolKind.test);
    });

    test('syncing again keeps the day Mom chose', () {
      final work = parseCourseWork(response, 'Maths 5B', {}, now);
      final moved = schoolItemFor(work.first, 'a', now)
        ..fromYmd = '20261026'
        ..toYmd = '20261026';
      final again = schoolItemFor(work.first, 'a', now, existing: moved);
      expect(again.fromYmd, '20261026');
    });
  });
}
