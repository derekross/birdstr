import 'dart:async';

import 'package:birdnet_flutter/birdnet_flutter.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'recording_state.dart';

/// Manages audio recording state for bird sound capture.
///
/// Owns the [AudioCaptureService] and [RingBuffer]. Exposes the ring buffer
/// so the [IdentificationBloc] can read audio samples for inference.
class RecordingCubit extends Cubit<RecordingState> {
  RecordingCubit() : super(const RecordingState.idle());

  final RingBuffer _ringBuffer = RingBuffer();
  AudioCaptureService? _captureService;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<int>? _dataSub;

  /// The ring buffer containing captured audio samples.
  /// Read by the identification pipeline.
  RingBuffer get ringBuffer => _ringBuffer;

  /// Whether audio data is available for inference (at least 3s of audio).
  bool get hasEnoughAudio =>
      _ringBuffer.available >= AudioCaptureService.defaultSampleRate * 3;

  /// Start listening for bird sounds.
  Future<void> startListening() async {
    if (state.isListening) return;

    _captureService = AudioCaptureService(ringBuffer: _ringBuffer);
    await _captureService!.start();

    if (_captureService!.state == CaptureState.error) {
      emit(
        RecordingState(
          status: RecordingStatus.error,
          error: _captureService!.lastError ?? 'Failed to start audio capture',
        ),
      );
      return;
    }

    // Stream audio level for the UI meter.
    _levelSub = _captureService!.levelStream.listen((level) {
      if (state.isListening) {
        emit(state.copyWith(audioLevel: level));
      }
    });

    // Track when new audio data arrives.
    _dataSub = _captureService!.onDataAvailable.listen((_) {
      // Emit a state update so listeners know new audio is available.
      if (state.isListening && !state.hasNewAudio) {
        emit(state.copyWith(hasNewAudio: true));
      }
    });

    emit(const RecordingState.listening());
  }

  /// Stop listening.
  Future<void> stopListening() async {
    await _levelSub?.cancel();
    _levelSub = null;
    await _dataSub?.cancel();
    _dataSub = null;
    await _captureService?.dispose();
    _captureService = null;
    emit(const RecordingState.idle());
  }

  /// Mark that audio has been consumed by inference.
  void markAudioConsumed() {
    if (state.hasNewAudio) {
      emit(state.copyWith(hasNewAudio: false));
    }
  }

  @override
  Future<void> close() async {
    await stopListening();
    return super.close();
  }
}
