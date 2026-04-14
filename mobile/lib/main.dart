import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'blocs/auth/auth_cubit.dart';
import 'blocs/feed/feed_cubit.dart';
import 'blocs/identification/identification_bloc.dart';
import 'blocs/recording/recording_cubit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthCubit()..tryRestore()),
        BlocProvider(create: (_) => RecordingCubit()),
        BlocProvider(create: (_) => IdentificationBloc()),
        BlocProvider(create: (_) => FeedCubit()),
      ],
      child: const BirdsApp(),
    ),
  );
}
