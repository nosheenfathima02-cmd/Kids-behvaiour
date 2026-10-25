// Data saved for one family. Stage 1 keeps it on the phone; Stage 2 moves
// the same shapes into Firestore.

enum TaskCategory {
  salah,
  morning,
  study,
  quran,
  chores,
  health,
  screen,
  sleep,
  fast,
}

enum Prayer { fajr, dhuhr, asr, maghrib, isha }

extension PrayerName on Prayer {
  String get label => const ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'][index];
}

extension CategoryLabel on TaskCategory {
  String get label => const [
    'Salah',
    'Morning',
    'Study',
    "Qur'an",
    'Chores',
    'Healthy eating',
    'Screen time',
    'Sleep',
    'Fasting',
  ][index];
}

/// Who marked a task done.
enum DoneBy { kid, mom }

/// Firestore can hand back nested maps typed loosely, especially on the web.
Map<String, dynamic> asMap(Object? o) => (o as Map).cast<String, dynamic>();

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

class RoutineTask {
  RoutineTask({
    required this.id,
    required this.title,
    required this.category,
    this.startMin = 0,
    this.endMin = 0,
    this.prayer,
    List<int>? weekdays,
    this.kidIds,
    this.bonus = false,
  }) : weekdays = weekdays ?? const [1, 2, 3, 4, 5];

  final String id;
  String title;
  TaskCategory category;

  /// Minutes after midnight. Ignored when [prayer] is set: the window then
  /// follows that day's prayer time.
  int startMin;
  int endMin;
  Prayer? prayer;

  /// 1 = Monday … 5 = Friday.
  List<int> weekdays;

  /// null means every child.
  List<String>? kidIds;

  /// Optional extra (e.g. sunnah fast): adds a bonus star, never counts against the day.
  bool bonus;

  bool appliesTo(String kidId, int weekday) =>
      weekdays.contains(weekday) && (kidIds == null || kidIds!.contains(kidId));

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category.name,
    'startMin': startMin,
    'endMin': endMin,
    'prayer': prayer?.name,
    'weekdays': weekdays,
    'kidIds': kidIds,
    'bonus': bonus,
  };

  factory RoutineTask.fromJson(Map<String, dynamic> j) => RoutineTask(
    id: j['id'] as String,
    title: j['title'] as String,
    category: _enumByName(
      TaskCategory.values,
      j['category'],
      TaskCategory.chores,
    ),
    startMin: j['startMin'] as int? ?? 0,
    endMin: j['endMin'] as int? ?? 0,
    prayer: j['prayer'] == null
        ? null
        : _enumByName(Prayer.values, j['prayer'], Prayer.fajr),
    weekdays: (j['weekdays'] as List?)?.cast<int>(),
    kidIds: (j['kidIds'] as List?)?.cast<String>(),
    bonus: j['bonus'] as bool? ?? false,
  );
}

class Reward {
  Reward(this.name, this.stars);
  String name;
  int stars;

  Map<String, dynamic> toJson() => {'name': name, 'stars': stars};
  factory Reward.fromJson(Map<String, dynamic> j) =>
      Reward(j['name'] as String, j['stars'] as int);
}

class TimeOut {
  TimeOut({required this.weekday, required this.minute, required this.reason});
  final int weekday;
  final int minute;
  final String reason;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'minute': minute,
    'reason': reason,
  };
  factory TimeOut.fromJson(Map<String, dynamic> j) => TimeOut(
    weekday: j['weekday'] as int,
    minute: j['minute'] as int,
    reason: j['reason'] as String,
  );
}

class Kid {
  Kid({
    required this.id,
    required this.name,
    required this.age,
    this.theme = 'ocean',
    this.examMode = false,
    this.surahName = 'Al-Ikhlas (112)',
    this.ayahDone = 0,
    this.ayahTotal = 4,
    List<Reward>? rewards,
    this.wishIndex,
    Map<String, DoneBy>? checks,
    List<TimeOut>? timeouts,
  }) : rewards = rewards ?? [],
       checks = checks ?? {},
       timeouts = timeouts ?? [];

  final String id;
  String name;
  int age;
  String theme;
  bool examMode;

  // Qur'an memorisation goal for this week.
  String surahName;
  int ayahDone;
  int ayahTotal;

  List<Reward> rewards;
  int? wishIndex;

  // This week only. Key is "<weekday>:<taskId>".
  Map<String, DoneBy> checks;
  List<TimeOut> timeouts;

  static String key(int weekday, String taskId) => '$weekday:$taskId';

  void clearWeek() {
    checks.clear();
    timeouts.clear();
    wishIndex = null;
    ayahDone = 0;
  }

  void copyProfileFrom(Kid o) {
    name = o.name;
    age = o.age;
    theme = o.theme;
    examMode = o.examMode;
    surahName = o.surahName;
    ayahDone = o.ayahDone;
    ayahTotal = o.ayahTotal;
    rewards = o.rewards;
  }

  /// The fields that stay from week to week (families/{fid}/kids/{id}).
  Map<String, dynamic> profileJson() => toJson()
    ..removeWhere(
      (k, _) => const {'id', 'checks', 'timeouts', 'wishIndex'}.contains(k),
    );

