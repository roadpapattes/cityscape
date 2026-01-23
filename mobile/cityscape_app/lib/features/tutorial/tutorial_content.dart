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

  /// Construit le widget avec un bouton "Terminer" pour la dernière étape
  Widget buildWithButton(BuildContext context, {required VoidCallback onTerminate}) {
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTerminate,
              icon: const Icon(Icons.check_circle),
              label: const Text(
                'Terminer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
  static const navigation = TutorialContent(
    title: 'Navigation',
    description: 'Naviguez dans les différents menus pour trouver un escape game ou en créer un vous même !',
    icon: Icons.menu,
  );

  static const profileButton = TutorialContent(
    title: 'Votre profil',
    description: 'Accédez à votre profil, changez de thème ou modifiez vos informations personnelles',
    icon: Icons.account_circle,
  );

  static const listTab = TutorialContent(
    title: 'Liste des Escape Game',
    description: 'Accédez à la liste complète des Escape Game',
    icon: Icons.list_alt,
  );

  // Phase 2: Liste des escapes
  static const searchAndFilter = TutorialContent(
    title: 'Triez, recherchez',
    description: 'Trouvez les Escape Game les mieux notés ou ceux dans votre ville. Ajoutez des favoris pour les retrouver facilement plus tard.',
    icon: Icons.search,
  );

  static const escapeCard = TutorialContent(
    title: 'L\'Escape Game en un coup d\'oeil',
    description: 'Retrouvez ici le titre de l\'Escape Game, sa durée estimée ou encore la note moyenne attribuée par les joueurs. Cliquez dessus pour voir les détails et lancer une partie !',
    icon: Icons.games,
  );

  // Phase 3: Détails escape
  static const itineraryButton = TutorialContent(
    title: 'Rejoignez le point de départ',
    description: 'Suivez l\'itinéraire proposé pour vous rendre au point de départ et démarrer votre aventure',
    icon: Icons.directions_walk,
  );

  static const commentsSection = TutorialContent(
    title: 'Commentaires',
    description: 'Retrouvez les avis des joueurs pour choisir les Escape Game selon vos affinités',
    icon: Icons.comment,
  );

  static const reportButton = TutorialContent(
    title: 'Vigilants ensemble',
    description: 'Signalez les Escape Game qui contiendraient des informations inconvenantes',
    icon: Icons.flag,
  );

  static const startButton = TutorialContent(
    title: 'Démarrez l\'aventure',
    description: 'Prêt ? Cliquez ici pour commencer votre escape game',
    icon: Icons.play_arrow,
  );

  static const creatorTab = TutorialContent(
    title: 'Vous préférez créer votre Escape Game ?',
    description: 'Rendez-vous dans le menu créateur, concevez votre propre Escape Game et soumettez le pour modération.',
    icon: Icons.edit_note,
  );

  // Phase 4: Mode Créateur
  static const creatorList = TutorialContent(
    title: 'Vos créations',
    description: 'Retrouvez ici les Escape Game que vous avez créé, modifiez les puis soumettez les',
    icon: Icons.folder,
  );

  static const createButton = TutorialContent(
    title: 'Créer un Escape Game',
    description: 'Commencez à créer votre propre Escape Game et partagez le juste avec vos amis ou avec le monde entier !',
    icon: Icons.add_circle,
  );

  static const feedbackButton = TutorialContent(
    title: 'Partagez vos suggestions',
    description: 'Aidez-nous à améliorer l\'application en envoyant vos suggestions ou les bugs que vous pourriez rencontrer',
    icon: Icons.bug_report,
  );

  // Fin
  static const tutorialComplete = TutorialContent(
    title: 'Vous êtes prêt !',
    description: 'Bonne exploration et amusez-vous bien !\nVous pouvez revoir ce tutoriel depuis votre profil.',
    icon: Icons.celebration,
  );
}
