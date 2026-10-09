# -*- coding: utf-8 -*-
"""Suppression de compte : anonymisation, trace de la demande, commande.

Ce qui est verifie ici tient autant du produit que de la technique : ce qui
doit disparaitre, et surtout ce qui doit survivre. Une suppression seche
ferait cascader la base et emporterait les notes laissees aux autres joueurs
ainsi que les pieces des transactions.
"""

from io import StringIO

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from engagement.anonymisation import (
    PREFIXE_ANONYME, anonymiser_compte, est_deja_anonymise,
)
from engagement.models import (
    AccountDeletionRequest, EmailVerificationToken, PasswordResetToken,
    PlaySession, Rating, UserProfile,
)
from games.models import EscapeGame, GameStep

User = get_user_model()


def _escape(titre, owner=None, status="published", **kw):
    return EscapeGame.objects.create(
        title=titre, city="Paris", latitude=48.85, longitude=2.35,
        status=status, owner=owner, **kw
    )


class CompteGarniTestCase(TestCase):
    """Un compte avec de tout : c'est la seule facon de prouver que
    l'anonymisation trie correctement."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="marie", email="marie@example.com", password="pw",
            first_name="Marie", last_name="Dupont",
        )
        self.jeton = Token.objects.create(user=self.user)
        UserProfile.objects.create(user=self.user, email_verified=True)
        PasswordResetToken.objects.create(user=self.user, code="123456")
        EmailVerificationToken.objects.create(user=self.user, code="654321")

        # Escapes qu'elle a creees, dont une publiee et une brouillon.
        self.escape_publiee = _escape("Son escape publiee", owner=self.user)
        self.escape_brouillon = _escape(
            "Son brouillon", owner=self.user, status="draft",
        )

        # Une escape d'un tiers, qu'elle a jouee et notee.
        self.autre = User.objects.create_user(username="autre", password="pw")
        self.escape_tierce = _escape("Escape d'un tiers", owner=self.autre)
        GameStep.objects.create(
            escape=self.escape_tierce, order=1, title="Etape", text="?",
            answer_type="text", answer_text="reponse",
        )
        self.note = Rating.objects.create(
            user=self.user, escape=self.escape_tierce, stars=4,
            comment="Super parcours, je me suis bien amusee !",
        )
        PlaySession.objects.create(
            user=self.user, escape=self.escape_tierce,
            answers={"1": "ma reponse tapee a la main"},
        )

        # Elle figure sur la liste blanche d'une escape privee.
        self.escape_privee = _escape("Escape privee", owner=self.autre, is_private=True)
        self.escape_privee.allowed_users.add(self.user)


class AnonymisationTests(CompteGarniTestCase):
    def test_les_donnees_personnelles_disparaissent(self):
        anonymiser_compte(self.user)
        self.user.refresh_from_db()

        self.assertTrue(self.user.username.startswith(PREFIXE_ANONYME))
        self.assertNotIn("marie", self.user.username.lower())
        self.assertEqual(self.user.email, "")
        self.assertEqual(self.user.first_name, "")
        self.assertEqual(self.user.last_name, "")
        self.assertFalse(self.user.is_active)
        self.assertFalse(self.user.has_usable_password())

    def test_tout_moyen_de_connexion_est_revoque(self):
        anonymiser_compte(self.user)
        self.assertFalse(Token.objects.filter(user=self.user).exists())
        self.assertFalse(PasswordResetToken.objects.filter(user=self.user).exists())
        self.assertFalse(EmailVerificationToken.objects.filter(user=self.user).exists())

        profil = UserProfile.objects.get(user=self.user)
        self.assertFalse(profil.email_verified)
        self.assertIsNone(profil.token_last_used)

    def test_un_jeton_revoque_ne_donne_plus_acces(self):
        """Verification de bout en bout : la revocation est effective."""
        cle = self.jeton.key
        anonymiser_compte(self.user)
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Token {cle}")
        self.assertEqual(client.get("/api/auth/me").status_code, 401)

    def test_l_historique_de_jeu_est_supprime(self):
        """Les reponses tapees sont du texte libre, et l'historique est un
        releve de comportement : rien a conserver pour autrui."""
        anonymiser_compte(self.user)
        self.assertFalse(PlaySession.objects.filter(user=self.user).exists())

    def test_les_notes_survivent_mais_perdent_leur_commentaire(self):
        anonymiser_compte(self.user)
        self.note.refresh_from_db()
        self.assertEqual(self.note.stars, 4, "l'etoile a une valeur pour les autres joueurs")
        self.assertEqual(self.note.comment, "", "le texte libre peut identifier la personne")

    def test_les_escapes_creees_sont_conservees_y_compris_publiees(self):
        anonymiser_compte(self.user)
        self.escape_publiee.refresh_from_db()
        self.escape_brouillon.refresh_from_db()
        self.assertEqual(self.escape_publiee.status, "published")
        self.assertTrue(EscapeGame.objects.filter(id=self.escape_brouillon.id).exists())
        # L'escape reste rattachee au compte, desormais anonyme : les joueurs
        # qui l'ont debloquee ne perdent rien.
        self.assertEqual(self.escape_publiee.owner_id, self.user.id)

    def test_l_acces_aux_escapes_privees_est_retire(self):
        """Figurer sur une liste blanche est un lien nominatif."""
        anonymiser_compte(self.user)
        self.assertFalse(self.escape_privee.allowed_users.filter(id=self.user.id).exists())

    def test_les_autres_comptes_ne_sont_pas_touches(self):
        anonymiser_compte(self.user)
        self.autre.refresh_from_db()
        self.assertEqual(self.autre.username, "autre")
        self.assertTrue(self.autre.is_active)

    def test_la_simulation_n_ecrit_rien(self):
        rapport = anonymiser_compte(self.user, simulation=True)
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "marie")
        self.assertEqual(self.user.email, "marie@example.com")
        self.assertTrue(PlaySession.objects.filter(user=self.user).exists())
        self.assertTrue(Token.objects.filter(user=self.user).exists())
        # Mais le rapport compte bien ce qui serait fait.
        self.assertEqual(rapport["sessions_supprimees"], 1)
        self.assertEqual(rapport["notes_conservees"], 1)
        self.assertEqual(rapport["commentaires_effaces"], 1)
        self.assertEqual(rapport["escapes_publiees_conservees"], 1)

    def test_rejouer_l_anonymisation_est_sans_effet(self):
        anonymiser_compte(self.user)
        self.user.refresh_from_db()
        nom = self.user.username

        anonymiser_compte(self.user)  # ne doit pas lever
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, nom)
        self.assertTrue(est_deja_anonymise(self.user))

    def test_un_compte_privilegie_perd_ses_privileges(self):
        self.user.is_staff = True
        self.user.is_superuser = True
        self.user.save()
        anonymiser_compte(self.user)
        self.user.refresh_from_db()
        self.assertFalse(self.user.is_staff)
        self.assertFalse(self.user.is_superuser)


@override_settings(RATELIMIT_ENABLE=False)
class TraceDeLaDemandeTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="paul", email="paul@example.com", password="pw",
        )
        self.client = APIClient()

    def _demander(self, email, motif=""):
        return self.client.post(
            "/api/auth/delete-account-request",
            {"email": email, "reason": motif}, format="json",
        )

    def test_une_demande_laisse_une_trace(self):
        r = self._demander("paul@example.com", "je n'utilise plus l'app")
        self.assertEqual(r.status_code, 200)

        demande = AccountDeletionRequest.objects.get()
        self.assertEqual(demande.user, self.user)
        self.assertEqual(demande.statut, AccountDeletionRequest.STATUT_EN_ATTENTE)
        self.assertEqual(demande.username_au_moment_de_la_demande, "paul")
        self.assertEqual(demande.motif, "je n'utilise plus l'app")

    def test_l_echeance_est_a_trente_jours(self):
        self._demander("paul@example.com")
        demande = AccountDeletionRequest.objects.get()
        ecart = demande.echeance - demande.demandee_le
        self.assertEqual(ecart.days, 30)
        self.assertFalse(demande.en_retard)

    def test_rejouer_la_demande_ne_repousse_pas_l_echeance(self):
        """Sinon un tiers pourrait, en rejouant l'appel, reculer
        indefiniment la date a laquelle on doit avoir traite."""
        self._demander("paul@example.com")
        demande = AccountDeletionRequest.objects.get()
        premiere_echeance = demande.echeance

        self._demander("paul@example.com")
        self.assertEqual(AccountDeletionRequest.objects.count(), 1)
        demande.refresh_from_db()
        self.assertEqual(demande.echeance, premiere_echeance)

    def test_une_adresse_inconnue_ne_cree_aucune_trace(self):
        r = self._demander("inconnu@example.com")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(AccountDeletionRequest.objects.count(), 0)

    def test_la_reponse_ne_revele_pas_l_existence_du_compte(self):
        connu = self._demander("paul@example.com")
        inconnu = self._demander("inconnu@example.com")
        self.assertEqual(connu.json(), inconnu.json())

    def test_cloturer_efface_l_adresse_et_le_motif(self):
        """Garder l'adresse de quelqu'un dont on vient d'anonymiser le compte
        reviendrait a conserver la donnee qu'il a demande d'effacer."""
        self._demander("paul@example.com", "un motif personnel")
        demande = AccountDeletionRequest.objects.get()
        demande.marquer_traitee(detail="rapport d'anonymisation")

        demande.refresh_from_db()
        self.assertEqual(demande.statut, AccountDeletionRequest.STATUT_TRAITEE)
        self.assertIsNotNone(demande.traitee_le)
        self.assertEqual(demande.email_demande, "")
        self.assertEqual(demande.motif, "")
        self.assertEqual(demande.detail_traitement, "rapport d'anonymisation")
        # Le pseudo reste : c'est la trace lisible du traitement.
        self.assertEqual(demande.username_au_moment_de_la_demande, "paul")

    def test_une_demande_en_retard_est_signalee(self):
        self._demander("paul@example.com")
        demande = AccountDeletionRequest.objects.get()
        AccountDeletionRequest.objects.filter(id=demande.id).update(
            demandee_le=timezone.now() - timezone.timedelta(days=31),
        )
        demande.refresh_from_db()
        self.assertTrue(demande.en_retard)


class CommandeAnonymiserCompteTests(CompteGarniTestCase):
    def _lancer(self, *args):
        sortie = StringIO()
        call_command("anonymiser_compte", *args, stdout=sortie, stderr=sortie)
        return sortie.getvalue()

    def test_sans_confirmer_la_commande_simule(self):
        """Garde-fou principal : l'operation est irreversible."""
        sortie = self._lancer("--username", "marie")
        self.assertIn("SIMULATION", sortie)
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "marie")
        self.assertTrue(PlaySession.objects.filter(user=self.user).exists())

    def test_avec_confirmer_la_commande_anonymise(self):
        sortie = self._lancer("--username", "marie", "--confirmer")
        self.assertIn("Anonymisation effectuee", sortie)
        self.user.refresh_from_db()
        self.assertTrue(est_deja_anonymise(self.user))

    def test_la_commande_cloture_la_demande_en_attente(self):
        demande = AccountDeletionRequest.objects.create(
            user=self.user, email_demande="marie@example.com",
            username_au_moment_de_la_demande="marie",
        )
        self._lancer("--id", str(self.user.id), "--confirmer")

        demande.refresh_from_db()
        self.assertEqual(demande.statut, AccountDeletionRequest.STATUT_TRAITEE)
        self.assertIn("sessions de jeu supprimees", demande.detail_traitement)

    def test_la_commande_signale_l_absence_de_demande(self):
        sortie = self._lancer("--username", "marie", "--confirmer")
        self.assertIn("Aucune demande en attente", sortie)

    def test_on_peut_cibler_par_email(self):
        self._lancer("--email", "MARIE@example.com", "--confirmer")
        self.user.refresh_from_db()
        self.assertTrue(est_deja_anonymise(self.user))

    def test_un_compte_introuvable_leve_une_erreur(self):
        with self.assertRaises(CommandError):
            self._lancer("--username", "personne", "--confirmer")

    def test_une_adresse_ambigue_est_refusee(self):
        """Plutot refuser que d'anonymiser un compte au hasard."""
        User.objects.create_user(
            username="homonyme", email="marie@example.com", password="pw",
        )
        with self.assertRaises(CommandError) as ctx:
            self._lancer("--email", "marie@example.com", "--confirmer")
        self.assertIn("--id", str(ctx.exception))
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "marie", "rien ne doit avoir ete touche")


