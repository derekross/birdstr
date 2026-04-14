import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Encodes raw Float32 audio samples to WAV format.
///
/// WAV is used because it requires no native encoding libraries.
/// A 3-second clip at 32kHz PCM16 is ~192KB — reasonable for Blossom upload.
class AudioEncoderService {
  AudioEncoderService._();
  static final instance = AudioEncoderService._();

  static const _uuid = Uuid();

  /// Encode Float32 audio samples to a WAV file.
  ///
  /// Returns the path to the encoded `.wav` file, or null on failure.
  Future<String?> encodeToWav({
    required Float32List samples,
    required int sampleRate,
    int channels = 1,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final id = _uuid.v4().substring(0, 8);
    final wavPath = '${tempDir.path}/bird_clip_$id.wav';

    try {
      await _writeWav(
        path: wavPath,
        samples: samples,
        sampleRate: sampleRate,
        channels: channels,
      );
      final size = File(wavPath).lengthSync();
      debugPrint('[AudioEncoder] WAV written: $wavPath ($size bytes)');
      return wavPath;
    } catch (e) {
      debugPrint('[AudioEncoder] error: $e');
      return null;
    }
  }

  /// Write a WAV file from Float32 mono/stereo samples.
  ///
  /// Converts Float32 [-1.0, 1.0] → PCM16 for maximum compatibility.
  Future<void> _writeWav({
    required String path,
    required Float32List samples,
    required int sampleRate,
    int channels = 1,
  }) async {
    final numSamples = samples.length;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = numSamples * (bitsPerSample ~/ 8);
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    var offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // R
    buffer.setUint8(offset++, 0x49); // I
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // W
    buffer.setUint8(offset++, 0x41); // A
    buffer.setUint8(offset++, 0x56); // V
    buffer.setUint8(offset++, 0x45); // E

    // fmt sub-chunk
    buffer.setUint8(offset++, 0x66); // f
    buffer.setUint8(offset++, 0x6D); // m
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x20); // (space)
    buffer.setUint32(offset, 16, Endian.little); // sub-chunk size
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little); // PCM format
    offset += 2;
    buffer.setUint16(offset, channels, Endian.little);
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    buffer.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little);
    offset += 2;

    // data sub-chunk
    buffer.setUint8(offset++, 0x64); // d
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    // PCM16 sample data: convert Float32 [-1.0, 1.0] → Int16
    for (var i = 0; i < numSamples; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final pcm16 = (clamped * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(offset, pcm16, Endian.little);
      offset += 2;
    }

    await File(path).writeAsBytes(buffer.buffer.asUint8List(), flush: true);
  }

  /// Cleanup a temp encoded file.
  Future<void> cleanup(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
