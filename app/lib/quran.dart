// Qur'an text and Sheikh Mahmoud Khalil Al-Husary's recitation for the
// memorisation screen. Text and audio stream from free public Qur'an
// services; text is cached on the phone after the first load.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SurahInfo {
  const SurahInfo(
    this.number,
    this.arabicName,
    this.englishName,
    this.meaning,
    this.ayahCount,
  );
  final int number;
  final String arabicName;
  final String englishName;
  final String meaning;
  final int ayahCount;

  Map<String, dynamic> toJson() => {
    'number': number,
    'name': arabicName,
    'englishName': englishName,
    'englishNameTranslation': meaning,
    'numberOfAyahs': ayahCount,
  };

  factory SurahInfo.fromJson(Map<String, dynamic> j) => SurahInfo(
    (j['number'] as num).toInt(),
    j['name'] as String? ?? '',
    j['englishName'] as String? ?? '',
    j['englishNameTranslation'] as String? ?? '',
    (j['numberOfAyahs'] as num?)?.toInt() ?? 0,
  );
}

class Ayah {
  const Ayah({
    required this.numberInSurah,
    required this.text,
    required this.audioUrl,
    this.translation = '',
  });
  final int numberInSurah;
  final String text;

  /// The meaning in English (Sahih International).
  final String translation;

  /// Al-Husary's normal (murattal) recitation of this ayah.
  final String audioUrl;

  Map<String, dynamic> toJson() => {
    'n': numberInSurah,
    't': text,
    'a': audioUrl,
    'e': translation,
  };
  factory Ayah.fromJson(Map<String, dynamic> j) => Ayah(
    numberInSurah: (j['n'] as num).toInt(),
    text: j['t'] as String,
    audioUrl: j['a'] as String,
    translation: j['e'] as String? ?? '',
  );
}

class Surah {
  const Surah({required this.info, required this.ayahs, this.bismillah});
  final SurahInfo info;
  final List<Ayah> ayahs;

  /// Shown above the first ayah (every surah except Al-Fatiha and At-Tawbah).
  final String? bismillah;

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'ayahs': ayahs.map((a) => a.toJson()).toList(),
    'bismillah': bismillah,
  };

  factory Surah.fromJson(Map<String, dynamic> j) => Surah(
    info: SurahInfo.fromJson(asMap(j['info'])),
    ayahs: (j['ayahs'] as List).map((e) => Ayah.fromJson(asMap(e))).toList(),
    bismillah: j['bismillah'] as String?,
  );
}

/// Al-Husary "Al-Mu'allim" (teaching) recording: the sheikh recites an ayah
/// and leaves time for the child to repeat it.
String teachingAudioUrl(int surah, int ayah) =>
    'https://everyayah.com/data/Husary_Muallim_128kbps/'
    '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';

/// Reads the surah number from Mom's weekly goal, e.g. "Al-'Asr (103)" -> 103.
int? surahNumberFrom(String goal) {
  final m = RegExp(r'\((\d{1,3})\)').firstMatch(goal);
  final n = m == null ? null : int.parse(m.group(1)!);
  return n != null && n >= 1 && n <= 114 ? n : null;
}

