// lib/features/home/main_home.dart

import 'package:flutter/material.dart';

// Import services
import '../../services/auth_service.dart';
import '../../services/api/api_service.dart';
import '../../services/game_timer_service.dart';

// Import models
import '../../models/user_me.dart';

// Import core constants
import '../../core/constants.dart';

// Import feature pages
import '../list/list_page.dart';
import '../map/map_page.dart';
import '../creator/creator_page.dart';
import '../auth/auth_page.dart';
import '../profile/profile_page.dart';

// Import core widgets
import '../../core/widgets/timer_badge.dart';
import '../../core/widgets/themed_app_bar.dart';
import '../../core/widgets/themed_bottom_nav.dart';

// Import services for preferences
import '../../services/preferences_service.dart';
import '../../models/user_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    AuthService.instance.loadFromPrefs();
    _prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    setState(() {}); // Rebuild when preferences change
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
      bottomNavigationBar: useThemedUI
          ? ThemedBottomNav(
              currentIndex: _tabIndex,
              onTap: (i) => setState(() => _tabIndex = i),
              style: style,
            )
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.list_alt), label: 'Liste'),
                NavigationDestination(
                    icon: Icon(Icons.map_outlined), label: 'Carte'),
                NavigationDestination(
                    icon: Icon(Icons.edit_note_outlined), label: 'Créateur'),
              ],
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
