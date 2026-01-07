// lib/features/list/list_page.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import models
import '../../models/escape_game.dart';

// Import services
import '../../services/api/api_service.dart';

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
