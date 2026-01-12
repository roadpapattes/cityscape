// lib/features/map/map_page.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Import models
import '../../models/escape_game.dart';

// Import services
import '../../services/api/api_service.dart';
import '../../services/favorites_service.dart';

// Import constants
import '../../core/constants.dart';

// Import widgets
import 'widgets/custom_marker_painter.dart';
import 'widgets/escape_bottom_sheet.dart';
import 'widgets/map_filters.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _api = ApiService.instance;
  final _favService = FavoritesService.instance;

  GoogleMapController? _controller;
  LatLng _center = const LatLng(48.8566, 2.3522); // Paris
  LatLng? _userLoc;

  // Données et rendus
  List<EscapeGame> _items = [];
  List<EscapeGame> _filteredItems = [];
  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // Rayon de recherche
  EscapeGame? _selected;
  bool _loading = true;
  bool _didAutoCenter = false;

  // Filtres
  MapFilters _filters = const MapFilters();
  Set<int> _favoriteIds = {};

  // Paramètres de clustering
  double _zoom = 12;
  static const double _gridSizePx = 80;

  // Style de carte (mode sombre optionnel)
  bool _isDarkMode = false;
  static const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#212121"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#757575"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#212121"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#000000"}]
  }
]
''';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _setInitialCenterFromLocation();
    await _refreshMapData();
    await _loadFavorites();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFavorites() async {
    final favIds = await _favService.getAllFavoriteIds();
    if (mounted) {
      setState(() => _favoriteIds = favIds);
    }
  }

  bool _looksLikeAndroidEmuLatLng(double lat, double lon) {
    const mvLat = 37.4219983;
    const mvLon = -122.084;
    const tol = 0.02;
    return ((lat - mvLat).abs() < tol && (lon - mvLon).abs() < tol);
  }

  Future<void> _setInitialCenterFromLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _userLoc = const LatLng(48.8566, 2.3522);
        _center = _userLoc!;
        return;
      }

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        _userLoc = const LatLng(48.8566, 2.3522);
        _center = _userLoc!;
        return;
      }

      final pos = await Geolocator.getCurrentPosition();

      if (_looksLikeAndroidEmuLatLng(pos.latitude, pos.longitude)) {
        _userLoc = const LatLng(48.8566, 2.3522);
      } else {
        _userLoc = LatLng(pos.latitude, pos.longitude);
      }
      _center = _userLoc!;
    } catch (_) {
      _userLoc = const LatLng(48.8566, 2.3522);
      _center = _userLoc!;
    }
  }

  Future<void> _refreshMapData() async {
    try {
      var items = await _api.fetchAll();
      _items = items;
      _applyFilters();
      _updateSearchRadius();
      await _rebuildMarkers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur carte: $e')),
      );
    }
  }

  void _applyFilters() {
    _filteredItems = _items.where((e) {
      // Filtre difficulté
      if (!_filters.difficulties.contains(e.difficulty)) return false;

      // Filtre note minimale
      if (e.rating < _filters.minRating) return false;

      // Filtre favoris
      if (_filters.favoritesOnly && !_favoriteIds.contains(e.id)) {
        return false;
      }

      return true;
    }).toList();
  }

  void _updateSearchRadius() {
    if (_userLoc == null) {
      setState(() => _circles = {});
      return;
    }

    setState(() {
      _circles = {
        Circle(
          circleId: const CircleId('searchRadius'),
          center: _userLoc!,
          radius: kDefaultRadiusKm * 1000, // km vers mètres
          fillColor: Colors.blue.withOpacity(0.1),
          strokeColor: Colors.blue.withOpacity(0.3),
          strokeWidth: 2,
        ),
      };
    });
  }

  // ============================
  // Clustering
  // ============================

  Future<void> _rebuildMarkers() async {
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
      visible.addAll(_filteredItems);
    } else {
      final sw = b.southwest;
      final ne = b.northeast;

      bool inBounds(EscapeGame e) {
        final lat = e.latitude, lon = e.longitude;
        final latOk = lat >= sw.latitude && lat <= ne.latitude;

        if (sw.longitude <= ne.longitude) {
          return latOk && lon >= sw.longitude && lon <= ne.longitude;
        }
        return latOk && (lon >= sw.longitude || lon <= ne.longitude);
      }

      for (final e in _filteredItems) {
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
      return (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2 *
          worldSize;
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
        final icon = await CustomMarkerGenerator.createEscapeMarker(
          difficulty: e.difficulty,
          rating: e.rating,
        );
        out.add(Marker(
          markerId: MarkerId('e_${e.id}'),
          position: LatLng(e.latitude, e.longitude),
          icon: icon,
          onTap: () => setState(() => _selected = e),
          anchor: const Offset(0.5, 1.0), // Ancre au bas du pin
        ));
      } else {
        // Cluster
        final lat =
            list.map((e) => e.latitude).reduce((a, b) => a + b) / list.length;
        final lon =
            list.map((e) => e.longitude).reduce((a, b) => a + b) / list.length;
        final count = list.length;

        final icon = await CustomMarkerGenerator.createClusterMarker(
          count: count,
        );
        out.add(Marker(
          markerId: MarkerId('c_${entry.key}_$count'),
          position: LatLng(lat, lon),
          icon: icon,
          onTap: () async {
            final target = LatLng(lat, lon);
            final nextZoom = (_zoom + 2).clamp(2.0, 20.0);
            await _controller?.animateCamera(
              CameraUpdate.newCameraPosition(
                  CameraPosition(target: target, zoom: nextZoom)),
            );
          },
        ));
      }
    }

    if (!mounted) return;
    setState(() => _markers = out);
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
            if (_isDarkMode) {
              c.setMapStyle(_darkMapStyle);
            }
            if (!_didAutoCenter) {
              _didAutoCenter = true;
              _goToMyLocation();
            }
          },
          markers: _markers,
          circles: _circles,
          onCameraMove: (pos) {
            final newZoom = pos.zoom;
            _center = pos.target;

            if ((newZoom - _zoom).abs() >= 1.0) {
              _zoom = newZoom;
              _rebuildMarkers();
            }
          },
          onCameraIdle: () {
            _rebuildMarkers();
          },
        ),

        // Boutons flottants
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              // Bouton Ma position
              FloatingActionButton.small(
                heroTag: 'myLoc',
                tooltip: 'Ma position',
                onPressed: _goToMyLocation,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),

              // Bouton Mode sombre
              FloatingActionButton.small(
                heroTag: 'darkMode',
                tooltip: 'Mode sombre',
                onPressed: () {
                  setState(() => _isDarkMode = !_isDarkMode);
                  if (_isDarkMode) {
                    _controller?.setMapStyle(_darkMapStyle);
                  } else {
                    _controller?.setMapStyle(null);
                  }
                },
                child: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              ),
            ],
          ),
        ),

        // Filtres
        Positioned(
          bottom: _selected != null ? 280 : 24,
          right: 12,
          child: MapFiltersButton(
            filters: _filters,
            onFiltersChanged: (newFilters) {
              setState(() {
                _filters = newFilters;
                _applyFilters();
              });
              _rebuildMarkers();
            },
          ),
        ),

        // Bottom sheet
        if (_selected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: EscapeBottomSheet(
              escape: _selected!,
              userLocation: _userLoc,
              onClose: () {
                setState(() => _selected = null);
              },
            ),
          ),

        // Loading
        if (_loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Future<void> _goToMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        final target = const LatLng(48.8566, 2.3522);
        _userLoc = target;
        await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
        _updateSearchRadius();
        await _rebuildMarkers();
        return;
      }

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        final target = const LatLng(48.8566, 2.3522);
        _userLoc = target;
        await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
        _updateSearchRadius();
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
      _updateSearchRadius();
      await _rebuildMarkers();
    } catch (_) {
      final target = const LatLng(48.8566, 2.3522);
      _userLoc = target;
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
      _updateSearchRadius();
      await _rebuildMarkers();
    }
  }
}
