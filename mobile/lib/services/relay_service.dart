import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nostr_sdk/nostr_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's relay list (NIP-65, kind:10002).
///
/// On login, fetches the user's relay list from bootstrap relays.
/// Falls back to defaults if no list is found. Relays are categorized
/// as read, write, or both. Persists locally for offline startup.
class RelayService {
  RelayService._();
  static final instance = RelayService._();

  static const _prefsKey = 'relay_list_json';

  /// Bootstrap relays used to discover the user's relay list.
  static const bootstrapRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.ditto.pub',
  ];

  /// Default relay list when no NIP-65 event is found.
  static const defaultRelayEntries = [
    RelayEntry(url: 'wss://relay.damus.io', read: true, write: true),
    RelayEntry(url: 'wss://nos.lol', read: true, write: true),
    RelayEntry(url: 'wss://relay.ditto.pub', read: true, write: true),
  ];

  List<RelayEntry> _relays = List.of(defaultRelayEntries);
  bool _loadedFromNostr = false;

  /// Cache of other users' write relays (pubkey → relay URLs).
  /// Avoids re-fetching for the same user during a session.
  final Map<String, List<String>> _userWriteRelayCache = {};

  /// The current relay list.
  List<RelayEntry> get relays => List.unmodifiable(_relays);

  /// Relays the user publishes to.
  List<String> get writeRelays =>
      _relays.where((r) => r.write).map((r) => r.url).toList();

  /// Relays the user reads from.
  List<String> get readRelays =>
      _relays.where((r) => r.read).map((r) => r.url).toList();

  /// All unique relay URLs.
  List<String> get allRelayUrls => _relays.map((r) => r.url).toSet().toList();

  /// Whether the relay list was loaded from a NIP-65 event (vs defaults).
  bool get loadedFromNostr => _loadedFromNostr;

  /// Fetch the user's relay list from Nostr (kind:10002).
  ///
  /// Queries bootstrap relays for the user's NIP-65 event.
  /// If found, updates the relay list and persists locally.
  /// If not found, keeps the current list (defaults or cached).
  Future<void> fetchRelayList(String pubkey, Nostr nostr) async {
    try {
      final events = await nostr.queryEvents([
        {
          'kinds': [EventKind.relayListMetadata],
          'authors': [pubkey],
          'limit': 1,
        },
      ], timeout: const Duration(seconds: 8));

      if (events.isEmpty) {
        debugPrint('[RelayService] no NIP-65 event found, using defaults');
        return;
      }

      // Parse the most recent event.
      final event = events.first;
      final entries = <RelayEntry>[];

      for (final tag in event.tags) {
        if (tag.isEmpty || tag[0] != 'r' || tag.length < 2) continue;
        final url = tag[1];
        if (tag.length >= 3) {
          final marker = tag[2];
          entries.add(
            RelayEntry(
              url: url,
              read: marker == 'read',
              write: marker == 'write',
            ),
          );
        } else {
          // No marker = both read and write.
          entries.add(RelayEntry(url: url, read: true, write: true));
        }
      }

      if (entries.isNotEmpty) {
        _relays = entries;
        _loadedFromNostr = true;
        await _persistLocally();
        debugPrint(
          '[RelayService] loaded ${entries.length} relays from NIP-65'
          ' (${writeRelays.length} write, ${readRelays.length} read)',
        );
      }
    } catch (e) {
      debugPrint('[RelayService] fetch error: $e');
    }
  }

  /// Fetch another user's write relays from their NIP-65 event.
  ///
  /// Results are cached for the session. Returns the user's write
  /// relay URLs, or an empty list if no NIP-65 event is found.
  /// Falls back to querying from our own connected relays.
  Future<List<String>> fetchUserWriteRelays(String pubkey, Nostr nostr) async {
    // Check cache first.
    if (_userWriteRelayCache.containsKey(pubkey)) {
      return _userWriteRelayCache[pubkey]!;
    }

    try {
      final events = await nostr.queryEvents([
        {
          'kinds': [EventKind.relayListMetadata],
          'authors': [pubkey],
          'limit': 1,
        },
      ], timeout: const Duration(seconds: 5));

      if (events.isEmpty) {
        _userWriteRelayCache[pubkey] = [];
        return [];
      }

      final event = events.first;
      final writeUrls = <String>[];

      for (final tag in event.tags) {
        if (tag.isEmpty || tag[0] != 'r' || tag.length < 2) continue;
        final url = tag[1];
        if (tag.length >= 3) {
          // Only 'write' markers indicate write relays.
          if (tag[2] == 'write') writeUrls.add(url);
        } else {
          // No marker = both read and write.
          writeUrls.add(url);
        }
      }

      _userWriteRelayCache[pubkey] = writeUrls;
      debugPrint('[RelayService] user $pubkey write relays: $writeUrls');
      return writeUrls;
    } catch (e) {
      debugPrint('[RelayService] fetchUserWriteRelays error: $e');
      _userWriteRelayCache[pubkey] = [];
      return [];
    }
  }

  /// Clear the user relay cache (call on logout or when stale).
  void clearUserRelayCache() => _userWriteRelayCache.clear();

  /// Publish the current relay list to Nostr as a kind:10002 event.
  Future<Event?> saveRelayList(Nostr nostr, String pubkey) async {
    final tags = <List<String>>[];
    for (final relay in _relays) {
      if (relay.read && relay.write) {
        tags.add(['r', relay.url]);
      } else if (relay.read) {
        tags.add(['r', relay.url, 'read']);
      } else if (relay.write) {
        tags.add(['r', relay.url, 'write']);
      }
    }

    final event = Event(pubkey, EventKind.relayListMetadata, tags, '');
    final result = await nostr.sendEvent(event);

    if (result != null) {
      await _persistLocally();
      debugPrint('[RelayService] published NIP-65 relay list');
    }
    return result;
  }

  /// Add a relay to the list.
  void addRelay(String url, {bool read = true, bool write = true}) {
    final normalized = _normalizeUrl(url);
    if (_relays.any((r) => r.url == normalized)) return;
    _relays.add(RelayEntry(url: normalized, read: read, write: write));
    _persistLocally();
  }

  /// Remove a relay from the list.
  void removeRelay(String url) {
    _relays.removeWhere((r) => r.url == url);
    _persistLocally();
  }

  /// Update a relay's read/write flags.
  void updateRelay(String url, {bool? read, bool? write}) {
    final index = _relays.indexWhere((r) => r.url == url);
    if (index < 0) return;
    final old = _relays[index];
    _relays[index] = RelayEntry(
      url: old.url,
      read: read ?? old.read,
      write: write ?? old.write,
    );
    _persistLocally();
  }

  /// Replace the entire relay list.
  void setRelays(List<RelayEntry> relays) {
    _relays = List.of(relays);
    _persistLocally();
  }

  /// Connect all relays to a Nostr instance.
  Future<void> connectAll(Nostr nostr) async {
    for (final url in allRelayUrls) {
      try {
        await nostr.addRelay(
          RelayBase(url, RelayStatus(url)),
          autoSubscribe: false,
          init: true,
        );
      } catch (e) {
        debugPrint('[RelayService] failed to connect to $url: $e');
      }
    }
    debugPrint('[RelayService] connected to ${allRelayUrls.length} relays');
  }

  /// Load cached relay list from local storage.
  Future<void> loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null) {
        final list = jsonDecode(json) as List<dynamic>;
        final entries = list
            .map((e) => RelayEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        if (entries.isNotEmpty) {
          _relays = entries;
          debugPrint(
            '[RelayService] loaded ${entries.length} relays from cache',
          );
        }
      }
    } catch (e) {
      debugPrint('[RelayService] cache load error: $e');
    }
  }

  Future<void> _persistLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_relays.map((r) => r.toJson()).toList());
      await prefs.setString(_prefsKey, json);
    } catch (e) {
      debugPrint('[RelayService] cache save error: $e');
    }
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('wss://') && !u.startsWith('ws://')) {
      u = 'wss://$u';
    }
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

/// A single relay entry with read/write flags.
class RelayEntry {
  const RelayEntry({required this.url, this.read = true, this.write = true});

  final String url;
  final bool read;
  final bool write;

  Map<String, dynamic> toJson() => {'url': url, 'read': read, 'write': write};

  factory RelayEntry.fromJson(Map<String, dynamic> json) => RelayEntry(
    url: json['url'] as String,
    read: json['read'] as bool? ?? true,
    write: json['write'] as bool? ?? true,
  );
}
