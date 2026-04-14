import 'dart:io';

import 'package:blossom_upload_service/blossom_upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/publish/publish_cubit.dart';
import '../../models/detection_with_audio.dart';
import '../../services/audio_encoder_service.dart';
import '../../services/blossom_auth_provider_impl.dart';
import '../../services/blossom_server_service.dart';
import '../../services/location_service.dart';
import '../../widgets/audio_trimmer/audio_trimmer.dart';

/// Screen to review a detection and publish it to Nostr.
class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key, required this.detectionWithAudio});

  final DetectionWithAudio detectionWithAudio;

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _notesController = TextEditingController();
  late final PublishCubit _publishCubit;

  // Trim range (sample indices).
  late int _trimStart;
  late int _trimEnd;

  @override
  void initState() {
    super.initState();
    _publishCubit = PublishCubit();
    _trimStart = 0;
    _trimEnd = widget.detectionWithAudio.audioSamples.length;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _publishCubit.close();
    super.dispose();
  }

  Future<void> _publish() async {
    final dwa = widget.detectionWithAudio;

    // Get GPS location.
    final locationService = LocationService.instance;
    final position = await locationService.getCurrentPosition();
    if (!mounted) return;

    // Trim audio.
    final trimmedAudio = dwa.trimAudio(_trimStart, _trimEnd);

    // Encode to WAV.
    final encoder = AudioEncoderService.instance;
    final wavPath = await encoder.encodeToWav(
      samples: trimmedAudio,
      sampleRate: dwa.sampleRate,
    );

    if (!mounted) return;

    // Upload to Blossom servers (try each until one succeeds).
    String? audioUrl;
    String? audioHash;
    if (wavPath != null) {
      final file = File(wavPath);
      final hashResult = await HashUtil.sha256File(file);
      audioHash = hashResult.hash;
      debugPrint(
        '[PublishScreen] uploading audio: hash=$audioHash '
        'size=${hashResult.size} bytes',
      );

      final servers = BlossomServerService.instance.servers;
      for (final server in servers) {
        try {
          final uploader = BlossomUploadService(
            authProvider: BlossomAuthProviderImpl(),
            defaultServerUrl: server,
          );
          final result = await uploader.uploadAudio(
            audioFile: file,
            mimeType: 'audio/wav',
          );
          debugPrint(
            '[PublishScreen] upload to $server: success=${result.success} '
            'url=${result.url} cdnUrl=${result.cdnUrl}',
          );
          if (result.success && result.cdnUrl != null) {
            audioUrl = result.cdnUrl;
            break;
          }
        } catch (e) {
          debugPrint('[PublishScreen] upload to $server failed: $e');
          // Try next server.
        }
      }

      await encoder.cleanup(wavPath);
    }

    if (!mounted) return;

    _publishCubit.publishObservation(
      detection: dwa.detection,
      latitude: position?.latitude ?? 0.0,
      longitude: position?.longitude ?? 0.0,
      geohash: position != null ? locationService.lastGeohash : '000000',
      notes: _notesController.text,
      audioUrl: audioUrl,
      audioHash: audioHash,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dwa = widget.detectionWithAudio;

    return BlocProvider.value(
      value: _publishCubit,
      child: Scaffold(
        appBar: AppBar(title: const Text('Publish Observation')),
        body: BlocConsumer<PublishCubit, PublishState>(
          listener: (context, state) {
            if (state.isPublished) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Observation published to Nostr!'),
                  backgroundColor: Colors.green,
                ),
              );
              context.pop();
            }
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          builder: (context, publishState) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Detection summary card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dwa.species.commonName,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                dwa.species.scientificName,
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withAlpha(150),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(20),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            dwa.confidencePercent,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Audio trimmer
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AudioTrimmer(
                      audioSamples: dwa.audioSamples,
                      sampleRate: dwa.sampleRate,
                      onTrimChanged: (start, end) {
                        _trimStart = start;
                        _trimEnd = end;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Notes field
                Text(
                  'Field Notes (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Add notes about this observation...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // What will be published
                Text(
                  'Publishes kind:30747 event with:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '  - ${dwa.species.scientificName} (${dwa.confidencePercent})\n'
                  '  - Trimmed WAV audio clip\n'
                  '  - GPS location (auto-detected)\n'
                  '  - Tags: #birding #birdwatching',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 24),

                // Auth check + publish button
                BlocBuilder<AuthCubit, AuthState>(
                  builder: (context, authState) {
                    if (!authState.isAuthenticated) {
                      return Column(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            size: 48,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Connect your Nostr account in Settings to publish.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => context.push('/settings'),
                            child: const Text('Go to Settings'),
                          ),
                        ],
                      );
                    }

                    return FilledButton.icon(
                      onPressed: publishState.isPublishing ? null : _publish,
                      icon: publishState.isPublishing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        publishState.isPublishing
                            ? 'Publishing...'
                            : 'Publish to Nostr',
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
