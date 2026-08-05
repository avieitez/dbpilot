import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

enum SubscriptionPlan {
  free,
  pro,
}

extension SubscriptionPlanX on SubscriptionPlan {
  String get label {
    switch (this) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.pro:
        return 'Pro';
    }
  }
}

class AppUserSession {
  const AppUserSession({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.emailVerified,
    required this.plan,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;
  final SubscriptionPlan plan;

  bool get hasVerifiedEmail =>
      emailVerified && email != null && email!.trim().isNotEmpty;
}

class AuthService {
  static const String _apiBaseUrl = 'https://dbpilot-5g16.onrender.com';
  static const String _serverClientId =
      '100510560960-20gcgaoctqjk0khcv3llln4crk58ql57.apps.googleusercontent.com';

  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  bool _googleInitialized = false;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  Future<AppUserSession?> currentSession() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return _sessionFromUser(user);
  }

  Future<AppUserSession?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final googleUser = await _googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    return _sessionFromUser(user);
  }

  Future<void> signOut() async {
    await _ensureGoogleInitialized();
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  Future<void> deleteAccount() async {
    await _ensureGoogleInitialized();
    var user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No authenticated Firebase user is available.');
    }

    await _reauthenticateWithGoogle(user);
    user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('Firebase user is not available after reauthentication.');
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception('A valid session is required to delete the account.');
    }

    final response = await http.delete(
      Uri.parse('$_apiBaseUrl/api/v1/account'),
      headers: {'Authorization': 'Bearer $idToken'},
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_errorMessageFromResponse(
        response.body,
        fallback: 'Account deletion failed (${response.statusCode}).',
      ));
    }

    final payload = _decodeObject(response.body);
    if (payload['requiresClientAuthDeletion'] == true ||
        payload['authDeleted'] == false) {
      await _deleteCurrentFirebaseUser();
    }

    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
    await _firebaseAuth.signOut();
  }

  Future<void> _deleteCurrentFirebaseUser() async {
    var user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('Firebase user is not available for account deletion.');
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code != 'requires-recent-login') {
        throw Exception(_firebaseAuthErrorMessage(
          error,
          'Firebase account deletion failed',
        ));
      }

      await _reauthenticateWithGoogle(user);
      user = _firebaseAuth.currentUser;
      if (user == null) {
        throw Exception(
          'Firebase user is not available after recent-login reauthentication.',
        );
      }

      try {
        await user.delete();
      } on FirebaseAuthException catch (retryError) {
        throw Exception(_firebaseAuthErrorMessage(
          retryError,
          'Firebase account deletion failed after reauthentication',
        ));
      }
    }
  }

  Future<void> _reauthenticateWithGoogle(User user) async {
    try {
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      throw Exception(_firebaseAuthErrorMessage(
        error,
        'Firebase reauthentication failed',
      ));
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      throw Exception(
        'Google reauthentication failed: $message',
      );
    }
  }

  String _firebaseAuthErrorMessage(
    FirebaseAuthException error,
    String prefix,
  ) {
    final message = error.message?.trim();
    final detail = message == null || message.isEmpty
        ? error.code
        : '${error.code}: $message';
    return '$prefix ($detail).';
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic>) return payload;
    } catch (_) {
      // The backend should return JSON, but keep deletion compatible with
      // older deployments that only returned a status code.
    }
    return const {};
  }

  String _errorMessageFromResponse(
    String body, {
    required String fallback,
  }) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) return detail;
      }
    } catch (_) {
      // Keep the original fallback when the backend does not return JSON.
    }
    return fallback;
  }

  Future<AppUserSession> _sessionFromUser(User user) async {
    final plan = await checkPlayStoreSubscription(user.uid);
    return AppUserSession(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      emailVerified: user.emailVerified,
      plan: plan,
    );
  }

  Future<SubscriptionPlan> checkPlayStoreSubscription(String uid) async {
    if (uid.trim().isEmpty) return SubscriptionPlan.free;
    final user = _firebaseAuth.currentUser;
    if (user == null || user.uid != uid) return SubscriptionPlan.free;

    try {
      final idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) return SubscriptionPlan.free;
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/v1/subscriptions/me'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return SubscriptionPlan.free;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['plan']?.toString().toLowerCase() == 'pro'
          ? SubscriptionPlan.pro
          : SubscriptionPlan.free;
    } catch (_) {
      return SubscriptionPlan.free;
    }
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize(serverClientId: _serverClientId);
    _googleInitialized = true;
  }
}
