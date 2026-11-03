// Islamic (Hijri) dates by the tabular calendar. It can differ by a day
// from the moon sighting in your country, so the app says "about".

const hijriMonths = [
  'Muharram',
  'Safar',
  "Rabi' al-Awwal",
  "Rabi' al-Thani",
  'Jumada al-Ula',
  'Jumada al-Akhirah',
  'Rajab',
  "Sha'ban",
  'Ramadan',
  'Shawwal',
  "Dhu al-Qa'dah",
  'Dhu al-Hijjah',
];

class HijriDate {
  const HijriDate(this.year, this.month, this.day);
  final int year;
  final int month; // 1 = Muharram, 9 = Ramadan
  final int day;

  bool get isRamadan => month == 9;
  String get monthName => hijriMonths[month - 1];

  @override
  String toString() => '$day $monthName $year';
}

int _julianDay(DateTime d) {
  final a = (14 - d.month) ~/ 12;
  final y = d.year + 4800 - a;
  final m = d.month + 12 * a - 3;
  return d.day +
      (153 * m + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}

HijriDate toHijri(DateTime date) {
  var l = _julianDay(date) - 1948440 + 10632;
  final n = (l - 1) ~/ 10631;
  l = l - 10631 * n + 354;
  final j =
      ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
      (l ~/ 5670) * ((43 * l) ~/ 15238);
  l =
      l -
      ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
      (j ~/ 16) * ((15238 * j) ~/ 43) +
      29;
  final month = (24 * l) ~/ 709;
  final day = l - (709 * month) ~/ 24;
  final year = 30 * n + j - 30;
  return HijriDate(year, month, day);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The first day of the next Ramadan (today if Ramadan starts today).
DateTime nextRamadanStart(DateTime from) {
  var d = _day(from);
  for (var i = 0; i < 400; i++) {
    final h = toHijri(d);
    if (h.isRamadan && h.day == 1) return d;
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// Sunnah fasting days coming up: Mondays, Thursdays and the "white days"
/// (13th, 14th and 15th of each Islamic month), not in Ramadan or on Eid.
List<(DateTime, String)> nextSunnahFasts(DateTime from, {int count = 5}) {
  final out = <(DateTime, String)>[];
  var d = _day(from);
  while (out.length < count) {
    final h = toHijri(d);
    final eid =
        (h.month == 10 && h.day == 1) ||
        (h.month == 12 && h.day >= 10 && h.day <= 13);
    if (!h.isRamadan && !eid) {
      if (h.day >= 13 && h.day <= 15) {
        out.add((d, 'White day (${h.day} ${h.monthName})'));
      } else if (d.weekday == DateTime.monday) {
        out.add((d, 'Monday'));
      } else if (d.weekday == DateTime.thursday) {
        out.add((d, 'Thursday'));
      }
    }
    d = d.add(const Duration(days: 1));
  }
  return out;
}
