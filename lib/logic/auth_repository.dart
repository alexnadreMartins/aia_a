import 'package:firedart/firedart.dart';
import 'package:firedart/auth/user_gateway.dart'; // Explicit import for User
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthNotifier extends StateNotifier<User?> {
  final FirebaseAuth _auth;

  AuthNotifier(this._auth) : super(null) {
    _init();
  }

  Future<void> _init() async {
    if (_auth.isSignedIn) {
      try {
        state = await _auth.getUser();
      } catch (e) {
        // Token might be invalid
        _auth.signOut();
        state = null;
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signIn(email, password);
    state = await _auth.getUser();
  }

  void signOut() {
    _auth.signOut();
    state = null;
  }
}

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  return AuthNotifier(ref.watch(firebaseAuthProvider));
});
