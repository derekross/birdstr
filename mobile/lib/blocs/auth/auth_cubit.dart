import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nostr_sdk/nostr_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/nostr_service.dart';

part 'auth_state.dart';

/// Manages Nostr authentication state.
///
/// Supports local nsec signing and NIP-46 remote signing.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(const AuthState.unauthenticated());

  final _nostrService = NostrService.instance;

  /// Try to restore a saved session on app start.
  Future<void> tryRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNsec = prefs.getString('auth_nsec');
    final savedBunker = prefs.getString('auth_bunker_uri');

    if (savedNsec != null) {
      await importNsec(savedNsec, save: false);
    } else if (savedBunker != null) {
      await connectBunker(savedBunker, save: false);
    }
  }

  /// Import a local nsec key.
  Future<void> importNsec(String nsec, {bool save = true}) async {
    emit(const AuthState.connecting());
    try {
      await _nostrService.loginWithNsec(nsec);
      if (save) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_nsec', nsec);
        await prefs.remove('auth_bunker_uri');
      }
      emit(
        AuthState(
          status: AuthStatus.authenticated,
          pubkey: _nostrService.publicKey,
          npub: _nostrService.npub,
        ),
      );
    } catch (e) {
      emit(
        AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Failed to login: $e',
        ),
      );
    }
  }

  /// Connect via NIP-46 bunker URI.
  Future<void> connectBunker(String bunkerUri, {bool save = true}) async {
    emit(const AuthState.connecting());
    try {
      // Parse the bunker:// URI (throws on invalid input).
      final info = NostrRemoteSignerInfo.parseBunkerUrl(bunkerUri);

      // Create remote signer and connect.
      final remoteSigner = NostrRemoteSigner(RelayMode.baseMode, info);
      await remoteSigner.connect();

      // Wait briefly for the connection to establish.
      await Future<void>.delayed(const Duration(seconds: 2));

      // Login with the remote signer.
      await _nostrService.loginWithSigner(remoteSigner);

      if (save) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_bunker_uri', bunkerUri);
        await prefs.remove('auth_nsec');
      }

      emit(
        AuthState(
          status: AuthStatus.authenticated,
          pubkey: _nostrService.publicKey,
          npub: _nostrService.npub,
        ),
      );

      debugPrint('[AuthCubit] connected via NIP-46 bunker');
    } catch (e) {
      debugPrint('[AuthCubit] bunker connection failed: $e');
      emit(
        AuthState(
          status: AuthStatus.unauthenticated,
          error: 'Bunker connection failed: $e',
        ),
      );
    }
  }

  /// Disconnect and clear credentials.
  Future<void> disconnect() async {
    _nostrService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_nsec');
    await prefs.remove('auth_bunker_uri');
    emit(const AuthState.unauthenticated());
  }
}
