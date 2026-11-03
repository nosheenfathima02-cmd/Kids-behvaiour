import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../hijri.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'kid_screen.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _date(DateTime d) =>
    '${_days[d.weekday]} ${d.day} ${_months[d.month - 1]}';

/// Ramadan for children: the countdown, suhoor and iftar times, a fasting
/// tracker, and the sunnah fasts the rest of the year.
class RamadanTab extends StatefulWidget {
  const RamadanTab({super.key, required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  State<RamadanTab> createState() => _RamadanTabState();
}

class _RamadanTabState extends State<RamadanTab> {
  Set<int> _fasted = {};

  String get _key =>
      'ramadan_${toHijri(widget.store.now).year}_${widget.kid.id}';

  @override
  void initState() {
    super.initState();
    _loadFasts();
  }

  Future<void> _loadFasts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final days = prefs.getStringList(_key) ?? const [];
      if (mounted) {
        setState(() => _fasted = {for (final d in days) int.parse(d)});
      }
    } catch (_) {}
  }

  Future<void> _toggleFast(int day) async {
    setState(
      () => _fasted.contains(day) ? _fasted.remove(day) : _fasted.add(day),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final d in _fasted) '$d']);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now;
    final today = toHijri(now);
    final times = store.prayersToday.times;
    return KidTabPage(
      header: KidTabHeader(
        kid: widget.kid,
        title: 'Ramadan 🌙',
        subtitle: 'About $today',
      ),
      children: today.isRamadan
          ? _inRamadan(context, today, times)
          : _restOfYear(context, now),
    );
  }

  List<Widget> _inRamadan(
    BuildContext context,
    HijriDate today,
    Map<Prayer, int> times,
  ) {
    final cs = Theme.of(context).colorScheme;
    final minute = widget.store.nowMinute;
    final iftar = times[Prayer.maghrib]!;
    final left = iftar - minute;
    return [
      SectionCard(
        title: 'Ramadan day ${today.day}',
        trailing: Text(
          '${_fasted.length} fasts',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🌅 Suhoor ends at Fajr: ${formatMinute(times[Prayer.fajr]!)}',
            ),
            Text('🌇 Iftar at Maghrib: ${formatMinute(iftar)}'),
            if (left > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Iftar in ${left >= 60 ? '${left ~/ 60} h ' : ''}${left % 60} min. You can do it!',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'My fasts',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tap today when you fast. Half days count too!'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 30; d++)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    // Only today and earlier days can be ticked.
                    onTap: d <= today.day ? () => _toggleFast(d) : null,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _fasted.contains(d)
                            ? starGold
                            : d == today.day
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        border: d == today.day
                            ? Border.all(color: cs.primary, width: 2)
                            : null,
                      ),
                      child: _fasted.contains(d)
                          ? const Text('🌙')
                          : Text(
                              '$d',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: d > today.day ? cs.outline : null,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const _DuaCard(),
      const SizedBox(height: 12),
      const _GoodDeedsCard(),
    ];
  }

  List<Widget> _restOfYear(BuildContext context, DateTime now) {
    final start = nextRamadanStart(now);
    final days = start
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final bonus = widget.store.score(widget.kid).bonus;
    return [
      SectionCard(
        title: 'Ramadan is coming!',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$days days to go',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              'Expected to start around ${_date(start)} ${start.year}. '
              'The exact day depends on the moon sighting.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Practise with sunnah fasts',
        trailing: bonus > 0
            ? Text(
                '+$bonus ★',
                style: const TextStyle(
                  color: starGold,
                  fontWeight: FontWeight.w800,
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Prophet, peace be upon him, fasted on Mondays and Thursdays, and on the 13th, 14th and 15th of each Islamic month. '
              'Ask Mom first, and each fast gives you a bonus star!',
            ),
            const SizedBox(height: 8),
            for (final (day, why) in nextSunnahFasts(now))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Text('🌙  '),
                    Expanded(
                      child: Text(
                        '${_date(day)} · $why',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const _DuaCard(),
    ];
  }
}

class _DuaCard extends StatelessWidget {
  const _DuaCard();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: 'Dua for breaking the fast',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ذَهَبَ الظَّمَأُ وَابْتَلَّتِ الْعُرُوقُ وَثَبَتَ الْأَجْرُ إِنْ شَاءَ اللَّهُ',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 22, height: 1.8),
        ),
        SizedBox(height: 4),
        Text(
          'Dhahaba al-ẓama’u wabtallat al-‘urūq wa thabata al-ajru in shā’ Allāh',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        Text(
          '"The thirst is gone, the veins are moistened, and the reward is certain, if Allah wills." (Abu Dawud)',
        ),
      ],
    ),
  );
}

class _GoodDeedsCard extends StatelessWidget {
  const _GoodDeedsCard();

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: 'Ramadan good deeds',
    child: Text(
      '📖 Read a little Qur\'an every day\n'
      '🤲 Make dua before iftar\n'
      '🍽️ Help set the table for iftar\n'
      '💝 Give some sadaqah, even a smile\n'
      '🕌 Pray taraweeh with your family',
      style: TextStyle(height: 1.7),
    ),
  );
}
