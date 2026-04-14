import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nostr_sdk/nostr_sdk.dart';

import '../../models/observation.dart';
import '../../services/location_service.dart';
import '../../services/nostr_service.dart';
import '../../services/relay_service.dart';
import '../../services/social_service.dart';

part 'feed_state.dart';

/// Manages querying and displaying bird observations from Nostr relays.
class FeedCubit extends Cubit<FeedState> {
  FeedCubit() : super(const FeedState.initial());

  final _nostrService = NostrService.instance;

  /// Load observations for the current user.
  Future<void> loadMyObservations() async {
    if (!_nostrService.isAuthenticated) {
      emit(const FeedState(status: FeedStatus.error, error: 'Not logged in.'));
      return;
    }

    emit(const FeedState(status: FeedStatus.loading));

    try {
      final events = await _nostrService.queryEvents([
        {
          'kinds': [30747],
          'authors': [_nostrService.publicKey!],
          'limit': 50,
        },
      ]);

      final observations =
          events.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(FeedState(status: FeedStatus.loaded, observations: observations));

      debugPrint('[FeedCubit] loaded ${observations.length} observations');
    } catch (e) {
      debugPrint('[FeedCubit] error: $e');
      emit(
        FeedState(
          status: FeedStatus.error,
          error: 'Failed to load observations: $e',
        ),
      );
    }
  }

  /// Load all observations from any user (global feed).
  Future<void> loadGlobalFeed() async {
    if (!_nostrService.isAuthenticated) {
      emit(const FeedState(status: FeedStatus.error, error: 'Not logged in.'));
      return;
    }

    emit(const FeedState(status: FeedStatus.loading));

    try {
      final events = await _nostrService.queryEvents([
        {
          'kinds': [30747],
          'limit': 100,
        },
      ]);

      final observations =
          events.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(FeedState(status: FeedStatus.loaded, observations: observations));

      debugPrint(
        '[FeedCubit] global feed: ${observations.length} observations',
      );
    } catch (e) {
      emit(
        FeedState(status: FeedStatus.error, error: 'Failed to load feed: $e'),
      );
    }
  }

  /// Load observations near the user's current location (Feature 9).
  Future<void> loadNearbyFeed() async {
    if (!_nostrService.isAuthenticated) {
      emit(const FeedState(status: FeedStatus.error, error: 'Not logged in.'));
      return;
    }

    emit(const FeedState(status: FeedStatus.loading));

    try {
      // Get current location.
      final location = LocationService.instance;
      final position = await location.getCurrentPosition();

      if (position == null) {
        emit(
          const FeedState(
            status: FeedStatus.error,
            error: 'Could not get your location.',
          ),
        );
        return;
      }

      // Use 4-char geohash prefix (~40km radius).
      final geohash = location.computeGeohash(
        position.latitude,
        position.longitude,
        precision: 4,
      );

      final events = await _nostrService.queryEvents([
        {
          'kinds': [30747],
          '#g': [geohash],
          'limit': 100,
        },
      ]);

      final observations =
          events.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(FeedState(status: FeedStatus.loaded, observations: observations));

      debugPrint(
        '[FeedCubit] nearby ($geohash): ${observations.length} observations',
      );
    } catch (e) {
      emit(
        FeedState(
          status: FeedStatus.error,
          error: 'Failed to load nearby feed: $e',
        ),
      );
    }
  }

  /// Load observations from birders the user follows (NIP-65 outbox model).
  ///
  /// For each followed user:
  /// 1. Look up their write relays from their NIP-65 event (kind:10002)
  /// 2. Query those specific relays for their kind:30747 bird observations
  /// 3. Fall back to our own relays if no NIP-65 event is found
  ///
  /// This is the correct decentralized approach — we go to where
  /// each user publishes, not just where we happen to be connected.
  Future<void> loadFollowingFeed() async {
    if (!_nostrService.isAuthenticated) {
      emit(const FeedState(status: FeedStatus.error, error: 'Not logged in.'));
      return;
    }

    emit(const FeedState(status: FeedStatus.loading));

    try {
      final nostr = _nostrService.nostr;
      if (nostr == null) throw StateError('No Nostr instance');

      // Get who we follow.
      final following = await SocialService.instance.getFollowing();

      if (following.isEmpty) {
        emit(const FeedState(status: FeedStatus.loaded, observations: []));
        return;
      }

      debugPrint(
        '[FeedCubit] loading following feed for '
        '${following.length} users (NIP-65 outbox)',
      );

      final allEvents = <Event>[];

      // Group users by their write relays to batch queries.
      // Users sharing the same write relays get queried together.
      final relayToAuthors = <String, Set<String>>{};
      final usersWithoutRelays = <String>{};

      for (final pubkey in following) {
        final writeRelays = await RelayService.instance.fetchUserWriteRelays(
          pubkey,
          nostr,
        );

        if (writeRelays.isEmpty) {
          usersWithoutRelays.add(pubkey);
        } else {
          for (final relay in writeRelays) {
            relayToAuthors.putIfAbsent(relay, () => {}).add(pubkey);
          }
        }
      }

      // Query each relay group in parallel.
      final futures = <Future<List<Event>>>[];

      for (final entry in relayToAuthors.entries) {
        final relay = entry.key;
        final authors = entry.value.toList();

        debugPrint('[FeedCubit] querying $relay for ${authors.length} authors');

        futures.add(
          _nostrService
              .queryEvents(
                [
                  {
                    'kinds': [30747],
                    'authors': authors,
                    'limit': 50,
                  },
                ],
                tempRelays: [relay],
                timeout: const Duration(seconds: 8),
              )
              .catchError((e) {
                debugPrint('[FeedCubit] query to $relay failed: $e');
                return <Event>[];
              }),
        );
      }

      // For users without NIP-65, fall back to our connected relays.
      if (usersWithoutRelays.isNotEmpty) {
        debugPrint(
          '[FeedCubit] ${usersWithoutRelays.length} users '
          'without NIP-65, querying own relays',
        );

        futures.add(
          _nostrService
              .queryEvents([
                {
                  'kinds': [30747],
                  'authors': usersWithoutRelays.toList(),
                  'limit': 50,
                },
              ])
              .catchError((e) {
                debugPrint('[FeedCubit] fallback query failed: $e');
                return <Event>[];
              }),
        );
      }

      // Wait for all queries to complete.
      final results = await Future.wait(futures);
      for (final events in results) {
        allEvents.addAll(events);
      }

      // Deduplicate by event ID (same event may appear on multiple relays).
      final seen = <String>{};
      final unique = <Event>[];
      for (final event in allEvents) {
        if (seen.add(event.id)) {
          unique.add(event);
        }
      }

      final observations =
          unique.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(FeedState(status: FeedStatus.loaded, observations: observations));

      debugPrint(
        '[FeedCubit] following feed: ${observations.length} observations '
        'from ${relayToAuthors.length} relay groups + '
        '${usersWithoutRelays.length} fallback users',
      );
    } catch (e) {
      debugPrint('[FeedCubit] following feed error: $e');
      emit(
        FeedState(
          status: FeedStatus.error,
          error: 'Failed to load following feed: $e',
        ),
      );
    }
  }

  /// Compute life list — unique species observed.
  List<String> get lifeList {
    final species = <String>{};
    for (final obs in state.observations) {
      if (obs.species.isNotEmpty) {
        species.add(obs.species);
      }
    }
    return species.toList()..sort();
  }

  int get speciesCount => lifeList.length;
}
