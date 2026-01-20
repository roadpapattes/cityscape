
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

// Import models
import 'models/escape_game.dart';
import 'models/game_step.dart';
import 'models/comment_item.dart';
import 'models/user_me.dart';
import 'models/cache_entry.dart';

// Import core utilities and constants
import 'core/constants.dart';
import 'core/utils/type_utils.dart';

// Import services
import 'services/preferences_service.dart';
import 'core/utils/image_utils.dart';

// Import services
import 'services/game_timer_service.dart';
import 'services/auth_service.dart';
import 'services/api/api_service.dart';

// Import core widgets
import 'core/widgets/timer_badge.dart';
import 'core/widgets/creator_feedback_sheet.dart';

// Import features
import 'features/splash/splash_screen.dart';
import 'features/home/main_home.dart';

// Utility functions have been moved to core/utils/

// openCreatorFeedbackSheet has been moved to core/widgets/creator_feedback_sheet.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ouvre le cache Hive + charge l'auth depuis les prefs
  await ApiService.instance.initCache();
  await AuthService.instance.loadFromPrefs();
  await PreferencesService.instance.initialize();

  runApp(const CityscapeApp());
}

// Constants have been moved to core/constants.dart

class CityscapeApp extends StatelessWidget {
  const CityscapeApp({super.key});

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

// GameTimer has been moved to services/game_timer_service.dart

// MainHome and _MainHomeState have been moved to features/home/main_home.dart

// TimerBadge has been moved to core/widgets/timer_badge.dart

// _CacheEntry has been moved to models/cache_entry.dart as CacheEntry

// _TitleWithUser and _TitleWithUserState have been moved to features/home/main_home.dart

// _openAuthDialog has been moved to features/home/main_home.dart

/* ============================
   MODELS + SERVICES
============================ */

// EscapeGame has been moved to models/escape_game.dart

// CommentItem has been moved to models/comment_item.dart

// GameStep has been moved to models/game_step.dart

// ApiService has been moved to services/api/api_service.dart


// UserMe has been moved to models/user_me.dart

// AuthService has been moved to services/auth_service.dart

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
                              normalizeImageUrl(img, baseUrl),
                              fit: BoxFit.contain,
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
   Moved to: lib/features/list/list_page.dart
============================ */

/* ============================
   WIDGETS : CARTE (simplifiée)
   Moved to: lib/features/map/map_page.dart
============================ */

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
  bool _hasStarted = false;  // true si l'utilisateur a déjà commencé cet escape
  int _currentStepIndex = 0; // index de l'étape en cours (0-based)
  int _totalSteps = 0;       // nombre total d'étapes
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
      if (j != null) {
        // Récupérer les infos de progression
        _totalSteps = (j['total_steps'] as int?) ?? (j['total'] as int?) ?? 0;
        _currentStepIndex = (j['step_index'] as int?) ?? 0;

        if (j['finished'] == true) {
          _alreadyFinished = true;
          _hasStarted = true;
          final s = (j['completed_at'] ?? j['finished_at']) as String?;
          if (s != null) {
            final parsed = DateTime.tryParse(s);
            _completedAt = parsed?.toLocal(); // heure locale
          }
        } else {
          _alreadyFinished = false;
          _completedAt = null;
          // L'utilisateur a commencé si on a une session avec step_index > 0
          // ou si la session existe tout simplement
          _hasStarted = true;
        }
      } else {
        // Pas de session existante
        _alreadyFinished = false;
        _hasStarted = false;
        _completedAt = null;
        _currentStepIndex = 0;
        _totalSteps = 0;
      }
    } catch (_) {
      // on ignore et on laisse le bouton actif si on ne sait pas
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _openDirections() async {
    final e = widget.escape;
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${e.latitude},${e.longitude}'
      '&travelmode=walking',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
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
                normalizeImageUrl(e.imageUrl, baseUrl),
                height: 180,
                width: double.infinity,
                fit: BoxFit.contain,
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(_hasStarted && !_alreadyFinished ? Icons.play_arrow : Icons.play_arrow),
                  label: Text(
                    _alreadyFinished
                        ? 'Terminé'
                        : (_hasStarted && _totalSteps > 0
                            ? 'Reprendre (${_currentStepIndex + 1}/$_totalSteps)'
                            : 'Démarrer'),
                  ),
                  onPressed: _alreadyFinished
                      ? null
                      : () async {
                          try {
                            await _api.startSession(e.id); // crée/reprend la session

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
              ),
              const SizedBox(width: 12),
              // Bouton Itinéraire
              OutlinedButton.icon(
                icon: const Icon(Icons.directions_walk),
                label: const Text('Itinéraire'),
                onPressed: _openDirections,
              ),
            ],
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

  // Coordonnées de l'étape (pour afficher la carte si défini)
  double? _stepLatitude;
  double? _stepLongitude;
  bool _showStepLocation = true;  // true par défaut, contrôlé par le créateur

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
    final j = await _api.startSession(widget.escape.id);

    // statut fin
    _finished = (j['finished'] == true);

    // total
    _total = _asInt(j['total_steps']) ?? _asInt(j['total']) ?? 0;

    // sync pénalité côté timer
    final penaltyFromApi =
        _asInt(j['penalty']) ?? _asInt(j['accumulated_penalty_minutes']) ?? 0;
    GameTimer.instance.syncPenaltyMinutes(penaltyFromApi);

    if (_finished) {
      // session finie → pas d'étape courante
      _index = _total > 0 ? _total - 1 : 0;

      _stepTitle = '';
      _stepImageUrl = null;
      _prompt = '';
      _stepLatitude = null;
      _stepLongitude = null;
      _showStepLocation = true;
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

      // coordonnées de l'étape (pour afficher carte popup)
      _stepLatitude = (st['latitude'] as num?)?.toDouble();
      _stepLongitude = (st['longitude'] as num?)?.toDouble();
      _showStepLocation = st['show_location'] != false; // true par défaut

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
                    child: Text("Impossible de charger l'image",
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

  // ---------- Carte point d'étape ----------
  bool get _hasStepLocation =>
      _showStepLocation && _stepLatitude != null && _stepLongitude != null;

  void _openStepLocationMap() {
    if (_stepLatitude == null || _stepLongitude == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                // Poignée de drag
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Titre
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _stepTitle.isNotEmpty ? _stepTitle : 'Point de l\'étape',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Carte
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_stepLatitude!, _stepLongitude!),
                      zoom: 16,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('step_location'),
                        position: LatLng(_stepLatitude!, _stepLongitude!),
                        infoWindow: InfoWindow(
                          title: _stepTitle.isNotEmpty ? _stepTitle : 'Étape ${_index + 1}',
                        ),
                      ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                  ),
                ),
                // Bouton itinéraire
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.directions_walk),
                      label: const Text('Itinéraire vers ce point'),
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1'
                          '&destination=$_stepLatitude,$_stepLongitude'
                          '&travelmode=walking',
                        );
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
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

    // Cellule A (fixe) - taille flexible selon contenu
    Widget _aCell(int aIndexOriginal, {bool flexible = false}) {
      final selected = (_selA == aIndexOriginal);

      final cell = InkWell(
        onTap: () => _onTapA(aIndexOriginal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.secondary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 10),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _matchLeft[aIndexOriginal],
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      );

      return flexible ? Flexible(child: cell) : cell;
    }

    // Cellule B (ordre courant) - taille flexible selon contenu
    Widget _bCell(int rowIndex, {bool flexible = false}) {
      final bOriginal = _rightOrder[rowIndex];
      final selected  = (_selB == bOriginal);

      final cell = InkWell(
        onTap: () => _onTapB(bOriginal),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.square, size: 10),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _matchRight[bOriginal],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _unpairRow(rowIndex),
                child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

      return flexible ? Flexible(child: cell) : cell;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Clique un item de A puis un item de B (ou l'inverse). B se place en face de A.",
        ),
        const SizedBox(height: 12),

        // Lignes A | B avec tailles dynamiques adaptées au contenu
        for (int row = 0; row < rowCount; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _aCell(row, flexible: true),
                const SizedBox(width: 12),
                _bCell(row, flexible: true),
              ],
            ),
          ),

        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Ordre B: ' + _rightOrder.map((e) => (e + 1).toString()).join(' → '),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            TextButton.icon(
              onPressed: _resetPairs,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Réinitialiser'),
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
                                      normalizeImageUrl(_stepImageUrl, baseUrl),
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
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

                      // ---- BOUTON CARTE (si coordonnées définies) ----
                      if (_hasStepLocation) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Voir le point sur la carte'),
                          onPressed: _openStepLocationMap,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                          ),
                        ),
                      ],

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
   Moved to: lib/features/creator/creator_page.dart