  /// Load this week's ticks, time-outs and reward pick (families/{fid}/weeks/{weekId}_{id}).
  void applyWeek(Map<String, dynamic>? week) {
    final w = Kid.fromJson({'id': id, 'name': name, 'age': age, ...?week});
    checks = w.checks;
    timeouts = w.timeouts;
    wishIndex = w.wishIndex;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'age': age,
    'theme': theme,
    'examMode': examMode,
    'surahName': surahName,
    'ayahDone': ayahDone,
    'ayahTotal': ayahTotal,
    'rewards': rewards.map((r) => r.toJson()).toList(),
    'wishIndex': wishIndex,
    'checks': checks.map((k, v) => MapEntry(k, v.name)),
    'timeouts': timeouts.map((t) => t.toJson()).toList(),
  };

  factory Kid.fromJson(Map<String, dynamic> j) => Kid(
    id: j['id'] as String,
    name: j['name'] as String,
    age: j['age'] as int,
    theme: j['theme'] as String? ?? 'ocean',
    examMode: j['examMode'] as bool? ?? false,
    surahName: j['surahName'] as String? ?? '',
    ayahDone: j['ayahDone'] as int? ?? 0,
    ayahTotal: j['ayahTotal'] as int? ?? 1,
    rewards: ((j['rewards'] as List?) ?? [])
        .map((e) => Reward.fromJson(asMap(e)))
        .toList(),
    wishIndex: j['wishIndex'] as int?,
    checks: ((j['checks'] as Map?) ?? {}).map(
      (k, v) =>
          MapEntry(k as String, _enumByName(DoneBy.values, v, DoneBy.kid)),
    ),
    timeouts: ((j['timeouts'] as List?) ?? [])
        .map((e) => TimeOut.fromJson(asMap(e)))
        .toList(),
  );
}

class PrayerSettings {
  PrayerSettings({
    this.city = 'Dubai',
    this.latitude = 25.2048,
    this.longitude = 55.2708,
    this.method = 'dubai',
    this.hanafiAsr = false,
  });
  String city;
  double latitude;
  double longitude;
  String method;
  bool hanafiAsr;

  Map<String, dynamic> toJson() => {
    'city': city,
    'latitude': latitude,
    'longitude': longitude,
    'method': method,
    'hanafiAsr': hanafiAsr,
  };
  factory PrayerSettings.fromJson(Map<String, dynamic> j) => PrayerSettings(
    city: j['city'] as String,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    method: j['method'] as String,
    hanafiAsr: j['hanafiAsr'] as bool? ?? false,
  );
}

/// Result of a finished week, kept so Mom can look back.
class WeekSummary {
  WeekSummary(this.weekId, this.starsByKid);
  final String weekId;
  final Map<String, int> starsByKid;

  Map<String, dynamic> toJson() => {'weekId': weekId, 'starsByKid': starsByKid};
  factory WeekSummary.fromJson(Map<String, dynamic> j) => WeekSummary(
    j['weekId'] as String,
    (j['starsByKid'] as Map).cast<String, int>(),
  );
}

class FamilyData {
  FamilyData({
    required this.id,
    required this.parents,
    required this.prayer,
    required this.kids,
    required this.routine,
    required this.weekId,
    List<WeekSummary>? history,
    this.adhanEnabled = true,
    this.tzOffsetMin = 0,
    Map<String, List<int>>? prayerWindows,
  }) : history = history ?? [],
       prayerWindows = prayerWindows ?? {};

  /// Firestore document id of the family.
  final String id;
  List<String> parents;
  PrayerSettings prayer;
  List<Kid> kids;
  List<RoutineTask> routine;
  String weekId;
  List<WeekSummary> history;
  bool adhanEnabled;

  /// Minutes from UTC of the family's time zone; the security rules use it.
  int tzOffsetMin;

  /// "20261026" -> [fajr start, fajr end, dhuhr start, ... isha end] in
  /// minutes. Written ahead by the parent's phone so the security rules can
  /// check salah ticks without doing astronomy.
  Map<String, List<int>> prayerWindows;

  /// Fields stored on families/{id}. Kids and weeks live in sub-collections.
  Map<String, dynamic> toDoc() => {
    'parents': parents,
    'prayer': prayer.toJson(),
    'routine': {for (final t in routine) t.id: t.toJson()},
    'weekId': weekId,
    'history': history.map((h) => h.toJson()).toList(),
    'adhanEnabled': adhanEnabled,
    'tzOffsetMin': tzOffsetMin,
    'prayerWindows': prayerWindows,
  };

  factory FamilyData.fromDoc(
    String id,
    Map<String, dynamic> j,
    List<Kid> kids,
  ) => FamilyData(
    id: id,
    parents: ((j['parents'] as List?) ?? []).cast<String>(),
    prayer: j['prayer'] == null
        ? PrayerSettings()
        : PrayerSettings.fromJson((j['prayer'] as Map).cast<String, dynamic>()),
    kids: kids,
    routine: ((j['routine'] as Map?) ?? {}).values
        .map((e) => RoutineTask.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    weekId: j['weekId'] as String? ?? '',
    history: ((j['history'] as List?) ?? [])
        .map((e) => WeekSummary.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    adhanEnabled: j['adhanEnabled'] as bool? ?? true,
    tzOffsetMin: (j['tzOffsetMin'] as num?)?.toInt() ?? 0,
    prayerWindows: ((j['prayerWindows'] as Map?) ?? {}).map(
      (k, v) => MapEntry(
        k as String,
        (v as List).map((e) => (e as num).toInt()).toList(),
      ),
    ),
  );
}
