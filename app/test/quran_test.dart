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
