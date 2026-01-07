// lib/core/utils/image_utils.dart

import 'package:flutter/material.dart';

/// Transforme les URL d'images backend en URL valides côté app.
/// - remplace 10.0.2.2/localhost/127.0.0.1 par l'hôte/port de baseUrl
/// - préfixe les chemins relatifs avec baseUrl
/// - renvoie toujours une String non nulle
String normalizeImageUrl(String? url, String baseUrl) {
  if (url == null || url.isEmpty) return '';
  try {
    final base = Uri.parse(baseUrl);
    final parsed = Uri.parse(url);

    // Cas 1: URL absolue
    if (parsed.hasScheme) {
      // Si c'est 10.0.2.2 / localhost / 127.0.0.1 => remapper vers host/port de baseUrl
      if (parsed.host == '10.0.2.2' || parsed.host == 'localhost' || parsed.host == '127.0.0.1') {
        final remapped = parsed.replace(
          scheme: base.scheme,
          host: base.host,
          port: base.hasPort ? base.port : null,
        );
        return remapped.toString();
      }
      return url; // autre domaine déjà correct
    }

    // Cas 2: chemin relatif (ex: /media/...)
    final resolved = base.resolve(url.startsWith('/') ? url.substring(1) : url);
    return resolved.toString();
  } catch (_) {
    // En cas d'URL mal formée, renvoyer tout de même quelque chose d'affichable
    return url ?? '';
  }
}

/// Miniature responsive qui conserve les proportions.
/// - Encapsulée dans une boîte max 180 px de haut.
/// - Si url vide → placeholder.
Widget imageThumb(String? url) {
  final u = url?.trim();
  final has = (u != null && u.isNotEmpty);
  return Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 180),
    decoration: BoxDecoration(
      color: has ? const Color(0xFFF7F7F7) : const Color(0xFFF3F3F3),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x11000000)),
    ),
    alignment: Alignment.center,
    child: has
        ? FittedBox(
            fit: BoxFit.contain,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                u!,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Impossible de charger l\'image'),
                ),
              ),
            ),
          )
        : const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Aucune image'),
          ),
  );
}
