// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_me.dart';
import '../core/constants.dart';

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  final tokenNotifier = ValueNotifier<String?>(null);
  final meNotifier = ValueNotifier<UserMe?>(null);

  Future<UserMe>? _meLoading; // <-- déduplication en cours

  /// Indicates if the last successful login/register/google was a new user
  bool _lastLoginWasNewUser = false;
  bool get lastLoginWasNewUser => _lastLoginWasNewUser;

  // Le jeton vit desormais dans le Keystore Android via le stockage
  // securise. Il etait auparavant ecrit en clair dans SharedPreferences
  // (XML lisible sur un appareil roote), d'ou la migration ci-dessous.
  static const _cleJeton = 'auth_token';
  // Reglages par defaut de la v11 : chiffrement AES-GCM, cle protegee par
  // RSA dans le Keystore Android, sans biometrie. C'est ce qu'on veut ici.
  static const _stockageSecurise = FlutterSecureStorage();

  Future<void> loadFromPrefs() async {
    tokenNotifier.value = await _lireJeton();
  }

  /// Lit le jeton, en migrant au passage l'ancien emplacement en clair.
  ///
  /// La migration doit etre invisible : un joueur deja connecte ne doit pas
  /// se retrouver deconnecte par la mise a jour. On ne supprime donc la
  /// copie en clair qu'une fois la copie chiffree ecrite avec succes.
  Future<String?> _lireJeton() async {
    try {
      final securise = await _stockageSecurise.read(key: _cleJeton);
      if (securise != null) return securise;
    } catch (e) {
      // Le Keystore peut refuser une lecture (cle invalidee, restauration
      // d'appareil). On ne bloque pas le demarrage : au pire le joueur se
      // reconnecte.
      debugPrint('[AUTH] Lecture du stockage securise impossible : $e');
    }

    final sp = await SharedPreferences.getInstance();
    final ancien = sp.getString(_cleJeton);
    if (ancien == null) return null;

    try {
      await _stockageSecurise.write(key: _cleJeton, value: ancien);
      await sp.remove(_cleJeton); // ne plus laisser trainer la version en clair
      debugPrint('[AUTH] Jeton migre vers le stockage securise');
    } catch (e) {
      // Ecriture impossible : on conserve l'ancien emplacement plutot que de
      // perdre la session du joueur. La migration sera retentee au prochain
      // demarrage.
      debugPrint('[AUTH] Migration impossible, jeton conserve en l\'etat : $e');
    }
    return ancien;
  }

  Future<String?> getToken() async => tokenNotifier.value;

  Future<void> saveToken(String token) async {
    try {
      await _stockageSecurise.write(key: _cleJeton, value: token);
    } catch (e) {
      // Repli sur l'ancien emplacement : mieux vaut une session qui
      // fonctionne qu'un joueur incapable de se connecter.
      debugPrint('[AUTH] Ecriture securisee impossible, repli : $e');
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cleJeton, token);
    }
    tokenNotifier.value = token;
    meNotifier.value = null;   // profil à recharger
  }

  Future<void> logout() async {
    // On efface les deux emplacements : un jeton oublie dans l'ancien
    // ressusciterait la session a la prochaine lecture.
    try {
      await _stockageSecurise.delete(key: _cleJeton);
    } catch (e) {
      debugPrint('[AUTH] Suppression securisee impossible : $e');
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_cleJeton);

    tokenNotifier.value = null;
    meNotifier.value = null;
  }

  bool get isAdmin => meNotifier.value?.isAdmin == true;

/// Login with username/password. Returns true if is_new_user (always false for login).
Future<bool> login(String username, String password) async {
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

  // Check if new user (should always be false for login)
  final isNewUser = j['is_new_user'] as bool? ?? false;
  _lastLoginWasNewUser = isNewUser;

  // 1) Sauvegarde immédiate -> l'UI considère qu'on est loggé
  await saveToken(token);

  // 2) Préchargement du profil en tâche de fond (sans bloquer, sans propager l'erreur)
  unawaited(ensureProfileLoaded().catchError((_) {}));

  return isNewUser;
}


  /// Register new user. Returns true if is_new_user (always true for register).
  Future<bool> register(String username, String password, String? email) async {
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

    // Check if new user (should always be true for register)
    final isNewUser = j['is_new_user'] as bool? ?? true;
    _lastLoginWasNewUser = isNewUser;

    await saveToken(token);
    unawaited(ensureProfileLoaded().catchError((_) {}));

    return isNewUser;
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

  /// Sign in with Google. Returns true if is_new_user.
  Future<bool> signInWithGoogle() async {
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

        // Check if new user
        final isNewUser = data['is_new_user'] as bool? ?? false;
        _lastLoginWasNewUser = isNewUser;

        // Save token
        await saveToken(token);

        // Load user profile
        unawaited(ensureProfileLoaded().catchError((_) {}));

        return isNewUser;
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
