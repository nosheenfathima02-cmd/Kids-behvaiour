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
  });
  final int numberInSurah;
  final String text;

  /// Al-Husary's normal (murattal) recitation of this ayah.
  final String audioUrl;

  Map<String, dynamic> toJson() => {
    'n': numberInSurah,
    't': text,
    'a': audioUrl,
  };
  factory Ayah.fromJson(Map<String, dynamic> j) => Ayah(
    numberInSurah: (j['n'] as num).toInt(),
    text: j['t'] as String,
    audioUrl: j['a'] as String,
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

/// Parses api.alquran.cloud's surah/{n}/editions/quran-uthmani,ar.husary.
Surah parseSurahResponse(Map<String, dynamic> body) {
  final editions = (body['data'] as List).map(asMap).toList();
  final textEd = editions.first;
  final audioEd = editions.length > 1 ? editions[1] : editions.first;
  final info = SurahInfo.fromJson(textEd);
  final texts = (textEd['ayahs'] as List).map(asMap).toList();
  final audios = (audioEd['ayahs'] as List).map(asMap).toList();
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
    final key = 'quran_surah_v1_$number';
    final cached = prefs.getString(key);
    if (cached != null) return Surah.fromJson(asMap(jsonDecode(cached)));
    final surah = parseSurahResponse(
      await _get('/surah/$number/editions/quran-uthmani,ar.husary'),
    );
    await prefs.setString(key, jsonEncode(surah.toJson()));
    return surah;
  }
}
