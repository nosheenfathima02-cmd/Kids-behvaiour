import 'package:flutter/material.dart';

import '../classroom.dart';
import '../content.dart';
import 'ramadan_tab.dart';
import '../logic.dart';

import 'package:just_audio/just_audio.dart';

import '../main.dart';
import '../models.dart';
import '../notifications.dart';
import '../prayer.dart';
import '../quran.dart';
import '../store.dart';
import '../widgets.dart';
import 'mom_screen.dart';
import 'quran_screen.dart';
import 'school_screens.dart';

/// The lock button on the kids' screens.
Future<void> openParentArea(BuildContext context) async {
  final store = StoreScope.of(context);
  if (!store.isParent) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parent settings'),
        content: Text(
          'Changes are made in the Super Mom app on Mom\'s phone.\n\n'
          'This device: ${store.deviceName.isEmpty ? 'linked' : store.deviceName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  if (await askParentPin(context, store) && context.mounted) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    store.setKidsMode(false);
  }
}

/// What the app opens to. A parent's phone shows the parent screens unless
/// it was handed to the kids. A device linked to one child goes straight to
/// that child's page; a shared device shows a "Who are you?" picker.
class KidEntryScreen extends StatelessWidget {
  const KidEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.isParent && !store.kidsMode) return const MomScreen();
    final kids = store.visibleKids;
    if (kids.length == 1) return KidHome(kid: kids.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Mom'),
        actions: [
          IconButton(
            tooltip: 'Parent',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => openParentArea(context),
          ),
        ],
      ),
      body: kids.isEmpty
          ? const Center(
              child: Text('Ask Mom to add you in the parent screens.'),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Who are you?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final k in kids)
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => KidHome(kid: k)),
                          ),
                          child: Container(
                            width: 140,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              gradient: themeOf(k).gradient,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: themeOf(k).color
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  themeOf(k).emoji,
                                  style: const TextStyle(fontSize: 44),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  k.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class KidAvatar extends StatelessWidget {
  const KidAvatar({super.key, required this.kid, this.radius = 22});
  final Kid kid;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = themeOf(kid);
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: t.gradient,
        boxShadow: [
          BoxShadow(
            color: t.color.withValues(alpha: 0.3),
            blurRadius: radius * 0.4,
            offset: Offset(0, radius * 0.1),
          ),
        ],
      ),
      child: Text(
        kid.name.isEmpty ? '?' : kid.name[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

class KidHome extends StatefulWidget {
  const KidHome({super.key, required this.kid});
  final Kid kid;

  @override
  State<KidHome> createState() => _KidHomeState();
}

/// A child's app: five tabs along the bottom.
class _KidHomeState extends State<KidHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kid = widget.kid;
    final t = themeOf(kid);
    final brightness = Theme.of(context).brightness;
    final hasSchool =
        store.schoolItemsFor(kid).isNotEmpty ||
        store.noticesFor(kid).isNotEmpty;
    return Theme(
      data: buildKidTheme(t, brightness),
      child: Builder(
        builder: (context) {
          final tabs = <Widget>[
            _DayTab(kid: kid, store: store),
            _PrayerTab(kid: kid, store: store),
            _QuranTab(kid: kid),
            _SchoolTab(kid: kid, store: store),
            RamadanTab(kid: kid, store: store),
          ];
          return Scaffold(
            body: IndexedStack(index: _tab, children: tabs),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.checklist_rounded),
                  label: 'My day',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.mosque_outlined),
                  selectedIcon: Icon(Icons.mosque),
                  label: 'Prayer',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: "Qur'an",
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: hasSchool,
                    smallSize: 8,
                    child: const Icon(Icons.school_outlined),
                  ),
                  selectedIcon: const Icon(Icons.school),
                  label: 'School',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.nightlight_outlined),
                  selectedIcon: Icon(Icons.nightlight),
                  label: 'Ramadan',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A scrolling tab page, centred on wide screens.
class KidTabPage extends StatelessWidget {
  const KidTabPage({super.key, required this.header, required this.children});
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      header,
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ],
  );
}

/// The smaller coloured header of the other tabs.
class KidTabHeader extends StatelessWidget {
  const KidTabHeader({
    super.key,
    required this.kid,
    required this.title,
    this.subtitle,
  });
  final Kid kid;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = themeOf(kid);
    final canPop = Navigator.of(context).canPop();
    return Container(
      decoration: BoxDecoration(
        gradient: t.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPop)
                const BackButton(color: Colors.white)
              else
                const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Parent',
                color: Colors.white,
                icon: const Icon(Icons.lock_outline),
                onPressed: () => openParentArea(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSalah(RoutineTask t) => t.category == TaskCategory.salah;

class _DayTab extends StatelessWidget {
  const _DayTab({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) => KidTabPage(
    header: _Hero(kid: kid, store: store),
    children: [
      if (kid.examMode) ...[
        const _Banner(
          "📖 Exam week! Only salah, Qur'an and study today. You can do it, in sha Allah.",
        ),
        const SizedBox(height: 12),
      ],
      if (store.isWeekend) ...[
        _Banner(
          "🎉 It's the weekend! You earned ${store.score(kid).total} stars this week. "
          'A new week starts on Monday.',
        ),
        const SizedBox(height: 12),
      ],
      _StarsCard(kid: kid, store: store),
      if (!store.isWeekend) ...[
        const SizedBox(height: 12),
        _JobsCard(
          kid: kid,
          store: store,
          title: 'My jobs & chores today',
          where: (t) => !_isSalah(t),
        ),
      ],
      const SizedBox(height: 12),
      _RewardsCard(kid: kid, store: store),
    ],
  );
}

class _PrayerTab extends StatelessWidget {
  const _PrayerTab({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) => KidTabPage(
    header: KidTabHeader(
      kid: kid,
      title: 'My salah 🕌',
      subtitle: 'Hayya ʿalaṣ-ṣalāh, come to prayer!',
    ),
    children: [
      _PrayerCard(store: store),
      if (!store.isWeekend) ...[
        const SizedBox(height: 12),
        _JobsCard(
          kid: kid,
          store: store,
          title: 'Tick each prayer when you pray it',
          where: _isSalah,
        ),
      ],
    ],
  );
}

class _QuranTab extends StatelessWidget {
  const _QuranTab({required this.kid});
  final Kid kid;

  @override
  Widget build(BuildContext context) {
    final surah = surahNumberFrom(kid.surahName);
    return KidTabPage(
      header: KidTabHeader(
        kid: kid,
        title: "My Qur'an 📖",
        subtitle: 'Listen, repeat and recite',
      ),
      children: [
        _QuranCard(kid: kid),
        const SizedBox(height: 12),
        FutureBuilder<Set<String>>(
          future: QuranProgress.load(),
          builder: (context, snap) {
            final passed = snap.data ?? const <String>{};
            final mine = surah == null
                ? 0
                : QuranProgress.countFor(passed, surah);
            return SectionCard(
              title: 'Recited correctly',
              trailing: Text(
                '${passed.length} ayat',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: Text(
                surah == null
                    ? 'Recite to the microphone in "Check me" and every ayah you get right is counted here.'
                    : '$mine ayat of ${kid.surahName} recited correctly with the microphone check. '
                          'Keep going, every letter is a reward!',
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const SectionCard(
          title: 'How to memorise',
          child: Text(
            '1. Listen to Sheikh Al-Husary.\n'
            '2. Recite back to the microphone. Long ayat come in small parts.\n'
            '3. Green words are right, red words need another go.\n'
            '4. Read the meaning so you know what you are learning.\n'
            '5. Hide the text and test yourself.',
            style: TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _SchoolTab extends StatelessWidget {
  const _SchoolTab({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final empty =
        store.schoolItemsFor(kid).isEmpty &&
        store.noticesFor(kid).isEmpty &&
        store.schoolWorkLeftToday(kid).isEmpty;
    return KidTabPage(
      header: KidTabHeader(
        kid: kid,
        title: 'My school 🎒',
        subtitle: 'Homework, tests and news from your teacher',
      ),
      children: [
        if (empty)
          const SectionCard(
            title: 'All clear!',
            child: Text(
              'No homework, tests or announcements right now. Well done! 🌟',
            ),
          ),
        if (kid.examMode) const FocusTimerCard(),
        KidSchoolCard(kid: kid),
        // On the child's own device (not Mom's phone in kids mode).
        if (!store.isParent &&
            classroomEnabled &&
            ClassroomClient.supported &&
            kid.mayConnectClassroom)
          KidClassroomCard(kid: kid),
      ],
    );
  }
}

/// The colourful top of a child's page: greeting, time and today's reminder,
/// on their theme's gradient with its little pictures.
class _Hero extends StatelessWidget {
  const _Hero({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final t = themeOf(kid);
    final r = reminderFor(store.now);
    final canPop = Navigator.of(context).canPop();
    Widget sprinkle(double? left, double? right, double top, double size) =>
        Positioned(
          left: left,
          right: right,
          top: top,
          child: Opacity(
            opacity: 0.22,
            child: Text(t.emoji, style: TextStyle(fontSize: size)),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        gradient: t.gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          sprinkle(null, 18, 54, 56),
          sprinkle(null, 92, 18, 26),
          sprinkle(null, 150, 64, 18),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (canPop)
                            const BackButton(color: Colors.white)
                          else
                            const SizedBox(width: 8),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Parent',
                            color: Colors.white,
                            icon: const Icon(Icons.lock_outline),
                            onPressed: () => openParentArea(context),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: KidAvatar(kid: kid, radius: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Salam, ${kid.name}! ${t.emoji}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${weekdayNames[store.todayWeekday]} · ${formatMinute(store.nowMinute)}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "✨ TODAY'S REMINDER",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '“${r.text}”',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.source,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: starGold.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _StarsCard extends StatelessWidget {
  const _StarsCard({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.score(kid);
    return SectionCard(
      title: 'My stars this week',
      trailing: Text(
        '${s.total} / $maxStars',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarRow(score: s, size: 26),
          if (s.lost > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${s.lost} star${s.lost == 1 ? '' : 's'} lost to time-out this week',
              ),
            ),
          if (s.bonus > 0) Text('+${s.bonus} bonus for fasting. MashaAllah!'),
        ],
      ),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final p = store.prayersToday;
    final next = nextPrayer(p, store.nowMinute);
    final cs = Theme.of(context).colorScheme;
    String countdown() {
      if (next == null) return 'Fajr tomorrow';
      final m = next.value - store.nowMinute;
      return '${next.key.label} in ${m >= 60 ? '${m ~/ 60} h ' : ''}${m % 60} min';
    }

    return SectionCard(
      title: 'Salah times · ${store.family.prayer.city}',
      trailing: Text(
        countdown(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      child: Column(
        children: [
          _prayerRow(p, next, cs),
          if (adhanAsset != null) const _AdhanButton(),
          if (store.family.adhanEnabled) const AdhanCheck(),
        ],
      ),
    );
  }

  Widget _prayerRow(
    DayPrayerTimes p,
    MapEntry<Prayer, int>? next,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        for (final e in p.times.entries)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: e.key == next?.key
                    ? cs.primary
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    e.key.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: e.key == next?.key ? cs.onPrimary : null,
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      formatMinute(e.value),
                      style: TextStyle(
                        fontSize: 12,
                        color: e.key == next?.key ? cs.onPrimary : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _JobsCard extends StatelessWidget {
  const _JobsCard({
    required this.kid,
    required this.store,
    this.title = 'My jobs today',
    this.where,
  });
  final Kid kid;
  final AppStore store;
  final String title;
  final bool Function(RoutineTask t)? where;

  @override
  Widget build(BuildContext context) {
    final day = store.todayWeekday;
    final tasks = store
        .tasksForDay(kid, day)
        .where(where ?? (_) => true)
        .toList();
    return SectionCard(
      title: title,
      trailing: const Text('Mom can see your ticks'),
      child: Column(
        children: [
          if (tasks.isEmpty) const Text('No jobs today.'),
          for (final t in tasks) _JobTile(kid: kid, task: t, store: store),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.kid, required this.task, required this.store});
  final Kid kid;
  final RoutineTask task;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final status = store.status(kid, task, store.todayWeekday);
    final canToggle = store.canKidToggle(kid, task);
    final done = status == TaskStatus.done;
    final w = store.window(task);
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: IconButton.filledTonal(
          tooltip: canToggle
              ? (done ? 'Untick: ${task.title}' : 'Mark done: ${task.title}')
              : 'Locked: ${task.title}',
          style: IconButton.styleFrom(
            backgroundColor: done ? const Color(0xFF23824F) : null,
            disabledBackgroundColor: done
                ? const Color(0xFF23824F).withValues(alpha: 0.75)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: canToggle
              ? () {
                  store.kidToggle(kid, task);
                  if (!done) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Well done! Mom can see it.'),
                        ),
                      );
                  }
                }
              : null,
          icon: Icon(
            done
                ? Icons.check_rounded
                : (canToggle ? iconFor(task.category) : Icons.lock_outline),
            color: done ? Colors.white : (canToggle ? cs.primary : cs.outline),
          ),
        ),
      ),
      title: Text(
        task.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${formatMinute(w.start)} – ${formatMinute(w.end)}'),
      trailing: StatusChip(status),
    );
  }
}

class _QuranCard extends StatelessWidget {
  const _QuranCard({required this.kid});
  final Kid kid;

  @override
  Widget build(BuildContext context) {
    final total = kid.ayahTotal <= 0 ? 1 : kid.ayahTotal;
    return SectionCard(
      title: "My Qur'an this week",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Surah ${kid.surahName} · ${kid.ayahDone} of ${kid.ayahTotal} ayat',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (kid.ayahDone / total).clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                // Keeps the child's theme colours.
                builder: (_) => Theme(
                  data: Theme.of(context),
                  child: QuranScreen(
                    initialSurah: surahNumberFrom(kid.surahName) ?? 1,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.headphones),
            label: const Text('Listen & memorise with Al-Husary'),
          ),
        ],
      ),
    );
  }
}

class _RewardsCard extends StatelessWidget {
  const _RewardsCard({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final total = store.score(kid).total;
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Where do I want to go?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collect stars by Friday to unlock a treat. Mom makes the list.',
          ),
          const SizedBox(height: 8),
          if (kid.rewards.isEmpty)
            const Text('Mom has not added any rewards yet.'),
          for (var i = 0; i < kid.rewards.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: kid.wishIndex == i
                      ? const BorderSide(color: starGold, width: 2)
                      : BorderSide.none,
                ),
                tileColor: total >= kid.rewards[i].stars
                    ? starGold.withValues(alpha: 0.16)
                    : cs.surfaceContainerHighest,
                enabled: total >= kid.rewards[i].stars,
                title: Text(
                  kid.rewards[i].name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(
                  kid.wishIndex == i
                      ? 'My pick!'
                      : total >= kid.rewards[i].stars
                      ? 'Tap to choose'
                      : '${kid.rewards[i].stars - total} more ★',
                ),
                onTap: () => store.pickReward(kid, i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Plays the adhan recording inside the app.
class _AdhanButton extends StatefulWidget {
  const _AdhanButton();

  @override
  State<_AdhanButton> createState() => _AdhanButtonState();
}

class _AdhanButtonState extends State<_AdhanButton> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((s) {
      final playing =
          s.playing && s.processingState != ProcessingState.completed;
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      return;
    }
    await _player.setAsset(adhanAsset!);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: _toggle,
      icon: Icon(
        _playing ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
      ),
      label: Text(_playing ? 'Stop adhan' : 'Play adhan'),
    ),
  );
}

/// Checks that Android lets the adhan ring at the exact minute, and (in
/// Settings) lets a parent hear a test adhan a minute later.
class AdhanCheck extends StatefulWidget {
  const AdhanCheck({super.key, this.showTest = false});
  final bool showTest;

  @override
  State<AdhanCheck> createState() => _AdhanCheckState();
}

class _AdhanCheckState extends State<AdhanCheck> with WidgetsBindingObserver {
  bool _onTime = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await Notifications.canRingOnTime();
    if (!mounted || ok == _onTime) return;
    setState(() => _onTime = ok);
    // Just allowed: schedule the adhan again at the exact minutes.
    if (ok) StoreScope.of(context).rescheduleReminders();
  }

  Future<void> _test() async {
    final ok = await Notifications.testAdhan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          ok
              ? 'The adhan will play in 1 minute. Lock the phone and wait. '
                    "If it doesn't play, check that notifications for Super Mom are on "
                    'and the alarm volume is up.'
              : 'Reminders work in the Android app, not here.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_onTime)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.alarm, color: cs.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Allow "Alarms & reminders" so the adhan plays exactly on time.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Notifications.allowRingingOnTime();
                    _check();
                  },
                  child: const Text('Allow'),
                ),
              ],
            ),
          ),
        if (widget.showTest)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Test the adhan (plays in 1 minute)'),
            ),
          ),
        if (widget.showTest)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The adhan plays at alarm volume. On some phones (Samsung, Xiaomi, '
              'Oppo) also set Battery for Super Mom to "Unrestricted" so it is never stopped.',
            ),
          ),
      ],
    );
  }
}
