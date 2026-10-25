import 'package:flutter/material.dart';

import '../content.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'editors.dart';
import 'kid_screen.dart';

/// Parent area, opened with the PIN.
class MomScreen extends StatefulWidget {
  const MomScreen({super.key});

  @override
  State<MomScreen> createState() => _MomScreenState();
}

class _MomScreenState extends State<MomScreen> {
  int _tab = 0;
  String? _kidId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kids = store.family.kids;
    final kid =
        kids.where((k) => k.id == _kidId).firstOrNull ?? kids.firstOrNull;

    final pages = [
      kid == null
          ? const _NoKids()
          : _TodayTab(kid: kid, onKid: (k) => setState(() => _kidId = k.id)),
      kid == null
          ? const _NoKids()
          : _WeekTab(kid: kid, onKid: (k) => setState(() => _kidId = k.id)),
      const FamilyTab(),
      const RoutineTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          TextButton.icon(
            onPressed: () => store.setKidsMode(true),
            icon: const Icon(Icons.child_care),
            label: const Text('Kids mode'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: pages[_tab],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            label: 'Week',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom),
            label: 'Kids',
          ),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Routine'),
        ],
      ),
    );
  }
}

class _NoKids extends StatelessWidget {
  const _NoKids();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Add a child in the Kids tab.'));
}

class _KidSelector extends StatelessWidget {
  const _KidSelector({required this.selected, required this.onKid});
  final Kid selected;
  final ValueChanged<Kid> onKid;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final k in store.family.kids)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: KidAvatar(kid: k, radius: 12),
                label: Text('${k.name} · ${store.score(k).total}★'),
                selected: k.id == selected.id,
                onSelected: (_) => onKid(k),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayTab extends StatefulWidget {
  const _TodayTab({required this.kid, required this.onKid});
  final Kid kid;
  final ValueChanged<Kid> onKid;

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  int? _day;

  Future<void> _giveTimeOut(AppStore store) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Time-out for ${widget.kid.name} (−1 star)'),
        children: [
          for (final r in timeOutReasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(r),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    store.addTimeOut(widget.kid, reason);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Time-out given to ${widget.kid.name}: −1 star')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kid = widget.kid;
    final day = _day ?? store.todayWeekday.clamp(1, 5);
    final tasks = store.tasksForDay(kid, day);
    final score = store.score(kid);
    final kidTicks = tasks
        .where((t) => kid.checks[Kid.key(day, t.id)] == DoneBy.kid)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KidSelector(selected: kid, onKid: widget.onKid),
        const SizedBox(height: 12),
        SectionCard(
          title: '${kid.name} this week',
          trailing: Text(
            '${score.total} / $maxStars',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarRow(score: score),
              const SizedBox(height: 4),
              Text(
                '${score.earned} earned · ${score.bonus} bonus · ${score.lost} lost to time-out',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _giveTimeOut(store),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Give time-out (−1★)'),
                  ),
                  if (kid.examMode) const Chip(label: Text('Exam week mode')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var d = 1; d <= 5; d++)
              ButtonSegment(value: d, label: Text(weekdayNames[d])),
          ],
          selected: {day},
          onSelectionChanged: (s) => setState(() => _day = s.first),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '${weekdayNames[day]} checklist',
          trailing: Text('$kidTicks ticked by ${kid.name}'),
          child: Column(
            children: [
              if (tasks.isEmpty) const Text('No tasks on this day.'),
              for (final t in tasks) _MomTaskTile(kid: kid, task: t, day: day),
            ],
          ),
        ),
      ],
    );
  }
}

class _MomTaskTile extends StatelessWidget {
  const _MomTaskTile({
    required this.kid,
    required this.task,
    required this.day,
  });
  final Kid kid;
  final RoutineTask task;
  final int day;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final status = store.status(kid, task, day);
    final by = kid.checks[Kid.key(day, task.id)];
    final w = store.window(task);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: by != null,
      onChanged: (v) => store.momSetDone(kid, task, day, v ?? false),
      title: Text(task.title),
      subtitle: Text(
        [
          '${formatMinute(w.start)} – ${formatMinute(w.end)}',
          if (by == DoneBy.kid) 'ticked by ${kid.name}',
          if (by == DoneBy.mom) 'marked by you',
          if (task.bonus) 'bonus',
        ].join(' · '),
      ),
      secondary: StatusChip(status),
    );
  }
}

class _WeekTab extends StatelessWidget {
  const _WeekTab({required this.kid, required this.onKid});
  final Kid kid;
  final ValueChanged<Kid> onKid;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = store.todayWeekday;
    final wish = kid.wishIndex != null && kid.wishIndex! < kid.rewards.length
        ? kid.rewards[kid.wishIndex!]
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KidSelector(selected: kid, onKid: onKid),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Stars by day',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1),
                },
                children: [
                  const TableRow(
                    children: [
                      Text(
                        'Day',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Tasks done',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Stars',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  for (var d = 1; d <= 5; d++)
                    () {
                      final list = store
                          .tasksForDay(kid, d)
                          .where((t) => !t.bonus)
                          .toList();
                      final done = list
                          .where(
                            (t) => kid.checks.containsKey(Kid.key(d, t.id)),
                          )
                          .length;
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(weekdayNames[d]),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              d > today ? '–' : '$done / ${list.length}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              d > today ? '–' : '★' * store.starsForDay(kid, d),
                            ),
                          ),
                        ],
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '90% of tasks done = 2 stars, 60% = 1 star. Each time-out takes away 1 star.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Time-outs',
          child: Column(
            children: [
              if (kid.timeouts.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('None this week. MashaAllah!'),
                ),
              for (var i = 0; i < kid.timeouts.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text(
                    '−1★',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  title: Text(kid.timeouts[i].reason),
                  subtitle: Text(
                    '${weekdayNames[kid.timeouts[i].weekday]} ${formatMinute(kid.timeouts[i].minute)}',
                  ),
                  trailing: TextButton(
                    onPressed: () => store.removeTimeOut(kid, i),
                    child: const Text('Remove'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Reward',
          child: Text(
            wish == null
                ? '${kid.name} has not picked a reward yet.'
                : '${kid.name} picked: ${wish.name} (${wish.stars}★)',
          ),
        ),
        if (store.family.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Past weeks',
            child: Column(
              children: [
                for (final h in store.family.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Week of ${formatWeekId(h.weekId)}'),
                    subtitle: Text(
                      h.starsByKid.entries
                          .map((e) => '${e.key}: ${e.value}★')
                          .join('   '),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
