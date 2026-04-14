import 'package:birdnet_flutter/birdnet_flutter.dart';

/// Constructs Nostr kind:30747 bird observation events.
///
/// Takes a [Detection] from BirdNET and location data,
/// builds the structured event tags for publishing to Nostr.
class ObservationService {
  /// Build the tags list for a kind:30747 bird observation event.
  ///
  /// Returns a list of tag arrays ready for inclusion in a Nostr event.
  static List<List<String>> buildObservationTags({
    required Detection detection,
    required String observationId,
    required double latitude,
    required double longitude,
    required String geohash,
    String? locationName,
    String? audioUrl,
    String? audioHash,
    String? notes,
  }) {
    final tags = <List<String>>[
      // Identity & editability
      ['d', observationId],
      [
        'alt',
        'Bird observation: ${detection.species.commonName} '
            '(${detection.species.scientificName})'
            '${locationName != null ? ' at $locationName' : ''}',
      ],

      // Species identification
      ['species', detection.species.scientificName],
      ['common-name', detection.species.commonName],
      if (detection.species.order.isNotEmpty)
        ['order', detection.species.order],
      if (detection.species.className.isNotEmpty)
        ['family', detection.species.className],

      // Confidence
      ['confidence', detection.confidence.toStringAsFixed(4)],

      // Observation metadata
      ['observation-type', 'audio'],
      ['start', (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString()],

      // Geolocation
      ['g', geohash],
      if (locationName != null) ['location', locationName],

      // Taxonomy labels (NIP-32)
      ['L', 'org.birds.taxonomy'],
      ['l', detection.species.scientificName, 'org.birds.taxonomy'],

      // Hashtags for discovery
      ['t', 'birding'],
      ['t', 'birdwatching'],
      ['t', detection.species.commonName.toLowerCase().replaceAll(' ', '-')],
    ];

    // Audio attachment (NIP-92 imeta)
    if (audioUrl != null) {
      final imetaParts = [
        'url $audioUrl',
        'm audio/wav',
        if (audioHash != null) 'x $audioHash',
        'alt ${detection.species.commonName} song recording',
      ];
      tags.add(['imeta', ...imetaParts]);
    }

    return tags;
  }

  /// The Nostr event kind for bird observations.
  static const int observationKind = 30747;
}
