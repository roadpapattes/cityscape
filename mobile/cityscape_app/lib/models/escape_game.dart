// lib/models/escape_game.dart

import '../core/utils/type_utils.dart';
import '../core/utils/image_utils.dart';

/// Retourne `null` si la chaîne est nulle ou vide après trim.
String? _asNonEmptyString(dynamic v) {
  if (v == null) return null;
  final s = (v is String) ? v.trim() : v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Normalise quelques anciens états éventuels.
String _normalizeStatus(dynamic v) {
  final s = (v is String ? v : v?.toString() ?? '').trim().toLowerCase();
  switch (s) {
    case 'refused':
      return 'rejected';
    case 'draft':
    case 'submitted':
    case 'published':
    case 'rejected':
      return s;
    default:
      return s.isEmpty ? 'draft' : s;
  }
}

class EscapeGame {
  final int id;
  final String title;
  final String city;
  final double latitude;
  final double longitude;
  final double rating;
  final int durationMinutes;
  final int difficulty;
  final String status;         // draft | submitted | published | rejected
  final String? createdAt;
  final String? rejectReason;  // null si vide
  final String? imageUrl;
  final String description;
  final String victoryMessage;

  bool isPrivate;
  List<String> allowedUsers;

  final bool penalizeWrongAnswers;
  final int wrongAnswerPenalty;

  EscapeGame({
    required this.id,
    required this.title,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.durationMinutes,
    required this.difficulty,
    required this.status,
    this.createdAt,
    this.rejectReason,
    this.imageUrl,
    this.description = '',
    this.victoryMessage = '',
    this.penalizeWrongAnswers = false,
    this.wrongAnswerPenalty = 0,
    this.isPrivate = false,
    List<String>? allowedUsers,
  }) : allowedUsers = allowedUsers ?? const [];

  factory EscapeGame.fromJson(Map<String, dynamic> j, String baseUrl) {
    // Normalise l'URL puis mappe '' -> null (car imageUrl est nullable)
    final normalized = normalizeImageUrl(j['image_url'] as String?, baseUrl);
    final img = (normalized.isEmpty) ? null : normalized;

    return EscapeGame(
      id: asInt(j['id']),
      title: (j['title'] ?? j['name'] ?? '') as String,
      city: (j['city'] ?? '') as String,
      latitude: asDouble(j['latitude'] ?? j['lat']),
      longitude: asDouble(j['longitude'] ?? j['lon'] ?? j['lng']),
      rating: asDouble(j['rating'] ?? j['avg_rating']),
      durationMinutes: asInt(j['duration_minutes'] ?? j['duration'] ?? 60, 60),
      difficulty: asInt(j['difficulty'] ?? 1, 1),
      status: _normalizeStatus(j['status'] ?? 'published'),
      createdAt: j['created_at'] as String?,
      rejectReason: _asNonEmptyString(
        j['reject_reason'] ??
        j['rejection_reason'] ??
        j['reason'] ??
        j['moderation_reason'],
      ),
      imageUrl: img,
      description: (j['description'] ?? '') as String,
      victoryMessage: (j['victory_message'] ?? '') as String,
      penalizeWrongAnswers: (j['penalize_wrong_answers'] as bool?) ?? false,
      wrongAnswerPenalty: asInt(j['wrong_answer_penalty'] ?? 0, 0),
      isPrivate: (j['is_private'] == true),
      allowedUsers: ((j['allowed_usernames'] as List?) ??
               (j['allowed_users'] as List?) ??
               const <dynamic>[])
              .map((e) => '$e')
              .toList(),
    );
  }
}
