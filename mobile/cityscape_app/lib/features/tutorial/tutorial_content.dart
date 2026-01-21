// lib/features/tutorial/tutorial_content.dart

import 'package:flutter/material.dart';

/// Contenu des différentes étapes du tutoriel
class TutorialContent {
  final String title;
  final String description;
  final IconData icon;

  const TutorialContent({
    required this.title,
    required this.description,
    required this.icon,
  });

  /// Construit le widget de contenu pour une bulle de tutoriel
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tapez pour continuer',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

/// Contenus prédéfinis pour chaque étape du tutoriel
class TutorialContents {
  // Phase 1: Navigation principale
  static const listTab = TutorialContent(
    title: 'Liste des Escapes',
    description: 'Découvrez tous les escape games disponibles dans votre région. Parcourez, filtrez et trouvez votre prochaine aventure !',
    icon: Icons.list_alt,
  );

  static const mapTab = TutorialContent(
    title: 'Carte Interactive',
    description: 'Visualisez les escapes proches de vous sur la carte. Trouvez facilement ceux à proximité !',
    icon: Icons.map,
  );

  static const creatorTab = TutorialContent(
    title: 'Mode Créateur',
    description: 'Créez vos propres escape games et partagez-les avec la communauté !',
    icon: Icons.edit_note,
  );

  static const profileButton = TutorialContent(
    title: 'Votre Profil',
    description: 'Accédez à votre profil, vos favoris et vos paramètres.',
    icon: Icons.account_circle,
  );

  // Phase 2: Exploration
  static const escapeCard = TutorialContent(
    title: 'Carte d\'Escape',
    description: 'Chaque carte représente un escape game. Cliquez dessus pour voir ses détails !',
    icon: Icons.games,
  );

  // Phase 3: Détails escape
  static const escapeImage = TutorialContent(
    title: 'Univers Unique',
    description: 'Chaque escape a son propre univers et son histoire. Plongez dans l\'aventure !',
    icon: Icons.image,
  );

  static const escapeDuration = TutorialContent(
    title: 'Durée & Difficulté',
    description: 'Consultez le temps estimé et le niveau de difficulté avant de vous lancer.',
    icon: Icons.timer,
  );

  static const startButton = TutorialContent(
    title: 'Démarrer l\'Aventure',
    description: 'Prêt ? Cliquez ici pour commencer votre escape game !',
    icon: Icons.play_arrow,
  );

  // Phase 4: En jeu
  static const timer = TutorialContent(
    title: 'Chronomètre',
    description: 'Votre temps de jeu est comptabilisé ici. Le temps continue même si vous quittez l\'app !',
    icon: Icons.access_time,
  );

  static const hintButton = TutorialContent(
    title: 'Indices',
    description: 'Besoin d\'aide ? Utilisez un indice, mais attention aux pénalités de temps !',
    icon: Icons.lightbulb_outline,
  );

  static const historyButton = TutorialContent(
    title: 'Historique',
    description: 'Consultez les étapes déjà complétées et revivez votre progression.',
    icon: Icons.history,
  );

  static const answerZone = TutorialContent(
    title: 'Zone de Réponse',
    description: 'Entrez votre réponse ici pour valider l\'étape et progresser.',
    icon: Icons.edit,
  );

  static const progression = TutorialContent(
    title: 'Progression',
    description: 'Suivez votre avancement dans l\'escape. Chaque étape vous rapproche de la victoire !',
    icon: Icons.linear_scale,
  );

  // Phase 5: Mode Créateur
  static const creatorList = TutorialContent(
    title: 'Mes Créations',
    description: 'Retrouvez tous vos escape games créés ici. Modifiez-les ou suivez leur popularité !',
    icon: Icons.folder,
  );

  static const createButton = TutorialContent(
    title: 'Créer un Escape',
    description: 'Commencez à créer votre propre escape game et partagez-le !',
    icon: Icons.add_circle,
  );

  // Fin
  static const tutorialComplete = TutorialContent(
    title: 'Vous êtes prêt !',
    description: 'Bonne exploration et amusez-vous bien ! Vous pouvez revoir ce tutoriel depuis votre profil.',
    icon: Icons.celebration,
  );
}
