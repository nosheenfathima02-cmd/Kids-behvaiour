import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../quran.dart';

/// Listen to Sheikh Al-Husary ayah by ayah, repeat, and test yourself.
class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key, this.initialSurah = 1, this.title});
  final int initialSurah;
  final String? title;

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  late int _surahNumber = widget.initialSurah;
  Surah? _surah;
  String? _error;

  int? _current;
  int _repeat = 3;
  int _repeatLeft = 0;
  bool _teaching = true;
  bool _continue = true;
  bool _hideText = false;
  bool _playing = false;
  bool _warnedTeaching = false;
  final Set<int> _revealed = {};
  final Map<int, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _sub = _player.playerStateStream.listen(_onPlayerState);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _surah = null;
      _error = null;
      _current = null;
      _revealed.clear();
    });
    await _player.stop();
    try {
      final s = await QuranLibrary.surah(_surahNumber);
      if (mounted) setState(() => _surah = s);
    } on QuranException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onPlayerState(PlayerState s) {
    if (mounted && s.playing != _playing) setState(() => _playing = s.playing);
    if (s.processingState != ProcessingState.completed || _current == null) {
      return;
    }
    if (_repeatLeft > 1) {
      _repeatLeft--;
      _player.seek(Duration.zero).then((_) => _player.play());
    } else if (_continue && _current! + 1 < (_surah?.ayahs.length ?? 0)) {
      _playAyah(_current! + 1);
    } else {
      _player.pause();
      _player.seek(Duration.zero);
    }
  }

  Future<void> _playAyah(int index) async {
    final surah = _surah;
    if (surah == null) return;
    final ayah = surah.ayahs[index];
    setState(() {
      _current = index;
      _repeatLeft = _repeat;
    });
    _scrollTo(index);
    final urls = [
      if (_teaching) teachingAudioUrl(surah.info.number, ayah.numberInSurah),
      ayah.audioUrl,
    ];
    for (final url in urls) {
      try {
        await _player.setUrl(url);
        unawaited(_player.play());
        return;
      } catch (_) {
        if (url != urls.last && !_warnedTeaching && mounted) {
          _warnedTeaching = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Teaching recording not available; playing the normal recitation.',
              ),
            ),
          );
        }
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not play the recitation. Check the internet connection.',
          ),
        ),
      );
    }
  }

  void _scrollTo(int index) {
    final ctx = _keys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else if (_current != null &&
        _player.processingState != ProcessingState.idle) {
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surah = _surah;
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _Controls(
                  teaching: _teaching,
                  repeat: _repeat,
                  cont: _continue,
                  hide: _hideText,
                  onTeaching: (v) => setState(() => _teaching = v),
                  onRepeat: (v) => setState(() {
                    _repeat = v;
                    _repeatLeft = v;
                  }),
                  onContinue: (v) => setState(() => _continue = v),
                  onHide: (v) => setState(() {
                    _hideText = v;
                    _revealed.clear();
                  }),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recited by Sheikh Mahmoud Khalil Al-Husary',
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
                for (var i = 0; i < surah.ayahs.length; i++)
                  Card(
                    key: _keys.putIfAbsent(i, GlobalKey.new),
                    color: i == _current ? cs.primaryContainer : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
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
                                  child: Text(
                                    '${surah.ayahs[i].numberInSurah}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Spacer(),
                                if (i == _current && _repeat > 1)
                                  Text(
                                    '${_repeat - _repeatLeft + 1} of $_repeat  ',
                                  ),
                                Icon(
                                  i == _current && _playing
                                      ? Icons.graphic_eq
                                      : Icons.play_circle_outline,
                                  color: cs.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_hideText && !_revealed.contains(i))
                              TextButton(
                                onPressed: () =>
                                    setState(() => _revealed.add(i)),
                                child: const Text(
                                  'Say it from memory, then tap to check',
                                ),
                              )
                            else
                              Text(
                                surah.ayahs[i].text,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 28,
                                  height: 1.9,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: surah == null
          ? null
          : SafeArea(
              child: Padding(
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
              ),
            ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.teaching,
    required this.repeat,
    required this.cont,
    required this.hide,
    required this.onTeaching,
    required this.onRepeat,
    required this.onContinue,
    required this.onHide,
  });
  final bool teaching;
  final int repeat;
  final bool cont;
  final bool hide;
  final ValueChanged<bool> onTeaching;
  final ValueChanged<int> onRepeat;
  final ValueChanged<bool> onContinue;
  final ValueChanged<bool> onHide;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Teaching: repeat after him'),
                ),
                ButtonSegment(value: false, label: Text('Recitation')),
              ],
              selected: {teaching},
              onSelectionChanged: (s) => onTeaching(s.first),
            ),
            const SizedBox(height: 12),
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
