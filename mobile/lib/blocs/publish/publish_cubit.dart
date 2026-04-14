import 'package:birdnet_flutter/birdnet_flutter.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/nostr_service.dart';
import '../../services/observation_service.dart';

part 'publish_state.dart';

/// Manages the flow of publishing a bird observation to Nostr.
class PublishCubit extends Cubit<PublishState> {
  PublishCubit() : super(const PublishState.idle());

  final _nostrService = NostrService.instance;

  /// Expose for Blossom auth.
  NostrService get nostrService => _nostrService;

  /// Publish a bird observation to Nostr.
  Future<void> publishObservation({
    required Detection detection,
    required double latitude,
    required double longitude,
    required String geohash,
    String? locationName,
    String notes = '',
    String? audioUrl,
    String? audioHash,
  }) async {
    if (!_nostrService.isAuthenticated) {
      emit(
        const PublishState(
          status: PublishStatus.error,
          error: 'Not logged in. Connect your Nostr account first.',
        ),
      );
      return;
    }

    emit(const PublishState(status: PublishStatus.publishing));

    try {
      final now = DateTime.now();
      final observationId =
          '${now.toIso8601String()}-'
          '${detection.species.scientificName.toLowerCase().replaceAll(' ', '-')}';

      final tags = ObservationService.buildObservationTags(
        detection: detection,
        observationId: observationId,
        latitude: latitude,
        longitude: longitude,
        geohash: geohash,
        locationName: locationName,
        audioUrl: audioUrl,
        audioHash: audioHash,
      );

      final event = await _nostrService.publishObservation(
        content: notes,
        tags: tags,
      );

      if (event != null) {
        emit(PublishState(status: PublishStatus.published, eventId: event.id));
      } else {
        emit(
          const PublishState(
            status: PublishStatus.error,
            error: 'Failed to publish — no relay accepted the event.',
          ),
        );
      }
    } catch (e) {
      emit(
        PublishState(status: PublishStatus.error, error: 'Publish failed: $e'),
      );
    }
  }

  void reset() {
    emit(const PublishState.idle());
  }
}
