import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_cubit.dart';

/// App settings — Nostr authentication, relay config, etc.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Nostr authentication section
              Text(
                'Nostr Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.read<AuthCubit>().disconnect(),
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

              // About section
              Text('About', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
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
                        'BirdNET+ V3.0 — 5,250 species\n'
                        'Model license: CC BY-NC-SA 4.0',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
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
      ),
    );
  }
}
