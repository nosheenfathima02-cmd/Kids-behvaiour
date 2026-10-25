import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content.dart';
import '../widgets.dart';

/// First launch: Mom sets a PIN, picks the city for prayer times and adds the first child.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _name = TextEditingController();
  int _age = 8;
  String _theme = 'ocean';
  City _city = cities.firstWhere((c) => c.name == 'Dubai');

  bool _busy = false;

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await StoreScope.of(context).createFamily(
        pin: _pin.text,
        city: _city,
        kidName: _name.text.trim(),
        kidAge: _age,
        theme: _theme,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the family: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.star_rounded, size: 56, color: starGold),
                  Text(
                    'Assalamu alaikum!',
                    style: text.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Let's set up Super Mom for your family.",
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text('1. Parent PIN', style: text.titleMedium),
                  const Text(
                    'Kids need this PIN to open the parent screens. Keep it secret.',
                  ),
                  TextFormField(
                    controller: _pin,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4 to 6 digits)',
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    validator: (v) => (v == null || v.length < 4)
                        ? 'Use at least 4 digits'
                        : null,
                  ),
                  TextFormField(
                    controller: _pin2,
                    decoration: const InputDecoration(
                      labelText: 'Type the PIN again',
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 6,
                    validator: (v) =>
                        v != _pin.text ? 'The two PINs are different' : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '2. Your city (for prayer times)',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<City>(
                    initialValue: _city,
                    isExpanded: true,
                    items: [
                      for (final c in cities)
                        DropdownMenuItem(value: c, child: Text(c.name)),
                    ],
                    onChanged: (c) => setState(() => _city = c!),
                  ),
                  const Text(
                    'You can change the calculation method later in Settings.',
                  ),
                  const SizedBox(height: 24),
                  Text('3. Your first child', style: text.titleMedium),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'First name'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Age'),
                      Expanded(
                        child: Slider(
                          value: _age.toDouble(),
                          min: 4,
                          max: 15,
                          divisions: 11,
                          label: '$_age',
                          onChanged: (v) => setState(() => _age = v.round()),
                        ),
                      ),
                      Text('$_age'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Theme'),
                  const SizedBox(height: 8),
                  ThemePicker(
                    value: _theme,
                    onChanged: (t) => setState(() => _theme = t),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _finish,
                    child: const Text('Start'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => StoreScope.of(context).signOut(),
                    child: const Text('Use a different account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in kidThemes.entries)
          Tooltip(
            message: e.value.name,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(e.key),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: e.value.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: 3,
                    color: e.key == value
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                  ),
                ),
                child: e.key == value
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// A parent signed in on a new phone: set the PIN that keeps kids out of the parent screens.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _form = GlobalKey<FormState>();
  final _pin = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent PIN for this phone')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'If your children also use this phone, they will need this PIN to open the parent screens.',
                ),
                TextFormField(
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'PIN (4 to 6 digits)',
                  ),
                  validator: (v) => (v == null || v.length < 4)
                      ? 'Use at least 4 digits'
                      : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      StoreScope.of(context).changePin(_pin.text);
                    }
                  },
                  child: const Text('Save PIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
