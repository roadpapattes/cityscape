// lib/main.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MyApp());

/// IMPORTANT : ajuste selon ton environnement.
/// - Emulateur Android : http://10.0.2.2:8000
/// - iOS Simulator     : http://127.0.0.1:8000
/// - Appareil physique : http://IP_LOCALE_PC:8000
const String baseUrl = "http://10.0.2.2:8000";

/* ===================== App ===================== */

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escape City',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00695C), // teal foncé
          foregroundColor: Colors.white,      // texte/icônes blancs
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const RootTabs(),
    );
  }
}

/* ===================== Auth (Token local) ===================== */

class AuthService {
  static const _key = 'auth_token';

  static Future<void> saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, token);
  }

  static Future<String?> getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_key);
  }

  static Future<void> clearToken() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;
}

/* ===================== Modèles + API ===================== */

class EscapeGame {
  final int id;
  final String title;
  final String description;
  final String city;
  final double latitude;
  final double longitude;
  final double rating;
  final int durationMinutes;
  final int difficulty;
  final DateTime createdAt;
  final double? distanceKm;
  final String? imageUrl;

  EscapeGame({
    required this.id,
    required this.title,
    required this.description,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.durationMinutes,
    required this.difficulty,
    required this.createdAt,
    this.distanceKm,
    this.imageUrl,
  });

  factory EscapeGame.fromJson(Map<String, dynamic> json) => EscapeGame(
        id: json['id'] as int,
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        city: json['city'] ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        durationMinutes: json['duration_minutes'] ?? 60,
        difficulty: json['difficulty'] ?? 1,
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        distanceKm: json['distance_km'] != null
            ? (json['distance_km'] as num).toDouble()
            : null,
        imageUrl: json['image_url'],
      );
}

class ApiService {
  Future<List<EscapeGame>> fetchAll() async {
    final res = await http.get(Uri.parse("$baseUrl/api/escapes/"));
    if (res.statusCode != 200) {
      throw Exception("Erreur API ${res.statusCode}");
    }
    final List data = jsonDecode(res.body);
    return data.map((e) => EscapeGame.fromJson(e)).toList();
  }

  Future<List<EscapeGame>> fetchNearby({
    required double lat,
    required double lon,
    double radiusKm = 5,
  }) async {
    final url = Uri.parse(
        "$baseUrl/api/escapes/nearby?lat=$lat&lon=$lon&radius_km=$radiusKm");
    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw Exception("Erreur API ${res.statusCode}");
    }
    final List data = jsonDecode(res.body);
    return data.map((e) => EscapeGame.fromJson(e)).toList();
  }

  /* -------- Auth -------- */

  Future<void> register(String username, String password, {String? email}) async {
    final res = await http.post(
      Uri.parse("$baseUrl/api/auth/register"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'email': email ?? ''}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body);
      await AuthService.saveToken(data['token']);
    } else {
      throw Exception("Inscription échouée: ${res.body}");
    }
  }

  Future<void> login(String username, String password) async {
    final res = await http.post(
      Uri.parse("$baseUrl/api/auth/login"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await AuthService.saveToken(data['token']);
    } else {
      throw Exception("Login échoué: ${res.body}");
    }
  }

  Future<void> logout() async {
    final token = await AuthService.getToken();
    if (token != null) {
      await http.post(
        Uri.parse("$baseUrl/api/auth/logout"),
        headers: {'Authorization': 'Token $token'},
      );
    }
    await AuthService.clearToken();
  }

  /* -------- Sessions & Ratings -------- */

  Future<void> startSession(int escapeId) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception("Non connecté");
    final res = await http.post(
      Uri.parse("$baseUrl/api/escapes/$escapeId/sessions/start"),
      headers: {'Authorization': 'Token $token'},
    );
    if (res.statusCode >= 400) {
      throw Exception("Erreur start session: ${res.body}");
    }
  }

  Future<bool> completeSession(int escapeId, String code) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception("Non connecté");
    final res = await http.post(
      Uri.parse("$baseUrl/api/escapes/$escapeId/sessions/complete"),
      headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    if (res.statusCode == 200) return true;
    if (res.statusCode == 400) return false;
    throw Exception("Erreur completion: ${res.body}");
  }

  Future<bool> canRate(int escapeId) async {
    final token = await AuthService.getToken();
    if (token == null) return false;
    final res = await http.get(
      Uri.parse("$baseUrl/api/escapes/$escapeId/can_rate"),
      headers: {'Authorization': 'Token $token'},
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body);
    return data['can_rate'] == true;
  }

  Future<Map<String, dynamic>> submitRating(
    int escapeId, {
    required int stars,
    String? comment,
  }) async {
    final token = await AuthService.getToken();
    if (token == null) throw Exception("Non connecté");
    final res = await http.post(
      Uri.parse("$baseUrl/api/escapes/$escapeId/ratings"),
      headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'stars': stars, 'comment': comment ?? ''}),
    );
    if (res.statusCode == 201) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Erreur rating: ${res.body}");
    }
  }
}

