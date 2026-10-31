import 'dart:async';

import 'package:flutter/material.dart';

import '../classroom.dart';
import '../content.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'mom_screen.dart';

const _shortDays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _shortMonths = [
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

/// "20261028" -> "Wed 28 Oct".
String formatYmd(String ymd) {
  final d = dateFromYmd(ymd);
  return '${_shortDays[d.weekday]} ${d.day} ${_shortMonths[d.month - 1]}';
}

String whenText(String ymd, DateTime now) {
  final n = daysUntil(ymd, now);
  if (n == 0) return 'today';
  if (n == 1) return 'tomorrow';
  return n < 0 ? '${-n} days ago' : 'in $n days';
}

IconData schoolIcon(SchoolKind k) => switch (k) {
  SchoolKind.homework => Icons.edit_note,
  SchoolKind.test => Icons.quiz_outlined,
  SchoolKind.event => Icons.emoji_events_outlined,
  SchoolKind.notice => Icons.campaign_outlined,
};

/// A teacher's announcement, in full.
Future<void> showNotice(
  BuildContext context,
  SchoolItem n, {
  VoidCallback? onDelete,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    icon: const Icon(Icons.campaign_outlined),
    title: Text(n.subject.isEmpty ? 'From your teacher' : n.subject),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatYmd(n.dueYmd), style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          SelectableText(n.details.isEmpty ? n.title : n.details),
        ],
      ),
    ),
    actions: [
      if (onDelete != null)
        TextButton(
          onPressed: () {
            onDelete();
            Navigator.pop(ctx);
          },
          child: const Text('Remove'),
        ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('OK'),
      ),
    ],
  ),
);

// ---------------- parent: School tab ----------------

class SchoolTab extends StatefulWidget {
  const SchoolTab({super.key, required this.kid, required this.onKid});
  final Kid kid;
  final ValueChanged<Kid> onKid;

  @override
  State<SchoolTab> createState() => _SchoolTabState();
}

class _SchoolTabState extends State<SchoolTab> {
  bool _syncing = false;

