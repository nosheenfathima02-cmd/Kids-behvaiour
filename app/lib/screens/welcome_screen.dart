import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../store.dart';
import '../widgets.dart';

/// First screen on a new phone: is this Mom's phone or a child's device?
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.star_rounded, size: 64, color: starGold),
                Text(
                  'Super Mom',
                  style: text.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Assalamu alaikum! Who is using this phone?',
                  style: text.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _BigChoice(
                  icon: Icons.admin_panel_settings_outlined,
                  title: "I'm a parent",
                  subtitle: 'Sign in to set up your family or manage it',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ParentSignInScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _BigChoice(
                  icon: Icons.child_care,
                  title: "This is my child's device",
                  subtitle:
                      "Link it to your family with the code on Mom's phone",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LinkDeviceScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, size: 36),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

// ---------------- parent sign-in ----------------

class ParentSignInScreen extends StatefulWidget {
  const ParentSignInScreen({super.key});

  @override
  State<ParentSignInScreen> createState() => _ParentSignInScreenState();
}

class _ParentSignInScreenState extends State<ParentSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _newAccount = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authMessage(e));
    } catch (e) {
      setState(() => _error = 'Sign-in did not work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => 'That email address does not look right.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email or password is not right.',
    'email-already-in-use' => 'There is already an account with this email. Choose "I have an account".',
    'weak-password' => 'Use a password with at least 8 characters.',
    'popup-closed-by-user' ||
    'canceled' ||
    'web-context-canceled' => 'Sign-in was cancelled.',
    'network-request-failed' => 'No internet connection.',
    _ => e.message ?? e.code,
  };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final showApple =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return Scaffold(
      appBar: AppBar(title: const Text('Parent sign-in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Only parents sign in. Children never need an account or password: '
                  'their devices are linked with a code from your phone.',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _run(store.signInWithGoogle),
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                ),
                if (showApple) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _run(store.signInWithApple),
                    icon: const Icon(Icons.apple),
                    label: const Text('Continue with Apple'),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('or with email'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('I have an account'),
                    ),
                    ButtonSegment(value: true, label: Text('New account')),
                  ],
                  selected: {_newAccount},
                  onSelectionChanged: (s) =>
                      setState(() => _newAccount = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  autofillHints: [
                    _newAccount
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _submitEmail(store),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _submitEmail(store),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_newAccount ? 'Create account' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitEmail(AppStore store) {
    if (_newAccount && _password.text.length < 8) {
      setState(() => _error = 'Use a password with at least 8 characters.');
      return;
    }
    _run(
      () => store.signInWithEmail(
        _email.text.trim(),
        _password.text,
        newAccount: _newAccount,
      ),
    );
  }
}

// ---------------- linking a child's device ----------------

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );
    if (value != null) {
      setState(() => _code.text = value.replaceFirst('supermom:', ''));
    }
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await StoreScope.of(context)
        .linkThisDevice(_code.text, _name.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Link a child's device")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('On your phone (the parent app):', style: text.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Settings → Children\'s devices → Link a device. Choose the child and a code appears.',
              ),
              const SizedBox(height: 20),
              if (_canScan) ...[
                FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan the QR code'),
                ),
                const SizedBox(height: 12),
                const Text('or type the 8-letter code:'),
              ],
              TextField(
                key: const Key('code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. K7PM2QXA',
                ),
              ),
              TextField(
                key: const Key('deviceName'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name for this device',
                  hintText: "e.g. Aisha's tablet",
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _link,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Link this device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Scan the code on Mom's phone")),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .where((v) => v.startsWith('supermom:'))
            .firstOrNull;
        if (value == null || _done) return;
        _done = true;
        Navigator.pop(context, value);
      },
    ),
  );
}

// ---------------- device removed by Mom ----------------

class UnlinkedScreen extends StatelessWidget {
  const UnlinkedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 56),
            const SizedBox(height: 12),
            Text(
              'This device is no longer linked',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'A parent removed it from the family. Ask Mom for a new code to link it again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => StoreScope.of(context).signOut(),
              child: const Text('Start again'),
            ),
          ],
        ),
      ),
    ),
  );
}
