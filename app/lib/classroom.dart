// Reads a child's upcoming Google Classroom work with their school account.
//
// Read-only scopes: course names, the child's own coursework and the
// teachers' announcements. Runs on the parent's phone; nothing is stored
// except the resulting homework, test and announcement items.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'logic.dart';
import 'models.dart';

const classroomScopes = [
  'https://www.googleapis.com/auth/classroom.courses.readonly',
  'https://www.googleapis.com/auth/classroom.coursework.me.readonly',
  'https://www.googleapis.com/auth/classroom.announcements.readonly',
];

/// How many days of teacher announcements to show.
const classroomNoticeDays = 7;

/// Build with `--dart-define=CLASSROOM=false` to hide the Classroom import,
/// e.g. for a store release before Google has verified the Classroom scopes.
const classroomEnabled = bool.fromEnvironment('CLASSROOM', defaultValue: true);

/// The project's web OAuth client (google-services.json, client_type 3).
/// Android's Google sign-in needs it because the app does not use the
/// google-services Gradle plugin.
const googleWebClientId =
    '407838898643-pmh2sdvul3d29mpcoa6o7m4cli71suih.apps.googleusercontent.com';

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
    this.handedIn = false,
  });

  final String courseId;
  final String workId;
  final String courseName;
  final String title;

  /// Due date and time in the phone's time zone.
  final DateTime due;
  final String? link;

  /// Already turned in (or returned by the teacher) in Classroom.
  final bool handedIn;

  /// Stable id, so syncing again updates instead of duplicating.
  String get itemId =>
      's_cw_${'${courseId}_$workId'.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';

  bool get looksLikeTest => RegExp(
    r'\b(test|quiz|exam|assessment)\b',
    caseSensitive: false,
  ).hasMatch(title);
}

/// Turns one courses.courseWork.list response into upcoming work, marking
/// what the child already handed in. Work without a due date is skipped.
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
    if (d == null) continue;
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
        handedIn: handedIn.contains(m['id']),
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

class ClassroomNotice {
  ClassroomNotice({
    required this.courseId,
    required this.id,
    required this.courseName,
    required this.text,
    required this.posted,
    this.link,
  });
  final String courseId;
  final String id;
  final String courseName;
  final String text;
  final DateTime posted;
  final String? link;

  String get itemId =>
      's_an_${'${courseId}_$id'.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}';
}

/// Teachers' announcements from the last [classroomNoticeDays] days.
List<ClassroomNotice> parseAnnouncements(
  Map<String, dynamic> json,
  String courseName,
  DateTime now,
) {
  final since = now.subtract(const Duration(days: classroomNoticeDays));
  final out = <ClassroomNotice>[];
  for (final a in (json['announcements'] as List?) ?? const []) {
    final m = asMap(a);
    final when = DateTime.tryParse(
      (m['updateTime'] ?? m['creationTime'] ?? '') as String,
    )?.toLocal();
    final text = (m['text'] as String? ?? '').trim();
    if (when == null || when.isBefore(since) || text.isEmpty) continue;
    out.add(
      ClassroomNotice(
        courseId: m['courseId'] as String,
        id: m['id'] as String,
        courseName: courseName,
        text: text.length > 600 ? '${text.substring(0, 600)}…' : text,
        posted: when,
        link: m['alternateLink'] as String?,
      ),
    );
  }
  return out;
}

/// The announcement as a school item: shown on the child's page, no task.
SchoolItem schoolItemForNotice(ClassroomNotice n, String kidId) {
  final headline = noticeHeadline(n.text);
  return SchoolItem(
    id: n.itemId,
    kidId: kidId,
    kind: SchoolKind.notice,
    title: headline.length > 80 ? '${headline.substring(0, 80)}…' : headline,
    subject: n.courseName,
    dueYmd: ymdKey(n.posted),
    source: 'classroom',
    link: n.link,
    details: n.text,
  );
}

final _greeting = RegExp(
  r"^(as+[s-]?alam|as+alamu|asslamu|salam|assalam|bismillah|dear\b|hello\b|hi\b|good (morning|afternoon|evening)|respected)",
  caseSensitive: false,
);

