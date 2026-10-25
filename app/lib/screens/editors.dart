import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content.dart';
import '../logic.dart';
import '../models.dart';
import '../prayer.dart';
import '../widgets.dart';
import 'kid_screen.dart';
import 'devices_screen.dart';
import 'setup_screen.dart';

// ---------------- Kids ----------------

class FamilyTab extends StatelessWidget {
  const FamilyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final k in store.family.kids)
          Card(
            child: ListTile(
              leading: KidAvatar(kid: k),
              title: Text(
                k.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Age ${k.age} · ${themeOf(k).name} theme${k.examMode ? ' · exam week' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => KidEditorScreen(kid: k)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final kid = store.addKid(
              'New child',
              8,
              kidThemes.keys.elementAt(
                store.family.kids.length % kidThemes.length,
              ),
            );
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => KidEditorScreen(kid: kid)),
            );
          },
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add a child'),
        ),
      ],
    );
  }
}

class KidEditorScreen extends StatefulWidget {
  const KidEditorScreen({super.key, required this.kid});
  final Kid kid;

  @override
  State<KidEditorScreen> createState() => _KidEditorScreenState();
}

class _KidEditorScreenState extends State<KidEditorScreen> {
  late final _name = TextEditingController(text: widget.kid.name);
  late final _surah = TextEditingController(text: widget.kid.surahName);
  bool _confirmDelete = false;

