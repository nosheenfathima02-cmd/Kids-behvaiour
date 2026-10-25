import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logic.dart';
import 'store.dart';

/// Gives every screen access to the store and rebuilds it on changes.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

const starGold = Color(0xFFE0A50F);

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.score, this.size = 20});
  final WeekScore score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: '${score.total} of $maxStars stars',
      child: Wrap(
        spacing: 1,
        children: [
          for (var i = 0; i < maxStars; i++)
            Icon(
              i < score.total ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i < score.total ? starGold : muted,
            ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      TaskStatus.open => ('Open now', cs.primary),
      TaskStatus.done => ('Done', const Color(0xFF23824F)),
      TaskStatus.missed => ('Time closed', cs.error),
      TaskStatus.upcoming => ('Later', cs.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Asks for the parent PIN. Returns true when it matches.
Future<bool> askParentPin(BuildContext context, AppStore store) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(store: store),
  );
  return ok ?? false;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.store});
  final AppStore store;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  int _failures = 0;

  void _submit() {
    if (widget.store.checkPin(_ctrl.text)) {
      Navigator.pop(context, true);
      return;
    }
    _failures++;
    setState(() {
      _error = 'That PIN is not right.';
      _ctrl.clear();
    });
    if (_failures >= 5) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parent PIN'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(errorText: _error, hintText: 'Enter PIN'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Unlock')),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
  });
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
