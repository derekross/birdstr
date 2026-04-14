import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/auth/auth_cubit.dart';
import '../../models/observation.dart';
import '../../services/nostr_service.dart';
import '../../widgets/observation_card/observation_card.dart';

/// Profile screen — your public Nostr identity and published observations.
///
/// Shows what other birders see when they view your profile:
/// your published observations, public life list (derived from published
/// kind:30747 events), and identity.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Observation> _publishedObservations = [];
  List<_PublicSpecies> _publicLifeList = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Reload from relays. Called by ShellScreen on tab switch.
  void refresh() => _load();

  Future<void> _load() async {
    final nostr = NostrService.instance;
    if (!nostr.isAuthenticated) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final events = await nostr.queryEvents([
        {
          'kinds': [30747],
          'authors': [nostr.publicKey!],
          'limit': 200,
        },
      ]);

      final observations =
          events.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Derive public life list from published observations.
      final speciesMap = <String, _PublicSpecies>{};
      for (final obs in observations) {
        if (obs.species.isEmpty) continue;
        final existing = speciesMap[obs.species];
        if (existing == null) {
          speciesMap[obs.species] = _PublicSpecies(
            scientificName: obs.species,
            commonName: obs.commonName,
            bestConfidence: obs.confidence,
            count: 1,
            firstSeen: obs.createdAt,
          );
        } else {
          speciesMap[obs.species] = _PublicSpecies(
            scientificName: obs.species,
            commonName: obs.commonName,
            bestConfidence: obs.confidence > existing.bestConfidence
                ? obs.confidence
                : existing.bestConfidence,
            count: existing.count + 1,
            firstSeen: obs.createdAt.isBefore(existing.firstSeen)
                ? obs.createdAt
                : existing.firstSeen,
          );
        }
      }

      final lifeList = speciesMap.values.toList()
        ..sort((a, b) => a.commonName.compareTo(b.commonName));

      if (mounted) {
        setState(() {
          _publishedObservations = observations;
          _publicLifeList = lifeList;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          if (!authState.isAuthenticated) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Connect your Nostr account to see your public profile.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.push('/settings'),
                      child: const Text('Go to Settings'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              // Identity card
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person,
                        size: 28,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${authState.npub?.substring(0, 20)}...',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _MiniStat(
                                value: '${_publicLifeList.length}',
                                label: 'species',
                              ),
                              const SizedBox(width: 16),
                              _MiniStat(
                                value: '${_publishedObservations.length}',
                                label: 'published',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tabs: Published / Public Life List
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'Published (${_publishedObservations.length})'),
                  Tab(text: 'Life List (${_publicLifeList.length})'),
                ],
              ),

              // Tab content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Published observations
                          _publishedObservations.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Text(
                                      'No published observations yet.\n'
                                      'Listen for birds and publish to Nostr!',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: _publishedObservations.length,
                                    itemBuilder: (context, index) {
                                      return ObservationCard(
                                        observation:
                                            _publishedObservations[index],
                                      );
                                    },
                                  ),
                                ),

                          // Public life list
                          _publicLifeList.isEmpty
                              ? const Center(
                                  child: Text('No species published yet.'),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: _publicLifeList.length,
                                    itemBuilder: (context, index) {
                                      final sp = _publicLifeList[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 3,
                                        ),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            child: Icon(
                                              Icons.spa,
                                              size: 18,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                          title: Text(
                                            sp.commonName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${sp.scientificName}\n'
                                            'First: ${_formatDate(sp.firstSeen)} '
                                            '— Best: ${sp.confidencePercent}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withAlpha(120),
                                            ),
                                          ),
                                          isThreeLine: true,
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${sp.count}x',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
          ),
        ),
      ],
    );
  }
}

class _PublicSpecies {
  const _PublicSpecies({
    required this.scientificName,
    required this.commonName,
    required this.bestConfidence,
    required this.count,
    required this.firstSeen,
  });

  final String scientificName;
  final String commonName;
  final double bestConfidence;
  final int count;
  final DateTime firstSeen;

  String get confidencePercent =>
      '${(bestConfidence * 100).toStringAsFixed(1)}%';
}
