// lib/main.dart
import 'dart:async';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EscapeCityApp());
}

/// Emulateur Android classique => 10.0.2.2
/// (Si tu fais `adb reverse tcp:8000 tcp:8000`, bascule en 127.0.0.1)
const String baseUrl = "http://10.0.2.2:8000";
const double kDefaultRadiusKm = 20;

class EscapeCityApp extends StatelessWidget {
  const EscapeCityApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escape City',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const MainHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainHome extends StatefulWidget {
  const MainHome({super.key});
  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  int _tabIndex = 0;

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
        title: const Text('Escape City'),
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
  final String? createdAt;
  final String status;
  final String? imageUrl;
  final String description;

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
    this.imageUrl,
    this.description = '',
  });

  factory EscapeGame.fromJson(Map<String, dynamic> j) => EscapeGame(
        id: j['id'] as int,
        title: (j['title'] ?? j['name'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        latitude: ((j['latitude'] ?? j['lat'] ?? 0).toDouble()),
        longitude: ((j['longitude'] ?? j['lon'] ?? j['lng'] ?? 0).toDouble()),
        rating: ((j['rating'] ?? j['avg_rating'] ?? 0).toDouble()),
        durationMinutes: ((j['duration_minutes'] ?? j['duration'] ?? 60) as num).toInt(),
        difficulty: ((j['difficulty'] ?? 1) as num).toInt(),
        status: (j['status'] ?? 'published') as String,
        createdAt: j['created_at'] as String?,
        imageUrl: j['image_url'] as String?,
        description: (j['description'] ?? '') as String,
      );
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

class ApiService {
  ApiService._();
  static final instance = ApiService._();

  Future<List<EscapeGame>> fetchAll() async {
    final r = await http.get(Uri.parse('$baseUrl/api/escapes/'));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} /api/escapes/');
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => EscapeGame.fromJson(e)).toList();
  }

  Future<List<EscapeGame>> fetchNearby({
    required double lat,
    required double lon,
    double radiusKm = kDefaultRadiusKm,
  }) async {
    final r = await http.get(Uri.parse(
        '$baseUrl/api/escapes/nearby?lat=$lat&lon=$lon&radius_km=$radiusKm'));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} /api/escapes/nearby');
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => EscapeGame.fromJson(e)).toList();
  }

  Future<List<CommentItem>> fetchComments(int escapeId, {int limit = 3}) async {
    final r = await http.get(
        Uri.parse('$baseUrl/api/escapes/$escapeId/comments?limit=$limit'));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} comments');
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => CommentItem.fromJson(e)).toList();
  }

  Future<bool> canRate(int escapeId) async {
    final r = await http.get(Uri.parse('$baseUrl/api/escapes/$escapeId/can_rate'));
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
    final r = await http.post(
      Uri.parse('$baseUrl/api/escapes/$escapeId/ratings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({'stars': stars, 'comment': comment}),
    );
    if (r.statusCode != 201) {
      throw Exception('Note refusée: ${r.statusCode} ${r.body}');
    }
  }

  // Créateur
  Future<List<EscapeGame>> fetchCreatorList() async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await http.get(
      Uri.parse('$baseUrl/api/creator/escapes/'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final L = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return L.map((e) => EscapeGame.fromJson(e)).toList();
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
    final r = await http.post(
      Uri.parse('$baseUrl/api/creator/escapes/'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'duration_minutes': durationMinutes,
        'difficulty': difficulty,
        'description': description,
        'steps': [],
      }),
    );
    if (r.statusCode != 201) throw Exception('Création refusée: ${r.statusCode} ${r.body}');
    final j = jsonDecode(r.body);
    return (j['id'] as num).toInt();
  }

  Future<void> publish(int id) async {
    final token = await AuthService.instance.getToken();
    if (token == null) throw Exception('Non connecté');
    final r = await http.post(
      Uri.parse('$baseUrl/api/creator/escapes/$id/publish'),
      headers: {'Authorization': 'Token $token'},
    );
    if (r.statusCode != 200) throw Exception('Publication refusée: ${r.statusCode} ${r.body}');
  }
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final tokenNotifier = ValueNotifier<String?>(null);

  Future<void> loadFromPrefs() async {
    final sp = await SharedPreferences.getInstance();
    tokenNotifier.value = sp.getString('auth_token');
  }

  Future<String?> getToken() async => tokenNotifier.value;

  Future<void> saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('auth_token', token);
    tokenNotifier.value = token;
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('auth_token');
    tokenNotifier.value = null;
  }

  Future<void> login(String username, String password) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (r.statusCode != 200) throw Exception('Identifiants invalides');
    final j = jsonDecode(r.body);
    final token = j['token'] as String?;
    if (token == null) throw Exception('Token manquant');
    await saveToken(token);
  }

  Future<void> register(String username, String password, String? email) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      }),
    );
    if (r.statusCode != 201) throw Exception('Inscription refusée: ${r.statusCode}');
    final j = jsonDecode(r.body);
    final token = j['token'] as String?;
    if (token == null) throw Exception('Token manquant');
    await saveToken(token);
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

  // NOUVEAU : on garde une source de vérité
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
      _items = _applyFiltersAndSort(_all); // re-calcul immédiat
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
                            '${e.city} • ${e.durationMinutes} min • diff ${e.difficulty}${dist != null ? " • $dist km" : ""}'),
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
   WIDGETS : CARTE
