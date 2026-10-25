// Rules for time windows, stars and the weekly reset. Pure functions, so they
// are easy to test and can run unchanged on the server in Stage 2.
import 'models.dart';

enum TaskStatus { upcoming, open, done, missed }

class TimeWindow {
  const TimeWindow(this.start, this.end);
  final int start;
  final int end;
  bool contains(int minute) => minute >= start && minute <= end;
}

/// Prayer start times for one day, as minutes after midnight.
class DayPrayerTimes {
  const DayPrayerTimes(this.sunrise, this.times);
  final int sunrise;
  final Map<Prayer, int> times;

  /// A salah task is open from its adhan until the next prayer
  /// (Fajr until sunrise, Isha for 2.5 hours).
  TimeWindow windowFor(Prayer p) {
    final start = times[p]!;
    switch (p) {
      case Prayer.fajr:
        return TimeWindow(start, sunrise);
      case Prayer.isha:
        return TimeWindow(start, (start + 150).clamp(start, 23 * 60 + 59));
      default:
        return TimeWindow(start, times[Prayer.values[p.index + 1]]!);
    }
  }
}

const examCategories = {
  TaskCategory.salah,
  TaskCategory.study,
  TaskCategory.quran,
  TaskCategory.sleep,
  TaskCategory.morning,
};

const maxStars = 10;
const starsPerDay = 2;

int minuteOfDay(DateTime t) => t.hour * 60 + t.minute;

TimeWindow windowOf(RoutineTask t, DayPrayerTimes prayers) => t.prayer != null
    ? prayers.windowFor(t.prayer!)
    : TimeWindow(t.startMin, t.endMin);

List<RoutineTask> tasksFor(
  Kid kid,
  List<RoutineTask> routine,
  int weekday,
  DayPrayerTimes prayers,
) {
  final list = routine
      .where((t) => t.appliesTo(kid.id, weekday))
      .where(
        (t) => !kid.examMode || t.bonus || examCategories.contains(t.category),
      )
      .toList();
  list.sort(
    (a, b) => windowOf(a, prayers).start.compareTo(windowOf(b, prayers).start),
  );
  return list;
}

/// [todayWeekday] is DateTime.weekday (1 = Monday … 7 = Sunday).
TaskStatus statusOf(
  Kid kid,
  RoutineTask t,
  int weekday,
  int todayWeekday,
  int nowMinute,
  DayPrayerTimes prayers,
) {
  if (kid.checks.containsKey(Kid.key(weekday, t.id))) return TaskStatus.done;
  if (weekday < todayWeekday) return TaskStatus.missed;
  if (weekday > todayWeekday) return TaskStatus.upcoming;
  final w = windowOf(t, prayers);
  if (nowMinute < w.start) return TaskStatus.upcoming;
  if (nowMinute > w.end) return TaskStatus.missed;
  return TaskStatus.open;
}

/// A child can tick (or untick their own tick) only while the window is open.
bool kidCanToggle(
  Kid kid,
  RoutineTask t,
  int weekday,
  int todayWeekday,
  int nowMinute,
  DayPrayerTimes prayers,
) {
  if (weekday != todayWeekday) return false;
  if (!windowOf(t, prayers).contains(nowMinute)) return false;
  final by = kid.checks[Kid.key(weekday, t.id)];
  return by == null || by == DoneBy.kid;
}

/// 90%+ of the day's tasks done = 2 stars, 60%+ = 1 star.
int dayStars(
  Kid kid,
  List<RoutineTask> routine,
  int weekday,
  int todayWeekday,
  DayPrayerTimes prayers,
) {
  if (weekday > todayWeekday) return 0;
  final list = tasksFor(
    kid,
    routine,
    weekday,
    prayers,
  ).where((t) => !t.bonus).toList();
  if (list.isEmpty) return 0;
  final done = list
      .where((t) => kid.checks.containsKey(Kid.key(weekday, t.id)))
      .length;
  final ratio = done / list.length;
  if (ratio >= 0.9) return 2;
  if (ratio >= 0.6) return 1;
  return 0;
}

