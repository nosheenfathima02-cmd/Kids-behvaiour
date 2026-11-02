// Reminders on this phone: a notification at each prayer time, and (on a
// parent's phone) push notifications when a child ticks a task.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:shared_preferences/shared_preferences.dart';

import 'logic.dart';
import 'models.dart';
import 'prayer.dart';

/// Set by the APK build when app/assets/audio/adhan.mp3 (Dhuhr, Asr, Maghrib,
/// Isha) and/or adhan_fajr.mp3 (with "as-salatu khayrun min an-nawm") are in
/// the repository. Without them the normal notification sound plays.
const adhanSoundBundled = bool.fromEnvironment('ADHAN_SOUND');
const fajrAdhanBundled = bool.fromEnvironment('ADHAN_FAJR');

/// The adhan file for in-app playback, preferring the regular one.
String? get adhanAsset => adhanSoundBundled
    ? 'assets/audio/adhan.mp3'
    : fajrAdhanBundled
    ? 'assets/audio/adhan_fajr.mp3'
    : null;

/// A one-off reminder, e.g. the evening before a test.
class ScheduledReminder {
  const ScheduledReminder(this.at, this.title, this.body);
  final DateTime at;
  final String title;
  final String body;
}

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> _init() async {
    if (_ready) return true;
    if (!_supported) return false;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    return _ready;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether Android lets this app ring at the exact minute. Without it,
  /// Android may hold the adhan back for many minutes to save battery.
  static Future<bool> canRingOnTime() async {
    if (!await _init()) return true;
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  /// Opens Android's "Alarms & reminders" page for this app.
  static Future<bool> allowRingingOnTime() async {
    if (!await _init()) return true;
    await _android?.requestExactAlarmsPermission();
    return canRingOnTime();
  }

  static Future<AndroidScheduleMode> _mode() async => await canRingOnTime()
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  // Android fixes a channel's sound when it is created, so each sound has
  // its own channel. The adhan plays at alarm volume (like an alarm clock),
  // so a low notification volume or silent mode does not hide it.
  static NotificationDetails _prayerDetails(bool fajr) {
    final sound = fajr
        ? (fajrAdhanBundled ? 'adhan_fajr' : null)
        : (adhanSoundBundled ? 'adhan' : null);
    final channel = sound == null
        ? 'salah'
        : (fajr ? 'adhan_fajr_alarm' : 'adhan_alarm');
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        sound == null ? 'Salah times' : (fajr ? 'Fajr adhan' : 'Adhan'),
        channelDescription: 'The adhan when each prayer time begins',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: sound == null
            ? AudioAttributesUsage.notification
            : AudioAttributesUsage.alarm,
        sound: sound == null
            ? null
            : RawResourceAndroidNotificationSound(sound),
      ),
      iOS: DarwinNotificationDetails(
        sound: sound == null ? null : '$sound.caf',
      ),
    );
  }

  /// Plays the adhan reminder a minute from now, so a parent can check that
  /// it works with the phone locked.
  static Future<bool> testAdhan() async {
    if (!await _init()) return false;
    await _plugin.zonedSchedule(
      id: 99,
      scheduledDate: tz.TZDateTime.now(tz.local)
          .add(const Duration(minutes: 1)),
      notificationDetails: _prayerDetails(false),
      androidScheduleMode: await _mode(),
      title: 'Adhan test',
      body: 'This is how the adhan will sound at each prayer time.',
    );
    return true;
  }

  /// Schedules prayer reminders for today and the next six days. Called
  /// again every day the app opens, so it keeps going even if the app is
  /// not opened for several days.
  static Future<void> schedulePrayers(
    PrayerSettings settings, {
    required bool enabled,
    List<ScheduledReminder> reminders = const [],
  }) async {
    if (!await _init()) return;
    await _plugin.cancelAll();
    // Channels from earlier versions played at notification volume.
    for (final old in ['adhan', 'adhan_fajr']) {
      await _android?.deleteNotificationChannel(channelId: old);
    }
    final mode = await _mode();
    var reminderId = 100;
    for (final r in reminders.take(40)) {
      await _plugin.zonedSchedule(
        id: reminderId++,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'school',
            'School reminders',
            channelDescription: 'Tests and competitions',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
    if (!enabled) return;

    final regular = _prayerDetails(false);
    // The regular adhan lacks "as-salatu khayrun min an-nawm", so Fajr keeps
    // the plain sound until a Fajr recording is added.
    final fajr = _prayerDetails(true);

    final now = tz.TZDateTime.now(tz.local);
    var id = 0;
    for (var day = 0; day < 7; day++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: day));
      final times = prayerTimesFor(settings, date);
      for (final e in times.times.entries) {
        final at = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          e.value ~/ 60,
          e.value % 60,
        );
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: at,
          notificationDetails: e.key == Prayer.fajr ? fajr : regular,
          androidScheduleMode: mode,
          title: "It's time for ${e.key.label}",
          body: 'Hayya ʿalaṣ-ṣalāh. Come to prayer!',
        );
      }
    }
  }

  /// Shows a notification for each teacher announcement this phone has not
  /// shown before (posted in the last 2 days, so old ones never pile up).
  static Future<void> announceNotices(
    List<SchoolItem> notices,
    String Function(String kidId) kidName,
  ) async {
    if (!await _init()) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList('seen_notices') ?? const []).toSet();
    final now = DateTime.now();
    var id = 900;
    for (final n in notices) {
      if (seen.contains(n.id)) continue;
      if (now.difference(dateFromYmd(n.dueYmd)).inDays <= 2) {
        final name = kidName(n.kidId);
        await _plugin.show(
          id: id++,
          title:
              '📣 ${n.subject.isEmpty ? 'Teacher' : n.subject}${name.isEmpty ? '' : ' · $name'}',
          body: n.details.isEmpty ? n.title : n.details,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'announcements',
              'Teacher announcements',
              channelDescription: 'New announcements from Google Classroom',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(''),
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
      seen.add(n.id);
    }
    final keep = seen.toList();
    await prefs.setStringList(
      'seen_notices',
      keep.length > 200 ? keep.sublist(keep.length - 200) : keep,
    );
  }

  /// Saves this phone's push token so the parents hear when a child ticks a
  /// task. Needs the optional Cloud Function (see README).
  static Future<void> registerParentPhone(
    DocumentReference<Map<String, dynamic>> family,
    String uid,
  ) async {
    if (!_supported) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      Future<void> save(String? token) async {
        if (token == null) return;
        await family.collection('parentTokens').doc(token).set({
          'uid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await save(await messaging.getToken());
      messaging.onTokenRefresh.listen(save);
    } catch (e) {
      debugPrint('Push notifications unavailable: $e');
    }
  }
}
