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
  /// Ordre: Itinéraire -> Commentaires -> Signaler -> Démarrer
  void showEscapeDetailsTargets(
    BuildContext context, {
    required GlobalKey itineraryKey,
    required GlobalKey commentsKey,
    required GlobalKey reportKey,
    required GlobalKey startKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.escapeDetails) return;

    final targets = <TargetFocus>[
      // Étape 3.1: Bouton Itinéraire
      _createTarget(
        key: itineraryKey,
        content: TutorialContents.itineraryButton,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 3.2: Section Commentaires
      _createTarget(
        key: commentsKey,
        content: TutorialContents.commentsSection,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 3.3: Bouton Signaler
      _createTarget(
        key: reportKey,
        content: TutorialContents.reportButton,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      // Étape 3.4: Bouton Démarrer
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
        radius: 12,
        paddingFocus: 12,
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
    bool isLoggedIn = true,
    bool isAdmin = false,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.creatorPage) return;

    // Position juste au-dessus du bouton "Passer" en bas à droite
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPosition = CustomTargetContentPosition(bottom: 80);

    final targets = <TargetFocus>[];

    // Si l'utilisateur est connecté, on montre les étapes normales
    if (isLoggedIn) {
      // Étape 4.1: Liste des créations (focus réduit)
      targets.add(_createTarget(
        key: listKey,
        content: TutorialContents.creatorList,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.custom,
        customPosition: bottomPosition,  // Juste au-dessus du bouton Passer
      ));
      // Étape 4.2: Bouton nouveau brouillon (seulement si pas admin)
      if (!isAdmin) {
        targets.add(_createTarget(
          key: createKey,
          content: TutorialContents.createButton,
          context: context,
          shape: ShapeLightFocus.RRect,
          contentAlign: ContentAlign.bottom,
        ));
      }
      // Étape 4.3: Bouton feedback
      targets.add(_createTarget(
        key: feedbackKey,
        content: TutorialContents.feedbackButton,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.top,
      ));
    }

    // Message de fin (toujours affiché) - clic n'importe où pour terminer
    final screenWidth = MediaQuery.of(context).size.width;
    targets.add(TargetFocus(
      identify: TutorialContents.tutorialComplete.title,
      targetPosition: TargetPosition(
        const Size(0, 0),
        Offset(screenWidth / 2, screenHeight * 0.3),
      ),
      shape: ShapeLightFocus.Circle,
      radius: 0,
      paddingFocus: 0,
      enableOverlayTab: true,  // Permet de cliquer n'importe où pour passer
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) => TutorialContents.tutorialComplete.build(context),
        ),
      ],
    ));

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
    double radius = 8,
    double paddingFocus = 8,
  }) {
    return TargetFocus(
      identify: content.title,
      keyTarget: key,
      shape: shape,
      radius: radius,
      paddingFocus: paddingFocus,
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
      alignSkip: Alignment.bottomCenter,
      paddingFocus: 10,
      onClickTarget: (target) {
        // Clic sur la cible - passe à l'étape suivante
      },
      onClickOverlay: (target) {
        // Clic sur l'overlay - passe aussi à l'étape suivante
        // Utile notamment pour le message de fin
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
