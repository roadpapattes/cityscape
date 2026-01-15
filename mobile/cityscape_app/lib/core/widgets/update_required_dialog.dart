// lib/core/widgets/update_required_dialog.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredDialog extends StatelessWidget {
  final String message;

  const UpdateRequiredDialog({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Empêche de fermer la dialog avec le bouton retour
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: Theme.of(context).primaryColor,
              size: 32,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Mise à jour requise',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Veuillez mettre à jour l\'application pour continuer à l\'utiliser.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _openPlayStore(),
            icon: const Icon(Icons.download),
            label: const Text('Mettre à jour'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlayStore() async {
    // URL du Play Store pour l'app CityScape
    const packageName = 'com.roadpapattes.cityscape';
    final uri = Uri.parse('market://details?id=$packageName');
    final fallbackUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Si l'ouverture échoue, on ne fait rien (l'utilisateur reste bloqué sur la dialog)
      debugPrint('Erreur ouverture Play Store: $e');
    }
  }
}
