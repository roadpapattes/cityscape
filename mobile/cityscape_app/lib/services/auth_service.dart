// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_me.dart';
import '../core/constants.dart';

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  final tokenNotifier = ValueNotifier<String?>(null);
  final meNotifier = ValueNotifier<UserMe?>(null);

  Future<UserMe>? _meLoading; // <-- déduplication en cours

  Future<void> loadFromPrefs() async {
    final sp = await SharedPreferences.getInstance();
    tokenNotifier.value = sp.getString('auth_token');
    // Note: If you have ApiService.instance.loadLocalModeration(),
    // you may need to import and call it here or handle it differently
    // await ApiService.instance.loadLocalModeration();
    // Pas de notifyListeners(); on utilise les Notifiers dédiés.
  }

  Future<String?> getToken() async => tokenNotifier.value;

  Future<void> saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('auth_token', token);
    tokenNotifier.value = token;
    meNotifier.value = null;   // profil à recharger
    // Pas de notifyListeners();
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('auth_token');
    tokenNotifier.value = null;
    meNotifier.value = null;
    // Pas de notifyListeners();
  }

  bool get isAdmin => meNotifier.value?.isAdmin == true;

Future<void> login(String username, String password) async {
  final r = await http.post(
    Uri.parse('$baseUrl/api$kAuthPrefix/auth/login'),
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    },
    body: jsonEncode({'username': username, 'password': password}),
  );

  if (r.statusCode != 200) {
    throw Exception('Identifiants invalides (${r.statusCode})');
  }

  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final token = j['token'] as String?;
  if (token == null || token.isEmpty) {
    throw Exception('Token manquant');
  }

  // 1) Sauvegarde immédiate -> l'UI considère qu'on est loggé
  await saveToken(token);

  // 2) Préchargement du profil en tâche de fond (sans bloquer, sans propager l'erreur)
  unawaited(ensureProfileLoaded().catchError((_) {}));
}


  Future<void> register(String username, String password, String? email) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api$kAuthPrefix/auth/register'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      }),
    );
    if (r.statusCode != 201) {
      throw Exception('Inscription refusée: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final token = j['token'] as String?;
    if (token == null || token.isEmpty) throw Exception('Token manquant');

    await saveToken(token);
    await ensureProfileLoaded();
	unawaited(ensureProfileLoaded().catchError((_) {}));
  }

  Future<UserMe> fetchMe() {
    final t = tokenNotifier.value;
    if (t == null) {
      return Future.error(Exception('Non connecté'));
    }
    // Si déjà en cours, renvoyer la même Future
    _meLoading ??= _doFetchMe(t);
    return _meLoading!;
  }

  Future<UserMe> _doFetchMe(String token) async {
    try {
      final rr = await http.get(
        Uri.parse('$baseUrl/api$kAuthPrefix/auth/me'),
        headers: {'Authorization': 'Token $token', 'Accept': 'application/json'},
      );
      if (rr.statusCode != 200) {
        throw Exception('Impossible de récupérer le profil (${rr.statusCode})');
      }
      final jj = jsonDecode(utf8.decode(rr.bodyBytes)) as Map<String, dynamic>;
      final me = UserMe.fromJson(jj);
      meNotifier.value = me;   // notifie les écouteurs du profil
      return me;
    } finally {
      // Toujours libérer pour les futurs appels
      _meLoading = null;
    }
  }

  Future<void> ensureProfileLoaded() async {
    if (tokenNotifier.value == null) {
      meNotifier.value = null;
      return;
    }
    if (meNotifier.value != null) return;
    await fetchMe(); // dédupliqué
  }

  // Google Sign-In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: '622564437605-fludcb1jo2157oi7ejbg25jju9d6qeht.apps.googleusercontent.com',
  );

  Future<void> signInWithGoogle() async {
    try {
      // Start Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        throw Exception('Connexion annulée');
      }

      // Get authentication tokens
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Impossible d\'obtenir le token Google');
      }

      // Send ID token to backend
      final response = await http.post(
        Uri.parse('$baseUrl/api$kAuthPrefix/auth/google'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({'id_token': idToken}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final token = data['token'] as String?;

        if (token == null) {
          throw Exception('Token manquant dans la réponse');
        }

        // Save token
        await saveToken(token);

        // Load user profile
        await fetchMe();
      } else {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(error['error'] ?? 'Erreur d\'authentification Google');
      }
    } catch (e) {
      // Sign out from Google if there was an error
      await _googleSignIn.signOut();
      rethrow;
    }
  }

  Future<void> signOutFromGoogle() async {
    await _googleSignIn.signOut();
    await logout();
  }

  /// Met à jour le profil utilisateur (username, email, first_name, last_name)
  Future<UserMe> updateProfile({
    String? username,
    String? email,
    String? firstName,
    String? lastName,
  }) async {
    final t = tokenNotifier.value;
    if (t == null) {
      throw Exception('Non connecté');
    }

    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (email != null) body['email'] = email;
    if (firstName != null) body['first_name'] = firstName;
    if (lastName != null) body['last_name'] = lastName;

    final response = await http.patch(
      Uri.parse('$baseUrl/api$kAuthPrefix/auth/profile'),
      headers: {
        'Authorization': 'Token $t',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(error['detail'] ?? 'Erreur lors de la mise à jour du profil');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final updatedUser = UserMe.fromJson(data);
    meNotifier.value = updatedUser;
    return updatedUser;
  }

  /// Change le mot de passe de l'utilisateur
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final t = tokenNotifier.value;
    if (t == null) {
      throw Exception('Non connecté');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api$kAuthPrefix/auth/change-password'),
      headers: {
        'Authorization': 'Token $t',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(error['detail'] ?? 'Erreur lors du changement de mot de passe');
    }
  }
}
