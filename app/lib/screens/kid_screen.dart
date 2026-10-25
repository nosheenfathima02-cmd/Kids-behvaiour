import 'package:flutter/material.dart';

import '../content.dart';
import '../logic.dart';
import '../main.dart';
import '../models.dart';
import '../prayer.dart';
import '../store.dart';
import '../widgets.dart';
import 'mom_screen.dart';
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
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => KidHome(kid: k)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                KidAvatar(kid: k, radius: 44),
                                const SizedBox(height: 8),
                                Text(
                                  k.name,
                                  style: Theme.of(context).textTheme.titleLarge,
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
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: themeOf(kid).color,
    child: Text(
      kid.name.isEmpty ? '?' : kid.name[0].toUpperCase(),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.9,
      ),
    ),
  );
}

class KidHome extends StatelessWidget {
  const KidHome({super.key, required this.kid});
  final Kid kid;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final color = themeOf(kid).color;
    final brightness = Theme.of(context).brightness;
    return Theme(
      data: buildTheme(color, brightness),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Text("${kid.name}'s day"),
              actions: [
                IconButton(
                  tooltip: 'Parent',
                  icon: const Icon(Icons.lock_outline),
                  onPressed: () => openParentArea(context),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _Greeting(kid: kid, store: store),
                    const SizedBox(height: 12),
                    _ReminderCard(color: color, store: store),
                    if (kid.examMode) ...[
                      const SizedBox(height: 12),
                      const _Banner(
                        "Exam week! Only salah, Qur'an and study today. You can do it, in sha Allah.",
                      ),
                    ],
                    if (store.isWeekend) ...[
                      const SizedBox(height: 12),
                      _Banner(
                        'It\'s the weekend! You earned ${store.score(kid).total} stars this week. '
                        'A new week starts on Monday.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    _StarsCard(kid: kid, store: store),
                    const SizedBox(height: 12),
                    _PrayerCard(store: store),
                    if (!store.isWeekend) ...[
                      const SizedBox(height: 12),
                      _JobsCard(kid: kid, store: store),
                      if (kid.examMode) const FocusTimerCard(),
                    ],
                    KidSchoolCard(kid: kid),
                    const SizedBox(height: 12),
                    _QuranCard(kid: kid),
                    const SizedBox(height: 12),
                    _RewardsCard(kid: kid, store: store),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        KidAvatar(kid: kid, radius: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salam, ${kid.name}!',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${weekdayNames[store.todayWeekday]} · ${formatMinute(store.nowMinute)}',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.color, required this.store});
  final Color color;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final r = reminderFor(store.now);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S REMINDER",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '“${r.text}”',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(r.source, style: const TextStyle(color: Colors.white)),
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
      child: Row(
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
      ),
    );
  }
}

class _JobsCard extends StatelessWidget {
  const _JobsCard({required this.kid, required this.store});
  final Kid kid;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final day = store.todayWeekday;
    final tasks = store.tasksForDay(kid, day);
    return SectionCard(
      title: 'My jobs today',
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
