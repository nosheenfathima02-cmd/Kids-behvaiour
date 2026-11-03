import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/hijri.dart';

void main() {
  test('Islamic dates match the calendar (within a day)', () {
    // 1 Ramadan 1447 was 18 or 19 February 2026.
    final r = toHijri(DateTime(2026, 2, 19));
    expect(r.year, 1447);
    expect(r.month, 9);
    expect(r.day, inInclusiveRange(1, 2));
    // 1 Muharram 1448 was about 16 June 2026.
    final m = toHijri(DateTime(2026, 6, 17));
    expect(m.year, 1448);
    expect(m.month, 1);
    expect(m.day, inInclusiveRange(1, 2));
  });

  test('the next Ramadan is found', () {
    final start = nextRamadanStart(DateTime(2026, 11, 3));
    expect(start.year, 2027);
    expect(start.month, 2);
    expect(start.day, inInclusiveRange(7, 9));
    expect(toHijri(start).isRamadan, isTrue);
  });

  test(
    'sunnah fasts: Mondays, Thursdays and the white days, never in Ramadan',
    () {
      final fasts = nextSunnahFasts(DateTime(2026, 11, 2), count: 8);
      expect(fasts.length, 8);
      for (final (day, why) in fasts) {
        expect(toHijri(day).isRamadan, isFalse);
        expect(
          day.weekday == DateTime.monday ||
              day.weekday == DateTime.thursday ||
              why.startsWith('White day'),
          isTrue,
        );
      }
      final inRamadan = nextSunnahFasts(DateTime(2027, 2, 10), count: 3);
      expect(inRamadan.every((f) => !toHijri(f.$1).isRamadan), isTrue);
    },
  );
}