============================ */
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
  bool get _isAdmin     => AuthService.instance.isAdmin;

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
              child: imageThumb(_imageCtrl.text),
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
                      onTap: (_isSubmitted && !_isAdmin)
                          ? null
                          : () async {
                              final changed = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => StepEditorPage(
                                    escapeId: e.id,
                                    existing: s,
                                    readOnly: _isSubmitted && _isAdmin,
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
  final bool readOnly;

  const StepEditorPage({
    super.key,
    required this.escapeId,
    this.existing,
    this.nextOrderResolver,
    this.readOnly = false,
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
  bool _showLocation = true;

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
                  enabled: !widget.readOnly,
                  decoration: InputDecoration(
                    labelText: 'Indice ${i + 1}',
                    hintText: 'Texte de l\'indice',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Supprimer cet indice',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: widget.readOnly || _hintCtrls.length <= 1
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
            onPressed: widget.readOnly ? null : () => setState(() => _hintCtrls.add(TextEditingController())),
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
    _showLocation = s?.showLocation ?? true;

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
      showLocation: _showLocation,
    );

    // on construit un patch pour fiabiliser l'UPDATE (et pour forcer narration)
    final Map<String, dynamic> patch = step.toPayload();
    patch['hints'] = hints;
    patch['hint'] = '';
    patch['hint_penalty'] = hintPenalty;
    patch['show_location'] = _showLocation;

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
              onPressed: widget.readOnly ? null : _lockStepFromMyLocation,
              child: const Text('Ma position'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.readOnly ? null : () async {
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
        onTap: widget.readOnly ? null : () => _onTapA(row),
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
                  enabled: !widget.readOnly,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Item A',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer la paire',
                onPressed: widget.readOnly ? null : () => _removePairAtRow(row),
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
        onTap: widget.readOnly ? null : () => _onTapB(bOriginal),
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
                  enabled: !widget.readOnly,
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
              onPressed: widget.readOnly ? null : _addPair,
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
        title: Text(widget.readOnly
            ? 'Consulter l\'étape (lecture seule)'
            : (_isEdit ? 'Modifier une étape' : 'Nouvelle étape')),
        actions: widget.readOnly
            ? null
            : [
                IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (widget.readOnly)
            Container(
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
                      'En attente d\'approbation – modification désactivée.',
                      style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ordre (1..N)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _title,
                  enabled: !widget.readOnly,
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            enabled: !widget.readOnly,
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
                onPressed: widget.readOnly ? null : () async {
                  final url = await _pickAndUploadStep(ImageSource.gallery);
                  if (url == null) return;
                  setState(() => _imageUrl.text = url);
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Prendre une photo'),
                onPressed: widget.readOnly ? null : () async {
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
                enabled: !widget.readOnly,
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
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Afficher la carte aux joueurs'),
              subtitle: const Text('Si désactivé, la carte ne sera pas visible pendant le jeu'),
              value: _showLocation,
              onChanged: widget.readOnly ? null : (v) => setState(() => _showLocation = v),
              contentPadding: EdgeInsets.zero,
            ),
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
                onChanged: widget.readOnly ? null : (v) => setState(() => _answerType = v ?? 'text'),
              ),
            ],
          ),

          const SizedBox(height: 8),
          if (_answerType == 'text') ...[
            TextField(
              controller: _answerText,
              enabled: !widget.readOnly,
              decoration: const InputDecoration(labelText: 'Réponse attendue'),
            ),
          ] else if (_answerType == 'numeric') ...[
            TextField(
              controller: _answerText,
              enabled: !widget.readOnly,
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
                    onChanged: widget.readOnly ? null : (v) => setState(() => _correctIndex = v),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _options[i],
                      enabled: !widget.readOnly,
                      decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: widget.readOnly || _options.length <= 2
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
                onPressed: widget.readOnly ? null : () => setState(() => _options.add(TextEditingController())),
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
              enabled: !widget.readOnly,
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

// _AuthDialog and _AuthDialogState have been moved to features/home/main_home.dart

// SplashBootstrap and _SplashBootstrapState have been moved to features/splash/splash_screen.dart

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

