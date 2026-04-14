import 'package:flutter/foundation.dart';
import 'package:nostr_sdk/nostr_sdk.dart';

import 'nostr_service.dart';

/// Handles social interactions for bird observations.
///
/// Peer verification (NIP-32 labels), cross-posting (kind:1),
/// and following other birders.
class SocialService {
  SocialService._();
  static final instance = SocialService._();

  final _nostrService = NostrService.instance;

  // -----------------------------------------------------------------------
  // Peer verification (NIP-32)
  // -----------------------------------------------------------------------

  /// Confirm a bird observation by publishing a NIP-32 label event.
  Future<Event?> confirmObservation({
    required String observationEventId,
    required String observationPubkey,
  }) async {
    final pk = _nostrService.publicKey;
    if (pk == null) return null;

    final event = Event(pk, EventKind.label, [
      ['e', observationEventId],
      ['p', observationPubkey],
      ['L', 'org.birds.verification'],
      ['l', 'confirmed', 'org.birds.verification'],
    ], '');

    return _nostrService.publishEvent(event);
  }

  /// Dispute a bird observation.
  Future<Event?> disputeObservation({
    required String observationEventId,
    required String observationPubkey,
    String reason = '',
  }) async {
    final pk = _nostrService.publicKey;
    if (pk == null) return null;

    final event = Event(pk, EventKind.label, [
      ['e', observationEventId],
      ['p', observationPubkey],
      ['L', 'org.birds.verification'],
      ['l', 'disputed', 'org.birds.verification'],
    ], reason);

    return _nostrService.publishEvent(event);
  }

  /// Query verification labels for an observation.
  Future<({int confirmed, int disputed})> getVerificationCounts(
    String observationEventId,
  ) async {
    try {
      final events = await _nostrService.queryEvents([
        {
          'kinds': [EventKind.label],
          '#e': [observationEventId],
          '#L': ['org.birds.verification'],
          'limit': 100,
        },
      ]);

      var confirmed = 0;
      var disputed = 0;

      for (final event in events) {
        for (final tag in event.tags) {
          if (tag.length >= 3 &&
              tag[0] == 'l' &&
              tag[2] == 'org.birds.verification') {
            if (tag[1] == 'confirmed') confirmed++;
            if (tag[1] == 'disputed') disputed++;
          }
        }
      }

      return (confirmed: confirmed, disputed: disputed);
    } catch (e) {
      debugPrint('[SocialService] getVerificationCounts error: $e');
      return (confirmed: 0, disputed: 0);
    }
  }

  // -----------------------------------------------------------------------
  // Cross-posting (kind:1)
  // -----------------------------------------------------------------------

  /// Cross-post a bird observation as a regular kind:1 note.
  Future<Event?> crossPostObservation({
    required String observationEventId,
    required String species,
    required String commonName,
    required String confidence,
    String? location,
    String? notes,
  }) async {
    final pk = _nostrService.publicKey;
    if (pk == null) return null;

    final parts = <String>[
      'Bird spotted: $commonName ($species)',
      'Confidence: $confidence',
    ];
    if (location != null && location.isNotEmpty) {
      parts.add('Location: $location');
    }
    if (notes != null && notes.isNotEmpty) {
      parts.add(notes);
    }
    parts.add('#birding #birdwatching #nostr');

    final content = parts.join('\n');

    final event = Event(pk, EventKind.textNote, [
      ['e', observationEventId, '', 'mention'],
      ['t', 'birding'],
      ['t', 'birdwatching'],
      ['t', commonName.toLowerCase().replaceAll(' ', '-')],
    ], content);

    return _nostrService.publishEvent(event);
  }

  // -----------------------------------------------------------------------
  // Following
  // -----------------------------------------------------------------------

  /// Get the current user's contact list (who they follow).
  Future<Set<String>> getFollowing() async {
    final pk = _nostrService.publicKey;
    if (pk == null) return {};

    try {
      final events = await _nostrService.queryEvents([
        {
          'kinds': [EventKind.contactList],
          'authors': [pk],
          'limit': 1,
        },
      ]);

      if (events.isEmpty) return {};

      final contactEvent = events.first;
      final following = <String>{};

      for (final tag in contactEvent.tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
          following.add(tag[1]);
        }
      }

      return following;
    } catch (e) {
      debugPrint('[SocialService] getFollowing error: $e');
      return {};
    }
  }

  /// Follow a birder by adding them to the contact list.
  ///
  /// This replaces the entire contact list (kind:3 is replaceable).
  Future<Event?> followBirder(String pubkeyHex) async {
    final pk = _nostrService.publicKey;
    if (pk == null) return null;

    // Get current contact list.
    final currentFollowing = await getFollowing();
    currentFollowing.add(pubkeyHex);

    // Build new contact list.
    final tags = currentFollowing.map((p) => ['p', p]).toList();

    final event = Event(pk, EventKind.contactList, tags, '');
    return _nostrService.publishEvent(event);
  }

  /// Unfollow a birder.
  Future<Event?> unfollowBirder(String pubkeyHex) async {
    final pk = _nostrService.publicKey;
    if (pk == null) return null;

    final currentFollowing = await getFollowing();
    currentFollowing.remove(pubkeyHex);

    final tags = currentFollowing.map((p) => ['p', p]).toList();

    final event = Event(pk, EventKind.contactList, tags, '');
    return _nostrService.publishEvent(event);
  }
}
