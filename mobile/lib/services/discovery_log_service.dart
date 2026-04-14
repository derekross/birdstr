import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:birdnet_flutter/birdnet_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/detection_with_audio.dart';

/// Persists every bird detection to a local JSON file, along with
/// the audio clip that produced the detection.
///
/// This is the user's personal discovery log — every bird BirdNET
/// identifies is recorded here, regardless of whether it's published
/// to Nostr. Survives app restarts.
class DiscoveryLogService {
  DiscoveryLogService._();
  static final instance = DiscoveryLogService._();

  List<DiscoveryEntry>? _entries;
  File? _file;
  Directory? _audioDir;

  /// All discoveries, sorted newest first.
  Future<List<DiscoveryEntry>> getAll() async {
    await _ensureLoaded();
    return List.unmodifiable(_entries!);
  }

  /// Unique species ever detected (life list).
  Future<List<String>> getLifeList() async {
    await _ensureLoaded();
    final species = <String>{};
    for (final e in _entries!) {
      species.add(e.scientificName);
    }
    final sorted = species.toList()..sort();
    return sorted;
  }

  /// Total number of discoveries.
  Future<int> get totalCount async {
    await _ensureLoaded();
    return _entries!.length;
  }

  /// Number of unique species.
  Future<int> get speciesCount async {
    final list = await getLifeList();
    return list.length;
  }

  /// Log a new detection with its audio clip.
  ///
  /// The audio samples are saved to a WAV file on disk.
  /// Deduplicates by species+time (won't log the same species
  /// twice within 30 seconds).
  Future<void> logDetection({
    required String commonName,
    required String scientificName,
    required double confidence,
    required DateTime detectedAt,
    Float32List? audioSamples,
    int sampleRate = 32000,
    double? latitude,
    double? longitude,
    bool publishedToNostr = false,
  }) async {
    await _ensureLoaded();

    // Deduplicate: skip if same species detected within 30 seconds.
    final isDuplicate = _entries!.any(
      (e) =>
          e.scientificName == scientificName &&
          detectedAt.difference(e.detectedAt).inSeconds.abs() < 30,
    );
    if (isDuplicate) return;

    // Save audio to disk if provided.
    String? audioPath;
    if (audioSamples != null && audioSamples.isNotEmpty) {
      audioPath = await _saveAudioClip(
        audioSamples,
        sampleRate,
        scientificName,
        detectedAt,
      );
    }

    final entry = DiscoveryEntry(
      commonName: commonName,
      scientificName: scientificName,
      confidence: confidence,
      detectedAt: detectedAt,
      latitude: latitude,
      longitude: longitude,
      publishedToNostr: publishedToNostr,
      audioPath: audioPath,
    );

    _entries!.insert(0, entry); // newest first
    await _save();

    debugPrint(
      '[DiscoveryLog] logged: $commonName ($scientificName) '
      '${(confidence * 100).toStringAsFixed(1)}%'
      '${audioPath != null ? ' [audio saved]' : ''}',
    );
  }

  /// Save a Float32 audio clip as a WAV file.
  Future<String?> _saveAudioClip(
    Float32List samples,
    int sampleRate,
    String scientificName,
    DateTime detectedAt,
  ) async {
    try {
      await _ensureAudioDir();
      final safeName = scientificName.toLowerCase().replaceAll(' ', '_');
      final ts = detectedAt.millisecondsSinceEpoch;
      final fileName = '${safeName}_$ts.wav';
      final file = File('${_audioDir!.path}/$fileName');

      // Write WAV.
      final numSamples = samples.length;
      const bitsPerSample = 16;
      final dataSize = numSamples * 2;
      final fileSize = 36 + dataSize;

      final buffer = ByteData(44 + dataSize);
      var offset = 0;

      // RIFF header
      for (final c in [0x52, 0x49, 0x46, 0x46]) {
        buffer.setUint8(offset++, c);
      }
      buffer.setUint32(offset, fileSize, Endian.little);
      offset += 4;
      for (final c in [0x57, 0x41, 0x56, 0x45]) {
        buffer.setUint8(offset++, c);
      }
      // fmt
      for (final c in [0x66, 0x6D, 0x74, 0x20]) {
        buffer.setUint8(offset++, c);
      }
      buffer.setUint32(offset, 16, Endian.little);
      offset += 4;
      buffer.setUint16(offset, 1, Endian.little);
      offset += 2;
      buffer.setUint16(offset, 1, Endian.little);
      offset += 2;
      buffer.setUint32(offset, sampleRate, Endian.little);
      offset += 4;
      buffer.setUint32(offset, sampleRate * 2, Endian.little);
      offset += 4;
      buffer.setUint16(offset, 2, Endian.little);
      offset += 2;
      buffer.setUint16(offset, bitsPerSample, Endian.little);
      offset += 2;
      // data
      for (final c in [0x64, 0x61, 0x74, 0x61]) {
        buffer.setUint8(offset++, c);
      }
      buffer.setUint32(offset, dataSize, Endian.little);
      offset += 4;
      for (var i = 0; i < numSamples; i++) {
        final pcm16 = (samples[i].clamp(-1.0, 1.0) * 32767).round();
        buffer.setInt16(offset, pcm16, Endian.little);
        offset += 2;
      }

      await file.writeAsBytes(buffer.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[DiscoveryLog] audio save error: $e');
      return null;
    }
  }

  /// Load audio samples from a saved WAV file.
  Future<Float32List?> loadAudioClip(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return null;

      // Skip the 44-byte WAV header, read PCM16 samples.
      final data = ByteData.sublistView(bytes);
      final numSamples = (bytes.length - 44) ~/ 2;
      final samples = Float32List(numSamples);

      for (var i = 0; i < numSamples; i++) {
        final pcm16 = data.getInt16(44 + i * 2, Endian.little);
        samples[i] = pcm16 / 32767.0;
      }

      return samples;
    } catch (e) {
      debugPrint('[DiscoveryLog] audio load error: $e');
      return null;
    }
  }