/// The first line with real news, skipping greetings such as
/// "Assalamu alaikum wa rahmatullah".
String noticeHeadline(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.firstWhere(
    (l) => !_greeting.hasMatch(l),
    orElse: () => lines.isEmpty ? '' : lines.first,
  );
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
const _monthWord =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
final _dayMonth = RegExp(
  '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s*(?:of\\s+)?$_monthWord\\b[,\\s]*(\\d{4})?',
  caseSensitive: false,
);
final _monthDay = RegExp(
  '\\b$_monthWord\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:[,\\s]+(\\d{4}))?',
  caseSensitive: false,
);
final _numeric = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})\b');
final _testWord = RegExp(
  r'\b(re-?tests?|tests?|exams?|quiz(?:zes)?|assessments?|examination)\b',
  caseSensitive: false,
);

/// The first date in an announcement that is today or within the next 60
/// days. Numeric dates are read day first (02/11/2026 = 2 November).
DateTime? findDateIn(String text, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime? make(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    return date.month == m ? date : null;
  }

  final candidates = <(int, DateTime?)>[];
  for (final m in _dayMonth.allMatches(text)) {
    final month = _months[m.group(2)!.substring(0, 3).toLowerCase()]!;
    final day = int.parse(m.group(1)!);
    final year = m.group(3) == null ? null : int.parse(m.group(3)!);
    candidates.add((
      m.start,
      year != null
          ? make(year, month, day)
          : _nextOccurrence(today, month, day),
    ));
  }
  for (final m in _monthDay.allMatches(text)) {
    final month = _months[m.group(1)!.substring(0, 3).toLowerCase()]!;
    final day = int.parse(m.group(2)!);
    final year = m.group(3) == null ? null : int.parse(m.group(3)!);
    candidates.add((
      m.start,
      year != null
          ? make(year, month, day)
          : _nextOccurrence(today, month, day),
    ));
  }
  for (final m in _numeric.allMatches(text)) {
    candidates.add((
      m.start,
      make(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      ),
    ));
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, date) in candidates) {
    if (date != null &&
        !date.isBefore(today) &&
        date.difference(today).inDays <= 60) {
      return date;
    }
  }
  return null;
}

DateTime? _nextOccurrence(DateTime today, int month, int day) {
  for (final y in [today.year, today.year + 1]) {
    final d = DateTime(y, month, day);
    if (d.month == month && !d.isBefore(today)) return d;
  }
  return null;
}

/// An announcement that names a test and a date ("retest in Maths on Monday
/// 02 November, 2026") becomes a test with a revision task the school day
/// before. Other dated announcements become a reminder for that day.
SchoolItem? datedItemFromNotice(ClassroomNotice n, String kidId, DateTime now) {
  final date = findDateIn(n.text, now);
  if (date == null) return null;
  final sentences =
      [
            for (final line in n.text.split('\n'))
              ...line.split(RegExp(r'(?<=[.!?])\s*(?=[A-Z])')),
          ]
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty && !_greeting.hasMatch(x))
          .toList();
  final isTest = _testWord.hasMatch(n.text);
  bool hasDate(String x) => findDateIn(x, now) != null;
  var sentence = sentences.firstWhere(
    (x) => isTest ? _testWord.hasMatch(x) && hasDate(x) : hasDate(x),
    orElse: () => sentences.firstWhere(
      (x) => isTest && _testWord.hasMatch(x),
      orElse: () => noticeHeadline(n.text),
    ),
  );
  if (sentence.length > 90) sentence = '${sentence.substring(0, 90)}…';
  final work = ymdKey(defaultWorkDay(date, now));
  return SchoolItem(
    id: '${n.itemId}_d',
    kidId: kidId,
    kind: isTest ? SchoolKind.test : SchoolKind.event,
    title: sentence,
    subject: n.courseName,
    dueYmd: ymdKey(date),
    fromYmd: isTest ? work : null,
    toYmd: isTest ? work : null,
    source: 'classroom',
    link: n.link,
  );
}

/// One Google Classroom class, e.g. "Grade 3".
class ClassroomCourse {
  const ClassroomCourse(this.id, this.name);
  final String id;
  final String name;
}

/// Lets the person connecting pick which classes to read (one account can be
/// in several grades). Returns null when they cancel.
typedef ChooseCourses = Future<Set<String>?> Function(
  List<ClassroomCourse> courses,
  Set<String> selected,
);

