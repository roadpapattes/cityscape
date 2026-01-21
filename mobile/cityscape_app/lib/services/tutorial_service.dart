// lib/services/tutorial_service.dart

import 'preferences_service.dart';

/// Service pour gérer l'état du tutoriel (complété ou non)
class TutorialService {
  static final TutorialService instance = TutorialService._();
  TutorialService._();

  /// Vérifie si le tutoriel a été complété
  bool get hasCompletedTutorial =>
      PreferencesService.instance.currentPreferences.tutorialCompleted;

  /// Marque le tutoriel comme complété
  Future<void> markTutorialCompleted() async {
    await PreferencesService.instance.setTutorialCompleted(true);
  }

  /// Réinitialise le tutoriel (pour le relancer)
  Future<void> resetTutorial() async {
    await PreferencesService.instance.setTutorialCompleted(false);
  }
}
