import 'package:flutter/material.dart';

import 'models.dart';

class KidTheme {
  const KidTheme(this.name, this.color);
  final String name;
  final Color color;
}

const kidThemes = <String, KidTheme>{
  'rose': KidTheme('Rose', Color(0xFFC9467E)),
  'ocean': KidTheme('Ocean', Color(0xFF2F78C9)),
  'garden': KidTheme('Garden', Color(0xFF2B8F55)),
  'sunset': KidTheme('Sunset', Color(0xFFD9602A)),
  'galaxy': KidTheme('Galaxy', Color(0xFF6F52D6)),
};

KidTheme themeOf(Kid k) => kidThemes[k.theme] ?? kidThemes['ocean']!;

class Reminder {
  const Reminder(this.text, this.source);
  final String text;
  final String source;
}

const dailyReminders = <Reminder>[
  Reminder('Indeed, with hardship comes ease.', "Qur'an 94:6"),
  Reminder(
    "The best of you are those who learn the Qur'an and teach it.",
    'Sahih al-Bukhari',
  ),
  Reminder('Your smile for your brother is charity.', "Jami' at-Tirmidhi"),
  Reminder(
    'The strong one is the one who controls himself when angry.',
    'Sahih al-Bukhari',
  ),
  Reminder(
    'Allah does not burden a soul beyond what it can bear.',
    "Qur'an 2:286",
  ),
  Reminder('And speak to people good words.', "Qur'an 2:83"),
  Reminder(
    'The deeds most loved by Allah are the regular ones, even if small.',
    'Sahih al-Bukhari',
  ),
];

Reminder reminderFor(DateTime day) {
  final dayOfYear = day.difference(DateTime(day.year)).inDays;
  return dailyReminders[dayOfYear % dailyReminders.length];
}

const timeOutReasons = [
  'Hitting or pushing',
  'Rude words or shouting',
  'Screen time without asking',
  'Not listening',
  'Refused to get ready',
];

class City {
  const City(this.name, this.lat, this.lng, this.method);
  final String name;
  final double lat;
  final double lng;
  final String method;
}

const cities = <City>[
  City('Makkah', 21.4225, 39.8262, 'umm_al_qura'),
  City('Madinah', 24.4672, 39.6024, 'umm_al_qura'),
  City('Riyadh', 24.7136, 46.6753, 'umm_al_qura'),
  City('Jeddah', 21.5433, 39.1728, 'umm_al_qura'),
  City('Dubai', 25.2048, 55.2708, 'dubai'),
  City('Abu Dhabi', 24.4539, 54.3773, 'dubai'),
  City('Sharjah', 25.3463, 55.4209, 'dubai'),
  City('Doha', 25.2854, 51.5310, 'qatar'),
  City('Kuwait City', 29.3759, 47.9774, 'kuwait'),
  City('Manama', 26.2285, 50.5860, 'dubai'),
  City('Muscat', 23.5880, 58.3829, 'dubai'),
  City('Karachi', 24.8607, 67.0011, 'karachi'),
  City('Lahore', 31.5204, 74.3587, 'karachi'),
  City('Islamabad', 33.6844, 73.0479, 'karachi'),
  City('Hyderabad (India)', 17.3850, 78.4867, 'karachi'),
  City('Chennai', 13.0827, 80.2707, 'karachi'),
  City('Bengaluru', 12.9716, 77.5946, 'karachi'),
  City('Mumbai', 19.0760, 72.8777, 'karachi'),
  City('Delhi', 28.6139, 77.2090, 'karachi'),
  City('Dhaka', 23.8103, 90.4125, 'karachi'),
  City('Kuala Lumpur', 3.1390, 101.6869, 'singapore'),
  City('Singapore', 1.3521, 103.8198, 'singapore'),
  City('Jakarta', -6.2088, 106.8456, 'singapore'),
  City('Istanbul', 41.0082, 28.9784, 'turkey'),
  City('Cairo', 30.0444, 31.2357, 'egyptian'),
  City('London', 51.5074, -0.1278, 'moon_sighting_committee'),
  City('Birmingham', 52.4862, -1.8904, 'moon_sighting_committee'),
  City('Toronto', 43.6532, -79.3832, 'north_america'),
  City('New York', 40.7128, -74.0060, 'north_america'),
  City('Chicago', 41.8781, -87.6298, 'north_america'),
  City('Houston', 29.7604, -95.3698, 'north_america'),
  City('Sydney', -33.8688, 151.2093, 'muslim_world_league'),
];