  Future<void> _editReward([int? index]) async {
    final kid = widget.kid;
    final existing = index == null ? null : kid.rewards[index];
    final name = TextEditingController(text: existing?.name ?? '');
    var stars = existing?.stars ?? 10;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add a reward' : 'Edit reward'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Place or treat',
                  hintText: 'e.g. Zoo trip',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Stars needed'),
                  Expanded(
                    child: Slider(
                      value: stars.toDouble(),
                      min: 1,
                      max: maxStars.toDouble(),
                      divisions: maxStars - 1,
                      label: '$stars',
                      onChanged: (v) => setLocal(() => stars = v.round()),
                    ),
                  ),
                  Text('$stars★'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    setState(() {
      if (existing == null) {
        kid.rewards.add(Reward(name.text.trim(), stars));
      } else {
        existing
          ..name = name.text.trim()
          ..stars = stars;
      }
      kid.rewards.sort((a, b) => b.stars.compareTo(a.stars));
      kid.wishIndex = null;
    });
    if (mounted) StoreScope.of(context).saveKidRewards(widget.kid);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kid = widget.kid;
    void update(VoidCallback f) {
      setState(f);
      store.saveKid(kid);
    }

    return Scaffold(
      appBar: AppBar(title: Text(kid.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'First name'),
            textCapitalization: TextCapitalization.words,
            onChanged: (v) =>
                update(() => kid.name = v.trim().isEmpty ? kid.name : v.trim()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Age'),
              Expanded(
                child: Slider(
                  value: kid.age.toDouble().clamp(4, 15),
                  min: 4,
                  max: 15,
                  divisions: 11,
                  label: '${kid.age}',
                  onChanged: (v) => update(() => kid.age = v.round()),
                ),
              ),
              Text('${kid.age}'),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Theme on their device'),
          const SizedBox(height: 8),
          ThemePicker(
            value: kid.theme,
            onChanged: (t) => update(() => kid.theme = t),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exam / study week'),
            subtitle: const Text(
              "Hides chores and screen goals. Only salah, Qur'an, study and sleep count.",
            ),
            value: kid.examMode,
            onChanged: (v) => update(() => kid.examMode = v),
          ),
          const Divider(height: 32),
          Text(
            "Qur'an memorisation this week",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextField(
            controller: _surah,
            decoration: const InputDecoration(
              labelText: 'Surah',
              hintText: 'e.g. Al-Asr (103)',
            ),
            onChanged: (v) => update(() => kid.surahName = v.trim()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Memorised ${kid.ayahDone} of ${kid.ayahTotal} ayat',
                ),
              ),
              IconButton(
                tooltip: 'One less memorised',
                onPressed: kid.ayahDone > 0
                    ? () => update(() => kid.ayahDone--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                tooltip: 'One more memorised',
                onPressed: kid.ayahDone < kid.ayahTotal
                    ? () => update(() => kid.ayahDone++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text('Goal (ayat this week)')),
              IconButton(
                tooltip: 'Smaller goal',
                onPressed: kid.ayahTotal > 1
                    ? () => update(() {
                        kid.ayahTotal--;
                        if (kid.ayahDone > kid.ayahTotal) {
                          kid.ayahDone = kid.ayahTotal;
                        }
                      })
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text('${kid.ayahTotal}'),
              IconButton(
                tooltip: 'Bigger goal',
                onPressed: () => update(() => kid.ayahTotal++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rewards ${kid.name} can choose',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _editReward(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          for (var i = 0; i < kid.rewards.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                '${kid.rewards[i].stars}★',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: starGold,
                ),
              ),
              title: Text(kid.rewards[i].name),
              onTap: () => _editReward(i),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() {
                    kid.rewards.removeAt(i);
                    kid.wishIndex = null;
                  });
                  store.saveKidRewards(kid);
                },
              ),
            ),
          const Divider(height: 32),
          if (!_confirmDelete)
            OutlinedButton.icon(
              onPressed: () => setState(() => _confirmDelete = true),
              icon: const Icon(Icons.delete_outline),
              label: Text('Remove ${kid.name}'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                store.removeKid(kid);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_forever),
              label: Text(
                'Tap again to remove ${kid.name} and this week\'s ticks',
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- Routine ----------------

class RoutineTab extends StatelessWidget {
  const RoutineTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tasks = [...store.family.routine]
      ..sort((a, b) => store.window(a).start.compareTo(store.window(b).start));
    String who(RoutineTask t) => t.kidIds == null
        ? 'all kids'
        : t.kidIds!
              .map((id) => store.kidById(id)?.name ?? '')
              .where((n) => n.isNotEmpty)
              .join(', ');
    String days(RoutineTask t) => t.weekdays.length == 5
        ? 'Mon–Fri'
        : (t.weekdays.toList()..sort()).map((d) => weekdayNames[d]).join(', ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Kids can tick a task only between its opening and closing time. Salah tasks follow the prayer times.',
        ),
        const SizedBox(height: 8),
        for (final t in tasks)
          Card(
            child: ListTile(
              leading: Icon(iconFor(t.category)),
              title: Text(t.title),
              subtitle: Text(
                '${formatMinute(store.window(t).start)} – ${formatMinute(store.window(t).end)} · ${days(t)} · ${who(t)}${t.bonus ? ' · bonus' : ''}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TaskEditorScreen(task: t)),
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaskEditorScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add a task'),
        ),
      ],
    );
  }
}

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task});
  final RoutineTask? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late TaskCategory _category = widget.task?.category ?? TaskCategory.chores;
  late Prayer? _prayer = widget.task?.prayer;
  late int _start = widget.task?.startMin ?? 16 * 60;
  late int _end = widget.task?.endMin ?? 18 * 60;
  late final Set<int> _days = {
    ...(widget.task?.weekdays ?? const [1, 2, 3, 4, 5]),
  };
  late Set<String>? _kids = widget.task?.kidIds?.toSet();
  late bool _bonus = widget.task?.bonus ?? false;
  String? _error;
  bool _confirmDelete = false;

  Future<void> _pickTime(bool start) async {
    final m = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    setState(
      () => start
          ? _start = t.hour * 60 + t.minute
          : _end = t.hour * 60 + t.minute,
    );
  }

  void _save() {
    final store = StoreScope.of(context);
    if (_title.text.trim().isEmpty) {
      return setState(() => _error = 'Give the task a name.');
    }
    if (_days.isEmpty) return setState(() => _error = 'Pick at least one day.');
    if (_prayer == null && _end <= _start) {
      return setState(
        () => _error = 'Closing time must be after opening time.',
      );
    }
    if (_kids != null && _kids!.isEmpty) {
      return setState(
        () => _error = 'Pick at least one child, or choose all kids.',
      );
    }
    store.upsertTask(
      RoutineTask(
        id: widget.task?.id ?? store.newTaskId(),
        title: _title.text.trim(),
        category: _prayer != null ? TaskCategory.salah : _category,
        startMin: _start,
        endMin: _end,
        prayer: _prayer,
        weekdays: _days.toList()..sort(),
        kidIds: _kids?.toList(),
        bonus: _bonus,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'New task' : 'Edit task'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: 'Task',
              hintText: 'e.g. Read 10 pages',
              errorText: _error,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TaskCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final c in TaskCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (c) => setState(() {
              _category = c!;
              if (c != TaskCategory.salah) _prayer = null;
            }),
          ),
          const SizedBox(height: 16),
          if (_category == TaskCategory.salah)
            DropdownButtonFormField<Prayer?>(
              initialValue: _prayer,
              decoration: const InputDecoration(labelText: 'Time window'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Set my own times'),
                ),
                for (final p in Prayer.values)
                  DropdownMenuItem(
                    value: p,
                    child: Text('Follow ${p.label} time'),
                  ),
              ],
              onChanged: (p) => setState(() => _prayer = p),
            ),
          if (_prayer == null)
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
          const SizedBox(height: 16),
          const Text('Days'),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 5; d++)
                FilterChip(
                  label: Text(weekdayNames[d]),
                  selected: _days.contains(d),
                  onSelected: (v) =>
                      setState(() => v ? _days.add(d) : _days.remove(d)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('For'),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: const Text('All kids'),
                selected: _kids == null,
                onSelected: (v) => setState(() => _kids = v ? null : {}),
              ),
              if (_kids != null)
                for (final k in store.family.kids)
                  FilterChip(
                    label: Text(k.name),
                    selected: _kids!.contains(k.id),
                    onSelected: (v) => setState(
                      () => v ? _kids!.add(k.id) : _kids!.remove(k.id),
                    ),
                  ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bonus task'),
            subtitle: const Text(
              'Optional. Doing it adds a bonus star; skipping it costs nothing.',
            ),
            value: _bonus,
            onChanged: (v) => setState(() => _bonus = v),
          ),
          if (widget.task != null) ...[
            const SizedBox(height: 16),
            _confirmDelete
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () {
                      store.deleteTask(widget.task!);
                      Navigator.pop(context);
                    },
                    child: const Text('Tap again to delete this task'),
                  )
                : OutlinedButton(
                    onPressed: () => setState(() => _confirmDelete = true),
                    child: const Text('Delete task'),
                  ),
          ],
        ],
      ),
    );
  }
}

