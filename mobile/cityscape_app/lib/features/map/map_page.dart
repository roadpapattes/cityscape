// lib/features/map/map_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Import models
import '../../models/escape_game.dart';

// Import services
import '../../services/api/api_service.dart';

// Import constants
import '../../core/constants.dart';

// Import EscapeDetailsPage (temporarily from main.dart until it's extracted)
import '../../main.dart' show EscapeDetailsPage;

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
  // Position réelle de l'utilisateur (si dispo)
  LatLng? _userLoc;

  // Données et rendus
  List<EscapeGame> _items = [];
  Set<Marker> _markers = {};
  EscapeGame? _selected;
  bool _loading = true;
  bool _didAutoCenter = false;

  // Cache d'icônes générées à la volée (bitmap)
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
  // Heuristique: l'émulateur Android par défaut renvoie ~ (37.4219983, -122.084)
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

    // Si ça ressemble fortement à l'émulateur Android (Google HQ),
    // on fige Paris ; sinon, on prend la vraie position.
    if (_looksLikeAndroidEmuLatLng(pos.latitude, pos.longitude)) {
      _userLoc = const LatLng(48.8566, 2.3522);
    } else {
      _userLoc = LatLng(pos.latitude, pos.longitude);
    }
    _center = _userLoc!;
  } catch (_) {
    // En cas d'erreur, on reste sur Paris
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
