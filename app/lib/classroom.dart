// Reads a child's upcoming Google Classroom work with their school account.
//
// Read-only scopes: course names and the child's own coursework. Runs on the
// parent's phone; nothing is stored except the resulting homework items.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'logic.dart';
import 'models.dart';

const classroomScopes = [
  'https://www.googleapis.com/auth/classroom.courses.readonly',
  'https://www.googleapis.com/auth/classroom.coursework.me.readonly',
];

/// Build with `--dart-define=CLASSROOM=false` to hide the Classroom import,
/// e.g. for a store release before Google has verified the Classroom scopes.
const classroomEnabled = bool.fromEnvironment('CLASSROOM', defaultValue: true);

/// How many days ahead to import.
const classroomDaysAhead = 14;

class ClassroomWork {
  ClassroomWork({
    required this.courseId,
    required this.workId,
    required this.courseName,
    required this.title,
    required this.due,
    this.link,
  });

  final String courseId;
  final String workId;
  final String courseName;
  final String title;

  /// Due date and time in the phone's time zone.
  final DateTime due;
  final String? link;

  /// Stable id, so syncing again updates instead of duplicating.
  String get itemId =>
      's_cw_${'${courseId}_$workId'.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';

  bool get looksLikeTest => RegExp(
    r'\b(test|quiz|exam|assessment)\b',
    caseSensitive: false,
  ).hasMatch(title);
}

/// Turns one courses.courseWork.list response into upcoming, not yet
/// handed-in work. Work without a due date is skipped.
List<ClassroomWork> parseCourseWork(
  Map<String, dynamic> json,
  String courseName,
  Set<String> handedIn,
  DateTime now,
) {
  final out = <ClassroomWork>[];
  final today = DateTime(now.year, now.month, now.day);
  final last = today.add(const Duration(days: classroomDaysAhead + 1));
  for (final w in (json['courseWork'] as List?) ?? const []) {
    final m = asMap(w);
    final d = m['dueDate'] == null ? null : asMap(m['dueDate']);
    if (d == null || handedIn.contains(m['id'])) continue;
    final t = m['dueTime'] == null ? <String, dynamic>{} : asMap(m['dueTime']);
    // Classroom gives due dates in UTC; no time means the end of that day.
    final due = (t.isEmpty
        ? DateTime(d['year'] as int, d['month'] as int, d['day'] as int, 23, 59)
        : DateTime.utc(
            d['year'] as int,
            d['month'] as int,
            d['day'] as int,
            (t['hours'] as int?) ?? 0,
            (t['minutes'] as int?) ?? 0,
          ).toLocal());
    if (due.isBefore(today) || !due.isBefore(last)) continue;
    out.add(
      ClassroomWork(
        courseId: m['courseId'] as String,
        workId: m['id'] as String,
        courseName: courseName,
        title: (m['title'] as String? ?? 'Classwork').trim(),
        due: due,
        link: m['alternateLink'] as String?,
      ),
    );
  }
  return out;
}

/// The homework item for a piece of Classroom work. Keeps any day Mom
/// already moved it to.
SchoolItem schoolItemFor(
  ClassroomWork w,
  String kidId,
  DateTime now, {
  SchoolItem? existing,
}) {
  final workDay = ymdKey(defaultWorkDay(w.due, now));
  return SchoolItem(
    id: w.itemId,
    kidId: kidId,
    kind: w.looksLikeTest ? SchoolKind.test : SchoolKind.homework,
    title: w.title,
    subject: w.courseName,
    dueYmd: ymdKey(w.due),
    fromYmd: existing?.fromYmd ?? workDay,
    toYmd: existing?.toYmd ?? workDay,
    startMin: existing?.startMin ?? 15 * 60 + 30,
    endMin: existing?.endMin ?? 18 * 60 + 30,
    source: 'classroom',
    link: w.link,
  );
}

class ClassroomResult {
  ClassroomResult(this.email, this.work);
  final String email;
  final List<ClassroomWork> work;
}

class ClassroomException implements Exception {
  ClassroomException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ClassroomClient {
  static bool _initialised = false;

  /// Google sign-in for Classroom works in the Android and iPhone apps.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Asks the parent to pick the child's school account, then reads their
  /// upcoming work.
  static Future<ClassroomResult> fetch(DateTime now) async {
    if (!supported) {
      throw ClassroomException('Google Classroom works in the phone app.');
    }
    final signIn = GoogleSignIn.instance;
    if (!_initialised) {
      await signIn.initialize();
      _initialised = true;
    }
    final GoogleSignInAccount account;
    try {
      // Always show the account picker: each child has their own school account.
      await signIn.signOut();
      account = await signIn.authenticate(scopeHint: classroomScopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw ClassroomException('Sign-in was cancelled.');
      }
      throw ClassroomException(
        'Could not sign in to Google: ${e.description ?? e.code.name}',
      );
    }
    final auth =
        await account.authorizationClient.authorizationForScopes(
          classroomScopes,
        ) ??
        await account.authorizationClient.authorizeScopes(classroomScopes);
    final headers = {'Authorization': 'Bearer ${auth.accessToken}'};

    Future<Map<String, dynamic>> get(
      String path, [
      Map<String, dynamic>? query,
    ]) async {
      final uri = Uri.https('classroom.googleapis.com', path, query);
      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 403 || res.statusCode == 401) {
        throw ClassroomException(
          "This school account can't share Classroom with other apps. "
          "The school's Google admin may need to allow Super Mom. You can still add homework by hand.",
        );
      }
      if (res.statusCode != 200) {
        throw ClassroomException(
          'Google Classroom answered ${res.statusCode}.',
        );
      }
      return asMap(jsonDecode(res.body));
    }

    final courses = await get('/v1/courses', {
      'studentId': 'me',
      'courseStates': 'ACTIVE',
      'pageSize': '30',
    });
    final work = <ClassroomWork>[];
    for (final c in (courses['courses'] as List?) ?? const []) {
      final course = asMap(c);
      final id = course['id'] as String;
      final submissions = await get(
        '/v1/courses/$id/courseWork/-/studentSubmissions',
        {
          'userId': 'me',
          'states': ['TURNED_IN', 'RETURNED'],
          'pageSize': '100',
        },
      );
      final handedIn = {
        for (final s
            in (submissions['studentSubmissions'] as List?) ?? const [])
          asMap(s)['courseWorkId'] as String,
      };
      final list = await get('/v1/courses/$id/courseWork', {
        'courseWorkStates': 'PUBLISHED',
        'orderBy': 'dueDate desc',
        'pageSize': '30',
      });
      work.addAll(
        parseCourseWork(
          list,
          course['name'] as String? ?? 'Class',
          handedIn,
          now,
        ),
      );
    }
    return ClassroomResult(account.email, work);
  }
}
