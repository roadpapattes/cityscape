
// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';


int _asInt(dynamic v, [int? fallback]) {
  if (v == null) return fallback ?? 0;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? (fallback ?? 0);
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? fallback;
}


/// Transforme les URL d'images backend en URL valides côté app.
/// - remplace 10.0.2.2/localhost/127.0.0.1 par l'hôte/port de baseUrl
/// - préfixe les chemins relatifs avec baseUrl
/// - renvoie toujours une String non nulle
String normalizeImageUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  try {
    final base = Uri.parse(baseUrl);
    final parsed = Uri.parse(url);

    // Cas 1: URL absolue
    if (parsed.hasScheme) {
      // Si c'est 10.0.2.2 / localhost / 127.0.0.1 => remapper vers host/port de baseUrl
      if (parsed.host == '10.0.2.2' || parsed.host == 'localhost' || parsed.host == '127.0.0.1') {
        final remapped = parsed.replace(
          scheme: base.scheme,
          host: base.host,
          port: base.hasPort ? base.port : null,
        );
        return remapped.toString();
      }
      return url; // autre domaine déjà correct
    }

    // Cas 2: chemin relatif (ex: /media/...)
    final resolved = base.resolve(url.startsWith('/') ? url.substring(1) : url);
    return resolved.toString();
  } catch (_) {
    // En cas d'URL mal formée, renvoyer tout de même quelque chose d'affichable
    return url ?? '';
  }
}

/// Miniature responsive qui conserve les proportions.
/// - Encapsulée dans une boîte max 180 px de haut.
/// - Si url vide → placeholder.
Widget _imageThumb(String? url) {
  final u = url?.trim();
  final has = (u != null && u.isNotEmpty);
  return Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 180),
    decoration: BoxDecoration(
      color: has ? const Color(0xFFF7F7F7) : const Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x11000000)),
    ),
    alignment: Alignment.center,
    child: has
        ? FittedBox(
            fit: BoxFit.contain,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                u!,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Impossible de charger l’image'),
                ),
              ),
            ),
          )
        : const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Aucune image'),
          ),
  );
}

// ---------- Creator feedback (bottom sheet) ----------
Future<void> openCreatorFeedbackSheet(
  BuildContext context, {
  int? escapeId,
  int? stepId,
  String? page,
}) async {
  final txt = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final padding = EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
        left: 16, right: 16, top: 16,
      );
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Envoyer un feedback créateur',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: txt,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Décris le bug ou l’amélioration souhaitée…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer'),
                  onPressed: () async {
                    final message = txt.text.trim();
                    if (message.length < 10) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Merci de détailler un peu (≥ 10 caractères).')),
                      );
                      return;
                    }
                    try {
                      // 👉 Utilise ton ApiService si dispo
                      await ApiService.instance.sendCreatorFeedback(
                        message: message,
                        escapeId: escapeId,
                        stepId: stepId,
                        page: page ?? 'creator_hub',
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Merci pour ton feedback !')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Envoi impossible : $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ouvre le cache Hive + charge l’auth depuis les prefs
  await ApiService.instance.initCache();
  await AuthService.instance.loadFromPrefs();

  runApp(const EscapeCityApp());
}

/// Emulateur Android classique => 10.0.2.2
/// (Si tu fais `adb reverse tcp:8000 tcp:8000`, bascule en 127.0.0.1)
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://roadpapattes.synology.me',
);
const String kEngagementPrefix = ""; // sessions, hints, answers, rating
const String kAuthPrefix       = ""; // auth stays at /api/auth/...
const double kDefaultRadiusKm = 20;

// Asset du logo (déclaré dans pubspec.yaml)
const String kLogoAsset = 'assets/logo.png';

// Valeur de statut utilisée par l'API pour un escape refusé.
// Adapte si besoin: 'refused', 'rejected', 'denied', etc.
// const String kStatusRejected = 'rejected';


class EscapeCityApp extends StatelessWidget {
  const EscapeCityApp({super.key});

  static const brandSeed = Color(0xFF3D7AFF); // ← ta couleur de marque

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CityScape',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // clair/sombre selon l’OS
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: brandSeed,
        splashFactory: InkSparkle.splashFactory,
        visualDensity: VisualDensity.adaptivePlatformDensity,

        // petits réglages UI (facultatif, mais joli)
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          filled: true,
        ),
        cardTheme: const CardThemeData(
  elevation: 0,
  margin: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  ),
),
        chipTheme: const ChipThemeData(
          shape: StadiumBorder(),
          side: BorderSide.none,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            side: const BorderSide(width: 1),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: brandSeed,
        brightness: Brightness.dark,
        splashFactory: InkSparkle.splashFactory,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashBootstrap(),
    );
  }
}


class MainHome extends StatefulWidget {
  const MainHome({super.key});
  @override
  State<MainHome> createState() => _MainHomeState();
}

class GameTimer extends ChangeNotifier {
  static final GameTimer instance = GameTimer._();
  GameTimer._();

  DateTime? _startAt;
  Duration _penalties = Duration.zero;
  Timer? _ticker;

  bool get isRunning => _startAt != null;

  /// Temps écoulé + pénalités
  Duration get elapsed {
    if (_startAt == null) return _penalties;
    final base = DateTime.now().difference(_startAt!);
    return base + _penalties;
  }

  String get elapsedText {
    final d = elapsed;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${_2(h)}:${_2(m)}:${_2(s)}' : '${_2(m)}:${_2(s)}';
  }

  /// Démarre si pas déjà en cours (idempotent). Ne réinitialise PAS si déjà démarré.
  void start() {
    if (isRunning) return;
    _startAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners(); // tick immédiat
  }

  /// Met en pause sans remettre les pénalités à zéro.
  void pause() {
    _ticker?.cancel();
    _ticker = null;
    _startAt = null;
    notifyListeners();
  }

  /// Stoppe et remet à zéro.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _startAt = null;
    _penalties = Duration.zero;
    notifyListeners();
  }

  /// Ajoute une pénalité en secondes (appliquée immédiatement à l’affichage).
  void addPenaltySeconds(int seconds) {
    if (seconds <= 0) return;
    _penalties += Duration(seconds: seconds);
    notifyListeners();
  }

  /// Pratique : pénalité en minutes.
  void addPenaltyMinutes(int minutes) {
    if (minutes <= 0) return;
    _penalties += Duration(minutes: minutes);
    notifyListeners();
  }

  /// Force la pénalité courante à une valeur en minutes (depuis le serveur).
  void syncPenaltyMinutes(int minutes) {
    final m = minutes < 0 ? 0 : minutes;
    _penalties = Duration(minutes: m);
    notifyListeners();
  }

  /// Alias pratique si un jour tu veux sync en secondes.
  void syncPenaltySeconds(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    _penalties = Duration(seconds: s);
    notifyListeners();
  }

  /// Renvoie le texte final et remet à zéro.
  String finishAndGetResult() {
    final txt = elapsedText;
    stop();
    return txt;
  }

  String _2(int n) => n.toString().padLeft(2, '0');
}



class TimerBadge extends StatelessWidget {
  const TimerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GameTimer.instance,
      builder: (_, __) {
        if (!GameTimer.instance.isRunning) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            GameTimer.instance.elapsedText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}


class _CacheEntry {
  final Uint8List body;
  final String? etag;
  final String? contentType;
  final int fetchedAtMs;

  _CacheEntry(this.body, this.etag, this.contentType, this.fetchedAtMs);

  Map<String, dynamic> toMap() => {
    'body': body,
    'etag': etag,
    'ct': contentType,
    'at': fetchedAtMs,
  };

  static _CacheEntry? fromMap(dynamic m) {
    if (m is! Map) return null;
    final body = m['body'];
    if (body is! Uint8List) return null;
    return _CacheEntry(
      body,
      m['etag'] as String?,
      m['ct'] as String?,
      (m['at'] as num?)?.toInt() ?? 0,
    );
  }
}


class _MainHomeState extends State<MainHome> {
  int _tabIndex = 1;

  @override
  void initState() {
    super.initState();
    AuthService.instance.loadFromPrefs();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const ListPage(), const MapPage(), const CreatorPage()];
    return Scaffold(
      appBar: AppBar(
        title: _TitleWithUser(),
        actions: [
          ValueListenableBuilder<String?>(
            valueListenable: AuthService.instance.tokenNotifier,
            builder: (context, token, _) {
              if (token == null) {
                return IconButton(
                  tooltip: 'Se connecter',
                  icon: const Icon(Icons.login),
                  onPressed: () => _openAuthDialog(context),
                );
              }
              return IconButton(
                tooltip: 'Se déconnecter',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await AuthService.instance.logout();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Déconnecté')),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: AuthService.instance.tokenNotifier,
            builder: (context, token, _) {
              if (token != null) return const SizedBox.shrink();
              return MaterialBanner(
                content: const Text("Vous n'êtes pas connecté."),
                leading: const Icon(Icons.person_outline),
                actions: [
                  TextButton(
                    onPressed: () => _openAuthDialog(context),
                    child: const Text('Se connecter'),
                  ),
                ],
              );
            },
          ),
          Expanded(child: pages[_tabIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Liste'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Carte'),
          NavigationDestination(icon: Icon(Icons.edit_note_outlined), label: 'Créateur'),
        ],
      ),
    );
  }

  void _openAuthDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _AuthDialog());
  }
}

class _TitleWithUser extends StatefulWidget {
  const _TitleWithUser();
  @override
  State<_TitleWithUser> createState() => _TitleWithUserState();
}

class _TitleWithUserState extends State<_TitleWithUser> {
  String? _username;

  @override
  void initState() {
    super.initState();
    AuthService.instance.tokenNotifier.addListener(_onAuthChange);
    _refreshUsername();
  }

  @override
  void dispose() {
    AuthService.instance.tokenNotifier.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() => _refreshUsername();

  Future<void> _refreshUsername() async {
    final token = AuthService.instance.tokenNotifier.value;
    if (token == null) {
      setState(() => _username = null);
      return;
    }
    try {
      final me = await ApiService.instance.fetchMe();
      setState(() {
        _username = (me?['username'] as String?) ?? (me?['user'] as String?);
      });
    } catch (_) {
      setState(() => _username = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _username == null ? 'CityScape' : 'CityScape | $_username';
    return Text(text, overflow: TextOverflow.ellipsis, maxLines: 1);
  }
}

/* ============================
   MODELS + SERVICES
============================ */

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


  factory EscapeGame.fromJson(Map<String, dynamic> j) {
    // Helpers globaux déjà présents dans ton main.dart :
    // int _asInt(dynamic v, [int? fallback])
    // double _asDouble(dynamic v, [double fallback = 0])
    // String normalizeImageUrl(String? url)

    // Normalise l’URL puis mappe '' -> null (car imageUrl est nullable)
    final normalized = normalizeImageUrl(j['image_url'] as String?);
    final img = (normalized.isEmpty) ? null : normalized;

    return EscapeGame(
      id: _asInt(j['id']),
      title: (j['title'] ?? j['name'] ?? '') as String,
      city: (j['city'] ?? '') as String,
      latitude: _asDouble(j['latitude'] ?? j['lat']),
      longitude: _asDouble(j['longitude'] ?? j['lon'] ?? j['lng']),
      rating: _asDouble(j['rating'] ?? j['avg_rating']),
      durationMinutes: _asInt(j['duration_minutes'] ?? j['duration'] ?? 60, 60),
      difficulty: _asInt(j['difficulty'] ?? 1, 1),
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
      wrongAnswerPenalty: _asInt(j['wrong_answer_penalty'] ?? 0, 0),
	  isPrivate: (j['is_private'] == true),
      allowedUsers: ((j['allowed_usernames'] as List?) ??
               (j['allowed_users'] as List?) ??
               const <dynamic>[])
              .map((e) => '$e')
              .toList(),
    );
  }
}

/// Helpers locaux légers (pas de doublon avec _asInt/_asDouble globaux)

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

class CommentItem {
  final String user;
  final int stars;
  final String comment;
  final String? createdAt;
  CommentItem({required this.user, required this.stars, required this.comment, this.createdAt});
  factory CommentItem.fromJson(Map<String, dynamic> j) => CommentItem(
        user: (j['user'] ?? 'Anonyme') as String,
        stars: (j['stars'] ?? 0) as int,
        comment: (j['comment'] ?? j['text'] ?? '') as String,
        createdAt: j['created_at'] as String?,
      );
}

class GameStep {
  final int id;
  final int escapeId;

  int order;
  String title;
  String text;
  double? latitude;
  double? longitude;
  String? imageUrl;

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

  // Getters de compatibilité pour l’existant (s.left / s.right)
  List<String> get left => matchLeft;
  List<String> get right => matchRight;

  // Indices (compat + nouveau)
  String hint;                 // compat “indice unique”
  List<String> hints;          // nouveau “multi-indices”
  int hintPenalty;

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
    this.answerText = '',
    List<String>? options,
    this.correctIndex,
    this.matchLeft = const [],
    this.matchRight = const [],
    this.matchPairs = const [],
    this.hint = '',
    List<String>? hints,
    this.hintPenalty = 0,
  })  : options = options ?? const [],
        hints = hints ?? const [];

  factory GameStep.fromJson(Map<String, dynamic> j) {
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
    imageUrl: normalizeImageUrl(j['image_url'] as String?),
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
    'answer_type': answerType,
    'hint_penalty': hintPenalty,
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
      // Non interactivé : on neutralise tout + pas d’indices
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
    final cached = _CacheEntry.fromMap(_cacheBox.get(cacheKey));
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
    _cacheBox.put(cacheKey, _CacheEntry(bytes, newEtag, ct, now).toMap());

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
	return EscapeGame.fromJson(j);
}

