import 'dart:typed_data';

import 'package:birdnet_flutter/birdnet_flutter.dart';

/// A bird detection paired with the audio clip that produced it.
///
/// When BirdNET identifies a species, we snapshot the audio window
/// so the user can review, trim, and publish the recording.
class DetectionWithAudio {
  const DetectionWithAudio({
    required this.detection,
    required this.audioSamples,
    required this.sampleRate,
    required this.capturedAt,
  });

  /// The BirdNET detection result.
  final Detection detection;

  /// Raw mono Float32 audio samples from the inference window.
  /// Typically 3 seconds × sampleRate samples.
  final Float32List audioSamples;

  /// Sample rate of the audio (typically 32000 Hz).
  final int sampleRate;

  /// When this audio was captured.
  final DateTime capturedAt;

  /// Duration of the audio clip.
  Duration get duration =>
      Duration(milliseconds: (audioSamples.length / sampleRate * 1000).round());

  /// Extract a trimmed portion of the audio.
  Float32List trimAudio(int startSample, int endSample) {
    final start = startSample.clamp(0, audioSamples.length);
    final end = endSample.clamp(start, audioSamples.length);
    return audioSamples.sublist(start, end);
  }

  /// Shorthand accessors from the inner detection.
  Species get species => detection.species;
  double get confidence => detection.confidence;
  String get confidencePercent => detection.confidencePercent;
}
