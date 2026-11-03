import 'package:flutter_test/flutter_test.dart';
import 'package:super_mom/quran.dart';

Map<String, dynamic> response(int number, List<String> texts) => {
  'code': 200,
  'data': [
    {
      'number': number,
      'name': 'سُورَةُ العَصۡرِ',
      'englishName': 'Al-Asr',
      'englishNameTranslation': 'The Declining Day',
      'numberOfAyahs': texts.length,
      'ayahs': [
        for (var i = 0; i < texts.length; i++)
          {'number': 6200 + i, 'text': texts[i], 'numberInSurah': i + 1},
      ],
    },
    {
      'number': number,
      'ayahs': [
        for (var i = 0; i < texts.length; i++)
          {
            'number': 6200 + i,
            'audio':
                'https://cdn.islamic.network/quran/audio/128/ar.husary/${6200 + i}.mp3',
            'numberInSurah': i + 1,
          },
      ],
    },
  ],
};

void main() {
  memorisingTests();
  test(
    'reads text and Al-Husary audio, and moves the Bismillah to a heading',
    () {
      final surah = parseSurahResponse(
        response(103, [
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ وَٱلْعَصْرِ',
          'إِنَّ ٱلْإِنسَٰنَ لَفِى خُسْرٍ',
          'إِلَّا ٱلَّذِينَ ءَامَنُوا۟',
        ]),
      );
      expect(surah.info.number, 103);
      expect(surah.info.englishName, 'Al-Asr');
      expect(surah.bismillah, 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ');
      expect(surah.ayahs.first.text, 'وَٱلْعَصْرِ');
      expect(surah.ayahs.length, 3);
      expect(surah.ayahs[1].audioUrl, endsWith('/ar.husary/6201.mp3'));
    },
  );

  test('Al-Fatiha keeps the Bismillah as its first ayah', () {
    final surah = parseSurahResponse(
      response(1, [
        'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
        'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ',
      ]),
    );
    expect(surah.bismillah, isNull);
    expect(surah.ayahs.first.text, startsWith('بِسْمِ'));
  });

  test('teaching recording links use surah and ayah numbers', () {
    expect(
      teachingAudioUrl(103, 2),
      'https://everyayah.com/data/Husary_Muallim_128kbps/103002.mp3',
    );
    expect(teachingAudioUrl(1, 1), endsWith('/001001.mp3'));
  });

  test("the weekly goal opens the right surah", () {
    expect(surahNumberFrom("Al-'Asr (103)"), 103);
    expect(surahNumberFrom('Al-Ikhlas (112)'), 112);
    expect(surahNumberFrom('Al-Mulk'), isNull);
    expect(surahNumberFrom('Something (200)'), isNull);
  });

  test('a downloaded surah survives the cache round trip', () {
    final surah = parseSurahResponse(
      response(103, ['بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ وَٱلْعَصْرِ']),
    );
    final back = Surah.fromJson(surah.toJson());
    expect(back.ayahs.first.text, surah.ayahs.first.text);
    expect(back.bismillah, surah.bismillah);
    expect(back.info.ayahCount, 1);
  });
}

const ayatAlKursi =
    'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ '
    'لَّهُۥ مَا فِى ٱلسَّمَٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ ۚ '
    'يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَىْءٍ مِّنْ عِلْمِهِۦٓ إِلَّا بِمَا شَآءَ ۚ '
    'وَسِعَ كُرْسِيُّهُ ٱلسَّمَٰوَٰتِ وَٱلْأَرْضَ ۖ وَلَا يَـُٔودُهُۥ حِفْظُهُمَا ۚ وَهُوَ ٱلْعَلِىُّ ٱلْعَظِيمُ';

void memorisingTests() {
  test('a long ayah is split at its pause marks into short parts', () {
    final parts = ayahParts(ayatAlKursi);
    expect(parts.length, greaterThanOrEqualTo(6));
    expect(parts.first, startsWith('ٱللَّهُ لَآ إِلَٰهَ'));
    expect(parts.first, endsWith('ٱلْقَيُّومُ ۚ'));
    for (final p in parts) {
      expect(
        p.split(' ').where((w) => w.length > 1).length,
        inInclusiveRange(3, 10),
      );
    }
    // Nothing is lost.
    expect(
      parts.join(' ').replaceAll(' ', ''),
      ayatAlKursi.replaceAll(' ', ''),
    );
  });

  test('a short ayah stays whole', () {
    expect(ayahParts('إِنَّ ٱلْإِنسَٰنَ لَفِى خُسْرٍ'), [
      'إِنَّ ٱلْإِنسَٰنَ لَفِى خُسْرٍ',
    ]);
  });

  test("the Qur'an's spelling and plain Arabic compare", () {
    expect(normalizeArabic('ٱلرَّحْمَٰنِ'), 'الرحمان');
    expect(normalizeArabic('ٱلْحَىُّ'), 'الحي');
    expect(normalizeArabic('لَا تَأْخُذُهُۥ'), 'لا تاخذه');
  });

  test('a correct recitation passes, even with small spelling differences', () {
    final c = checkRecitation(
      'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ',
      'الله لا إله إلا هو الحي القيوم',
    );
    expect(c.correct, everyElement(isTrue));
    expect(c.words.length, 7);
    expect(c.passed, isTrue);
  });

  test('missed words are marked, and too many misses do not pass', () {
    final c = checkRecitation(
      'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ',
      'الله لا اله الحي',
    );
    expect(c.correct, [true, true, true, false, false, true, false]);
    expect(c.passed, isFalse);
    expect(checkRecitation('وَٱلْعَصْرِ', '').passed, isFalse);
  });

  test('the meaning in English is read with the ayah and cached', () {
    final body = response(103, [
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ وَٱلْعَصْرِ',
    ]);
    (body['data'] as List).add({
      'number': 103,
      'edition': {'identifier': 'en.sahih'},
      'ayahs': [
        {'number': 6200, 'text': 'By time,', 'numberInSurah': 1},
      ],
    });
    final surah = parseSurahResponse(body);
    expect(surah.ayahs.first.translation, 'By time,');
    expect(Surah.fromJson(surah.toJson()).ayahs.first.translation, 'By time,');
  });
}