class WeekScore {
  const WeekScore({
    required this.earned,
    required this.bonus,
    required this.lost,
  });
  final int earned;
  final int bonus;
  final int lost;
  int get total => (earned + bonus - lost).clamp(0, maxStars);
}

WeekScore weekScore(
  Kid kid,
  List<RoutineTask> routine,
  int todayWeekday,
  DayPrayerTimes prayers,
) {
  var earned = 0, bonus = 0;
  for (var d = 1; d <= 5; d++) {
    earned += dayStars(kid, routine, d, todayWeekday, prayers);
    if (d > todayWeekday) continue;
    bonus += tasksFor(
      kid,
      routine,
      d,
      prayers,
    ).where((t) => t.bonus && kid.checks.containsKey(Kid.key(d, t.id))).length;
  }
  return WeekScore(earned: earned, bonus: bonus, lost: kid.timeouts.length);
}

/// The school week is identified by its Monday. Saturday and Sunday still
/// belong to the week that just ended, so kids can see their stars and pick a
/// reward; everything resets when Monday starts.
String weekIdFor(DateTime now) {
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  return ymdKey(monday);
}

/// "20261019" for 19 Oct 2026. Used for week and day keys in the cloud.
String ymdKey(DateTime d) => '${d.year * 10000 + d.month * 100 + d.day}';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "20261019" -> "19 Oct 2026".
String formatWeekId(String id) {
  final n = int.tryParse(id);
  if (n == null || id.length != 8) return id;
  return '${n % 100} ${_monthNames[(n ~/ 100) % 100 - 1]} ${n ~/ 10000}';
}

String formatMinute(int m) {
  final h = m ~/ 60, mm = (m % 60).toString().padLeft(2, '0');
  final h12 = ((h + 11) % 12) + 1;
  return '$h12:$mm ${h >= 12 ? 'pm' : 'am'}';
}

const weekdayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// ---------------- school (Stage 3) ----------------

/// "20261028" -> 28 Oct 2026 (local midnight).
DateTime dateFromYmd(String ymd) {
  final n = int.parse(ymd);
  return DateTime(n ~/ 10000, (n ~/ 100) % 100, n % 100);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Whole days from today to [ymd] (0 = today, 1 = tomorrow, negative = past).
int daysUntil(String ymd, DateTime now) =>
    dateFromYmd(ymd).difference(_day(now)).inHours ~/ 24;

/// When to do homework or revise for a test: the school day before it is
/// due, but never before today.
DateTime defaultWorkDay(DateTime due, DateTime today) {
  final dueDay = _day(due);
  final todayDay = _day(today);
  var d = dueDay.subtract(const Duration(days: 1));
  while (d.weekday > 5) {
    d = d.subtract(const Duration(days: 1));
  }
  if (d.isBefore(todayDay)) d = todayDay.isAfter(dueDay) ? dueDay : todayDay;
  return d;
}

/// The school items that need a task this week, as routine-style tasks.
/// Their ids start with "s_", which the security rules recognise.
List<RoutineTask> schoolTasks(List<SchoolItem> items, String weekId) {
  if (weekId.length != 8) return [];
  final monday = dateFromYmd(weekId);
  final out = <RoutineTask>[];
  for (final item in items.where((i) => i.hasTask)) {
    final days = <int>[
      for (var d = 1; d <= 5; d++)
        if (() {
          final ymd = ymdKey(monday.add(Duration(days: d - 1)));
          return ymd.compareTo(item.fromYmd!) >= 0 &&
              ymd.compareTo(item.toYmd!) <= 0;
        }())
          d,
    ];
    if (days.isEmpty) continue;
    out.add(
      RoutineTask(
        id: item.id,
        title: item.taskTitle,
        category: TaskCategory.study,
        startMin: item.startMin,
        endMin: item.endMin,
        weekdays: days,
        kidIds: [item.kidId],
      ),
    );
  }
  return out;
}

/// Practice sessions for a competition ticked this week.
int practiceTicksThisWeek(Kid kid, SchoolItem item) =>
    kid.checks.keys.where((k) => k.endsWith(':${item.id}')).length;
