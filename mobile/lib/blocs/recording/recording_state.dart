part of 'recording_cubit.dart';

enum RecordingStatus { idle, listening, error }

class RecordingState extends Equatable {
  const RecordingState({
    required this.status,
    this.audioLevel = 0.0,
    this.hasNewAudio = false,
    this.error,
  });

  const RecordingState.idle()
    : status = RecordingStatus.idle,
      audioLevel = 0.0,
      hasNewAudio = false,
      error = null;

  const RecordingState.listening()
    : status = RecordingStatus.listening,
      audioLevel = 0.0,
      hasNewAudio = false,
      error = null;

  final RecordingStatus status;

  /// Current audio level (0.0 - 1.0) for the level meter.
  final double audioLevel;

  /// Whether new audio data has arrived since last inference.
  final bool hasNewAudio;

  final String? error;

  bool get isListening => status == RecordingStatus.listening;

  RecordingState copyWith({
    RecordingStatus? status,
    double? audioLevel,
    bool? hasNewAudio,
    String? error,
  }) {
    return RecordingState(
      status: status ?? this.status,
      audioLevel: audioLevel ?? this.audioLevel,
      hasNewAudio: hasNewAudio ?? this.hasNewAudio,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, audioLevel, hasNewAudio, error];
}
