import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'waveform_painter.dart';

/// Audio trimmer widget with waveform visualization and trim handles.
///
/// Allows the user to select a sub-region of the audio clip by dragging
/// start/end handles on the waveform.
class AudioTrimmer extends StatefulWidget {
  const AudioTrimmer({
    super.key,
    required this.audioSamples,
    required this.sampleRate,
    this.onTrimChanged,
  });

  final Float32List audioSamples;
  final int sampleRate;

  /// Called when trim handles are moved.
  /// Reports (startSample, endSample) indices.
  final void Function(int startSample, int endSample)? onTrimChanged;

  @override
  State<AudioTrimmer> createState() => _AudioTrimmerState();
}

class _AudioTrimmerState extends State<AudioTrimmer> {
  double _trimStart = 0.0; // fraction [0.0, 1.0]
  double _trimEnd = 1.0;
  bool _isPlaying = false;
  double _playbackFraction = 0.0; // 0.0–1.0 within the full waveform
  final AudioPlayer _player = AudioPlayer();
  String? _tempWavPath;
  Duration _clipDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        final completed = state.processingState == ProcessingState.completed;
        setState(() {
          _isPlaying = state.playing && !completed;
          if (completed) _playbackFraction = 0.0;
        });
        if (completed) {
          _player.pause();
          _player.seek(Duration.zero);
        }
      }
    });
    _player.positionStream.listen((pos) {
      if (mounted && _isPlaying && _clipDuration.inMilliseconds > 0) {
        // Map playback position within the trimmed clip back to
        // a fraction of the full waveform.
        final clipFraction = pos.inMilliseconds / _clipDuration.inMilliseconds;
        final waveformFraction =
            _trimStart + clipFraction * (_trimEnd - _trimStart);
        setState(() => _playbackFraction = waveformFraction.clamp(0.0, 1.0));
      }
    });
    _player.durationStream.listen((dur) {
      if (dur != null) _clipDuration = dur;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _cleanupTemp();
    super.dispose();
  }

  void _cleanupTemp() {
    if (_tempWavPath != null) {
      File(_tempWavPath!).delete().catchError((_) => File(_tempWavPath!));
    }
  }

  int get _startSample => (_trimStart * widget.audioSamples.length).round();
  int get _endSample => (_trimEnd * widget.audioSamples.length).round();

  Duration get _trimmedDuration => Duration(
    milliseconds: ((_endSample - _startSample) / widget.sampleRate * 1000)
        .round(),
  );

  Duration get _totalDuration => Duration(
    milliseconds: (widget.audioSamples.length / widget.sampleRate * 1000)
        .round(),
  );

  String _formatDuration(Duration d) {
    final s = d.inMilliseconds / 1000;
    return '${s.toStringAsFixed(1)}s';
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    // Write trimmed WAV to temp file for playback.
    final trimmed = widget.audioSamples.sublist(_startSample, _endSample);
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/trim_preview.wav';

    await _writeWavForPlayback(path, trimmed, widget.sampleRate);
    _tempWavPath = path;

    await _player.setFilePath(path);
    await _player.play();
  }

  /// Write a minimal WAV for playback preview.
  Future<void> _writeWavForPlayback(
    String path,
    Float32List samples,
    int sampleRate,
  ) async {
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
    buffer.setUint32(offset, sampleRate * (bitsPerSample ~/ 8), Endian.little);
    offset += 4;
    buffer.setUint16(offset, bitsPerSample ~/ 8, Endian.little);
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

    await File(path).writeAsBytes(buffer.buffer.asUint8List(), flush: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Audio Clip (${_formatDuration(_totalDuration)})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Selected: ${_formatDuration(_trimmedDuration)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Waveform with trim handles
        SizedBox(
          height: 80,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                onHorizontalDragUpdate: (details) {
                  // Drag to adjust nearest handle.
                  final fraction = (details.localPosition.dx / width).clamp(
                    0.0,
                    1.0,
                  );
                  final distToStart = (fraction - _trimStart).abs();
                  final distToEnd = (fraction - _trimEnd).abs();

                  setState(() {
                    if (distToStart < distToEnd) {
                      _trimStart = fraction.clamp(0.0, _trimEnd - 0.05);
                    } else {
                      _trimEnd = fraction.clamp(_trimStart + 0.05, 1.0);
                    }
                  });
                  widget.onTrimChanged?.call(_startSample, _endSample);
                },
                child: CustomPaint(
                  size: Size(width, 80),
                  painter: WaveformPainter(
                    samples: widget.audioSamples,
                    trimStart: _trimStart,
                    trimEnd: _trimEnd,
                    playheadPosition: _isPlaying ? _playbackFraction : null,
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(40),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),

        // Trim position labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(
                Duration(
                  milliseconds: (_trimStart * _totalDuration.inMilliseconds)
                      .round(),
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _formatDuration(
                Duration(
                  milliseconds: (_trimEnd * _totalDuration.inMilliseconds)
                      .round(),
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Play button
        Center(
          child: IconButton.filled(
            onPressed: _togglePlayback,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            tooltip: _isPlaying ? 'Pause preview' : 'Play trimmed clip',
          ),
        ),
      ],
    );
  }
}
