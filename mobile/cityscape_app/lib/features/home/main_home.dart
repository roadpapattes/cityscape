// lib/features/home/main_home.dart

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

// Import services
import '../../services/auth_service.dart';
import '../../services/api/api_service.dart';
import '../../services/tutorial_service.dart';
import '../../services/preferences_service.dart';

// Import feature pages
import '../list/list_page.dart';
import '../map/map_page.dart';
import '../creator/creator_page.dart';
import '../auth/auth_page.dart';
import '../profile/profile_page.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_content.dart';

// Import core widgets
import '../../core/widgets/themed_app_bar.dart';
import '../../core/widgets/themed_bottom_nav.dart';

/* ============================
   MAIN HOME SCREEN
   Bottom navigation with 3 tabs: List, Map, Creator
============================ */

class MainHome extends StatefulWidget {
  const MainHome({super.key});
  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  int _tabIndex = 1;
  final _prefs = PreferencesService.instance;

  // GlobalKeys pour le tutoriel Phase 1 et Phase 3.5
  final _bottomNavKey = GlobalKey();
  final _profileButtonKey = GlobalKey();
  final _listTabKey = GlobalKey();
  final _creatorTabKey = GlobalKey();
  bool _creatorTabTutorialShown = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.loadFromPrefs();
    _prefs.addListener(_onPrefsChanged);
    TutorialController.instance.addListener(_onTutorialPhaseChanged);

