// lib/map/marker_icons.dart
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Couleurs
const kClusterBlue = Color(0xFF0D47A1);   // bleu foncé pour les clusters
const kEscapeGreen = Color(0xFF40826D);   // vert demandé pour les escapes
const kWhite = Colors.white;

/// Caches pour éviter de redessiner tout le temps
final Map<int, BitmapDescriptor> _clusterCache = {};
final Map<String, BitmapDescriptor> _ratingCache = {};

/// Dessine un marqueur circulaire rempli d’une couleur, avec un texte centré.
Future<BitmapDescriptor> _circleTextIcon({
  required String text,
  required Color fill,
  Color border = Colors.white,
  double size = 96,        // taille en px du canvas (sera downscalé par Google Maps)
  double borderWidth = 6,
  double fontSize = 44,
  FontWeight fontWeight = FontWeight.w700,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);
  final radius = (size / 2) - borderWidth;

  // Cercle plein
  final fillPaint = Paint()..color = fill;
  canvas.drawCircle(center, radius, fillPaint);

  // Bordure
  final strokePaint = Paint()
    ..color = border
    ..style = PaintingStyle.stroke
    ..strokeWidth = borderWidth;
  canvas.drawCircle(center, radius, strokePaint);

  // Texte
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: kWhite,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size);

  final textOffset = Offset(
    (size - textPainter.width) / 2,
    (size - textPainter.height) / 2,
  );
  textPainter.paint(canvas, textOffset);

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
}

/// Icône pour cluster : texte = nombre (ex: 12)
Future<BitmapDescriptor> clusterIcon(int count) async {
  // Option: bucketer (2 chiffres / 3 chiffres). Ici cache par valeur simple.
  if (_clusterCache.containsKey(count)) return _clusterCache[count]!;
  // Ajuster un peu la taille/typo selon la longueur
  final digits = count.toString().length;
  final size = digits >= 3 ? 110.0 : 96.0;
  final font = digits >= 3 ? 42.0 : 44.0;
  final icon = await _circleTextIcon(
    text: count.toString(),
    fill: kClusterBlue,
    size: size,
    fontSize: font,
  );
  _clusterCache[count] = icon;
  return icon;
}

/// Icône pour escape individuel : texte = note avec 1 décimale (ex: 4.2)
Future<BitmapDescriptor> ratingIcon(double? rating) async {
  final r = (rating ?? 0).clamp(0, 5);
  final label = r.toStringAsFixed(1);
  // cache clé par label
  final key = 'r:$label';
  if (_ratingCache.containsKey(key)) return _ratingCache[key]!;
  final icon = await _circleTextIcon(
    text: label,
    fill: kEscapeGreen,
    size: 90,
    fontSize: 40,
  );
  _ratingCache[key] = icon;
  return icon;
}