============================ */

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _api = ApiService.instance;
  GoogleMapController? _controller;
  LatLng _center = const LatLng(48.8566, 2.3522); // Paris
  Set<Marker> _markers = {};
  EscapeGame? _selected;
  double _currentZoom = 12;
  bool _loading = true;

  // Fit bounds uniquement la première fois
  bool _fitOnce = true;
  LatLng? _lastCenter;
  double? _lastZoom;

  // cache icônes
  final Map<String, BitmapDescriptor> _iconCache = {};

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

  Future<void> _setInitialCenterFromLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      _center = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  Future<void> _refreshMapData() async {
    try {
      var items = await _api.fetchNearby(
        lat: _center.latitude,
        lon: _center.longitude,
        radiusKm: kDefaultRadiusKm,
      );
      if (items.isEmpty) {
        items = await _api.fetchAll();
      }
      await _rebuildClusters(items);

      if (_fitOnce && _markers.isNotEmpty && _controller != null) {
        final lats = _markers.map((m) => m.position.latitude).toList();
        final lons = _markers.map((m) => m.position.longitude).toList();
        final sw = LatLng(
          lats.reduce((a, b) => a < b ? a : b),
          lons.reduce((a, b) => a < b ? a : b),
        );
        final ne = LatLng(
          lats.reduce((a, b) => a > b ? a : b),
          lons.reduce((a, b) => a > b ? a : b),
        );
        final bounds = LatLngBounds(southwest: sw, northeast: ne);
        await _controller!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 60),
        );
        _fitOnce = false;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur carte: $e')),
      );
    }
  }

  // === Nouveau clustering “à rayon pixels” (meilleure désagrégation au zoom) ===

  double _metersPerPixel(double lat, double zoom) {
    // WebMercator approx
    return 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final la1 = a.latitude * math.pi / 180.0;
    final la2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * R * math.asin(math.sqrt(h));
  }

  Future<void> _rebuildClusters(List<EscapeGame> items) async {
    // Rayon en pixels pour fusionner (ajuste au besoin)
    const radiusPx = 72.0;
    final mpp = _metersPerPixel(_center.latitude, _currentZoom);
    final radiusMeters = mpp * radiusPx;

    final clusters = <_Cluster2>[];

    for (final e in items) {
      final p = LatLng(e.latitude, e.longitude);
      _Cluster2? target;
      double best = double.infinity;

      // Cherche le cluster le plus proche sous le rayon
      for (final c in clusters) {
        final d = _haversineMeters(c.center, p);
        if (d < radiusMeters && d < best) {
          best = d;
          target = c;
        }
      }

      if (target == null) {
        clusters.add(_Cluster2(e));
      } else {
        target.add(e);
      }
    }

    final markers = <Marker>{};
    for (final c in clusters) {
      if (c.count == 1) {
        final e = c.items.first;
        final icon = await _getCircleIcon(
          text: e.rating > 0 ? e.rating.toStringAsFixed(1) : null,
        );
        markers.add(Marker(
          markerId: MarkerId("e_${e.id}"),
          position: LatLng(e.latitude, e.longitude),
          icon: icon,
          onTap: () => setState(() => _selected = e),
        ));
      } else {
        final center = c.center;
        final icon = await _getCircleIcon(text: "${c.count}");
        markers.add(Marker(
          markerId: MarkerId("c_${center.latitude}_${center.longitude}_${c.count}"),
          position: center,
          icon: icon,
          onTap: () async {
            await _controller?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: center,
                  zoom: (_currentZoom + 2).clamp(3, 20).toDouble(),
                ),
              ),
            );
          },
        ));
      }
    }

    if (!mounted) return;
    setState(() => _markers = markers);
  }

  Future<BitmapDescriptor> _getCircleIcon({String? text}) async {
    final key = 'v2:${text ?? 'single'}'; // <-- ajoute 'v2:' pour invalider l'ancien cache
    if (_iconCache.containsKey(key)) return _iconCache[key]!;
    final bmp = await _buildCircleMarkerIcon(text: text);
    _iconCache[key] = bmp;
    return bmp;
  }

  // Pastille bleu foncé, bordure blanche, texte blanc gras, fond transparent
  Future<BitmapDescriptor> _buildCircleMarkerIcon({String? text}) async {
  const int size = 120;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
  );

  // fond transparent
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0x00000000),
  );

  // cercle bleu + liseré blanc
  final blue = const Color(0xFF0B3D91);
  final white = const Color(0xFFFFFFFF);
  final center = Offset(size / 2, size / 2);
  final radius = size * 0.44;

  canvas.drawCircle(center, radius, Paint()..color = blue);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0,
  );

  // texte centré (si fourni)
  if (text != null && text.isNotEmpty) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.toDouble());

    final dx = (size - tp.width) / 2;
    final dy = (size - tp.height) / 2 - 2; // petit ajustement optique
    tp.paint(canvas, Offset(dx, dy));
  }

  final picture = recorder.endRecording();
  final img = await picture.toImage(size, size);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
}

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          myLocationEnabled: true,
          myLocationButtonEnabled: false, // on garde notre bouton custom
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          initialCameraPosition: CameraPosition(target: _center, zoom: 12),
          onMapCreated: (c) => _controller = c,
          markers: _markers,
          onCameraMove: (p) {
            _currentZoom = p.zoom;
            _center = p.target;
          },
          onCameraIdle: () async {
            // recharge si changement significatif
            if (_lastZoom == null ||
                (_lastZoom! - _currentZoom).abs() >= 0.35 ||
                _lastCenter == null ||
                _distanceDeg(_lastCenter!, _center) >= 0.02) {
              _lastZoom = _currentZoom;
              _lastCenter = _center;

              // Pas besoin de re-fetch si on reste dans la même zone :
              // on refait juste le clustering avec les mêmes items
              // MAIS comme on ne conserve pas les "items" ici,
              // on re-fetch léger nearby (plus simple et reste fluide).
              await _refreshMapData();
            }
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

  double _distanceDeg(LatLng a, LatLng b) =>
      ((a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs());

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
                child: Text('${e.title}\n${e.city}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
      if (!enabled) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Géolocalisation indisponible')));
    }
  }

  Future<void> _openDirections(EscapeGame e) async {
    LatLng origin = _center;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        LocationPermission p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        if (p != LocationPermission.denied && p != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition();
          origin = LatLng(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {}
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${origin.latitude},${origin.longitude}'
      '&destination=${e.latitude},${e.longitude}'
      '&travelmode=walking',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

class _Cluster2 {
  double latSum = 0, lonSum = 0;
  int count = 0;
  double ratingSum = 0;
  final List<EscapeGame> items = [];
  _Cluster2(EscapeGame e) {
    add(e);
  }
  void add(EscapeGame e) {
    latSum += e.latitude;
    lonSum += e.longitude;
    count++;
    ratingSum += e.rating;
    items.add(e);
  }
  LatLng get center => LatLng(latSum / count, lonSum / count);
  double get avgRating => count == 0 ? 0 : ratingSum / count;
}

/* ============================
   WIDGETS : DÉTAILS
============================ */

class EscapeDetailsPage extends StatefulWidget {
  final EscapeGame escape;
  const EscapeDetailsPage({super.key, required this.escape});

  @override
  State<EscapeDetailsPage> createState() => _EscapeDetailsPageState();
}

class _EscapeDetailsPageState extends State<EscapeDetailsPage> {
  final _api = ApiService.instance;

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
                e.imageUrl!,
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
            subtitle: Text('Note ${e.rating.toStringAsFixed(1)} • ${e.durationMinutes} min • diff ${e.difficulty}'),
          ),
          const SizedBox(height: 8),

          FilledButton.icon(
            icon: const Icon(Icons.directions_walk),
            label: const Text('Itinéraire'),
            onPressed: () async {
              final url = Uri.parse(
                'https://www.google.com/maps/dir/?api=1'
                '&destination=${e.latitude},${e.longitude}'
                '&travelmode=walking',
              );
              await launchUrl(url, mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 16),

          const Text('Derniers commentaires', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<CommentItem>>(
            future: _api.fetchComments(e.id, limit: 3),
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
                    )
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          ValueListenableBuilder<String?>(
            valueListenable: AuthService.instance.tokenNotifier,
            builder: (context, token, _) {
              if (token == null) {
                return const Text(
                  'Connectez-vous pour noter cet escape.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                );
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.star),
                  label: const Text('Noter'),
                  onPressed: () => _openRatingDialog(context, e),
                ),
              );
            },
          ),
        ],
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
              items: List.generate(5, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} ★'))),
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
                await _api.submitRating(
                  escapeId: e.id,
                  stars: stars,
                  comment: controller.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Merci pour votre note !')),
                  );
                  setState(() {});
                }
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
   WIDGETS : CRÉATEUR
============================ */

class CreatorPage extends StatefulWidget {
  const CreatorPage({super.key});
  @override
  State<CreatorPage> createState() => _CreatorPageState();
}

class _CreatorPageState extends State<CreatorPage> {
  final _api = ApiService.instance;
  Future<List<EscapeGame>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _api.fetchCreatorList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.instance.tokenNotifier,
      builder: (context, token, _) {
        if (token == null) {
          return const Center(child: Text('Connectez-vous pour accéder au mode créateur.'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  const Text('Mes escapes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Nouveau brouillon'),
                    onPressed: () => _openDraftDialog(context),
                  ),
                ],
              ),
            ),
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
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return const Center(child: Text('Aucun escape.'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = items[i];
                      return ListTile(
                        title: Text(e.title),
                        subtitle: Text('${e.city} • statut: ${e.status}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (e.status == 'draft')
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await _api.publish(e.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Publié !')),
                                      );
                                      _reload();
                                    }
                                  } catch (err) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Erreur: $err')),
                                    );
                                  }
                                },
                                child: const Text('Publier'),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _openDraftDialog(BuildContext context) {
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
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Brouillon créé (#$id)')),
                );
                _reload();
              } catch (err) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erreur: $err')),
                );
              }
            },
            child: const Text('Créer'),
          ),
        ],
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
