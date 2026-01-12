// lib/features/list/widgets/card_collection_style.dart

import 'package:flutter/material.dart';
import '../../../models/escape_game.dart';

class CardCollectionStyleCard extends StatelessWidget {
  final EscapeGame escape;
  final bool isFavorite;
  final String? distance;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const CardCollectionStyleCard({
    super.key,
    required this.escape,
    required this.isFavorite,
    this.distance,
    required this.onTap,
    required this.onFavoriteTap,
  });

  Color _getDifficultyColor() {
    switch (escape.difficulty) {
      case 1:
        return const Color(0xFF4CAF50); // Vert
      case 2:
        return const Color(0xFFFF9800); // Orange
      case 3:
        return const Color(0xFFF44336); // Rouge
      default:
        return Colors.grey;
    }
  }

  LinearGradient _getDifficultyGradient() {
    final baseColor = _getDifficultyColor();
    return LinearGradient(
      colors: [
        baseColor.withOpacity(0.8),
        baseColor.withOpacity(0.4),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: _getDifficultyGradient(),
          boxShadow: [
            BoxShadow(
              color: _getDifficultyColor().withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Background pattern
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.1,
                    child: CustomPaint(
                      painter: _DiamondPatternPainter(),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header avec titre et favoris
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              escape.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              color: isFavorite ? Colors.amber : Colors.white,
                            ),
                            onPressed: onFavoriteTap,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Badges d'infos
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildBadge(
                            Icons.location_city,
                            escape.city,
                            Colors.white,
                          ),
                          _buildBadge(
                            Icons.timer,
                            '${escape.durationMinutes} min',
                            Colors.white,
                          ),
                          if (distance != null)
                            _buildBadge(
                              Icons.near_me,
                              '$distance km',
                              Colors.white,
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Footer avec note et difficulté
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Note
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  escape.rating > 0
                                      ? escape.rating.toStringAsFixed(1)
                                      : '–',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Difficulté
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                3,
                                (index) => Icon(
                                  Icons.brightness_1,
                                  size: 12,
                                  color: index < escape.difficulty
                                      ? _getDifficultyColor()
                                      : Colors.grey[300],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter pour le motif de fond
class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        final path = Path()
          ..moveTo(x, y - 10)
          ..lineTo(x + 10, y)
          ..lineTo(x, y + 10)
          ..lineTo(x - 10, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
