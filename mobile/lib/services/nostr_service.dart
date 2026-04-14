import 'package:flutter/foundation.dart';
import 'package:nostr_sdk/nostr_sdk.dart';

/// Manages the Nostr connection — signer, relay pool, event publishing.
///
/// This is the app's single point of contact with the Nostr network.
class NostrService {
  NostrService._();
  static final instance = NostrService._();

  Nostr? _nostr;
  NostrSigner? _signer;
  String? _publicKey;

  /// Default relays for publishing bird observations.
  static const defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.ditto.pub',
  ];

  /// Whether we have an active signer.
  bool get isAuthenticated => _signer != null && _publicKey != null;

  /// The current user's hex public key.
  String? get publicKey => _publicKey;

  /// The current user's npub.
  String? get npub =>
      _publicKey != null ? Nip19.encodePubKey(_publicKey!) : null;

  /// The underlying Nostr instance for advanced usage.
  Nostr? get nostr => _nostr;

  /// Initialize with a local private key (nsec).
  Future<void> loginWithNsec(String nsec) async {
    final privateKeyHex = Nip19.decode(nsec);
    if (privateKeyHex.isEmpty) {
      throw ArgumentError('Invalid nsec');
    }

    _signer = LocalNostrSigner(privateKeyHex);
    await _initNostr();
  }

  /// Initialize with a hex private key.
  Future<void> loginWithHex(String privateKeyHex) async {
    _signer = LocalNostrSigner(privateKeyHex);
    await _initNostr();
  }

  /// Initialize with an existing signer (e.g., NIP-46 remote signer).
  Future<void> loginWithSigner(NostrSigner signer) async {
    _signer = signer;
    await _initNostr();
  }

  Future<void> _initNostr() async {
    final signer = _signer;
    if (signer == null) return;

    _nostr = Nostr(signer, [], (url) => RelayBase(url, RelayStatus(url)));

    await _nostr!.refreshPublicKey();
    _publicKey = _nostr!.publicKey;
    debugPrint('[NostrService] logged in as $_publicKey');

    // Connect to default relays.
    for (final url in defaultRelays) {
      try {
        await _nostr!.addRelay(
          RelayBase(url, RelayStatus(url)),
          autoSubscribe: false,
          init: true,
        );
        debugPrint('[NostrService] connected to $url');
      } catch (e) {
        debugPrint('[NostrService] failed to connect to $url: $e');
      }
    }
  }

  /// Sign and publish an event to all connected relays.
  Future<Event?> publishEvent(Event event) async {
    if (_nostr == null) {
      throw StateError('Not logged in. Call login first.');
    }
    return _nostr!.sendEvent(event);
  }

  /// Create and publish a bird observation event (kind 30747).
  Future<Event?> publishObservation({
    required String content,
    required List<List<String>> tags,
  }) async {
    final pk = publicKey;
    if (pk == null || _nostr == null) {
      throw StateError('Not logged in.');
    }

    final event = Event(pk, 30747, tags, content);
    return _nostr!.sendEvent(event);
  }

  /// Request deletion of an event (NIP-09, kind:5).
  ///
  /// Publishes a kind:5 event referencing the target event.
  /// Relays SHOULD delete the referenced event, but compliance varies.
  Future<Event?> deleteEvent(String eventId) async {
    final pk = publicKey;
    if (pk == null || _nostr == null) {
      throw StateError('Not logged in.');
    }

    final event = Event(pk, 5, [
      ['e', eventId],
    ], 'Deleted');
    return _nostr!.sendEvent(event);
  }

  /// Query events from connected relays.
  Future<List<Event>> queryEvents(
    List<Map<String, dynamic>> filters, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_nostr == null) {
      throw StateError('Not logged in.');
    }
    return _nostr!.queryEvents(filters, timeout: timeout);
  }

  /// Disconnect and clear credentials.
  void logout() {
    _signer?.close();
    _signer = null;
    _nostr?.close();
    _nostr = null;
    _publicKey = null;
    debugPrint('[NostrService] logged out');
  }
}
