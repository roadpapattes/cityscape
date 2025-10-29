
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  runApp(const MyApp());
}

/// IMPORTANT : Ajuste cette constante suivant ton environnement.
/// - Android Emulator : http://10.0.2.2:8000
/// - iOS Simulator : http://127.0.0.1:8000
/// - Appareil physique : http://ADRESSE_LAN_DE_TON_PC:8000 (ex: http://192.168.1.50:8000)
const String baseUrl = "http://10.0.2.2:8000";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escape City',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const RootTabs(),
    );
  }
}

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
  });

  factory EscapeGame.fromJson(Map<String, dynamic> json) {
    return EscapeGame(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      city: json['city'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      durationMinutes: json['duration_minutes'] as int? ?? 60,
      difficulty: json['difficulty'] as int? ?? 1,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      distanceKm: json['distance_km'] != null ? (json['distance_km'] as num).toDouble() : null,
    );
  }
}

class ApiService {
  Future<List<EscapeGame>> fetchAll() async {
    final url = Uri.parse("$baseUrl/api/escapes/");
    final res = await http.get(url);
    if (res.statusCode != 200) throw Exception("Erreur API ${res.statusCode}");
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<EscapeGame>> fetchNearby({
    required double lat,
    required double lon,
    double radiusKm = 5,
  }) async {
    final url = Uri.parse("$baseUrl/api/escapes/nearby?lat=$lat&lon=$lon&radius_km=$radiusKm");
    final res = await http.get(url);
    if (res.statusCode != 200) throw Exception("Erreur API ${res.statusCode}");
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => EscapeGame.fromJson(e as Map<String, dynamic>)).toList();
  }
}

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
      body: IndexedStack(
        index: _index,
        children: const [
          HomeListPage(),
          MapPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: "Liste"),
          NavigationDestination(icon: Icon(Icons.map), label: "Carte"),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

class HomeListPage extends StatefulWidget {
  const HomeListPage({super.key});

  @override
  State<HomeListPage> createState() => _HomeListPageState();
}

class _HomeListPageState extends State<HomeListPage> {
  final _api = ApiService();
  final _latCtrl = TextEditingController(text: "48.8566");
  final _lonCtrl = TextEditingController(text: "2.3522");
  final _radiusCtrl = TextEditingController(text: "5");

  bool _loading = false;
  List<EscapeGame> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.fetchAll();
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNearby() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lat = double.parse(_latCtrl.text.trim());
      final lon = double.parse(_lonCtrl.text.trim());
      final r = double.tryParse(_radiusCtrl.text.trim()) ?? 5.0;
      final items = await _api.fetchNearby(lat: lat, lon: lon, radiusKm: r);
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escape City (Liste)"),
        actions: [
          IconButton(
            onPressed: _loadAll,
            tooltip: "Tout afficher",
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latCtrl,
                    decoration: const InputDecoration(
                      labelText: "Latitude",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lonCtrl,
                    decoration: const InputDecoration(
                      labelText: "Longitude",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _radiusCtrl,
                    decoration: const InputDecoration(
                      labelText: "Rayon (km)",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loadNearby,
                  icon: const Icon(Icons.my_location),
                  label: const Text("Autour"),
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
              itemBuilder: (context, index) {
                final e = _items[index];
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text(
                    "${e.city} • note ${e.rating.toStringAsFixed(1)} • ${e.durationMinutes} min • diff ${e.difficulty}"
                    "${e.distanceKm != null ? " • ${e.distanceKm!.toStringAsFixed(2)} km" : ""}",
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailPage(item: e),
                    ));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _api = ApiService();
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
  bool _loading = true;
  String? _error;

  static const CameraPosition _paris = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _api.fetchAll();
      final markers = items.map((e) => Marker(
        markerId: MarkerId("eg_${e.id}"),
        position: LatLng(e.latitude, e.longitude),
        infoWindow: InfoWindow(title: e.title, snippet: "${e.city} • ${e.rating.toStringAsFixed(1)}★"),
        onTap: () {
          showModalBottomSheet(
            context: context,
            builder: (_) => _BottomSheetCard(item: e),
          );
        },
      ));
      setState(() {
        _markers.clear();
        _markers.addAll(markers);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Carte des escapes")),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _paris,
            markers: _markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            onMapCreated: (c) => _controller = c,
          ),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 3),
            ),
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
        ],
      ),
    );
  }
}

class _BottomSheetCard extends StatelessWidget {
  final EscapeGame item;
  const _BottomSheetCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("${item.city} • note ${item.rating.toStringAsFixed(1)} • ${item.durationMinutes} min • diff ${item.difficulty}"),
            const SizedBox(height: 8),
            Text(item.description, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DetailPage(item: item),
                  ));
                },
                child: const Text("Voir le détail"),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class DetailPage extends StatelessWidget {
  final EscapeGame item;
  const DetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.city, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(item.description),
            const SizedBox(height: 16),
            Row(
              children: [
                Chip(label: Text("Note ${item.rating.toStringAsFixed(1)}")),
                const SizedBox(width: 8),
                Chip(label: Text("${item.durationMinutes} min")),
                const SizedBox(width: 8),
                Chip(label: Text("Diff ${item.difficulty}")),
              ],
            ),
            const SizedBox(height: 16),
            Text("Coordonnées: ${item.latitude}, ${item.longitude}"),
            if (item.distanceKm != null)
              Text("Distance: ${item.distanceKm!.toStringAsFixed(2)} km"),
          ],
        ),
      ),
    );
  }
}