/* ===================== Favoris ===================== */

class FavoritesStore {
  static const _key = 'favorites_ids';

  static Future<Set<int>> load() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_key) ?? <String>[];
    return list.map((e) => int.tryParse(e) ?? -1).where((e) => e >= 0).toSet();
  }

  static Future<void> save(Set<int> ids) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_key, ids.map((e) => e.toString()).toList());
  }

  static Future<bool> toggle(int id) async {
    final favs = await load();
    if (favs.contains(id)) {
      favs.remove(id);
      await save(favs);
      return false;
    } else {
      favs.add(id);
      await save(favs);
      return true;
    }
  }
}

/* ===================== Tabs + Bouton Compte ===================== */

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});
  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: const [HomeListPage(), MapPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: "Liste"),
          NavigationDestination(icon: Icon(Icons.map), label: "Carte"),
        ],
      ),
    );
  }
}

class AccountButton extends StatefulWidget {
  const AccountButton({super.key});
  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _logged = await AuthService.isLoggedIn();
    if (mounted) setState(() {});
  }

  Future<void> _onTap() async {
    if (_logged) {
      await ApiService().logout();
      if (mounted) {
        setState(() => _logged = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Déconnecté")));
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const _AuthDialog(),
      );
      await _refresh();
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Connecté")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _onTap,
      icon: Icon(_logged ? Icons.logout : Icons.login, color: Colors.white),
      label: Text(_logged ? "Se déconnecter" : "Se connecter",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}

/* ===================== LISTE ===================== */

enum SortBy { ratingDesc, distanceAsc, durationAsc, recentDesc }

class HomeListPage extends StatefulWidget {
  const HomeListPage({super.key});
  @override
  State<HomeListPage> createState() => _HomeListPageState();
}

class _HomeListPageState extends State<HomeListPage> {
  final _api = ApiService();

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _city = 'Toutes';
  RangeValues _duration = const RangeValues(0, 180);
  final Set<int> _difficulties = {};

  bool _loading = false;
  String? _error;
  List<EscapeGame> _all = [];
  List<EscapeGame> _items = [];

  SortBy _sortBy = SortBy.ratingDesc;
  bool _favoritesOnly = false;
  Set<int> _favorites = {};
  Position? _userPos;

  List<String> get _cities {
    final s = {'Toutes', ..._all.map((e) => e.city).where((c) => c.isNotEmpty)};
    final l = s.toList()..sort();
    return l;
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    _favorites = await FavoritesStore.load();
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.fetchAll();
      setState(() {
        _all = items;
      });
      _applyFiltersAndSort();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyFiltersAndSort() {
    final q = _search.trim().toLowerCase();

    var filtered = _all.where((e) {
      final matchesText = q.isEmpty ||
          e.title.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.city.toLowerCase().contains(q);
      final matchesCity = _city == 'Toutes' || e.city == _city;
      final matchesDiff =
          _difficulties.isEmpty || _difficulties.contains(e.difficulty);
      final matchesDur =
          e.durationMinutes >= _duration.start && e.durationMinutes <= _duration.end;
      final matchesFav = !_favoritesOnly || _favorites.contains(e.id);
      return matchesText && matchesCity && matchesDiff && matchesDur && matchesFav;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case SortBy.ratingDesc:
          return b.rating.compareTo(a.rating);
        case SortBy.durationAsc:
          return a.durationMinutes.compareTo(b.durationMinutes);
        case SortBy.recentDesc:
          return b.createdAt.compareTo(a.createdAt);
        case SortBy.distanceAsc:
          final da = _distanceFor(a);
          final db = _distanceFor(b);
          return da.compareTo(db);
      }
    });

    setState(() => _items = filtered);
  }

  double _distanceFor(EscapeGame e) {
    if (e.distanceKm != null) return e.distanceKm!;
    if (_userPos == null) return double.infinity;
    return _haversineKm(_userPos!.latitude, _userPos!.longitude, e.latitude, e.longitude);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  void _resetFilters() {
    _searchCtrl.clear();
    _search = '';
    _city = 'Toutes';
    _duration = const RangeValues(0, 180);
    _difficulties.clear();
    _favoritesOnly = false;
    _sortBy = SortBy.ratingDesc;
    _applyFiltersAndSort();
  }

  Future<void> _aroundMe() async {
    try {
      await _ensureLocationPermission();
      final pos = await Geolocator.getCurrentPosition();
      final items =
          await _api.fetchNearby(lat: pos.latitude, lon: pos.longitude, radiusKm: 5);
      setState(() {
        _all = items;
        _userPos = pos;
      });
      _applyFiltersAndSort();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _ensureUserPositionIfNeeded() async {
    if (_userPos != null) return;
    try {
      await _ensureLocationPermission();
      _userPos = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  Future<void> _toggleFavorite(int id) async {
    final nowFav = await FavoritesStore.toggle(id);
    if (mounted) {
      setState(() {
        if (nowFav) {
          _favorites.add(id);
        } else {
          _favorites.remove(id);
        }
      });
      _applyFiltersAndSort();
    }
  }

  @override
  Widget build(BuildContext context) {
    final diffs = [1, 2, 3, 4, 5];
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escape City (Liste)"),
        actions: const [
          AccountButton(),
        ],
      ),
      body: Column(
        children: [
          const AuthNotice(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Rechercher par titre, ville…",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search = '';
                          _applyFiltersAndSort();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                _search = v;
                _applyFiltersAndSort();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _cities.contains(_city) ? _city : 'Toutes',
                    items: _cities
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      _city = v;
                      _applyFiltersAndSort();
                    },
                    decoration: const InputDecoration(
                      labelText: "Ville",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text("Réinitialiser"),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 8,
              children: diffs
                  .map((d) => FilterChip(
                        selected: _difficulties.contains(d),
                        label: Text("Diff $d"),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _difficulties.add(d);
                            } else {
                              _difficulties.remove(d);
                            }
                          });
                          _applyFiltersAndSort();
                        },
                      ))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SortBy>(
                    value: _sortBy,
                    items: const [
                      DropdownMenuItem(
                        value: SortBy.ratingDesc,
                        child: Text("Tri : Note ↓"),
                      ),
                      DropdownMenuItem(
                        value: SortBy.distanceAsc,
                        child: Text("Tri : Distance ↑"),
                      ),
                      DropdownMenuItem(
                        value: SortBy.durationAsc,
                        child: Text("Tri : Durée ↑"),
                      ),
                      DropdownMenuItem(
                        value: SortBy.recentDesc,
                        child: Text("Tri : Récents ↓"),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      _sortBy = v;
                      if (_sortBy == SortBy.distanceAsc) {
                        await _ensureUserPositionIfNeeded();
                      }
                      _applyFiltersAndSort();
                    },
                    decoration: const InputDecoration(
                      labelText: "Tri",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Favoris"),
                    Switch(
                      value: _favoritesOnly,
                      onChanged: (val) {
                        setState(() => _favoritesOnly = val);
                        _applyFiltersAndSort();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _items[i];
                final isFav = _favorites.contains(e.id);
                final dist = _distanceFor(e);
                final distText = dist.isFinite ? " • ${dist.toStringAsFixed(2)} km" : "";
                return ListTile(
                  leading: _Thumb(url: e.imageUrl),
                  title: Text(e.title),
                  subtitle: Text(
                    "${e.city} • ${e.rating.toStringAsFixed(1)}★ • ${e.durationMinutes} min • diff ${e.difficulty}$distText",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav ? Colors.red : null),
                        onPressed: () => _toggleFavorite(e.id),
                        tooltip: isFav ? "Retirer des favoris" : "Ajouter aux favoris",
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetailPage(item: e)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ===================== CARTE (clustering custom) ===================== */

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _api = ApiService();
  GoogleMapController? _controller;

  bool _loading = true;
  String? _error;

  List<EscapeGame> _all = [];
  Set<Marker> _markers = {};

  double _zoom = 11;
  static const double _clusterPixelRadius = 64;
  final Map<int, BitmapDescriptor> _clusterIconCache = {};
  Set<int> _favorites = {};

  static const _fallbackParis = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 11,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _favorites = await FavoritesStore.load();
    await _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final items = await _api.fetchAll();
      setState(() {
        _all = items;
        _loading = false;
      });
      await _rebuildClusters();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _aroundMe() async {
    try {
      setState(() => _loading = true);
      await _ensureLocationPermission();
      final pos = await Geolocator.getCurrentPosition();
      final items =
          await _api.fetchNearby(lat: pos.latitude, lon: pos.longitude, radiusKm: 5);
      setState(() {
        _all = items;
      });
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 13),
      );
      await _rebuildClusters();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _rebuildClusters() async {
    final clusters = _clusterize(_all, _zoom);
    final Set<Marker> markers = {};

    for (final c in clusters) {
      if (c.count == 1 && c.single != null) {
        final e = c.single!;
        markers.add(
          Marker(
            markerId: MarkerId("eg_${e.id}"),
            position: LatLng(e.latitude, e.longitude),
            infoWindow: InfoWindow(
              title: e.title,
              snippet: "${e.city} • ${e.rating.toStringAsFixed(1)}★",
              onTap: () => _openDetail(e),
            ),
            onTap: () => _showBottomSheet(e),
          ),
        );
      } else {
        final icon = await _getClusterIcon(c.count);
        markers.add(
          Marker(
            markerId: MarkerId("cl_${c.centerLat.toStringAsFixed(5)}_${c.centerLon.toStringAsFixed(5)}"),
            position: LatLng(c.centerLat, c.centerLon),
            icon: icon,
            onTap: () {
              _controller?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(c.centerLat, c.centerLon),
                  _zoom + 1.5,
                ),
              );
            },
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _markers = markers);
    }
  }

  void _showBottomSheet(EscapeGame e) {
    final isFav = _favorites.contains(e.id);
    showModalBottomSheet(
      context: context,
      builder: (_) => _BottomSheetCard(
        item: e,
        isFavorite: isFav,
        onToggleFavorite: () async {
          final nowFav = await FavoritesStore.toggle(e.id);
          if (mounted) {
            setState(() {
              if (nowFav) {
                _favorites.add(e.id);
              } else {
                _favorites.remove(e.id);
              }
            });
          }
          Navigator.of(context).pop();
          _showBottomSheet(e);
        },
        onDirections: () => _openDirections(e.latitude, e.longitude),
        onDetail: () => _openDetail(e),
      ),
    );
  }

  void _openDetail(EscapeGame e) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(item: e)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text("Carte des escapes"), actions: const [
        AccountButton(),
      ],),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: _fallbackParis,
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          onMapCreated: (c) {
            _controller = c;
            _goToUserLocationIfPlausible();
          },
          onCameraMove: (pos) {
            _zoom = pos.zoom;
          },
          onCameraIdle: _rebuildClusters,
        ),
        // Bandeau connexion
        Positioned(
          left: 0, right: 0, top: 8,
          child: const AuthNotice(),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: "around",
                onPressed: _aroundMe,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: "reload",
                onPressed: _loadAll,
                child: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_loading)
          const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 3)),
        if (_error != null)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              color: Colors.red,
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
          ),
      ]),
    );
  }

  Future<void> _goToUserLocationIfPlausible() async {
    try {
      await _ensureLocationPermission();
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (_isPlausibleNearFrance(pos.latitude, pos.longitude)) {
        await _controller?.moveCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 13),
        );
      }
    } catch (_) {}
  }

  bool _isPlausibleNearFrance(double lat, double lon) {
    return _haversineKm(lat, lon, 48.8566, 2.3522) <= 1200.0;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  // --- Web Mercator projection & simple grid clustering ---

  static const int _tileSize = 256;
  static const double _minLat = -85.05112878;
  static const double _maxLat = 85.05112878;

  static _Point _project(double lat, double lon, double zoom) {
    final clampedLat = lat.clamp(_minLat, _maxLat);
    double siny = math.sin(clampedLat * math.pi / 180.0);
    siny = siny.clamp(-0.9999, 0.9999);
    final x = 0.5 + (lon / 360.0);
    final y = 0.5 - (math.log((1 + siny) / (1 - siny)) / (4 * math.pi));
    final scale = math.pow(2, zoom).toDouble() * _tileSize;
    return _Point(x * scale, y * scale);
    }

  Set<_Cluster> _clusterize(List<EscapeGame> items, double zoom) {
    final Map<_Cell, List<EscapeGame>> buckets = {};
    for (final e in items) {
      final p = _project(e.latitude, e.longitude, zoom);
      final cell = _Cell(
        (p.x / _clusterPixelRadius).floor(),
        (p.y / _clusterPixelRadius).floor(),
      );
      buckets.putIfAbsent(cell, () => []).add(e);
    }

    final Set<_Cluster> clusters = {};
    buckets.forEach((cell, list) {
      if (list.length == 1) {
        clusters.add(_Cluster.single(list.first));
      } else {
        double lat = 0, lon = 0;
        for (final e in list) {
          lat += e.latitude;
          lon += e.longitude;
        }
        lat /= list.length;
        lon /= list.length;
        clusters.add(_Cluster.multiple(
          centerLat: lat,
          centerLon: lon,
          count: list.length,
        ));
      }
    });

    return clusters;
  }

  // --- Rendu bitmap des clusters (fond transparent) ---

  Future<BitmapDescriptor> _getClusterIcon(int count) async {
    final bucket = _bucketFor(count);
    final cached = _clusterIconCache[bucket];
    if (cached != null) return cached;

    final bytes = await _createClusterIconBytes(bucket);
    final icon = BitmapDescriptor.fromBytes(bytes);
    _clusterIconCache[bucket] = icon;
    return icon;
  }

  int _bucketFor(int count) {
    if (count < 10) return count;
    if (count < 25) return 10;
    if (count < 50) return 25;
    if (count < 100) return 50;
    return 100;
  }

  Future<Uint8List> _createClusterIconBytes(int bucket) async {
    const double size = 96;
    const double scale = 3.0;
    final double r = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size * scale, size * scale));
    canvas.scale(scale);

    // Cercle bleu foncé
    const Color blue = Color(0xFF0D47A1);
    final center = Offset(r, r);

    final fillPaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, r - 4, fillPaint);

    // Liseré blanc
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..isAntiAlias = true;
    canvas.drawCircle(center, r - 4, borderPaint);

    // Texte blanc gras centré
    final text = bucket >= 10 ? "$bucket+" : "$bucket";
    final double fontSize = bucket >= 100 ? 34 : (bucket >= 10 ? 36 : 40);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    tp.paint(canvas, textOffset);

    final picture = recorder.endRecording();
    final ui.Image img = await picture.toImage((size * scale).toInt(), (size * scale).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}

/* ===================== Types clustering internes ===================== */

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}

class _Cell {
  final int i, j;
  const _Cell(this.i, this.j);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Cell && runtimeType == other.runtimeType && i == other.i && j == other.j;
  @override
  int get hashCode => Object.hash(i, j);
}

class _Cluster {
  final double centerLat;
  final double centerLon;
  final int count;
  final EscapeGame? single;

  _Cluster.multiple({
    required this.centerLat,
    required this.centerLon,
    required this.count,
  }) : single = null;

  _Cluster.single(EscapeGame e)
      : centerLat = e.latitude,
        centerLon = e.longitude,
        count = 1,
        single = e;
}

/* ===================== Détail (auth + terminer + noter) ===================== */

class DetailPage extends StatefulWidget {
  final EscapeGame item;
  const DetailPage({super.key, required this.item});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _api = ApiService();
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _refreshLogged();
    _maybeStartSession();
  }

  Future<void> _refreshLogged() async {
    _logged = await AuthService.isLoggedIn();
    if (mounted) setState(() {});
  }

  Future<void> _maybeStartSession() async {
    if (await AuthService.isLoggedIn()) {
      try {
        await _api.startSession(widget.item.id);
      } catch (_) {}
    }
  }

  Future<void> _handleEnsureLogin() async {
    if (_logged) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _AuthDialog(),
    );
    await _refreshLogged();
    if (ok == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Connecté")));
    }
  }

  Future<void> _handleCompleteWithCode() async {
    if (!_logged) {
      await _handleEnsureLogin();
      if (!_logged) return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _CodeDialog(),
    );
    if (code == null || code.isEmpty) return;
    final ok = await _api.completeSession(widget.item.id, code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? "Session validée, tu peux noter !" : "Code invalide"),
    ));
  }

  Future<void> _handleRate() async {
    if (!_logged) {
      await _handleEnsureLogin();
      if (!_logged) return;
    }
    final can = await _api.canRate(widget.item.id);
    if (!can) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Tu dois terminer l'escape avant de noter."),
      ));
      return;
    }
    final result = await showDialog<_RatingResult>(
      context: context,
      builder: (_) => const _RatingDialog(),
    );
    if (result == null) return;
    try {
      final resp = await _api.submitRating(
        widget.item.id,
        stars: result.stars,
        comment: result.comment,
      );
      if (!mounted) return;
      final avg = (resp['aggregate']?['avg'] ?? widget.item.rating).toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Merci pour ta note ! Nouvelle moyenne ~ $avg★"),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Erreur envoi note: $e"),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: const [AccountButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_logged)
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text("Tu n’es pas connecté"),
                subtitle: const Text("Connecte-toi pour terminer et noter cet escape"),
                trailing: FilledButton(
                  onPressed: _handleEnsureLogin,
                  child: const Text("Se connecter"),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
              ),
            )
          else
            const _ImagePlaceholder(),
          const SizedBox(height: 12),
          Text(item.city, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(item.description),
          const SizedBox(height: 16),
          Row(children: [
            Chip(label: Text("Note ${item.rating.toStringAsFixed(1)}")),
            const SizedBox(width: 8),
            Chip(label: Text("${item.durationMinutes} min")),
            const SizedBox(width: 8),
            Chip(label: Text("Diff ${item.difficulty}")),
          ]),
          const SizedBox(height: 16),
          Text("Coordonnées: ${item.latitude}, ${item.longitude}"),
          if (item.distanceKm != null)
            Text("Distance: ${item.distanceKm!.toStringAsFixed(2)} km"),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _handleCompleteWithCode,
                  icon: const Icon(Icons.verified),
                  label: const Text("Terminer (code)"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleRate,
                  icon: const Icon(Icons.star_rate_rounded),
                  label: const Text("Noter"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

/* ===================== Dialogs: Auth / Code / Rating ===================== */

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();
  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  bool _isLogin = true;
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  final _api = ApiService();

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await _api.login(_userCtrl.text.trim(), _passCtrl.text);
      } else {
        await _api.register(_userCtrl.text.trim(), _passCtrl.text, email: _emailCtrl.text.trim());
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isLogin ? "Se connecter" : "Créer un compte"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: "Nom d'utilisateur")),
          if (!_isLogin) TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Email (optionnel)")),
          TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: "Mot de passe"), obscureText: true),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _isLogin = !_isLogin),
          child: Text(_isLogin ? "Créer un compte" : "J'ai déjà un compte"),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Valider"),
        ),
      ],
    );
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _codeCtrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Code de validation"),
      content: TextField(
        controller: _codeCtrl,
        decoration: const InputDecoration(hintText: "Ex: 0000"),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
        FilledButton(onPressed: () => Navigator.of(context).pop(_codeCtrl.text.trim()), child: const Text("Valider")),
      ],
    );
  }
}

