// lib/features/list/widgets/playful_style.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../models/escape_game.dart';

class PlayfulStyleCard extends StatelessWidget {
  final EscapeGame escape;
  final bool isFavorite;
  final String? distance;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const PlayfulStyleCard({
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
        return const Color(0xFF7CB342); // Vert pomme
      case 2:
        return const Color(0xFFFFB300); // Jaune doré
      case 3:
        return const Color(0xFFE53935); // Rouge cerise
      default:
        return Colors.blue;
    }
  }

  List<Color> _getPlayfulGradient() {
    final baseColor = _getDifficultyColor();
    return [
      baseColor,
      _adjustColor(baseColor, 0.8),
    ];
  }

  Color _adjustColor(Color color, double factor) {
    return Color.fromRGBO(
      (color.red * factor).round().clamp(0, 255),
      (color.green * factor).round().clamp(0, 255),
      (color.blue * factor).round().clamp(0, 255),
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _getPlayfulGradient();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Stack(
          children: [
            // Main card
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  children: [
                    // Header coloré
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Patterns décoratifs
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _BubblesPainter(),
                            ),
                          ),

                          // Contenu du header
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Icône de difficulté
                                _buildDifficultyIcon(),
                                const SizedBox(width: 12),

                                // Titre
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        escape.title,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Favoris
                                Material(
                                  color: Colors.white.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    onTap: onFavoriteTap,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        isFavorite ? Icons.favorite : Icons.favorite_border,
                                        color: isFavorite ? Colors.red : Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Contenu
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Badges colorés
                          Row(
                            children: [
                              _buildColorfulBadge(
                                Icons.location_city,
                                escape.city,
                                Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              _buildColorfulBadge(
                                Icons.access_time,
                                '${escape.durationMinutes} min',
                                Colors.purple,
                              ),
                              if (distance != null) ...[
                                const SizedBox(width: 8),
                                _buildColorfulBadge(
                                  Icons.place,
                                  '$distance km',
                                  Colors.teal,
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Note avec étoiles colorées
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ...List.generate(
                                5,
                                (index) => Icon(
                                  index < (escape.rating.round())
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: _getStarColor(index),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                escape.rating > 0
                                    ? escape.rating.toStringAsFixed(1)
                                    : 'Pas de note',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
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

            // Sticker "NOUVEAU" (si récent)
            // Positioned(
            //   top: 0,
            //   right: 20,
            //   child: Transform.rotate(
            //     angle: math.pi / 8,
            //     child: _buildSticker(),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyIcon() {
    final icons = [Icons.sentiment_satisfied, Icons.sentiment_neutral, Icons.sentiment_dissatisfied];
    final colors = [Colors.greenAccent, Colors.orangeAccent, Colors.redAccent];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icons[escape.difficulty - 1],
        color: colors[escape.difficulty - 1],
        size: 32,
      ),
    );
  }

  Widget _buildColorfulBadge(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStarColor(int index) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.lightGreen,
      Colors.green,
    ];
    return colors[index];
  }

  // Widget _buildSticker() {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  //     decoration: BoxDecoration(
  //       color: Colors.pink,
  //       borderRadius: BorderRadius.circular(8),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.pink.withOpacity(0.5),
  //           blurRadius: 8,
  //         ),
  //       ],
  //     ),
  //     child: const Text(
  //       'NOUVEAU',
  //       style: TextStyle(
  //         color: Colors.white,
  //         fontWeight: FontWeight.bold,
  //         fontSize: 10,
  //       ),
  //     ),
  //   );
  // }
}

class _BubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final random = math.Random(42); // Seed fixe pour consistance

    for (int i = 0; i < 15; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 20 + 10;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