/// Picks the classes to read: the saved choice (only classes that still
/// exist), or every class when nothing was chosen yet.
Set<String> coursesToRead(List<ClassroomCourse> all, Set<String> saved) {
  final ids = {for (final c in all) c.id};
  final keep = saved.intersection(ids);
  return keep.isEmpty ? ids : keep;
}

class ClassroomResult {
  ClassroomResult(
    this.email,
    this.work,
    this.notices, [
    this.classNames = const [],
    this.courseIds = const [],
    this.allClassNames = const [],
  ]);
  final String email;

  /// Ids of the classes that were read (the ones chosen).
  final List<String> courseIds;

  /// Every class the account is in, chosen or not.
  final List<String> allClassNames;

  /// The Classroom classes found for this account, e.g. ["Grade 3"].
  final List<String> classNames;
  final List<ClassroomWork> work;
  final List<ClassroomNotice> notices;
}

/// Explains what Google Classroom's error means and how to fix it.
String classroomErrorMessage(int status, String body) {
  var message = '';
  var reason = '';
  try {
    final err = asMap(asMap(jsonDecode(body))['error']);
    message = (err['message'] as String?) ?? '';
    for (final d in (err['details'] as List?) ?? const []) {
      reason = '$reason ${asMap(d)['reason'] ?? ''}';
    }
    reason = '$reason ${err['status'] ?? ''}';
  } catch (_) {}
  final all = '$message $reason';
  if (all.contains('SERVICE_DISABLED') ||
      all.contains('has not been used in project') ||
      all.contains('is disabled')) {
    return 'Google Classroom is not switched on for Super Mom yet. In Google Cloud (project super-mom-43520), '
        'open "APIs & Services", search "Google Classroom API" and click Enable. Then connect again.';
  }
  if (all.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT') ||
      all.contains('insufficient authentication scopes')) {
    return 'Classroom permissions were not given. Add the 3 Classroom permissions under Google Auth Platform → '
        'Data access, then tap Connect again and tick every box Google shows.';
  }
  if (all.contains('ClassroomApiDisabled') ||
      all.contains('@ClassroomApiDisabled')) {
    return "This school's Google admin has turned off Classroom access for apps. The admin can allow it in the "
        'Admin console (Apps → Google Workspace → Classroom → Data access).';
  }
  if (status == 401) return 'Google sign-in expired. Tap Connect again.';
  if (status == 403) {
    return "This account isn't allowed to share Classroom with Super Mom"
        '${message.isEmpty ? '' : ' ($message)'}. If it is a school account, the school admin may need to trust the app.';
  }
  return 'Google Classroom answered $status${message.isEmpty ? '' : ': $message'}';
}

class ClassroomException implements Exception {
  ClassroomException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _googleSignInReady = false;

/// Google's own sign-in (used for the parent's "Continue with Google" on
/// phones and for the Classroom import). Initialised once per app run.
Future<GoogleSignIn> googleSignIn() async {
  final signIn = GoogleSignIn.instance;
  if (!_googleSignInReady) {
    await signIn.initialize(serverClientId: googleWebClientId);
    _googleSignInReady = true;
  }
  return signIn;
}

class ClassroomClient {
  /// Google sign-in for Classroom works in the Android and iPhone apps.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Reads the child's upcoming work and recent announcements. With
  /// [interactive] the parent picks the child's school account; without it
  /// (the daily background sync) it only works when that account is still
  /// signed in and returns null otherwise, never showing a screen.
  static Future<ClassroomResult?> fetch(
    DateTime now, {
    bool interactive = true,
    String? expectedEmail,
    Set<String> savedCourses = const {},
    ChooseCourses? choose,
  }) async {
    if (!supported) {
      throw ClassroomException('Google Classroom works in the phone app.');
    }
    final signIn = await googleSignIn();
    final GoogleSignInAccount account;
    // "Sync now" for an account that is still signed in: no account picker.
    if (interactive && expectedEmail != null) {
      try {
        final quiet = await signIn.attemptLightweightAuthentication(
          reportAllExceptions: false,
        );
        if (quiet != null && quiet.email == expectedEmail) {
          final quietAuth = await quiet.authorizationClient
              .authorizationForScopes(classroomScopes);
          if (quietAuth != null) {
            return await _read(
              now,
              quiet.email,
              quietAuth.accessToken,
              savedCourses,
              choose,
            );
          }
        }
      } on GoogleSignInException {
        // Fall back to the account picker below.
      }
    }
    if (!interactive) {
      final quiet = await signIn.attemptLightweightAuthentication(
        reportAllExceptions: false,
      );
      if (quiet == null ||
          (expectedEmail != null && quiet.email != expectedEmail)) {
        return null;
      }
      final quietAuth = await quiet.authorizationClient.authorizationForScopes(
        classroomScopes,
      );
      if (quietAuth == null) return null;
      return _read(now, quiet.email, quietAuth.accessToken, savedCourses);
    }
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
    return _read(now, account.email, auth.accessToken, savedCourses, choose);
  }

