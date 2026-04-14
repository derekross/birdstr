import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/feed/feed_cubit.dart';
import '../../widgets/observation_card/observation_card.dart';

/// Social feed — observations from other birders on Nostr.
///
/// Three tabs: Following (birders you follow), Nearby (by geohash),
/// Global (all kind:30747 events). Your own published observations
/// are on the Profile tab.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitial();
  }

  void _loadInitial() {
    final authState = context.read<AuthCubit>().state;
    if (authState.isAuthenticated) {
      context.read<FeedCubit>().loadFollowingFeed();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Following'),
            Tab(text: 'Nearby'),
            Tab(text: 'Global'),
          ],
          onTap: (index) {
            final cubit = context.read<FeedCubit>();
            switch (index) {
              case 0:
                cubit.loadFollowingFeed();
              case 1:
                cubit.loadNearbyFeed();
              case 2:
                cubit.loadGlobalFeed();
            }
          },
        ),
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          if (!authState.isAuthenticated) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Connect your Nostr account in Settings '
                      'to see what other birders are hearing.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: const [
              _ObservationFeed(showAuthor: true),
              _ObservationFeed(showAuthor: true),
              _ObservationFeed(showAuthor: true),
            ],
          );
        },
      ),
    );
  }
}

class _ObservationFeed extends StatelessWidget {
  const _ObservationFeed({this.showAuthor = false});
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(state.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => context.read<FeedCubit>().loadGlobalFeed(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state.observations.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.spa_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No observations found.\n'
                    'Follow other birders or check back later!',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => context.read<FeedCubit>().loadGlobalFeed(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: state.observations.length,
            itemBuilder: (context, index) {
              return ObservationCard(
                observation: state.observations[index],
                showAuthor: showAuthor,
              );
            },
          ),
        );
      },
    );
  }
}
