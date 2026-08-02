// lib/features/map/widgets/escape_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/escape_game.dart';
import '../../../services/favorites_service.dart';
import '../../../main.dart' show EscapeDetailsPage;

class EscapeBottomSheet extends StatefulWidget {
  final EscapeGame escape;
  final LatLng? userLocation;
  final VoidCallback onClose;

  const EscapeBottomSheet({
    super.key,
    required this.escape,
    required this.userLocation,
    required this.onClose,
  });

  @override
  State<EscapeBottomSheet> createState() => _EscapeBottomSheetState();
}

class _EscapeBottomSheetState extends State<EscapeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final _favService = FavoritesService.instance;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final isFav = await _favService.isFavorite(widget.escape.id);
    if (mounted) {
      setState(() => _isFavorite = isFav);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.reverse().then((_) => widget.onClose());
  }

  String _getDistance() {
    if (widget.userLocation == null) return 'Distance inconnue';
    final distance = _calculateDistance(
      widget.userLocation!.latitude,
      widget.userLocation!.longitude,
      widget.escape.latitude,
      widget.escape.longitude,
    );
    if (distance < 1) {
      return '${(distance * 1000).round()} m';
    }
    return '${distance.toStringAsFixed(1)} km';
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (0.5 - 0.5 * _cos(dLat)) +
        _cos(_toRad(lat1)) * _cos(_toRad(lat2)) * (0.5 - 0.5 * _cos(dLon));
    return 2 * R * _asin(_sqrt(a));
  }

  double _toRad(double deg) => deg * 3.14159265359 / 180.0;
  double _cos(double x) => _cosHelper(x);
  double _sin(double x) => _cosHelper(x - 3.14159265359 / 2);
  double _asin(double x) => x; // Approximation simplifiée
  double _sqrt(double x) => x; // Approximation simplifiée
  double _cosHelper(double x) {
    // Taylor series approximation
    return 1 - x * x / 2 + x * x * x * x / 24;
  }

  Future<void> _openDirections() async {
    final origin = widget.userLocation ?? LatLng(48.8566, 2.3522);
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${origin.latitude},${origin.longitude}'
      '&destination=${widget.escape.latitude},${widget.escape.longitude}'
      '&travelmode=walking',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await _favService.removeFavorite(widget.escape.id);
    } else {
      await _favService.addFavorite(widget.escape.id);
    }
    if (mounted) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _animation.value) * 300),
          child: Opacity(
            opacity: _animation.value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre de drag
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Contenu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête avec image et infos principales
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: widget.escape.imageUrl != null &&
                                widget.escape.imageUrl!.isNotEmpty
                            ? Image.network(
                                widget.escape.imageUrl!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              )
                            : _buildPlaceholder(),
                      ),
                      const SizedBox(width: 16),

                      // Infos
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Titre
                            Text(
                              widget.escape.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),

                            // Ville
                            Row(
                              children: [
                                Icon(Icons.location_city,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  widget.escape.city,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Note
                            _buildStarRating(),
                          ],
                        ),
                      ),

                      // Bouton favori
                      IconButton(
                        icon: Icon(
                          _isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: _isFavorite ? Colors.red : Colors.grey,
                        ),
                        onPressed: _toggleFavorite,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildBadge(
                        icon: Icons.signal_cellular_alt,
                        label: _getDifficultyLabel(),
                        color: _getDifficultyColor(),
                      ),
                      _buildBadge(
                        icon: Icons.access_time,
                        label: '${widget.escape.durationMinutes} min',
                        color: Colors.blue,
                      ),
                      _buildBadge(
                        icon: Icons.directions_walk,
                        label: _getDistance(),
                        color: Colors.green,
                      ),
                      _buildBadge(
                        icon: Icons.shield_outlined,
                        label: _getAgeLabel(),
                        color: _getAgeColor(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description si disponible
                  if (widget.escape.description.isNotEmpty) ...[
                    Text(
                      widget.escape.description,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Boutons d'action
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Détails'),
                          onPressed: () {
                            _close();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EscapeDetailsPage(escape: widget.escape),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('Itinéraire'),
                          onPressed: _openDirections,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.image, size: 40, color: Colors.grey[500]),
    );
  }

  Widget _buildStarRating() {
    final rating = widget.escape.rating;
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;

    return Row(
      children: [
        for (int i = 0; i < fullStars; i++)
          const Icon(Icons.star, color: Colors.amber, size: 18),
        if (hasHalfStar)
          const Icon(Icons.star_half, color: Colors.amber, size: 18),
        for (int i = fullStars + (hasHalfStar ? 1 : 0); i < 5; i++)
          Icon(Icons.star_border, color: Colors.grey[400], size: 18),
        const SizedBox(width: 4),
        Text(
          rating > 0 ? rating.toStringAsFixed(1) : 'N/A',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getDifficultyLabel() {
    switch (widget.escape.difficulty) {
      case 1:
        return 'Facile';
      case 2:
        return 'Moyen';
      case 3:
        return 'Difficile';
      default:
        return 'Inconnu';
    }
  }

  Color _getDifficultyColor() {
    switch (widget.escape.difficulty) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getAgeLabel() => 'PEGI ${widget.escape.ageRating}+';

  Color _getAgeColor() {
    switch (widget.escape.ageRating) {
      case '12':
        return Colors.orange;
      case '18':
        return Colors.red;
      default:
        return Colors.green;
    }
  }
}
