import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// CustomPainter that renders a waveform from Float32 audio samples.
///
/// Auto-normalizes the waveform to fill the available height, even
/// for quiet recordings. Shows trim handles, and a moving playhead
/// during audio playback.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.samples,
    required this.trimStart,
    required this.trimEnd,
    required this.activeColor,
    required this.inactiveColor,
    this.playheadPosition,
  });

  final Float32List samples;

  /// Trim range as fractions [0.0, 1.0].
  final double trimStart;
  final double trimEnd;

  /// Current playback position as a fraction [0.0, 1.0] of the full waveform.
  /// Null when not playing.
  final double? playheadPosition;

  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final midY = height / 2;

    // Downsample to one bar per 2 pixels for a cleaner look.
    final barsCount = (width / 2).floor();
    if (barsCount <= 0) return;

    final samplesPerBar = samples.length / barsCount;
    final barWidth = width / barsCount;

    // First pass: find the peak amplitude for normalization.
    var globalPeak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final abs = samples[i].abs();
      if (abs > globalPeak) globalPeak = abs;
    }
    final normFactor = globalPeak > 0.001 ? 0.9 / globalPeak : 1.0;

    // Draw bars.
    for (var i = 0; i < barsCount; i++) {
      final startSample = (i * samplesPerBar).round();
      final endSample = ((i + 1) * samplesPerBar).round().clamp(
        0,
        samples.length,
      );

      var peak = 0.0;
      for (var s = startSample; s < endSample; s++) {
        final abs = samples[s].abs();
        if (abs > peak) peak = abs;
      }

      final fraction = i / barsCount;
      final isActive = fraction >= trimStart && fraction <= trimEnd;

      // If playhead is active, bars before the playhead get a brighter color.
      final isPlayed =
          playheadPosition != null && fraction <= playheadPosition!;

      Color barColor;
      if (!isActive) {
        barColor = inactiveColor;
      } else if (isPlayed) {
        barColor = activeColor;
      } else {
        barColor = activeColor.withAlpha(100);
      }

      final normalized = peak * normFactor;
      final barHeight = math.max(normalized * height, 2.0);

      final paint = Paint()
        ..color = barColor
        ..strokeWidth = math.max(barWidth - 1.5, 1)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(i * barWidth + barWidth / 2, midY - barHeight / 2),
        Offset(i * barWidth + barWidth / 2, midY + barHeight / 2),
        paint,
      );
    }

    // Draw trim handle lines.
    final handlePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final startX = trimStart * width;
    final endX = trimEnd * width;
    canvas.drawLine(Offset(startX, 0), Offset(startX, height), handlePaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, height), handlePaint);

    // Small handle indicators at top/bottom.
    final handleKnob = Paint()..color = activeColor;
    canvas.drawCircle(Offset(startX, 4), 4, handleKnob);
    canvas.drawCircle(Offset(startX, height - 4), 4, handleKnob);
    canvas.drawCircle(Offset(endX, 4), 4, handleKnob);
    canvas.drawCircle(Offset(endX, height - 4), 4, handleKnob);

    // Draw playhead line.
    if (playheadPosition != null) {
      final playX = playheadPosition! * width;
      final playheadPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(playX, 0), Offset(playX, height), playheadPaint);
      // Playhead dot.
      canvas.drawCircle(Offset(playX, midY), 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.trimStart != trimStart ||
      oldDelegate.trimEnd != trimEnd ||
      oldDelegate.playheadPosition != playheadPosition ||
      !identical(oldDelegate.samples, samples);
}