  Future<List<EscapeGame>> fetchAll() async {
  final token = await AuthService.instance.getToken();
  final uri = Uri.parse('$baseUrl/api/escapes');

  if (token != null) {
    // Authentifié : **on envoie le token** pour que l’API filtre correctement
    final r = await _get(uri, headers: {
      'Authorization': 'Token $token',
      'Accept': 'application/json',
    });
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
  } else {
    // Anonyme : cache séparé
    final list = await _getJsonListCached(
      cacheKey: 'escapes_all_v1:anon',
      uri: uri,
      ttl: const Duration(hours: 24),
    );
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
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
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
  } else {
    final key = 'nearby_v1:anon:${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)},$radiusKm';
    final list = await _getJsonListCached(
      cacheKey: key,
      uri: uri,
      ttl: const Duration(minutes: 30),
    );
    return list.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
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
        // on ne passe pas 'all' à l’API (=> pas de filtre)
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
    return data.map<EscapeGame>((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
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

    // 1) Nouveau flux : POST sur l’action DRF (avec ET sans slash)
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

      // 404/405/301/308 -> on tentera l’autre variante / le fallback
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
      if (r.statusCode == 404) continue; // essaye l’autre forme
      // 403 ici = “admin ne peut pas modifier”, on n’insiste pas si l’action a échoué
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
  return EscapeGame.fromJson(j);
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
  final eg = EscapeGame.fromJson(j);

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
    return L.map((e) => GameStep.fromJson(e)).toList();
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
    return GameStep.fromJson(j);
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
    return GameStep.fromJson(j);
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
}) async {
  final token = await AuthService.instance.getToken();
  if (token == null) throw Exception('Non connecté');

  // Construit le payload selon le type
  Map<String, dynamic> payload = {};

  if (narration) {
    // Narration: body vide accepté par l’API
    payload = {};
  } else if (pairs != null) {
    // Association: on n’envoie QUE les paires [[li,ri], ...]
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
    return normalizeImageUrl(url) ?? url;
  }
}


class UserMe {
  final String username;
  final bool isStaff;
  final bool isSuperuser;

  const UserMe({
    required this.username,
    required this.isStaff,
    required this.isSuperuser,
  });

  factory UserMe.fromJson(Map<String, dynamic> j) => UserMe(
        username: j['username'] as String? ?? '',
        isStaff: j['is_staff'] == true,
        isSuperuser: j['is_superuser'] == true,
      );

  bool get isAdmin => isStaff || isSuperuser;
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  final tokenNotifier = ValueNotifier<String?>(null);
  final meNotifier = ValueNotifier<UserMe?>(null);

  Future<UserMe>? _meLoading; // <-- déduplication en cours

  Future<void> loadFromPrefs() async {
    final sp = await SharedPreferences.getInstance();
    tokenNotifier.value = sp.getString('auth_token');
    await ApiService.instance.loadLocalModeration();
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
}

class PastStepsPage extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  const PastStepsPage({super.key, required this.steps});

  Widget _answerBlock(Map<String, dynamic>? ans) {
    if (ans == null) return const SizedBox.shrink();

    final type = ans['type'] as String?;
    switch (type) {
      case 'text':
      case 'numeric': {
        final v = (ans['value'] ?? '') as String;
        if (v.isEmpty) return const SizedBox.shrink();
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Réponse donnée : ',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }
      case 'mcq': {
        final label = (ans['selected_label'] ?? '') as String;
        final idx = ans['selected_index'];
        final suffix = (idx is int) ? ' (#${idx + 1})' : '';
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Choix sélectionné : ${label.isNotEmpty ? label : '(option)'}$suffix',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      case 'matching': {
        final pv = (ans['pairs_verbose'] as List?)?.cast<Map<String, dynamic>>();
        if (pv == null || pv.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Associations :', style: TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 4),
              for (final p in pv) Text('• ${p['left'] ?? 'A'}  →  ${p['right'] ?? 'B'}'),
            ],
          ),
        );
      }
      case 'narration':
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Étape narrative (aucune réponse requise).',
              style: TextStyle(fontStyle: FontStyle.italic)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Étapes passées')),
      body: steps.isEmpty
          ? const Center(child: Text('Aucune étape passée pour le moment.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: steps.length,
              itemBuilder: (_, i) {
                final s = steps[i];
                final title = (s['title'] ?? '') as String;
                final text  = (s['text'] ?? '') as String;
                final img   = (s['image_url'] ?? '') as String;

                // --- Multi-indices ---
                final revealedHints = (s['revealed_hints'] as List?)
                        ?.map((e) => '$e')
                        .where((t) => t.trim().isNotEmpty)
                        .toList() ??
                    const <String>[];
                final hintsTotal = (s['hints_total'] as int?) ?? 0;
                final hintsUsed  = (s['hints_used']  as int?) ?? revealedHints.length;

                // Réponse donnée (si le backend la fournit dans "answer")
                final ans = (s['answer'] as Map?)?.cast<String, dynamic>();

                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                        ],
                        if (img.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              normalizeImageUrl(img),
                              fit: BoxFit.cover,
                              height: 160,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                height: 160,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.image_not_supported_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (text.isNotEmpty) ...[
                          Text(text),
                          const SizedBox(height: 8),
                        ],

                        // ---- Réponse donnée ----
                        _answerBlock(ans),

                        const SizedBox(height: 8),

                        // ---- Indices ----
                        if (revealedHints.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withOpacity(.25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.secondary.withOpacity(.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Indices révélés (${hintsUsed}/${hintsTotal})',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                for (int k = 0; k < revealedHints.length; k++)
                                  Text('• Indice ${k + 1} : ${revealedHints[k]}'),
                              ],
                            ),
                          ),
                        ] else ...[
                          Text(
                            hintsTotal > 0
                                ? 'Aucun indice consulté (0/$hintsTotal)'
                                : 'Aucun indice disponible',
                            style: TextStyle(color: cs.outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}




/* ============================
   WIDGETS : LISTE
============================ */

enum SortMode { rating, distance }

class ListPage extends StatefulWidget {
  const ListPage({super.key});
  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _api = ApiService.instance;
  final _searchCtrl = TextEditingController();
  bool _favOnly = false;

  List<EscapeGame> _all = [];
  List<EscapeGame> _items = [];
  Set<int> _favorites = {};
  SortMode _sort = SortMode.rating;
  Position? _pos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _items = _applyFiltersAndSort(_all);
      });
    });
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadFavs();
    await _loadLocation();
    await _loadAll();
  }

  Future<void> _loadFavs() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getStringList('fav_ids') ?? <String>[];
    _favorites = s.map((e) => int.tryParse(e) ?? -1).where((e) => e >= 0).toSet();
  }

  Future<void> _saveFavs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('fav_ids', _favorites.map((e) => e.toString()).toList());
  }

  Future<void> _loadLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      _pos = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final L = await _api.fetchAll();
      setState(() {
        _all = L;
        _items = _applyFiltersAndSort(_all);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<EscapeGame> _applyFiltersAndSort(List<EscapeGame> source) {
    var out = [...source];

    // 1) recherche
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((e) {
        final t = e.title.toLowerCase();
        final c = e.city.toLowerCase();
        return t.contains(q) || c.contains(q);
      }).toList();
    }

    // 2) favoris
    if (_favOnly) {
      out = out.where((e) => _favorites.contains(e.id)).toList();
    }

    // 3) tri
    switch (_sort) {
      case SortMode.rating:
        out.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case SortMode.distance:
        if (_pos != null) {
          double d(EscapeGame e) => _distanceKm(
              _pos!.latitude, _pos!.longitude, e.latitude, e.longitude);
          out.sort((a, b) => d(a).compareTo(d(b)));
        }
        break;
    }
    return out;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * R * math.asin(math.sqrt(a));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  void _toggleFav(int id) async {
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
      } else {
        _favorites.add(id);
      }
      _items = _applyFiltersAndSort(_all);
    });
    await _saveFavs();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildListHeader(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = _items[i];
                      final fav = _favorites.contains(e.id);
                      final dist = (_pos == null)
                          ? null
                          : _distanceKm(_pos!.latitude, _pos!.longitude,
                                  e.latitude, e.longitude)
                              .toStringAsFixed(1);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            e.rating > 0 ? e.rating.toStringAsFixed(1) : '–',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(e.title),
                        subtitle: Text(
                          '${e.city} • durée ${e.durationMinutes} min • diff ${e.difficulty}'
                          '${dist != null ? " • $dist km" : ""}',
                        ),
                        trailing: IconButton(
                          icon: Icon(fav ? Icons.star : Icons.star_border),
                          color: fav ? Colors.amber : null,
                          onPressed: () => _toggleFav(e.id),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EscapeDetailsPage(escape: e),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Escapes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              DropdownButton<SortMode>(
                value: _sort,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _sort = v;
                    _items = _applyFiltersAndSort(_all);
                  });
                },
                items: [
                  const DropdownMenuItem(
                    value: SortMode.rating,
                    child: Text('Par note'),
                  ),
                  DropdownMenuItem(
                    value: SortMode.distance,
                    enabled: _pos != null,
                    child: const Text('Par distance'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher (titre, ville)',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _favOnly,
                label: const Text('Favoris'),
                onSelected: (v) {
                  setState(() {
                    _favOnly = v;
                    _items = _applyFiltersAndSort(_all);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================
   WIDGETS : CARTE (simplifiée)
============================ */

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // Cache des icônes de marqueurs pour éviter de régénérer à chaque rebuild
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  final _api = ApiService.instance;

  GoogleMapController? _controller;
  // Centre de la carte (évolue quand on se déplace)
  LatLng _center = const LatLng(48.8566, 2.3522); // Paris
  // Position réelle de l’utilisateur (si dispo)
  LatLng? _userLoc;

  // Données et rendus
  List<EscapeGame> _items = [];
  Set<Marker> _markers = {};
  EscapeGame? _selected;
  bool _loading = true;
  bool _didAutoCenter = false;

  // Cache d’icônes générées à la volée (bitmap)
  final Map<String, BitmapDescriptor> _iconCache = {};
  
  // Couleurs pastilles
static const kClusterBlue = Color(0xFF0B3D91); // bleu foncé pour clusters
static const kEscapeGreen = Color(0xFF40826D); // vert pour escapes individuels

  // Paramètres de clustering
  double _zoom = 12; // zoom courant
  static const double _gridSizePx = 80; // taille de la grille de cluster (pixels)
  static const double _singleSize = 44; // diamètre pastille single
  static const double _clusterSize = 64; // diamètre pastille cluster

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _setInitialCenterFromLocation();
    await _refreshMapData();
    if (mounted) setState(() => _loading = false);
  }

  bool _looksLikeAndroidEmuLatLng(double lat, double lon) {
  // Heuristique: l’émulateur Android par défaut renvoie ~ (37.4219983, -122.084)
  const mvLat = 37.4219983;
  const mvLon = -122.084;
  const tol = 0.02; // ~2 km de tolérance

  return ( (lat - mvLat).abs() < tol && (lon - mvLon).abs() < tol );
}


  Future<void> _setInitialCenterFromLocation() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      // Pas de géoloc => centre Paris
      _userLoc = const LatLng(48.8566, 2.3522);
      _center = _userLoc!;
      return;
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      // Refus => centre Paris
      _userLoc = const LatLng(48.8566, 2.3522);
      _center = _userLoc!;
      return;
    }

    final pos = await Geolocator.getCurrentPosition();

    // Si ça ressemble fortement à l’émulateur Android (Google HQ),
    // on fige Paris ; sinon, on prend la vraie position.
    if (_looksLikeAndroidEmuLatLng(pos.latitude, pos.longitude)) {
      _userLoc = const LatLng(48.8566, 2.3522);
    } else {
      _userLoc = LatLng(pos.latitude, pos.longitude);
    }
    _center = _userLoc!;
  } catch (_) {
    // En cas d’erreur, on reste sur Paris
    _userLoc = const LatLng(48.8566, 2.3522);
    _center = _userLoc!;
  }
}

  Future<void> _refreshMapData() async {
  try {
    var items = await _api.fetchAll(); // 🔥 charge tout au lieu de nearby
    _items = items;
    debugPrint('MAP data: count=${_items.length}');
    if (_items.isNotEmpty) {
      final e = _items.first;
      debugPrint('First item: ${e.title} at ${e.latitude}, ${e.longitude}');
    }
    await _rebuildMarkers();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur carte: $e')),
    );
  }
}



  // ============================
  // Clustering
  // ============================

  Future<void> _rebuildMarkers() async {
  // Filtrer par zone visible et regrouper en clusters selon le zoom courant,
  // puis dessiner des icônes custom (bleu = cluster, vert = escape unique).
  final ctrl = _controller;
  if (ctrl == null) return;

  // 1) Déterminer la zone visible
  LatLngBounds? b;
  try {
    b = await ctrl.getVisibleRegion();
  } catch (_) {
    b = null;
  }

  final List<EscapeGame> visible = <EscapeGame>[];
  if (b == null) {
    visible.addAll(_items);
  } else {
    final sw = b.southwest;
    final ne = b.northeast;

    bool inBounds(EscapeGame e) {
      final lat = e.latitude, lon = e.longitude;
      final latOk = lat >= sw.latitude && lat <= ne.latitude;

      // Cas normal (pas d'antiméridien)
      if (sw.longitude <= ne.longitude) {
        return latOk && lon >= sw.longitude && lon <= ne.longitude;
      }
      // Cas rare (antiméridien traversé) : [sw.lon..180] U [-180..ne.lon]
      return latOk && (lon >= sw.longitude || lon <= ne.longitude);
    }

    for (final e in _items) {
      if (inBounds(e)) visible.add(e);
    }
  }

  // 2) Bucketiser en grille écran
  final Map<String, List<EscapeGame>> buckets = {};
  final double scale = math.pow(2.0, _zoom).toDouble();
  final double worldSize = 256.0 * scale;

  double lonToX(double lon) => (lon + 180.0) / 360.0 * worldSize;
  double latToY(double lat) {
    final latRad = lat * math.pi / 180.0;
    return (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * worldSize;
  }

  for (final e in visible) {
    final x = lonToX(e.longitude);
    final y = latToY(e.latitude);
    final cx = (x / _gridSizePx).floor();
    final cy = (y / _gridSizePx).floor();
    final key = '$cx:$cy';
    (buckets[key] ??= <EscapeGame>[]).add(e);
  }

  // 3) Produire les marqueurs
  final Set<Marker> out = {};

  for (final entry in buckets.entries) {
    final list = entry.value;
    if (list.length == 1) {
      final e = list.first;
      final icon = await _iconForEscape(e);;
      out.add(Marker(
        markerId: MarkerId('e_${e.id}'),
        position: LatLng(e.latitude, e.longitude),
        icon: icon,
        infoWindow: InfoWindow(
          title: e.title,
          snippet: e.city,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EscapeDetailsPage(escape: e)),
            );
          },
        ),
        onTap: () => setState(() => _selected = e),
      ));
    } else {
      // Cluster
      final lat = list.map((e) => e.latitude).reduce((a, b) => a + b) / list.length;
      final lon = list.map((e) => e.longitude).reduce((a, b) => a + b) / list.length;
      final count = list.length;

      final icon = await _iconForCluster(count);
      out.add(Marker(
        markerId: MarkerId('c_${entry.key}_$count'),
        position: LatLng(lat, lon),
        icon: icon,
        onTap: () async {
          final target = LatLng(lat, lon);
          final nextZoom = (_zoom + 1).clamp(2.0, 20.0);
          await _controller?.animateCamera(
            CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: nextZoom)),
          );
        },
      ));
    }
  }

  if (!mounted) return;
  setState(() => _markers = out);
}

