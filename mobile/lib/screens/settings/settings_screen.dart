import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_cubit.dart';
import '../../services/blossom_server_service.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';

/// Settings screen with Account, Relays, and Blossom Servers tabs.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Account'),
            Tab(text: 'Relays'),
            Tab(text: 'Blossom'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_AccountTab(), _RelaysTab(), _BlossomTab()],
      ),
    );
  }
}

// =============================================================================
// Account Tab
// =============================================================================

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  void _showNsecDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import nsec'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'nsec1...',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          maxLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final nsec = controller.text.trim();
              if (nsec.isNotEmpty) {
                context.read<AuthCubit>().importNsec(nsec);
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showBunkerDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect with NIP-46'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'bunker://...',
            border: OutlineInputBorder(),
          ),
          maxLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final uri = controller.text.trim();
              if (uri.isNotEmpty) {
                context.read<AuthCubit>().connectBunker(uri);
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            if (state.isAuthenticated)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Connected',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.npub ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.read<AuthCubit>().disconnect(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ),
              )
            else if (state.status == AuthStatus.connecting)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else
              Column(
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('Connect with NIP-46'),
                      subtitle: const Text('Amber or bunker app'),
                      onTap: () => _showBunkerDialog(context),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.key),
                      title: const Text('Import nsec'),
                      subtitle: const Text('Paste your private key'),
                      onTap: () => _showNsecDialog(context),
                    ),
                  ),
                ],
              ),

            const Divider(height: 32),

            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Birds',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Identify bird sounds with BirdNET and publish observations to Nostr.',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'BirdNET+ V3.0\n'
                      'Model license: CC BY-NC-SA 4.0\n'
                      'Event kind: 30747 (bird observation)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Relays Tab
// =============================================================================

class _RelaysTab extends StatefulWidget {
  const _RelaysTab();

  @override
  State<_RelaysTab> createState() => _RelaysTabState();
}

class _RelaysTabState extends State<_RelaysTab> {
  bool _saving = false;

  void _addRelay() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add relay'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'wss://relay.example.com',
            border: OutlineInputBorder(),
          ),
          maxLines: 1,
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                RelayService.instance.addRelay(url);
                Navigator.pop(dialogContext);
                setState(() {});
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToNostr() async {
    final nostr = NostrService.instance.nostr;
    final pubkey = NostrService.instance.publicKey;
    if (nostr == null || pubkey == null) return;

    setState(() => _saving = true);
    final result = await RelayService.instance.saveRelayList(nostr, pubkey);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result != null
                ? 'Relay list published to Nostr (kind:10002)'
                : 'Failed to publish relay list',
          ),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final relays = RelayService.instance.relays;
    final isAuth = NostrService.instance.isAuthenticated;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${relays.length} relays',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      RelayService.instance.loadedFromNostr
                          ? 'Loaded from NIP-65'
                          : 'Using defaults',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ),
              ),
              if (isAuth)
                TextButton.icon(
                  onPressed: _saving ? null : _saveToNostr,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Publish'),
                ),
              IconButton(icon: const Icon(Icons.add), onPressed: _addRelay),
            ],
          ),
        ),

        // Relay list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: relays.length,
            itemBuilder: (context, index) {
              final relay = relays[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  title: Text(
                    relay.url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      _ToggleChip(
                        label: 'Read',
                        active: relay.read,
                        onTap: () {
                          RelayService.instance.updateRelay(
                            relay.url,
                            read: !relay.read,
                          );
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _ToggleChip(
                        label: 'Write',
                        active: relay.write,
                        onTap: () {
                          RelayService.instance.updateRelay(
                            relay.url,
                            write: !relay.write,
                          );
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.red.withAlpha(150),
                    ),
                    onPressed: () {
                      RelayService.instance.removeRelay(relay.url);
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primary.withAlpha(20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withAlpha(40),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withAlpha(100),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Blossom Servers Tab
// =============================================================================

class _BlossomTab extends StatefulWidget {
  const _BlossomTab();

  @override
  State<_BlossomTab> createState() => _BlossomTabState();
}

class _BlossomTabState extends State<_BlossomTab> {
  bool _saving = false;

  void _addServer() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Blossom server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://blossom.example.com',
            border: OutlineInputBorder(),
          ),
          maxLines: 1,
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                BlossomServerService.instance.addServer(url);
                Navigator.pop(dialogContext);
                setState(() {});
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToNostr() async {
    final nostr = NostrService.instance.nostr;
    final pubkey = NostrService.instance.publicKey;
    if (nostr == null || pubkey == null) return;

    setState(() => _saving = true);
    final result = await BlossomServerService.instance.saveServerList(
      nostr,
      pubkey,
    );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result != null
                ? 'Server list published to Nostr (kind:10063)'
                : 'Failed to publish server list',
          ),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = BlossomServerService.instance.servers;
    final isAuth = NostrService.instance.isAuthenticated;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${servers.length} servers',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      BlossomServerService.instance.loadedFromNostr
                          ? 'Loaded from kind:10063'
                          : 'Using defaults',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'First server is used for uploads. Drag to reorder.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(80),
                      ),
                    ),
                  ],
                ),
              ),
              if (isAuth)
                TextButton.icon(
                  onPressed: _saving ? null : _saveToNostr,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Publish'),
                ),
              IconButton(icon: const Icon(Icons.add), onPressed: _addServer),
            ],
          ),
        ),

        // Server list (reorderable)
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: servers.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              BlossomServerService.instance.reorderServer(oldIndex, newIndex);
              setState(() {});
            },
            itemBuilder: (context, index) {
              final server = servers[index];
              return Card(
                key: ValueKey(server),
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  leading: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        index == 0 ? Icons.star : Icons.drag_indicator,
                        size: 20,
                        color: index == 0
                            ? Colors.amber
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(60),
                      ),
                      if (index == 0)
                        Text(
                          'Primary',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.amber[700],
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    server,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.red.withAlpha(150),
                    ),
                    onPressed: () {
                      BlossomServerService.instance.removeServer(server);
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
