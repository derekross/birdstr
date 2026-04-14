part of 'identification_bloc.dart';

enum IdentificationStatus { initial, loading, ready, identifying }

class IdentificationState extends Equatable {
  const IdentificationState({
    required this.status,
    this.sessionList = const [],
    this.latestDetections = const [],
    this.error,
  });

  const IdentificationState.initial()
    : status = IdentificationStatus.initial,
      sessionList = const [],
      latestDetections = const [],
      error = null;

  const IdentificationState.loading()
    : status = IdentificationStatus.loading,
      sessionList = const [],
      latestDetections = const [],
      error = null;

  const IdentificationState.ready()
    : status = IdentificationStatus.ready,
      sessionList = const [],
      latestDetections = const [],
      error = null;

  final IdentificationStatus status;

  /// Accumulated session list — deduplicated by species, best confidence kept.
  /// Persists across inference cycles and even after stopping recording.
  final List<DetectionWithAudio> sessionList;

  /// Latest detections from the most recent inference cycle.
  /// Used to show "just heard" indicators.
  final List<DetectionWithAudio> latestDetections;

  final String? error;

  bool get isReady =>
      status == IdentificationStatus.ready ||
      status == IdentificationStatus.identifying;
  bool get isIdentifying => status == IdentificationStatus.identifying;
  bool get hasResults => sessionList.isNotEmpty;

  /// Number of unique species in the session.
  int get speciesCount => sessionList.length;

  IdentificationState copyWith({
    IdentificationStatus? status,
    List<DetectionWithAudio>? sessionList,
    List<DetectionWithAudio>? latestDetections,
    String? error,
  }) {
    return IdentificationState(
      status: status ?? this.status,
      sessionList: sessionList ?? this.sessionList,
      latestDetections: latestDetections ?? this.latestDetections,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, sessionList, latestDetections, error];
}
