// lib/features/welcome/welcome_screen.dart

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/tutorial_service.dart';
import '../auth/terms_page.dart';
import '../home/main_home.dart';

/* ============================
   WELCOME SCREEN
   First screen for new users without an account
   Offers Login, Register, or Google Sign-In
============================ */

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _googleBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.08),

                // --- Illustration & Branding ---
                _buildIllustration(theme),

                SizedBox(height: size.height * 0.04),

                // --- Welcome Text ---
                Text(
                  'Bienvenue sur CityScape',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Explorez votre ville autrement avec des escape games en plein air !',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: size.height * 0.06),

                // --- Action Buttons ---
                _buildActionButtons(context, theme),

                const SizedBox(height: 24),

                // --- Terms & Privacy ---
                Text(
                  'En continuant, vous acceptez nos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
                  ),
                  child: Text(
                    'Conditions d\'utilisation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIllustration(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        kLogoAsset,
        width: 180,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.location_city,
            size: 100,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Se connecter (Login) ---
        FilledButton.icon(
          onPressed: () => _navigateToAuth(context, isLogin: true),
          icon: const Icon(Icons.login),
          label: const Text(
            'Se connecter',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // --- Créer un compte (Register) ---
        OutlinedButton.icon(
          onPressed: () => _navigateToAuth(context, isLogin: false),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text(
            'Créer un compte',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: theme.colorScheme.primary),
          ),
        ),

        const SizedBox(height: 20),

        // --- Divider OR ---
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OU',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),

        const SizedBox(height: 20),

        // --- Google Sign-In ---
        OutlinedButton.icon(
          onPressed: _googleBusy ? null : _handleGoogleSignIn,
          icon: _googleBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Image.network(
                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                  height: 24,
                  width: 24,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.g_mobiledata, size: 24),
                ),
          label: Text(
            _googleBusy ? 'Connexion...' : 'Continuer avec Google',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: Colors.grey[300]!),
          ),
        ),
      ],
    );
  }

  /// Navigate to AuthPage with specific tab (login or register)
  void _navigateToAuth(BuildContext context, {required bool isLogin}) async {
    // Navigate to auth and wait for result
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthPageWithCallback(
          initialTab: isLogin ? 0 : 1,
          onAuthSuccess: (bool isNewUser) {
            _onAuthSuccess(context, isNewUser);
          },
        ),
      ),
    );

    // Check if user got authenticated while in AuthPage
    if (!mounted) return;
    if (AuthService.instance.tokenNotifier.value != null) {
      // User authenticated - check if new user from AuthService
      final isNewUser = AuthService.instance.lastLoginWasNewUser;
      _onAuthSuccess(context, isNewUser);
    }
  }

  /// Handle Google Sign-In from WelcomeScreen
  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleBusy = true);

    try {
      final isNewUser = await AuthService.instance.signInWithGoogle();

      if (!mounted) return;
      _onAuthSuccess(context, isNewUser);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// Called after successful authentication
  void _onAuthSuccess(BuildContext context, bool isNewUser) {
    if (!mounted) return;

    // Navigate to MainHome, replacing the entire navigation stack
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainHome()),
      (route) => false,
    );

    // If new user, reset tutorial and it will start automatically
    if (isNewUser) {
      TutorialService.instance.resetTutorial();
    }
  }
}

/* ============================
   AUTH PAGE WITH CALLBACK
   Wrapper around AuthPage that notifies on success
============================ */

class AuthPageWithCallback extends StatefulWidget {
  final int initialTab;
  final void Function(bool isNewUser) onAuthSuccess;

  const AuthPageWithCallback({
    super.key,
    this.initialTab = 0,
    required this.onAuthSuccess,
  });

  @override
  State<AuthPageWithCallback> createState() => _AuthPageWithCallbackState();
}

