// lib/map/map_screen.dart (ou ton fichier existant)
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart';
import 'marker_icons.dart'; // <— le fichier créé

class EscapeItem with ClusterItem {
  EscapeItem({required this.position, required this.id, required this.title, required this.rating});
  @override
  final LatLng position;
  final int id;
  final String title;
  final double rating;
}

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _map;
  late ClusterManager<EscapeItem> _manager;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    // TODO: remplace par tes données
    final items = <EscapeItem>[
      // … remplit depuis ton API …
    ];

    _manager = ClusterManager<EscapeItem>(
      items,
      _updateMarkers,
      markerBuilder: _markerBuilder,
      levels: [1, 5, 9, 12, 16], // adapte si besoin
    );
  }

  void _updateMarkers(Set<Marker> markers) {
    setState(() => _markers = markers);
  }

  Future<Marker> _markerBuilder(Cluster<EscapeItem> cluster) async {
    if (cluster.isMultiple) {
      // CLUSTER : bleu foncé + nombre
      final icon = await clusterIcon(cluster.count);
      return Marker(
        markerId: MarkerId('cluster_${cluster.getId()}'),
        position: cluster.location,
        icon: icon,
        consumeTapEvents: true,
        onTap: () {
          // Zoomer sur le cluster au tap
          _map?.animateCamera(
            CameraUpdate.newLatLngZoom(cluster.location, (_mapZoom + 2).clamp(3.0, 21.0)),
          );
        },
      );
    } else {
      // ESCAPE INDIVIDUEL : vert + note (une décimale)
      final item = cluster.items.first;
      final icon = await ratingIcon(item.rating);
      return Marker(
        markerId: MarkerId('escape_${item.id}'),
        position: item.position,
        icon: icon,
        infoWindow: InfoWindow(title: item.title, snippet: 'Note ${item.rating.toStringAsFixed(1)}'),
        onTap: () {
          // Ouvre ta fiche, etc.
        },
      );
    }
  }

  double _mapZoom = 10;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: LatLng(48.8566, 2.3522), zoom: 11),
      onMapCreated: (c) {
        _map = c;
        _manager.setMapId(c.mapId);
      },
      onCameraMove: (pos) {
        _mapZoom = pos.zoom;
        _manager.onCameraMove(pos);
      },
      onCameraIdle: _manager.updateMap,
      markers: _markers,
      myLocationButtonEnabled: false,
      compassEnabled: true,
    );
  }
}