  Future<void> _sync(AppStore store) async {
    setState(() => _syncing = true);
    final msg = await store.syncClassroom(widget.kid);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _edit(SchoolKind kind, [SchoolItem? item]) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SchoolItemEditor(kid: widget.kid, kind: kind, item: item),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kid = widget.kid;
    final items = store.schoolItemsFor(kid);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        KidSelector(selected: kid, onKid: widget.onKid),
        if (classroomEnabled) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Google Classroom',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kid.classroomEmail == null
                      ? "Import ${kid.name}'s homework, tests and teacher announcements. "
                            "Sign in with the school Google account ${kid.name} uses in Classroom; Super Mom only reads."
                      : 'Connected: ${kid.classroomEmail}\n'
                            '${kid.classroomClasses.isEmpty ? 'No classes found for this account.' : 'Classes: ${kid.classroomClasses.join(', ')}'}\n'
                            'Checks by itself once a day, or tap Sync now.',
                ),
                const SizedBox(height: 8),
                if (ClassroomClient.supported)
                  FilledButton.tonalIcon(
                    onPressed: _syncing ? null : () => _sync(store),
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      kid.classroomEmail == null
                          ? 'Connect school account'
                          : 'Sync now',
                    ),
                  )
                else
                  const Text(
                    'Classroom import works in the Android and iPhone app.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _edit(SchoolKind.homework),
              icon: const Icon(Icons.edit_note),
              label: const Text('Add homework'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _edit(SchoolKind.test),
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Add test'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _edit(SchoolKind.event),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Add competition'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Coming up',
          child: Column(
            children: [
              if (items.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nothing coming up.'),
                ),
              for (final i in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(schoolIcon(i.kind)),
                  title: Text(
                    i.kind == SchoolKind.homework || i.kind == SchoolKind.test
                        ? '${i.subject.isEmpty ? '' : '${i.subject}: '}${i.title}'
                        : i.title,
                  ),
                  subtitle: Text(
                    [
                      '${i.kind == SchoolKind.event ? 'On' : 'Due'} ${formatYmd(i.dueYmd)} (${whenText(i.dueYmd, store.now)})',
                      if (i.kind != SchoolKind.event && i.hasTask)
                        'task on ${formatYmd(i.fromYmd!)}',
                      if (i.kind == SchoolKind.event && i.practiceTarget > 0)
                        'practice ${i.practiceDone + practiceTicksThisWeek(kid, i)} of ${i.practiceTarget}',
                      if (i.handedIn) 'handed in ✓',
                      if (i.source == 'classroom' && !i.handedIn)
                        'from Classroom',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(i.kind, i),
                ),
            ],
          ),
        ),
        if (store.noticesFor(kid).isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Teacher announcements',
            child: Column(
              children: [
                for (final n in store.noticesFor(kid))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(
                      n.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${n.subject} · ${formatYmd(n.dueYmd)}'),
                    onTap: () => showNotice(
                      context,
                      n,
                      onDelete: () => store.deleteSchoolItem(n),
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

class SchoolItemEditor extends StatefulWidget {
  const SchoolItemEditor({
    super.key,
    required this.kid,
    required this.kind,
    this.item,
  });
  final Kid kid;
  final SchoolKind kind;
  final SchoolItem? item;

  @override
  State<SchoolItemEditor> createState() => _SchoolItemEditorState();
}

class _SchoolItemEditorState extends State<SchoolItemEditor> {
  late SchoolKind _kind = widget.item?.kind ?? widget.kind;
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _subject = TextEditingController(text: widget.item?.subject ?? '');
  late DateTime _due;
  late DateTime _workDay;
  late bool _practice;
  late int _target;
  late int _start;
  late int _end;
  String? _error;
  bool _confirmDelete = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    final now = StoreScope.of(context).now;
    final item = widget.item;
    _due = item == null
        ? now.add(const Duration(days: 2))
        : dateFromYmd(item.dueYmd);
    _workDay = item?.fromYmd != null
        ? dateFromYmd(item!.fromYmd!)
        : defaultWorkDay(_due, now);
    _practice = item == null ? true : item.hasTask;
    _target = item?.practiceTarget ?? 10;
    _start =
        item?.startMin ?? (_kind == SchoolKind.event ? 17 * 60 : 15 * 60 + 30);
    _end = item?.endMin ?? (_kind == SchoolKind.event ? 19 * 60 : 18 * 60 + 30);
  }

  bool _initDone = false;

  Future<DateTime?> _pickDate(DateTime initial) {
    final now = StoreScope.of(context).now;
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
  }

  Future<void> _pickTime(bool start) async {
    final m = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t != null) {
      setState(
        () => start
            ? _start = t.hour * 60 + t.minute
            : _end = t.hour * 60 + t.minute,
      );
    }
  }

  void _save() {
    final store = StoreScope.of(context);
    if (_title.text.trim().isEmpty) {
      return setState(() => _error = 'Give it a name.');
    }
    if (_end <= _start) {
      return setState(
        () => _error = 'Closing time must be after opening time.',
      );
    }
    final event = _kind == SchoolKind.event;
    if (!event && _workDay.isAfter(_due)) {
      return setState(
        () => _error = 'The task day must be on or before the due date.',
      );
    }
    final today = ymdKey(store.now);
    final dayBefore = ymdKey(_due.subtract(const Duration(days: 1)));
    store.upsertSchoolItem(
      SchoolItem(
        id: widget.item?.id ?? store.newSchoolItemId(),
        kidId: widget.kid.id,
        kind: _kind,
        title: _title.text.trim(),
        subject: event ? '' : _subject.text.trim(),
        dueYmd: ymdKey(_due),
        fromYmd: event ? (_practice ? today : null) : ymdKey(_workDay),
        toYmd: event
            ? (_practice
                  ? (dayBefore.compareTo(today) < 0 ? today : dayBefore)
                  : null)
            : ymdKey(_workDay),
        startMin: _start,
        endMin: _end,
        source: widget.item?.source ?? 'manual',
        link: widget.item?.link,
        practiceTarget: event && _practice ? _target : 0,
        practiceDone: widget.item?.practiceDone ?? 0,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final event = _kind == SchoolKind.event;
    final names = {
      SchoolKind.homework: 'homework',
      SchoolKind.test: 'test',
      SchoolKind.event: 'competition',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.item == null ? 'New' : 'Edit'} ${names[_kind]} · ${widget.kid.name}',
        ),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<SchoolKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: SchoolKind.homework,
                label: Text('Homework'),
              ),
              ButtonSegment(value: SchoolKind.test, label: Text('Test')),
              ButtonSegment(
                value: SchoolKind.event,
                label: Text('Competition'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: event
                  ? 'Competition'
                  : (_kind == SchoolKind.test ? 'Test' : 'Homework'),
              hintText: event
                  ? "e.g. School Qur'an recitation"
                  : (_kind == SchoolKind.test
                        ? 'e.g. Chapter 4 quiz'
                        : 'e.g. Worksheet p.42'),
              errorText: _error,
            ),
          ),
          if (!event)
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Subject',
                hintText: 'e.g. Maths',
              ),
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(event ? 'Competition day' : 'Due'),
            subtitle: Text(formatYmd(ymdKey(_due))),
            onTap: () async {
              final d = await _pickDate(_due);
              if (d == null) return;
              setState(() {
                _due = d;
                if (widget.item?.fromYmd == null) {
                  _workDay = defaultWorkDay(d, store.now);
                }
              });
            },
          ),
          if (!event)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.checklist),
              title: Text(
                _kind == SchoolKind.test
                    ? 'Revision task on'
                    : 'Homework task on',
              ),
              subtitle: Text(
                '${formatYmd(ymdKey(_workDay))} (usually the school day before)',
              ),
              onTap: () async {
                final d = await _pickDate(_workDay);
                if (d != null) setState(() => _workDay = d);
              },
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily practice task until then'),
              subtitle: const Text(
                'A task every school day; each tick counts as one practice session',
              ),
              value: _practice,
              onChanged: (v) => setState(() => _practice = v),
            ),
            if (_practice)
              Row(
                children: [
                  const Text('Practice goal'),
                  Expanded(
                    child: Slider(
                      value: _target.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$_target',
                      onChanged: (v) => setState(() => _target = v.round()),
                    ),
                  ),
                  Text('$_target sessions'),
                ],
              ),
          ],
          if (!event || _practice) ...[
            const SizedBox(height: 8),
            const Text('Time window for the task'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text('Opens ${formatMinute(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text('Closes ${formatMinute(_end)}'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            event
                ? '${widget.kid.name} gets a reminder the evening before and on the morning of the competition.'
                : _kind == SchoolKind.test
                ? '${widget.kid.name} gets a reminder the evening before the test.'
                : 'The homework appears in ${widget.kid.name}\'s jobs on the task day and counts towards stars.',
          ),
          if (widget.item?.source == 'classroom')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Imported from Google Classroom.'),
            ),
          if (widget.item != null) ...[
            const SizedBox(height: 20),
            _confirmDelete
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () {
                      store.deleteSchoolItem(widget.item!);
                      Navigator.pop(context);
                    },
                    child: const Text('Tap again to delete'),
                  )
                : OutlinedButton(
                    onPressed: () => setState(() => _confirmDelete = true),
                    child: const Text('Delete'),
                  ),
          ],
        ],
      ),
    );
  }
}