  static Future<ClassroomResult> _read(
    DateTime now,
    String email,
    String token,
    Set<String> savedCourses, [
    ChooseCourses? choose,
  ]) async {
    final headers = {'Authorization': 'Bearer $token'};

    Future<Map<String, dynamic>> get(
      String path, [
      Map<String, dynamic>? query,
    ]) async {
      final uri = Uri.https('classroom.googleapis.com', path, query);
      final res = await http.get(uri, headers: headers);
      if (res.statusCode != 200) {
        throw ClassroomException(
          classroomErrorMessage(res.statusCode, res.body),
        );
      }
      return asMap(jsonDecode(res.body));
    }

    // Classes the account is in as a student (a child's account) or as a
    // teacher (useful for teachers and for testing), without duplicates.
    final courses = <String, Map<String, dynamic>>{};
    for (final role in ['studentId', 'teacherId']) {
      final page = await get('/v1/courses', {
        role: 'me',
        'courseStates': 'ACTIVE',
        'pageSize': '30',
      });
      for (final c in (page['courses'] as List?) ?? const []) {
        final course = asMap(c);
        courses[course['id'] as String] = course;
      }
    }
    final all = [
      for (final c in courses.values)
        ClassroomCourse(c['id'] as String, (c['name'] as String?) ?? 'Class'),
    ];
    var selected = coursesToRead(all, savedCourses);
    if (choose != null && all.length > 1) {
      final picked = await choose(all, selected);
      if (picked == null) throw ClassroomException('No classes were chosen.');
      if (picked.isNotEmpty) selected = picked;
    }
    final work = <ClassroomWork>[];
    final notices = <ClassroomNotice>[];
    for (final course in courses.values.where(
      (c) => selected.contains(c['id']),
    )) {
      final id = course['id'] as String;
      final announcements = await get('/v1/courses/$id/announcements', {
        'announcementStates': 'PUBLISHED',
        'orderBy': 'updateTime desc',
        'pageSize': '10',
      });
      notices.addAll(
        parseAnnouncements(
          announcements,
          course['name'] as String? ?? 'Class',
          now,
        ),
      );
      // Only students have their own submissions; a teacher's account gets
      // an error here, which just means "nothing handed in".
      Map<String, dynamic> submissions;
      try {
        submissions = await get(
          '/v1/courses/$id/courseWork/-/studentSubmissions',
          {
            'userId': 'me',
            'states': ['TURNED_IN', 'RETURNED'],
            'pageSize': '100',
          },
        );
      } on ClassroomException {
        submissions = const {};
      }
      final handedIn = {
        for (final s
            in (submissions['studentSubmissions'] as List?) ?? const [])
          asMap(s)['courseWorkId'] as String,
      };
      // A teacher's account may not be allowed to list classwork with the
      // student permission; the announcements above still come through.
      Map<String, dynamic> list;
      try {
        list = await get('/v1/courses/$id/courseWork', {
          'courseWorkStates': 'PUBLISHED',
          'orderBy': 'dueDate desc',
          'pageSize': '30',
        });
      } on ClassroomException {
        list = const {};
      }
      work.addAll(
        parseCourseWork(
          list,
          course['name'] as String? ?? 'Class',
          handedIn,
          now,
        ),
      );
    }
    return ClassroomResult(
      email,
      work,
      notices,
      [
        for (final c in all)
          if (selected.contains(c.id)) c.name,
      ],
      [
        for (final c in all)
          if (selected.contains(c.id)) c.id,
      ],
      [for (final c in all) c.name],
    );
  }
}
