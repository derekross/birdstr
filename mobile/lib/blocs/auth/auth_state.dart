part of 'auth_cubit.dart';

enum AuthStatus { unauthenticated, connecting, authenticated }

class AuthState extends Equatable {
  const AuthState({required this.status, this.pubkey, this.npub, this.error});

  const AuthState.unauthenticated()
    : status = AuthStatus.unauthenticated,
      pubkey = null,
      npub = null,
      error = null;

  const AuthState.connecting()
    : status = AuthStatus.connecting,
      pubkey = null,
      npub = null,
      error = null;

  final AuthStatus status;
  final String? pubkey;
  final String? npub;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  List<Object?> get props => [status, pubkey, npub, error];
}