class _RatingResult {
  final int stars;
  final String comment;
  _RatingResult(this.stars, this.comment);
}

class _RatingDialog extends StatefulWidget {
  const _RatingDialog();
  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 5;
  final _commentCtrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Ta note"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return IconButton(
                icon: Icon(filled ? Icons.star : Icons.star_border, size: 32, color: filled ? Colors.amber : null),
                onPressed: () => setState(() => _stars = i + 1),
              );
            }),
          ),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: "Ton avis (facultatif)"),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
        FilledButton(onPressed: () {
          Navigator.of(context).pop(_RatingResult(_stars, _commentCtrl.text.trim()));
        }, child: const Text("Envoyer")),
      ],
    );
  }
}

/* ===================== UI partagées ===================== */

class _BottomSheetCard extends StatelessWidget {
  final EscapeGame item;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onDirections;
  final VoidCallback? onDetail;
  const _BottomSheetCard({
    required this.item,
    required this.isFavorite,
    this.onToggleFavorite,
    this.onDirections,
    this.onDetail,
  });
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : null),
                  onPressed: onToggleFavorite,
                  tooltip: isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                )
              ],
            ),
            const SizedBox(height: 8),
            Text(
                "${item.city} • ${item.rating.toStringAsFixed(1)}★ • ${item.durationMinutes} min • diff ${item.difficulty}"),
            const SizedBox(height: 8),
            Text(item.description, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: onDirections,
                icon: const Icon(Icons.directions_walk),
                label: const Text("Itinéraire"),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onDetail,
                icon: const Icon(Icons.open_in_new),
                label: const Text("Détail"),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final double size;
  const _ImagePlaceholder({this.size = 200});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size == 200 ? double.infinity : size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Icon(Icons.image_not_supported),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({this.url});
  @override
  Widget build(BuildContext context) {
    const w = 56.0;
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: w,
          height: w,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImagePlaceholder(size: 56),
        ),
      );
    }
    return const _ImagePlaceholder(size: 56);
  }
}

class AuthNotice extends StatefulWidget {
  const AuthNotice({super.key});
  @override
  State<AuthNotice> createState() => _AuthNoticeState();
}

class _AuthNoticeState extends State<AuthNotice> {
  bool _logged = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _logged = await AuthService.isLoggedIn();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_logged) return const SizedBox.shrink();
    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text("Tu n’es pas connecté"),
        subtitle: const Text("Connecte-toi pour terminer et noter les escapes"),
        trailing: FilledButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => const _AuthDialog(),
            );
            if (ok == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Connecté")),
              );
              setState(() {}); // rafraîchit l’affichage
            }
          },
          child: const Text("Se connecter"),
        ),
      ),
    );
  }
}

/* ===================== Helpers ===================== */

Future<void> _openDirections(double lat, double lon) async {
  final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=walking');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw Exception("Impossible d’ouvrir Google Maps.");
  }
}

Future<void> _ensureLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) throw Exception("Service de localisation désactivé.");
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) {
      throw Exception("Permission de localisation refusée.");
    }
  }
  if (perm == LocationPermission.deniedForever) {
    throw Exception("Permission refusée définitivement. Autorise-la dans les paramètres.");
  }
}
