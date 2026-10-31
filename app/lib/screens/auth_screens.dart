import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../store.dart';
import '../widgets.dart';

/// Turns Firebase sign-in errors into plain sentences.
String authMessage(FirebaseAuthException e) => switch (e.code) {
  'invalid-email' => 'That email address does not look right.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Email or password is not right.',
  'email-already-in-use' =>
    'There is already an account with this email. Sign in instead.',
  'weak-password' => 'Choose a stronger password: at least 8 characters.',
  'too-many-requests' =>
    'Too many tries. Please wait a few minutes and try again.',
  'popup-closed-by-user' ||
  'canceled' ||
  'web-context-canceled' => 'Sign-in was cancelled.',
  'network-request-failed' => 'No internet connection.',
  _ => e.message ?? e.code,
};

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/welcome.jpg',
                      height: 96,
                      width: 96,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.45),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _field(
  String label,
  IconData icon, {
  String? hint,
  Widget? suffix,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  prefixIcon: Icon(icon),
  suffixIcon: suffix,
  border: const OutlineInputBorder(),
);

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.validator,
    this.newPassword = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool newPassword;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autofillHints: [
      widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: widget.validator,
    onFieldSubmitted: (_) => widget.onSubmitted?.call(),
    decoration: _field(
      widget.label,
      Icons.lock_outline,
      suffix: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

// ---------------- sign in ----------------

class ParentSignInScreen extends StatefulWidget {
  const ParentSignInScreen({super.key});

  @override
  State<ParentSignInScreen> createState() => _ParentSignInScreenState();
}

class _ParentSignInScreenState extends State<ParentSignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in did not work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot(AppStore store) async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(
        () => _error =
            'Type your email above first, then tap "Forgot password?".',
      );
      return;
    }
    try {
      await store.sendPasswordReset(email);
      setState(() {
        _error = null;
        _info =
            'If $email has an account, we sent a link to choose a new password. Check Spam too.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = authMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final showApple =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return AbsorbPointer(
      absorbing: _busy,
      child: _AuthScaffold(
        title: 'Welcome back',
        subtitle:
            'Sign in to manage your family. Children never need an account.',
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => _run(store.signInWithGoogle),
            icon: const Icon(Icons.g_mobiledata, size: 30),
            label: const Text('Continue with Google'),
          ),
          if (showApple) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
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
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or sign in with email'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: _field('Email', Icons.mail_outline),
                  validator: (v) =>
                      (v ?? '').contains('@') ? null : 'Enter your email',
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Enter your password' : null,
                  onSubmitted: () => _signIn(store),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _forgot(store),
              child: const Text('Forgot password?'),
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
          if (_info != null) Text(_info!, style: TextStyle(color: cs.primary)),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => _signIn(store),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('New to Super Mom?'),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateAccountScreen(),
                  ),
                ),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _signIn(AppStore store) {
    if (!_form.currentState!.validate()) return;
    _run(
      () => store.signInWithEmail(
        _email.text.trim(),
        _password.text,
        newAccount: false,
      ),
    );
  }
}

// ---------------- create an account ----------------

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _adult = false;
  bool _adultError = false;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final ok = _form.currentState!.validate();
    setState(() => _adultError = !_adult);
    if (!ok || !_adult) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await StoreScope.of(context).createParentAccount(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the account: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AbsorbPointer(
      absorbing: _busy,
      child: _AuthScaffold(
        title: 'Create your parent account',
        subtitle: 'For parents and guardians. You will add your children next.',
        children: [
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('fullName'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: _field('Full name', Icons.person_outline),
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('newEmail'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: _field('Email', Icons.mail_outline),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch((v ?? '').trim())
                      ? null
                      : 'Enter a valid email',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('newPhone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: _field(
                    'Phone number',
                    Icons.phone_outlined,
                    hint: '+974 5512 3456',
                  ),
                  validator: (v) => AppStore.checkPhone(v ?? ''),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  newPassword: true,
                  validator: (v) =>
                      (v ?? '').length < 8 ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _password2,
                  label: 'Confirm password',
                  newPassword: true,
                  validator: (v) => v != _password.text
                      ? 'The passwords are different'
                      : null,
                  onSubmitted: _create,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _adult,
            onChanged: (v) => setState(() {
              _adult = v ?? false;
              _adultError = false;
            }),
            title: const Text(
              "I am the child's parent or legal guardian, and I am 18 years or older.",
            ),
            subtitle: _adultError
                ? Text(
                    'Please confirm to continue',
                    style: TextStyle(color: cs.error),
                  )
                : null,
          ),
          Text(
            'We will send a link to confirm your email. By creating an account you agree to the '
            'Super Mom privacy policy: your family\'s information is used only to run the app and is never sold or shared.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _create,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create account'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already have an account?'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
