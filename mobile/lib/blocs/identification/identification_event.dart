part of 'identification_bloc.dart';

sealed class IdentificationEvent extends Equatable {
  const IdentificationEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the BirdNET model.
class InitializeModel extends IdentificationEvent {
  const InitializeModel();
}

/// Start running inference on audio from the ring buffer.
class StartIdentifying extends IdentificationEvent {
  const StartIdentifying({required this.ringBuffer});
  final RingBuffer ringBuffer;

  @override
  List<Object?> get props => [ringBuffer];
}

/// Stop running inference (keeps session list).
class StopIdentifying extends IdentificationEvent {
  const StopIdentifying();
}

/// Clear the session list (user-initiated).
class ClearSession extends IdentificationEvent {
  const ClearSession();
}

/// Internal event for inference results (not public API).
class _InferenceResult extends IdentificationEvent {
  const _InferenceResult(this.detections);
  final List<DetectionWithAudio> detections;

  @override
  List<Object?> get props => [detections];
}
