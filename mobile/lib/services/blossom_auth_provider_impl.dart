import 'package:blossom_upload_service/blossom_upload_service.dart';
import 'package:nostr_sdk/nostr_sdk.dart';

import 'nostr_service.dart';

/// Bridges [NostrService] to [BlossomAuthProvider] for Blossom uploads.
///
/// Creates and signs kind:24242 authentication events using the
/// active Nostr signer, as required by the Blossom (BUD-01) protocol.
class BlossomAuthProviderImpl implements BlossomAuthProvider {
  BlossomAuthProviderImpl({NostrService? nostrService})
    : _nostrService = nostrService ?? NostrService.instance;

  final NostrService _nostrService;

  @override
  bool get isAuthenticated => _nostrService.isAuthenticated;

  @override
  Future<BlossomSignedEvent?> createAndSignEvent({
    required int kind,
    required String content,
    required List<List<String>> tags,
  }) async {
    final nostr = _nostrService.nostr;
    final pubkey = _nostrService.publicKey;
    if (nostr == null || pubkey == null) return null;

    // Create the Blossom auth event (kind 24242).
    final event = Event(pubkey, kind, tags, content);

    // Sign via the active signer.
    await nostr.signEvent(event);

    if (!event.isSigned) return null;

    return BlossomSignedEvent(json: event.toJson());
  }
}
