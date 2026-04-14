import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:birdnet_flutter/birdnet_flutter.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/detection_with_audio.dart';
import '../../services/discovery_log_service.dart';
import '../../services/location_service.dart';

part 'identification_event.dart';
part 'identification_state.dart';

/// Manages BirdNET inference state.
///
/// Accumulates detections into a persistent session list that survives
/// across inference cycles. Deduplicates by species, keeping the highest
/// confidence detection for each.
class IdentificationBloc
    extends Bloc<IdentificationEvent, IdentificationState> {
  IdentificationBloc() : super(const IdentificationState.initial()) {
    on<InitializeModel>(_onInitializeModel);
    on<StartIdentifying>(_onStartIdentifying);
    on<StopIdentifying>(_onStopIdentifying);
    on<_InferenceResult>(_onInferenceResult);
    on<ClearSession>(_onClearSession);
  }

  final InferenceIsolate _isolate = InferenceIsolate();
  ModelConfig? _modelConfig;
  Timer? _inferenceTimer;
  RingBuffer? _ringBuffer;

  /// The sample rate from the loaded model config.
  int get sampleRate => _modelConfig?.audio.sampleRate ?? 32000;

  Future<void> _onInitializeModel(
    InitializeModel event,
    Emitter<IdentificationState> emit,
  ) async {
    emit(const IdentificationState.loading());

    try {
      final configJson = await rootBundle.loadString(
        'assets/models/model_config.json',
      );
      final configMap = json.decode(configJson) as Map<String, dynamic>;
      final audioModelConfig = configMap['audioModel'] as Map<String, dynamic>;
      _modelConfig = ModelConfig.fromJson(audioModelConfig);

      final labelsCsv = await rootBundle.loadString(
        'assets/models/${_modelConfig!.labels.file}',
      );

      final modelFilePath = await _ensureModelFile(
        _modelConfig!.onnx.modelFile,
      );

      await _isolate.start(
        modelFilePath: modelFilePath,
        labelsCsv: labelsCsv,
        config: _modelConfig!,
      );

      debugPrint('[IdentificationBloc] model loaded, isolate ready');
      emit(const IdentificationState.ready());
    } catch (e, st) {
      debugPrint('[IdentificationBloc] init error: $e\n$st');
      emit(
        IdentificationState(
          status: IdentificationStatus.initial,
          error: 'Failed to load model: $e',
        ),
      );
    }
  }

  Future<String> _ensureModelFile(String assetFileName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${docsDir.path}/models');
    if (!modelDir.existsSync()) {
      await modelDir.create(recursive: true);
    }

    final targetFile = File('${modelDir.path}/$assetFileName');

    if (!targetFile.existsSync()) {
      debugPrint('[IdentificationBloc] copying model to ${targetFile.path}');
      final data = await rootBundle.load('assets/models/$assetFileName');
      await targetFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      debugPrint(
        '[IdentificationBloc] model copied (${targetFile.lengthSync()} bytes)',
      );
    } else {
      debugPrint('[IdentificationBloc] model already at ${targetFile.path}');
    }

    return targetFile.path;
  }

  Future<void> _onStartIdentifying(
    StartIdentifying event,
    Emitter<IdentificationState> emit,
  ) async {
    if (!_isolate.isRunning) {
      debugPrint('[IdentificationBloc] isolate not running, cannot identify');
      return;
    }

    _ringBuffer = event.ringBuffer;
    // Keep the existing session list when starting a new recording.
    emit(state.copyWith(status: IdentificationStatus.identifying));

    _inferenceTimer?.cancel();
    _inferenceTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _runInference(),
    );

    _runInference();
  }

  Future<void> _onStopIdentifying(
    StopIdentifying event,
    Emitter<IdentificationState> emit,
  ) async {
    _inferenceTimer?.cancel();
    _inferenceTimer = null;
    _ringBuffer = null;
    _isolate.resetPooling();
    // Keep the session list! Only change status.
    emit(
      state.copyWith(
        status: IdentificationStatus.ready,
        latestDetections: const [],
      ),
    );
  }

  Future<void> _onInferenceResult(
    _InferenceResult event,
    Emitter<IdentificationState> emit,
  ) async {
    debugPrint(
      '[IdentificationBloc] inference result: '
      '${event.detections.length} detections',
    );

    // Merge new detections into the session list.
    // Deduplicate by species — keep the highest confidence for each.
    final sessionMap = <String, DetectionWithAudio>{};

    // Start with existing session entries.
    for (final dwa in state.sessionList) {
      sessionMap[dwa.species.scientificName] = dwa;
    }

    // Merge new detections — replace if higher confidence.
    for (final dwa in event.detections) {
      final key = dwa.species.scientificName;
      final existing = sessionMap[key];
      if (existing == null || dwa.confidence > existing.confidence) {
        sessionMap[key] = dwa;
      }
    }

    // Auto-log each new detection to the local discovery log (with audio).
    for (final dwa in event.detections) {
      try {
        await DiscoveryLogService.instance.logDetection(
          commonName: dwa.species.commonName,
          scientificName: dwa.species.scientificName,
          confidence: dwa.confidence,
          detectedAt: dwa.capturedAt,
          audioSamples: dwa.audioSamples,
          sampleRate: dwa.sampleRate,
          latitude: LocationService.instance.lastPosition?.latitude,
          longitude: LocationService.instance.lastPosition?.longitude,
        );
      } catch (e) {
        debugPrint('[IdentificationBloc] discovery log error: $e');
      }
    }

    // Sort by most recently detected (new detections first), then by confidence.
    final newSpecies = event.detections
        .map((d) => d.species.scientificName)
        .toSet();
    final sorted = sessionMap.values.toList()
      ..sort((a, b) {
        final aIsNew = newSpecies.contains(a.species.scientificName);
        final bIsNew = newSpecies.contains(b.species.scientificName);
        if (aIsNew != bIsNew) return aIsNew ? -1 : 1;
        return b.confidence.compareTo(a.confidence);
      });

    emit(
      state.copyWith(
        status: IdentificationStatus.identifying,
        sessionList: sorted,
        latestDetections: event.detections,
      ),
    );
  }

  /// Clear the session list (user-initiated).
  void _onClearSession(ClearSession event, Emitter<IdentificationState> emit) {
    _isolate.resetPooling();
    emit(state.copyWith(sessionList: const [], latestDetections: const []));
  }

  Future<void> _runInference() async {
    final buffer = _ringBuffer;
    if (buffer == null || !_isolate.isRunning) return;

    final windowSamples = sampleRate * 3;
    if (buffer.available < windowSamples) {
      debugPrint(
        '[IdentificationBloc] not enough audio: '
        '${buffer.available}/$windowSamples samples',
      );
      return;
    }

    try {
      final samples = buffer.readLast(windowSamples);
      final detections = await _isolate.infer(samples);

      if (!isClosed && detections.isNotEmpty) {
        final now = DateTime.now();
        final audioCopy = Float32List.fromList(samples);
        final withAudio = detections
            .map(
              (d) => DetectionWithAudio(
                detection: d,
                audioSamples: audioCopy,
                sampleRate: sampleRate,
                capturedAt: now,
              ),
            )
            .toList();
        add(_InferenceResult(withAudio));
      }
    } catch (e) {
      debugPrint('[IdentificationBloc] inference error: $e');
    }
  }

  @override
  Future<void> close() async {
    _inferenceTimer?.cancel();
    await _isolate.stop();
    return super.close();
  }
}
