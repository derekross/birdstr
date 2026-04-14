import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/observation.dart';
import '../../services/nostr_service.dart';
import '../../services/social_service.dart';
import '../../services/wikipedia_service.dart';
import '../verification_buttons/verification_buttons.dart';

/// Displays a single observation in a feed with a bird photo.
class ObservationCard extends StatefulWidget {
  const ObservationCard({
    super.key,
    required this.observation,
    this.showAuthor = false,
  });

  final Observation observation;
  final bool showAuthor;

  @override
  State<ObservationCard> createState() => _ObservationCardState();
}

class _ObservationCardState extends State<ObservationCard> {
  String? _imageUrl;
  bool _imageLoaded = false;

  Observation get observation => widget.observation;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  Future<void> _fetchImage() async {
    final info = await WikipediaService.instance.fetchBirdInfo(
      commonName: observation.commonName,
      scientificName: observation.species,
    );
    if (mounted && info?.thumbnailUrl != null) {
      setState(() {
        _imageUrl = info!.thumbnailUrl;
        _imageLoaded = true;
      });
    } else if (mounted) {
      setState(() => _imageLoaded = true);
    }
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Cross-post as note'),
              subtitle: const Text('Share to your followers as a kind:1 note'),
              onTap: () async {
                Navigator.pop(context);
                final result = await SocialService.instance
                    .crossPostObservation(
                      observationEventId: observation.eventId,
                      species: observation.species,
                      commonName: observation.commonName,
                      confidence: observation.confidencePercent,
                      location: observation.location,
                      notes: observation.notes,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result != null
                            ? 'Cross-posted to Nostr!'
                            : 'Failed to cross-post.',
                      ),
                      backgroundColor: result != null
                          ? Colors.green
                          : Colors.red,
                    ),
                  );
                }
              },
            ),
            if (widget.showAuthor &&
                observation.pubkey != NostrService.instance.publicKey)
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Follow this birder'),
                subtitle: Text('${observation.npub?.substring(0, 16)}...'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await SocialService.instance.followBirder(
                    observation.pubkey,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result != null
                              ? 'Now following this birder!'
                              : 'Failed to follow.',
                        ),
                        backgroundColor: result != null
                            ? Colors.green
                            : Colors.red,
                      ),
                    );
                  }
                },
              ),
            // Delete option — only for your own observations.
            if (observation.pubkey == NostrService.instance.publicKey)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red[400]),
                title: Text(
                  'Delete observation',
                  style: TextStyle(color: Colors.red[400]),
                ),
                subtitle: const Text('Request relays to delete this post'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete observation?'),
        content: Text(
          'This will request relays to delete your '
          '${observation.commonName} observation. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final result = await NostrService.instance.deleteEvent(
                  observation.eventId,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result != null
                            ? 'Observation deleted.'
                            : 'Failed to delete.',
                      ),
                      backgroundColor: result != null
                          ? Colors.green
                          : Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final confidence = observation.confidence;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bird photo + species overlay
          Stack(
            children: [
              // Photo
              SizedBox(
                height: _imageUrl != null ? 160 : 0,
                width: double.infinity,
                child: _imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 160,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      )
                    : const SizedBox.shrink(),
              ),

              // Gradient overlay on photo
              if (_imageUrl != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ),

              // Species name on photo
              if (_imageUrl != null)
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        observation.commonName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                      Text(
                        observation.species,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Confidence badge on photo
              if (_imageUrl != null)
                Positioned(
                  bottom: 8,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      observation.confidencePercent,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

              // Menu button on photo
              if (_imageUrl != null && NostrService.instance.isAuthenticated)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: () => _showActions(context),
                  ),
                ),
            ],
          ),

          // Fallback header when no image
          if (_imageUrl == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withAlpha(30),
                    radius: 20,
                    child: Icon(Icons.music_note, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          observation.commonName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          observation.species,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      observation.confidencePercent,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (NostrService.instance.isAuthenticated)
                    SizedBox(
                      width: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => _showActions(context),
                      ),
                    ),
                ],
              ),
            ),

          // Body content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notes
                if (observation.notes != null &&
                    observation.notes!.isNotEmpty) ...[
                  Text(
                    observation.notes!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],

                // Audio player
                if (observation.audioUrl != null) ...[
                  _AudioMiniPlayer(url: observation.audioUrl!),
                  const SizedBox(height: 8),
                ],

                // Footer: location, time, author
                Row(
                  children: [
                    if (observation.location != null) ...[
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(100),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          observation.location!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(100),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(100),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      observation.timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                    if (widget.showAuthor && observation.npub != null) ...[
                      const Spacer(),
                      Text(
                        '${observation.npub!.substring(0, 12)}...',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(80),
                        ),
                      ),
                    ],
                  ],
                ),

                // Verification buttons
                const SizedBox(height: 8),
                VerificationButtons(observation: observation),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline mini audio player for observation cards.
class _AudioMiniPlayer extends StatefulWidget {
  const _AudioMiniPlayer({required this.url});
  final String url;

  @override
  State<_AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

class _AudioMiniPlayerState extends State<_AudioMiniPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        final completed = state.processingState == ProcessingState.completed;
        setState(() {
          _isPlaying = state.playing && !completed;
          _isLoading =
              state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering;
          if (completed) {
            _position = _duration;
          }
        });
        if (completed) {
          _player.pause();
          _player.seek(Duration.zero);
        }
      }
    });
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle) {
        try {
          await _player.setUrl(widget.url);
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Could not load audio: $e')));
          }
          return;
        }
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: _duration.inMilliseconds > 0
                  ? _position.inMilliseconds / _duration.inMilliseconds
                  : 0,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withAlpha(20),
              valueColor: AlwaysStoppedAnimation(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _duration.inMilliseconds > 0
                ? '${(_position.inMilliseconds / 1000).toStringAsFixed(1)}/'
                      '${(_duration.inMilliseconds / 1000).toStringAsFixed(1)}s'
                : '--',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
            ),
          ),
        ],
      ),
    );
  }
}