class PagesLegalesTests(TestCase):
    """Les pages servies a l'utilisateur, et ce qu'elles promettent.

    Ces tests existent a cause d'un defaut constate le 2026-10-09 : les
    deux pages etaient lues depuis `static_html/`, ou le depot ne les
    contenait pas - les copies versionnees etaient a la racine et n'etaient
    donc jamais servies, tandis que les fichiers reellement servis sur le
    serveur n'etaient suivis par aucun versionnement. Un simple appel les
    aurait mis en evidence.
    """

    def test_la_politique_de_confidentialite_est_servie(self):
        r = self.client.get("/privacy-policy")
        self.assertEqual(r.status_code, 200)
        self.assertIn(b"Conservation des", r.content)

    def test_la_page_de_suppression_est_servie(self):
        r = self.client.get("/delete-account")
        self.assertEqual(r.status_code, 200)
        self.assertIn(b"Supprimer mon compte", r.content)

    def test_aucune_page_ne_promet_un_effacement_total(self):
        """Garde-fou contre une regression du texte.

        L'anonymisation conserve volontairement les etoiles des notes et les
        escapes publiees. Promettre que « toutes vos donnees » seront
        supprimees serait donc inexact, et c'est un engagement envers
        l'utilisateur, pas une formule de style.
        """
        formules_interdites = [
            "toutes vos données seront supprimés",
            "toutes vos données seront supprimées",
            "toutes mes données seront définitivement supprimées",
        ]
        for chemin in ("/privacy-policy", "/delete-account"):
            contenu = self.client.get(chemin).content.decode("utf-8")
            for formule in formules_interdites:
                self.assertNotIn(
                    formule, contenu,
                    f"{chemin} promet un effacement total, que le mecanisme ne fait pas",
                )

    def test_la_page_dit_la_verite_sur_les_favoris(self):
        """Les favoris vivent dans les preferences locales du telephone
        (cle `fav_ids`), jamais sur le serveur. La page annoncait leur
        suppression, ce qui etait faux dans le sens rassurant : une
        suppression de compte ne peut pas effacer ce qui est sur
        l'appareil."""
        contenu = self.client.get("/delete-account").content.decode("utf-8")
        self.assertIn("favoris", contenu)
        self.assertIn("uniquement sur votre téléphone", contenu)
        self.assertNotIn("La suppression de vos favoris", contenu)

    def test_les_pages_annoncent_ce_qui_est_conserve(self):
        """Temoin positif : sans lui, le test precedent passerait aussi bien
        sur une page vide."""
        for chemin in ("/privacy-policy", "/delete-account"):
            contenu = self.client.get(chemin).content.decode("utf-8")
            self.assertIn("sans mention de leur", contenu, chemin)
            self.assertIn("30 jours", contenu, chemin)