/// Parses api.alquran.cloud's
/// surah/{n}/editions/quran-uthmani,ar.husary,en.sahih.
Surah parseSurahResponse(Map<String, dynamic> body) {
  final editions = (body['data'] as List).map(asMap).toList();
  Map<String, dynamic>? byId(String id, int index) =>
      editions
          .where((e) => asMap(e['edition'] ?? const {})['identifier'] == id)
          .firstOrNull ??
      (index < editions.length ? editions[index] : null);
  final textEd = byId('quran-uthmani', 0)!;
  final audioEd = byId('ar.husary', 1) ?? textEd;
  final meaningEd = byId('en.sahih', 2);
  final info = SurahInfo.fromJson(textEd);
  final texts = (textEd['ayahs'] as List).map(asMap).toList();
  final audios = (audioEd['ayahs'] as List).map(asMap).toList();
  final meanings = meaningEd == null
      ? const <Map<String, dynamic>>[]
      : (meaningEd['ayahs'] as List).map(asMap).toList();
  String? bismillah;
  final ayahs = <Ayah>[];
  for (var i = 0; i < texts.length; i++) {
    var text = (texts[i]['text'] as String).trim();
    // The text service puts the Bismillah in front of each surah's first
    // ayah; show it as a heading instead (it is ayah 1 only in Al-Fatiha).
    if (i == 0 &&
        info.number != 1 &&
        info.number != 9 &&
        text.startsWith('بِسْمِ')) {
      final words = text.split(RegExp(r'\s+'));
      if (words.length > 4) {
        bismillah = words.take(4).join(' ');
        text = words.skip(4).join(' ');
      }
    }
    ayahs.add(
      Ayah(
        numberInSurah: (texts[i]['numberInSurah'] as num).toInt(),
        text: text,
        audioUrl: (audios[i]['audio'] as String?) ?? '',
        translation: i < meanings.length
            ? (meanings[i]['text'] as String? ?? '').trim()
            : '',
      ),
    );
  }
  return Surah(info: info, ayahs: ayahs, bismillah: bismillah);
}

class QuranException implements Exception {
  QuranException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QuranLibrary {
  static const _base = 'https://api.alquran.cloud/v1';

  static Future<Map<String, dynamic>> _get(String path) async {
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('$_base$path'))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw QuranException(
        'No internet connection. Connect once to download this surah.',
      );
    }
    if (res.statusCode != 200) {
      throw QuranException(
        'The Qur\'an service answered ${res.statusCode}. Try again later.',
      );
    }
    return asMap(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  static Future<List<SurahInfo>> surahList() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('quran_list');
    if (cached != null) {
      return (jsonDecode(cached) as List)
          .map((e) => SurahInfo.fromJson(asMap(e)))
          .toList();
    }
    final body = await _get('/surah');
    final list = (body['data'] as List)
        .map((e) => SurahInfo.fromJson(asMap(e)))
        .toList();
    await prefs.setString(
      'quran_list',
      jsonEncode(list.map((s) => s.toJson()).toList()),
    );
    return list;
  }

  static Future<Surah> surah(int number) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'quran_surah_v2_$number';
    final cached = prefs.getString(key);
    if (cached != null) return Surah.fromJson(asMap(jsonDecode(cached)));
    final surah = parseSurahResponse(
      await _get('/surah/$number/editions/quran-uthmani,ar.husary,en.sahih'),
    );
    await prefs.setString(key, jsonEncode(surah.toJson()));
    return surah;
  }
}

// ---------------- memorising: parts of long ayahs ----------------

/// Qur'an pause marks (waqf signs) where a reciter may stop: ۖ ۗ ۘ ۚ ۛ.
final _pauseMark = RegExp('[ۖۗۘۚۛ]');

/// A mark-only token such as "ۖ" standing between two words.
bool _isMarkOnly(String w) => w.replaceAll(RegExp('[ۖ-ۭ]'), '').trim().isEmpty;

/// Splits a long ayah into parts a child can learn one at a time: at the
/// pause marks first, then into pieces of about [size] words. Short ayahs
/// stay in one part.
List<String> ayahParts(String text, {int longerThan = 10, int size = 7}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final realWords = words.where((w) => !_isMarkOnly(w)).length;
  if (realWords <= longerThan) return [text.trim()];

  // 1. Cut after every pause mark.
  final pieces = <List<String>>[[]];
  for (final w in words) {
    if (_isMarkOnly(w)) {
      if (pieces.last.isNotEmpty) {
        pieces.last.add(w);
        pieces.add([]);
      }
      continue;
    }
    pieces.last.add(w);
    if (_pauseMark.hasMatch(w)) pieces.add([]);
  }
  pieces.removeWhere((p) => p.isEmpty);

  // 2. Very long pieces are cut into even chunks.
  final cut = <List<String>>[];
  for (final p in pieces) {
    final n = p.where((w) => !_isMarkOnly(w)).length;
    if (n <= size + 2) {
      cut.add(p);
      continue;
    }
    final chunks = (n / size).ceil();
    final per = (p.length / chunks).ceil();
    for (var i = 0; i < p.length; i += per) {
      cut.add(p.sublist(i, i + per > p.length ? p.length : i + per));
    }
  }

  // 3. Tiny pieces (one or two words) join the piece before them.
  final out = <List<String>>[];
  for (final p in cut) {
    final n = p.where((w) => !_isMarkOnly(w)).length;
    if (out.isNotEmpty && n <= 2) {
      out.last.addAll(p);
    } else {
      out.add([...p]);
    }
  }
  if (out.length > 1 && out.first.where((w) => !_isMarkOnly(w)).length <= 2) {
    out[1].insertAll(0, out.removeAt(0));
  }
  return [for (final p in out) p.join(' ')];
}