/// The routine a new family starts with. Mom can change all of it.
List<RoutineTask> defaultRoutine() {
  int m(int h, int min) => h * 60 + min;
  RoutineTask t(String id, String title, TaskCategory c, int s, int e) =>
      RoutineTask(id: id, title: title, category: c, startMin: s, endMin: e);
  RoutineTask p(String id, String title, Prayer pr) => RoutineTask(
    id: id,
    title: title,
    category: TaskCategory.salah,
    prayer: pr,
  );
  return [
    t('wake', 'Wake up by 6:00 am', TaskCategory.morning, m(5, 0), m(6, 15)),
    p('fajr', 'Pray Fajr', Prayer.fajr),
    t(
      'bag',
      'Pack school bag & uniform',
      TaskCategory.chores,
      m(6, 0),
      m(7, 15),
    ),
    t(
      'breakfast',
      'Healthy breakfast',
      TaskCategory.health,
      m(6, 15),
      m(7, 30),
    ),
    p('dhuhr', 'Pray Dhuhr (at school)', Prayer.dhuhr),
    p('asr', 'Pray Asr', Prayer.asr),
    t('homework', 'Homework', TaskCategory.study, m(15, 30), m(18, 30)),
    t(
      'quran',
      "Qur'an: memorise 1 ayah",
      TaskCategory.quran,
      m(16, 0),
      m(19, 0),
    ),
    t('room', 'Tidy room & toys', TaskCategory.chores, m(17, 0), m(19, 0)),
    p('maghrib', 'Pray Maghrib', Prayer.maghrib),
    t(
      'revise',
      "Revise today's lessons (20 min)",
      TaskCategory.study,
      m(18, 0),
      m(19, 30),
    ),
    t(
      'veg',
      'Fruit or veggies with dinner',
      TaskCategory.health,
      m(18, 30),
      m(20, 0),
    ),
    p('isha', 'Pray Isha', Prayer.isha),
    t(
      'screen',
      'Screen time 1 hour or less',
      TaskCategory.screen,
      m(19, 30),
      m(20, 30),
    ),
    t('bed', 'In bed by 8:30 pm', TaskCategory.sleep, m(20, 0), m(20, 45)),
    RoutineTask(
      id: 'fast',
      title: 'Sunnah fast (optional bonus star)',
      category: TaskCategory.fast,
      startMin: m(4, 0),
      endMin: m(19, 0),
      weekdays: const [1, 4],
      bonus: true,
    ),
  ];
}

List<Reward> defaultRewards() => [
  Reward('Picnic at the park', 10),
  Reward('Pick Friday dinner', 8),
  Reward('Extra 30 min weekend play', 6),
];

IconData iconFor(TaskCategory c) => switch (c) {
  TaskCategory.salah => Icons.mosque_outlined,
  TaskCategory.morning => Icons.wb_twilight,
  TaskCategory.study => Icons.school_outlined,
  TaskCategory.quran => Icons.menu_book_outlined,
  TaskCategory.chores => Icons.cleaning_services_outlined,
  TaskCategory.health => Icons.restaurant_outlined,
  TaskCategory.screen => Icons.tv_outlined,
  TaskCategory.sleep => Icons.bedtime_outlined,
  TaskCategory.fast => Icons.nightlight_outlined,
};
