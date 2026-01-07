// lib/features/auth/password_reset_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Import core constants
import '../../core/constants.dart';

/* ============================
   PASSWORD RESET FLOW
   Step 1: Enter email → sends 6-digit code
   Step 2: Enter code + new password → resets password
============================ */

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Step 1 data
  final _emailCtrl = TextEditingController();

  // Step 2 data
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mot de passe oublié'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Email'),
                Expanded(child: Divider(color: _currentStep >= 1 ? Theme.of(context).colorScheme.primary : Colors.grey[300])),
                _buildStepIndicator(1, 'Code'),
              ],
            ),
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1EmailInput(
                  emailCtrl: _emailCtrl,
                  onNext: () => _goToStep(1),
                ),
                _Step2CodeAndPassword(
                  emailCtrl: _emailCtrl,
                  codeCtrl: _codeCtrl,
                  newPasswordCtrl: _newPasswordCtrl,
                  confirmPasswordCtrl: _confirmPasswordCtrl,
                  onSuccess: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey[300],
            shape: BoxShape.circle,
            border: isCurrent ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

/* ============================
   STEP 1: EMAIL INPUT
============================ */

class _Step1EmailInput extends StatefulWidget {
  final TextEditingController emailCtrl;
  final VoidCallback onNext;

  const _Step1EmailInput({
    required this.emailCtrl,
    required this.onNext,
  });

  @override
  State<_Step1EmailInput> createState() => _Step1EmailInputState();
}

class _Step1EmailInputState extends State<_Step1EmailInput> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.email_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),

            Text(
              'Réinitialisation de mot de passe',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              'Entrez votre adresse email. Vous recevrez un code à 6 chiffres pour réinitialiser votre mot de passe.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            TextFormField(
              controller: widget.emailCtrl,
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
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return 'Email invalide';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _busy ? null : _sendCode,
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
                      'Envoyer le code',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api$kAuthPrefix/auth/password-reset/request'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': widget.emailCtrl.text.trim()}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code envoyé par email'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onNext();
      } else {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(error['error'] ?? 'Erreur lors de l\'envoi du code');
      }
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
   STEP 2: CODE & NEW PASSWORD
============================ */

class _Step2CodeAndPassword extends StatefulWidget {
  final TextEditingController emailCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController newPasswordCtrl;
  final TextEditingController confirmPasswordCtrl;
  final VoidCallback onSuccess;

  const _Step2CodeAndPassword({
    required this.emailCtrl,
    required this.codeCtrl,
    required this.newPasswordCtrl,
    required this.confirmPasswordCtrl,
    required this.onSuccess,
  });

  @override
  State<_Step2CodeAndPassword> createState() => _Step2CodeAndPasswordState();
}

class _Step2CodeAndPasswordState extends State<_Step2CodeAndPassword> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.lock_reset,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),

            Text(
              'Code de vérification',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              'Entrez le code à 6 chiffres reçu par email et votre nouveau mot de passe.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Code input
            TextFormField(
              controller: widget.codeCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                labelText: 'Code de vérification',
                hintText: '000000',
                prefixIcon: const Icon(Icons.pin_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Entrez le code reçu';
                }
                if (value.length != 6) {
                  return 'Le code doit contenir 6 chiffres';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // New password
            TextFormField(
              controller: widget.newPasswordCtrl,
              enabled: !_busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Entrez un nouveau mot de passe';
                }
                if (value.length < 8) {
                  return 'Minimum 8 caractères';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Confirm password
            TextFormField(
              controller: widget.confirmPasswordCtrl,
              enabled: !_busy,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Confirmez le mot de passe';
                }
                if (value != widget.newPasswordCtrl.text) {
                  return 'Les mots de passe ne correspondent pas';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            FilledButton(
              onPressed: _busy ? null : _resetPassword,
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
                      'Réinitialiser le mot de passe',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api$kAuthPrefix/auth/password-reset/confirm'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': widget.emailCtrl.text.trim(),
          'code': widget.codeCtrl.text.trim(),
          'new_password': widget.newPasswordCtrl.text.trim(),
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mot de passe réinitialisé avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
      } else {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(error['error'] ?? 'Erreur lors de la réinitialisation');
      }
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
