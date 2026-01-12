// lib/features/map/widgets/custom_marker_painter.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Génère des icônes de marqueurs personnalisées avec dégradés
class CustomMarkerGenerator {
  static final Map<String, BitmapDescriptor> _cache = {};

  /// Crée un marqueur pour un escape individuel
  static Future<BitmapDescriptor> createEscapeMarker({
    required int difficulty,
    required double rating,
    double size = 100.0,
  }) async {
    final key = 'escape_${difficulty}_${rating}_$size';
    if (_cache.containsKey(key)) return _cache[key]!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final markerSize = ui.Size(size, size * 1.3);

    // Couleur de dégradé selon la difficulté
    final gradientColors = _getGradientForDifficulty(difficulty);

    // Dessiner la goutte (pin shape)
    _drawPinShape(canvas, markerSize, gradientColors);

    // Dessiner les étoiles pour la note
    _drawStars(canvas, markerSize, rating);

    // Dessiner le badge de difficulté
    _drawDifficultyBadge(canvas, markerSize, difficulty);

    final picture = recorder.endRecording();
    final img = await picture.toImage(markerSize.width.toInt(), markerSize.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final bmp = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());

    _cache[key] = bmp;
    return bmp;
  }

  /// Crée un marqueur pour un cluster
  static Future<BitmapDescriptor> createClusterMarker({
    required int count,
    double size = 110.0,
  }) async {
    final key = 'cluster_${count}_$size';
    if (_cache.containsKey(key)) return _cache[key]!;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final markerSize = ui.Size(size, size);
    final center = Offset(size / 2, size / 2);
    final radius = size / 2;

    // Dégradé bleu pour les clusters
    final gradient = ui.Gradient.radial(
      center,
      radius,
      [
        const Color(0xFF1E88E5),
        const Color(0xFF0B3D91),
      ],
      [0.0, 1.0],
    );

    // Ombre portée
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(0, 4), radius - 4, shadowPaint);

    // Cercle avec dégradé
    final circlePaint = Paint()..shader = gradient;
    canvas.drawCircle(center, radius - 6, circlePaint);

    // Bordure blanche
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius - 6, borderPaint);

    // Texte du compte
    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: size * 0.35,
      fontWeight: FontWeight.w900,
    );
    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.center);
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('$count');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(
      paragraph,
      Offset(0, center.dy - paragraph.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(markerSize.width.toInt(), markerSize.height.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final bmp = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());

    _cache[key] = bmp;
    return bmp;
  }

  /// Dessine la forme de pin (goutte) avec dégradé
  static void _drawPinShape(Canvas canvas, ui.Size size, List<Color> colors) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final radius = size.width * 0.35;

    // Ombre portée
    final shadowPath = Path();
    shadowPath.addOval(Rect.fromCircle(center: center, radius: radius));
    shadowPath.moveTo(center.dx, center.dy + radius);
    shadowPath.lineTo(center.dx, size.height - 10);
    shadowPath.close();

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(shadowPath, shadowPaint);

    // Chemin du pin
    final path = Path();
    path.addOval(Rect.fromCircle(center: center, radius: radius));
    path.moveTo(center.dx, center.dy + radius);
    path.lineTo(center.dx, size.height - 5);
    path.close();

    // Dégradé
    final gradient = ui.Gradient.linear(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      colors,
    );

    final paint = Paint()..shader = gradient;
    canvas.drawPath(path, paint);

    // Bordure blanche
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawPath(path, borderPaint);
  }

  /// Dessine les étoiles pour la note
  static void _drawStars(Canvas canvas, ui.Size size, double rating) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final starSize = size.width * 0.12;
    final numStars = rating.round().clamp(0, 5);

    for (int i = 0; i < numStars; i++) {
      final x = center.dx - (starSize * 2) + (i * starSize * 0.9);
      final y = center.dy + 3;
      _drawStar(canvas, Offset(x, y), starSize * 0.5, Colors.yellow);
    }
  }

  /// Dessine une étoile
  static void _drawStar(Canvas canvas, Offset center, double size, Color color) {
    final path = Path();
    final angle = 2 * 3.14159 / 5;

    for (int i = 0; i < 5; i++) {
      final outer = Offset(
        center.dx + size * 0.5 * (i == 0 ? 0 : -1) * 0.5,
        center.dy - size * 0.5,
      );
      final rotated = _rotatePoint(outer, center, angle * i);

      if (i == 0) {
        path.moveTo(rotated.dx, rotated.dy);
      } else {
        path.lineTo(rotated.dx, rotated.dy);
      }

      final inner = Offset(
        center.dx + size * 0.2 * (i == 0 ? 0 : -1) * 0.5,
        center.dy - size * 0.2,
      );
      final rotatedInner = _rotatePoint(inner, center, angle * i + angle / 2);
      path.lineTo(rotatedInner.dx, rotatedInner.dy);
    }
    path.close();

    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);

    // Contour or pour faire ressortir
    final borderPaint = Paint()
      ..color = Colors.orange.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, borderPaint);
  }

  /// Dessine le badge de difficulté
  static void _drawDifficultyBadge(Canvas canvas, ui.Size size, int difficulty) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final radius = size.width * 0.35;
    final badgeCenter = Offset(center.dx + radius - 12, center.dy - radius + 12);
    final badgeRadius = 16.0;

    // Cercle blanc de fond
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(badgeCenter, badgeRadius, bgPaint);

    // Cercle coloré selon difficulté
    final difficultyColor = _getDifficultyColor(difficulty);
    final difficultyPaint = Paint()..color = difficultyColor;
    canvas.drawCircle(badgeCenter, badgeRadius - 2, difficultyPaint);

    // Texte de difficulté
    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w900,
    );
    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.center);
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('$difficulty');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: badgeRadius * 2));
    canvas.drawParagraph(
      paragraph,
      Offset(badgeCenter.dx - badgeRadius, badgeCenter.dy - paragraph.height / 2),
    );
  }

  /// Obtient les couleurs de dégradé selon la difficulté
  static List<Color> _getGradientForDifficulty(int difficulty) {
    switch (difficulty) {
      case 1:
        return [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]; // Vert
      case 2:
        return [const Color(0xFFFF9800), const Color(0xFFE65100)]; // Orange
      case 3:
        return [const Color(0xFFF44336), const Color(0xFFC62828)]; // Rouge
      default:
        return [const Color(0xFF9E9E9E), const Color(0xFF616161)]; // Gris
    }
  }

  /// Obtient la couleur selon la difficulté
  static Color _getDifficultyColor(int difficulty) {
    switch (difficulty) {
      case 1:
        return const Color(0xFF4CAF50); // Vert
      case 2:
        return const Color(0xFFFF9800); // Orange
      case 3:
        return const Color(0xFFF44336); // Rouge
      default:
        return const Color(0xFF9E9E9E); // Gris
    }
  }

  /// Rotation d'un point autour d'un centre
  static Offset _rotatePoint(Offset point, Offset center, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );
  }

  /// Efface le cache
  static void clearCache() {
    _cache.clear();
  }
}
