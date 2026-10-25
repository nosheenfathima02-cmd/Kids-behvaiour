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

import 'models.dart';
import 'prayer.dart';

/// Build with `--dart-define=ADHAN_SOUND=true` once the adhan recording is
/// added (android/app/src/main/res/raw/adhan.mp3 and ios/Runner/adhan.caf,
/// at most 30 seconds on iPhone). Without it the normal notification sound plays.
const adhanSoundBundled = bool.fromEnvironment('ADHAN_SOUND');

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
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    return _ready;
  }

  /// Schedules prayer reminders for today and the next two days. Called
  /// again every day the app opens, so it never runs out.
  static Future<void> schedulePrayers(
    PrayerSettings settings, {
    required bool enabled,
    List<ScheduledReminder> reminders = const [],
  }) async {
    if (!await _init()) return;
    await _plugin.cancelAll();
    var reminderId = 100;
    for (final r in reminders.take(20)) {
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

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        adhanSoundBundled ? 'adhan' : 'salah',
        'Salah times',
        channelDescription: 'A reminder when each prayer time begins',
        importance: Importance.high,
        priority: Priority.high,
        sound: adhanSoundBundled
            ? const RawResourceAndroidNotificationSound('adhan')
            : null,
      ),
      iOS: DarwinNotificationDetails(
        sound: adhanSoundBundled ? 'adhan.caf' : null,
      ),
    );

    final now = tz.TZDateTime.now(tz.local);
    var id = 0;
    for (var day = 0; day < 3; day++) {
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
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: "It's time for ${e.key.label}",
          body: 'Hayya ʿalaṣ-ṣalāh. Come to prayer!',
        );
      }
    }
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
