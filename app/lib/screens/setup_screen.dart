import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content.dart';
import '../store.dart';
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
  final _parentName = TextEditingController();
  final _phone = TextEditingController();
  int _age = 8;
  String _theme = 'rose';
  City _city = cities.firstWhere((c) => c.name == 'Dubai');

  bool _busy = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final store = StoreScope.of(context);
    _parentName.text = store.suggestedName;
    _phone.text = store.suggestedPhone;
  }

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await StoreScope.of(context).createFamily(
        parentName: _parentName.text.trim(),
        phone: _phone.text.trim(),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/welcome.jpg',
                      height: 180,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
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
                  Text('1. About you', style: text.titleMedium),
                  ParentDetailsFields(
                    name: _parentName,
                    phone: _phone,
                    adultConfirmed: StoreScope.of(context)
                        .adultAlreadyConfirmed,
                  ),
                  const SizedBox(height: 16),
                  Text('2. Parent PIN', style: text.titleMedium),
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
                    '3. Your city (for prayer times)',
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
                  Text('4. Your first child', style: text.titleMedium),
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

/// The parent's name and phone number, used at sign-up and by
/// [ParentProfileScreen]. Stored privately: children's devices cannot see it.
class ParentDetailsFields extends StatelessWidget {
  const ParentDetailsFields({
    super.key,
    required this.name,
    required this.phone,
    this.adultConfirmed = false,
  });
  final TextEditingController name;
  final TextEditingController phone;

  /// Already ticked on the "Create an account" form.
  final bool adultConfirmed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Your name'),
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        validator: (v) =>
            (v == null || v.trim().length < 2) ? 'Enter your name' : null,
      ),
      TextFormField(
        controller: phone,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+974 5512 3456',
        ),
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        validator: (v) => AppStore.checkPhone(v ?? ''),
      ),
      const SizedBox(height: 8),
      // Only adults may create the family account; children never sign up.
      FormField<bool>(
        initialValue: adultConfirmed,
        validator: (v) => v == true ? null : 'Please confirm to continue',
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              key: const Key('adultConfirm'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: field.value ?? false,
              onChanged: field.didChange,
              title: const Text(
                "I am the child's parent or legal guardian, and I am 18 years or older.",
              ),
            ),
            if (field.hasError)
              Text(
                field.errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Signed up with email: tap the link in the confirmation email first.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await StoreScope.of(context).checkEmailVerified();
      if (!ok && mounted) {
        setState(
          () => _message = "Not confirmed yet. Open the email and tap the link, then try again. Check the spam folder too.",
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not check: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await StoreScope.of(context).resendVerificationEmail();
      if (mounted) {
        setState(
          () => _message = 'Sent again. It can take a minute to arrive.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not send: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 64),
                const SizedBox(height: 12),
                Text(
                  'Confirm your email',
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a link to ${store.signedInEmail}. Open the email and tap the link, '
                  'then come back and tap the button below.',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _check,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("I've confirmed my email"),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _resend,
                  child: const Text('Send the email again'),
                ),
                TextButton(
                  onPressed: store.signOut,
                  child: const Text('Use a different account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Existing parents who signed up before name and phone were asked.
class ParentProfileScreen extends StatefulWidget {
  const ParentProfileScreen({super.key});

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final store = StoreScope.of(context);
    _name.text =
        (store.parentProfile?['name'] as String?) ?? store.suggestedName;
    _phone.text =
        (store.parentProfile?['phone'] as String?) ?? store.suggestedPhone;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await StoreScope.of(context).saveParentProfile(_name.text, _phone.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About you')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Please add your name and phone number. Only parents in your family can see them.',
              ),
              ParentDetailsFields(name: _name, phone: _phone),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
