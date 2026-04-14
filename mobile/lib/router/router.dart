import 'package:go_router/go_router.dart';

import '../models/detection_with_audio.dart';
import '../screens/bird_detail/bird_detail_screen.dart';
import '../screens/publish/publish_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/shell_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ShellScreen()),
    GoRoute(
      path: '/bird-detail',
      builder: (context, state) {
        final dwa = state.extra as DetectionWithAudio;
        return BirdDetailScreen(detectionWithAudio: dwa);
      },
    ),
    GoRoute(
      path: '/publish',
      builder: (context, state) {
        final dwa = state.extra as DetectionWithAudio;
        return PublishScreen(detectionWithAudio: dwa);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
