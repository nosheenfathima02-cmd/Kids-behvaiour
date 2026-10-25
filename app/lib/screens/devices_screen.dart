import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../store.dart';
import '../widgets.dart';
import 'kid_screen.dart';

/// Parent: the children's phones and tablets linked to the family.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  String? _confirmUid;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    String names(List<String> ids) =>
        ids.map((id) => store.kidById(id)?.name).whereType<String>().join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text("Children's devices")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A linked device shows only its own child, and can only tick that child\'s tasks while they are open. '
            'Remove a device here if it is lost or given away.',
          ),
          const SizedBox(height: 12),
          if (store.devices.isEmpty) const Text('No devices linked yet.'),
          for (final d in store.devices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.tablet_android),
                title: Text(d.name),
                subtitle: Text('For ${names(d.kidIds)}'),
                trailing: _confirmUid == d.uid
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () {
                          store.unlinkDevice(d.uid);
                          setState(() => _confirmUid = null);
                        },
                        child: const Text('Remove'),
                      )
                    : TextButton(
                        onPressed: () => setState(() => _confirmUid = d.uid),
                        child: const Text('Remove…'),
                      ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: store.family.kids.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LinkNewDeviceScreen(),
                    ),
                  ),
            icon: const Icon(Icons.qr_code),
            label: const Text('Link a device'),
          ),
        ],
      ),
    );
  }
}

class LinkNewDeviceScreen extends StatefulWidget {
  const LinkNewDeviceScreen({super.key});

  @override
  State<LinkNewDeviceScreen> createState() => _LinkNewDeviceScreenState();
}

class _LinkNewDeviceScreenState extends State<LinkNewDeviceScreen> {
  final Set<String> _kidIds = {};
  PairingCode? _code;
  bool _busy = false;
  Timer? _timer;
  late AppStore _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = StoreScope.of(context);
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final code = await StoreScope.of(context).createPairing(_kidIds.toList());
      setState(() => _code = code);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not make a code: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final code = _code;
    // An unused code is deleted so it cannot be used later.
    if (code != null && !_store.devices.any((d) => d.pairCode == code.code)) {
      _store.cancelPairing(code.code).ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final code = _code;
    final linked = code == null
        ? null
        : store.devices.where((d) => d.pairCode == code.code).firstOrNull;
    final left = code?.expiresAt.difference(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Link a device')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (code == null) ...[
                Text(
                  'Who will use the new device?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick one child for their own phone, or several for a shared tablet.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in store.family.kids)
                      FilterChip(
                        avatar: KidAvatar(kid: k, radius: 12),
                        label: Text(k.name),
                        selected: _kidIds.contains(k.id),
                        onSelected: (v) => setState(
                          () => v ? _kidIds.add(k.id) : _kidIds.remove(k.id),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _kidIds.isEmpty || _busy ? null : _create,
                  child: const Text('Show the code'),
                ),
              ] else if (linked != null) ...[
                const Icon(
                  Icons.check_circle,
                  size: 72,
                  color: Color(0xFF23824F),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${linked.name}" is linked',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ] else if (left!.isNegative) ...[
                const Text('The code expired.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    _timer?.cancel();
                    setState(() => _code = null);
                  },
                  child: const Text('Make a new code'),
                ),
              ] else ...[
                const Text(
                  'On the child\'s device, install Super Mom, choose "This is my child\'s device", '
                  'then scan this QR code or type the code below.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: code.qrData,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  code.code,
                  key: const Key('pairCode'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Works once. Expires in ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Waiting for the device…'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
