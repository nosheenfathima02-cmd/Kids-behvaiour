import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content.dart';
import 'logic.dart';
import 'models.dart';
import 'notifications.dart';
import 'prayer.dart';

/// Where the app is in its start-up and sign-in flow.
enum Phase {
  /// Waiting for the first data from the cloud.
  loading,

  /// Nobody is signed in: "I'm a parent" or "Link this child's device".
  welcome,

  /// A parent is signed in but has no family yet.
  parentNeedsFamily,

  /// A parent's family exists but this phone has no parent PIN yet.
  parentNeedsPin,

  ready,

  /// Mom removed this child's device from the family.
  deviceUnlinked,
}

enum Role { parent, device }

class LinkedDevice {
  LinkedDevice(this.uid, this.name, this.kidIds, this.pairedAt, this.pairCode);
  final String uid;
  final String name;
  final List<String> kidIds;
  final DateTime? pairedAt;
  final String pairCode;
}

class PairingCode {
  PairingCode(this.code, this.expiresAt);
  final String code;
  final DateTime expiresAt;

  /// What the QR code contains.
  String get qrData => 'supermom:$code';
}

/// Holds the family's data, keeps it in sync with Firestore, and resets the week.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this.db, this.auth, this.clock);

  static const _roleKey = 'role';
  static const _familyKey = 'family_id';
  static const _pinKey = 'pin_hash';
  static const _kidsModeKey = 'kids_mode';

  final SharedPreferences _prefs;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final DateTime Function() clock;

  Phase phase = Phase.loading;
  Role? role;
  String? familyId;
  FamilyData? data;

  /// Linked children's devices (parent only).
  List<LinkedDevice> devices = [];

  /// The kids this device may act for (child device only).
  List<String> deviceKidIds = [];
  String deviceName = '';

  /// Last error to show to the user once (e.g. a rejected tick).
  final ValueNotifier<String?> errors = ValueNotifier(null);

  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, StreamSubscription<Object?>> _kidSubs = {};
  final Map<String, Kid> _kids = {};
  final Map<String, Map<String, dynamic>?> _weeks = {};
  Map<String, dynamic>? _familyDoc;
  String _listeningWeek = '';
  Timer? _ticker;
  String _maintainedDay = '';
  String _scheduledFor = '';

  static Future<AppStore> load({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    DateTime Function()? clock,
  }) async {
    final store = AppStore._(
      await SharedPreferences.getInstance(),
      db ?? FirebaseFirestore.instance,
      auth ?? FirebaseAuth.instance,
      clock ?? DateTime.now,
    );
    await store._start();
    return store;
  }

  Future<void> _start() async {
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
    final user = auth.currentUser;
    final savedRole = _prefs.getString(_roleKey);
    familyId = _prefs.getString(_familyKey);
    if (user != null && savedRole == Role.device.name && familyId != null) {
      role = Role.device;
      _listenAsDevice();
    } else if (user != null && !user.isAnonymous) {
      await _afterParentSignIn();
    } else {
      _setPhase(Phase.welcome);
    }
  }

  // ---------------- convenience used by the screens ----------------

  bool get isSetUp => phase == Phase.ready && data != null;
  FamilyData get family => data!;
  bool get isParent => role == Role.parent;

  DateTime get now => clock();
  int get todayWeekday => now.weekday;
  int get nowMinute => minuteOfDay(now);
  bool get isWeekend => todayWeekday > 5;
  String get currentWeekId => weekIdFor(now);
  DayPrayerTimes get prayersToday => prayerTimesFor(family.prayer, now);

  /// The kids this app shows: all of them for a parent, the linked ones on a child's device.
  List<Kid> get visibleKids => isParent
      ? family.kids
      : family.kids.where((k) => deviceKidIds.contains(k.id)).toList();

  Kid? kidById(String id) => family.kids.where((k) => k.id == id).firstOrNull;

  List<RoutineTask> tasksForDay(Kid kid, int weekday) =>
      tasksFor(kid, family.routine, weekday, prayersToday);
  TaskStatus status(Kid kid, RoutineTask t, int weekday) =>
      statusOf(kid, t, weekday, todayWeekday, nowMinute, prayersToday);
  bool canKidToggle(Kid kid, RoutineTask t) =>
      kidCanToggle(kid, t, todayWeekday, todayWeekday, nowMinute, prayersToday);
  WeekScore score(Kid kid) =>
      weekScore(kid, family.routine, todayWeekday, prayersToday);
  int starsForDay(Kid kid, int weekday) =>
      dayStars(kid, family.routine, weekday, todayWeekday, prayersToday);
  TimeWindow window(RoutineTask t) => windowOf(t, prayersToday);

  DocumentReference<Map<String, dynamic>> get _familyRef =>
      db.collection('families').doc(familyId);
  DocumentReference<Map<String, dynamic>> _weekRef(
    String kidId, [
    String? weekId,
  ]) => _familyRef.collection('weeks').doc('${weekId ?? currentWeekId}_$kidId');

  // ---------------- parent sign-in & setup ----------------

  Future<void> signInWithGoogle() => _signInWith(GoogleAuthProvider());
  Future<void> signInWithApple() => _signInWith(AppleAuthProvider());

  Future<void> _signInWith(AuthProvider provider) async {
    if (kIsWeb) {
      await auth.signInWithPopup(provider);
    } else {
      await auth.signInWithProvider(provider);
    }
    await _afterParentSignIn();
  }

  Future<void> signInWithEmail(
    String email,
    String password, {
    required bool newAccount,
  }) async {
    if (newAccount) {
      await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } else {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    }
    await _afterParentSignIn();
  }

  Future<void> _afterParentSignIn() async {
    final user = auth.currentUser!;
    role = Role.parent;
    await _prefs.setString(_roleKey, Role.parent.name);
    final found = await db
        .collection('families')
        .where('parents', arrayContains: user.uid)
        .limit(1)
        .get();
    if (found.docs.isEmpty) {
      _setPhase(Phase.parentNeedsFamily);
      return;
    }
    familyId = found.docs.first.id;
    await _prefs.setString(_familyKey, familyId!);
    _listenAsParent();
  }

  Future<void> createFamily({
    required String pin,
    required City city,
    required String kidName,
    required int kidAge,
    required String theme,
  }) async {
    final uid = auth.currentUser!.uid;
    final ref = db.collection('families').doc();
    final family = FamilyData(
      id: ref.id,
      parents: [uid],
      prayer: PrayerSettings(
        city: city.name,
        latitude: city.lat,
        longitude: city.lng,
        method: city.method,
      ),
      kids: [],
      routine: defaultRoutine(),
      weekId: currentWeekId,
      tzOffsetMin: now.timeZoneOffset.inMinutes,
    );
    family.prayerWindows = _windowsAhead(family.prayer);
    await ref.set(family.toDoc());
    final kid = Kid(
      id: _newId(),
      name: kidName,
      age: kidAge,
      theme: theme,
      rewards: defaultRewards(),
    );
    await ref.collection('kids').doc(kid.id).set(kid.profileJson());
    familyId = ref.id;
    await _prefs.setString(_familyKey, ref.id);
    await _prefs.setString(_pinKey, _hashPin(pin));
    _listenAsParent();
  }

  // ---------------- PIN (protects the parent screens on a shared phone) ----------------

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _newId([int length = 12]) {
    final r = Random.secure();
    return List.generate(length, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  String _hashPin(String pin) {
    final salt = _newId();
    return '$salt\$${_hash(pin, salt)}';
  }

  bool get hasPin => _prefs.getString(_pinKey) != null;

  /// A parent's phone handed to the children: shows the kids' screens until the PIN is entered.
  bool get kidsMode => _prefs.getBool(_kidsModeKey) ?? false;

  Future<void> setKidsMode(bool on) async {
    await _prefs.setBool(_kidsModeKey, on);
    notifyListeners();
  }

  bool checkPin(String pin) {
    final parts = (_prefs.getString(_pinKey) ?? '').split('\$');
    return parts.length == 2 && _hash(pin, parts[0]) == parts[1];
  }

  Future<void> changePin(String pin) async {
    await _prefs.setString(_pinKey, _hashPin(pin));
    if (phase == Phase.parentNeedsPin) _rebuild();
  }

  // ---------------- linking a child's device ----------------

  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Parent: makes a one-time code, valid for 10 minutes, for these kids.
  Future<PairingCode> createPairing(List<String> kidIds) async {
    final r = Random.secure();
    final code = List.generate(
      8,
      (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)],
    ).join();
    final expires = DateTime.now().add(const Duration(minutes: 10));
    await db.collection('pairings').doc(code).set({
      'familyId': familyId,
      'kidIds': kidIds,
      'createdBy': auth.currentUser!.uid,
      'expiresAt': Timestamp.fromDate(expires),
    });
    return PairingCode(code, expires);
  }

  Future<void> cancelPairing(String code) =>
      db.collection('pairings').doc(code).delete();

  /// Child's device: joins the family with the code from Mom's phone.
  /// Returns an error message, or null when linked.
  Future<String?> linkThisDevice(String rawCode, String name) async {
    final code = rawCode
        .trim()
        .toUpperCase()
        .replaceFirst('SUPERMOM:', '')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length != 8) return 'The code has 8 letters and numbers.';
    try {
      if (auth.currentUser == null || !auth.currentUser!.isAnonymous) {
        await auth.signOut();
        await auth.signInAnonymously();
      }
      final uid = auth.currentUser!.uid;
      final pairing = await db.collection('pairings').doc(code).get();
      if (!pairing.exists) {
        return 'This code is not valid. Ask Mom for a new one.';
      }
      final p = pairing.data()!;
      if ((p['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
        return 'This code has expired. Ask Mom for a new one.';
      }
      final fid = p['familyId'] as String;
      final batch = db.batch()
        ..set(db.doc('families/$fid/devices/$uid'), {
          'kidIds': p['kidIds'],
          'name': name.trim().isEmpty ? 'Tablet' : name.trim(),
          'pairCode': code,
          'pairedAt': Timestamp.now(),
        })
        ..delete(pairing.reference);
      await batch.commit();
      familyId = fid;
      role = Role.device;
      await _prefs.setString(_roleKey, Role.device.name);
      await _prefs.setString(_familyKey, fid);
      _listenAsDevice();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'This code is not valid or has expired. Ask Mom for a new one.';
      }
      return 'Could not link: ${e.message ?? e.code}. Check the internet connection.';
    }
  }

  Future<void> unlinkDevice(String uid) =>
      _familyRef.collection('devices').doc(uid).delete();

  Future<void> renameDevice(LinkedDevice d, String name) =>
      _familyRef.collection('devices').doc(d.uid).update({'name': name});

  /// Parent: signs out. Child's device: forgets the family (Mom has to link it again).
  Future<void> signOut() async {
    if (role == Role.device && familyId != null && auth.currentUser != null) {
      try {
        await unlinkDevice(auth.currentUser!.uid);
      } catch (_) {
        // Already unlinked.
      }
    }
    _stopListening();
    await auth.signOut();
    await _prefs.remove(_roleKey);
    await _prefs.remove(_familyKey);
    role = null;
    familyId = null;
    data = null;
    _setPhase(Phase.welcome);
  }

  // ---------------- listening to the cloud ----------------

  void _listenAsParent() {
    _stopListening();
    _setPhase(Phase.loading);
    _subs.add(
      _familyRef.snapshots().listen((s) {
        _familyDoc = s.data();
        _rebuild();
      }, onError: _onListenError),
    );
    _subs.add(
      _familyRef.collection('kids').snapshots().listen((s) {
        final ids = s.docs.map((d) => d.id).toSet();
        _kids.removeWhere((id, _) => !ids.contains(id));
        for (final d in s.docs) {
          _updateKid(d.id, d.data());
        }
        _rebuild();
      }, onError: _onListenError),
    );
    _subs.add(
      _familyRef.collection('devices').snapshots().listen((s) {
        devices = [
          for (final d in s.docs)
            LinkedDevice(
              d.id,
              d.data()['name'] as String? ?? 'Device',
              ((d.data()['kidIds'] as List?) ?? []).cast<String>(),
              (d.data()['pairedAt'] as Timestamp?)?.toDate(),
              d.data()['pairCode'] as String? ?? '',
            ),
        ];
        notifyListeners();
      }, onError: _onListenError),
    );
    _listenToWeeksAsParent();
    Notifications.registerParentPhone(_familyRef, auth.currentUser!.uid);
  }

  void _listenToWeeksAsParent() {
    _listeningWeek = currentWeekId;
    _kidSubs.remove('weeks')?.cancel();
    _kidSubs['weeks'] = _familyRef
        .collection('weeks')
        .where('weekId', isEqualTo: _listeningWeek)
        .snapshots()
        .listen((s) {
          _weeks.clear();
          for (final d in s.docs) {
            _weeks[d.data()['kidId'] as String] = d.data();
          }
          _rebuild();
        }, onError: _onListenError);
  }

  void _listenAsDevice() {
    _stopListening();
    _setPhase(Phase.loading);
    final uid = auth.currentUser!.uid;
    _subs.add(
      _familyRef.collection('devices').doc(uid).snapshots().listen((s) {
        if (!s.exists) {
          _deviceUnlinked();
          return;
        }
        deviceName = s.data()!['name'] as String? ?? '';
        final kidIds = ((s.data()!['kidIds'] as List?) ?? []).cast<String>();
        if (!listEquals(kidIds, deviceKidIds)) {
          deviceKidIds = kidIds;
          _listenToDeviceKids();
        }
        _rebuild();
      }, onError: _onListenError),
    );
    _subs.add(
      _familyRef.snapshots().listen((s) {
        _familyDoc = s.data();
        _rebuild();
      }, onError: _onListenError),
    );
  }

  void _listenToDeviceKids() {
    for (final s in _kidSubs.values) {
      s.cancel();
    }
    _kidSubs.clear();
    _kids.removeWhere((id, _) => !deviceKidIds.contains(id));
    _listeningWeek = currentWeekId;
    for (final id in deviceKidIds) {
      _kidSubs['kid:$id'] = _familyRef
          .collection('kids')
          .doc(id)
          .snapshots()
          .listen((s) {
            if (s.exists) {
              _updateKid(id, s.data()!);
            } else {
              _kids.remove(id);
            }
            _rebuild();
          }, onError: _onListenError);
      _kidSubs['week:$id'] = _weekRef(id, _listeningWeek).snapshots().listen((
        s,
      ) {
        _weeks[id] = s.data();
        _rebuild();
      }, onError: _onListenError);
    }
  }

  void _onListenError(Object e) {
    if (e is FirebaseException &&
        e.code == 'permission-denied' &&
        role == Role.device) {
      _deviceUnlinked();
      return;
    }
    errors.value = 'Could not reach the cloud: $e';
  }

  void _deviceUnlinked() {
    _stopListening();
    _prefs.remove(_roleKey);
    _prefs.remove(_familyKey);
    data = null;
    _setPhase(Phase.deviceUnlinked);
  }

  void _stopListening() {
    for (final s in [..._subs, ..._kidSubs.values]) {
      s.cancel();
    }
    _subs.clear();
    _kidSubs.clear();
    _kids.clear();
    _weeks.clear();
    _familyDoc = null;
    devices = [];
    deviceKidIds = [];
  }

  /// Keeps the same Kid object, so open screens update in place.
  void _updateKid(String id, Map<String, dynamic> profile) {
    final fresh = Kid.fromJson({...profile, 'id': id});
    final kid = _kids.putIfAbsent(id, () => fresh);
    if (!identical(kid, fresh)) kid.copyProfileFrom(fresh);
  }

  void _rebuild() {
    final doc = _familyDoc;
    if (doc == null || familyId == null) return;
    final kids = _kids.values.toList()..sort((a, b) => b.age.compareTo(a.age));
    for (final k in kids) {
      k.applyWeek(_weeks[k.id]);
    }
    data = FamilyData.fromDoc(familyId!, doc, kids);
    if (isParent && !hasPin) {
      _setPhase(Phase.parentNeedsPin);
      return;
    }
    _setPhase(Phase.ready);
    _maintain();
  }

  void _setPhase(Phase p) {
    phase = p;
    notifyListeners();
  }

  void _onTick() {
    if (data == null) return;
    if (_listeningWeek.isNotEmpty && _listeningWeek != currentWeekId) {
      // A new week started while the app was open.
      _weeks.clear();
      if (isParent) {
        _listenToWeeksAsParent();
      } else {
        _listenToDeviceKids();
      }
    }
    _maintain();
    notifyListeners(); // time windows open and close
  }

  /// Daily upkeep: reminders on this device, and (on a parent's phone) the
  /// weekly reset, time zone and salah windows for the security rules.
  void _maintain() {
    final today = ymdKey(now);
    final schedKey =
        '$today|${family.adhanEnabled}|${jsonEncode(family.prayer.toJson())}';
    if (_scheduledFor != schedKey) {
      _scheduledFor = schedKey;
      Notifications.schedulePrayers(
        family.prayer,
        enabled: family.adhanEnabled,
      );
    }
    if (!isParent || _maintainedDay == today) return;
    _maintainedDay = today;
    final updates = <String, Object?>{};
    final offset = now.timeZoneOffset.inMinutes;
    if (family.tzOffsetMin != offset) updates['tzOffsetMin'] = offset;
    final aheadKey = ymdKey(now.add(const Duration(days: 27)));
    if (!family.prayerWindows.containsKey(aheadKey)) {
      updates['prayerWindows'] = _windowsAhead(family.prayer);
    }
    if (updates.isNotEmpty) _write(_familyRef.update(updates));
    if (family.weekId != currentWeekId) _rollWeek();
  }

  Map<String, List<int>> _windowsAhead(PrayerSettings p) {
    final start = DateTime(now.year, now.month, now.day);
    final out = <String, List<int>>{};
    for (var i = 0; i < 35; i++) {
      final day = start.add(Duration(days: i));
      final times = prayerTimesFor(p, day);
      out[ymdKey(day)] = [
        for (final pr in Prayer.values) ...[
          times.windowFor(pr).start,
          times.windowFor(pr).end,
        ],
      ];
    }
    return out;
  }

  // ---------------- writes ----------------

  void _write(Future<void> f) {
    f.catchError((Object e) {
      errors.value = e is FirebaseException && e.code == 'permission-denied'
          ? 'That change was not allowed. The time for it may have closed.'
          : 'Could not save: $e';
    });
  }

  /// Returns false if the window is closed (the button is disabled, but the
  /// rule is checked here and again on the server).
  bool kidToggle(Kid kid, RoutineTask t) {
    if (!canKidToggle(kid, t)) return false;
    final key = Kid.key(todayWeekday, t.id);
    final ref = _weekRef(kid.id);
    if (kid.checks.containsKey(key)) {
      kid.checks.remove(key);
      _write(
        ref.update({
          FieldPath(['checks', key]): FieldValue.delete(),
          'lastChange': key,
        }),
      );
    } else {
      kid.checks[key] = DoneBy.kid;
      _write(
        ref.set({
          'kidId': kid.id,
          'weekId': currentWeekId,
          'checks': {key: DoneBy.kid.name},
          'lastChange': key,
        }, SetOptions(merge: true)),
      );
    }
    notifyListeners();
    return true;
  }

  void pickReward(Kid kid, int index) {
    if (score(kid).total < kid.rewards[index].stars) return;
    kid.wishIndex = index;
    _write(_weekRef(kid.id).update({'wishIndex': index}));
    notifyListeners();
  }

  void momSetDone(Kid kid, RoutineTask t, int weekday, bool done) {
    final key = Kid.key(weekday, t.id);
    final ref = _weekRef(kid.id);
    if (done) {
      kid.checks[key] = DoneBy.mom;
      _write(
        ref.set({
          'kidId': kid.id,
          'weekId': currentWeekId,
          'checks': {key: DoneBy.mom.name},
        }, SetOptions(merge: true)),
      );
    } else {
      kid.checks.remove(key);
      _write(
        ref.update({
          FieldPath(['checks', key]): FieldValue.delete(),
        }),
      );
    }
    notifyListeners();
  }

  void addTimeOut(Kid kid, String reason) {
    final t = TimeOut(
      weekday: todayWeekday.clamp(1, 5),
      minute: nowMinute,
      reason: reason,
    );
    kid.timeouts.add(t);
    _write(
      _weekRef(kid.id).set({
        'kidId': kid.id,
        'weekId': currentWeekId,
        'timeouts': FieldValue.arrayUnion([t.toJson()]),
      }, SetOptions(merge: true)),
    );
    notifyListeners();
  }

  void removeTimeOut(Kid kid, int index) {
    kid.timeouts.removeAt(index);
    _write(
      _weekRef(kid.id)
          .update({'timeouts': kid.timeouts.map((t) => t.toJson()).toList()}),
    );
    notifyListeners();
  }

  Kid addKid(String name, int age, String theme) {
    final kid = Kid(
      id: _newId(),
      name: name,
      age: age,
      theme: theme,
      rewards: defaultRewards(),
    );
    _kids[kid.id] = kid;
    family.kids.add(kid);
    _write(_familyRef.collection('kids').doc(kid.id).set(kid.profileJson()));
    notifyListeners();
    return kid;
  }

  void saveKid(Kid kid) {
    _write(_familyRef.collection('kids').doc(kid.id).set(kid.profileJson()));
    notifyListeners();
  }

  /// Saves the reward pick and reward list together when Mom edits rewards.
  void saveKidRewards(Kid kid) {
    saveKid(kid);
    if (kid.wishIndex == null) {
      _write(
        _weekRef(kid.id).set({
          'kidId': kid.id,
          'weekId': currentWeekId,
          'wishIndex': null,
        }, SetOptions(merge: true)),
      );
    }
  }

  Future<void> removeKid(Kid kid) async {
    final batch = db.batch()
      ..delete(_familyRef.collection('kids').doc(kid.id))
      ..delete(_weekRef(kid.id));
    for (final t in family.routine.where(
      (t) => t.kidIds?.contains(kid.id) ?? false,
    )) {
      t.kidIds!.remove(kid.id);
      batch.update(_familyRef, {
        FieldPath(['routine', t.id]): t.toJson(),
      });
    }
    for (final d in devices.where((d) => d.kidIds.contains(kid.id))) {
      final left = d.kidIds.where((id) => id != kid.id).toList();
      final ref = _familyRef.collection('devices').doc(d.uid);
      left.isEmpty ? batch.delete(ref) : batch.update(ref, {'kidIds': left});
    }
    _kids.remove(kid.id);
    family.kids.remove(kid);
    notifyListeners();
    _write(batch.commit());
  }

  String newTaskId() => _newId();

  void upsertTask(RoutineTask t) {
    _write(
      _familyRef.update({
        FieldPath(['routine', t.id]): t.toJson(),
      }),
    );
  }

  void deleteTask(RoutineTask t) {
    _write(
      _familyRef.update({
        FieldPath(['routine', t.id]): FieldValue.delete(),
      }),
    );
  }

  /// Saves prayer and reminder settings, and recalculates the salah windows.
  void saveSettings() {
    _write(
      _familyRef.update({
        'prayer': family.prayer.toJson(),
        'adhanEnabled': family.adhanEnabled,
        'prayerWindows': _windowsAhead(family.prayer),
      }),
    );
    notifyListeners();
  }

  /// Mom's "start a new week now": keeps a summary, clears ticks and time-outs.
  Future<void> startNewWeek() => _archiveWeek(
    family.weekId.isEmpty ? currentWeekId : family.weekId,
    scoreDay: todayWeekday,
  );

  Future<void> _rollWeek() => _archiveWeek(family.weekId, scoreDay: 7);

  Future<void> _archiveWeek(String oldWeekId, {required int scoreDay}) async {
    final weeks = await _familyRef.collection('weeks').get();
    final oldWeek = {
      for (final d in weeks.docs)
        if (d.data()['weekId'] == oldWeekId)
          d.data()['kidId'] as String: d.data(),
    };
    final summary = <String, int>{};
    for (final k in family.kids) {
      final copy = Kid.fromJson({
        ...k.toJson(),
        'checks': null,
        'timeouts': null,
      })..applyWeek(oldWeek[k.id]);
      summary[k.name] = weekScore(
        copy,
        family.routine,
        scoreDay,
        prayersToday,
      ).total;
    }
    final history = [
      WeekSummary(oldWeekId, summary),
      ...family.history,
    ].take(12).toList();
    final batch = db.batch()
      ..update(_familyRef, {
        'weekId': currentWeekId,
        'history': history.map((h) => h.toJson()).toList(),
      });
    for (final d in weeks.docs) {
      final stale = d.data()['weekId'] != currentWeekId || scoreDay != 7;
      if (stale) batch.delete(d.reference);
    }
    for (final k in family.kids) {
      batch.update(_familyRef.collection('kids').doc(k.id), {'ayahDone': 0});
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopListening();
    super.dispose();
  }
}