// ---------------- memorising: checking a recitation ----------------

/// Arabic letters only: no vowel marks, Qur'anic signs or letter variants,
/// so the Qur'an's spelling and what speech recognition writes compare.
String normalizeArabic(String s) => s
    .replaceAll('ٰ', 'ا') // small (dagger) alif is read as alif
    .replaceAll(RegExp('[ؐ-ًؚ-ٟۖ-ۭـ]'), '')
    .replaceAll(RegExp('[ٱأإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll(RegExp(r'[^ء-ي\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _words(String s) =>
    normalizeArabic(s).split(' ').where((w) => w.isNotEmpty).toList();

int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Small spelling differences (a missing alif or hamza) still count.
bool _sameWord(String expected, String heard) {
  if (expected == heard) return true;
  // "wa", "fa" and "bi" are sometimes written apart by speech recognition.
  final allowed = expected.length >= 6
      ? 2
      : expected.length >= 3
      ? 1
      : 0;
  return _distance(expected, heard) <= allowed;
}

class RecitationCheck {
  const RecitationCheck(this.words, this.correct);

  /// The ayah's words as written, and whether each one was heard.
  final List<String> words;
  final List<bool> correct;

  double get score =>
      correct.isEmpty ? 0 : correct.where((c) => c).length / correct.length;

  /// Good enough to move on.
  bool get passed => score >= 0.75;
}

/// Compares what speech recognition heard with the ayah (or part), word by
/// word and in order.
RecitationCheck checkRecitation(String expectedText, String heardText) {
  final shown = expectedText
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_isMarkOnly(w))
      .toList();
  final expected = [for (final w in shown) normalizeArabic(w)];
  // Speech recognition may join "wa" to the next word or split it off.
  final heard = _words(heardText);
  final joined = heard.join('');
  final correct = List<bool>.filled(expected.length, false);
  var j = 0;
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i];
    if (e.isEmpty) {
      correct[i] = true;
      continue;
    }
    for (var k = j; k < heard.length && k <= j + 3; k++) {
      final two = k + 1 < heard.length ? heard[k] + heard[k + 1] : null;
      if (_sameWord(e, heard[k])) {
        correct[i] = true;
        j = k + 1;
        break;
      }
      if (two != null && _sameWord(e, two)) {
        correct[i] = true;
        j = k + 2;
        break;
      }
    }
  }
  // Words recognised as one long run without spaces.
  if (heard.length <= 1 && expected.length > 1) {
    final all = expected.join('');
    if (_sameWord(all, joined) || joined.contains(all)) {
      correct.fillRange(0, correct.length, true);
    }
  }
  return RecitationCheck(shown, correct);
}

/// Ayat a child recited correctly with the microphone check, kept on this
/// device ("103:2" = Al-'Asr, ayah 2).
class QuranProgress {
  static const _key = 'quran_passed';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  static Future<void> markPassed(int surah, int ayah) async {
    final prefs = await SharedPreferences.getInstance();
    final all = (prefs.getStringList(_key) ?? const []).toSet()
      ..add('$surah:$ayah');
    await prefs.setStringList(_key, all.toList());
  }

  /// How many ayat of [surah] were recited correctly.
  static int countFor(Set<String> passed, int surah) =>
      passed.where((p) => p.startsWith('$surah:')).length;
}
