import 'package:nostr_sdk/nostr_sdk.dart';

/// A parsed bird observation from a kind:30747 Nostr event.
class Observation {
  const Observation({
    required this.eventId,
    required this.pubkey,
    required this.createdAt,
    required this.species,
    required this.commonName,
    required this.confidence,
    required this.geohash,
    this.location,
    this.notes,
    this.audioUrl,
    this.npub,
  });

  final String eventId;
  final String pubkey;
  final DateTime createdAt;
  final String species;
  final String commonName;
  final double confidence;
  final String geohash;
  final String? location;
  final String? notes;
  final String? audioUrl;
  final String? npub;

  /// Parse a kind:30747 Nostr event into an Observation.
  static Observation? fromEvent(Event event) {
    if (event.kind != 30747) return null;

    String species = '';
    String commonName = '';
    double confidence = 0.0;
    String geohash = '';
    String? location;
    String? audioUrl;

    for (final tag in event.tags) {
      if (tag.isEmpty) continue;
      final key = tag[0];
      if (tag.length < 2) continue;
      final value = tag[1];

      switch (key) {
        case 'species':
          species = value;
        case 'common-name':
          commonName = value;
        case 'confidence':
          confidence = double.tryParse(value) ?? 0.0;
        case 'g':
          geohash = value;
        case 'location':
          location = value;
        case 'imeta':
          // Parse imeta for audio URL
          for (final part in tag.skip(1)) {
            if (part.startsWith('url ')) {
              audioUrl = part.substring(4);
              break;
            }
          }
      }
    }

    if (species.isEmpty && commonName.isEmpty) return null;

    return Observation(
      eventId: event.id,
      pubkey: event.pubkey,
      createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      species: species,
      commonName: commonName.isNotEmpty ? commonName : species,
      confidence: confidence,
      geohash: geohash,
      location: location,
      notes: event.content.isNotEmpty ? event.content : null,
      audioUrl: audioUrl,
      npub: Nip19.encodePubKey(event.pubkey),
    );
  }

  /// Formatted confidence as percentage.
  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  /// Relative time string (e.g., "2 hours ago").
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
