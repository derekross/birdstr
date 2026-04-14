import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/discovery_log_service.dart';

/// Shows the user's complete discovery history from local storage.
///
/// This includes every bird BirdNET has ever identified,
/// regardless of whether it was published to Nostr.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<DiscoveryEntry> _allEntries = [];
  List<String> _lifeList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  /// Reload data from the discovery log. Called by ShellScreen on tab switch.
  void refresh() => _load();

  Future<void> _load() async {
    final entries = await DiscoveryLogService.instance.getAll();
    final lifeList = await DiscoveryLogService.instance.getLifeList();
    if (mounted) {
      setState(() {
        _allEntries = entries;
        _lifeList = lifeList;
        _loading = false;
      });
    }
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
        title: const Text('Discovery History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'All (${_allEntries.length})'),
            Tab(text: 'Life List (${_lifeList.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // All discoveries tab
                _allEntries.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No discoveries yet.\nStart listening for birds!',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _allEntries.length,
                          itemBuilder: (context, index) {
                            return _DiscoveryTile(entry: _allEntries[index]);
                          },
                        ),
                      ),

                // Life list tab
                _lifeList.isEmpty
                    ? const Center(child: Text('No species recorded yet.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _lifeList.length,
                          itemBuilder: (context, index) {
                            final species = _lifeList[index];
                            // Find best confidence for this species.
                            final entries = _allEntries.where(
                              (e) => e.scientificName == species,
                            );
                            final best = entries.reduce(
                              (a, b) => a.confidence > b.confidence ? a : b,
                            );
                            final count = entries.length;

                            return _LifeListTile(
                              species: species,
                              commonName: best.commonName,
                              bestConfidence: best.confidencePercent,
                              count: count,
                              firstSeen: entries.last.dateString,
                              bestEntry: best,
                            );
                          },
                        ),
                      ),
              ],
            ),
    );
  }
}

class _DiscoveryTile extends StatelessWidget {
  const _DiscoveryTile({required this.entry});
  final DiscoveryEntry entry;

  Future<void> _onTap(BuildContext context) async {
    // Load saved audio and navigate to bird detail.
    final dwa = await DiscoveryLogService.instance.toDetectionWithAudio(entry);
    if (dwa != null && context.mounted) {
      context.push('/bird-detail', extra: dwa);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence = entry.confidence;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        onTap: () => _onTap(context),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          radius: 20,
          child: Icon(Icons.music_note, color: color, size: 18),
        ),
        title: Text(
          entry.commonName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${entry.scientificName} — ${entry.timeAgo}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.hasAudio)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.audiotrack,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
                ),
              ),
            if (entry.publishedToNostr)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.cloud_done,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            Text(
              entry.confidencePercent,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeListTile extends StatelessWidget {
  const _LifeListTile({
    required this.species,
    required this.commonName,
    required this.bestConfidence,
    required this.count,
    required this.firstSeen,
    required this.bestEntry,
  });

  final String species;
  final String commonName;
  final String bestConfidence;
  final int count;
  final String firstSeen;
  final DiscoveryEntry bestEntry;

  Future<void> _onTap(BuildContext context) async {
    final dwa = await DiscoveryLogService.instance.toDetectionWithAudio(
      bestEntry,
    );
    if (dwa != null && context.mounted) {
      context.push('/bird-detail', extra: dwa);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: ListTile(
        onTap: () => _onTap(context),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.spa,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 18,
          ),
        ),
        title: Text(
          commonName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$species\nFirst: $firstSeen — Best: $bestConfidence',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
          ),
        ),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${count}x',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
