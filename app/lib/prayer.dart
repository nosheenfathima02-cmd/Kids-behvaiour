// Prayer times are calculated on the phone. Only the city Mom picks is used;
// the app never reads GPS location.
import 'package:adhan/adhan.dart' as adhan;

import 'logic.dart';
import 'models.dart';

const calculationMethods = <String, String>{
  'muslim_world_league': 'Muslim World League',
  'umm_al_qura': 'Umm al-Qura, Makkah',
  'dubai': 'Gulf region (Dubai)',
  'qatar': 'Qatar',
  'kuwait': 'Kuwait',
  'karachi': 'University of Islamic Sciences, Karachi',
  'egyptian': 'Egyptian General Authority',
  'north_america': 'ISNA (North America)',
  'moon_sighting_committee': 'Moonsighting Committee',
  'singapore': 'Singapore / Malaysia / Indonesia',
  'turkey': 'Diyanet (Turkey)',
};

DayPrayerTimes prayerTimesFor(PrayerSettings s, DateTime date) {
  final method = adhan.CalculationMethod.values.firstWhere(
    (m) => m.name == s.method,
    orElse: () => adhan.CalculationMethod.muslim_world_league,
  );
  final params = method.getParameters()
    ..madhab = s.hanafiAsr ? adhan.Madhab.hanafi : adhan.Madhab.shafi;
  final t = adhan.PrayerTimes(
    adhan.Coordinates(s.latitude, s.longitude),
    adhan.DateComponents.from(date),
    params,
  );
  return DayPrayerTimes(minuteOfDay(t.sunrise), {
    Prayer.fajr: minuteOfDay(t.fajr),
    Prayer.dhuhr: minuteOfDay(t.dhuhr),
    Prayer.asr: minuteOfDay(t.asr),
    Prayer.maghrib: minuteOfDay(t.maghrib),
    Prayer.isha: minuteOfDay(t.isha),
  });
}

/// The next prayer after [minute], or null once Isha has started.
MapEntry<Prayer, int>? nextPrayer(DayPrayerTimes p, int minute) {
  for (final e in p.times.entries) {
    if (e.value > minute) return e;
  }
  return null;
}
