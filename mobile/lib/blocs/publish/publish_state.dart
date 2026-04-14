part of 'publish_cubit.dart';

enum PublishStatus { idle, publishing, published, error }

class PublishState extends Equatable {
  const PublishState({required this.status, this.eventId, this.error});

  const PublishState.idle()
    : status = PublishStatus.idle,
      eventId = null,
      error = null;

  final PublishStatus status;
  final String? eventId;
  final String? error;

  bool get isPublishing => status == PublishStatus.publishing;
  bool get isPublished => status == PublishStatus.published;

  @override
  List<Object?> get props => [status, eventId, error];
}