class _AuthPageWithCallbackState extends State<AuthPageWithCallback>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authentification'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Logo section
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.location_city,
                  size: 60,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'CityScape',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[700],
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Connexion'),
                Tab(text: 'Inscription'),
              ],
            ),
          ),

          // Google Sign-In
          Padding(
            padding: const EdgeInsets.all(24),
            child: _GoogleSignInButtonWithCallback(
              onSuccess: widget.onAuthSuccess,
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LoginFormWithCallback(onSuccess: widget.onAuthSuccess),
                _RegisterFormWithCallback(onSuccess: widget.onAuthSuccess),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================
   LOGIN FORM WITH CALLBACK
============================ */

class _LoginFormWithCallback extends StatefulWidget {
  final void Function(bool isNewUser) onSuccess;

  const _LoginFormWithCallback({required this.onSuccess});

  @override
  State<_LoginFormWithCallback> createState() => _LoginFormWithCallbackState();
}

class _LoginFormWithCallbackState extends State<_LoginFormWithCallback> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameCtrl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Nom d\'utilisateur ou email',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Veuillez entrer votre nom d\'utilisateur';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordCtrl,
              enabled: !_busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Veuillez entrer votre mot de passe';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _handleLogin,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Se connecter',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final isNewUser = await AuthService.instance.login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close AuthPage
      widget.onSuccess(isNewUser);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/* ============================
   REGISTER FORM WITH CALLBACK
============================ */

class _RegisterFormWithCallback extends StatefulWidget {
  final void Function(bool isNewUser) onSuccess;

  const _RegisterFormWithCallback({required this.onSuccess});

  @override
  State<_RegisterFormWithCallback> createState() =>
      _RegisterFormWithCallbackState();
}

class _RegisterFormWithCallbackState extends State<_RegisterFormWithCallback> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;
  bool _busy = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameCtrl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Nom d\'utilisateur',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Veuillez entrer un nom d\'utilisateur';
                }
                if (value.trim().length < 3) {
                  return 'Au moins 3 caractères';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Veuillez entrer votre email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                    .hasMatch(value)) {
                  return 'Email invalide';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordCtrl,
              enabled: !_busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Veuillez entrer un mot de passe';
                }
                if (value.length < 8) {
                  return 'Au moins 8 caractères';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordCtrl,
              enabled: !_busy,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value != _passwordCtrl.text) {
                  return 'Les mots de passe ne correspondent pas';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acceptTerms,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _acceptTerms = value ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GestureDetector(
                      onTap: _busy
                          ? null
                          : () => setState(() => _acceptTerms = !_acceptTerms),
                      child: Text(
                        'J\'accepte les conditions d\'utilisation',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_busy || !_acceptTerms) ? null : _handleRegister,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'S\'inscrire',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceptez les conditions d\'utilisation'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final isNewUser = await AuthService.instance.register(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text.trim(),
        _emailCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close AuthPage
      widget.onSuccess(isNewUser); // Always true for register
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/* ============================
   GOOGLE SIGN-IN WITH CALLBACK
============================ */

class _GoogleSignInButtonWithCallback extends StatefulWidget {
  final void Function(bool isNewUser) onSuccess;

  const _GoogleSignInButtonWithCallback({required this.onSuccess});

  @override
  State<_GoogleSignInButtonWithCallback> createState() =>
      _GoogleSignInButtonWithCallbackState();
}

class _GoogleSignInButtonWithCallbackState
    extends State<_GoogleSignInButtonWithCallback> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OU',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _handleGoogleSignIn,
          icon: _busy
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Image.network(
                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                  height: 24,
                  width: 24,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.g_mobiledata),
                ),
          label: Text(
            _busy ? 'Connexion...' : 'Continuer avec Google',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: Colors.grey[300]!),
          ),
        ),
      ],
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _busy = true);

    try {
      final isNewUser = await AuthService.instance.signInWithGoogle();

      if (!mounted) return;
      Navigator.pop(context); // Close AuthPage
      widget.onSuccess(isNewUser);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
