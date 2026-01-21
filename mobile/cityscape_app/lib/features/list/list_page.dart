// lib/features/list/list_page.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import models
import '../../models/escape_game.dart';
import '../../models/user_preferences.dart';

// Import services
import '../../services/api/api_service.dart';
import '../../services/preferences_service.dart';

// Import tutorial
import '../tutorial/tutorial_controller.dart';

// Import card styles
import 'widgets/card_collection_style.dart';
import 'widgets/gaming_ui_style.dart';
import 'widgets/playful_style.dart';

// Import other features (for navigation)
// TODO: Update this import once EscapeDetailsPage is extracted
import '../../main.dart' show EscapeDetailsPage;

enum SortMode { rating, distance }

class ListPage extends StatefulWidget {
  const ListPage({super.key});
  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _api = ApiService.instance;
  final _prefs = PreferencesService.instance;
  final _searchCtrl = TextEditingController();
  bool _favOnly = false;

  List<EscapeGame> _all = [];
  List<EscapeGame> _items = [];
  Set<int> _favorites = {};
  SortMode _sort = SortMode.rating;
  Position? _pos;
  bool _loading = true;

  // Tutorial Phase 2
  final _firstCardKey = GlobalKey();
  bool _tutorialShown = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _items = _applyFiltersAndSort(_all);
      });
    });
    TutorialController.instance.addListener(_onTutorialChanged);
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    TutorialController.instance.removeListener(_onTutorialChanged);
    super.dispose();
  }

  void _onTutorialChanged() {
    if (mounted) {
      setState(() {});
      // Vérifier si on doit lancer le tutoriel Phase 2 après un changement de phase
      _checkAndShowTutorial();
    }
  }

  /// Lance le tutoriel Phase 2 si conditions remplies
  void _checkAndShowTutorial() {
    if (_tutorialShown) return;
    if (!TutorialController.instance.isActive) return;
    if (TutorialController.instance.currentPhase != TutorialPhase.escapeList) return;
    if (_items.isEmpty) return;

    _tutorialShown = true;

    // Attendre que le widget soit rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TutorialController.instance.showEscapeCardTarget(
        context,
        cardKey: _firstCardKey,
        onFinish: () {
          // Naviguer vers la page de détails du premier escape
          if (_items.isNotEmpty && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EscapeDetailsPage(escape: _items.first),
              ),
            );
          }
        },
      );
    });
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
      // Vérifier si on doit lancer le tutoriel Phase 2
      _checkAndShowTutorial();
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
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final e = _items[i];
                      final fav = _favorites.contains(e.id);
                      final dist = (_pos == null)
                          ? null
                          : _distanceKm(_pos!.latitude, _pos!.longitude,
                                  e.latitude, e.longitude)
                              .toStringAsFixed(1);

                      // Ajouter le GlobalKey pour la première carte (tutoriel)
                      final isFirstCard = i == 0;
                      return _buildStyledCard(e, fav, dist, isFirstCard: isFirstCard);
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

  Widget _buildStyledCard(EscapeGame escape, bool isFavorite, String? distance, {bool isFirstCard = false}) {
    final style = _prefs.currentPreferences.listCardStyle;

    Widget card;
    switch (style) {
      case ListCardStyle.cardCollection:
        card = CardCollectionStyleCard(
          escape: escape,
          isFavorite: isFavorite,
          distance: distance,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EscapeDetailsPage(escape: escape),
            ),
          ),
          onFavoriteTap: () => _toggleFav(escape.id),
        );
        break;

      case ListCardStyle.gamingUI:
        card = GamingUIStyleCard(
          escape: escape,
          isFavorite: isFavorite,
          distance: distance,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EscapeDetailsPage(escape: escape),
            ),
          ),
          onFavoriteTap: () => _toggleFav(escape.id),
        );
        break;

      case ListCardStyle.playful:
        card = PlayfulStyleCard(
          escape: escape,
          isFavorite: isFavorite,
          distance: distance,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EscapeDetailsPage(escape: escape),
            ),
          ),
          onFavoriteTap: () => _toggleFav(escape.id),
        );
        break;
    }

    // Wrapper la première carte avec le GlobalKey pour le tutoriel
    if (isFirstCard) {
      return Container(
        key: _firstCardKey,
        child: card,
      );
    }

    return card;
  }
}
