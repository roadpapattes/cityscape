// lib/features/profile/profile_page.dart

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/preferences_service.dart';
import '../../services/version_check_service.dart';
import '../../models/user_preferences.dart';
import 'personal_info_page.dart';
import 'change_password_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = AuthService.instance;
  final _prefs = PreferencesService.instance;

  bool _loading = true;
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    setState(() => _loading = true);
    try {
      final user = _auth.meNotifier.value;
      setState(() {
        _username = user?.username ?? 'Utilisateur';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _auth.logout();
      if (mounted) {
        Navigator.of(context).pop(); // Retour à l'écran précédent
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Déconnecté avec succès')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Header avec avatar
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  child: Text(
                    _username?.substring(0, 1).toUpperCase() ?? '?',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _username ?? 'Utilisateur',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Section Style d'affichage
          _buildSection(
            'Style d\'affichage',
            [
              _buildStyleSelector(),
            ],
          ),

          const Divider(),

          // Section Compte
          _buildSection(
            'Compte',
            [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Informations personnelles'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PersonalInfoPage(),
                    ),
                  );
                  if (result == true && mounted) {
                    _loadUserInfo(); // Recharger les infos après modification
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Changer le mot de passe'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangePasswordPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const Divider(),

          // Section À propos
          _buildSection(
            'À propos',
            [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Version de l\'application'),
                subtitle: Text(VersionCheckService.currentVersion),
              ),
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Aide et support'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Ouvrir page d'aide
                },
              ),
            ],
          ),

          const Divider(),

          // Bouton de déconnexion
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildStyleSelector() {
    final currentStyle = _prefs.currentPreferences.listCardStyle;

    return Column(
      children: [
        for (final style in ListCardStyle.values)
          RadioListTile<ListCardStyle>(
            value: style,
            groupValue: currentStyle,
            title: Text(UserPreferences(listCardStyle: style).getStyleDisplayName()),
            subtitle: Text(
              UserPreferences(listCardStyle: style).getStyleDescription(),
              style: const TextStyle(fontSize: 12),
            ),
            onChanged: (value) async {
              if (value != null) {
                await _prefs.updateListCardStyle(value);
                setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Style mis à jour !'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              }
            },
          ),
      ],
    );
  }
}
