// lib/features/tutorial/tutorial_controller.dart

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../services/tutorial_service.dart';
import 'tutorial_content.dart';

/// Les différentes phases du tutoriel
enum TutorialPhase {
  mainHome,        // Phase 1: Navigation principale
  escapeList,      // Phase 2: Liste des escapes (clic sur une carte)
  escapeDetails,   // Phase 3: Détails d'un escape
  creatorTabFocus, // Phase 3.5: Focus sur le bouton Créateur (après détails)
  creatorPage,     // Phase 4: Mode créateur
  completed,       // Terminé
}

/// Controller global pour gérer le tutoriel multi-pages
class TutorialController extends ChangeNotifier {
  static final TutorialController instance = TutorialController._();
  TutorialController._();

  bool _isActive = false;
  TutorialPhase _currentPhase = TutorialPhase.mainHome;
  TutorialCoachMark? _tutorialCoachMark;

  /// Indique si le tutoriel est actuellement actif
  bool get isActive => _isActive;

  /// Phase actuelle du tutoriel
  TutorialPhase get currentPhase => _currentPhase;

  /// Démarre le tutoriel depuis le début (appelé après l'intro MainHome)
  void startTutorial() {
    _isActive = true;
    _currentPhase = TutorialPhase.escapeList;  // On commence à escapeList car MainHome a déjà fait l'intro
    notifyListeners();
  }

  /// Arrête le tutoriel
  Future<void> stopTutorial({bool markCompleted = false}) async {
    _isActive = false;
    _currentPhase = TutorialPhase.completed;
    _tutorialCoachMark?.finish();
    _tutorialCoachMark = null;

    if (markCompleted) {
      await TutorialService.instance.markTutorialCompleted();
    }

    notifyListeners();
  }

  /// Passe à la phase suivante
  void nextPhase() {
    switch (_currentPhase) {
      case TutorialPhase.mainHome:
        _currentPhase = TutorialPhase.escapeList;
        break;
      case TutorialPhase.escapeList:
        _currentPhase = TutorialPhase.escapeDetails;
        break;
      case TutorialPhase.escapeDetails:
        _currentPhase = TutorialPhase.creatorTabFocus;
        break;
      case TutorialPhase.creatorTabFocus:
        _currentPhase = TutorialPhase.creatorPage;
        break;
      case TutorialPhase.creatorPage:
        _currentPhase = TutorialPhase.completed;
        stopTutorial(markCompleted: true);
        break;
      case TutorialPhase.completed:
        break;
    }
    notifyListeners();
  }

  /// Affiche les targets pour la page liste (Phase 2)
  void showEscapeListTargets(
    BuildContext context, {
    required GlobalKey searchFilterKey,
    required GlobalKey cardKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.escapeList) return;

    final targets = <TargetFocus>[
      // Étape 2.1: Zone de recherche et tri
      _createTarget(
        key: searchFilterKey,
        content: TutorialContents.searchAndFilter,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 2.2: Carte d'escape
      _createTarget(
        key: cardKey,
        content: TutorialContents.escapeCard,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      nextPhase();
      onFinish();
    });
  }

  /// Affiche les targets pour la page de détails (Phase 3)
  void showEscapeDetailsTargets(
    BuildContext context, {
    required GlobalKey imageKey,
    required GlobalKey itineraryKey,
    required GlobalKey startKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.escapeDetails) return;

    final targets = <TargetFocus>[
      // Étape 3.1: Image
      _createTarget(
        key: imageKey,
        content: TutorialContents.escapeImage,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 3.2: Bouton Itinéraire
      _createTarget(
        key: itineraryKey,
        content: TutorialContents.itineraryButton,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 3.3: Bouton Démarrer
      _createTarget(
        key: startKey,
        content: TutorialContents.startButton,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      nextPhase();
      onFinish();
    });
  }

  /// Affiche le target pour le bouton créateur (après Phase 3, avant Phase 4)
  void showCreatorTabTarget(
    BuildContext context, {
    required GlobalKey creatorTabKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.creatorTabFocus) return;

    final targets = <TargetFocus>[
      _createTarget(
        key: creatorTabKey,
        content: TutorialContents.creatorTab,
        context: context,
        shape: ShapeLightFocus.Circle,
        contentAlign: ContentAlign.top,
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      nextPhase();
      onFinish();
    });
  }

  /// Affiche les targets pour la page créateur (Phase 4 finale)
  void showCreatorTargets(
    BuildContext context, {
    required GlobalKey listKey,
    required GlobalKey createKey,
    required GlobalKey feedbackKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.creatorPage) return;

    // Position juste au-dessus du bouton "Passer" en bas à droite
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPosition = CustomTargetContentPosition(bottom: 80);

    final targets = <TargetFocus>[
      // Étape 4.1: Liste des créations (focus réduit)
      _createTarget(
        key: listKey,
        content: TutorialContents.creatorList,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.custom,
        customPosition: bottomPosition,  // Juste au-dessus du bouton Passer
      ),
      // Étape 4.2: Bouton nouveau brouillon
      _createTarget(
        key: createKey,
        content: TutorialContents.createButton,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.bottom,
      ),
      // Étape 4.3: Bouton feedback
      _createTarget(
        key: feedbackKey,
        content: TutorialContents.feedbackButton,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.top,
      ),
      // Message de fin
      _createTarget(
        key: GlobalKey(), // Placeholder - on affiche juste le message final
        content: TutorialContents.tutorialComplete,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.custom,
        customPosition: CustomTargetContentPosition(top: screenHeight * 0.3),
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      stopTutorial(markCompleted: true);
      onFinish();
    });
  }

  /// Crée un TargetFocus avec le contenu personnalisé
  TargetFocus _createTarget({
    required GlobalKey key,
    required TutorialContent content,
    required BuildContext context,
    ShapeLightFocus shape = ShapeLightFocus.RRect,
    Alignment alignSkip = Alignment.topRight,
    ContentAlign contentAlign = ContentAlign.bottom,
    CustomTargetContentPosition? customPosition,
  }) {
    return TargetFocus(
      identify: content.title,
      keyTarget: key,
      shape: shape,
      radius: 8,
      paddingFocus: 8,
      contents: [
        TargetContent(
          align: contentAlign,
          customPosition: customPosition,
          builder: (context, controller) => content.build(context),
        ),
      ],
    );
  }

  /// Lance l'affichage du tutoriel
  void _showTutorial(
    BuildContext context,
    List<TargetFocus> targets, {
    required VoidCallback onFinish,
  }) {
    _tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      hideSkip: false,
      textSkip: 'Passer',
      paddingFocus: 10,
      onClickTarget: (target) {
        // Clic sur la cible
      },
      onClickOverlay: (target) {
        // Clic sur l'overlay (pour passer à la suite)
      },
      onSkip: () {
        stopTutorial(markCompleted: true);
        return true;
      },
      onFinish: onFinish,
    );

    _tutorialCoachMark!.show(context: context);
  }
}
