// lib/features/auth/terms_page.dart

import 'package:flutter/material.dart';

/* ============================
   TERMS OF SERVICE (CGU)
   GDPR-compliant French terms for CityScape app
============================ */

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conditions Générales d\'Utilisation'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conditions Générales d\'Utilisation',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dernière mise à jour : ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            _buildSection(
              context,
              '1. Présentation du service',
              '''CityScape est une application mobile gratuite de jeux d'escape games urbains géolocalisés. L'application permet aux utilisateurs de :
- Découvrir et jouer à des escape games dans leur ville
- Créer et partager leurs propres escape games
- Participer à des classements et laisser des commentaires

L'éditeur de l'application est accessible via l'application mobile.''',
            ),

            _buildSection(
              context,
              '2. Acceptation des conditions',
              '''En créant un compte et en utilisant CityScape, vous acceptez sans réserve les présentes Conditions Générales d'Utilisation (CGU) et notre Politique de Confidentialité.

Si vous n'acceptez pas ces conditions, veuillez ne pas utiliser l'application.''',
            ),

            _buildSection(
              context,
              '3. Création de compte',
              '''Pour utiliser certaines fonctionnalités de CityScape, vous devez créer un compte en fournissant :
- Un nom d'utilisateur unique
- Une adresse email valide
- Un mot de passe sécurisé (minimum 8 caractères)

Vous êtes responsable de la confidentialité de vos identifiants de connexion. En cas d'utilisation non autorisée de votre compte, vous devez immédiatement nous en informer.''',
            ),

            _buildSection(
              context,
              '4. Protection des données personnelles (RGPD)',
              '''Conformément au Règlement Général sur la Protection des Données (RGPD) et à la loi Informatique et Libertés, vous disposez des droits suivants concernant vos données personnelles :

• Droit d'accès : vous pouvez demander une copie de vos données
• Droit de rectification : vous pouvez corriger vos informations
• Droit à l'effacement : vous pouvez demander la suppression de vos données
• Droit à la portabilité : vous pouvez récupérer vos données
• Droit d'opposition : vous pouvez vous opposer au traitement de vos données

Données collectées :
- Nom d'utilisateur et email (obligatoires pour l'inscription)
- Données de localisation (uniquement pendant le jeu, avec votre consentement)
- Commentaires et évaluations que vous publiez
- Statistiques de jeu (temps de complétion, escapes joués)

Conservation des données :
Vos données sont conservées tant que votre compte est actif. En cas de suppression de compte, vos données personnelles sont effacées sous 30 jours, à l'exception des données nécessaires pour nos obligations légales.

Pour exercer vos droits, contactez-nous à : [votre email de contact]

Responsable du traitement : [Votre nom/société]''',
            ),

            _buildSection(
              context,
              '5. Utilisation du service',
              '''Vous vous engagez à :
- Ne pas créer de contenu offensant, diffamatoire ou illégal
- Respecter les droits d'auteur et la propriété intellectuelle
- Ne pas perturber le fonctionnement de l'application
- Ne pas créer d'escape games dangereux ou sur propriété privée sans autorisation
- Respecter les autres utilisateurs et la communauté

CityScape se réserve le droit de :
- Modérer et supprimer tout contenu inapproprié
- Suspendre ou supprimer les comptes en cas de non-respect des CGU
- Modifier ou interrompre le service à tout moment''',
            ),

            _buildSection(
              context,
              '6. Contenu créé par les utilisateurs',
              '''En publiant un escape game ou un commentaire sur CityScape, vous :
- Restez propriétaire de votre contenu
- Accordez à CityScape une licence mondiale, non exclusive et gratuite pour afficher et distribuer votre contenu via l'application
- Garantissez que votre contenu ne viole aucun droit de propriété intellectuelle
- Acceptez que votre contenu soit modéré par notre équipe

Nous nous réservons le droit de refuser ou supprimer tout contenu qui viole ces conditions.''',
            ),

            _buildSection(
              context,
              '7. Données de localisation',
              '''CityScape utilise la géolocalisation uniquement pour :
- Afficher les escape games à proximité de votre position
- Vérifier votre progression pendant un jeu

Vous pouvez désactiver la géolocalisation à tout moment dans les paramètres de votre appareil, mais certaines fonctionnalités de jeu ne seront plus disponibles.

Vos données de localisation ne sont jamais partagées avec des tiers sans votre consentement explicite.''',
            ),

            _buildSection(
              context,
              '8. Propriété intellectuelle',
              '''L'application CityScape, son code, son design et sa marque sont protégés par le droit d'auteur et appartiennent à leurs propriétaires respectifs.

Vous n'êtes pas autorisé à :
- Copier, modifier ou distribuer l'application
- Utiliser la marque CityScape sans autorisation
- Extraire ou copier le contenu de la base de données''',
            ),

            _buildSection(
              context,
              '9. Limitation de responsabilité',
              '''CityScape est fourni "en l'état" sans garantie d'aucune sorte. Nous ne pouvons être tenus responsables de :
- Dommages directs ou indirects liés à l'utilisation de l'application
- Perte de données ou interruption de service
- Contenu créé par d'autres utilisateurs
- Accidents survenus pendant un jeu d'escape game

Les escape games se déroulent dans des lieux publics. Vous êtes responsable de votre sécurité et devez respecter le code de la route et les propriétés privées.''',
            ),

            _buildSection(
              context,
              '10. Cookies et technologies similaires',
              '''CityScape peut utiliser des cookies et technologies similaires pour :
- Maintenir votre session de connexion
- Mémoriser vos préférences
- Analyser l'utilisation de l'application (anonymisé)

Vous pouvez gérer les cookies dans les paramètres de votre appareil.''',
            ),

            _buildSection(
              context,
              '11. Modifications des CGU',
              '''Nous nous réservons le droit de modifier ces CGU à tout moment. En cas de modification substantielle, vous serez informé par email ou via une notification dans l'application.

L'utilisation continue de CityScape après modification des CGU vaut acceptation des nouvelles conditions.''',
            ),

            _buildSection(
              context,
              '12. Résiliation',
              '''Vous pouvez supprimer votre compte à tout moment depuis les paramètres de l'application.

Nous pouvons suspendre ou résilier votre compte en cas de violation des présentes CGU, sans préavis ni remboursement.''',
            ),

            _buildSection(
              context,
              '13. Loi applicable et juridiction',
              '''Les présentes CGU sont soumises au droit français.

En cas de litige, et à défaut de résolution amiable, les tribunaux français seront seuls compétents.''',
            ),

            _buildSection(
              context,
              '14. Contact',
              '''Pour toute question concernant ces CGU ou vos données personnelles, vous pouvez nous contacter à :

Email : [votre email de contact]

Vous pouvez également contacter la CNIL (Commission Nationale de l'Informatique et des Libertés) si vous estimez que vos droits ne sont pas respectés :
https://www.cnil.fr/''',
            ),

            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'En créant un compte CityScape, vous acceptez ces conditions générales d\'utilisation et notre politique de confidentialité.',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