  bool _isNearUser(EscapeGame e) {
    if (_userLoc == null) return false;
    return _distanceKm(_userLoc!.latitude, _userLoc!.longitude, e.latitude, e.longitude) <= kDefaultRadiusKm;
    // NB : kDefaultRadiusKm est déjà défini en haut du fichier
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * R * math.asin(math.sqrt(a));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  Future<BitmapDescriptor> _circleIcon({
    required String text,
    required double diameter,
    required Color color,
    double stroke = 0,
  }) async {
    final key = '${color.value}_${diameter}_${stroke}_$text';
	final cached = _iconCache[key];
    if (cached != null) return cached;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = ui.Size(diameter, diameter);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;

    // Cercle de couleur
    final fill = Paint()..color = color;
    canvas.drawCircle(center, radius, fill);

    // Liseré blanc
    if (stroke > 0) {
      final border = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawCircle(center, radius - stroke / 2, border);
    }

    // Texte (compte) si cluster
    if (text.isNotEmpty) {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontWeight: FontWeight.w700,
          fontSize: diameter * 0.42,
        ),
      )..pushStyle(ui.TextStyle(color: Colors.white))
       ..addText(text);

      final para = builder.build()
        ..layout(ui.ParagraphConstraints(width: diameter));
      canvas.drawParagraph(para, Offset(0, center.dy - para.height / 2));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(diameter.toInt(), diameter.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final bmp = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _iconCache[key] = bmp;
    return bmp;
  }
  
  Future<BitmapDescriptor> _iconForEscape(EscapeGame e) {
  final label = (e.rating > 0) ? e.rating.toStringAsFixed(1) : '';
  return _circleIcon(
    text: label,
    diameter: 96,
    color: kEscapeGreen,
    stroke: 6, // liseré blanc
  );
}

  Future<BitmapDescriptor> _iconForCluster(int count) {
  return _circleIcon(
    text: '$count',
    diameter: 110,
    color: kClusterBlue,
    stroke: 6, // liseré blanc
  );
}


  // ============================
  // UI Google Map
  // ============================

  @override
Widget build(BuildContext context) {
  return Stack(
    children: [
      GoogleMap(
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
        onMapCreated: (c) {
  _controller = c;
  if (!_didAutoCenter) {
    _didAutoCenter = true;
    _goToMyLocation(); // gère permissions + fallback Paris
  }
},
        markers: _markers,
        onCameraMove: (pos) {
          final newZoom = pos.zoom;
          _center = pos.target;

          // Détecte un vrai changement de zoom
          if ((newZoom - _zoom).abs() >= 1.0) {
            _zoom = newZoom;
            debugPrint("Zoom changé: $_zoom → rebuild markers");
            _rebuildMarkers();
          }
        },
        onCameraIdle: () {
          // Tu peux garder ça pour raffiner les clusters
          _rebuildMarkers();
        },
      ),
      Positioned(
        top: 12,
        right: 12,
        child: FloatingActionButton.small(
          heroTag: 'myLoc',
          tooltip: 'Ma position',
          onPressed: _goToMyLocation,
          child: const Icon(Icons.my_location),
        ),
      ),
      if (_selected != null) _buildBottomCard(),
      if (_loading) const Center(child: CircularProgressIndicator()),
    ],
  );
}

Widget _buildBottomCard() {
  final e = _selected!;
  return Positioned(
    left: 0,
    right: 0,
    bottom: 8,
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${e.title}\n${e.city}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('Détails'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EscapeDetailsPage(escape: e)),
                );
              },
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.directions_walk),
              label: const Text('Itinéraire'),
              onPressed: () => _openDirections(e),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _goToMyLocation() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      final target = const LatLng(48.8566, 2.3522);
      _userLoc = target;
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
      await _rebuildMarkers();
      return;
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      final target = const LatLng(48.8566, 2.3522);
      _userLoc = target;
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
      await _rebuildMarkers();
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    LatLng target;
    if (_looksLikeAndroidEmuLatLng(pos.latitude, pos.longitude)) {
      target = const LatLng(48.8566, 2.3522);
    } else {
      target = LatLng(pos.latitude, pos.longitude);
    }

    _userLoc = target;
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
    await _rebuildMarkers();
  } catch (_) {
    final target = const LatLng(48.8566, 2.3522);
    _userLoc = target;
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
    await _rebuildMarkers();
  }
}

Future<void> _openDirections(EscapeGame e) async {
  LatLng origin = _userLoc ?? _center;
  final url = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&origin=${origin.latitude},${origin.longitude}'
    '&destination=${e.latitude},${e.longitude}'
    '&travelmode=walking',
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

}

/* ============================
   WIDGETS : DÉTAILS + DÉMARRER
============================ */

class EscapeDetailsPage extends StatefulWidget {
  final EscapeGame escape;
  const EscapeDetailsPage({super.key, required this.escape});

  @override
  State<EscapeDetailsPage> createState() => _EscapeDetailsPageState();
}

class _EscapeDetailsPageState extends State<EscapeDetailsPage> {
  final _api = ApiService.instance;

  bool _checkingStatus = false;
  bool _alreadyFinished = false;
  DateTime? _completedAt;

