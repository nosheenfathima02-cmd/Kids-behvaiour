import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'classroom.dart';
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

  /// A parent signed up with email and has not tapped the confirmation link yet.
  parentNeedsVerification,

  /// A parent has not given their name and phone number yet.
  parentNeedsProfile,

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

  /// This parent's name and phone (families/{fid}/parents/{uid}); parents only.
  Map<String, dynamic>? parentProfile;
  bool _profileLoaded = false;

  /// The kids this device may act for (child device only).
  List<String> deviceKidIds = [];
  String deviceName = '';

  /// Last error to show to the user once (e.g. a rejected tick).
  final ValueNotifier<String?> errors = ValueNotifier(null);

  final List<StreamSubscription<Object?>> _subs = [];
  final Map<String, StreamSubscription<Object?>> _kidSubs = {};
  final Map<String, Kid> _kids = {};
  final Map<String, Map<String, dynamic>?> _weeks = {};

  /// families/{fid}/kidSchool/{kidId}: what children imported from Google
  /// Classroom on their own devices.
  final Map<String, Map<String, dynamic>> _kidSchool = {};
  final Set<String> _kidSchoolIds = {};
  DateTime? _lastAutoClassroom;
  bool _autoClassroomRunning = false;

  /// When Classroom was last checked for each child on this phone.
  DateTime? lastClassroomSync(Kid kid) {
    final ms = _prefs.getInt('classroom_last_${kid.id}');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Map<String, dynamic>? _familyDoc;
  String _listeningWeek = '';
  Timer? _ticker;
  String _maintainedDay = '';
  String _scheduledFor = '';
  String _announcedKey = '';

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
      if (needsEmailVerification) {
        role = Role.parent;
        _setPhase(Phase.parentNeedsVerification);
        return;
      }
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

  /// The weekly routine plus this week's homework, tests and competition practice.
  List<RoutineTask> get allTasks => [
    ...family.routine,
    ...schoolTasks(family.schoolItems, currentWeekId),
  ];

  /// Upcoming homework, tests and competitions for one child, soonest first.
  List<SchoolItem> schoolItemsFor(Kid kid) =>
      family.schoolItems
          .where(
            (i) =>
                i.kidId == kid.id &&
                i.kind != SchoolKind.notice &&
                daysUntil(i.dueYmd, now) >= 0,
          )
          .toList()
        ..sort((a, b) => a.dueYmd.compareTo(b.dueYmd));

  List<RoutineTask> tasksForDay(Kid kid, int weekday) =>
      tasksFor(kid, allTasks, weekday, prayersToday);
  TaskStatus status(Kid kid, RoutineTask t, int weekday) =>
      statusOf(kid, t, weekday, todayWeekday, nowMinute, prayersToday);
  bool canKidToggle(Kid kid, RoutineTask t) =>
      kidCanToggle(kid, t, todayWeekday, todayWeekday, nowMinute, prayersToday);
  WeekScore score(Kid kid) =>
      weekScore(kid, allTasks, todayWeekday, prayersToday);
  int starsForDay(Kid kid, int weekday) =>
      dayStars(kid, allTasks, weekday, todayWeekday, prayersToday);
  TimeWindow window(RoutineTask t) => windowOf(t, prayersToday);

  DocumentReference<Map<String, dynamic>> get _familyRef =>
      db.collection('families').doc(familyId);
  DocumentReference<Map<String, dynamic>> _weekRef(
    String kidId, [
    String? weekId,
  ]) => _familyRef.collection('weeks').doc('${weekId ?? currentWeekId}_$kidId');

  // ---------------- parent sign-in & setup ----------------

  /// On phones this uses Google's account picker and hands its token to
  /// Firebase. (Firebase's own web-based Google window fails on some Android
  /// phones with "Failed to generate/retrieve public encryption key".)
  Future<void> signInWithGoogle() async {
    if (kIsWeb) return _signInWith(GoogleAuthProvider());
    final signIn = await googleSignIn();
    final GoogleSignInAccount account;
    try {
      await signIn.signOut(); // always offer the account list
      account = await signIn.authenticate();
    } on GoogleSignInException catch (e) {
      throw FirebaseAuthException(
        code: e.code == GoogleSignInExceptionCode.canceled
            ? 'canceled'
            : 'google-sign-in-failed',
        message: e.description ?? 'Google sign-in did not work.',
      );
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: 'Google did not return a sign-in token.',
      );
    }
    await auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    await _afterParentSignIn();
  }

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
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.sendEmailVerification();
    } else {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    }
    if (needsEmailVerification) {
      role = Role.parent;
      _setPhase(Phase.parentNeedsVerification);
      return;
    }
    await _afterParentSignIn();
  }

  static const _pendingNameKey = 'pending_name';
  static const _pendingPhoneKey = 'pending_phone';
  static const _pendingAdultKey = 'pending_adult';

  /// "Create an account": name, phone and the 18+ confirmation are kept on
  /// this phone until the family is set up (the server only accepts them
  /// once the email is confirmed).
  Future<void> createParentAccount({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final cred = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(name.trim());
    await _prefs.setString(_pendingNameKey, name.trim());
    await _prefs.setString(_pendingPhoneKey, phone.trim());
    await _prefs.setBool(_pendingAdultKey, true);
    await cred.user?.sendEmailVerification();
    role = Role.parent;
    await _prefs.setString(_roleKey, Role.parent.name);
    if (needsEmailVerification) {
      _setPhase(Phase.parentNeedsVerification);
      return;
    }
    await _afterParentSignIn();
  }

  /// Prefills "About you" with what the parent already gave (sign-up form or
  /// their Google account).
  String get suggestedName =>
      _prefs.getString(_pendingNameKey) ?? auth.currentUser?.displayName ?? '';
  String get suggestedPhone =>
      _prefs.getString(_pendingPhoneKey) ?? auth.currentUser?.phoneNumber ?? '';
  bool get adultAlreadyConfirmed => _prefs.getBool(_pendingAdultKey) ?? false;

  Future<void> sendPasswordReset(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  /// Email-and-password accounts must confirm their address first. Google
  /// and Apple accounts are already confirmed.
  bool get needsEmailVerification {
    final user = auth.currentUser;
    return user != null &&
        !user.isAnonymous &&
        !user.emailVerified &&
        user.providerData.any((p) => p.providerId == 'password');
  }

  String get signedInEmail => auth.currentUser?.email ?? '';

  Future<void> resendVerificationEmail() async =>
      auth.currentUser?.sendEmailVerification();

  /// After the parent tapped the link: returns false if not confirmed yet.
  Future<bool> checkEmailVerified() async {
    await auth.currentUser?.reload();
    if (needsEmailVerification) return false;
    await auth.currentUser?.getIdToken(true); // so the server sees it too
    await _afterParentSignIn();
    return true;
  }

  static final _phonePattern = RegExp(r'^\+?[0-9 ()-]{7,20}$');

  /// Null when fine, otherwise what to fix.
  static String? checkPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!_phonePattern.hasMatch(phone.trim()) ||
        digits.length < 7 ||
        digits.length > 15) {
      return 'Enter a phone number with country code, e.g. +974 5512 3456';
    }
    return null;
  }

  DocumentReference<Map<String, dynamic>> get _myProfileRef =>
      _familyRef.collection('parents').doc(auth.currentUser!.uid);

  Future<void> saveParentProfile(String name, String phone) async {
    final data = {
      'name': name.trim(),
      'phone': phone.trim(),
      'email': auth.currentUser?.email ?? '',
      // Confirmed on the sign-up form (the form cannot be sent without it).
      'adultConfirmed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _myProfileRef.set(data);
    for (final k in [_pendingNameKey, _pendingPhoneKey, _pendingAdultKey]) {
      await _prefs.remove(k);
    }
    parentProfile = data;
    _rebuild();
  }

  String get parentName => (parentProfile?['name'] as String?) ?? '';

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
    required String parentName,
    required String phone,
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
    await saveParentProfile(parentName, phone);
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

  /// Parent: deletes their sign-in and, if they are the only parent, the whole
  /// family (children, ticks, devices, homework). Returns a message to show
  /// when it could not finish, or null when everything is deleted.
  Future<String?> deleteAccountAndData() async {
    final user = auth.currentUser;
    if (user == null || !isParent) {
      return 'Only a signed-in parent can delete the account.';
    }
    // Firebase only deletes a sign-in that was used in the last few minutes.
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null ||
        DateTime.now().difference(lastSignIn) > const Duration(minutes: 4)) {
      await signOut();
      return 'For your safety, sign in again and then choose "Delete account" within 5 minutes.';
    }
    try {
      final uid = user.uid;
      final otherParents = family.parents.where((p) => p != uid).toList();
      _stopListening();
      if (otherParents.isNotEmpty) {
        await _familyRef.update({'parents': otherParents});
      } else {
        for (final sub in [
          'weeks',
          'kids',
          'devices',
          'parentTokens',
          'parents',
          'kidSchool',
        ]) {
          final docs = (await _familyRef.collection(sub).get()).docs;
          for (var i = 0; i < docs.length; i += 400) {
            final batch = db.batch();
            for (final d in docs.skip(i).take(400)) {
              batch.delete(d.reference);
            }
            await batch.commit();
          }
        }
        final codes = await db
            .collection('pairings')
            .where('createdBy', isEqualTo: uid)
            .get();
        for (final d in codes.docs) {
          await d.reference.delete();
        }
        await _familyRef.delete();
      }
      await user.delete();
      await _prefs.clear();
      role = null;
      familyId = null;
      data = null;
      _setPhase(Phase.welcome);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        await signOut();
        return 'Your family data is deleted. Sign in once more and choose "Delete account" to remove your sign-in too.';
      }
      return 'Could not delete: ${e.message ?? e.code}';
    } catch (e) {
      return 'Could not delete: $e';
    }
  }

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
    _profileLoaded = false;
    _subs.add(
      _myProfileRef.snapshots().listen((s) {
        parentProfile = s.data();
        _profileLoaded = true;
        _rebuild();
      }, onError: _onListenError),
    );
    _subs.add(
      _familyRef.collection('kidSchool').snapshots().listen(
        (s) {
          _kidSchool
            ..clear()
            ..addAll({for (final d in s.docs) d.id: d.data()});
          _rebuild();
        },
        onError: (_) {},
      ), // Older security rules: nothing imported by children.
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
      _kidSubs['school:$id'] = _familyRef
          .collection('kidSchool')
          .doc(id)
          .snapshots()
          .listen((s) {
            final d = s.data();
            d == null ? _kidSchool.remove(id) : _kidSchool[id] = d;
            _rebuild();
          }, onError: (_) {}); // Older security rules: not available.
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
    _kidSchool.clear();
    _kidSchoolIds.clear();
    _familyDoc = null;
    devices = [];
    deviceKidIds = [];
    parentProfile = null;
    _profileLoaded = false;
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
    _mergeKidSchool(data!);
    if (isParent && !hasPin) {
      _setPhase(Phase.parentNeedsPin);
      return;
    }
    if (isParent &&
        _profileLoaded &&
        parentProfile?['adultConfirmed'] != true) {
      _setPhase(Phase.parentNeedsProfile);
      return;
    }
    _setPhase(Phase.ready);
    _maintain();
  }

  /// Adds what children imported on their own devices. Mom's copy of an
  /// item (in the family document) wins.
  void _mergeKidSchool(FamilyData fam) {
    _kidSchoolIds.clear();
    final have = {for (final i in fam.schoolItems) i.id};
    for (final kid in fam.kids) {
      final doc = _kidSchool[kid.id];
      kid.selfClassroomEmail = doc?['email'] as String?;
      kid.selfClassroomClasses = [
        for (final c in (doc?['classes'] as List?) ?? const []) '$c',
      ];
      kid.selfClassroomCourseIds = [
        for (final c in (doc?['courseIds'] as List?) ?? const []) '$c',
      ];
      for (final e in ((doc?['items'] as Map?) ?? const {}).values) {
        final item = tryParseSchoolItem(e);
        if (item == null || item.kidId != kid.id || have.contains(item.id)) {
          continue;
        }
        fam.schoolItems.add(item);
        _kidSchoolIds.add(item.id);
      }
    }
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

  /// Schedules this device's adhan and school reminders again (e.g. after
  /// Android allowed exact alarms).
  void rescheduleReminders() {
    if (!isSetUp) return;
    _scheduledFor = '';
    _maintain();
  }

  /// Daily upkeep: reminders on this device, and (on a parent's phone) the
  /// weekly reset, time zone and salah windows for the security rules.
  void _maintain() {
    final today = ymdKey(now);
    final reminders = _schoolReminders();
    final schedKey =
        '$today|${family.adhanEnabled}|${jsonEncode(family.prayer.toJson())}|'
        '${reminders.map((r) => '${r.at}${r.title}').join()}';
    if (_scheduledFor != schedKey) {
      _scheduledFor = schedKey;
      Notifications.schedulePrayers(
        family.prayer,
        enabled: family.adhanEnabled,
        reminders: reminders,
      );
    }
    final notices = [for (final k in visibleKids) ...noticesFor(k)];
    final noticeKey = notices.map((n) => n.id).join(',');
    if (noticeKey != _announcedKey) {
      _announcedKey = noticeKey;
      Notifications.announceNotices(notices, (id) => kidById(id)?.name ?? '');
    }
    // Classroom refreshes by itself when the app opens and every 2 hours
    // while it is open.
    if (_lastAutoClassroom == null ||
        now.difference(_lastAutoClassroom!) >= const Duration(hours: 2)) {
      _lastAutoClassroom = now;
      _autoClassroomSync();
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
      ..delete(_familyRef.collection('kidSchool').doc(kid.id))
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

  /// Tests and competitions: a reminder the evening before, and on the
  /// morning of a competition.
  List<ScheduledReminder> _schoolReminders() {
    final out = <ScheduledReminder>[];
    for (final kid in visibleKids) {
      for (final i in family.schoolItems.where((i) => i.kidId == kid.id)) {
        final name = kid.name;
        final cheer = encouragementFor(i.id);
        switch (i.kind) {
          case SchoolKind.homework:
            // When homework time starts, an hour before it closes, and on
            // the due day, until it is ticked or handed in on Classroom.
            if (_schoolDone(kid, i) || i.fromYmd == null) break;
            final work = dateFromYmd(i.fromYmd!);
            final what = i.subject.isEmpty
                ? i.title
                : '${i.subject}: ${i.title}';
            out.add(
              ScheduledReminder(
                work.add(Duration(minutes: i.startMin)),
                '📚 Homework time, $name!',
                '$what. $cheer',
              ),
            );
            if (i.endMin - i.startMin > 90) {
              out.add(
                ScheduledReminder(
                  work.add(Duration(minutes: i.endMin - 60)),
                  '⏰ Don\'t forget, $name: $what',
                  'Only one hour left. You\'re almost there, finish it now!',
                ),
              );
            }
            final due = dateFromYmd(i.dueYmd);
            if (due.isAfter(work)) {
              out.add(
                ScheduledReminder(
                  due.add(const Duration(hours: 7)),
                  '🎒 Hand it in today: $what',
                  'Put it in your school bag, $name. Well done for finishing it!',
                ),
              );
            }
          case SchoolKind.test:
            final what =
                '${i.subject.isEmpty ? '' : '${i.subject} '}test: ${i.title}';
            out.add(
              ScheduledReminder(
                dateFromYmd(i.dueYmd).subtract(const Duration(hours: 6)),
                '📝 Tomorrow: $what',
                'Revise a little, then sleep early, $name. $cheer',
              ),
            );
          case SchoolKind.event:
            final day = dateFromYmd(i.dueYmd);
            out.add(
              ScheduledReminder(
                day.subtract(const Duration(hours: 6)),
                '🏆 Tomorrow: ${i.title}',
                'Bismillah, $name. Get ready tonight and sleep early.',
              ),
            );
            out.add(
              ScheduledReminder(
                day.add(const Duration(hours: 7)),
                'Today: ${i.title}',
                'Good luck, $name! Say Bismillah and do your best.',
              ),
            );
          case SchoolKind.notice:
            break;
        }
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.where((r) => r.at.isAfter(now)).toList();
  }

  void upsertSchoolItem(SchoolItem item) {
    final i = family.schoolItems.indexWhere((x) => x.id == item.id);
    i >= 0 ? family.schoolItems[i] = item : family.schoolItems.add(item);
    _write(
      _familyRef.update({
        FieldPath(['schoolItems', item.id]): item.toJson(),
      }),
    );
    notifyListeners();
  }

  void deleteSchoolItem(SchoolItem item) {
    family.schoolItems.removeWhere((x) => x.id == item.id);
    // It may be in the family document (Mom's), the child's own import, or both.
    final inKidDoc = ((_kidSchool[item.kidId]?['items'] as Map?) ?? const {})
        .containsKey(item.id);
    if (inKidDoc) {
      _write(
        _familyRef.collection('kidSchool').doc(item.kidId).update({
          FieldPath(['items', item.id]): FieldValue.delete(),
        }),
      );
    }
    if (!_kidSchoolIds.contains(item.id)) {
      _write(
        _familyRef.update({
          FieldPath(['schoolItems', item.id]): FieldValue.delete(),
        }),
      );
    }
    notifyListeners();
  }

  String newSchoolItemId() => 's_${_newId()}';

  /// Imports a child's upcoming Google Classroom homework and tests, and
  /// their teachers' recent announcements. Returns a message for the parent,
  /// or null when a background sync could not run without asking.
  Future<String?> syncClassroom(
    Kid kid, {
    bool interactive = true,
    ChooseCourses? choose,
    bool otherAccount = false,
  }) async {
    try {
      final result = await ClassroomClient.fetch(
        now,
        interactive: interactive,
        savedCourses: {
          ...(isParent ? kid.classroomCourseIds : kid.selfClassroomCourseIds),
        },
        choose: interactive ? choose : null,
        expectedEmail: otherAccount
            ? null
            : (isParent ? kid.classroomEmail : kid.selfClassroomEmail),
      );
      if (result == null) return null;
      await _prefs.setInt(
        'classroom_last_${kid.id}',
        now.millisecondsSinceEpoch,
      );
      final updates = <String, Object?>{};
      var added = 0;
      for (final w in result.work) {
        final existing = family.schoolItems
            .where((x) => x.id == w.itemId)
            .firstOrNull;
        if (existing == null) added++;
        final item = schoolItemFor(w, kid.id, now, existing: existing)
          ..handedIn = w.handedIn;
        updates[item.id] = item.toJson();
      }
      for (final n in result.notices) {
        if (!family.schoolItems.any((x) => x.id == n.itemId)) added++;
        final item = schoolItemForNotice(n, kid.id);
        updates[item.id] = item.toJson();
        // A test or date in the announcement becomes its own reminder; Mom's
        // later changes to it are kept.
        final dated = datedItemFromNotice(n, kid.id, now);
        if (dated != null && !family.schoolItems.any((x) => x.id == dated.id)) {
          updates[dated.id] = dated.toJson();
          added++;
        }
      }
      // Classes that were not chosen: remove what was imported from them before.
      final unchosen = result.allClassNames.toSet()
        ..removeAll(result.classNames);
      for (final i in family.schoolItems) {
        if (i.kidId == kid.id &&
            i.source == 'classroom' &&
            unchosen.contains(i.subject) &&
            _kidSchoolIds.contains(i.id) != isParent) {
          updates[i.id] = FieldValue.delete();
        }
      }
      if (!isParent) {
        // A child's own device keeps what it imports in the child's own
        // document; Mom sees it too.
        await _familyRef.collection('kidSchool').doc(kid.id).set({
          'items': updates,
          'email': result.email,
          'classes': result.classNames,
          'courseIds': result.courseIds,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (updates.isNotEmpty) {
        await _familyRef.update({
          for (final e in updates.entries)
            FieldPath(['schoolItems', e.key]): e.value,
        });
      }
      if (isParent &&
          (kid.classroomEmail != result.email ||
              !listEquals(kid.classroomClasses, result.classNames) ||
              !listEquals(kid.classroomCourseIds, result.courseIds))) {
        kid.classroomEmail = result.email;
        kid.classroomClasses = result.classNames;
        kid.classroomCourseIds = result.courseIds;
        saveKid(kid);
      }
      if (result.classNames.isEmpty) {
        return '${result.email} is not in any Google Classroom class. '
            "Connect the account ${kid.name} uses in Classroom (the one that joined the class).";
      }
      return 'Classes: ${result.classNames.join(', ')}. '
          'Found ${result.work.length} homework/tests due in the next 2 weeks and '
          '${result.notices.length} announcements from the last 7 days ($added new).';
    } on ClassroomException catch (e) {
      return interactive ? e.message : null;
    } catch (e) {
      return interactive ? 'Classroom sync did not work: $e' : null;
    }
  }

  /// Refreshes Classroom without showing anything, for every child whose
  /// school account is still signed in on this phone: on a parent's phone
  /// the accounts Mom connected, on a child's device the child's own.
  Future<void> _autoClassroomSync() async {
    if (!classroomEnabled ||
        !ClassroomClient.supported ||
        _autoClassroomRunning) {
      return;
    }
    _autoClassroomRunning = true;
    try {
      final kids = isParent
          ? family.kids.where((k) => k.classroomEmail != null)
          : visibleKids.where(
              (k) => k.mayConnectClassroom && k.selfClassroomEmail != null,
            );
      for (final kid in kids.toList()) {
        await syncClassroom(kid, interactive: false);
      }
    } finally {
      _autoClassroomRunning = false;
    }
  }

  /// Teachers' announcements from the last week, newest first.
  List<SchoolItem> noticesFor(Kid kid) =>
      family.schoolItems
          .where(
            (i) =>
                i.kidId == kid.id &&
                i.kind == SchoolKind.notice &&
                daysUntil(i.dueYmd, now) >= -classroomNoticeDays,
          )
          .toList()
        ..sort((a, b) => b.dueYmd.compareTo(a.dueYmd));

  /// Homework or revision still to do today (not ticked, not handed in).
  List<SchoolItem> schoolWorkLeftToday(Kid kid) {
    final today = ymdKey(now);
    return family.schoolItems
        .where(
          (i) =>
              i.kidId == kid.id &&
              (i.kind == SchoolKind.homework || i.kind == SchoolKind.test) &&
              i.fromYmd != null &&
              i.fromYmd!.compareTo(today) <= 0 &&
              (i.toYmd ?? i.fromYmd!).compareTo(today) >= 0 &&
              !_schoolDone(kid, i),
        )
        .toList();
  }

  bool _schoolDone(Kid kid, SchoolItem i) {
    if (i.handedIn) return true;
    if (i.fromYmd == null) return false;
    final day = dateFromYmd(i.fromYmd!);
    return weekIdFor(day) == currentWeekId &&
        kid.checks.containsKey(Kid.key(day.weekday, i.id));
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
    final practiceAdds = <String, int>{};
    for (final k in family.kids) {
      final copy = Kid.fromJson({
        ...k.toJson(),
        'checks': null,
        'timeouts': null,
      })..applyWeek(oldWeek[k.id]);
      summary[k.name] = weekScore(
        copy,
        [...family.routine, ...schoolTasks(family.schoolItems, oldWeekId)],
        scoreDay,
        prayersToday,
      ).total;
      // Competition practice from that week counts towards the target.
      for (final item in family.schoolItems.where(
        (i) => i.kidId == k.id && i.kind == SchoolKind.event,
      )) {
        final ticks = practiceTicksThisWeek(copy, item);
        if (ticks > 0) {
          practiceAdds[item.id] = (practiceAdds[item.id] ?? 0) + ticks;
        }
      }
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
    final schoolUpdates = <Object, Object?>{};
    final cutoff = ymdKey(now.subtract(const Duration(days: 7)));
    for (final item in family.schoolItems) {
      final path = FieldPath(['schoolItems', item.id]);
      if (item.dueYmd.compareTo(cutoff) < 0) {
        schoolUpdates[path] =
            FieldValue.delete(); // finished more than a week ago
      } else if (practiceAdds.containsKey(item.id)) {
        schoolUpdates[FieldPath(['schoolItems', item.id, 'practiceDone'])] =
            item.practiceDone + practiceAdds[item.id]!;
      }
    }
    if (schoolUpdates.isNotEmpty) batch.update(_familyRef, schoolUpdates);
    await batch.commit();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopListening();
    super.dispose();
  }
}
