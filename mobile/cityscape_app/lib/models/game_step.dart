// lib/models/game_step.dart

import '../core/utils/image_utils.dart';

class GameStep {
  final int id;
  final int escapeId;

  int order;
  String title;
  String text;
  double? latitude;
  double? longitude;
  String? imageUrl;
  String imageCredit; // crédit/source de l'image, '' si absent

  /// 'text' | 'mcq' | 'numeric' | 'matching' | 'narration'
  final String answerType;

  // Texte libre / numérique (stock côté back dans answer_text)
  String answerText;

  // QCM
  List<String> options;
  int? correctIndex;

  // Association (matching)
  final List<String> matchLeft;             // mapping: matching_left
  final List<String> matchRight;            // mapping: matching_right
  final List<List<int>> matchPairs;         // (solution côté éditeur)

  // Getters de compatibilité pour l'existant (s.left / s.right)
  List<String> get left => matchLeft;
  List<String> get right => matchRight;

  // Indices (compat + nouveau)
  String hint;                 // compat "indice unique"
  List<String> hints;          // nouveau "multi-indices"
  int hintPenalty;

  // Affichage de la carte pour cette étape
  bool showLocation;

  GameStep({
    required this.id,
    required this.escapeId,
    required this.order,
    required this.title,
    required this.answerType,
    this.text = '',
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.imageCredit = '',
    this.answerText = '',
    List<String>? options,
    this.correctIndex,
    this.matchLeft = const [],
    this.matchRight = const [],
    this.matchPairs = const [],
    this.hint = '',
    List<String>? hints,
    this.hintPenalty = 0,
    this.showLocation = true,
  })  : options = options ?? const [],
        hints = hints ?? const [];

  factory GameStep.fromJson(Map<String, dynamic> j, String baseUrl) {
    // Pairs: [[li,ri], ...] OU [{"left_index": li, "right_index": ri}, ...]
    final rawPairs = j['match_pairs'] ?? j['matching_pairs'] ?? j['pairs'];
    final parsedPairs = <List<int>>[];
    if (rawPairs is List) {
      for (final p in rawPairs) {
        if (p is List && p.length == 2) {
          final li = (p[0] as num).toInt();
          final ri = (p[1] as num).toInt();
          parsedPairs.add([li, ri]);
        } else if (p is Map && p['left_index'] != null && p['right_index'] != null) {
          final li = (p['left_index'] as num).toInt();
          final ri = (p['right_index'] as num).toInt();
          parsedPairs.add([li, ri]);
        }
      }
    }

    // Hints: liste prioritaire, sinon accepte aussi une string unique; fallback sur 'hint' (legacy)
    List<String> parsedHints = const <String>[];
    final rawHints = j['hints'];
    if (rawHints is List) {
      parsedHints = rawHints
          .map((e) => '$e')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (rawHints is String) {
      final t = rawHints.trim();
      if (t.isNotEmpty) parsedHints = <String>[t];
    }
    if (parsedHints.isEmpty) {
      final single = (j['hint'] as String?)?.trim();
      if (single != null && single.isNotEmpty) {
        parsedHints = <String>[single];
      }
    }

    return GameStep(
      id: (j['id'] as num).toInt(),
      escapeId: (j['escape'] as num?)?.toInt() ?? (j['escape_id'] as num?)?.toInt() ?? 0,
      order: (j['order'] as num).toInt(),
      title: (j['title'] ?? '') as String,
      text: (j['text'] ?? j['prompt'] ?? '') as String,
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      imageUrl: normalizeImageUrl(j['image_url'] as String?, baseUrl),
      imageCredit: (j['image_credit'] ?? '') as String,
      answerType: (j['answer_type'] ?? 'text') as String,
      answerText: (j['answer_text'] ?? '') as String,
      options: ((j['options'] as List?) ?? const []).map((e) => '$e').toList(),
      correctIndex: j['correct_index'] == null ? null : (j['correct_index'] as num).toInt(),

      // Matching
      matchLeft: ((j['matching_left'] ?? j['match_left'] ?? j['left'] ?? const []) as List)
          .map((e) => '$e').toList(),
      matchRight: ((j['matching_right'] ?? j['match_right'] ?? j['right'] ?? const []) as List)
          .map((e) => '$e').toList(),
      matchPairs: parsedPairs,

      // Hints
      hint: (j['hint'] ?? '') as String,     // legacy (on conserve)
      hints: parsedHints,                     // multi-indices normalisés
      hintPenalty: (j['hint_penalty'] is num) ? (j['hint_penalty'] as num).toInt() : 0,

      // Affichage carte
      showLocation: j['show_location'] != false,  // true par défaut
    );
  }

  Map<String, dynamic> toPayload() {
    final m = <String, dynamic>{
      'escape': escapeId,
      'order': order,
      'title': title,
      'text': text,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
      'image_credit': imageCredit,
      'answer_type': answerType,
      'hint_penalty': hintPenalty,
      'show_location': showLocation,
    };

    // Multi-indices prioritaire ; jamais de null pour "hint"
    if (hints.isNotEmpty) {
      m['hints'] = hints;
      m['hint']  = hint.trim().isNotEmpty ? hint : '';
    } else {
      m['hints'] = <String>[];
      m['hint']  = hint.trim().isNotEmpty ? hint : '';
    }

    switch (answerType) {
      case 'text':
      case 'cesar':
        m['answer_text']   = answerText;   // requis
        m['options']       = <String>[];
        m['correct_index'] = null;
        m['match_left']    = <String>[];
        m['match_right']   = <String>[];
        m['match_pairs']   = <dynamic>[];
        break;

      case 'mcq':
        m['answer_text']   = '';
        m['options']       = options;
        m['correct_index'] = correctIndex;
        m['match_left']    = <String>[];
        m['match_right']   = <String>[];
        m['match_pairs']   = <dynamic>[];
        break;

      case 'numeric':
        m['answer_text']   = answerText;
        m['options']       = <String>[];
        m['correct_index'] = null;
        m['match_left']    = <String>[];
        m['match_right']   = <String>[];
        m['match_pairs']   = <dynamic>[];
        break;

      case 'matching':
        m['answer_text']   = '';
        m['options']       = <String>[];
        m['correct_index'] = null;
        m['match_left']    = matchLeft;
        m['match_right']   = matchRight;
        m['match_pairs']   = matchPairs;   // utile côté éditeur
        break;

      case 'narration':
        // Non interactivé : on neutralise tout + pas d'indices
        m['answer_text']   = '';
        m['options']       = <String>[];
        m['correct_index'] = null;
        m['match_left']    = <String>[];
        m['match_right']   = <String>[];
        m['match_pairs']   = <dynamic>[];
        m['hints']         = <String>[];   // vide
        m['hint']          = '';           // JAMAIS null
        m['hint_penalty']  = 0;
        break;

      default:
        // fallback compat
        m['answer_text']   = answerText;
        m['options']       = options;
        m['correct_index'] = correctIndex;
        m['match_left']    = <String>[];
        m['match_right']   = <String>[];
        m['match_pairs']   = <dynamic>[];
        break;
    }

    return m;
  }
}
