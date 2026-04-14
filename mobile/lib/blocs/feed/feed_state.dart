part of 'feed_cubit.dart';

enum FeedStatus { initial, loading, loaded, error }

class FeedState extends Equatable {
  const FeedState({
    required this.status,
    this.observations = const [],
    this.error,
  });

  const FeedState.initial()
    : status = FeedStatus.initial,
      observations = const [],
      error = null;

  final FeedStatus status;
  final List<Observation> observations;
  final String? error;

  bool get isLoading => status == FeedStatus.loading;
  bool get isLoaded => status == FeedStatus.loaded;

  @override
  List<Object?> get props => [status, observations, error];
}
