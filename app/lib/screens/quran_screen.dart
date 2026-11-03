import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../quran.dart';

enum QuranMode { listen, teaching, check }

/// Listen to Sheikh Al-Husary ayah by ayah, repeat after him, and recite
/// back to the microphone to check each ayah (long ayat part by part).
class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key, this.initialSurah = 1, this.title});
  final int initialSurah;
  final String? title;

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  final _player = AudioPlayer();
  final _speech = SpeechToText();
  StreamSubscription<PlayerState>? _sub;
  StreamSubscription<Duration>? _posSub;
  late int _surahNumber = widget.initialSurah;
  Surah? _surah;
  String? _error;

  int? _current;
  int _repeat = 1;
  int _repeatLeft = 0;
  QuranMode _mode = QuranMode.check;
  bool _continue = true;
  bool _hideText = false;
  bool _meaning = true;
  bool _playing = false;
  bool _warnedTeaching = false;
  final Set<int> _revealed = {};
  final Map<int, GlobalKey> _keys = {};

  /// Which part of the current ayah the recitation has reached (estimated
  /// from how far the recording has played).
  int _playingPart = 0;
  Duration? _duration;

  // The child's turn (Recite & check).
  bool _myTurn = false;
  int _turnPart = 0;
  bool _listening = false;
  String _heard = '';
  RecitationCheck? _result;
  String? _localeId;
  bool _speechReady = false;
  final Map<String, RecitationCheck> _checks = {}; // "ayah:part"
  Set<String> _passed = {};

  @override
  void initState() {
    super.initState();
    _sub = _player.playerStateStream.listen(_onPlayerState);
    _posSub = _player.positionStream.listen(_onPosition);
    QuranProgress.load().then((p) {
      if (mounted) setState(() => _passed = p);
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _posSub?.cancel();
    _speech.cancel();
    _player.dispose();
    super.dispose();
  }

  List<String> _partsOf(int i) => ayahParts(_surah!.ayahs[i].text);

  Future<void> _load() async {
    setState(() {
      _surah = null;
      _error = null;
      _current = null;
      _myTurn = false;
      _revealed.clear();
      _checks.clear();
    });
    await _player.stop();
    try {
      final s = await QuranLibrary.surah(_surahNumber);
      if (mounted) setState(() => _surah = s);
    } on QuranException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onPosition(Duration pos) {
    final d = _duration;
    if (_current == null || d == null || d.inMilliseconds == 0) return;
    if (_mode == QuranMode.teaching) return; // has pauses: no estimate
    final parts = _partsOf(_current!);
    if (parts.length < 2) return;
    // Each part takes about as long as its share of the letters.
    final lengths = [for (final p in parts) normalizeArabic(p).length + 1];
    final total = lengths.reduce((a, b) => a + b);
    final at = pos.inMilliseconds / d.inMilliseconds * total;
    var sum = 0, part = 0;
    for (; part < lengths.length - 1; part++) {
      sum += lengths[part];
      if (at < sum) break;
    }
    if (part != _playingPart && mounted) setState(() => _playingPart = part);
  }

  void _onPlayerState(PlayerState s) {
    if (mounted && s.playing != _playing) setState(() => _playing = s.playing);
    if (s.processingState != ProcessingState.completed || _current == null) {
      return;
    }
    if (_myTurn) {
      // "Hear this part" / "Listen again" finished: still the child's turn.
      _player.pause();
      return;
    }
    if (_repeatLeft > 1) {
      _repeatLeft--;
      _player.seek(Duration.zero).then((_) => _player.play());
      return;
    }
    _player.pause();
    _player.seek(Duration.zero);
    if (_mode == QuranMode.check) {
      _startTurn(0);
    } else {
      _next();
    }
  }

  void _next() {
    if (_continue && _current! + 1 < (_surah?.ayahs.length ?? 0)) {
      _playAyah(_current! + 1);
    }
  }

  Future<void> _playAyah(int index) async {
    final surah = _surah;
    if (surah == null) return;
    await _stopListening();
    final ayah = surah.ayahs[index];
    setState(() {
      _current = index;
      _repeatLeft = _mode == QuranMode.check ? 1 : _repeat;
      _playingPart = 0;
      _myTurn = false;
      _result = null;
      _heard = '';
    });
    _scrollTo(index);
    final urls = [
      if (_mode == QuranMode.teaching)
        teachingAudioUrl(surah.info.number, ayah.numberInSurah),
      ayah.audioUrl,
    ];
    for (final url in urls) {
      try {
        _duration = await _player.setUrl(url);
        unawaited(_player.play());
        return;
      } catch (_) {
        if (url != urls.last && !_warnedTeaching && mounted) {
          _warnedTeaching = true;
          _say(
            'Teaching recording not available; playing the normal recitation.',
          );
        }
      }
    }
    _say('Could not play the recitation. Check the internet connection.');
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollTo(int index) {
    final ctx = _keys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.2,
      );
    }
  }

  // ---------------- the child's turn ----------------

  Future<bool> _prepareSpeech() async {
    if (_speechReady) return true;
    final ok = await _speech.initialize(
      onError: (e) {
        if (!mounted) return;
        setState(() => _listening = false);
        if (e.errorMsg.contains('no_match') ||
            e.errorMsg.contains('speech_timeout')) {
          _finishTurn();
        }
      },
      onStatus: (s) {
        if (mounted && (s == 'done' || s == 'notListening')) {
          setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      _say(
        'The microphone is not available. Allow Super Mom to use the microphone in the phone settings.',
      );
      return false;
    }
    final locales = await _speech.locales();
    final arabic = locales.where(
      (l) => l.localeId.toLowerCase().startsWith('ar'),
    );
    _localeId =
        arabic
            .where((l) => l.localeId.toLowerCase().contains('sa'))
            .firstOrNull
            ?.localeId ??
        arabic.firstOrNull?.localeId ??
        'ar-SA';
    _speechReady = true;
    return true;
  }

  Future<void> _startTurn(int part) async {
    if (_current == null) return;
    setState(() {
      _myTurn = true;
      _turnPart = part;
      _heard = '';
      _result = null;
    });
    await _listen();
  }

  Future<void> _listen() async {
    if (!await _prepareSpeech() || _current == null) return;
    await _player.pause();
    final expected = _partsOf(_current!)[_turnPart];
    setState(() {
      _heard = '';
      _result = null;
      _listening = true;
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) _finishTurn();
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 40),
        pauseFor: const Duration(seconds: 4),
        contextualPhrases: [normalizeArabic(expected)],
      ),
    );
  }

  Future<void> _stopListening() async {
    if (_speech.isListening) await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _finishTurn() {
    final i = _current;
    if (i == null || !_myTurn || _result != null) return;
    final check = checkRecitation(_partsOf(i)[_turnPart], _heard);
    setState(() {
      _listening = false;
      _result = check;
      _checks['$i:$_turnPart'] = check;
      _revealed.add(i);
    });
    if (check.passed) {
      Timer(const Duration(milliseconds: 1600), () {
        if (!mounted || _current != i || _result != check) return;
        _afterPass();
      });
    }
  }

  void _afterPass({bool skipped = false}) {
    final i = _current!;
    if (_turnPart + 1 < _partsOf(i).length) {
      _startTurn(_turnPart + 1);
      return;
    }
    // Every part was recited correctly (none skipped).
    final allPassed =
        !skipped &&
        List.generate(
          _partsOf(i).length,
          (p) => _checks['$i:$p']?.passed ?? false,
        ).every((ok) => ok);
    if (!allPassed) {
      setState(() => _myTurn = false);
      _next();
      return;
    }
    QuranProgress.markPassed(
      _surah!.info.number,
      _surah!.ayahs[i].numberInSurah,
    );
    setState(() {
      _passed.add('${_surah!.info.number}:${_surah!.ayahs[i].numberInSurah}');
      _myTurn = false;
    });
    _next();
  }

  /// Plays just one part of a long ayah (its place in the recording is
  /// estimated from its length).
  Future<void> _hearPart() async {
    final i = _current, d = _duration;
    if (i == null) return;
    await _stopListening();
    final parts = _partsOf(i);
    if (parts.length < 2 || d == null) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    final lengths = [for (final p in parts) normalizeArabic(p).length + 1];
    final total = lengths.reduce((a, b) => a + b);
    final before = lengths.take(_turnPart).fold(0, (a, b) => a + b);
    final startMs = (d.inMilliseconds * before / total - 400).clamp(
      0,
      d.inMilliseconds,
    );
    final endMs =
        (d.inMilliseconds * (before + lengths[_turnPart]) / total + 500).clamp(
          0,
          d.inMilliseconds,
        );
    setState(() => _repeatLeft = 1);
    await _player.seek(Duration(milliseconds: startMs.round()));
    unawaited(_player.play());
    Timer(Duration(milliseconds: (endMs - startMs).round()), () {
      if (mounted && _myTurn) _player.pause();
    });
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else if (_current != null &&
        !_myTurn &&
        _player.processingState != ProcessingState.idle &&
        _player.processingState != ProcessingState.completed) {
      await _player.play();
    } else {
      await _playAyah(_current ?? 0);
    }
  }

  Future<void> _pickSurah() async {
    List<SurahInfo> list;
    try {
      list = await QuranLibrary.surahList();
    } on QuranException catch (e) {
      _say(e.message);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choose a surah',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            // Juz 'Amma (the short surahs children learn first) at the top.
            for (final s in [
              ...list.where((s) => s.number == 1 || s.number >= 78),
              ...list.where((s) => s.number > 1 && s.number < 78),
            ])
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    '${s.number}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                title: Text(s.englishName),
                subtitle: Text('${s.meaning} · ${s.ayahCount} ayat'),
                trailing: Text(
                  s.arabicName,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 18),
                ),
                selected: s.number == _surahNumber,
                onTap: () => Navigator.pop(ctx, s.number),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _surahNumber) {
      _surahNumber = picked;
      await _load();
    }
  }

  // ---------------- screen ----------------

  @override
  Widget build(BuildContext context) {
    final surah = _surah;
    final learned = surah == null
        ? 0
        : QuranProgress.countFor(_passed, surah.info.number);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          surah == null
              ? (widget.title ?? "Qur'an")
              : '${surah.info.englishName} · ${surah.info.arabicName}',
        ),
        actions: [
          TextButton.icon(
            onPressed: _pickSurah,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Surah'),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : surah == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _Controls(
                  mode: _mode,
                  repeat: _repeat,
                  cont: _continue,
                  hide: _hideText,
                  meaning: _meaning,
                  onMode: (v) async {
                    await _stopListening();
                    await _player.stop();
                    setState(() {
                      _mode = v;
                      _myTurn = false;
                    });
                  },
                  onRepeat: (v) => setState(() {
                    _repeat = v;
                    _repeatLeft = v;
                  }),
                  onContinue: (v) => setState(() => _continue = v),
                  onHide: (v) => setState(() {
                    _hideText = v;
                    _revealed.clear();
                  }),
                  onMeaning: (v) => setState(() => _meaning = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recited by Sheikh Mahmoud Khalil Al-Husary · '
                  'Recited correctly: $learned of ${surah.ayahs.length} ayat',
                  textAlign: TextAlign.center,
                ),
                if (surah.bismillah != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      surah.bismillah!,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                for (var i = 0; i < surah.ayahs.length; i++) _ayahCard(i),
              ],
            ),
      bottomNavigationBar: surah == null
          ? null
          : SafeArea(child: _myTurn ? _turnPanel() : _playerBar(surah)),
    );
  }

  Widget _ayahCard(int i) {
    final cs = Theme.of(context).colorScheme;
    final surah = _surah!;
    final ayah = surah.ayahs[i];
    final parts = _partsOf(i);
    final current = i == _current;
    final passed = _passed.contains(
      '${surah.info.number}:${ayah.numberInSurah}',
    );
    final hidden = _hideText && !_revealed.contains(i);
    return Card(
      key: _keys.putIfAbsent(i, GlobalKey.new),
      color: current ? cs.primaryContainer.withValues(alpha: 0.55) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: current
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _playAyah(i),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: passed ? const Color(0xFF23824F) : null,
                    child: passed
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${ayah.numberInSurah}',
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                  if (parts.length > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${parts.length} parts',
                      style: TextStyle(color: cs.outline, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  if (current && _repeat > 1 && _mode != QuranMode.check)
                    Text('${_repeat - _repeatLeft + 1} of $_repeat  '),
                  Icon(
                    current && _playing
                        ? Icons.graphic_eq
                        : Icons.play_circle_outline,
                    color: cs.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (hidden)
                TextButton(
                  onPressed: () => setState(() => _revealed.add(i)),
                  child: const Text('Say it from memory, then tap to check'),
                )
              else
                for (var p = 0; p < parts.length; p++)
                  _partText(i, p, parts[p], parts.length > 1),
              if (_meaning && ayah.translation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ayah.translation,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One part of an ayah: highlighted while it is recited or while it is the
  /// child's turn, and coloured word by word after a check.
  Widget _partText(int i, int p, String text, bool split) {
    final active =
        i == _current &&
        ((_myTurn && _turnPart == p) ||
            (!_myTurn && _playing && (!split || _playingPart == p)));
    final check = _checks['$i:$p'];
    const style = TextStyle(fontSize: 28, height: 1.9);
    Widget child;
    if (check != null) {
      child = Text.rich(
        TextSpan(
          children: [
            for (var w = 0; w < check.words.length; w++)
              TextSpan(
                text: '${check.words[w]} ',
                style: TextStyle(
                  color: check.correct[w]
                      ? const Color(0xFF1E7A45)
                      : const Color(0xFFC62828),
                  decoration: check.correct[w]
                      ? null
                      : TextDecoration.underline,
                ),
              ),
          ],
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        style: style,
      );
    } else {
      child = Text(
        text,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        style: style,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFE9A8) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _playerBar(Surah surah) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous ayah',
          iconSize: 32,
          onPressed: (_current ?? 0) > 0
              ? () => _playAyah(_current! - 1)
              : null,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 16),
        IconButton.filled(
          tooltip: _playing ? 'Pause' : 'Play',
          iconSize: 40,
          onPressed: _togglePlay,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Next ayah',
          iconSize: 32,
          onPressed: (_current ?? -1) + 1 < surah.ayahs.length
              ? () => _playAyah((_current ?? -1) + 1)
              : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    ),
  );

  /// "Your turn": the child recites the ayah (or part) to the microphone.
  Widget _turnPanel() {
    final cs = Theme.of(context).colorScheme;
    final i = _current!;
    final parts = _partsOf(i);
    final r = _result;
    final title = parts.length > 1
        ? 'Your turn · part ${_turnPart + 1} of ${parts.length}'
        : 'Your turn · ayah ${_surah!.ayahs[i].numberInSurah}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                onPressed: () async {
                  await _stopListening();
                  setState(() => _myTurn = false);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (r == null)
            Text(
              _listening
                  ? (_heard.isEmpty ? '🎙️ Listening… recite now' : _heard)
                  : 'Tap the microphone and recite.',
              textDirection: _heard.isEmpty ? null : TextDirection.rtl,
              style: TextStyle(
                fontSize: _heard.isEmpty ? 15 : 20,
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Text(
              r.passed
                  ? (r.score == 1
                        ? 'MashaAllah! Perfect ⭐'
                        : 'MashaAllah! Well done ✓')
                  : 'Almost! The red words were missed. Listen and try again.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: r.passed
                    ? const Color(0xFF1E7A45)
                    : const Color(0xFFC62828),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _hearPart,
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(
                  parts.length > 1 ? 'Hear this part' : 'Listen again',
                ),
              ),
              FilledButton.icon(
                onPressed: _listening ? _stopListening : _listen,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(
                  _listening ? 'Done' : (r == null ? 'Recite' : 'Try again'),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _stopListening();
                  _afterPass(skipped: true);
                },
                child: const Text('Skip'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.mode,
    required this.repeat,
    required this.cont,
    required this.hide,
    required this.meaning,
    required this.onMode,
    required this.onRepeat,
    required this.onContinue,
    required this.onHide,
    required this.onMeaning,
  });
  final QuranMode mode;
  final int repeat;
  final bool cont;
  final bool hide;
  final bool meaning;
  final ValueChanged<QuranMode> onMode;
  final ValueChanged<int> onRepeat;
  final ValueChanged<bool> onContinue;
  final ValueChanged<bool> onHide;
  final ValueChanged<bool> onMeaning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<QuranMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: QuranMode.check,
                  icon: Icon(Icons.mic_none),
                  label: Text('Check me'),
                ),
                ButtonSegment(value: QuranMode.teaching, label: Text('Repeat')),
                ButtonSegment(value: QuranMode.listen, label: Text('Listen')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),
            const SizedBox(height: 8),
            Text(switch (mode) {
              QuranMode.check =>
                'Check me: listen to each ayah, then recite it to the microphone. '
                    'Long ayat are learned part by part. Green words were right.',
              QuranMode.teaching => 'Repeat: Sheikh Al-Husary recites and pauses for you to repeat after him.',
              QuranMode.listen => 'Listen to the recitation.',
            }, style: Theme.of(context).textTheme.bodySmall),
            if (mode != QuranMode.check) ...[
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text('Repeat each ayah'),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final n in const [1, 3, 5, 10])
                        ChoiceChip(
                          label: Text('$n×'),
                          selected: repeat == n,
                          onSelected: (_) => onRepeat(n),
                        ),
                    ],
                  ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show the meaning (English)'),
              value: meaning,
              onChanged: onMeaning,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Go on to the next ayah'),
              value: cont,
              onChanged: onContinue,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide the text to test myself'),
              value: hide,
              onChanged: onHide,
            ),
          ],
        ),
      ),
    );
  }
}
