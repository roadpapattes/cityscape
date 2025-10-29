import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const kClusterBlue = Color(0xFF0D47A1); // cluster = bleu foncé
const kEscapeGreen = Color(0xFF40826D); // escape = vert demandé

final Map<int, BitmapDescriptor> _clusterCache = {};
final Map<String, BitmapDescriptor> _ratingCache = {};

Future<BitmapDescriptor> _circleTextIcon({
  required String text,
  required Color fill,
  Color border = Colors.white,
  double size = 96,
  double borderWidth = 6,
  double fontSize = 44,
  FontWeight fontWeight = FontWeight.w700,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);
  final radius = (size / 2) - borderWidth;

  canvas.drawCircle(center, radius, Paint()..color = fill);
  final stroke = Paint()
    ..color = border
    ..style = PaintingStyle.stroke
    ..strokeWidth = borderWidth;
  canvas.drawCircle(center, radius, stroke);

  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: fontWeight, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size);
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

  final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
}

Future<BitmapDescriptor> clusterIcon(int count) async {
  if (_clusterCache.containsKey(count)) return _clusterCache[count]!;
  final digits = count.toString().length;
  final size = digits >= 3 ? 110.0 : 96.0;
  final font = digits >= 3 ? 42.0 : 44.0;
  final icon = await _circleTextIcon(text: count.toString(), fill: kClusterBlue, size: size, fontSize: font);
  _clusterCache[count] = icon;
  return icon;
}

Future<BitmapDescriptor> ratingIcon(double? rating) async {
  final r = (rating ?? 0).clamp(0, 5);
  final label = r.toStringAsFixed(1);
  final key = 'r:$label';
  if (_ratingCache.containsKey(key)) return _ratingCache[key]!;
  final icon = await _circleTextIcon(text: label, fill: kEscapeGreen, size: 90, fontSize: 40);
  _ratingCache[key] = icon;
  return icon;
}
