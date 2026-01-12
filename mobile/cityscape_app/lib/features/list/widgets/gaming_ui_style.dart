// lib/features/list/widgets/gaming_ui_style.dart

import 'package:flutter/material.dart';
import '../../../models/escape_game.dart';

class GamingUIStyleCard extends StatelessWidget {
  final EscapeGame escape;
  final bool isFavorite;
  final String? distance;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const GamingUIStyleCard({
    super.key,
    required this.escape,
    required this.isFavorite,
    this.distance,
    required this.onTap,
    required this.onFavoriteTap,
  });

  Color _getDifficultyNeonColor() {
    switch (escape.difficulty) {
      case 1:
        return const Color(0xFF00FF88); // Néon vert
      case 2:
        return const Color(0xFFFFAA00); // Néon orange
      case 3:
        return const Color(0xFFFF0066); // Néon rose
      default:
        return Colors.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final neonColor = _getDifficultyNeonColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E27),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: neonColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: neonColor.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: neonColor.withOpacity(0.3),
              blurRadius: 40,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Grid background
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  painter: _CyberGridPainter(neonColor),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header avec badge de difficulté
                  Row(
                    children: [
                      // Badge de difficulté en hexagone
                      _buildHexBadge(escape.difficulty, neonColor),
                      const SizedBox(width: 12),

                      // Titre
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              escape.title.toUpperCase(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: neonColor,
                                letterSpacing: 1.5,
                                shadows: [
                                  Shadow(
                                    color: neonColor.withOpacity(0.8),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              escape.city.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.cyan,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Favoris
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.bookmark : Icons.bookmark_border,
                          color: isFavorite ? neonColor : Colors.white54,
                        ),
                        onPressed: onFavoriteTap,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Stats bar
                  Row(
                    children: [
                      _buildStatChip(
                        Icons.timer_outlined,
                        '${escape.durationMinutes}\'',
                        neonColor,
                      ),
                      const SizedBox(width: 8),
                      _buildStatChip(
                        Icons.star_outline,
                        escape.rating > 0
                            ? escape.rating.toStringAsFixed(1)
                            : '–',
                        Colors.amber,
                      ),
                      if (distance != null) ...[
                        const SizedBox(width: 8),
                        _buildStatChip(
                          Icons.navigation,
                          '$distance km',
                          Colors.cyan,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Progress bar effet (décoratif)
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          neonColor,
                          neonColor.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner accent
            Positioned(
              top: 0,
              right: 0,
              child: ClipPath(
                clipper: _CornerClipper(),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        neonColor.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHexBadge(int level, Color color) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'LV$level',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CyberGridPainter extends CustomPainter {
  final Color color;

  _CyberGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.05)
      ..strokeWidth = 1;

    const spacing = 20.0;

    // Vertical lines
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Horizontal lines
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
