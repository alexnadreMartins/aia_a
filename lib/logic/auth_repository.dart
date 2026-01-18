import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firestore_service.dart';
import '../models/user_model.dart';

class AuthNotifier extends StateNotifier<User?> {
  final FirebaseAuth _auth;

  AuthNotifier(this._auth) : super(_auth.currentUser) {
    _auth.authStateChanges().listen((user) {
      state = user;
    });
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  void signOut() {
    _auth.signOut();
  }
}

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  return AuthNotifier(ref.watch(firebaseAuthProvider));
});

// Provides AiaUser profile for the logged-in user
final userProfileProvider = FutureProvider<AiaUser?>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return null;
  
  // Import FirestoreService
  return await FirestoreService().getUser(user.uid);
});