// ---------------- Settings ----------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmReset = false;
  bool _confirmDelete = false;

  Future<void> _changePin() async {
    final store = StoreScope.of(context);
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New parent PIN'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '4 to 6 digits'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (pin == null || !mounted) return;
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN not changed: use at least 4 digits.'),
        ),
      );
      return;
    }
    store.changePin(pin);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN changed')));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = store.family.prayer;
    final cityMatch = cities.where((c) => c.name == p.city).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Prayer times', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<City>(
            initialValue: cityMatch,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'City'),
            items: [
              for (final c in cities)
                DropdownMenuItem(value: c, child: Text(c.name)),
            ],
            onChanged: (c) {
              p
                ..city = c!.name
                ..latitude = c.lat
                ..longitude = c.lng
                ..method = c.method;
              store.saveSettings();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(p.method),
            initialValue: calculationMethods.containsKey(p.method)
                ? p.method
                : 'muslim_world_league',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Calculation method'),
            items: [
              for (final e in calculationMethods.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (m) {
              p.method = m!;
              store.saveSettings();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hanafi Asr time'),
            subtitle: const Text('Later Asr, used in South Asia and Turkey'),
            value: p.hanafiAsr,
            onChanged: (v) {
              p.hanafiAsr = v;
              store.saveSettings();
            },
          ),
          Text(
            "Today: ${store.prayersToday.times.entries.map((e) => '${e.key.label} ${formatMinute(e.value)}').join(' · ')}",
          ),
          const Text(
            'Times use this phone\'s clock and time zone, so set the phone to your local time zone.',
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prayer time reminders'),
            subtitle: const Text(
              "A notification at each adhan time on the kids' devices and this phone",
            ),
            value: store.family.adhanEnabled,
            onChanged: (v) {
              store.family.adhanEnabled = v;
              store.saveSettings();
            },
          ),
          const Divider(height: 32),
          Text(
            "Children's devices",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_other),
            title: Text('${store.devices.length} linked'),
            subtitle: const Text('Link a new phone or tablet, or remove one'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevicesScreen()),
            ),
          ),
          const Divider(height: 32),
          Text('Security', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Change parent PIN'),
            onTap: _changePin,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: Text(store.auth.currentUser?.email ?? ''),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              store.signOut();
            },
          ),
          const Divider(height: 32),
          Text('Week', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'The week resets by itself every Monday at midnight. Stars stay visible over the weekend so kids can pick their reward.',
          ),
          const SizedBox(height: 8),
          _confirmReset
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () {
                    store.startNewWeek();
                    setState(() => _confirmReset = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('New week started')),
                    );
                  },
                  child: const Text(
                    'Tap again to clear all ticks and time-outs',
                  ),
                )
              : OutlinedButton(
                  onPressed: () => setState(() => _confirmReset = true),
                  child: const Text('Start a new week now'),
                ),
          const Divider(height: 32),
          Text(
            'Delete account',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Deletes your sign-in and everything about your family: children, ticks, stars, '
            'homework and linked devices. This cannot be undone.',
          ),
          const SizedBox(height: 8),
          _confirmDelete
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    final msg = await store.deleteAccountAndData();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          msg ?? 'Your account and family data are deleted.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Tap again to delete everything'),
                )
              : OutlinedButton(
                  onPressed: () => setState(() => _confirmDelete = true),
                  child: const Text('Delete account and family data'),
                ),
        ],
      ),
    );
  }
}