  Future<List<CommentItem>>? _futureComments;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _futureComments = _api.fetchComments(widget.escape.id, limit: 3);
  }

  String _fmt(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _checkStatus() async {
    setState(() => _checkingStatus = true);
    try {
      final j = await _api.tryGetSessionState(widget.escape.id);
      if (j != null && (j['finished'] == true)) {
        _alreadyFinished = true;
        final s = (j['completed_at'] ?? j['finished_at']) as String?;
        if (s != null) {
          final parsed = DateTime.tryParse(s);
          _completedAt = parsed?.toLocal(); // heure locale
        }
      } else {
        _alreadyFinished = false;
        _completedAt = null;
      }
    } catch (_) {
      // on ignore et on laisse le bouton actif si on ne sait pas
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  void _openReportSheet(BuildContext context, EscapeGame escape) {
    final ctrl = TextEditingController();
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16 + bottomInset),
          child: StatefulBuilder(
            builder: (ctx, setSt) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Signaler cet escape', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'Explique ce qui ne va pas (contenu inapproprié, erreur, etc.)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: sending ? null : () => Navigator.pop(ctx),
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: sending
                          ? null
                          : () async {
                              final msg = ctrl.text.trim();
                              if (msg.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Merci de saisir un message.')),
                                );
                                return;
                              }
                              setSt(() => sending = true);
                              try {
                                await ApiService.instance.reportEscape(escape.id, msg);
                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Signalement envoyé. Merci !')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  setSt(() => sending = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Erreur: $e')),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.send),
                      label: const Text('Envoyer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.escape;

    return Scaffold(
      appBar: AppBar(title: Text(e.title)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (e.imageUrl != null && e.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                normalizeImageUrl(e.imageUrl),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
          const SizedBox(height: 12),

          Text(
            e.description.isNotEmpty ? e.description : "Pas de description.",
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(e.city),
            subtitle: Text(
              'Durée ${e.durationMinutes} min • diff ${e.difficulty} • note ${e.rating.toStringAsFixed(1)}',
            ),
          ),
          const SizedBox(height: 8),

          // --- Démarrer / reprendre la session ---
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Démarrer'),
            onPressed: _alreadyFinished
                ? null
                : () async {
                    try {
                      await _api.getSessionState(e.id); // crée/reprend la session

                      if (!GameTimer.instance.isRunning) {
                        GameTimer.instance.start();
                      }
                      if (!context.mounted) return;

                      // On navigue vers la partie, puis on rafraîchit au retour
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => SessionPlayerPage(escape: e)),
                      );

                      if (!mounted) return;
                      await _checkStatus();
                      setState(() {
                        _futureComments = _api.fetchComments(e.id, limit: 3);
                      });
                    } catch (err) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Impossible de démarrer : $err')),
                      );
                    }
                  },
          ),

          if (_alreadyFinished) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _completedAt != null
                        ? 'Escape déjà terminé le ${_fmt(_completedAt!)}'
                        : 'Escape déjà terminé.',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Text('Derniers commentaires', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          FutureBuilder<List<CommentItem>>(
            future: _futureComments,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Pas encore de commentaires.'),
                );
              }
              final items = snap.data!;
              return Column(
                children: [
                  for (final c in items)
                    ListTile(
                      dense: true,
                      leading: Text('★' * c.stars + '☆' * (5 - c.stars)),
                      title: Text(c.user),
                      subtitle: Text(c.comment),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // --- Signaler l'escape ---
          OutlinedButton.icon(
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Signaler cet escape'),
            onPressed: () => _openReportSheet(context, e),
          ),
          const SizedBox(height: 8),

          // Petit bouton manuel si besoin
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Actualiser'),
            onPressed: () async {
              await _checkStatus();
              setState(() {
                _futureComments = _api.fetchComments(e.id, limit: 3);
              });
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}



/* ============================
   WIDGETS : SESSION JOUEUR
============================ */

class SessionPlayerPage extends StatefulWidget {
  final EscapeGame escape;
  const SessionPlayerPage({super.key, required this.escape});

  @override
  State<SessionPlayerPage> createState() => _SessionPlayerPageState();
}

class _SessionPlayerPageState extends State<SessionPlayerPage> {
  final _api = ApiService.instance;

  bool _loading = true;
  bool _submitting = false;

  int _index = 0;
  int _total = 0;
  bool _finished = false;

  bool _hintAvailable = false;
  int _hintsTotal = 0;
  int _hintsUsed = 0;
  int _currentHintPenalty = 0;

  int? _currentStepId;
  String _stepTitle = '';
  String? _stepImageUrl;
  String _prompt = '';
  // String? _revealedHint;
  List<String> _revealedHints = [];

  // Réponse (texte/numérique)
  final _answerCtrl = TextEditingController();

  // Type de réponse
  String _answerType = 'text';

  // QCM
  List<String> _mcqOptions = [];
  int? _selectedOption;

  // Matching (A↔B)
  List<String> _matchLeft = [];
  List<String> _matchRight = [];

  // --- Matching par clic-clic ---
  // Ordre courant de B (ligne -> indexOriginalRight)
  List<int> _rightOrder = [];
  // Ordre initial mélangé de B (pour reset/détacher)
  List<int> _initialRightOrder = [];
  // Pour éviter de re-mélanger en plein milieu de la même étape
  int? _lastShuffleStepId;

  // Sélection en cours
  int? _selA; // index original dans _matchLeft
  int? _selB; // index original dans _matchRight

  // ---------- Helpers ----------
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  // S'assurer que _rightOrder existe, sans écraser un mélange déjà en place
  void _ensureRightOrder() {
    if (_rightOrder.length != _matchRight.length) {
      if (_initialRightOrder.length == _matchRight.length) {
        _rightOrder = List<int>.from(_initialRightOrder);
      } else {
        _initialRightOrder = List<int>.generate(_matchRight.length, (i) => i);
        _initialRightOrder.shuffle(); // aléatoire non déterministe
        _rightOrder = List<int>.from(_initialRightOrder);
      }
    }
  }

  // Quand A et B sont sélectionnés, on place B en face de A
  void _pairSelectedIfReady() {
    if (_selA == null || _selB == null) return;
    _ensureRightOrder();

    int rowA = _selA!;
    if (rowA < 0) rowA = 0;
    if (rowA >= _rightOrder.length) rowA = _rightOrder.length - 1;

    final posB = _rightOrder.indexOf(_selB!);
    if (posB == -1) {
      setState(() { _selA = null; _selB = null; });
      return;
    }

    setState(() {
      final moving = _rightOrder.removeAt(posB);
      _rightOrder.insert(rowA, moving);
      _selA = null;
      _selB = null;
    });
  }

  void _onTapA(int originalIndexA) {
    setState(() {
      _selA = (_selA == originalIndexA) ? null : originalIndexA;
    });
    _pairSelectedIfReady();
  }

  void _onTapB(int originalIndexB) {
    setState(() {
      _selB = (_selB == originalIndexB) ? null : originalIndexB;
    });
    _pairSelectedIfReady();
  }

  // Détacher la paire sur une ligne donnée → remet B à sa position du mélange initial
  void _unpairRow(int rowIndex) {
    _ensureRightOrder();
    if (rowIndex < 0 || rowIndex >= _rightOrder.length) return;
    final bOriginal = _rightOrder[rowIndex];
    setState(() {
      _rightOrder.removeAt(rowIndex);
      final initialPos = _initialRightOrder.indexOf(bOriginal);
      final target = (initialPos >= 0)
          ? initialPos
          : bOriginal.clamp(0, _rightOrder.length);
      _rightOrder.insert(target, bOriginal);
      if (_selA == rowIndex) _selA = null;
      if (_selB == bOriginal) _selB = null;
    });
  }

  // Réinitialiser toutes les paires → revient à l’ordre mélangé initial
  void _resetPairs() {
    setState(() {
      _rightOrder = List<int>.from(_initialRightOrder);
      _selA = null;
      _selB = null;
    });
  }

  // ---------- Chargement état session ----------
  Future<void> _loadState() async {
  setState(() => _loading = true);
  try {
    final j = await _api.getSessionState(widget.escape.id) ?? <String, dynamic>{};

    // statut fin
    _finished = (j['finished'] == true);

    // total
    _total = _asInt(j['total_steps']) ?? _asInt(j['total']) ?? 0;

    // sync pénalité côté timer
    final penaltyFromApi =
        _asInt(j['penalty']) ?? _asInt(j['accumulated_penalty_minutes']) ?? 0;
    GameTimer.instance.syncPenaltyMinutes(penaltyFromApi);

    if (_finished) {
      // session finie → pas d’étape courante
      _index = _total > 0 ? _total - 1 : 0;

      _stepTitle = '';
      _stepImageUrl = null;
      _prompt = '';
      _hintsTotal = 0;
      _hintsUsed = 0;
      _hintAvailable = false;
      _answerType = 'text';
      _mcqOptions = const [];
      _selectedOption = null;
      _currentHintPenalty = 0;
      _revealedHints = [];       // <= reset
      _answerCtrl.clear();

      _matchLeft = [];
      _matchRight = [];
      _rightOrder = [];
      _initialRightOrder = [];
      _lastShuffleStepId = null;
      _selA = null; _selB = null;
    } else {
      // session en cours
      _index = _asInt(j['step_index']) ?? 0;

      final Map<String, dynamic> st = (j['step'] is Map)
          ? (j['step'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};

      // id d'étape & détection de changement
      final sid = _asInt(st['id']) ?? _asInt(st['step_id']);
      final bool stepChanged = (_currentStepId != sid);
      if (stepChanged) {
        _currentStepId = sid;
        _revealedHints = [];     // <= reset à chaque changement d’étape
      }

      // titre / image / énoncé
      _stepTitle = '${st['title'] ?? ''}'.trim();
      final imgAny = st['image_url'] ?? st['image'] ?? st['imageUrl'];
      _stepImageUrl = (imgAny == null) ? null : '$imgAny'.trim();
      _prompt = '${st['text'] ?? st['description'] ?? st['prompt'] ?? ''}'.trim();

      // indices (tolérant vieux payloads)
      _hintAvailable = (st['hint_available'] == true);
      final int totalFromApi = _asInt(st['hints_total']) ?? 0;
      _hintsTotal = totalFromApi > 0 ? totalFromApi : (_hintAvailable ? 1 : 0);
      final int? usedFromApi = _asInt(st['hints_used']);
      _hintsUsed = usedFromApi ?? ((st['hint_used'] == true) ? 1 : 0);
      _currentHintPenalty = _asInt(st['hint_penalty']) ?? _asInt(st['hintPenalty']) ?? 0;

      // si le backend fournit la liste des indices révélés, on l'utilise
      final rh = (st['revealed_hints'] as List?) ?? const [];
      _revealedHints = rh
          .map((e) => '$e'.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: true);

      // types & données
      final atRaw = '${st['answer_type'] ?? st['type'] ?? 'text'}'.trim().toLowerCase();
      final ansTextRaw = '${st['answer_text'] ?? st['answer'] ?? ''}'.trim();
      final opts = (st['options'] as List?)?.map((e) => '$e').toList() ?? const <String>[];

      final leftRaw  = (st['matching_left'] ?? st['match_left'] ?? []) as List?;
      final rightRaw = (st['matching_right'] ?? st['match_right'] ?? []) as List?;

      // Détection robuste de la narration
      final bool isNarration =
          atRaw == 'narration' ||
          st['is_narration'] == true ||
          (atRaw == 'text' && ansTextRaw == '__NARRATION__');

      if (isNarration) {
        _answerType = 'narration';
        _mcqOptions = const [];
        _selectedOption = null;
        _matchLeft = [];
        _matchRight = [];
        _rightOrder = [];
        _initialRightOrder = [];
        _lastShuffleStepId = null;
        _selA = null; _selB = null;

      } else if (atRaw == 'mcq') {
        _answerType = 'mcq';
        _mcqOptions = opts;
        _selectedOption = null;
        _matchLeft = [];
        _matchRight = [];
        _rightOrder = [];
        _initialRightOrder = [];
        _lastShuffleStepId = null;
        _selA = null; _selB = null;

      } else if (atRaw == 'numeric') {
        _answerType = 'numeric';
        _mcqOptions = const [];
        _selectedOption = null;
        _matchLeft = [];
        _matchRight = [];
        _rightOrder = [];
        _initialRightOrder = [];
        _lastShuffleStepId = null;
        _selA = null; _selB = null;

      } else if (atRaw == 'matching' && leftRaw != null && rightRaw != null) {
        _answerType = 'matching';
        _mcqOptions = const [];
        _selectedOption = null;
        _matchLeft  = leftRaw.map((e) => '$e').toList();
        _matchRight = rightRaw.map((e) => '$e').toList();

        final bool shouldShuffle =
            stepChanged ||
            _initialRightOrder.length != _matchRight.length ||
            _lastShuffleStepId != (_currentStepId ?? -1);

        if (shouldShuffle) {
          _initialRightOrder = List<int>.generate(_matchRight.length, (i) => i);
          _initialRightOrder.shuffle();
          _rightOrder = List<int>.from(_initialRightOrder);
          _lastShuffleStepId = _currentStepId ?? -1;
        } else {
          if (_rightOrder.length != _matchRight.length) {
            _rightOrder = List<int>.from(_initialRightOrder);
          }
        }
        _selA = null;
        _selB = null;

      } else if (opts.isNotEmpty) {
        _answerType = 'mcq';
        _mcqOptions = opts;
        _selectedOption = null;
        _matchLeft = [];
        _matchRight = [];
        _rightOrder = [];
        _initialRightOrder = [];
        _lastShuffleStepId = null;
        _selA = null; _selB = null;

      } else {
        _answerType = 'text';
        _mcqOptions = const [];
        _selectedOption = null;
        _matchLeft = [];
        _matchRight = [];
        _rightOrder = [];
        _initialRightOrder = [];
        _lastShuffleStepId = null;
        _selA = null; _selB = null;
      }

      _answerCtrl.clear();

      // NOTE : pour les vieux backends qui ne renvoient pas 'revealed_hints',
      // on n'essaie pas de relire les textes (sinon risque de re-déclencher une pénalité).
      // On se contente d'afficher le compteur. Dès qu'un nouvel indice est demandé,
      // on l'ajoute localement à _revealedHints.
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Erreur état: $e')));
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  // ---------- Image plein écran ----------
  void _openImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Impossible de charger l’image',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Indice ----------
  Future<void> _askHint() async {
  try {
    final j = await _api.requestHint(widget.escape.id);
    final hint = '${j['hint'] ?? ''}'.trim();

    if (!mounted) return;
    if (hint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pas d\'indice')),
      );
      return;
    }

    setState(() {
      // on stocke plusieurs indices
      _revealedHints = List<String>.from(_revealedHints)..add(hint);
      _hintsUsed = (_hintsUsed + 1).clamp(0, _hintsTotal);
    });

    if (_currentHintPenalty > 0) {
      GameTimer.instance.addPenaltyMinutes(_currentHintPenalty);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur indice: $e')),
    );
  }
}


  // ---------- Soumission ----------
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
	  // ---- Narration : pas de réponse, on avance juste l’étape ----
      if (_answerType == 'narration') {
        final j = await _api.submitAnswer(widget.escape.id, narration: true);

        final finished = (j['finished'] ?? false) as bool;
        final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;

        if (!context.mounted) return;
        if (finished) {
          final finalTimeText = GameTimer.instance.finishAndGetResult();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => VictoryPage(
                escape: widget.escape,
                finalMessage: finalMsg,
                timeOverride: finalTimeText,
              ),
            ),
          );
        } else {
          await _loadState();
        }
        return; // très important : on sort ici, on ne tombe pas dans les autres types
      }  
	  if (_answerType == 'narration') {
		final j = await _api.submitAnswer(widget.escape.id, narration: true);

		final finished = (j['finished'] ?? false) as bool;
		final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;

		if (finished) {
			final finalTimeText = GameTimer.instance.finishAndGetResult();
			if (!context.mounted) return;
			Navigator.of(context).pushReplacement(
				MaterialPageRoute(
					builder: (_) => VictoryPage(
						escape: widget.escape,
						finalMessage: finalMsg,
						timeOverride: finalTimeText,
					),
				),
			);
		} else {
		  await _loadState();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Étape suivante')),
          );
        }
        return;
      } 
      // QCM
      if (_answerType == 'mcq') {
        int? idx = _selectedOption;
        if (idx == null) return;

        final j = await _api.submitAnswer(
          widget.escape.id,
          optionIndex: idx,
          answer: (idx >= 0 && idx < _mcqOptions.length) ? _mcqOptions[idx] : null,
        );

        final correct  = (j['correct'] ?? false) as bool;
        final finished = (j['finished'] ?? false) as bool;

        if (!context.mounted) return;
        if (!correct) {
          final applied = _asInt(j['applied_penalty']) ?? 0;
          final pCumul  = _asInt(j['penalty']);
          if (pCumul != null) {
            GameTimer.instance.syncPenaltyMinutes(pCumul);
          } else if (applied > 0) {
            GameTimer.instance.addPenaltyMinutes(applied);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(applied > 0
                ? 'Mauvaise réponse. +$applied min de pénalité'
                : 'Mauvaise réponse.')),
          );
          setState(() => _selectedOption = null);
          return;
        }

        final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;
        if (finished) {
          final finalTimeText = GameTimer.instance.finishAndGetResult();
          if (!context.mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => VictoryPage(
                escape: widget.escape,
                finalMessage: finalMsg,
                timeOverride: finalTimeText,
              ),
            ),
          );
        } else {
          await _loadState();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bonne réponse !')),
          );
          setState(() => _selectedOption = null);
        }
        return;
      }

      // Matching — clic-clic : A fixe, B réordonnée
      if (_answerType == 'matching') {
        _ensureRightOrder();

        final rowCount = (_matchLeft.length <= _matchRight.length)
            ? _matchLeft.length
            : _matchRight.length;

        // pairs: [indexOriginalDeA, indexOriginalDeB] pour chaque ligne
        final pairs = <List<int>>[];
        for (int row = 0; row < rowCount; row++) {
          final leftOriginal  = row;              // A est fixe: index = ligne
          final rightOriginal = _rightOrder[row]; // B réordonnée
          pairs.add([leftOriginal, rightOriginal]);
        }

        final j = await _api.submitAnswer(widget.escape.id, pairs: pairs);

        final correct  = (j['correct'] ?? false) as bool;
        final finished = (j['finished'] ?? false) as bool;

        if (!context.mounted) return;
        if (!correct) {
          final applied = _asInt(j['applied_penalty']) ?? 0;
          final pCumul  = _asInt(j['penalty']);
          if (pCumul != null) {
            GameTimer.instance.syncPenaltyMinutes(pCumul);
          } else if (applied > 0) {
            GameTimer.instance.addPenaltyMinutes(applied);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(applied > 0
                ? 'Mauvaise réponse. +$applied min de pénalité'
                : 'Mauvaise réponse.')),
          );
          return;
        }

        final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;
        if (finished) {
          final finalTimeText = GameTimer.instance.finishAndGetResult();
          if (!context.mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => VictoryPage(
                escape: widget.escape,
                finalMessage: finalMsg,
                timeOverride: finalTimeText,
              ),
            ),
          );
        } else {
          await _loadState();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bonne réponse !')),
          );
        }
        return;
      }

      // Texte | Numérique
      final ans = _answerCtrl.text.trim();
      if (ans.isEmpty) return;

      final j = await _api.submitAnswer(
        widget.escape.id,
        answer: ans,
      );

      final correct  = (j['correct'] ?? false) as bool;
      final finished = (j['finished'] ?? false) as bool;

      if (!context.mounted) return;
      if (!correct) {
        final applied = _asInt(j['applied_penalty']) ?? 0;
        final pCumul  = _asInt(j['penalty']);
        if (pCumul != null) {
          GameTimer.instance.syncPenaltyMinutes(pCumul);
        } else if (applied > 0) {
          GameTimer.instance.addPenaltyMinutes(applied);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(applied > 0
              ? 'Mauvaise réponse. +$applied min de pénalité'
              : 'Mauvaise réponse.')),
        );
        _answerCtrl.clear();
        return;
      }

      final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;
      if (finished) {
        final finalTimeText = GameTimer.instance.finishAndGetResult();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VictoryPage(
              escape: widget.escape,
              finalMessage: finalMsg,
              timeOverride: finalTimeText,
            ),
          ),
        );
      } else {
        await _loadState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bonne réponse !')),
        );
        _answerCtrl.clear();
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
  
  Future<void> _submitNarration() async {
  if (_submitting) return;
  setState(() => _submitting = true);
  try {
    // On appelle l’API sans réponse (ack de lecture)
    final j = await _api.submitAnswer(widget.escape.id);

    final finished = (j['finished'] ?? false) as bool;
    final finalMsg = (j['final_message'] ?? j['victory_message'] ?? '') as String;

    if (!mounted) return;
    if (finished) {
      final finalTimeText = GameTimer.instance.finishAndGetResult();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VictoryPage(
            escape: widget.escape,
            finalMessage: finalMsg,
            timeOverride: finalTimeText,
          ),
        ),
      );
    } else {
      await _loadState();
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur: $e')),
    );
  } finally {
    if (mounted) setState(() => _submitting = false);
  }
}

  // ---------- UI Matching (clic-clic) ----------
  Widget _buildMatchingClickPair() {
    _ensureRightOrder();

    final rowCount = (_matchLeft.length <= _matchRight.length)
        ? _matchLeft.length
        : _matchRight.length;

    final cs = Theme.of(context).colorScheme;

    // Cellule A (fixe)
    Widget _aCell(int aIndexOriginal) {
      final selected = (_selA == aIndexOriginal);

      return InkWell(
        onTap: () => _onTapA(aIndexOriginal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.secondary : cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _matchLeft[aIndexOriginal],
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Cellule B (ordre courant)
    Widget _bCell(int rowIndex) {
      final bOriginal = _rightOrder[rowIndex];
      final selected  = (_selB == bOriginal);

      return InkWell(
        onTap: () => _onTapB(bOriginal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.square, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _matchRight[bOriginal],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  softWrap: true,
                ),
              ),
              IconButton(
                tooltip: 'Détacher',
                onPressed: () => _unpairRow(rowIndex),
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Clique un item de A puis un item de B (ou l’inverse). B se place en face de A.',
        ),
        const SizedBox(height: 12),

        // Lignes A | B avec hauteurs égales
        for (int row = 0; row < rowCount; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _aCell(row)),
                  const SizedBox(width: 12),
                  Expanded(child: _bCell(row)),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Ordre B: ' + _rightOrder.map((e) => (e + 1).toString()).join(' → '),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _resetPairs,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Réinitialiser les paires'),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    // UI indices
    final int totalForUi = (_hintsTotal > 0) ? _hintsTotal : (_hintAvailable ? 1 : 0);
    final int usedForUi  = (_hintsTotal > 0) ? _hintsUsed  : (_hintAvailable ? (_hintsUsed > 0 ? 1 : 0) : 0);
    final bool hasHintSection = (totalForUi > 0);
    final bool canAskHint = usedForUi < totalForUi;

    return Scaffold(
      appBar: AppBar(
  title: Text('Étape ${_index + 1} / $_total'),
  actions: [
    IconButton(
      tooltip: 'Étapes passées',
      icon: const Icon(Icons.history),
      onPressed: () async {
        try {
          final steps = await _api.getPastSteps(widget.escape.id);
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PastStepsPage(steps: steps)),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Historique indisponible: $e')),
          );
        }
      },
    ),
    const Center(child: TimerBadge()),
  ],
),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _finished
              ? Center(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text('Voir le trophée'),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => VictoryPage(escape: widget.escape)),
                      );
                    },
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_submitting) ...[
                        const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 8),
                      ],

                      // ---- CONTENU DÉFILABLE ----
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Titre
                              if (_stepTitle.isNotEmpty) ...[
                                Text(_stepTitle,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                              ],

                              // Image cliquable
                              if ((_stepImageUrl ?? '').isNotEmpty) ...[
                                GestureDetector(
                                  onTap: () => _openImageViewer(_stepImageUrl!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      normalizeImageUrl(_stepImageUrl),
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 160,
                                        color: Colors.grey.shade200,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.image_not_supported_outlined),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Énoncé
                              if (_prompt.isNotEmpty) ...[
                                Text(_prompt, style: const TextStyle(fontSize: 16)),
                                const SizedBox(height: 16),
                              ],

                              // --- Zone réponse ---
                              if (_answerType == 'mcq' && _mcqOptions.isNotEmpty) ...[
                                for (int i = 0; i < _mcqOptions.length; i++)
                                  RadioListTile<int>(
                                    value: i,
                                    groupValue: _selectedOption,
                                    onChanged: _submitting ? null : (v) => setState(() => _selectedOption = v),
                                    title: Text(_mcqOptions[i]),
                                    dense: true,
                                  ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.check),
                                    label: const Text('Valider'),
                                    onPressed: (_selectedOption == null || _submitting) ? null : _submit,
                                  ),
                                ),
                              ] else if (_answerType == 'narration') ...[
								// Rien d’interactif : on a déjà le titre / image / texte plus haut
								const SizedBox(height: 12),
								Align(
									alignment: Alignment.centerRight,
									child: FilledButton.icon(
									  icon: const Icon(Icons.arrow_forward),
									  label: const Text('Passer à l’étape suivante'),
									  onPressed: _submitting ? null : _submit,
									),
								),
							  ] else if (_answerType == 'matching') ...[
                                const SizedBox(height: 8),
                                _buildMatchingClickPair(),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    onPressed: _submitting ? null : _submit,
                                    icon: const Icon(Icons.check),
                                    label: const Text('Valider'),
                                  ),
                                ),
                              ] else ...[
                                // text | numeric : un seul champ
                                TextField(
                                  controller: _answerCtrl,
                                  keyboardType: _answerType == 'numeric'
                                      ? const TextInputType.numberWithOptions(decimal: true, signed: false)
                                      : TextInputType.text,
                                  decoration: InputDecoration(
                                    labelText: _answerType == 'numeric'
                                        ? 'Réponse attendue (nombre)'
                                        : 'Réponse attendue',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.send),
                                      onPressed: _submitting ? null : _submit,
                                    ),
                                  ),
                                  enabled: !_submitting,
                                  onSubmitted: (_) => _submitting ? null : _submit(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // ---- PIED : INDICES (multi) ----
						if (hasHintSection) ...[
						  const SizedBox(height: 12),

						  // Bouton "demander un indice"
						  if (_revealedHints.length < _hintsTotal) ...[
							Align(
							  alignment: Alignment.centerLeft,
							  child: OutlinedButton.icon(
								icon: const Icon(Icons.help_outline),
								label: Text(
								  'Indice (${_revealedHints.length}/$_hintsTotal) • Pénalité : $_currentHintPenalty min'),
								onPressed: _askHint,
							  ),
							),
						  ] else ...[
							Align(
							  alignment: Alignment.centerLeft,
							  child: Text(
								'Tous les indices ont été révélés (${_revealedHints.length}/$_hintsTotal).',
								style: TextStyle(color: Colors.grey.shade700),
							  ),
							),
						  ],

						  const SizedBox(height: 8),

						  // Liste des indices déjà révélés
						  if (_revealedHints.isNotEmpty) ...[
							Column(
							  crossAxisAlignment: CrossAxisAlignment.stretch,
							  children: [
								for (int i = 0; i < _revealedHints.length; i++)
								  Container(
									margin: const EdgeInsets.only(bottom: 8),
									padding: const EdgeInsets.all(12),
									decoration: BoxDecoration(
									  color: Colors.amber.withOpacity(0.08),
									  borderRadius: BorderRadius.circular(10),
									  border: Border.all(color: Colors.amber.withOpacity(0.35)),
									),
									child: Column(
									  crossAxisAlignment: CrossAxisAlignment.start,
									  children: [
										Text('Indice ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
										const SizedBox(height: 6),
										Text(_revealedHints[i]),
										const SizedBox(height: 6),
										Text(
										  'Pénalité : $_currentHintPenalty min',
										  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
										),
									  ],
									),
								  ),
							  ],
							),
						  ],
						],
                    ],
                  ),
                ),
    );
  }
}




