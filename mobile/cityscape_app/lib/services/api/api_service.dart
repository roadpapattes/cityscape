// lib/services/api/api_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/escape_game.dart';
import '../../models/game_step.dart';
import '../../models/comment_item.dart';
import '../../models/cache_entry.dart';
import '../../core/constants.dart';
import '../../core/utils/image_utils.dart';
import '../auth_service.dart';

class ApiService {
  ApiService._() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 6;
    _client = IOClient(io);
  }

  static final instance = ApiService._();
  late final IOClient _client;
  late Box _cacheBox;

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // --- Cache local des refus ---
  Set<int> _refusedIds = {};
  final Map<int, String> _rejectReasons = {}; // motif local

  Future<void> loadLocalModeration() async {
    final sp = await SharedPreferences.getInstance();
    _refusedIds = (sp.getStringList('refused_ids') ?? const <String>[])
        .map((s) => int.tryParse(s) ?? -1)
        .where((v) => v >= 0)
        .toSet();
    for (final id in _refusedIds) {
      final r = sp.getString('reject_reason_$id');
      if (r != null && r.trim().isNotEmpty) _rejectReasons[id] = r;
    }
  }

  Future<void> invalidatePublicListsCache() async {
  // Clear the anonymous public lists
  await _cacheBox.delete('escapes_all_v1:anon');
  // Optionally clear nearby anon entries (lightweight best-effort)
  final keys = _cacheBox.keys.where((k) => k is String && k.startsWith('nearby_v1:anon:')).toList();
  for (final k in keys) {
    await _cacheBox.delete(k);
  }
}


  Future<void> _saveLocalModeration() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('refused_ids', _refusedIds.map((e) => e.toString()).toList());
  }

  Future<void> submitEscape(int id) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _post(
      Uri.parse('$baseUrl/api/creator/escapes/$id/submit'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode != 200) {
      throw Exception('Soumission refusée: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> sendCreatorFeedback({
  required String message,
  int? escapeId,
  int? stepId,
  String? page,
}) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  final uri = Uri.parse('$baseUrl/api/creator/feedback/');
  final payload = {
    'message': message,
    if (escapeId != null) 'escape_id': escapeId,
    if (stepId != null)   'step_id': stepId,
    if (page != null)     'page': page,
  };

  final r = await _post(
    uri,
    headers: {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: jsonEncode(payload),
  );

  if (r.statusCode != 200) {
    throw Exception('Feedback: ${r.statusCode} ${r.body}');
  }
}

  Future<void> reportEscape(int escapeId, String message) async {
	final token = await AuthService.instance.getToken();
	if (token == null) throw Exception('Non connecté');

	final uri = Uri.parse('$baseUrl/api$kEngagementPrefix/escapes/$escapeId/report');

	final r = await _post(
	  uri,
	  headers: {
	    'Authorization': 'Token $token',
	    'Content-Type': 'application/json; charset=utf-8',
	  },
	  body: jsonEncode({'message': message}),
	);

	if (r.statusCode != 201) {
	  throw Exception('Report: ${r.statusCode} ${r.body}');
	}
  }


  Future<void> initCache() async {
    await Hive.initFlutter();
    _cacheBox = await Hive.openBox('http_cache_v1');
  }

  bool isLocallyRefused(int id) => _refusedIds.contains(id);

  Future<void> markLocallyRefused(int id) async {
    _refusedIds.add(id);
    await _saveLocalModeration();
  }

  Future<void> unmarkLocallyRefused(int id) async {
    _refusedIds.remove(id);
    _rejectReasons.remove(id);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('reject_reason_$id');
    await _saveLocalModeration();
  }

  String? localRejectReason(int id) => _rejectReasons[id];

  Future<void> setLocalRejectReason(int id, String reason) async {
    _rejectReasons[id] = reason;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('reject_reason_$id', reason);
  }

  // ---------------- HTTP CORE (avec retry + timeout) ----------------

  Future<http.Response> _sendWithRetry(
    http.BaseRequest req, {
    int maxAttempts = 3,
    Duration opTimeout = const Duration(seconds: 20),
    bool forceCloseOnLast = true,
  }) async {
    http.Response? last;
    Duration backoff = const Duration(milliseconds: 200);

    for (int i = 1; i <= maxAttempts; i++) {
      try {
        final streamed = await _client.send(req).timeout(opTimeout);
        final r = await http.Response.fromStream(streamed).timeout(opTimeout);
        last = r;

        if (r.statusCode < 400) return r;

        if (r.statusCode >= 500 && i < maxAttempts) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        return r;
      } on TimeoutException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        if (i == maxAttempts - 1 && forceCloseOnLast) {
          req.headers['Connection'] = 'close';
        }
        continue;
      } on SocketException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        if (i == maxAttempts - 1 && forceCloseOnLast) {
          req.headers['Connection'] = 'close';
        }
        continue;
      } on HandshakeException {
        rethrow;
      } on HttpException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      }
    }

    return last ?? http.Response('No response', 599, request: req, reasonPhrase: 'No response after retries');
  }

  int _previewLen(String s, [int max = 300]) => s.length < max ? s.length : max;

  Future<http.Response> _sendWithRetryReq(
    http.Request template, {
    int maxAttempts = 3,
    Duration opTimeout = const Duration(seconds: 20),
    bool forceCloseOnLast = true,
  }) async {
    http.Response? last;
    Duration backoff = const Duration(milliseconds: 200);

    for (int i = 1; i <= maxAttempts; i++) {
      final req = http.Request(template.method, template.url)
        ..followRedirects = template.followRedirects
        ..maxRedirects = template.maxRedirects
        ..persistentConnection = template.persistentConnection;

      req.headers.addAll(template.headers);
      if (template.bodyBytes.isNotEmpty) {
        req.bodyBytes = template.bodyBytes;
      }

      try {
        final streamed = await _client.send(req).timeout(opTimeout);
        final r = await http.Response.fromStream(streamed).timeout(opTimeout);
        last = r;

        if (r.statusCode < 400) return r;

        if (r.statusCode >= 500 && i < maxAttempts) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        return r;
      } on TimeoutException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        if (i == maxAttempts - 1 && forceCloseOnLast) {
          template.headers['Connection'] = 'close';
        }
        continue;
      } on SocketException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        if (i == maxAttempts - 1 && forceCloseOnLast) {
          template.headers['Connection'] = 'close';
        }
        continue;
      } on HandshakeException {
        rethrow;
      } on HttpException {
        if (i == maxAttempts) rethrow;
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      }
    }

    return last ?? http.Response('No response', 599, request: template, reasonPhrase: 'No response after retries');
  }

  Future<http.Response> _get(Uri u, {Map<String, String>? headers}) async {
    final req = http.Request('GET', u)
      ..headers.addAll({'Accept': 'application/json', ...?headers});
    debugPrint('[HTTP GET] $u');
    final r = await _sendWithRetryReq(req);
    debugPrint('  -> ${r.statusCode} ${r.headers['content-type']} ${r.bodyBytes.length}B');
    final ct = r.headers['content-type'] ?? '';
    if (ct.contains('text/html')) {
      final s = utf8.decode(r.bodyBytes);
      final p = _previewLen(s);
      debugPrint('  BODY(0..$p): ${s.substring(0, p)}');
    }
    return r;
  }

  Future<http.Response> _post(Uri u, {Map<String, String>? headers, Object? body}) async {
    final req = http.Request('POST', u)
      ..headers.addAll({'Accept': 'application/json', ...?headers});

    if (body is String) {
      req.headers.putIfAbsent('Content-Type', () => 'application/json; charset=utf-8');
      req.body = body;
    } else if (body != null) {
      req.headers.putIfAbsent('Content-Type', () => 'application/json; charset=utf-8');
      req.body = jsonEncode(body);
    }

    debugPrint('[HTTP POST] $u');
    final r = await _sendWithRetryReq(req);
    debugPrint('  -> ${r.statusCode} ${r.headers['content-type']} ${r.bodyBytes.length}B');
    final s = utf8.decode(r.bodyBytes);
    final p = _previewLen(s);
    if ((r.headers['content-type'] ?? '').contains('text/html')) {
      debugPrint('  BODY(0..$p): ${s.substring(0, p)}');
    }
    return r;
  }

  Future<http.Response> _patchJson(Uri u, {Map<String, String>? headers, Object? body}) async {
    final req = http.Request('PATCH', u)
      ..headers.addAll({'Accept': 'application/json', ...?headers});

    if (body is String) {
      req.headers.putIfAbsent('Content-Type', () => 'application/json; charset=utf-8');
      req.body = body;
    } else if (body != null) {
      req.headers.putIfAbsent('Content-Type', () => 'application/json; charset=utf-8');
      req.body = jsonEncode(body);
    }

    debugPrint('[HTTP PATCH] $u');
    final r = await _sendWithRetryReq(req);
    debugPrint('  -> ${r.statusCode} ${r.headers['content-type']} ${r.bodyBytes.length}B');
    return r;
  }

  Future<http.Response> _getWithIfNoneMatch(Uri u, {String? ifNoneMatch, Map<String, String>? headers}) {
    final all = <String, String>{
      'Accept': 'application/json',
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) 'If-None-Match': ifNoneMatch,
      ...?headers,
    };
    return _get(u, headers: all);
  }

  Future<List> _getJsonListCached({
    required String cacheKey,
    required Uri uri,
    Duration ttl = const Duration(hours: 24),
    Map<String, String>? extraHeaders,
  }) async {
    final cached = CacheEntry.fromMap(_cacheBox.get(cacheKey));
    final now = _nowMs();
    final isFresh = cached != null && (now - cached.fetchedAtMs) < ttl.inMilliseconds;
    final etag = cached?.etag;

    http.Response r;

    try {
      if (etag != null) {
        r = await _getWithIfNoneMatch(uri, ifNoneMatch: etag, headers: extraHeaders);
        if (r.statusCode == 304 && cached != null) {
          final data = jsonDecode(utf8.decode(cached.body));
          if (data is! List) throw Exception('Réponse cache inattendue');
          return data;
        }
      } else {
        r = await _get(uri, headers: extraHeaders);
      }
    } catch (e) {
      if (cached != null) {
        final data = jsonDecode(utf8.decode(cached.body));
        if (data is! List) throw Exception('Réponse cache inattendue');
        return data;
      }
      rethrow;
    }

    if (r.statusCode != 200) {
      if (cached != null) {
        final data = jsonDecode(utf8.decode(cached.body));
        if (data is! List) throw Exception('Réponse cache inattendue');
        return data;
      }
      throw Exception('HTTP ${r.statusCode}');
    }

    final newEtag = r.headers['etag'];
    final ct = r.headers['content-type'];
    final bytes = r.bodyBytes;
    _cacheBox.put(cacheKey, CacheEntry(bytes, newEtag, ct, now).toMap());

    final data = jsonDecode(utf8.decode(bytes));
    if (data is! List) throw Exception('Réponse inattendue (liste attendue)');
    return data;
  }

  // ---------------- API PUBLIC ----------------

  Future<void> ping() async {
    try {
      final uri = Uri.parse('$baseUrl/api/health');
      final r = await _get(uri);
      debugPrint('[PING] ${r.statusCode}');
    } catch (e) {
      debugPrint('[PING] échec: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPastSteps(int escapeId) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  final uri = Uri.parse('$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/history');

  final r = await _get(
    uri,
    headers: {'Authorization': 'Token $token'},
  );
  if (r.statusCode != 200) {
    throw Exception('History: ${r.statusCode} ${r.body}');
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final steps = (j['steps'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  return steps;
}


  Future<EscapeGame> fetchCreatorDetail(int id) async {
	final token = await AuthService.instance.getToken();
	if (token == null) throw Exception('Non connecté');
	final r = await _get(
		Uri.parse('$baseUrl/api/creator/escapes/$id'),
		headers: {'Authorization': 'Token $token', 'Accept': 'application/json'},
	);
	if (r.statusCode != 200) {
		throw Exception('HTTP ${r.statusCode} detail');
	}
	final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
	return EscapeGame.fromJson(j, baseUrl);
}

  Future<List<EscapeGame>> fetchAll() async {
  final token = await AuthService.instance.getToken();
  final uri = Uri.parse('$baseUrl/api/escapes');

  if (token != null) {
    // Authentifié : **on envoie le token** pour que l'API filtre correctement
    final r = await _get(uri, headers: {
      'Authorization': 'Token $token',
      'Accept': 'application/json',
    });
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>, baseUrl)).toList();
  } else {
    // Anonyme : cache séparé
    final list = await _getJsonListCached(
      cacheKey: 'escapes_all_v1:anon',
      uri: uri,
      ttl: const Duration(hours: 24),
    );
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>, baseUrl)).toList();
  }
}


  Future<List<EscapeGame>> fetchNearby({
  required double lat,
  required double lon,
  double radiusKm = kDefaultRadiusKm,
}) async {
  final token = await AuthService.instance.getToken();
  final uri = Uri.parse('$baseUrl/api/escapes/nearby').replace(queryParameters: {
    'lat': '$lat',
    'lon': '$lon',
    'radius_km': '$radiusKm',
  });

  if (token != null) {
    final r = await _get(uri, headers: {
      'Authorization': 'Token $token',
      'Accept': 'application/json',
    });
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>, baseUrl)).toList();
  } else {
    final key = 'nearby_v1:anon:${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)},$radiusKm';
    final list = await _getJsonListCached(
      cacheKey: key,
      uri: uri,
      ttl: const Duration(minutes: 30),
    );
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>, baseUrl)).toList();
  }
}


  Future<List<CommentItem>> fetchComments(int escapeId, {int limit = 3}) async {
    final uri = Uri.parse('$baseUrl/api/escapes/$escapeId/comments')
        .replace(queryParameters: {'limit': '$limit'});
    final r = await _get(uri);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} comments');
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => CommentItem.fromJson(e)).toList();
  }

  Future<bool> canRate(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) return false; // non connecté -> pas le droit de noter

    final r = await _get(
		Uri.parse('$baseUrl/api$kEngagementPrefix/escapes/$escapeId/can_rate'),
		headers: {'Authorization': 'Token $token'},
    );

    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    return (j['can_rate'] ?? false) as bool;
  }

  Future<void> submitRating({
    required int escapeId,
    required int stars,
    required String comment,
  }) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _post(
      Uri.parse('$baseUrl/api$kEngagementPrefix/escapes/$escapeId/ratings'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: {'escape': escapeId, 'stars': stars, 'comment': comment},
    );
    if (r.statusCode != 201) {
      throw Exception('Note refusée: ${r.statusCode} ${r.body}');
    }
  }

  // ---------- CREATOR ----------
  Future<List<EscapeGame>> fetchCreatorList({String? status}) async {
    final token = AuthService.instance.tokenNotifier.value;
    if (token == null) throw Exception('Non connecté');

    // Normalisation du filtre "status"
    String? s;
    if (status != null) {
      const allowed = {'draft', 'submitted', 'published', 'rejected', 'all'};
      if (allowed.contains(status)) {
        // on ne passe pas 'all' à l'API (=> pas de filtre)
        if (status != 'all') s = status;
      } else {
        s = null; // filtre non reconnu -> pas de filtre
      }
    }

    final base = Uri.parse('$baseUrl/api/creator/escapes');
    final uri = (s == null) ? base : base.replace(queryParameters: {'status': s});

    final r = await _get(
      uri,
      headers: {
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      },
    );

    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }

    final data = jsonDecode(utf8.decode(r.bodyBytes));
    if (data is! List) {
      throw Exception('Réponse inattendue (liste attendue)');
    }
    return data.map<EscapeGame>((e) => EscapeGame.fromJson(e as Map<String, dynamic>, baseUrl)).toList();
  }

  Future<Map<String, dynamic>?> fetchMe() async {
    final token = await AuthService.instance.getToken();
    if (token == null) return null;
    final r = await _get(
      Uri.parse('$baseUrl/api$kAuthPrefix/auth/me'),
      headers: {'Authorization': 'Token $token', 'Accept': 'application/json'},
    );
    if (r.statusCode != 200) return null;
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<int> createDraft({
    required String title,
    required String city,
    required double latitude,
    required double longitude,
    int durationMinutes = 60,
    int difficulty = 2,
    String description = '',
  }) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _post(
      Uri.parse('$baseUrl/api/creator/escapes'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: {
        'title': title,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'duration_minutes': durationMinutes,
        'difficulty': difficulty,
        'description': description,
        'steps': [],
      },
    );
    if (r.statusCode != 201) throw Exception('Création refusée: ${r.statusCode} ${r.body}');
    final j = jsonDecode(r.body);
    return (j['id'] as num).toInt();
  }

  Future<void> publish(int id) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _post(
      Uri.parse('$baseUrl/api/creator/escapes/$id/publish'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode != 200) throw Exception('Publication refusée: ${r.statusCode} ${r.body}');
    await unmarkLocallyRefused(id);
  }

  /// Rejette un escape (POST /reject/ si dispo, sinon /reject, sinon PATCH fallback).
  Future<void> rejectEscape(int id, String reason, {bool includeStatus = true}) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');

    // 1) Nouveau flux : POST sur l'action DRF (avec ET sans slash)
    final candidates = <Uri>[
      Uri.parse('$baseUrl/api/creator/escapes/$id/reject/'),
      Uri.parse('$baseUrl/api/creator/escapes/$id/reject'),
    ];

    for (final u in candidates) {
      final r = await _post(
        u,
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: {'reason': reason},
      );

      // OK
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await markLocallyRefused(id);
        await setLocalRejectReason(id, reason);
        return;
      }

      // 404/405/301/308 -> on tentera l'autre variante / le fallback
      if (r.statusCode == 404 || r.statusCode == 405 || r.statusCode == 301 || r.statusCode == 308) {
        continue;
      }

      // Autres erreurs côté action -> stop net
      throw Exception('Reject failed (${r.statusCode}): ${r.body}');
    }

    // 2) Fallback legacy : PATCH (peut être refusé aux admins côté serveur)
    final payload = <String, dynamic>{
      'reject_reason': reason,
      if (includeStatus) 'status': 'rejected',
    };

    final patchUris = <Uri>[
      Uri.parse('$baseUrl/api/creator/escapes/$id'),
      Uri.parse('$baseUrl/api/creator/escapes/$id/'),
    ];

    for (final u in patchUris) {
      final r = await _patchJson(
        u,
        headers: {
          'Authorization': 'Token $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: payload,
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        await markLocallyRefused(id);
        await setLocalRejectReason(id, reason);
        return;
      }
      if (r.statusCode == 404) continue; // essaye l'autre forme
      // 403 ici = "admin ne peut pas modifier", on n'insiste pas si l'action a échoué
      if (r.statusCode == 403) {
        throw Exception('Rejet refusé (403 via PATCH): ${r.body}');
      }
    }

    // 3) Dernier essai : PATCH sans le champ status si includeStatus posait souci
    if (includeStatus) {
      final payload2 = {'reject_reason': reason};
      for (final u in patchUris) {
        final r = await _patchJson(
          u,
          headers: {
            'Authorization': 'Token $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: payload2,
        );
        if (r.statusCode >= 200 && r.statusCode < 300) {
          await markLocallyRefused(id);
          await setLocalRejectReason(id, reason);
          return;
        }
      }
    }

    throw Exception('Rejet refusé: aucun endpoint valide (/reject ni PATCH).');
  }

  Future<EscapeGame> getEscapeDetail(int id) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  final r = await _get(
    Uri.parse('$baseUrl/api/creator/escapes/$id'),
    headers: {
      'Authorization': 'Token $token',
      'Accept': 'application/json',
    },
  );
  if (r.statusCode != 200) {
    throw Exception('HTTP ${r.statusCode}');
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  return EscapeGame.fromJson(j, baseUrl);
}

  Future<EscapeGame> updateEscape(int id, Map<String, dynamic> patch) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  final req = http.Request('PATCH', Uri.parse('$baseUrl/api/creator/escapes/$id'))
    ..followRedirects = false
    ..headers.addAll({
      'Authorization': 'Token $token',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'Accept-Language': 'fr',
    })
    ..body = jsonEncode(patch);

  final r = await _sendWithRetryReq(req);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('Update refusée: ${r.statusCode} ${r.body}');
  }

  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final eg = EscapeGame.fromJson(j, baseUrl);

  // ⤵️ Important : on purge les listes publiques (anonymes) pour éviter
  // d'afficher un ancien snapshot (ex: devenu privé).
  try {
    await invalidatePublicListsCache();
  } catch (_) {
    // best-effort : on ignore les erreurs de purge de cache
  }

  return eg;
}


  Future<List<GameStep>> fetchSteps(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _get(
      Uri.parse('$baseUrl/api/creator/escapes/$escapeId/steps'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode} ${r.body}');
    }
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => GameStep.fromJson(e, baseUrl)).toList();
  }

  Future<GameStep> createStep(int escapeId, GameStep step) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await _post(
      Uri.parse('$baseUrl/api/creator/escapes/$escapeId/steps'),
      headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json; charset=utf-8'},
      body: step.toPayload(),
    );
    if (r.statusCode != 201) {
      throw Exception('Création step refusée: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return GameStep.fromJson(j, baseUrl);
  }

  Future<GameStep> updateStep(int escapeId, int stepId, Map<String, dynamic> patch) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final req = http.Request('PATCH', Uri.parse('$baseUrl/api/creator/escapes/$escapeId/steps/$stepId'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Token $token',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'Accept-Language': 'fr',
      })
      ..body = jsonEncode(patch);

    final r = await _sendWithRetryReq(req);
    if (r.statusCode != 200) {
      throw Exception('Update step refusée: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return GameStep.fromJson(j, baseUrl);
  }

  Future<void> deleteStep(int escapeId, int stepId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final req = http.Request('DELETE', Uri.parse('$baseUrl/api/creator/escapes/$escapeId/steps/$stepId'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Token $token',
        'Accept': 'application/json',
      });
    final r = await _sendWithRetryReq(req);
    if (r.statusCode != 204) {
      throw Exception('Suppression step refusée: ${r.statusCode} ${r.body}');
    }
  }

  // ---------- SESSIONS ----------
  Future<Map<String, dynamic>> startSession(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final url = '$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/start';
    debugPrint('[START] POST $url');
    final r = await _post(Uri.parse(url), headers: {'Authorization': 'Token $token'});
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw Exception('Start: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSessionState(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final url = '$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/state';
    debugPrint('[STATE] GET  $url');
    final r = await _get(Uri.parse(url), headers: {'Authorization': 'Token $token'});
    if (r.statusCode != 200) {
      throw Exception('State: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> tryGetSessionState(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) return null;
    final r = await _get(
      Uri.parse('$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/state'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw Exception('State: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestHint(int escapeId) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final url = '$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/hint';
    debugPrint('[HINT] POST $url');
    final r = await _post(Uri.parse(url), headers: {'Authorization': 'Token $token'});
    if (r.statusCode != 200) {
      throw Exception('Hint: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitAnswer(
  int escapeId, {
  String? answer,
  int? optionIndex,
  List<List<int>>? pairs, // matching
  bool narration = false,
  int? sessionSeconds, // temps de jeu depuis le dernier sync
}) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  // Construit le payload selon le type
  Map<String, dynamic> payload = {};

  if (narration) {
    // Narration: body vide accepté par l'API
    payload = {};
  } else if (pairs != null) {
    // Association: on n'envoie QUE les paires [[li,ri], ...]
    payload = {'pairs': pairs};
  } else {
    // Texte / Numérique / QCM
    if (answer != null) {
      payload['answer'] = answer;
    }
    if (optionIndex != null) {
      // Le backend accepte 'index' OU 'selected_index' → on envoie les deux par robustesse
      payload['index'] = optionIndex;
      payload['selected_index'] = optionIndex;
    }

    if (payload.isEmpty) {
      // Pas narration et aucun champ fourni → erreur côté client
      throw Exception('Réponse manquante');
    }
  }

  // Ajouter le temps de session si fourni (sync du temps de jeu)
  if (sessionSeconds != null && sessionSeconds > 0) {
    payload['session_seconds'] = sessionSeconds;
  }

  final uri = Uri.parse(
    '$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/answer',
  );

  final r = await _post(
    uri,
    headers: {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: jsonEncode(payload),
  );

  if (r.statusCode != 200) {
    throw Exception('Answer: ${r.statusCode} ${r.body}');
  }
  return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
}



  // ---------- SYNC TIME ----------
  Future<void> syncPlayTime(int escapeId, int additionalSeconds) async {
    final token = await AuthService.instance.getToken();
    if (token == null) return; // silently ignore if not logged in
    if (additionalSeconds <= 0) return; // nothing to sync

    final url = '$baseUrl/api$kEngagementPrefix/escapes/$escapeId/sessions/sync_time';
    debugPrint('[SYNC_TIME] POST $url (additional: $additionalSeconds s)');

    try {
      final r = await _post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: {'additional_seconds': additionalSeconds},
      );
      if (r.statusCode == 200) {
        debugPrint('[SYNC_TIME] OK');
      } else {
        debugPrint('[SYNC_TIME] Failed: ${r.statusCode}');
      }
    } catch (e) {
      debugPrint('[SYNC_TIME] Error: $e');
      // Ignore errors - best effort sync
    }
  }

  // ---------- UPLOAD ----------
  Future<String> uploadImage(XFile xfile) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final uri = Uri.parse('$baseUrl/api/creator/upload_image');

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Token $token'
      ..headers['Accept'] = 'application/json';

    final bytes = await xfile.readAsBytes();
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: xfile.name));

    final streamRes = await _client.send(req);
    final r = await http.Response.fromStream(streamRes);

    if (r.statusCode != 201 && r.statusCode != 200) {
      throw Exception('Upload refusé: ${r.statusCode} ${r.body}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) throw Exception('URL manquante');
    return normalizeImageUrl(url, baseUrl) ?? url;
  }
}
