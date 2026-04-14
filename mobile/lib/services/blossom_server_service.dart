import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nostr_sdk/nostr_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's Blossom server list (kind:10063).
///
/// On login, fetches the user's server list from relays.
/// Falls back to defaults if no list is found. Servers are ordered
/// by priority (first = primary). Persists locally for offline startup.
class BlossomServerService {
  BlossomServerService._();
  static final instance = BlossomServerService._();

  static const _prefsKey = 'blossom_servers_json';

  /// Kind for Blossom user server list (BUD-03).
  static const blossomServerListKind = 10063;

  /// Default servers when no kind:10063 event is found.
  static const defaultServers = [
    'https://blossom.band',
    'https://blossom.primal.net',
  ];

  List<String> _servers = List.of(defaultServers);
  bool _loadedFromNostr = false;

  /// The current server list, ordered by priority.
  List<String> get servers => List.unmodifiable(_servers);

  /// The primary (first) server for uploads.
  String get primaryServer =>
      _servers.isNotEmpty ? _servers.first : defaultServers.first;

  /// Whether the server list was loaded from a kind:10063 event.
  bool get loadedFromNostr => _loadedFromNostr;

  /// Fetch the user's Blossom server list from Nostr (kind:10063).
  Future<void> fetchServerList(String pubkey, Nostr nostr) async {
    try {
      final events = await nostr.queryEvents([
        {
          'kinds': [blossomServerListKind],
          'authors': [pubkey],
          'limit': 1,
        },
      ], timeout: const Duration(seconds: 8));

      if (events.isEmpty) {
        debugPrint(
          '[BlossomService] no kind:10063 event found, using defaults',
        );
        return;
      }

      final event = events.first;
      final servers = <String>[];

      for (final tag in event.tags) {
        if (tag.length >= 2 && tag[0] == 'server') {
          final url = tag[1].trim();
          if (url.isNotEmpty) servers.add(url);
        }
      }

      if (servers.isNotEmpty) {
        _servers = servers;
        _loadedFromNostr = true;
        await _persistLocally();
        debugPrint(
          '[BlossomService] loaded ${servers.length} servers from kind:10063',
        );
      }
    } catch (e) {
      debugPrint('[BlossomService] fetch error: $e');
    }
  }

  /// Publish the current server list to Nostr as kind:10063.
  Future<Event?> saveServerList(Nostr nostr, String pubkey) async {
    final tags = _servers.map((s) => ['server', s]).toList();
    final event = Event(pubkey, blossomServerListKind, tags, '');
    final result = await nostr.sendEvent(event);

    if (result != null) {
      await _persistLocally();
      debugPrint('[BlossomService] published kind:10063 server list');
    }
    return result;
  }

  /// Add a server to the list.
  void addServer(String url) {
    final normalized = _normalizeUrl(url);
    if (_servers.contains(normalized)) return;
    _servers.add(normalized);
    _persistLocally();
  }

  /// Remove a server from the list.
  void removeServer(String url) {
    _servers.remove(url);
    _persistLocally();
  }

  /// Move a server in the priority order.
  void reorderServer(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _servers.length) return;
    if (newIndex < 0 || newIndex >= _servers.length) return;
    final server = _servers.removeAt(oldIndex);
    _servers.insert(newIndex, server);
    _persistLocally();
  }

  /// Replace the entire server list.
  void setServers(List<String> servers) {
    _servers = List.of(servers);
    _persistLocally();
  }

  /// Load cached server list from local storage.
  Future<void> loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null) {
        final list = (jsonDecode(json) as List<dynamic>).cast<String>();
        if (list.isNotEmpty) {
          _servers = list;
          debugPrint(
            '[BlossomService] loaded ${list.length} servers from cache',
          );
        }
      }
    } catch (e) {
      debugPrint('[BlossomService] cache load error: $e');
    }
  }

  Future<void> _persistLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_servers));
    } catch (e) {
      debugPrint('[BlossomService] cache save error: $e');
    }
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('https://') && !u.startsWith('http://')) {
      u = 'https://$u';
    }
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}
