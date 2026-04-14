import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/identification/identification_bloc.dart';
import '../../blocs/recording/recording_cubit.dart';
import '../../models/detection_with_audio.dart';

/// Main screen — tap to start listening for bird sounds.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final idBloc = context.read<IdentificationBloc>();
    if (idBloc.state.status == IdentificationStatus.initial) {
      idBloc.add(const InitializeModel());
    }
  }

  void _toggleListening() {
    final recordingCubit = context.read<RecordingCubit>();
    final idBloc = context.read<IdentificationBloc>();

    if (recordingCubit.state.isListening) {
      idBloc.add(const StopIdentifying());
      recordingCubit.stopListening();
    } else {
      recordingCubit.startListening().then((_) {
        if (recordingCubit.state.isListening) {
          idBloc.add(StartIdentifying(ringBuffer: recordingCubit.ringBuffer));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Birds')),
      body: Column(
        children: [
          // Model loading status
          BlocBuilder<IdentificationBloc, IdentificationState>(
            buildWhen: (prev, curr) =>
                prev.status != curr.status || prev.error != curr.error,
            builder: (context, state) {
              if (state.status == IdentificationStatus.loading) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Loading BirdNET model...'),
                    ],
                  ),
                );
              }
              if (state.error != null) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Main content
          Expanded(
            child: BlocBuilder<RecordingCubit, RecordingState>(
              builder: (context, recordingState) {
                return Column(
                  children: [
                    // Audio level indicator
                    if (recordingState.isListening)
                      _AudioLevelBar(level: recordingState.audioLevel),

                    // Listen button
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child:
                          BlocBuilder<IdentificationBloc, IdentificationState>(
                            builder: (context, idState) {
                              return _ListenButton(
                                isListening: recordingState.isListening,
                                isModelReady: idState.isReady,
                                audioLevel: recordingState.audioLevel,
                                hasNewDetection:
                                    idState.latestDetections.isNotEmpty,
                                speciesCount: idState.sessionList.length,
                                onPressed: idState.isReady
                                    ? _toggleListening
                                    : null,
                              );
                            },
                          ),
                    ),

                    // Session header with count + actions
                    BlocBuilder<IdentificationBloc, IdentificationState>(
                      buildWhen: (prev, curr) =>
                          prev.sessionList.length != curr.sessionList.length,
                      builder: (context, idState) {
                        if (idState.sessionList.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                '${idState.speciesCount} species found',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => context
                                    .read<IdentificationBloc>()
                                    .add(const ClearSession()),
                                icon: const Icon(Icons.clear_all, size: 18),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Session list
                    Expanded(
                      child:
                          BlocBuilder<IdentificationBloc, IdentificationState>(
                            builder: (context, idState) {
                              if (idState.sessionList.isEmpty) {
                                return Center(
                                  child: Text(
                                    recordingState.isListening
                                        ? 'Listening for birds...'
                                        : 'Tap the button to start listening',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withAlpha(150),
                                        ),
                                  ),
                                );
                              }

                              // Build set of "just heard" species for NEW badge.
                              final latestSpecies = idState.latestDetections
                                  .map((d) => d.species.scientificName)
                                  .toSet();

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: idState.sessionList.length,
                                itemBuilder: (context, index) {
                                  final dwa = idState.sessionList[index];
                                  final isNew = latestSpecies.contains(
                                    dwa.species.scientificName,
                                  );
                                  return _DetectionCard(
                                    detectionWithAudio: dwa,
                                    isNew: isNew,
                                  );
                                },
                              );
                            },
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioLevelBar extends StatelessWidget {
  const _AudioLevelBar({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    // Scale up the RMS level for visibility — raw RMS is typically 0.01-0.15
    // for normal ambient/bird sounds. Multiply by 5 and clamp.
    final scaled = (level * 5.0).clamp(0.0, 1.0);
    final color = Color.lerp(
      Theme.of(context).colorScheme.primary.withAlpha(100),
      Theme.of(context).colorScheme.primary,
      scaled,
    )!;

    return Container(
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: scaled,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ListenButton extends StatefulWidget {
  const _ListenButton({
    required this.isListening,
    required this.isModelReady,
    this.audioLevel = 0.0,
    this.hasNewDetection = false,
    this.speciesCount = 0,
    this.onPressed,
  });

  final bool isListening;
  final bool isModelReady;
  final double audioLevel;
  final bool hasNewDetection;
  final int speciesCount;
  final VoidCallback? onPressed;

  @override
  State<_ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<_ListenButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _detectionController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _detectionAnimation;

  bool _lastHasDetection = false;

  @override
  void initState() {
    super.initState();

    // Continuous pulse while listening.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Detection burst — triggers once per new detection.
    _detectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _detectionAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _detectionController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_ListenButton old) {
    super.didUpdateWidget(old);

    // Start/stop pulse.
    if (widget.isListening && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isListening && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }

    // Trigger detection burst when new birds found.
    if (widget.hasNewDetection && !_lastHasDetection) {
      _detectionController.forward(from: 0.0);
    }
    _lastHasDetection = widget.hasNewDetection;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _detectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = widget.isListening ? 88.0 : 72.0;
    // Scale up slightly with audio level.
    final levelBoost = widget.isListening ? widget.audioLevel * 80.0 : 0.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _detectionAnimation]),
      builder: (context, child) {
        final pulseValue = _pulseAnimation.value;
        final detectionValue = _detectionAnimation.value;

        // Detection burst ring expands outward and fades.
        final burstRadius = baseSize / 2 + 30 * detectionValue;
        final burstOpacity = (1.0 - detectionValue) * 0.6;

        // Pulse ring breathes gently.
        final pulseRadius =
            baseSize / 2 + 8 + (levelBoost * 0.5) + 6 * pulseValue;
        final pulseOpacity = widget.isListening ? 0.15 + 0.1 * pulseValue : 0.0;

        return GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: baseSize + 80,
            height: baseSize + 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Detection burst ring (green, expands on detection).
                if (detectionValue > 0.01)
                  Container(
                    width: burstRadius * 2,
                    height: burstRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.green.withAlpha(
                          (burstOpacity * 255).round(),
                        ),
                        width: 3,
                      ),
                    ),
                  ),

                // Pulse ring (breathes while listening).
                if (widget.isListening)
                  Container(
                    width: pulseRadius * 2,
                    height: pulseRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.error.withAlpha(
                        (pulseOpacity * 255).round(),
                      ),
                    ),
                  ),

                // Audio level ring.
                if (widget.isListening && levelBoost > 1)
                  Container(
                    width: baseSize + levelBoost * 0.6,
                    height: baseSize + levelBoost * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.error.withAlpha(30),
                    ),
                  ),

                // Main button.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: baseSize,
                  height: baseSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isListening
                        ? Theme.of(context).colorScheme.error
                        : widget.isModelReady
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    boxShadow: [
                      if (widget.isListening)
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withAlpha(80),
                          blurRadius: 16 + levelBoost * 0.3,
                          spreadRadius: 2 + levelBoost * 0.1,
                        ),
                    ],
                  ),
                  child: Icon(
                    widget.isListening ? Icons.stop : Icons.mic,
                    size: 32,
                    color: widget.isListening || widget.isModelReady
                        ? Colors.white
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.detectionWithAudio, this.isNew = false});

  final DetectionWithAudio detectionWithAudio;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final confidence = detectionWithAudio.confidence;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
        ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => context.push('/bird-detail', extra: detectionWithAudio),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(Icons.music_note, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                detectionWithAudio.species.commonName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isNew)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'NOW',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          detectionWithAudio.species.scientificName,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            detectionWithAudio.confidencePercent,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
