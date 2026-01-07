import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants.dart';
import '../../models/escape_game.dart';
import '../../services/api/api_service.dart';
import '../home/main_home.dart';

/// Splash screen with bootstrap loading.
/// Handles initialization of the app including:
/// - API connectivity check (ping)
/// - Local moderation data loading
/// - User geolocation retrieval
/// - Preloading of escape game lists and nearby games
/// - Creator mode preparation
class SplashBootstrap extends StatefulWidget {
  const SplashBootstrap({Key? key}) : super(key: key);

  @override
  State<SplashBootstrap> createState() => _SplashBootstrapState();
}

class _SplashBootstrapState extends State<SplashBootstrap> {
  String _status = 'Initialisation…';

  // Progression (3 tasks: Liste, Carte, Créateur)
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
      // 0) Load local moderation (ids + reasons)
      await ApiService.instance.loadLocalModeration();

      // 1) DNS/TLS pre-warming + API (small GET)
      setState(() => _status = 'Connexion au serveur…');
      await ApiService.instance.ping();

      // 2) Geolocation best effort (doesn't block if denied)
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
        // ignore: keep userLoc=null => fallback in MapPage
      }

      // 3) Sequential preloading + progress (3 steps)
      setState(() => _status = 'Chargement de la liste…');
      await ApiService.instance
          .fetchAll()
          .then((_) => _markLoaded())
          .catchError((e) {
        debugPrint('[BOOT] fetchAll error: $e');
        // IMPORTANT: return compatible type
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
        debugPrint('[BOOT] fetchNearby error: $e');
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
        debugPrint('[BOOT] fetchMe error: $e');
        _markLoaded();
        return null;
      });

      // 4) Respect minimum splash display time
      final elapsed = DateTime.now().difference(started);
      const minSplash = Duration(milliseconds: 800);
      if (elapsed < minSplash) {
        await Future.delayed(minSplash - elapsed);
      }

      if (!mounted) return;
      // 5) Open app (Map tab already selected in MainScaffold)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainHome()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Impossible de démarrer (${e.toString()}).');
      // Small retry?
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
          // --- Logo full screen ---
          Image.asset(
            kLogoAsset,
            fit: BoxFit.cover, // covers entire screen
            errorBuilder: (_, __, ___) => const FlutterLogo(size: 160),
          ),

          // --- Dark overlay for text readability ---
          Container(color: Colors.black.withOpacity(0.35)),

          // --- Info at bottom: progress bar, status, counter ---
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar (N/3) or indeterminate at start
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
                  // Status + Counter
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
                        '$_loaded/$_totalTasks',
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

