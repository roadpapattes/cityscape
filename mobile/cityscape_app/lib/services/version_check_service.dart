// lib/services/version_check_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class VersionCheckService {
  VersionCheckService._();
  static final instance = VersionCheckService._();

  // Version actuelle de l'app (doit correspondre à versionName dans build.gradle.kts)
  static const String currentVersion = '0.3.14';

  Future<AppConfigResponse> checkVersion() async {
    try {
      final uri = Uri.parse('$baseUrl/api/app-config');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout lors de la vérification de version');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return AppConfigResponse.fromJson(json);
    } catch (e) {
      debugPrint('[VersionCheck] Erreur: $e');
      rethrow;
    }
  }

  bool shouldForceUpdate(AppConfigResponse config) {
    if (!config.forceUpdate) return false;

    // Compare les versions: si currentVersion < minVersion, on force la mise à jour
    return _isVersionOlder(currentVersion, config.minVersion);
  }

  // Compare deux versions au format "X.Y.Z"
  // Retourne true si versionA < versionB
  bool _isVersionOlder(String versionA, String versionB) {
    final partsA = versionA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = versionB.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final a = i < partsA.length ? partsA[i] : 0;
      final b = i < partsB.length ? partsB[i] : 0;

      if (a < b) return true;
      if (a > b) return false;
    }

    return false; // versions égales
  }
}

class AppConfigResponse {
  final String minVersion;
  final String currentVersion;
  final bool forceUpdate;
  final String updateMessage;

  AppConfigResponse({
    required this.minVersion,
    required this.currentVersion,
    required this.forceUpdate,
    required this.updateMessage,
  });

  factory AppConfigResponse.fromJson(Map<String, dynamic> json) {
    return AppConfigResponse(
      minVersion: json['min_version'] as String? ?? '0.0.0',
      currentVersion: json['current_version'] as String? ?? '0.0.0',
      forceUpdate: json['force_update'] as bool? ?? false,
      updateMessage: json['update_message'] as String? ?? 'Une mise à jour est disponible.',
    );
  }
}
