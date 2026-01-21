// lib/features/tutorial/tutorial_controller.dart

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../services/tutorial_service.dart';
import 'tutorial_content.dart';

/// Les différentes phases du tutoriel
enum TutorialPhase {
  mainHome,      // Phase 1: Navigation principale
  escapeList,    // Phase 2: Liste des escapes (clic sur une carte)
  escapeDetails, // Phase 3: Détails d'un escape
  sessionPlayer, // Phase 4: En jeu
  creatorPage,   // Phase 5: Mode créateur
  completed,     // Terminé
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
        _currentPhase = TutorialPhase.creatorPage;
        break;
      case TutorialPhase.sessionPlayer:
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

  /// Affiche les targets pour la phase MainHome
  void showMainHomeTargets(
    BuildContext context, {
    required GlobalKey listTabKey,
    required GlobalKey mapTabKey,
    required GlobalKey creatorTabKey,
    required GlobalKey profileKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.mainHome) return;

    final targets = <TargetFocus>[
      _createTarget(
        key: listTabKey,
        content: TutorialContents.listTab,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: mapTabKey,
        content: TutorialContents.mapTab,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: creatorTabKey,
        content: TutorialContents.creatorTab,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: profileKey,
        content: TutorialContents.profileButton,
        context: context,
        shape: ShapeLightFocus.Circle,
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      nextPhase();
      onFinish();
    });
  }

  /// Affiche le target pour la carte d'escape (Phase 2)
  void showEscapeCardTarget(
    BuildContext context, {
    required GlobalKey cardKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.escapeList) return;

    final targets = <TargetFocus>[
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
    required GlobalKey durationKey,
    required GlobalKey startKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.escapeDetails) return;

    final targets = <TargetFocus>[
      _createTarget(
        key: imageKey,
        content: TutorialContents.escapeImage,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: durationKey,
        content: TutorialContents.escapeDuration,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
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

  /// Affiche les targets pour la page de jeu (Phase 4)
  void showSessionPlayerTargets(
    BuildContext context, {
    required GlobalKey timerKey,
    required GlobalKey hintKey,
    required GlobalKey historyKey,
    required GlobalKey answerKey,
    required GlobalKey progressKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.sessionPlayer) return;

    final targets = <TargetFocus>[
      _createTarget(
        key: timerKey,
        content: TutorialContents.timer,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: hintKey,
        content: TutorialContents.hintButton,
        context: context,
        shape: ShapeLightFocus.Circle,
      ),
      _createTarget(
        key: historyKey,
        content: TutorialContents.historyButton,
        context: context,
        shape: ShapeLightFocus.Circle,
      ),
      _createTarget(
        key: answerKey,
        content: TutorialContents.answerZone,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
      _createTarget(
        key: progressKey,
        content: TutorialContents.progression,
        context: context,
        shape: ShapeLightFocus.RRect,
      ),
    ];

    _showTutorial(context, targets, onFinish: () {
      nextPhase();
      onFinish();
    });
  }

  /// Affiche les targets pour la page créateur (Phase 5)
  void showCreatorTargets(
    BuildContext context, {
    required GlobalKey listKey,
    required GlobalKey createKey,
    required VoidCallback onFinish,
  }) {
    if (!_isActive || _currentPhase != TutorialPhase.creatorPage) return;

    final targets = <TargetFocus>[
      _createTarget(
        key: listKey,
        content: TutorialContents.creatorList,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.top,  // Afficher au-dessus car la liste prend l'écran
      ),
      _createTarget(
        key: createKey,
        content: TutorialContents.createButton,
        context: context,
        shape: ShapeLightFocus.Circle,
        contentAlign: ContentAlign.bottom,  // Bouton en haut, donc contenu en dessous
      ),
      _createTarget(
        key: GlobalKey(), // Placeholder - on affiche juste le message final
        content: TutorialContents.tutorialComplete,
        context: context,
        shape: ShapeLightFocus.RRect,
        contentAlign: ContentAlign.custom,  // Centre de l'écran
        alignSkip: Alignment.center,
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