// ---------------- child: School card and focus timer ----------------

class KidSchoolCard extends StatelessWidget {
  const KidSchoolCard({super.key, required this.kid});
  final Kid kid;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final items = store
        .schoolItemsFor(kid)
        .where(
          (i) =>
              i.kind != SchoolKind.homework &&
              daysUntil(i.dueYmd, store.now) <= 14,
        );
    final left = store.schoolWorkLeftToday(kid);
    final notices = store.noticesFor(kid);
    if (items.isEmpty && left.isEmpty && notices.isEmpty) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'School',
        child: Column(
          children: [
            if (left.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: starGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '💪 Come on, ${kid.name}! ${left.length == 1 ? 'Your ${left.first.subject.isEmpty ? left.first.title : left.first.subject} homework is' : '${left.length} pieces of school work are'} '
                  'waiting today. ${encouragementFor('${left.first.id}${store.todayWeekday}')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(schoolIcon(i.kind), color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.kind == SchoolKind.test
                                ? '${i.subject.isEmpty ? '' : '${i.subject} '}test: ${i.title}'
                                : i.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${formatYmd(i.dueYmd)} · ${whenText(i.dueYmd, store.now)}',
                          ),
                          if (i.kind == SchoolKind.event &&
                              i.practiceTarget > 0) ...[
                            const SizedBox(height: 6),
                            () {
                              final done =
                                  i.practiceDone +
                                  practiceTicksThisWeek(kid, i);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(
                                    value: (done / i.practiceTarget).clamp(
                                      0,
                                      1,
                                    ),
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$done of ${i.practiceTarget} practice sessions',
                                  ),
                                ],
                              );
                            }(),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (notices.isNotEmpty) ...[
              const Divider(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '📣 From your teacher',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final n in notices.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${n.subject} · ${formatYmd(n.dueYmd)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showNotice(context, n),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Exam week: a simple 25-minute study timer with a 5-minute break.
class FocusTimerCard extends StatefulWidget {
  const FocusTimerCard({super.key});

  @override
  State<FocusTimerCard> createState() => _FocusTimerCardState();
}

class _FocusTimerCardState extends State<FocusTimerCard> {
  static const _study = Duration(minutes: 25);
  static const _break = Duration(minutes: 5);
  Duration _left = _study;
  bool _onBreak = false;
  int _sessions = 0;
  Timer? _timer;

  void _toggle() {
    if (_timer != null) {
      _timer!.cancel();
      setState(() => _timer = null);
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _left -= const Duration(seconds: 1);
        if (_left > Duration.zero) return;
        if (!_onBreak) _sessions++;
        _onBreak = !_onBreak;
        _left = _onBreak ? _break : _study;
      });
    });
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _onBreak = false;
      _left = _study;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = _left.inMinutes.toString().padLeft(2, '0');
    final ss = (_left.inSeconds % 60).toString().padLeft(2, '0');
    final running = _timer != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: _onBreak
            ? 'Break time · stretch and drink water'
            : 'Study focus',
        trailing: Text('$_sessions done'),
        child: Row(
          children: [
            Text(
              '$mm:$ss',
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton.filled(
              tooltip: running ? 'Pause' : 'Start',
              onPressed: _toggle,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Reset',
              onPressed: _reset,
              icon: const Icon(Icons.replay),
            ),
          ],
        ),
      ),
    );
  }
}
