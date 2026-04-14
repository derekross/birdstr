import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/detection_with_audio.dart';
import '../../services/wikipedia_service.dart';

/// Shows detailed info about a detected bird species, including
/// a Wikipedia photo, description, and link to the full article.
class BirdDetailScreen extends StatefulWidget {
  const BirdDetailScreen({super.key, required this.detectionWithAudio});

  final DetectionWithAudio detectionWithAudio;

  @override
  State<BirdDetailScreen> createState() => _BirdDetailScreenState();
}

class _BirdDetailScreenState extends State<BirdDetailScreen> {
  BirdWikiInfo? _wikiInfo;
  bool _loading = true;
  String? _error;

  DetectionWithAudio get dwa => widget.detectionWithAudio;

  @override
  void initState() {
    super.initState();
    _fetchWikipedia();
  }

  Future<void> _fetchWikipedia() async {
    try {
      final info = await WikipediaService.instance.fetchBirdInfo(
        commonName: dwa.species.commonName,
        scientificName: dwa.species.scientificName,
      );
      if (mounted) {
        setState(() {
          _wikiInfo = info;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load bird info.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openWikipedia() async {
    final url = _wikiInfo?.pageUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence = dwa.confidence;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
        ? Colors.orange
        : Colors.red;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image or colored header
          SliverAppBar(
            expandedHeight: _wikiInfo?.thumbnailUrl != null ? 280 : 160,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                dwa.species.commonName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
              background: _wikiInfo?.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl:
                          _wikiInfo!.fullImageUrl ?? _wikiInfo!.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.image_not_supported, size: 48),
                      ),
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Center(
                        child: Icon(
                          Icons.music_note,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer.withAlpha(100),
                        ),
                      ),
                    ),
            ),
            actions: [
              // Publish button
              IconButton(
                icon: const Icon(Icons.send),
                tooltip: 'Publish to Nostr',
                onPressed: () => context.push('/publish', extra: dwa),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Species info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Scientific name
                          Text(
                            dwa.species.scientificName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 8),
                          // Confidence + time
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withAlpha(20),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'Confidence: ${dwa.confidencePercent}',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatTime(dwa.capturedAt),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                          // Taxonomy
                          if (dwa.species.order.isNotEmpty ||
                              dwa.species.className.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            if (dwa.species.order.isNotEmpty)
                              _InfoRow(
                                label: 'Order',
                                value: dwa.species.order,
                              ),
                            if (dwa.species.className.isNotEmpty)
                              _InfoRow(
                                label: 'Family',
                                value: dwa.species.className,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Wikipedia section
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else if (_wikiInfo != null) ...[
                    Text(
                      'About',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _wikiInfo!.extract,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openWikipedia,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Read more on Wikipedia'),
                    ),
                  ] else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No Wikipedia article found for this species.',
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/publish', extra: dwa),
                          icon: const Icon(Icons.send),
                          label: const Text('Publish to Nostr'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