    // Vérifier si on doit lancer le tutoriel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartTutorial();
    });
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    TutorialController.instance.removeListener(_onTutorialPhaseChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    setState(() {}); // Rebuild when preferences change
  }

  /// Détecte les changements de phase du tutoriel pour naviguer automatiquement
  void _onTutorialPhaseChanged() {
    if (!mounted) return;
    final phase = TutorialController.instance.currentPhase;

    // Phase 3.5: Focus sur le bouton Créateur
    if (phase == TutorialPhase.creatorTabFocus && !_creatorTabTutorialShown) {
      _creatorTabTutorialShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        TutorialController.instance.showCreatorTabTarget(
          context,
          creatorTabKey: _creatorTabKey,
          onFinish: () {
            // Aller à l'onglet Créateur
            setState(() => _tabIndex = 2);
          },
        );
      });
    }
    // Phase 4: Page Créateur
    else if (phase == TutorialPhase.creatorPage && _tabIndex != 2) {
      // Aller automatiquement à l'onglet Créateur
      setState(() => _tabIndex = 2);
    }
  }

  /// Vérifie si le tutoriel doit être lancé
  void _checkAndStartTutorial() {
    if (!TutorialService.instance.hasCompletedTutorial) {
      _startTutorial();
    }
  }

  /// Lance le tutoriel interactif
  void _startTutorial() {
    final targets = <TargetFocus>[
      // Étape 1.1: Bottom Navigation - Vue d'ensemble
      TargetFocus(
        identify: 'bottomNav',
        keyTarget: _bottomNavKey,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        paddingFocus: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => TutorialContents.navigation.build(context),
          ),
        ],
      ),
      // Étape 1.2: Profil button
      TargetFocus(
        identify: 'profile',
        keyTarget: _profileButtonKey,
        shape: ShapeLightFocus.Circle,
        radius: 8,
        paddingFocus: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => TutorialContents.profileButton.build(context),
          ),
        ],
      ),
      // Étape 1.3: Bouton Liste (ciblage en cercle)
      TargetFocus(
        identify: 'listTab',
        keyTarget: _listTabKey,
        shape: ShapeLightFocus.Circle,
        radius: 8,
        paddingFocus: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => TutorialContents.listTab.build(context),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      hideSkip: false,
      textSkip: 'Passer',
      paddingFocus: 10,
      onClickTarget: (target) {
        // Si l'utilisateur clique sur le bouton Liste, on navigue vers la liste
        if (target.identify == 'listTab') {
          setState(() => _tabIndex = 0);
        }
      },
      onSkip: () {
        TutorialService.instance.markTutorialCompleted();
        return true;
      },
      onFinish: () {
        // Aller à l'onglet Liste pour la suite du tutoriel
        setState(() => _tabIndex = 0);
        TutorialController.instance.startTutorial();
      },
    ).show(context: context);
  }

  /// Relance le tutoriel (appelé depuis ProfilePage)
  void restartTutorial() {
    _startTutorial();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const ListPage(), const MapPage(), const CreatorPage()];
    final style = _prefs.currentPreferences.listCardStyle;
    final useThemedUI = _tabIndex <= 1; // Liste (0) et Carte (1)

    // Actions communes pour l'AppBar
    final appBarActions = [
      ValueListenableBuilder<String?>(
        valueListenable: AuthService.instance.tokenNotifier,
        builder: (context, token, _) {
          if (token == null) {
            return IconButton(
              tooltip: 'Se connecter',
              icon: const Icon(Icons.login),
              onPressed: () => _openAuthDialog(context),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: _profileButtonKey,
                tooltip: 'Profil',
                icon: const Icon(Icons.account_circle),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfilePage(),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Se déconnecter',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  await AuthService.instance.logout();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Déconnecté')),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    ];

    return Scaffold(
      appBar: useThemedUI
          ? ThemedAppBar(
              title: _getPageTitle(),
              style: style,
              actions: appBarActions,
            )
          : AppBar(
              title: const _TitleWithUser(),
              actions: appBarActions,
            ),
      body: Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: AuthService.instance.tokenNotifier,
            builder: (context, token, _) {
              if (token != null) return const SizedBox.shrink();
              return MaterialBanner(
                content: const Text("Vous n'êtes pas connecté."),
                leading: const Icon(Icons.person_outline),
                actions: [
                  TextButton(
                    onPressed: () => _openAuthDialog(context),
                    child: const Text('Se connecter'),
                  ),
                ],
              );
            },
          ),
          Expanded(child: pages[_tabIndex]),
        ],
      ),
      bottomNavigationBar: Container(
        key: _bottomNavKey,
        child: useThemedUI
            ? ThemedBottomNav(
                currentIndex: _tabIndex,
                onTap: (i) => setState(() => _tabIndex = i),
                style: style,
                listTabKey: _listTabKey,
                creatorTabKey: _creatorTabKey,
              )
            : NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: (i) => setState(() => _tabIndex = i),
                destinations: [
                  NavigationDestination(
                      key: _listTabKey,
                      icon: const Icon(Icons.list_alt), label: 'Liste'),
                  const NavigationDestination(
                      icon: Icon(Icons.map_outlined), label: 'Carte'),
                  NavigationDestination(
                      key: _creatorTabKey,
                      icon: const Icon(Icons.edit_note_outlined), label: 'Créateur'),
                ],
              ),
      ),
    );
  }

  void _openAuthDialog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  String _getPageTitle() {
    switch (_tabIndex) {
      case 0:
        return 'Liste des Escapes';
      case 1:
        return 'Carte';
      default:
        return 'CityScape';
    }
  }
}

/* ============================
   TITLE WITH USER WIDGET
   Displays "CityScape" or "CityScape | username" in app bar
============================ */

class _TitleWithUser extends StatefulWidget {
  const _TitleWithUser();
  @override
  State<_TitleWithUser> createState() => _TitleWithUserState();
}

class _TitleWithUserState extends State<_TitleWithUser> {
  String? _username;

  @override
  void initState() {
    super.initState();
    AuthService.instance.tokenNotifier.addListener(_onAuthChange);
    _refreshUsername();
  }

  @override
  void dispose() {
    AuthService.instance.tokenNotifier.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() => _refreshUsername();

  Future<void> _refreshUsername() async {
    final token = AuthService.instance.tokenNotifier.value;
    if (token == null) {
      setState(() => _username = null);
      return;
    }
    try {
      final me = await ApiService.instance.fetchMe();
      setState(() {
        _username = (me?['username'] as String?) ?? (me?['user'] as String?);
      });
    } catch (_) {
      setState(() => _username = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _username == null ? 'CityScape' : 'CityScape | $_username';
    return Text(text, overflow: TextOverflow.ellipsis, maxLines: 1);
  }
}

/* ============================
   AUTH DIALOG - REMOVED
   Replaced by AuthPage (lib/features/auth/auth_page.dart)
============================ */
