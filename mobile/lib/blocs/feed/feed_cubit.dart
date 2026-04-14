import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/observation.dart';
import '../../services/location_service.dart';
import '../../services/nostr_service.dart';
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

  /// Load observations from birders the user follows.
  Future<void> loadFollowingFeed() async {
    if (!_nostrService.isAuthenticated) {
      emit(const FeedState(status: FeedStatus.error, error: 'Not logged in.'));
      return;
    }

    emit(const FeedState(status: FeedStatus.loading));

    try {
      // Get who we follow.
      final following = await SocialService.instance.getFollowing();

      if (following.isEmpty) {
        emit(const FeedState(status: FeedStatus.loaded, observations: []));
        return;
      }

      final events = await _nostrService.queryEvents([
        {
          'kinds': [30747],
          'authors': following.toList(),
          'limit': 100,
        },
      ]);

      final observations =
          events.map(Observation.fromEvent).whereType<Observation>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(FeedState(status: FeedStatus.loaded, observations: observations));

      debugPrint(
        '[FeedCubit] following feed: ${observations.length} observations',
      );
    } catch (e) {
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