  /// Convert a DiscoveryEntry to a DetectionWithAudio by loading
  /// the saved audio clip from disk.
  Future<DetectionWithAudio?> toDetectionWithAudio(DiscoveryEntry entry) async {
    Float32List? audio;
    if (entry.audioPath != null) {
      audio = await loadAudioClip(entry.audioPath!);
    }

    return DetectionWithAudio(
      detection: Detection(
        species: Species(
          index: 0,
          id: 0,
          scientificName: entry.scientificName,
          commonName: entry.commonName,
          order: '',
          className: '',
        ),
        confidence: entry.confidence,
        timestamp: entry.detectedAt,
      ),
      audioSamples: audio ?? Float32List(0),
      sampleRate: 32000,
      capturedAt: entry.detectedAt,
    );
  }

  /// Mark a discovery as published to Nostr.
  Future<void> markPublished({
    required String scientificName,
    required DateTime detectedAt,
  }) async {
    await _ensureLoaded();
    for (var i = 0; i < _entries!.length; i++) {
      final e = _entries![i];
      if (e.scientificName == scientificName &&
          e.detectedAt.difference(detectedAt).inSeconds.abs() < 30) {
        _entries![i] = e.copyWith(publishedToNostr: true);
        await _save();
        return;
      }
    }
  }

  /// Get all discoveries for a specific species.
  Future<List<DiscoveryEntry>> getForSpecies(String scientificName) async {
    await _ensureLoaded();
    return _entries!.where((e) => e.scientificName == scientificName).toList();
  }

  /// Clear all discoveries (for testing/reset).
  Future<void> clearAll() async {
    _entries = [];
    await _save();
  }

  // -----------------------------------------------------------------------
  // Persistence
  // -----------------------------------------------------------------------

  Future<void> _ensureAudioDir() async {
    if (_audioDir != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _audioDir = Directory('${dir.path}/bird_audio');
    if (!_audioDir!.existsSync()) {
      await _audioDir!.create(recursive: true);
    }
  }

  Future<void> _ensureLoaded() async {
    if (_entries != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/discovery_log.json');

    if (await _file!.exists()) {
      try {
        final json = await _file!.readAsString();
        final list = jsonDecode(json) as List<dynamic>;
        _entries = list
            .map((e) => DiscoveryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint('[DiscoveryLog] loaded ${_entries!.length} entries');
      } catch (e) {
        debugPrint('[DiscoveryLog] error loading: $e');
        _entries = [];
      }
    } else {
      _entries = [];
    }
  }

  Future<void> _save() async {
    if (_file == null || _entries == null) return;
    final json = jsonEncode(_entries!.map((e) => e.toJson()).toList());
    await _file!.writeAsString(json, flush: true);
  }
}

/// A single bird discovery entry.
class DiscoveryEntry {
  const DiscoveryEntry({
    required this.commonName,
    required this.scientificName,
    required this.confidence,
    required this.detectedAt,
    this.latitude,
    this.longitude,
    this.publishedToNostr = false,
    this.audioPath,
  });

  final String commonName;
  final String scientificName;
  final double confidence;
  final DateTime detectedAt;
  final double? latitude;
  final double? longitude;
  final bool publishedToNostr;

  /// Path to the saved WAV audio clip on disk (null if no audio).
  final String? audioPath;

  bool get hasAudio => audioPath != null;

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  String get timeAgo {
    final diff = DateTime.now().difference(detectedAt);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  String get dateString {
    final d = detectedAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  DiscoveryEntry copyWith({bool? publishedToNostr}) => DiscoveryEntry(
    commonName: commonName,
    scientificName: scientificName,
    confidence: confidence,
    detectedAt: detectedAt,
    latitude: latitude,
    longitude: longitude,
    publishedToNostr: publishedToNostr ?? this.publishedToNostr,
    audioPath: audioPath,
  );

  Map<String, dynamic> toJson() => {
    'commonName': commonName,
    'scientificName': scientificName,
    'confidence': confidence,
    'detectedAt': detectedAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'publishedToNostr': publishedToNostr,
    'audioPath': audioPath,
  };

  factory DiscoveryEntry.fromJson(Map<String, dynamic> json) => DiscoveryEntry(
    commonName: json['commonName'] as String,
    scientificName: json['scientificName'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    detectedAt: DateTime.parse(json['detectedAt'] as String),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    publishedToNostr: json['publishedToNostr'] as bool? ?? false,
    audioPath: json['audioPath'] as String?,
  );
}
