import 'package:dart_geohash/dart_geohash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/feed/feed_cubit.dart';
import '../../models/observation.dart';

/// Map view showing bird observations as pins on a map.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _geoHasher = GeoHasher();
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Load global feed for map data.
    final authState = context.read<AuthCubit>().state;
    if (authState.isAuthenticated) {
      context.read<FeedCubit>().loadGlobalFeed();
    }
  }

  LatLng? _geohashToLatLng(String geohash) {
    if (geohash.isEmpty || geohash == '000000') return null;
    try {
      final decoded = _geoHasher.decode(geohash);
      return LatLng(decoded[1], decoded[0]); // [lon, lat] → LatLng(lat, lon)
    } catch (_) {
      return null;
    }
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.7) return Colors.green;
    if (confidence >= 0.4) return Colors.orange;
    return Colors.red;
  }

  void _showObservationDetail(BuildContext context, Observation obs) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _confidenceColor(
                      obs.confidence,
                    ).withAlpha(30),
                    child: Icon(
                      Icons.music_note,
                      color: _confidenceColor(obs.confidence),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          obs.commonName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          obs.species,
                          style: const TextStyle(fontStyle: FontStyle.italic),
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
                      color: _confidenceColor(obs.confidence).withAlpha(20),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      obs.confidencePercent,
                      style: TextStyle(
                        color: _confidenceColor(obs.confidence),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (obs.notes != null && obs.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(obs.notes!),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(obs.timeAgo, style: const TextStyle(color: Colors.grey)),
                  if (obs.location != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        obs.location!,
                        style: const TextStyle(color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (obs.npub != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${obs.npub!.substring(0, 20)}...',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          if (!authState.isAuthenticated) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Connect your Nostr account in Settings to see the map.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return BlocBuilder<FeedCubit, FeedState>(
            builder: (context, feedState) {
              // Build markers from observations with valid geohashes.
              final markers = <Marker>[];
              for (final obs in feedState.observations) {
                final latLng = _geohashToLatLng(obs.geohash);
                if (latLng == null) continue;

                markers.add(
                  Marker(
                    point: latLng,
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _showObservationDetail(context, obs),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _confidenceColor(obs.confidence),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(40),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                );
              }

              // Compute center from markers or default to world view.
              LatLng center;
              double zoom;
              if (markers.isNotEmpty) {
                var sumLat = 0.0;
                var sumLon = 0.0;
                for (final m in markers) {
                  sumLat += m.point.latitude;
                  sumLon += m.point.longitude;
                }
                center = LatLng(
                  sumLat / markers.length,
                  sumLon / markers.length,
                );
                zoom = markers.length == 1 ? 12.0 : 8.0;
              } else {
                center = const LatLng(40.0, -95.0); // US center
                zoom = 4.0;
              }

              return Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: zoom,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.birds.birds',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  // Marker count badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        '${markers.length} observations',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (feedState.isLoading)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: CircularProgressIndicator(),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