/* ============================
   WIDGETS : VICTORY + rating
============================ */

class VictoryPage extends StatefulWidget {
  final EscapeGame escape;
  final String? finalMessage;   // message renvoyé par l’API à la dernière étape (facultatif)
  final String? timeOverride;   // texte temps final pré-calculé (facultatif)

  const VictoryPage({
    super.key,
    required this.escape,
    this.finalMessage,
    this.timeOverride,
  });

  @override
  State<VictoryPage> createState() => _VictoryPageState();
}

class _VictoryPageState extends State<VictoryPage> {
  bool _checkingCanRate = true;
  bool _canRate = true; // par défaut on autorise, puis on confirme avec l’API

  @override
  void initState() {
    super.initState();
    _loadCanRate();
  }

  Future<void> _loadCanRate() async {
    try {
      final ok = await ApiService.instance.canRate(widget.escape.id);
      if (!mounted) return;
      setState(() {
        _canRate = ok;
      });
    } catch (_) {
      // En cas d’échec réseau, on garde le bouton actif (l’API refusera si besoin)
      if (!mounted) return;
      setState(() => _canRate = true);
    } finally {
      if (mounted) setState(() => _checkingCanRate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // “Latche” le temps s’il n’a pas été fourni en override
    final timeText = widget.timeOverride?.trim().isNotEmpty == true
        ? widget.timeOverride!.trim()
        : GameTimer.instance.finishAndGetResult();

    // Message : priorité au finalMessage, sinon celui stocké dans l’escape
    final vm = (widget.finalMessage?.trim().isNotEmpty ?? false)
        ? widget.finalMessage!.trim()
        : (widget.escape.victoryMessage.trim().isNotEmpty
            ? widget.escape.victoryMessage.trim()
            : null);

    return WillPopScope(
      onWillPop: () async {
        // On renvoie `true` pour déclencher le rafraîchissement sur la page d’info
        Navigator.of(context).pop(true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Bravo !')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events, size: 96),
                const SizedBox(height: 12),
                Text('Escape terminé : ${widget.escape.title}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Temps: $timeText', style: const TextStyle(fontSize: 16)),
                if (vm != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    vm,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
                const SizedBox(height: 24),

                // Bouton "Noter"
                FilledButton.icon(
                  icon: const Icon(Icons.star_border),
                  label: Text(_checkingCanRate
                      ? '...' 
                      : (_canRate ? 'Noter cet escape' : 'Déjà noté')),
                  onPressed: (_checkingCanRate || !_canRate)
                      ? null
                      : () => _openRatingDialog(context, widget.escape),
                ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Revenir à la liste'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRatingDialog(BuildContext context, EscapeGame e) {
    int stars = 5;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Votre note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<int>(
              value: stars,
              onChanged: (v) => stars = v ?? 5,
              items: List.generate(
                5,
                (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} ★')),
              ),
            ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Commentaire (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              try {
                await ApiService.instance.submitRating(
                  escapeId: e.id,
                  stars: stars,
                  comment: controller.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.pop(context); // ferme le dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Merci pour votre note !')),
                );
                // On revient à la page détails et on déclenche le refresh (result = true)
                Navigator.of(context).pop(true);
              } catch (err) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur: $err')),
                );
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}




/* ============================
   WIDGETS : CRÉATEUR (version compacte, compatible API)
============================ */

class CreatorPage extends StatefulWidget {
  const CreatorPage({super.key});
  @override
  State<CreatorPage> createState() => _CreatorPageState();
}

class _CreatorPageState extends State<CreatorPage> {
  final _api = ApiService.instance;

  Future<List<EscapeGame>>? _future;
  bool _isAdmin = false;
  bool _profileLoading = true; // tant que /me n'est pas prêt
  bool get _roleKnown => !_profileLoading;

  // Filtre par statut (admin seulement)
  // autorisés: {all, draft, submitted, published, rejected}
  String _statusFilter = 'all';

  late final VoidCallback _onTokenChanged;

  @override
  void initState() {
    super.initState();

    _onTokenChanged = () {
      final token = AuthService.instance.tokenNotifier.value;
      if (token == null) {
        setState(() {
          _future = null;
          _profileLoading = false; // pas de profil si pas de token
          _isAdmin = false;
        });
        return;
      }
      // token présent -> charger le profil UNE fois
      setState(() {
        _profileLoading = true;
      });
      _ensureProfileBeforeLoading();
    };

    // écouter UNIQUEMENT les changements de token
    AuthService.instance.tokenNotifier.addListener(_onTokenChanged);

    // boot initial (au cas où token déjà présent)
    _onTokenChanged();
  }

  @override
  void dispose() {
    AuthService.instance.tokenNotifier.removeListener(_onTokenChanged);
    super.dispose();
  }

  Future<void> _ensureProfileBeforeLoading() async {
    try {
      await AuthService.instance.ensureProfileLoaded();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;        // défaut: vue user si le profil échoue
        _profileLoading = false; // on retire le loader
      });
      _reload();                 // charge la liste côté user
      return;
    }

    if (!mounted) return;
    setState(() {
      _isAdmin = AuthService.instance.isAdmin; // admin connu
      _profileLoading = false;
    });
    _reload();                                   // charge la bonne liste (admin/user)
  }

  void _reload() {
    final token = AuthService.instance.tokenNotifier.value;
    if (token == null) {
      setState(() => _future = null);
      return;
    }

    // Pour admin : on passe le filtre s'il n'est pas "all".
    // Pour user : on ignore le filtre (le backend renvoie uniquement ses escapes).
    final String? statusParam = (_isAdmin && _statusFilter != 'all') ? _statusFilter : null;

    setState(() {
      _future = _api.fetchCreatorList(status: statusParam);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.instance.tokenNotifier,
      builder: (_, token, __) {
        if (token == null) {
          return const Center(child: Text('Connectez-vous pour accéder au mode créateur.'));
        }

        if (_profileLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Garantit qu'une requête est lancée (ex: si /me a échoué)
        if (_future == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _future == null) _reload();
          });
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // Header + filtres + bouton "Nouveau brouillon"
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isAdmin ? 'Tous les escapes' : 'Mes escapes',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),

                  // Filtres visibles uniquement pour admin
                  if (_roleKnown && _isAdmin) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _statusFilter,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _statusFilter = v);
                          _reload();
                        },
                        items: const [
                          DropdownMenuItem(value: 'all',       child: Text('Tous')),
                          DropdownMenuItem(value: 'draft',     child: Text('Brouillons')),
                          DropdownMenuItem(value: 'submitted', child: Text('Soumis')),
                          DropdownMenuItem(value: 'published', child: Text('Publiés')),
                          DropdownMenuItem(value: 'rejected',  child: Text('Rejetés')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Bouton "Nouveau brouillon" : caché pour admin
                  if (!_isAdmin)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Nouveau brouillon'),
                          onPressed: () => _openDraftDialog(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (_roleKnown && _isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Filtre: ${{
                      'all': 'Tous',
                      'draft': 'Brouillons',
                      'submitted': 'Soumis',
                      'published': 'Publiés',
                      'rejected': 'Rejetés',
                    }[_statusFilter] ?? _statusFilter}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ),

            // Liste
            Expanded(
              child: FutureBuilder<List<EscapeGame>>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Erreur: ${snap.error}'));
                  }

                  var items = snap.data ?? [];

                  // Filtrage complémentaire côté client pour admin quand _statusFilter != 'all'
                  if (_isAdmin && _statusFilter != 'all') {
                    items = items.where((e) => e.status == _statusFilter).toList();
                  }

                  if (items.isEmpty) {
                    return const Center(child: Text('Aucun escape.'));
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = items[i];

                        final human = ({
                          'draft': 'Brouillon',
                          'submitted': 'Soumis',
                          'published': 'Publié',
                          'rejected': 'Rejeté',
                        }[e.status]) ?? e.status;

                        return ListTile(
                          title: Text(e.title),
                          subtitle: Text('${e.city} • durée ${e.durationMinutes} min • statut: $human'),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => EscapeEditorPage(escape: e)),
                            );
                            _reload();
                          },
                          trailing: _isAdmin
                              ? AdminActions(
                                  escape: e,
                                  roleKnown: _roleKnown,
                                  isAdmin: _isAdmin,
                                  onReload: _reload,
                                )
                              : (e.status == 'draft'
                                  ? FilledButton.icon(
                                      icon: const Icon(Icons.send_outlined),
                                      label: const Text('Soumettre'),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Soumettre cet escape ?'),
                                            content: const Text(
                                              'Il passera en “Soumis” et ne sera plus modifiable jusqu’à décision.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('Annuler'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: const Text('Soumettre'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok != true) return;
                                        try {
                                          await _api.submitEscape(e.id);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Soumis pour approbation')),
                                          );
                                          _reload();
                                        } catch (err) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Erreur: $err')),
                                          );
                                        }
                                      },
                                    )
                                  : null),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // --------- Bouton feedback collé en bas ---------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Envoyer un feedback'),
                    onPressed: () => openCreatorFeedbackSheet(
                      context,
                      page: 'creator_page',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openDraftDialog(BuildContext context) {
    final durationCtrl = TextEditingController(text: '60');
    final titleCtrl = TextEditingController();
    final cityCtrl = TextEditingController(text: 'Paris');
    final latCtrl = TextEditingController(text: '48.8566');
    final lonCtrl = TextEditingController(text: '2.3522');
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau brouillon'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(decoration: const InputDecoration(labelText: 'Titre'), controller: titleCtrl),
              TextField(decoration: const InputDecoration(labelText: 'Ville'), controller: cityCtrl),
              TextField(decoration: const InputDecoration(labelText: 'Durée (min)'), controller: durationCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Latitude'), controller: latCtrl, keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Longitude'), controller: lonCtrl, keyboardType: TextInputType.number)),
                ],
              ),
              TextField(decoration: const InputDecoration(labelText: 'Description (optionnel)'), controller: descCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              try {
                final id = await _api.createDraft(
                  title: titleCtrl.text.trim(),
                  city: cityCtrl.text.trim(),
                  latitude: double.tryParse(latCtrl.text.trim()) ?? 0,
                  longitude: double.tryParse(lonCtrl.text.trim()) ?? 0,
                  description: descCtrl.text.trim(),
                  durationMinutes: int.tryParse(durationCtrl.text.trim()) ?? 60,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Brouillon créé (#$id)')));
                _reload();
              } catch (err) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $err')));
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }
}




class AdminActions extends StatefulWidget {
  final EscapeGame escape;
  final bool roleKnown;
  final bool isAdmin;
  final VoidCallback onReload;

  const AdminActions({
    super.key,
    required this.escape,
    required this.roleKnown,
    required this.isAdmin,
    required this.onReload,
  });

  @override
  State<AdminActions> createState() => _AdminActionsState();
}

class _AdminActionsState extends State<AdminActions> {
  bool _busy = false;
  ApiService get _api => ApiService.instance;

  @override
  Widget build(BuildContext context) {
    // Rien si rôle inconnu ou non-admin
    if (!widget.roleKnown || !widget.isAdmin) {
      return const SizedBox.shrink();
    }

    // Nouvelle logique :
    // - Approuver -> seulement quand 'submitted'
    // - Rejeter   -> quand 'submitted' ou 'published'
    final st = widget.escape.status;
    final canApprove = st == 'submitted';
    final canReject  = (st == 'submitted' || st == 'published');

    final buttons = <Widget>[];

    if (canApprove) {
      buttons.add(TextButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  // On réutilise l’endpoint publish() qui publie après vérifs backend.
                  await _api.publish(widget.escape.id);
                  // Nettoie un éventuel état local de "refusé"
                  await ApiService.instance.unmarkLocallyRefused(widget.escape.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escape approuvé et publié')),
                    );
                  }
                  widget.onReload();
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $err')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: const Text('Approuver'),
      ));
    }

    if (canReject) {
      buttons.add(TextButton(
        onPressed: _busy
            ? null
            : () async {
                final ctrl = TextEditingController();
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Motif de refus'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(hintText: 'Expliquez brièvement le refus'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                        child: const Text('Rejeter'),
                      ),
                    ],
                  ),
                );
                if (reason == null || reason.isEmpty) return;

                setState(() => _busy = true);
                try {
                  await _api.rejectEscape(
                    widget.escape.id,
                    reason,
                    includeStatus: (st == 'published'), // utile seulement si publié
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escape rejeté')),
                    );
                  }
                  widget.onReload();
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $err')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: const Text('Rejeter'),
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    // Petit indicateur si action en cours
    if (_busy) {
      buttons.add(const Padding(
        padding: EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}




/* ============================
   WIDGETS : ÉDITEUR (compact)
============================ */

class EscapeEditorPage extends StatefulWidget {
  final dynamic escape; // votre modèle EscapeGame typé dynamique ici
  const EscapeEditorPage({super.key, required this.escape});

  @override
  State<EscapeEditorPage> createState() => _EscapeEditorPageState();
}

class _EscapeEditorPageState extends State<EscapeEditorPage> {
  final _api = ApiService.instance;
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _titleCtrl;
  late TextEditingController _imageCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _durationCtrl;
  late TextEditingController _victoryCtrl;

  // Pénalités “mauvaise réponse”
  bool _penalizeWrong = false;
  late TextEditingController _wrongPenaltyCtrl;

  double? _startLat;
  double? _startLon;
  GoogleMapController? _miniMapCtrl; // <— contrôleur pour animer la mini-carte

  // Rejet (modération)
  String? _rejectReasonOverride;
  Map<String, String> _initial = {};
  bool _dirtySinceReject = false;
  
  bool _isPrivate = false;
  final TextEditingController _addUserCtrl = TextEditingController();
  List<String> _allowedUsers = [];

  Future<List<GameStep>>? _futureSteps;

  String? get _effectiveRejectReason =>
      (_rejectReasonOverride?.trim().isNotEmpty ?? false)
          ? _rejectReasonOverride!.trim()
          : (widget.escape.rejectReason?.trim().isNotEmpty ?? false)
              ? widget.escape.rejectReason!.trim()
              : null;

  String _humanAnswerSummary(GameStep s) {
	final t = (s.answerType ?? 'text').toLowerCase();
	switch (t) {
		case 'narration':
			return 'Narration';
		case 'matching':
			final a = s.matchLeft?.length ?? 0;
			final b = s.matchRight?.length ?? 0;
			return 'Réponse: association ($a ↔ $b)';
		case 'numeric':
			return 'Réponse: numérique';
		case 'mcq':
			final nb = s.options?.length ?? 0;
			return 'Réponse: QCM ($nb option${nb > 1 ? 's' : ''})';
		case 'text':
		default:
			return 'Réponse: texte libre';
	}
  }


  @override
  void initState() {
    super.initState();
    _startLat = widget.escape.latitude;
    _startLon = widget.escape.longitude;

    _titleCtrl    = TextEditingController(text: widget.escape.title);
    _imageCtrl    = TextEditingController(text: widget.escape.imageUrl ?? '');
    _descCtrl     = TextEditingController(text: widget.escape.description);
    _durationCtrl = TextEditingController(text: widget.escape.durationMinutes.toString());
    _victoryCtrl  = TextEditingController(text: widget.escape.victoryMessage ?? '');
    _wrongPenaltyCtrl = TextEditingController(text: '0');

    // Pré-remplissage pénalités si présents sur le modèle
    try {
      final dyn = widget.escape as dynamic;
      _penalizeWrong = (dyn.penalizeWrongAnswers as bool?) ?? false;
      final wp = (dyn.wrongAnswerPenalty as int?) ?? 0;
      _wrongPenaltyCtrl.text = '$wp';
    } catch (_) {}

    // Écouteurs “dirty”
    for (final c in [
      _titleCtrl, _imageCtrl, _descCtrl, _durationCtrl, _victoryCtrl, _wrongPenaltyCtrl,
    ]) {
      c.addListener(() {
        final changed = _hasChangedSinceSnapshot();
        if (changed != _dirtySinceReject) {
          setState(() => _dirtySinceReject = changed);
        }
      });
    }

    _reloadSteps();

    // 🔧 Hydrate TOUT depuis le détail (description/penalités/rejet…)
    _loadDetails();

    _takeSnapshot();
  }

  // ---------- Helpers statut ----------
  String get _status {
    try {
      final s = (widget.escape as dynamic).status as String?;
      return s ?? 'draft';
    } catch (_) {
      return 'draft';
    }
  }
  bool get _isDraft     => _status == 'draft';
  bool get _isSubmitted => _status == 'submitted';
  bool get _isPublished => _status == 'published';

  void _reloadSteps() {
    _futureSteps = _api.fetchSteps(widget.escape.id);
    setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _imageCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _victoryCtrl.dispose();
    _wrongPenaltyCtrl.dispose();
	_addUserCtrl.dispose();
    super.dispose();
  }

  void _openFullImage(String? url) {
    final u = url?.trim();
    if (u == null || u.isEmpty) return;
    final tag = 'escape-image-$u';
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImage(url: u, heroTag: tag),
      ),
    );
  }

  void _takeSnapshot() {
    _initial = {
      'title': _titleCtrl.text,
      'image_url': _imageCtrl.text,
      'description': _descCtrl.text,
      'victory_message': _victoryCtrl.text,
      'duration_minutes': _durationCtrl.text,
      'latitude': _startLat?.toString() ?? '',
      'longitude': _startLon?.toString() ?? '',
      'penalize_wrong_answers': _penalizeWrong ? '1' : '0',
      'wrong_answer_penalty': _wrongPenaltyCtrl.text,
    };
    _dirtySinceReject = false;
  }

  bool _hasChangedSinceSnapshot() {
    return _initial['title'] != _titleCtrl.text ||
        _initial['image_url'] != _imageCtrl.text ||
        _initial['description'] != _descCtrl.text ||
        _initial['victory_message'] != _victoryCtrl.text ||
        _initial['duration_minutes'] != _durationCtrl.text ||
        _initial['latitude'] != (_startLat?.toString() ?? '') ||
        _initial['longitude'] != (_startLon?.toString() ?? '') ||
        _initial['penalize_wrong_answers'] != (_penalizeWrong ? '1' : '0') ||
        _initial['wrong_answer_penalty']   != _wrongPenaltyCtrl.text;
  }

  // --- Recharge le détail complet (serveur) et réhydrate l’UI ---
  Future<void> _loadDetails() async {
    try {
      final fresh = await _api.fetchCreatorDetail(widget.escape.id);
      if (!mounted) return;

      setState(() {
        // Meta
        _titleCtrl.text    = fresh.title;
        _imageCtrl.text    = fresh.imageUrl ?? '';
        _descCtrl.text     = fresh.description;
        _victoryCtrl.text  = fresh.victoryMessage;
        _durationCtrl.text = '${fresh.durationMinutes}';
        _startLat          = fresh.latitude;
        _startLon          = fresh.longitude;

        // Pénalités
        _penalizeWrong         = fresh.penalizeWrongAnswers;
        _wrongPenaltyCtrl.text = '${fresh.wrongAnswerPenalty}';
		
		_isPrivate = fresh.isPrivate;
		_allowedUsers = List<String>.from(fresh.allowedUsers);

        // Statut + motif
        try { (widget.escape as dynamic).status = fresh.status; } catch (_) {}
        _rejectReasonOverride = fresh.rejectReason?.trim();
      });

      _takeSnapshot();
    } catch (e) {
      if (!mounted) return;
      // On ne bloque pas l’écran : on affiche juste un toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chargement des détails: $e')),
      );
    }
  }

  // Soumission: endpoint POST /submit
  Future<void> _submitForApproval() async {
    try {
      await _api.submitEscape(widget.escape.id);
      if (!mounted) return;
      setState(() {
        try {
          final dyn = widget.escape as dynamic;
          dyn.status = 'submitted';
          dyn.rejectReason = '';
          _rejectReasonOverride = null;
        } catch (_) {}
      });
      _takeSnapshot();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soumis pour approbation')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de soumission: $e')),
      );
    }
  }

  Future<void> _lockStartFromMyLocation() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Géolocalisation désactivée')),
      );
      return;
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission localisation refusée')),
      );
      return;
    }

    final pos = await Geolocator.getCurrentPosition();

    // 1) Persiste côté backend
    final eg = await _api.updateEscape(widget.escape.id, {
      'latitude': pos.latitude,
      'longitude': pos.longitude,
    });

    if (!mounted) return;

    // 2) Réhydrate l’UI
    setState(() {
      _applyServerEscape(eg);
      _startLat = pos.latitude;
      _startLon = pos.longitude;
      _dirtySinceReject = _hasChangedSinceSnapshot();
    });

    // 3) Centre en douceur la mini-carte
    _miniMapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude), 15,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Point de départ verrouillé sur votre position')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur géolocalisation: $e')),
    );
  }
}

  /// Upload + persist immédiatement l’URL sur l’escape.
  Future<void> _uploadAndPersist(ImageSource src) async {
    try {
      final XFile? x = await _picker.pickImage(
        source: src,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (x == null) return;
      final url = await _api.uploadImage(x);
      final eg = await _api.updateEscape(widget.escape.id, {'image_url': url});
      if (!mounted) return;
      setState(() {
        _applyServerEscape(eg);
        _imageCtrl.text = url;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image téléversée et enregistrée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload/Save: $e')),
      );
    }
  }

  Future<void> _saveMeta() async {
    // Par sécurité: l’édition est désactivée en 'submitted'
    if (_isSubmitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escape soumis : modification désactivée')),
        );
      }
      return;
    }

    try {
      final img = _imageCtrl.text.trim();
      final dur = int.tryParse(_durationCtrl.text.trim());
      final wrongPenalty = int.tryParse(_wrongPenaltyCtrl.text.trim()) ?? 0;

      final patch = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'image_url': img.isEmpty ? null : img,
        'description': _descCtrl.text.trim(),
        'victory_message': _victoryCtrl.text.trim(),
        if (dur != null) 'duration_minutes': dur,
        if (_startLat != null) 'latitude': _startLat,
        if (_startLon != null) 'longitude': _startLon,
        // Pénalités
        'penalize_wrong_answers': _penalizeWrong,
        'wrong_answer_penalty': wrongPenalty < 0 ? 0 : wrongPenalty,
		'is_private': _isPrivate,
		'allowed_usernames': _allowedUsers,
      }..removeWhere((_, v) => v == null);

      final eg = await _api.updateEscape(widget.escape.id, patch);
      if (!mounted) return;

      setState(() {
        _applyServerEscape(eg); // réhydrate depuis la réponse serveur
      });
      _takeSnapshot();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistré')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  /// Réapplique dans l’UI la réponse complète renvoyée par l’API
  void _applyServerEscape(EscapeGame eg) {
    _titleCtrl.text    = eg.title;
    _imageCtrl.text    = eg.imageUrl ?? '';
    _descCtrl.text     = eg.description;
    _victoryCtrl.text  = eg.victoryMessage;
    _durationCtrl.text = '${eg.durationMinutes}';
    _startLat          = eg.latitude;
    _startLon          = eg.longitude;

    _penalizeWrong = eg.penalizeWrongAnswers;
    _wrongPenaltyCtrl.text = '${eg.wrongAnswerPenalty}';
	
	_isPrivate    = eg.isPrivate;
	_allowedUsers = List<String>.from(eg.allowedUsers);

    try {
      (widget.escape as dynamic).status = eg.status;
      (widget.escape as dynamic).rejectReason = eg.rejectReason;
    } catch (_) {}
  }

  // -------- Bannières --------
  Widget _rejectionBanner() {
    final isRejected = (_status.toLowerCase() == 'rejected');
    final reason = _effectiveRejectReason;
    final hasReason = (reason != null && reason.trim().isNotEmpty);

    if (!isRejected && !hasReason) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'Refusé par la modération',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasReason ? reason! : 'Aucun motif communiqué.',
            style: TextStyle(color: Colors.red.shade800),
          ),
          const SizedBox(height: 8),
          Text(
            'Modifiez cet escape puis enregistrez : il repassera en brouillon. '
            'Ensuite, soumettez-le à nouveau depuis la liste.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _submittedBanner() {
    if (!_isSubmitted) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_outlined, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'En attente d’approbation – modification désactivée.',
              style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _startPointSection() {
  final canEdit = !_isSubmitted;
  final hasCoords = (_startLat != null && _startLon != null);
  final LatLng pos = hasCoords
      ? LatLng(_startLat!, _startLon!)
      : const LatLng(48.8566, 2.3522); // fallback Paris

  String _fmt(double? v) => (v == null) ? '-' : v.toStringAsFixed(6);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Ligne 1 : libellé + bouton "Ma position"
      Row(
        children: [
          const Icon(Icons.flag_circle_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Point de départ : ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: canEdit ? _lockStartFromMyLocation : null,
            child: const Text('Ma position'),
          ),
        ],
      ),
      const SizedBox(height: 8),

      // Ligne 2 : mini-carte (tap => ouvre le picker plein écran)
      GestureDetector
(
  onTap: canEdit
      ? () async {
          final picked = await Navigator.of(context).push<LatLng>(
            MaterialPageRoute(builder: (_) => MapPickerPage(initial: pos)),
          );
          if (picked != null && mounted) {
            setState(() {
              _startLat = picked.latitude;
              _startLon = picked.longitude;
              _dirtySinceReject = _hasChangedSinceSnapshot();
            });
            // recentre en douceur la mini-carte
            _miniMapCtrl?.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(_startLat!, _startLon!), 15,
              ),
            );
          }
        }
      : null,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 160,
      width: double.infinity,
      // on garde l’aperçu non interactif, mais l’animation fonctionne
      child: AbsorbPointer(
        absorbing: true,
        child: GoogleMap(
          onMapCreated: (c) => _miniMapCtrl = c, // <— récupère le contrôleur
          initialCameraPosition: CameraPosition(target: pos, zoom: 15),
          markers: {
            Marker(
              markerId: const MarkerId('start'),
              position: pos,
            ),
          },
          // IMPORTANT: pas de liteMode si on veut animer la caméra
          liteModeEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    ),
  ),
),
    ],
  );
}

  Widget _publishedInfoBanner() {
    if (!_isPublished) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Toute modification repassera cet escape en brouillon.',
              style: TextStyle(color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.escape;

    return Scaffold(
      appBar: AppBar(
        title: Text('Édition: ${_titleCtrl.text}'),
        actions: [
          IconButton(
            tooltip: 'Enregistrer',
            icon: const Icon(Icons.save_outlined),
            onPressed: _isSubmitted ? null : _saveMeta,
          ),
        ],
      ),

      // En “submitted”, on masque le FAB d’ajout d’étape
      floatingActionButton: _isSubmitted
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final nextOrder = () async {
                  final steps = await _api.fetchSteps(e.id);
                  return (steps.isEmpty)
                      ? 1
                      : (steps.map((s) => s.order).reduce((a, b) => a > b ? a : b) + 1);
                };
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => StepEditorPage(
                      escapeId: e.id,
                      existing: null,
                      nextOrderResolver: nextOrder,
                    ),
                  ),
                );
                if (changed == true) _reloadSteps();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une étape'),
            ),

      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Bannières
          _rejectionBanner(),
          _submittedBanner(),
          _publishedInfoBanner(),

          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            enabled: !_isSubmitted,
            decoration: const InputDecoration(
              labelText: 'Titre',
              hintText: 'Nom de l’escape',
            ),
          ),

          const SizedBox(height: 12),
          const Text('Image', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _openFullImage(_imageCtrl.text), // consultable même en submitted
            child: Hero(
              tag: 'escape-image-${_imageCtrl.text}',
              child: _imageThumb(_imageCtrl.text),
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Depuis la galerie'),
                onPressed: _isSubmitted ? null : () => _uploadAndPersist(ImageSource.gallery),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Prendre une photo'),
                onPressed: _isSubmitted ? null : () => _uploadAndPersist(ImageSource.camera),
              ),
            ],
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            enabled: !_isSubmitted,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _victoryCtrl,
            enabled: !_isSubmitted,
            decoration: const InputDecoration(
              labelText: 'Message de fin (victoire)',
              hintText: 'Texte affiché sur l’écran de victoire',
            ),
            minLines: 2,
            maxLines: 5,
          ),

          const SizedBox(height: 8),
          TextField(
            controller: _durationCtrl,
            enabled: !_isSubmitted,
            decoration: const InputDecoration(labelText: 'Durée estimée (min)'),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 12),
		  _startPointSection(),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Pénalités', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          SwitchListTile(
            value: _penalizeWrong,
            onChanged: _isSubmitted
                ? null
                : (v) => setState(() {
                      _penalizeWrong = v;
                      _dirtySinceReject = _hasChangedSinceSnapshot();
                    }),
            title: const Text('Pénaliser les mauvaises réponses'),
            subtitle: const Text('Ajoute du temps au chrono en cas de mauvaise réponse'),
          ),

          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _penalizeWrong ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !_penalizeWrong || _isSubmitted,
              child: TextField(
                controller: _wrongPenaltyCtrl,
                enabled: !_isSubmitted && _penalizeWrong,
                decoration: const InputDecoration(
                  labelText: 'Pénalité par mauvaise réponse (minutes)',
                  hintText: 'ex: 5',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ),
		  
		  // ------------------ Visibilité ------------------
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Visibilité', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          SwitchListTile(
            value: _isPrivate,
            onChanged: _isSubmitted ? null : (v) => setState(() => _isPrivate = v),
            title: const Text('Privé'),
            subtitle: const Text('Seuls vous et les utilisateurs désignés pourront voir cet escape'),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: !_isPrivate
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addUserCtrl,
                              enabled: !_isSubmitted,
                              decoration: const InputDecoration(
                                labelText: 'Ajouter un utilisateur par pseudo',
                                hintText: 'ex: alice, bob42…',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _isSubmitted
                                ? null
                                : () {
                                    final u = _addUserCtrl.text.trim();
                                    if (u.isEmpty) return;
                                    if (!_allowedUsers.contains(u)) {
                                      setState(() => _allowedUsers.add(u));
                                    }
                                    _addUserCtrl.clear();
                                  },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Ajouter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_allowedUsers.isEmpty)
                        Text(
                          'Aucun utilisateur désigné.',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: -8,
                          children: [
                            for (final u in _allowedUsers)
                              Chip(
                                label: Text(u),
                                onDeleted: _isSubmitted
                                    ? null
                                    : () => setState(() => _allowedUsers.remove(u)),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
          // ---------------- Fin visibilité ----------------

          const SizedBox(height: 8),
          const Text('Étapes', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<GameStep>>(
            future: _futureSteps,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snap.hasError) {
                return Text('Erreur: ${snap.error}');
              }
              final steps = snap.data ?? [];
              if (steps.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune étape pour le moment.'),
                );
              }
              return Column(
                children: [
                  for (final s in steps)
                    ListTile(
                      leading: CircleAvatar(child: Text('${s.order}')),
                      title: Text(s.title),
                      subtitle: Text(_humanAnswerSummary(s)),
                      onTap: _isSubmitted
                          ? null
                          : () async {
                              final changed = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => StepEditorPage(
                                    escapeId: e.id,
                                    existing: s,
                                  ),
                                ),
                              );
                              if (changed == true) _reloadSteps();
                            },
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Éditer',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: _isSubmitted
                                ? null
                                : () async {
                                    final changed = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => StepEditorPage(
                                          escapeId: e.id,
                                          existing: s,
                                        ),
                                      ),
                                    );
                                    if (changed == true) _reloadSteps();
                                  },
                          ),
                          IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _isSubmitted
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Supprimer l’étape ?'),
                                        content: Text('“${s.title}”'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Annuler'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Supprimer'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await _api.deleteStep(e.id, s.id);
                                      _reloadSteps();
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}


class MapPickerPage extends StatefulWidget {
  final LatLng initial;
  const MapPickerPage({super.key, required this.initial});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  late LatLng _pos;
  GoogleMapController? _ctrl;

  @override
  void initState() {
    super.initState();
    _pos = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir le point de départ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_pos),
            child: const Text('Valider'),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _pos, zoom: 15),
        onMapCreated: (c) => _ctrl = c,
        markers: {
          Marker(
            markerId: const MarkerId('picker'),
            position: _pos,
            draggable: true,
            onDragEnd: (p) => setState(() => _pos = p),
          ),
        },
        onTap: (p) => setState(() => _pos = p),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pop(_pos),
        icon: const Icon(Icons.check),
        label: const Text('Valider'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}


class StepEditorPage extends StatefulWidget {
  final int escapeId;
  final GameStep? existing;
  final Future<int> Function()? nextOrderResolver;

  const StepEditorPage({
    super.key,
    required this.escapeId,
    this.existing,
    this.nextOrderResolver,
  });

  @override
  State<StepEditorPage> createState() => _StepEditorPageState();
}

class _StepEditorPageState extends State<StepEditorPage> {
  final _api = ApiService.instance;
  final _picker = ImagePicker();

  // --- Contrôleurs “métadonnées”
  late TextEditingController _title;
  late TextEditingController _text;
  late TextEditingController _imageUrl;
  late TextEditingController _lat;
  late TextEditingController _lon;

  // Multi-indices
  final List<TextEditingController> _hintCtrls = <TextEditingController>[];
  late TextEditingController _hintPenalty;

  // Réponses
  late TextEditingController _answerText;
  late TextEditingController _orderCtrl;

  GoogleMapController? _stepMapCtrl;

  // --- Type de réponse & dépendances
  String _answerType = 'text';

  // QCM
  List<TextEditingController> _options = [];
  int? _correctIndex;

  // MATCHING (Association) — mode créateur
  final int _maxPairs = 10;
  List<TextEditingController> _leftCtrls = [];
  List<TextEditingController> _rightCtrls = [];
  // Ordre courant pour B: ligne -> index original B
  List<int> _rightOrder = [];
  // Sélection (ligne pour A, index original pour B)
  int? _selA;
  int? _selB;

  bool get _isEdit => widget.existing != null;

  String _stepHeroTag() => 'step-image-${widget.existing?.id ?? 'new'}-${_imageUrl.text}';

  // ---------- Helpers image ----------
  void _openFullImage(String? url) {
    final u = url?.trim();
    if (u == null || u.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImage(url: u, heroTag: _stepHeroTag()),
      ),
    );
  }

  // ---------- Éditeur d’indices (multi) ----------
  Widget _hintsEditor() {
    return Column(
      children: [
        for (int i = 0; i < _hintCtrls.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _hintCtrls[i],
                  decoration: InputDecoration(
                    labelText: 'Indice ${i + 1}',
                    hintText: 'Texte de l’indice',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Supprimer cet indice',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _hintCtrls.length <= 1
                    ? null
                    : () => setState(() {
                          _hintCtrls.removeAt(i).dispose();
                        }),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _hintCtrls.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un indice'),
          ),
        ),
      ],
    );
  }

  Widget _stepImageThumb(String? url) {
    final u = url?.trim();
    final has = (u != null && u.isNotEmpty);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: has ? const Color(0xFFF7F7F7) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x11000000)),
      ),
      alignment: Alignment.center,
      child: has
          ? FittedBox(
              fit: BoxFit.contain,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  u!,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Impossible de charger l’image'),
                  ),
                ),
              ),
            )
          : const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Aucune image'),
            ),
    );
  }

  // ---------- Lifecycle ----------
  @override
  void initState() {
    super.initState();
    final s = widget.existing;

    _title        = TextEditingController(text: s?.title ?? '');
    _text         = TextEditingController(text: s?.text ?? '');
    _imageUrl     = TextEditingController(text: s?.imageUrl ?? '');
    _lat          = TextEditingController(text: s?.latitude?.toString() ?? '');
    _lon          = TextEditingController(text: s?.longitude?.toString() ?? '');
    _hintPenalty  = TextEditingController(text: s?.hintPenalty.toString() ?? '0');
    _answerType   = s?.answerType ?? 'text';
    _answerText   = TextEditingController(text: s?.answerText ?? '');
    _correctIndex = s?.correctIndex;
    _orderCtrl    = TextEditingController(text: s?.order.toString() ?? '');

    // --- Multi-indices : préférer s.hints, fallback sur s.hint (legacy)
    final existingHints = (s?.hints ?? const <String>[]);
    if (existingHints.isNotEmpty) {
      _hintCtrls.addAll(existingHints.map((h) => TextEditingController(text: h)));
    } else {
      final legacy = (s?.hint ?? '').trim();
      _hintCtrls.add(
        legacy.isNotEmpty ? TextEditingController(text: legacy) : TextEditingController(),
      );
    }

    // --- QCM
    if (s?.options.isNotEmpty ?? false) {
      _options = s!.options.map((o) => TextEditingController(text: o)).toList();
    } else {
      _options = [TextEditingController(), TextEditingController()];
    }

    // --- MATCHING
    final List<String> existingLeft  = List<String>.from(s?.matchLeft  ?? const <String>[]);
    final List<String> existingRight = List<String>.from(s?.matchRight ?? const <String>[]);

    int len = existingLeft.length;
    if (existingRight.length < len) len = existingRight.length;
    if (len == 0) len = 2; // défaut 2 paires

    _leftCtrls  = List<TextEditingController>.generate(
      len,
      (i) => TextEditingController(text: (i < existingLeft.length) ? existingLeft[i] : ''),
    );
    _rightCtrls = List<TextEditingController>.generate(
      len,
      (i) => TextEditingController(text: (i < existingRight.length) ? existingRight[i] : ''),
    );

    // Ordre B depuis match_pairs si dispo, sinon identité
    final List<List<int>> pairs = List<List<int>>.from(s?.matchPairs ?? const <List<int>>[]);
    if (pairs.isNotEmpty) {
      final mapLeftToRight = <int, int>{};
      for (final p in pairs) {
        if (p.length == 2) mapLeftToRight[p[0]] = p[1];
      }
      _rightOrder = List<int>.generate(len, (row) {
        final r = mapLeftToRight[row];
        if (r != null && r >= 0 && r < existingRight.length) return r;
        return row.clamp(0, existingRight.length - 1);
      });
    } else {
      _rightOrder = List<int>.generate(len, (i) => i);
    }

    if (!_isEdit) _resolveDefaultOrder();
    WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  Future<void> _resolveDefaultOrder() async {
    if (widget.nextOrderResolver == null) return;
    final n = await widget.nextOrderResolver!();
    _orderCtrl.text = '$n';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _options) c.dispose();
    for (final c in _leftCtrls) c.dispose();
    for (final c in _rightCtrls) c.dispose();
    for (final c in _hintCtrls) c.dispose();

    _title.dispose();
    _text.dispose();
    _imageUrl.dispose();
    _lat.dispose();
    _lon.dispose();
    _hintPenalty.dispose();
    _answerText.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  // ---------- Actions génériques ----------
  Future<String?> _pickAndUploadStep(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (x == null) return null;
      final url = await ApiService.instance.uploadImage(x);
      if (!mounted) return url;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image téléversée')),
      );
      return url;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload: $e')),
      );
      return null;
    }
  }

  Future<void> _pickAndSetImage(ImageSource source) async {
    try {
      final XFile? x = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (x == null) return;
      final url = await _api.uploadImage(x);
      if (!mounted) return;
      setState(() => _imageUrl.text = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image téléversée (enregistrer pour valider)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload: $e')),
      );
    }
  }

  Future<void> _lockStepFromMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Géolocalisation désactivée')),
        );
        return;
      }
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission localisation refusée')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lon.text = pos.longitude.toStringAsFixed(6);
      });

      _stepMapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pos.latitude, pos.longitude),
          16,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur géolocalisation: $e')),
      );
    }
  }

  // ---------- Matching: logique principale ----------
  int _rowCount() => [
        _leftCtrls.length,
        _rightCtrls.length,
        _rightOrder.length,
      ].reduce((a, b) => a < b ? a : b);

  void _onTapA(int row) {
    setState(() => _selA = (_selA == row) ? null : row);
    _pairIfReady();
  }

  void _onTapB(int bOriginal) {
    setState(() => _selB = (_selB == bOriginal) ? null : bOriginal);
    _pairIfReady();
  }

  void _pairIfReady() {
    if (_selA == null || _selB == null) return;
    int rowA = _selA!.clamp(0, _rightOrder.length - 1);
    final posB = _rightOrder.indexOf(_selB!);
    if (posB < 0) {
      setState(() {
        _selA = null;
        _selB = null;
      });
      return;
    }
    setState(() {
      final moving = _rightOrder.removeAt(posB);
      _rightOrder.insert(rowA, moving);
      _selA = null;
      _selB = null;
    });
  }

  // --- Ajout / suppression par PAIRE ---
  void _addPair() {
    final len = _leftCtrls.length;
    if (len >= _maxPairs) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_maxPairs paires.')),
      );
      return;
    }
    setState(() {
      _leftCtrls.add(TextEditingController());
      _rightCtrls.add(TextEditingController());
      _rightOrder.add(_rightCtrls.length - 1);
      _selA = null;
      _selB = null;
    });
  }

  void _removePairAtRow(int row) {
    if (row < 0 || row >= _rowCount()) return;
    final bOriginal = _rightOrder[row];
    setState(() {
      _leftCtrls.removeAt(row).dispose();
      _rightCtrls.removeAt(bOriginal).dispose();
      _rightOrder.removeAt(row);
      for (int i = 0; i < _rightOrder.length; i++) {
        if (_rightOrder[i] > bOriginal) _rightOrder[i] -= 1;
      }
      _selA = null;
      _selB = null;
    });
  }

  // ---------- Sauvegarde ----------
  Future<void> _save() async {
  try {
    final order = int.tryParse(_orderCtrl.text.trim()) ?? 1;
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    final hintPenalty = int.tryParse(_hintPenalty.text.trim()) ?? 0;

    // collecte des indices (multi)
    final List<String> hints = _hintCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final step = GameStep(
      id: _isEdit ? widget.existing!.id : 0,
      escapeId: widget.escapeId,
      order: order,
      title: _title.text.trim(),
      text: _text.text.trim(),
      latitude: lat,
      longitude: lon,
      imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      answerType: _answerType,
      answerText: _answerText.text.trim(),
      options: _options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
      correctIndex: _answerType == 'mcq' ? _correctIndex : null,

      // Matching (solution côté éditeur)
      matchLeft: _leftCtrls.map((c) => c.text.trim()).toList(),
      matchRight: _rightCtrls.map((c) => c.text.trim()).toList(),
      matchPairs: List<List<int>>.generate(_rowCount(), (i) => [i, i]),

      // Multi-indices (modèle)
      hints: hints,
      hint: '', // legacy neutralisé
      hintPenalty: hintPenalty,
    );

    // on construit un patch pour fiabiliser l’UPDATE (et pour forcer narration)
    final Map<String, dynamic> patch = step.toPayload();
    patch['hints'] = hints;
    patch['hint'] = '';
    patch['hint_penalty'] = hintPenalty;

    if (_answerType == 'narration') {
      // Neutraliser réponses + indices
      patch['answer_type']   = 'narration';
      patch['answer_text']   = '';
      patch['options']       = [];
      patch['correct_index'] = null;
      patch['match_left']    = [];
      patch['match_right']   = [];
      patch['match_pairs']   = [];
      patch['hints']         = [];
      patch['hint']          = '';
      patch['hint_penalty']  = 0;
    }

    if (_answerType == 'matching') {
      final len = _rowCount();
      if (len == 0) throw Exception('Ajoute au moins une paire.');
      if (len > _maxPairs) throw Exception('Maximum $_maxPairs paires.');

      final leftOrdered  = <String>[];
      final rightOrdered = <String>[];

      for (int row = 0; row < len; row++) {
        final l = _leftCtrls[row].text.trim();
        final bOriginal = _rightOrder[row];
        final r = (bOriginal >= 0 && bOriginal < _rightCtrls.length)
            ? _rightCtrls[bOriginal].text.trim()
            : '';
        if (l.isEmpty || r.isEmpty) {
          throw Exception('Les items A et B doivent être remplis (ligne ${row + 1}).');
        }
        leftOrdered.add(l);
        rightOrdered.add(r);
      }

      patch['answer_type']   = 'matching';
      patch['answer_text']   = '';
      patch['options']       = [];
      patch['correct_index'] = null;
      patch['match_left']    = leftOrdered;
      patch['match_right']   = rightOrdered;
      patch['match_pairs']   = List<List<int>>.generate(len, (i) => [i, i]);
    }

    if (_answerType == 'numeric' && _answerText.text.trim().isEmpty) {
      throw Exception("Renseigne la réponse numérique attendue.");
    }

    if (_isEdit) {
      // UPDATE: on envoie le patch (Map)
      await _api.updateStep(widget.escapeId, widget.existing!.id, patch);
    } else {
      // CREATE: on repasse un GameStep (ton API attend un GameStep ici)
      await _api.createStep(widget.escapeId, step);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Étape enregistrée')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erreur: $e')),
    );
  }
}


  // ---------- Mini-carte ----------
  Widget _stepPointSection() {
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    final hasCoords = (lat != null && lon != null);
    final LatLng pos = hasCoords
        ? LatLng(lat!, lon!)
        : const LatLng(48.8566, 2.3522);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flag_circle_outlined),
            const SizedBox(width: 8),
            const Expanded(child: Text('Point de cette étape :')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _lockStepFromMyLocation,
              child: const Text('Ma position'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await Navigator.of(context).push<LatLng>(
              MaterialPageRoute(builder: (_) => MapPickerPage(initial: pos)),
            );
            if (picked != null && mounted) {
              setState(() {
                _lat.text = picked.latitude.toStringAsFixed(6);
                _lon.text = picked.longitude.toStringAsFixed(6);
              });
              _stepMapCtrl?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(picked.latitude, picked.longitude),
                  16,
                ),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: AbsorbPointer(
                absorbing: true,
                child: GoogleMap(
                  onMapCreated: (c) => _stepMapCtrl = c,
                  initialCameraPosition: CameraPosition(target: pos, zoom: 15),
                  markers: {
                    Marker(markerId: const MarkerId('step'), position: pos),
                  },
                  liteModeEnabled: false,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- UI matching editor (creator) ----------
  Widget _matchingEditor() {
    final cs = Theme.of(context).colorScheme;
    final len = _rowCount();

    Widget aCell(int row) {
      final selected = (_selA == row);
      return InkWell(
        onTap: () => _onTapA(row),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.secondary : cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 12),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _leftCtrls[row],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Item A',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer la paire',
                onPressed: () => _removePairAtRow(row),
                icon: const Icon(Icons.delete_outline),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      );
    }

    Widget bCell(int row) {
      final bOriginal = (row < _rightOrder.length) ? _rightOrder[row] : row;
      final selected  = (_selB == bOriginal);
      final ctrl = (bOriginal >= 0 && bOriginal < _rightCtrls.length)
          ? _rightCtrls[bOriginal]
          : TextEditingController();

      return InkWell(
        onTap: () => _onTapB(bOriginal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.square, size: 12),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Item B',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Association (créateur) — Clique un A puis un B (ou l’inverse) pour les aligner.'),
        const SizedBox(height: 12),

        for (int row = 0; row < len; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: aCell(row)),
                  const SizedBox(width: 12),
                  Expanded(child: bCell(row)),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _addPair,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une paire'),
            ),
            const Spacer(),
            Text(
              '$len / $_maxPairs paires',
              style: TextStyle(color: cs.outline),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier une étape' : 'Nouvelle étape'),
        actions: [
          IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ordre (1..N)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 3,
            maxLines: 6,
          ),

          const SizedBox(height: 8),
          const Text('Image', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _openFullImage(_imageUrl.text),
            child: Hero(
              tag: _stepHeroTag(),
              child: _stepImageThumb(_imageUrl.text),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Depuis la galerie'),
                onPressed: () async {
                  final url = await _pickAndUploadStep(ImageSource.gallery);
                  if (url == null) return;
                  setState(() => _imageUrl.text = url);
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Prendre une photo'),
                onPressed: () async {
                  final url = await _pickAndUploadStep(ImageSource.camera);
                  if (url == null) return;
                  setState(() => _imageUrl.text = url);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Options avancées (URL brute)'),
            children: [
              TextField(
                controller: _imageUrl,
                decoration: const InputDecoration(
                  labelText: 'Image (URL)',
                  hintText: 'https://...',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),

          // (masquer la carte pour Narration)
          if (_answerType != 'narration') ...[
            const SizedBox(height: 8),
            _stepPointSection(),
          ],

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),

          Row(
            children: [
              const Text('Type de réponse:'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _answerType,
                items: const [
                  DropdownMenuItem(value: 'text',     child: Text('Texte libre')),
                  DropdownMenuItem(value: 'mcq',      child: Text('Choix multiple')),
                  DropdownMenuItem(value: 'numeric',  child: Text('Numérique')),
                  DropdownMenuItem(value: 'matching', child: Text('Association')),
                  DropdownMenuItem(value: 'narration', child: Text('Narration')),
                ],
                onChanged: (v) => setState(() => _answerType = v ?? 'text'),
              ),
            ],
          ),

          const SizedBox(height: 8),
          if (_answerType == 'text') ...[
            TextField(
              controller: _answerText,
              decoration: const InputDecoration(labelText: 'Réponse attendue'),
            ),
          ] else if (_answerType == 'numeric') ...[
            TextField(
              controller: _answerText,
              decoration: const InputDecoration(labelText: 'Réponse attendue (nombre)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
            ),
          ] else if (_answerType == 'mcq') ...[
            const Text('Options', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (int i = 0; i < _options.length; i++)
              Row(
                children: [
                  Radio<int?>(
                    value: i,
                    groupValue: _correctIndex,
                    onChanged: (v) => setState(() => _correctIndex = v),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _options[i],
                      decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _options.length <= 2
                        ? null
                        : () => setState(() {
                              _options.removeAt(i).dispose();
                              if (_correctIndex != null && _correctIndex! >= _options.length) {
                                _correctIndex = null;
                              }
                            }),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _options.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une option'),
              ),
            ),
          ] else if (_answerType == 'matching') ...[
            _matchingEditor(),
          ] else if (_answerType == 'narration') ...[
            // Rien : narration = contenu non interactif (on laisse Titre / Description / Image)
          ],

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),

          // Masquer Indices / Pénalité pour Narration
          if (_answerType != 'narration') ...[
            const Text('Indices', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _hintsEditor(),
            const SizedBox(height: 8),
            TextField(
              controller: _hintPenalty,
              decoration: const InputDecoration(labelText: 'Pénalité par indice (minutes)'),
              keyboardType: TextInputType.number,
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}


// --- Simple fullscreen image preview used by StepEditorPage ---
class _FullScreenImage extends StatelessWidget {
  final String url;
  final String heroTag;
  const _FullScreenImage({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Impossible de charger l’image', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/* ============================
   DIALOG AUTH
============================ */

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();
  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _register = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_register ? 'Créer un compte' : 'Se connecter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: 'Nom d’utilisateur'),
          ),
          TextField(
            controller: _passCtrl,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
            obscureText: true,
          ),
          if (_register)
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email (optionnel)'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _register,
                onChanged: (v) => setState(() => _register = v ?? false),
              ),
              const Text('Créer un compte'),
            ],
          )
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_register ? 'Créer' : 'Connexion'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_register) {
        await AuthService.instance.register(
          _userCtrl.text.trim(),
          _passCtrl.text.trim(),
          _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        );
      } else {
        await AuthService.instance.login(
          _userCtrl.text.trim(),
          _passCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

}

class SplashBootstrap extends StatefulWidget {
  const SplashBootstrap({Key? key}) : super(key: key);

  @override
  State<SplashBootstrap> createState() => _SplashBootstrapState();
}

class _SplashBootstrapState extends State<SplashBootstrap> {

Future<void> _bootstrap() async {
    try {
      await ApiService.instance.ping();
      LatLng center = const LatLng(48.8566, 2.3522); // fallback Paris
try {
  final enabled = await Geolocator.isLocationServiceEnabled();
  LocationPermission p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) {
    p = await Geolocator.requestPermission();
  }
  if (enabled && p != LocationPermission.denied && p != LocationPermission.deniedForever) {
    final pos = await Geolocator.getCurrentPosition();
    center = LatLng(pos.latitude, pos.longitude);
  }
} catch (_) {
  // garde le fallback Paris
}
      final results = await Future.wait<List<EscapeGame>>([
        ApiService.instance.fetchAll(),
        ApiService.instance.fetchNearby(
          lat: center.latitude,
          lon: center.longitude,
          radiusKm: kDefaultRadiusKm,
        ),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <List<EscapeGame>>[<EscapeGame>[], <EscapeGame>[]],
      );
      // Optionnel: stocker results dans un cache global si désiré
    } catch (e) {
      debugPrint('[BOOTSTRAP] erreur: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainHome()),
    );
  }

  String _status = 'Initialisation…';

// Progression (3 tâches : Liste, Carte, Créateur)
int _loaded = 0;
static const int _totalTasks = 3;
double get _progress => _loaded / _totalTasks;
void _markLoaded() {
  if (mounted) setState(() => _loaded = (_loaded + 1).clamp(0, _totalTasks));
}

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
  final started = DateTime.now();
  try {
    // 0) Charger la modération locale (ids + motifs)
    await ApiService.instance.loadLocalModeration();

    // 1) Pré-chauffage DNS/TLS + API (petit GET)
    setState(() => _status = 'Connexion au serveur…');
    await ApiService.instance.ping();

      // 2) Géoloc best effort (ne bloque pas l’app si refusée)
      setState(() => _status = 'Récupération de la position…');
      LatLng? userLoc;
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (enabled) {
          var p = await Geolocator.checkPermission();
          if (p == LocationPermission.denied) {
            p = await Geolocator.requestPermission();
          }
          if (p != LocationPermission.denied &&
              p != LocationPermission.deniedForever) {
            final pos = await Geolocator.getCurrentPosition()
                .timeout(const Duration(seconds: 3));
            userLoc = LatLng(pos.latitude, pos.longitude);
          }
        }
      } catch (_) {
        // ignore: on garde userLoc=null => fallback dans ta MapPage
      }

      // 3) Préchargements séquentiels + progression (3 étapes)
setState(() => _status = 'Chargement de la liste…');
await ApiService.instance
    .fetchAll()
    .then((_) => _markLoaded())
    .catchError((e) {
      debugPrint('[BOOT] fetchAll erreur: $e');
      // IMPORTANT : renvoyer un type compatible
      return <EscapeGame>[];
    });

setState(() => _status = 'Chargement de la carte…');
await ApiService.instance
    .fetchNearby(
      lat: userLoc?.latitude ?? 48.8566,
      lon: userLoc?.longitude ?? 2.3522,
      radiusKm: 20,
    )
    .then((_) => _markLoaded())
    .catchError((e) {
      debugPrint('[BOOT] fetchNearby erreur: $e');
      return <EscapeGame>[];
    });

setState(() => _status = 'Préparation du mode créateur…');
await ApiService.instance
    .fetchMe()
    .then((me) async {
      if (me != null) {
        try {
          await ApiService.instance
              .fetchCreatorList()
              .catchError((_) => <EscapeGame>[]);
        } catch (_) {}
      }
      _markLoaded();
      return null; // type Map<String,dynamic>? OK
    })
    .catchError((e) {
      debugPrint('[BOOT] fetchMe erreur: $e');
      _markLoaded();
      return null;
    });



      // 4) Respecter un temps minimum d’affichage “clean”
      final elapsed = DateTime.now().difference(started);
      const minSplash = Duration(milliseconds: 800);
      if (elapsed < minSplash) {
        await Future.delayed(minSplash - elapsed);
      }

      if (!mounted) return;
      // 5) Ouvrir l’app (onglet Carte déjà sélectionné dans ton MainScaffold)
      Navigator.of(context).pushReplacement(
  MaterialPageRoute(builder: (_) => const MainHome()),
);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Impossible de démarrer (${e.toString()}).');
      // Petit retry bouton ?
      await Future.delayed(const Duration(seconds: 1));
      _boot();
    }
  }

  @override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        // --- Logo plein écran ---
        Image.asset(
          kLogoAsset,
          fit: BoxFit.cover, // occupe tout l'écran
          errorBuilder: (_, __, ___) => const FlutterLogo(size: 160),
        ),

        // --- Voile sombre pour lisibilité du texte ---
        Container(color: Colors.black.withOpacity(0.35)),

        // --- Infos en bas : barre, statut, compteur ---
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barre de progression déterminée (N/3) ou indéterminée au départ
                SizedBox(
                  width: double.infinity,
                  child: LinearProgressIndicator(
                    value: (_progress <= 0 || _progress.isNaN) ? null : _progress,
                    minHeight: 6,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(height: 12),
                // Statut + Compteur
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_loaded}/$_totalTasks',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}

/// Carte cible à droite avec effet “aimant” + capsule liée + croix pour détacher.
class _RightTargetCard extends StatefulWidget {
  final String title;
  final bool isAssigned;
  final String? assignedLeftLabel;
  final VoidCallback onUnassign;
  final ValueChanged<int> onAcceptLeftIndex;

  const _RightTargetCard({
    required this.title,
    required this.isAssigned,
    required this.assignedLeftLabel,
    required this.onUnassign,
    required this.onAcceptLeftIndex,
  });

  @override
  State<_RightTargetCard> createState() => _RightTargetCardState();
}

class _RightTargetCardState extends State<_RightTargetCard> with SingleTickerProviderStateMixin {
  bool _hovering = false;       // survol visuel (web/desktop)
  bool _candidateOver = false;  // un draggable est au-dessus

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // couleurs selon état
    final bool active = widget.isAssigned || _candidateOver;
    final bg = active ? cs.secondaryContainer : cs.surface;
    final fg = active ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final borderColor = _candidateOver ? cs.secondary : cs.outlineVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit:  (_) => setState(() => _hovering = false),
      child: DragTarget<int>(
        onWillAccept: (_) {
          setState(() => _candidateOver = true);
          return true;
        },
        onLeave: (_) => setState(() => _candidateOver = false),
        onAccept: (leftIdx) {
          setState(() => _candidateOver = false);
          widget.onAcceptLeftIndex(leftIdx);
        },
        builder: (context, candidate, rejected) {
          return AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: _candidateOver ? 1.02 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: _candidateOver ? 2 : 1),
                boxShadow: _hovering
                    ? [BoxShadow(blurRadius: 10, offset: const Offset(0, 6), color: Colors.black.withOpacity(0.08))]
                    : const [],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Libellé de droite
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Capsule de gauche “collée” + croix pour détacher (si assigné)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.isAssigned
                        ? Container(
                            key: const ValueKey('assigned'),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cs.primary.withOpacity(0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  widget.assignedLeftLabel ?? '',
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: widget.onUnassign,
                                  child: const Padding(
                                    padding: EdgeInsets.all(2.0),
                                    child: Icon(Icons.close, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            key: const ValueKey('unassigned'),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.surfaceVariant,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Text(
                              'Glisser un élément A',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

